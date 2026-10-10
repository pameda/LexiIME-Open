#include "lexi.h"
#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <filesystem>
#include <iomanip>
#include <locale>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace {
struct Entry { std::string text, syllables, code, initials, wubi, en, ja, es; int weight; };
struct Candidate { std::string text, gloss, kind; double score; int selections=0; };
struct Phrase { std::string trigger, text; };
using History = std::map<std::string,int>;
struct HistoryStamp {
    // State: missing=0, regular=1, inaccessible/nonregular=2.
    int state=0;
    unsigned long long device=0, identity=0, bytes=0, modified=0, changed=0;
    long modifiedNS=0, changedNS=0;
    bool operator==(const HistoryStamp& b) const {
        return state==b.state && device==b.device && identity==b.identity &&
            bytes==b.bytes && modified==b.modified && changed==b.changed &&
            modifiedNS==b.modifiedNS && changedNS==b.changedNS;
    }
};
struct Engine {
    std::vector<Entry> entries;
    std::vector<Phrase> phrases;
    std::map<std::string,std::string> layout;
    std::vector<Candidate> candidates;
    int fuzzy=0;
    bool tools=true;
    bool historyEnabled=false, historyStampKnown=false, historyValid=true, queryValid=false;
    std::filesystem::path historyPath;
    History history;
    HistoryStamp historyStamp;
    std::string queryCode, queryMode;
    std::string result="[]", error;
};
std::vector<std::string> split(const std::string& s, char sep) {
    std::vector<std::string> out; size_t begin=0, end;
    while ((end=s.find(sep,begin))!=std::string::npos) { out.push_back(s.substr(begin,end-begin)); begin=end+1; }
    out.push_back(s.substr(begin)); return out;
}
bool asciiCode(const std::string& s) {
    return !s.empty() && s.size()<=64 && std::all_of(s.begin(),s.end(),[](unsigned char c){return c>='a' && c<='z';});
}
bool validUTF8(const std::string& s, bool strictControls=false) {
    for (size_t i=0;i<s.size();) {
        unsigned char c=s[i++]; unsigned int cp; size_t n;
        if(c<128) { if(c<32 || c==127) return false; continue; }
        if(c>=0xc2 && c<=0xdf) {cp=c&31;n=1;}
        else if(c>=0xe0 && c<=0xef) {cp=c&15;n=2;}
        else if(c>=0xf0 && c<=0xf4) {cp=c&7;n=3;}
        else return false;
        if(i+n>s.size())return false;
        for(size_t j=0;j<n;++j) {unsigned char d=s[i++];if((d&0xc0)!=0x80)return false;cp=(cp<<6)|(d&63);}
        if((n==1&&cp<128)||(n==2&&cp<2048)||(n==3&&cp<65536)||cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff))return false;
        if(strictControls && cp>=0x80 && cp<=0x9f)return false;
    } return true;
}
constexpr size_t historyMaxBytes=1024*1024, historyMaxEntries=2000;
constexpr int historyMaxCount=1000000;
bool historyWord(const std::string& text) {
    if(text.empty() || text.size()>128 || !validUTF8(text,true))return false;
    size_t points=0;
    for(unsigned char c:text)if((c&0xc0)!=0x80)++points;
    return points<=16;
}
bool historyCandidate(const Candidate& c) {
    return c.kind!="segments" && c.kind!="tool" && c.kind!="emoji" && historyWord(c.text);
}
HistoryStamp historyStamp(const std::filesystem::path& path) {
    HistoryStamp result;
#ifdef _WIN32
    HANDLE file=CreateFileW(path.c_str(),FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    if(file==INVALID_HANDLE_VALUE) {
        DWORD error=GetLastError();
        result.state=(error==ERROR_FILE_NOT_FOUND||error==ERROR_PATH_NOT_FOUND)?0:2;
        return result;
    }
    BY_HANDLE_FILE_INFORMATION info{};
    if(!GetFileInformationByHandle(file,&info) ||
       (info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))result.state=2;
    else {
        result.state=1;result.device=info.dwVolumeSerialNumber;
        result.identity=(static_cast<unsigned long long>(info.nFileIndexHigh)<<32)|info.nFileIndexLow;
        result.bytes=(static_cast<unsigned long long>(info.nFileSizeHigh)<<32)|info.nFileSizeLow;
        result.modified=(static_cast<unsigned long long>(info.ftLastWriteTime.dwHighDateTime)<<32)|info.ftLastWriteTime.dwLowDateTime;
        result.changed=(static_cast<unsigned long long>(info.ftCreationTime.dwHighDateTime)<<32)|info.ftCreationTime.dwLowDateTime;
    }
    CloseHandle(file);
#else
    struct stat info{};
    if(lstat(path.c_str(),&info)!=0){result.state=errno==ENOENT?0:2;return result;}
    result.state=S_ISREG(info.st_mode)?1:2;
    result.device=info.st_dev;result.identity=info.st_ino;result.bytes=info.st_size;
#ifdef __APPLE__
    result.modified=info.st_mtimespec.tv_sec;result.modifiedNS=info.st_mtimespec.tv_nsec;
    result.changed=info.st_ctimespec.tv_sec;result.changedNS=info.st_ctimespec.tv_nsec;
#else
    result.modified=info.st_mtim.tv_sec;result.modifiedNS=info.st_mtim.tv_nsec;
    result.changed=info.st_ctim.tv_sec;result.changedNS=info.st_ctim.tv_nsec;
#endif
#endif
    return result;
}
// Reads do not create files or locks. Native handles permit atomic replacement
// during Windows reads; bounded reads also reject a file that grows after stat.
bool readHistory(const std::filesystem::path& path,History& pending) {
    auto stamp=historyStamp(path);
    if(stamp.state==0)return true;
    if(stamp.state!=1 || stamp.bytes>historyMaxBytes)return false;
    std::string contents(historyMaxBytes+1,'\0');size_t bytes=0;bool ok=true;
#ifdef _WIN32
    HANDLE file=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    if(file==INVALID_HANDLE_VALUE)return false;
    BY_HANDLE_FILE_INFORMATION info{};
    ok=GetFileInformationByHandle(file,&info) &&
        !(info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT));
    while(ok && bytes<contents.size()) {
        DWORD got=0;
        ok=ReadFile(file,&contents[bytes],DWORD(contents.size()-bytes),&got,nullptr)!=0;
        if(!ok||got==0)break;
        bytes+=got;
    }
    CloseHandle(file);
#else
    int file=open(path.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK);
    if(file<0)return false;
    struct stat info{};ok=fstat(file,&info)==0 && S_ISREG(info.st_mode);
    while(ok && bytes<contents.size()) {
        ssize_t got=read(file,&contents[bytes],contents.size()-bytes);
        if(got<0 && errno==EINTR)continue;
        if(got<0){ok=false;break;}
        if(got==0)break;
        bytes+=size_t(got);
    }
    close(file);
#endif
    if(!ok || bytes>historyMaxBytes)return false;
    contents.resize(bytes);std::istringstream rows(contents);std::string line;
    while(std::getline(rows,line)) {
        if(!rows.eof() && !line.empty() && line.back()=='\r')line.pop_back();
        auto fields=split(line,'\t');
        if(fields.size()!=2 || !historyWord(fields[0]) || fields[1].empty() ||
           fields[1].size()>7 || pending.size()>=historyMaxEntries || pending.count(fields[0]))return false;
        int count=0;
        for(unsigned char c:fields[1]) {
            if(c<'0'||c>'9')return false;
            count=count*10+(c-'0');if(count>historyMaxCount)return false;
        }
        if(count<1)return false;
        pending.emplace(fields[0],count);
    }
    return true;
}
bool refreshHistory(Engine& e,bool force=false) {
    if(!e.historyEnabled)return true;
    auto before=historyStamp(e.historyPath);
    if(!force && e.historyStampKnown && before==e.historyStamp) {
        if(!e.historyValid)e.error="历史文件无效或无法读取；未修改原文件";
        return e.historyValid;
    }
    // Compare both sides of validation so a concurrent replacement cannot mark
    // older data as current. On contention retry next query instead of spinning.
    for(int attempt=0;attempt<2;++attempt) {
        History pending;bool ok=readHistory(e.historyPath,pending);
        auto after=historyStamp(e.historyPath);
        if(before==after) {
            e.historyStamp=after;e.historyStampKnown=true;e.historyValid=ok;
            if(ok)e.history=std::move(pending);else e.history.clear();
            if(!ok)e.error="历史文件无效或无法读取；未修改原文件";
            return ok;
        }
        before=after;
    }
    e.history.clear();e.historyStampKnown=false;
    // Contention is not corruption: configuration remains successful and a
    // later query retries. Recording always reloads under the exclusive lock.
    return true;
}
// POSIX record locks are per-process, so also serialize engines within this
// process. Never unlink this stable sidecar: data-file replacement changes inode.
std::mutex historyWriteMutex;
class HistoryLock {
    std::unique_lock<std::mutex> guard{historyWriteMutex};
#ifdef _WIN32
    HANDLE file=INVALID_HANDLE_VALUE;OVERLAPPED overlap{};
#else
    int file=-1;
#endif
    bool locked=false;
public:
    explicit HistoryLock(const std::filesystem::path& path) {
        auto sidecar=path;sidecar+=".lock";
#ifdef _WIN32
        file=CreateFileW(sidecar.c_str(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,
            nullptr,OPEN_ALWAYS,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
        if(file==INVALID_HANDLE_VALUE)return;
        BY_HANDLE_FILE_INFORMATION info{};
        if(!GetFileInformationByHandle(file,&info) ||
           (info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))return;
        locked=LockFileEx(file,LOCKFILE_EXCLUSIVE_LOCK,0,1,0,&overlap)!=0;
#else
        file=open(sidecar.c_str(),O_RDWR|O_CREAT|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK,0600);
        if(file<0)return;
        struct stat info{};if(fstat(file,&info)!=0 || !S_ISREG(info.st_mode))return;
        struct flock lock{};lock.l_type=F_WRLCK;lock.l_whence=SEEK_SET;
        int status;do{status=fcntl(file,F_SETLKW,&lock);}while(status<0 && errno==EINTR);
        locked=status==0;
#endif
    }
    bool good() const{return locked;}
    ~HistoryLock() {
#ifdef _WIN32
        if(locked)UnlockFileEx(file,0,1,0,&overlap);
        if(file!=INVALID_HANDLE_VALUE)CloseHandle(file);
#else
        if(file>=0)close(file);
#endif
    }
};
bool replaceHistory(const std::filesystem::path& path,const History& history) {
    std::string contents;
    for(const auto& row:history)contents+=row.first+'\t'+std::to_string(row.second)+'\n';
    if(contents.size()>historyMaxBytes)return false;
#ifdef _WIN32
    static std::atomic<unsigned long> sequence{0};
    std::filesystem::path temporary;HANDLE file=INVALID_HANDLE_VALUE;
    for(int attempt=0;attempt<32;++attempt) {
        temporary=path;temporary+=".tmp."+std::to_string(GetCurrentProcessId())+"."+std::to_string(++sequence);
        file=CreateFileW(temporary.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(file!=INVALID_HANDLE_VALUE)break;
        if(GetLastError()!=ERROR_FILE_EXISTS && GetLastError()!=ERROR_ALREADY_EXISTS)return false;
    }
    if(file==INVALID_HANDLE_VALUE)return false;
    bool ok=true;size_t bytes=0;
    while(bytes<contents.size()) {
        DWORD wrote=0;
        if(!WriteFile(file,contents.data()+bytes,DWORD(contents.size()-bytes),&wrote,nullptr)||!wrote){ok=false;break;}
        bytes+=wrote;
    }
    if(ok)ok=FlushFileBuffers(file)!=0;
    if(!CloseHandle(file))ok=false;
    if(ok)ok=MoveFileExW(temporary.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)!=0;
    if(!ok)DeleteFileW(temporary.c_str());return ok;
#else
    std::string temporary=path.string()+".tmp.XXXXXX";
    std::vector<char> name(temporary.begin(),temporary.end());name.push_back('\0');
    int file=mkstemp(name.data());if(file<0)return false;
    fcntl(file,F_SETFD,FD_CLOEXEC);
    bool ok=true;size_t bytes=0;
    while(bytes<contents.size()) {
        ssize_t wrote=write(file,contents.data()+bytes,contents.size()-bytes);
        if(wrote<0 && errno==EINTR)continue;
        if(wrote<=0){ok=false;break;}bytes+=size_t(wrote);
    }
    if(ok)ok=fsync(file)==0;
    if(close(file)!=0)ok=false;
    if(ok)ok=rename(name.data(),path.c_str())==0;
    if(!ok){unlink(name.data());return false;}
    // Rename is the commit point. Directory sync is best effort on filesystems
    // that support it; a subsequent sync failure cannot undo a committed update.
    int directory=open(path.parent_path().c_str(),O_RDONLY|O_CLOEXEC|O_DIRECTORY);
    if(directory>=0){fsync(directory);close(directory);}return true;
#endif
}
std::string escape(const std::string& s) {
    std::string o="\""; for(unsigned char c:s) {
        if(c=='"'||c=='\\') {o+='\\';o+=char(c);} else if(c=='\n')o+="\\n";
        else if(c=='\t')o+="\\t"; else if(c>=32)o+=char(c);
    } return o+'"';
}
std::string gloss(const Entry& e,const std::string& lang) {
    if(lang=="en")return e.en;if(lang=="ja")return e.ja;if(lang=="es")return e.es;return "";
}
bool oneEdit(const std::string& a,const std::string& b) {
    if(a.size()>b.size()+1 || b.size()>a.size()+1)return false;
    if(a.size()==b.size()) {
        std::vector<size_t> d;for(size_t i=0;i<a.size();++i)if(a[i]!=b[i])d.push_back(i);
        return d.size()==1 || (d.size()==2 && d[1]==d[0]+1 && a[d[0]]==b[d[1]] && a[d[1]]==b[d[0]]);
    }
    const auto& shorter=a.size()<b.size()?a:b;const auto& longer=a.size()<b.size()?b:a;
    size_t i=0,j=0;while(i<shorter.size()&&j<longer.size()){if(shorter[i]==longer[j])++i;++j;}
    return i==shorter.size();
}
std::string keyFor(const Entry& e,const std::string& mode,const Engine& engine) {
    if(mode=="wubi")return e.wubi;
    if(mode=="double") {std::string k;for(auto& s:split(e.syllables,' ')) {auto it=engine.layout.find(s);if(it==engine.layout.end())return "";k+=it->second;}return k;}
    return e.code;
}
std::vector<std::string> fuzzySyllables(const std::string& syllable,int mask) {
    std::vector<std::string> forms{syllable};
    // Transform only the initial and the final of this syllable, never a
    // substring spanning adjacent syllables (e.g. san gan -> sang an).
    if((mask&1) && !syllable.empty() && (syllable[0]=='z'||syllable[0]=='c'||syllable[0]=='s')) {
        auto alternate=syllable;
        if(alternate.size()>1 && alternate[1]=='h')alternate.erase(1,1);
        else alternate.insert(1,"h");
        forms.push_back(alternate);
    }
    if((mask&2) && !syllable.empty() && (syllable[0]=='n'||syllable[0]=='l')) {
        auto alternate=syllable;alternate[0]=alternate[0]=='n'?'l':'n';forms.push_back(alternate);
    }
    if(mask&4) {
        const size_t originalCount=forms.size();
        for(size_t i=0;i<originalCount;++i) {
            for(const auto* final: {"an","en","in"}) {
                const std::string shortFinal=final,longFinal=shortFinal+"g";
                const auto& s=forms[i];
                if(s.size()>=longFinal.size() && s.compare(s.size()-longFinal.size(),longFinal.size(),longFinal)==0) {
                    forms.push_back(s.substr(0,s.size()-1));break;
                }
                if(s.size()>=shortFinal.size() && s.compare(s.size()-shortFinal.size(),shortFinal.size(),shortFinal)==0) {
                    forms.push_back(s+"g");break;
                }
            }
        }
    }
    return forms;
}
bool fuzzyMatch(const Entry& entry,const std::string& q,int mask,bool boundary) {
    auto syllables=split(entry.syllables,' ');
    if(boundary) {
        auto typed=split(q,'\'');if(typed.size()!=syllables.size())return false;
        for(size_t i=0;i<typed.size();++i) {
            auto forms=fuzzySyllables(syllables[i],mask);
            if(std::find(forms.begin(),forms.end(),typed[i])==forms.end())return false;
        }
        return true;
    }
    // Each DP step consumes exactly one dictionary syllable. Unseparated input
    // can have several interpretations; explicit apostrophes remove ambiguity.
    std::vector<bool> positions(q.size()+1);positions[0]=true;
    for(const auto& syllable:syllables) {
        std::vector<bool> next(q.size()+1);
        auto forms=fuzzySyllables(syllable,mask);
        for(size_t pos=0;pos<positions.size();++pos)if(positions[pos]) {
            for(const auto& form:forms)if(form.size()<=q.size()-pos && q.compare(pos,form.size(),form)==0)next[pos+form.size()]=true;
        }
        positions=std::move(next);
    }
    return positions.back();
}
class Arithmetic {
    const std::string& input;
    size_t pos=0;
    bool ok=true;
    static constexpr double limit=1e12;
    double bounded(double value) {
        if(!std::isfinite(value)||std::abs(value)>limit)ok=false;
        return value;
    }
    bool take(char c) {
        if(pos<input.size() && input[pos]==c){++pos;return true;}return false;
    }
    double primary(unsigned depth) {
        if(depth>32){ok=false;return 0;}
        if(take('+'))return primary(depth+1);
        if(take('-'))return bounded(-primary(depth+1));
        if(take('(')) {
            double value=expression(depth+1);if(!take(')'))ok=false;return value;
        }
        double value=0,scale=0.1;bool digits=false;
        while(pos<input.size() && input[pos]>='0' && input[pos]<='9') {
            digits=true;value=bounded(value*10+(input[pos++]-'0'));
        }
        if(take('.'))while(pos<input.size() && input[pos]>='0' && input[pos]<='9') {
            digits=true;value+=(input[pos++]-'0')*scale;scale*=0.1;
        }
        if(!digits)ok=false;
        return bounded(value);
    }
    double term(unsigned depth) {
        double value=primary(depth);
        while(ok && pos<input.size() && (input[pos]=='*'||input[pos]=='/')) {
            char op=input[pos++];double rhs=primary(depth);
            if(op=='/' && rhs==0){ok=false;return 0;}
            value=bounded(op=='*'?value*rhs:value/rhs);
        }
        return value;
    }
    double expression(unsigned depth) {
        double value=term(depth);
        while(ok && pos<input.size() && (input[pos]=='+'||input[pos]=='-')) {
            char op=input[pos++];double rhs=term(depth);value=bounded(op=='+'?value+rhs:value-rhs);
        }
        return value;
    }
public:
    explicit Arithmetic(const std::string& s):input(s){}
    bool evaluate(std::string& result) {
        double value=expression(0);
        if(!ok || pos!=input.size())return false;
        std::ostringstream out;out.imbue(std::locale::classic());
        out<<std::setprecision(15)<<(value==0?0:value);result=out.str();return true;
    }
};
void toolsFor(const std::string& q,std::vector<Candidate>& found) {
    auto add=[&](const std::string& text,const char* kind="tool"){
        found.push_back({text,"",kind,std::string(kind)=="emoji"?650.0:1300.0});
    };
    if(q=="vdate"||q=="vtime") {
        std::time_t now=std::time(nullptr);std::tm local{};
#ifdef _WIN32
        if(localtime_s(&local,&now)!=0)return;
#else
        if(!localtime_r(&now,&local))return;
#endif
        char value[32];if(std::strftime(value,sizeof(value),q=="vdate"?"%Y-%m-%d":"%H:%M:%S",&local))add(value);
    } else if(q=="vsymbol") {
        for(const auto* text:{"©","®","™","°","±","×","÷","→","✓"})add(text);
    } else if(q=="vemoji") {
        for(const auto* text:{"😀","😊","🎉","👍","🙏","❤️"})add(text);
    } else if(q.size()>1 && q[0]=='v') {
        std::string expression=q.substr(1),result;
        if(Arithmetic(expression).evaluate(result))add(result);
    }
    // Independently chosen, deliberately small Unicode associations.
    if(q=="kai'xin"||q=="kaixin") {add("😊","emoji");add("😄","emoji");}
    else if(q=="xie'xie"||q=="xiexie") {add("🙏","emoji");add("🌷","emoji");}
    else if(q=="zan")add("👍","emoji");
    else if(q=="qingzhu"||q=="qing'zhu")add("🎉","emoji");
}
}
extern "C" {
void* lexi_create(void){return new Engine;}
void lexi_destroy(void* p){delete static_cast<Engine*>(p);}
void lexi_set_fuzzy(void* p,int mask){if(p)static_cast<Engine*>(p)->fuzzy=mask&7;}
void lexi_set_tools(void* p,int enabled){if(p)static_cast<Engine*>(p)->tools=enabled!=0;}
int lexi_history(void* p,const char* path,int enabled) {
    if(!p)return -1;
    auto& e=*static_cast<Engine*>(p);e.error.clear();
    try {
        auto configured=e.historyPath;
        if(path) {
            std::string value=path;
            if(value.empty() || value.size()>4096 || !validUTF8(value,true)) {
                e.error="历史文件路径无效";return -1;
            }
            configured=std::filesystem::absolute(std::filesystem::u8path(value)).lexically_normal();
        }
        if(enabled && configured.empty()){e.error="历史文件路径为空";return -1;}
        if(configured==e.historyPath && (enabled!=0)==e.historyEnabled)return 0;
        e.historyPath=std::move(configured);e.historyEnabled=enabled!=0;
        e.history.clear();e.historyStampKnown=false;e.historyValid=true;
        return refreshHistory(e,true)?0:-1;
    } catch(const std::exception&) {e.error="历史文件路径无效";return -1;}
}
int lexi_record_selection(void* p,const char* code,const char* mode,const char* text) {
    if(!p)return -1;
    auto& e=*static_cast<Engine*>(p);e.error.clear();
    if(!e.historyEnabled)return 0;
    if(!code || !text || !e.queryValid){e.error="历史记录需要实际查询和候选选择";return -1;}
    std::string canonical=code;
    for(char& c:canonical)if(c>='A'&&c<='Z')c=char(c-'A'+'a');
    const std::string selected=text;
    if(canonical!=e.queryCode || std::string(mode?mode:"pinyin")!=e.queryMode || !historyWord(selected)) {
        e.error="历史记录的编码、方案或词语无效";return -1;
    }
    auto candidate=std::find_if(e.candidates.begin(),e.candidates.end(),[&](const Candidate& c){
        return c.text==selected && historyCandidate(c);
    });
    if(candidate==e.candidates.end()){e.error="只能记录当前显示的普通候选词";return -1;}
    HistoryLock lock(e.historyPath);
    if(!lock.good()){e.error="历史文件无法加锁";return -1;}
    History pending;
    if(!readHistory(e.historyPath,pending)) {
        e.history.clear();e.historyStampKnown=false;
        e.error="历史文件无效或无法读取；未修改原文件";return -1;
    }
    auto existing=pending.find(selected);
    if(existing!=pending.end())existing->second=std::min(historyMaxCount,existing->second+1);
    else {
        if(pending.size()>=historyMaxEntries) {
            // Map order deterministically breaks equal-count eviction ties.
            auto lowest=std::min_element(pending.begin(),pending.end(),[](const auto& a,const auto& b){return a.second<b.second;});
            pending.erase(lowest);
        }
        pending.emplace(selected,1);
    }
    if(!replaceHistory(e.historyPath,pending)){e.error="历史文件保存失败";return -1;}
    e.history=std::move(pending);e.historyStamp=historyStamp(e.historyPath);
    e.historyStampKnown=true;e.historyValid=true;return 1;
}
int lexi_clear_history(void* p) {
    if(!p)return -1;
    auto& e=*static_cast<Engine*>(p);e.error.clear();
    if(e.historyPath.empty())return 0;
    HistoryLock lock(e.historyPath);
    if(!lock.good() || !replaceHistory(e.historyPath,{})){e.error="历史文件清除失败";return -1;}
    e.history.clear();e.historyStamp=historyStamp(e.historyPath);e.historyStampKnown=true;e.historyValid=true;
    return 0;
}
const char* lexi_error(void* p){return static_cast<Engine*>(p)->error.c_str();}
int lexi_count(void* p){return int(static_cast<Engine*>(p)->entries.size());}
int lexi_candidate_count(void* p){return int(static_cast<Engine*>(p)->candidates.size());}
const char* lexi_candidate_field(void* p,int index,int field){
    auto& list=static_cast<Engine*>(p)->candidates;
    if(index<0||size_t(index)>=list.size())return "";
    auto& c=list[size_t(index)];return field==0?c.text.c_str():field==1?c.gloss.c_str():c.kind.c_str();
}
int lexi_load(void* p,const char* path) {
    auto& e=*static_cast<Engine*>(p);e.error.clear();
    std::ifstream in(std::filesystem::u8path(path),std::ios::binary|std::ios::ate);
    if(!in || in.tellg()>8*1024*1024){e.error="词库无法读取或超过 8 MB";return -1;}in.seekg(0);
    std::vector<Entry> pending;std::string line;size_t lineNo=0;
    while(std::getline(in,line)) {
        ++lineNo;if(!line.empty()&&line.back()=='\r')line.pop_back();
        if(line.empty()||line[0]=='#')continue;
        auto f=split(line,'\t');
        auto fail=[&](){e.error="词库第 "+std::to_string(lineNo)+" 行格式不正确";return -1;};
        if(f.size()!=8)return fail();
        for(auto& v:f)if(v.size()>512||!validUTF8(v))return fail();
        Entry row;row.text=f[0];row.syllables=f[1];row.wubi=f[2];row.en=f[3];row.ja=f[4];row.es=f[5];
        if(row.text.empty())return fail();
        for(auto& s:split(row.syllables,' ')){if(!asciiCode(s))return fail();row.code+=s;row.initials+=s[0];}
        if(row.code.size()>64 || (!row.wubi.empty()&&!asciiCode(row.wubi)))return fail();
        if(f[6].empty() || !std::all_of(f[6].begin(),f[6].end(),[](unsigned char c){return c>='0'&&c<='9';}))return fail();
        try{row.weight=std::stoi(f[6]);}catch(...){return fail();}
        if(row.weight<1||row.weight>100000)return fail();
        pending.push_back(std::move(row));if(pending.size()>50000)return fail();
    }
    if(pending.empty()){e.error="词库没有有效词条";return -1;}
    // Validate the entire file before changing the engine. Imports replace matching entries.
    std::map<std::string,Entry> merged;
    for(auto& r:e.entries)merged[r.text+"\t"+r.code]=r;
    for(auto& r:pending)merged[r.text+"\t"+r.code]=r;
    if(merged.size()>50000){e.error="词库合计不能超过 50000 条";return -1;}
    e.entries.clear();for(auto& r:merged)e.entries.push_back(std::move(r.second));return int(pending.size());
}
int lexi_load_layout(void* p,const char* path) {
    auto& e=*static_cast<Engine*>(p);e.error.clear();std::ifstream in(std::filesystem::u8path(path),std::ios::binary|std::ios::ate);
    if(!in||in.tellg()>65536){e.error="双拼方案无法读取或超过 64 KB";return -1;}in.seekg(0);
    std::map<std::string,std::string> pending;std::string line;
    while(std::getline(in,line)) {
        if(!line.empty()&&line.back()=='\r')line.pop_back();if(line.empty()||line[0]=='#')continue;
        auto f=split(line,'\t');if(f.size()!=2||!asciiCode(f[0])||!asciiCode(f[1])||f[1].size()!=2||pending.count(f[0])){e.error="双拼方案须为：拼音音节、Tab、两个小写字母，音节不能重复";return -1;}
        pending[f[0]]=f[1];
    }
    if(pending.empty()){e.error="双拼方案为空";return -1;}e.layout=std::move(pending);return int(e.layout.size());
}
int lexi_load_phrases(void* p,const char* path) {
    if(!p)return -1;
    auto& e=*static_cast<Engine*>(p);e.error.clear();
    if(!path){e.error="短语文件路径为空";return -1;}
    std::ifstream in(std::filesystem::u8path(path),std::ios::binary);
    if(!in){e.error="短语文件无法读取";return -1;}
    // Bound the actual read, even if the file grows after it is opened.
    constexpr size_t maxBytes=1024*1024;
    std::string contents(maxBytes+1,'\0');in.read(&contents[0],std::streamsize(contents.size()));
    const auto bytes=in.gcount();
    if(in.bad() || (!in.eof()&&in.fail()) || bytes>std::streamsize(maxBytes)){e.error="短语文件无法读取或超过 1 MiB";return -1;}
    contents.resize(size_t(bytes));std::istringstream rows(contents);
    std::vector<Phrase> pending;std::set<std::string> triggers;std::string line;size_t lineNo=0;
    while(std::getline(rows,line)) {
        ++lineNo;if(!rows.eof()&&!line.empty()&&line.back()=='\r')line.pop_back();
        auto fields=split(line,'\t');
        if(fields.size()!=2 || fields[0].size()>32 || !asciiCode(fields[0]) || fields[1].empty() ||
           fields[1].size()>512 || !validUTF8(fields[1],true) || pending.size()>=1000 || !triggers.insert(fields[0]).second) {
            e.error="短语第 "+std::to_string(lineNo)+" 行格式不正确、触发码重复或超过 1000 行";return -1;
        }
        pending.push_back({fields[0],fields[1]});
    }
    e.phrases=std::move(pending);return int(e.phrases.size());
}
const char* lexi_query(void* p,const char* input,const char* modeIn,const char* language,int correction) {
    auto& e=*static_cast<Engine*>(p);e.error.clear();e.candidates.clear();std::string q=input?input:"",mode=modeIn?modeIn:"pinyin",lang=language?language:"en";
    e.queryValid=false;e.queryCode.clear();e.queryMode.clear();
    refreshHistory(e);
    if(mode!="pinyin"&&mode!="initials"&&mode!="double"&&mode!="wubi"){e.error="未知输入方案";e.result="[]";return e.result.c_str();}
    if(q.size()>64){e.error="编码最多 64 个字符";e.result="[]";return e.result.c_str();}
    for(char& c:q)if(c>='A'&&c<='Z')c=char(c-'A'+'a');
    e.queryValid=true;e.queryCode=q;e.queryMode=mode;
    std::vector<Candidate> found;
    if(e.tools)toolsFor(q,found);
    // Arithmetic-like utility input cannot become a prefix/typo candidate when
    // parsing fails. All operators and literals must be consumed by Arithmetic.
    const bool arithmetic=(q.size()>1 && q[0]=='v' &&
        (q[1]=='+'||q[1]=='-'||q[1]=='('||q[1]=='.'||(q[1]>='0'&&q[1]<='9'))) ||
        q=="vnan"||q=="vinf"||q=="vinfinity";
    // Apostrophes force syllable boundaries in full-pinyin matching.
    const bool boundary=q.find('\'')!=std::string::npos;
    std::string flat=q;flat.erase(std::remove(flat.begin(),flat.end(),'\''),flat.end());
    for(const auto& phrase:e.phrases)if(phrase.trigger==q)found.push_back({phrase.text,"","phrase",1400});
    const bool dictionaryInput=asciiCode(flat)&&!arithmetic;
    if(dictionaryInput)for(auto& r:e.entries) {
        auto k=keyFor(r,mode,e);if(mode=="initials")k=r.initials;if(k.empty())continue;
        std::string explicitCode=r.syllables;std::replace(explicitCode.begin(),explicitCode.end(),' ','\'');
        const bool boundaryMatch=!boundary || (mode=="pinyin"&&explicitCode.compare(0,q.size(),q)==0);
        double score=0;std::string kind;
        if(boundaryMatch && k==flat){score=1000;kind="exact";}
        else if(mode=="pinyin"&&!boundary&&r.initials==flat){score=800;kind="initials";}
        else if(mode=="pinyin"&&e.fuzzy&&fuzzyMatch(r,q,e.fuzzy,boundary)){score=700;kind="fuzzy";}
        else if(boundaryMatch && k.compare(0,flat.size(),flat)==0){score=500-double(k.size()-flat.size());kind="prefix";}
        else if(mode=="pinyin"&&!boundary&&correction&&flat.size()>=4&&oneEdit(flat,k)){score=300;kind="correction";}
        if(score)found.push_back({r.text,gloss(r,lang),kind,score+std::log(double(r.weight))});
    }
    // Local dictionary segmentation, not a neural language model. No fabricated sentence translation.
    if(dictionaryInput&&!boundary&&(mode=="pinyin"||mode=="double")&&flat.size()>2) {
        struct Path{double score=-1e9;std::vector<const Entry*> words;};std::vector<Path> dp(flat.size()+1);dp[0].score=0;
        for(size_t i=0;i<flat.size();++i)if(dp[i].score>-1e8)for(auto& r:e.entries) {
            auto k=keyFor(r,mode,e);if(k.empty()||flat.compare(i,k.size(),k)!=0)continue;
            size_t end=i+k.size();if(end>flat.size())continue;
            double score=dp[i].score+std::log(double(r.weight))-12;
            if(score>dp[end].score){dp[end]=dp[i];dp[end].score=score;dp[end].words.push_back(&r);}
        }
        if(dp.back().words.size()>1){Candidate c{"","","segments",950};for(auto* r:dp.back().words){c.text+=r->text;auto g=gloss(*r,lang);if(!g.empty()){if(!c.gloss.empty())c.gloss+=" · ";c.gloss+=g;}}found.push_back(c);}
    }
    if(e.historyEnabled)for(auto& c:found) {
        auto row=e.history.find(c.text);
        if(row!=e.history.end() && historyCandidate(c))c.selections=row->second;
    }
    std::stable_sort(found.begin(),found.end(),[&](const auto& a,const auto& b){
        if(e.historyEnabled) {
            int aCount=a.selections,bCount=b.selections;
            int aTier=a.kind=="tool"?2:aCount>0?1:0,bTier=b.kind=="tool"?2:bCount>0?1:0;
            if(aTier!=bTier)return aTier>bTier;
            if(aCount!=bCount)return aCount>bCount;
        }
        return a.score>b.score;
    });
    e.result="[";std::set<std::string> seen;int count=0;
    for(auto& c:found){if(!seen.insert(c.text).second)continue;e.candidates.push_back(c);if(count++)e.result+=',';
        e.result+="{\"text\":"+escape(c.text)+",\"gloss\":"+escape(c.gloss)+",\"kind\":"+escape(c.kind)+"}";if(count==36)break;}
    e.result+=']';return e.result.c_str();
}
}
