#include "../core/lexi.h"
#include <cassert>
#include <chrono>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#ifndef _WIN32
#include <cerrno>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#endif
struct TempWorkspace {
    std::filesystem::path path;
    TempWorkspace() {
        auto base=std::filesystem::temp_directory_path()/
            ("lexi-core-tests-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
        for(int i=0;i<100;++i) {
            path=base;path+=std::to_string(i);
            if(std::filesystem::create_directory(path))return;
        }
        std::abort();
    }
    ~TempWorkspace(){std::error_code ignored;std::filesystem::remove_all(path,ignored);}
};
int main(int argc,char**argv){
    assert(argc==2);auto root=std::filesystem::path(argv[1]);TempWorkspace workspace;void* e=lexi_create();
    for(auto& f:std::filesystem::directory_iterator(root/"data"))if(f.path().extension()==".tsv"&&f.path().filename().string()[0]>='0'&&f.path().filename().string()[0]<='9')assert(lexi_load(e,f.path().string().c_str())>0);
    int checks=0;
    auto has=[&](const char* code,const char* mode,const char* lang,const char* expected,int correction=1){std::string actual=lexi_query(e,code,mode,lang,correction);if(actual.find(expected)==std::string::npos){std::cerr<<code<<": "<<actual<<" expected "<<expected<<"\n";std::abort();}++checks;};
    has("nihao","pinyin","en","hello");has("NIHAO","pinyin","ja","こんにちは");has("nihao","pinyin","es","hola");
    has("nh","pinyin","en","你好");has("nh","initials","en","你好");has("nihoa","pinyin","en","correction");
    has("nihao","pinyin","off","\"gloss\":\"\"");has("woxihuanxuexiyingyu","pinyin","en","I like learning English.");
    has("woqubeijing","pinyin","en","我去北京");has("woqubeijing","pinyin","en","segments");
    has("xian","pinyin","en","先");has("xi'an","pinyin","en","西安");
    assert(std::string(lexi_query(e,"xi'an","pinyin","en",1)).find("先")==std::string::npos);++checks;
    has("wqiy","wubi","en","你");has("nihao","wubi","en","[]");
    has("nihoa","pinyin","en","[]",0);has("!x","pinyin","en","[]");has("","pinyin","en","[]");
    assert(lexi_load_layout(e,(root/"data/layout.tsv").string().c_str())==10);++checks;
    has("nihc","double","en","你好");has("woqwerty","pinyin","en","[]");
    auto bad=workspace.path/"bad-test.tsv";{std::ofstream f(bad);f<<"恶意\tfoo\t\tbar\tbaz\tqux\t1000\ttest\ninvalid\n";}
    int before=lexi_count(e);assert(lexi_load(e,bad.string().c_str())==-1);assert(lexi_count(e)==before);++checks;
    auto invalid=workspace.path/"invalid-utf8.tsv";{std::ofstream f(invalid);f<<"\xff\tfoo\t\tbar\tbaz\tqux\t1000\ttest\n";}
    assert(lexi_load(e,invalid.string().c_str())==-1);++checks;
    assert(lexi_load(e,(root/"data/import-example.tsv").string().c_str())==1);has("ciban","pinyin","en","词伴开源版");
    assert(lexi_load(e,(root/"data/import-example.tsv").string().c_str())==1);assert(lexi_count(e)==before+1);++checks;
    has(std::string(65,'a').c_str(),"pinyin","en","[]");has("nihao","invalid","en","[]");
    auto pages=workspace.path/"page-test.tsv";{std::ofstream f(pages);for(int i=0;i<40;++i)f<<"分页测试"<<i<<"\tfen ye ce shi\t\tpage\t\t\t1000\ttest\n";}
    assert(lexi_load(e,pages.string().c_str())==40);
    lexi_query(e,"fenyeceshi","pinyin","en",0);assert(lexi_candidate_count(e)==36);
    assert(std::string(lexi_candidate_field(e,35,0)).find("分页测试")==0);++checks;
    // Isolated fixtures keep fuzzy/tool expectations independent of seed data.
    void* utility=lexi_create();auto fixture=workspace.path/"core-utility-test.tsv";
    std::string lastUtilityQuery;
    auto checkAt=[&](bool condition,int line){
        if(!condition){std::cerr<<"Behavior check "<<checks+1<<" failed at line "<<line<<" after query "<<lastUtilityQuery<<"\n";std::abort();}++checks;
    };
#define check(condition) checkAt((condition),__LINE__)
    auto query=[&](const std::string& q,const char* mode="pinyin",int correction=0){
        lastUtilityQuery=q;return std::string(lexi_query(utility,q.c_str(),mode,"en",correction));
    };
    auto candidate=[&](const std::string& text,const char* kind){
        for(int i=0;i<lexi_candidate_count(utility);++i)if(text==lexi_candidate_field(utility,i,0))return std::string(lexi_candidate_field(utility,i,2))==kind;
        return false;
    };
    auto write=[&](const std::string& contents){std::ofstream f(fixture,std::ios::binary);f.write(contents.data(),std::streamsize(contents.size()));assert(f.good());};
    write("中\tzhong\tzz\tmiddle\t\t\t100000\ttest\n"
          "总\tzong\tzo\ttotal\t\t\t1\ttest\n"
          "从\tcong\tco\tfrom\t\t\t1\ttest\n"
          "上\tshang\tsh\tup\t\t\t1\ttest\n"
          "南\tnan\tna\tsouth\t\t\t100000\ttest\n"
          "蓝\tlan\tla\tblue\t\t\t1\ttest\n"
          "岸\tan\taa\tbank\t\t\t1\ttest\n"
          "昂\tang\tag\trise\t\t\t1\ttest\n"
          "恩\ten\tee\tfavor\t\t\t1\ttest\n"
          "英\tying\tyy\tflower\t\t\t1\ttest\n"
          "银\tyin\tyi\tsilver\t\t\t1\ttest\n"
          "张\tzhang\tzh\topen\t\t\t1\ttest\n"
          "三干\tsan gan\t\tfixture\t\t\t1\ttest\n"
          "桑安\tsang an\t\tfixture\t\t\t1\ttest\n"
          "南岸\tnan an\t\tfixture\t\t\t1\ttest\n"
          "拒绝回落\tv\t\tfixture\t\t\t1\ttest\n");
    check(lexi_load(utility,fixture.string().c_str())==16);
    query("zong");check(candidate("总","exact")&&!candidate("中","fuzzy"));
    lexi_set_fuzzy(utility,1);
    query("zong");check(std::string(lexi_candidate_field(utility,0,0))=="总"&&candidate("中","fuzzy"));
    query("zhong");check(candidate("总","fuzzy")&&candidate("中","exact"));
    query("chong");check(candidate("从","fuzzy"));
    query("sang");check(candidate("上","fuzzy"));
    query("zan");check(!candidate("张","fuzzy")); // Needs both initial and final bits.
    query("lan");check(!candidate("南","fuzzy"));
    lexi_set_fuzzy(utility,2);
    query("lan");check(candidate("南","fuzzy")&&std::string(lexi_candidate_field(utility,0,0))=="蓝");
    query("nan");check(candidate("蓝","fuzzy"));
    query("zong");check(!candidate("中","fuzzy"));
    query("lan'an");check(candidate("南岸","fuzzy"));
    query("la'nan");check(!candidate("南岸","fuzzy"));
    lexi_set_fuzzy(utility,4);
    query("an");check(candidate("昂","fuzzy")&&candidate("岸","exact"));
    query("ang");check(candidate("岸","fuzzy"));
    query("eng");check(candidate("恩","fuzzy"));
    query("yin");check(candidate("英","fuzzy")&&candidate("银","exact"));
    query("ying");check(candidate("银","fuzzy"));
    query("san'an");check(candidate("桑安","fuzzy")&&!candidate("三干","fuzzy"));
    query("sang'an");check(!candidate("三干","fuzzy"));
    query("san'gan");check(candidate("三干","exact"));
    query("sa'ngan");check(!candidate("三干","fuzzy"));
    query("san'");check(!candidate("桑安","fuzzy")); // No partial fuzzy syllable.
    lexi_set_fuzzy(utility,5);
    query("zan");check(candidate("张","fuzzy"));
    lexi_set_fuzzy(utility,7);
    query("lang'ang");check(candidate("南岸","fuzzy"));
    query("zong","initials");check(!candidate("中","fuzzy"));
    query("zong","wubi");check(!candidate("中","fuzzy"));
    query("zong","double");check(!candidate("中","fuzzy"));
    lexi_set_fuzzy(utility,8);
    query("zong");check(!candidate("中","fuzzy"));

    write("hello\t您好，收到。\r\nenglish\tHello!\r\nquote\t\"引号\"\\路径\n");
    check(lexi_load_phrases(utility,fixture.string().c_str())==3);
    for(const auto* mode:{"pinyin","initials","double","wubi"}) {
        query("hello",mode);check(candidate("您好，收到。","phrase"));
        check(std::string(lexi_candidate_field(utility,0,1)).empty());
        query("english",mode);check(candidate("Hello!","phrase"));
    }
    check(query("hell")=="[]");check(query("hel'lo")=="[]");
    check(query("quote").find("\\\"引号\\\"\\\\路径")!=std::string::npos);
    const std::vector<std::string> badPhrases={
        "hello\tchanged\ninvalid\n", "hello\tchanged\nhello\tduplicate\n",
        "\ttext\n", "HELLO\ttext\n", "a1\ttext\n",
        std::string(33,'a')+"\ttext\n", "hello\t\n", "hello\t"+std::string(513,'x')+"\n",
        "hello\ttext\textra\n", "hello\tbad\rtext\n", "hello\tbad\r",
        "hello\tbad\x7f\n", "hello\t\xc2\x85\n", "hello\t\xff\n",
        "hello\t\xc0\xaf\n", "hello\t\xed\xa0\x80\n", "hello\t\xf4\x90\x80\x80\n",
        "hello\t\xe2\x82\n", std::string("hello\tbad\0text\n",15), "\n"
    };
    for(const auto& contents:badPhrases) {
        write(contents);check(lexi_load_phrases(utility,fixture.string().c_str())==-1);
        query("hello");check(candidate("您好，收到。","phrase")&&!candidate("changed","phrase"));
        // Query intentionally clears a previous import error, as in the existing ABI.
    }
    write(std::string(1024*1024+1,'x'));check(lexi_load_phrases(utility,fixture.string().c_str())==-1);
    query("hello");check(candidate("您好，收到。","phrase"));
    auto triggerFor=[](int i){return std::string("row")+char('a'+i/676)+char('a'+(i/26)%26)+char('a'+i%26);};
    std::string rows;for(int i=0;i<1001;++i)rows+=triggerFor(i)+"\trow"+std::to_string(i)+"\n";
    write(rows);check(lexi_load_phrases(utility,fixture.string().c_str())==-1);
    query("hello");check(candidate("您好，收到。","phrase"));
    rows.clear();for(int i=0;i<1000;++i)rows+=triggerFor(i)+"\trow"+std::to_string(i)+"\n";
    write(rows);check(lexi_load_phrases(utility,fixture.string().c_str())==1000);
    query(triggerFor(999));check(lexi_candidate_count(utility)==1&&candidate("row999","phrase"));
    check(query("hello")=="[]"); // Successful loads replace the entire phrase table.
    write(std::string(32,'a')+"\t"+std::string(512,'x')+"\n");
    check(lexi_load_phrases(utility,fixture.string().c_str())==1);
    query(std::string(32,'a'));check(candidate(std::string(512,'x'),"phrase"));
    check(lexi_load_phrases(utility,nullptr)==-1);
    check(lexi_load_phrases(utility,(workspace.path/"does-not-exist-phrases.tsv").string().c_str())==-1);
    query(std::string(32,'a'));check(candidate(std::string(512,'x'),"phrase"));
    write("");check(lexi_load_phrases(utility,fixture.string().c_str())==0);
    check(query(std::string(32,'a'))=="[]");

    auto localValue=[](const char* format){
        auto now=std::time(nullptr);std::tm local{};
#ifdef _WIN32
        assert(localtime_s(&local,&now)==0);
#else
        assert(localtime_r(&now,&local));
#endif
        char value[32];assert(std::strftime(value,sizeof(value),format,&local));return std::string(value);
    };
    for(const auto* mode:{"pinyin","initials","double","wubi"}) {
        auto beforeDate=localValue("%Y-%m-%d");query("vdate",mode);auto afterDate=localValue("%Y-%m-%d");
        check(candidate(beforeDate,"tool")||candidate(afterDate,"tool"));
        auto beforeTime=localValue("%H:%M:%S");query("vtime",mode);auto afterTime=localValue("%H:%M:%S");
        check(candidate(beforeTime,"tool")||candidate(afterTime,"tool"));
        check(std::string(lexi_candidate_field(utility,0,1)).empty());
        query("v(2+3)*4",mode);check(candidate("20","tool"));
        query("vsymbol",mode);check(candidate("±","tool"));
        query("vemoji",mode);check(candidate("😀","tool"));
        query("kaixin",mode);check(candidate("😊","emoji"));
    }
    query("xie'xie");check(candidate("🙏","emoji"));
    query("kai'xin");check(candidate("😄","emoji"));
    lexi_query(e,"xiexie","pinyin","en",0);
    check(std::string(lexi_candidate_field(e,0,0))=="谢谢"&&std::string(lexi_candidate_field(e,0,2))=="exact");
    bool foundThanksEmoji=false;
    for(int i=0;i<lexi_candidate_count(e);++i)if(std::string(lexi_candidate_field(e,i,2))=="emoji")foundThanksEmoji=true;
    check(foundThanksEmoji);
    check(query("kaix")=="[]");check(query("ka'i'xin")=="[]");
    query("v500+21");check(candidate("521","tool"));
    query("V500+21");check(candidate("521","tool"));
    query("v2+3*4");check(candidate("14","tool"));
    query("v8/4/2");check(candidate("1","tool"));
    query("v-(-2.5)+.5");check(candidate("3","tool"));
    query("v2*-3");check(candidate("-6","tool"));
    query("v0.1+0.2");check(candidate("0.3","tool"));
    query("v-0");check(candidate("0","tool"));
    query("v1000000000000");check(candidate("1000000000000","tool"));
    query("v"+std::string(32,'-')+"1");check(candidate("1","tool"));
    query("v"+std::string(17,'(')+std::string(15,'-')+"1"+std::string(17,')'));check(candidate("-1","tool"));
    const std::vector<std::string> badMath={
        "v1/0","v1/-0","v1/(2-2)","v0/0","v1+","v(2+3","v2+3)","v()","v.",
        "v2**3","v2//3","v1..2","v1.2.3","v2(3)","v(2)(3)","v1+oops","v1;2",
        "v1e309","vnan","vinf","vNaN","vInfinity","v0x10","v1<<2","v1%2","v1^2",
        "v1 2","v1\t+2","v1\n+2","v1+sin(2)","v1+$(echo 2)","v1+2junk","v1000000000001",
        "v1000000000000*2","v1000000000000/.1","v999999999999*999999999999",
        "v1/.0000000000001","v"+std::string(33,'-')+"1","v"+std::string(32,'(')+"1"+std::string(32,')'),
        "v"+std::string(64,'1'),"v1'2",
        "v"+std::string(17,'(')+std::string(16,'-')+"1"+std::string(17,')')
    };
    for(const auto& q:badMath)check(query(q)=="[]");
    // A failed arithmetic parse must not fall back to the fixture's 'v' entry,
    // even with correction enabled.
    check(query("v1+oops","pinyin",1)=="[]");
    lexi_set_tools(utility,0);
    for(const auto* q:{"vdate","vtime","vsymbol","vemoji","v2+2","kaixin","xiexie"})check(query(q)=="[]");
    write("vdate\tpersonal date\n");check(lexi_load_phrases(utility,fixture.string().c_str())==1);
    query("vdate","wubi");check(candidate("personal date","phrase"));
    lexi_set_tools(utility,1);query("v2+2");check(candidate("4","tool"));
    query("kaixin");check(candidate("😊","emoji")&&std::string(lexi_candidate_field(utility,0,1)).empty());
    check(std::string(lexi_query(utility,nullptr,nullptr,nullptr,0))=="[]");
    check(query("v2+2","invalid")=="[]");
    lexi_destroy(utility);std::filesystem::remove(fixture);

    // All persistence fixtures live in the temporary workspace, never a user's
    // default platform history directory. Query/configuration must stay read-only.
    auto usage=workspace.path/"usage.tsv", dictionary=workspace.path/"history-dictionary.tsv";
    auto phrases=workspace.path/"history-phrases.tsv", layout=workspace.path/"history-layout.tsv";
    auto put=[&](const std::filesystem::path& path,const std::string& contents){
        std::ofstream file(path,std::ios::binary);file.write(contents.data(),std::streamsize(contents.size()));check(file.good());
    };
    auto readFile=[](const std::filesystem::path& path){
        std::ifstream file(path,std::ios::binary);return std::string(std::istreambuf_iterator<char>(file),{});
    };
    std::string sixteen,seventeen,supplementary;
    for(int i=0;i<16;++i){sixteen+="字";supplementary+="𠮷";}seventeen=sixteen+"字";
    put(dictionary,"先\txian\taa\tfirst\t先\tprimero\t100000\ttest\n"
        "贤\txian\taa\twise\t賢い\tsabio\t50000\ttest\n"
        "西安\txi an\taa\tcity\t西安\tciudad\t1\ttest\n"
        "你\tni\tnn\tyou\t\t\t1\ttest\n"
        "好\thao\thh\tgood\t\t\t1\ttest\n"
        "开心\tkai xin\tkk\thappy\t\t\t1\ttest\n"
        "开新\tkai xin\tkk\tnew\t\t\t100000\ttest\n"
        "日期词\tvdate\tvd\tdate\t\t\t1\ttest\n"+
        sixteen+"\tshort\tss\tlimit\t\t\t1\ttest\n"+
        seventeen+"\tlong\tll\tlong\t\t\t1\ttest\n"+
        supplementary+"\tunicode\tuu\tunicode\t\t\t1\ttest\n"+
        std::string(129,'x')+"\tbytes\tbb\tbytes\t\t\t1\ttest\n");
    put(layout,"xi\txx\nan\taa\nxian\txa\n");
    put(phrases,"city\t西安\nvdate\t自定义\nlongphrase\t"+seventeen+"\n");
    auto createHistoryEngine=[&](){
        void* engine=lexi_create();check(lexi_load(engine,dictionary.string().c_str())==12);
        check(lexi_load_layout(engine,layout.string().c_str())==3);
        check(lexi_load_phrases(engine,phrases.string().c_str())==3);return engine;
    };
    void* history=createHistoryEngine();
    auto hquery=[&](const char* code="xian",const char* mode="pinyin",const char* lang="en",int correction=0){
        lastUtilityQuery=std::string("history: ")+code;
        return std::string(lexi_query(history,code,mode,lang,correction));
    };
    auto first=[&](){return std::string(lexi_candidate_field(history,0,0));};
    auto choose=[&](const char* text,const char* code="xian",const char* mode="pinyin"){
        return lexi_record_selection(history,code,mode,text);
    };
    auto contains=[](void* engine,const std::string& text){
        for(int i=0;i<lexi_candidate_count(engine);++i)if(text==lexi_candidate_field(engine,i,0))return true;
        return false;
    };
    check(lexi_history(nullptr,usage.string().c_str(),1)==-1);
    check(lexi_record_selection(nullptr,"xian","pinyin","先")==-1);
    check(lexi_clear_history(nullptr)==-1);
    check(lexi_history(history,nullptr,1)==-1);
    hquery();check(first()=="先");check(choose("西安")==0); // Default disabled.
    check(lexi_clear_history(history)==0);
    check(!std::filesystem::exists(usage)&&!std::filesystem::exists(usage.string()+".lock"));
    check(lexi_history(history,usage.string().c_str(),1)==0);
    check(lexi_history(history,usage.string().c_str(),1)==0);
    hquery();check(first()=="先");
    check(!std::filesystem::exists(usage)&&!std::filesystem::exists(usage.string()+".lock"));
    check(choose("西安")==1);check(readFile(usage)=="西安\t1\n");
    for(int i=0;i<2;++i){hquery();check(first()=="西安");check(choose("西安")==1);}
    check(readFile(usage)=="西安\t3\n");
    hquery();check(choose("贤")==1);hquery();check(first()=="西安");
    for(int i=0;i<3;++i){hquery();check(choose("贤")==1);}
    hquery();check(first()=="贤"); // Count, rather than dictionary weight, wins.
    hquery();check(choose("not displayed")==-1);check(choose("贤","xi")==-1);
    check(choose("贤","xian","wubi")==-1);check(choose("贤","XIAN")==1);
    check(lexi_record_selection(history,nullptr,"pinyin","贤")==-1);
    check(lexi_record_selection(history,"xian","pinyin",nullptr)==-1);
    hquery("!");check(choose("贤","!")==-1);
    hquery("xian","invalid");check(choose("贤","xian","invalid")==-1);
    check(lexi_clear_history(history)==0);
    hquery("xi'an");check(choose("西安","xi'an")==1);
    hquery();check(first()=="西安"); // Different code: apostrophes vs full pinyin.
    hquery("x","initials","off");check(first()=="西安");
    hquery("aa","wubi","ja");check(first()=="西安");
    hquery("xxaa","double","es");check(first()=="西安");
    check(choose("西安","xxaa","double")==1);
    hquery("XIAN",nullptr);check(choose("西安","xian",nullptr)==1);
    hquery("city");check(first()=="西安"&&choose("西安","city")==1);
    hquery();check(first()=="西安");
    auto baselineBytes=readFile(usage);
    for(const auto* lang:{"en","ja","es","off"}) {
        check(lexi_history(history,usage.string().c_str(),1)==0);
        hquery("xian","pinyin",lang);check(first()=="西安");
    }
    check(readFile(usage)==baselineBytes); // Queries/configuration never record.
    void* reloaded=createHistoryEngine();check(lexi_history(reloaded,usage.string().c_str(),1)==0);
    lexi_query(reloaded,"aa","wubi","off",0);check(std::string(lexi_candidate_field(reloaded,0,0))=="西安");
    lexi_query(reloaded,"xian","pinyin","en",0);check(lexi_record_selection(reloaded,"xian","pinyin","贤")==1);
    lexi_query(reloaded,"xian","pinyin","en",0);check(lexi_record_selection(reloaded,"xian","pinyin","贤")==1);
    for(int i=0;i<4;++i){lexi_query(reloaded,"xian","pinyin","en",0);check(lexi_record_selection(reloaded,"xian","pinyin","贤")==1);}
    check(lexi_history(history,usage.string().c_str(),1)==0);
    hquery();check(first()=="贤"); // Existing engine sees another engine's replacement.
    std::filesystem::remove(usage);hquery();check(first()=="先");
    check(!std::filesystem::exists(usage)); // Deletion refresh does not recreate data.
    hquery();check(choose("西安")==1);
    check(lexi_clear_history(reloaded)==0);hquery();check(first()=="先"&&readFile(usage).empty());

    // Only words actually displayed by the last query can be persisted.
    hquery("nihao");check(contains(history,"你好"));check(choose("你好","nihao")==-1);
    hquery("vdate");std::string date=first();check(choose(date.c_str(),"vdate")==-1);
    hquery("vemoji");check(choose("😀","vemoji")==-1);
    hquery("kaixin");check(contains(history,"😊"));check(choose("😊","kaixin")==-1);
    hquery("long");check(contains(history,seventeen));check(choose(seventeen.c_str(),"long")==-1);
    hquery("longphrase");check(choose(seventeen.c_str(),"longphrase")==-1);
    hquery("bytes");check(choose(std::string(129,'x').c_str(),"bytes")==-1);
    check(readFile(usage).empty());
    hquery("short");check(choose(sixteen.c_str(),"short")==1);
    hquery("unicode");check(choose(supplementary.c_str(),"unicode")==1);
    hquery("xain","pinyin","en",1);check(choose("西安","xain")==1); // Correction is ordinary.
    hquery("xi");check(first()=="西安"&&choose("西安","xi")==1); // Prefix is ordinary.
    hquery("kaixin");check(choose("开心","kaixin")==1);hquery("kaixin");check(first()=="开心");
    hquery("vdate");check(choose("自定义","vdate")==1);hquery("vdate");
    check(std::string(lexi_candidate_field(history,0,2))=="tool"); // Utility above promoted phrase.
    check(lexi_history(e,usage.string().c_str(),1)==0);
    lexi_query(e,"fenyeceshi","pinyin","en",0);
    std::string undisplayed;
    for(int i=0;i<40;++i)if(!contains(e,"分页测试"+std::to_string(i))){undisplayed="分页测试"+std::to_string(i);break;}
    check(!undisplayed.empty());check(lexi_record_selection(e,"fenyeceshi","pinyin",undisplayed.c_str())==-1);
    check(lexi_history(e,nullptr,0)==0);

    // Disable never reads even a malformed source, writes data, or creates locks.
    auto disabled=workspace.path/"disabled.tsv";put(disabled,"corrupt\n");
    check(lexi_history(history,disabled.string().c_str(),0)==0);
    hquery();check(first()=="先"&&choose("西安")==0);
    check(readFile(disabled)=="corrupt\n"&&!std::filesystem::exists(disabled.string()+".lock"));
    auto missingParent=workspace.path/"not-created"/"usage.tsv";
    check(lexi_history(history,missingParent.string().c_str(),1)==0);hquery();
    check(!std::filesystem::exists(missingParent.parent_path()));
    check(choose("西安")==-1);check(!std::filesystem::exists(missingParent.parent_path()));
    check(lexi_history(history,disabled.string().c_str(),0)==0);
    check(lexi_clear_history(history)==0&&readFile(disabled).empty()); // Explicit clear while off.
    check(lexi_history(history,usage.string().c_str(),1)==0);
    hquery();check(first()=="西安");

    // Whole-file validation: no partial import, no overwrite on recording.
    std::vector<std::string> badHistory={
        "西安\t9\ninvalid\n", "西安\t9\n西安\t1\n", "西安\t0\n", "西安\t-1\n",
        "西安\t1000001\n", "西安\t999999999999999999999\n", "西安\t1x\n", "西安\t\n",
        "\t1\n", "\n", "西安\t1\textra\n", "\xff\t1\n", "\xc0\xaf\t1\n",
        "\xed\xa0\x80\t1\n", "\xf4\x90\x80\x80\t1\n", "\xe2\x82\t1\n",
        "bad\rtext\t1\n", "bad\x7f\t1\n", "\xc2\x85\t1\n",
        std::string("bad\0text\t1\n",11),seventeen+"\t1\n",std::string(129,'x')+"\t1\n",
        std::string(1024*1024+1,'x')
    };
    std::string tooMany;for(int i=0;i<2001;++i)tooMany+="word"+std::to_string(i)+"\t1\n";
    badHistory.push_back(tooMany);
    for(const auto& contents:badHistory) {
        put(usage,contents);
        check(lexi_history(history,usage.string().c_str(),1)==0); // Unchanged: no read/reparse.
        hquery();check(first()=="先"&&!std::string(lexi_error(history)).empty());
        check(choose("西安")==-1);check(readFile(usage)==contents);
        check(lexi_history(reloaded,nullptr,0)==0);
        check(lexi_history(reloaded,usage.string().c_str(),1)==-1);
        lexi_query(reloaded,"xian","pinyin","en",0);
        check(std::string(lexi_candidate_field(reloaded,0,0))=="先");
    }
    check(lexi_clear_history(history)==0);hquery();check(choose("西安")==1);
    put(usage,"西安\t1000000\r\n贤\t1\n");hquery();check(first()=="西安");
    check(choose("西安")==1);check(readFile(usage)=="西安\t1000000\n贤\t1\n");
    put(usage,"西安\t2");hquery();check(first()=="西安"); // Valid final row without newline.
    check(choose("西安")==1&&readFile(usage)=="西安\t3\n");
    std::string full="lowest\t1\n";
    for(int i=0;i<1999;++i)full+="word"+std::to_string(i)+"\t2\n";
    put(usage,full);hquery();check(choose("西安")==1);
    std::string evicted=readFile(usage);check(evicted.find("lowest\t")==std::string::npos);
    check(evicted.find("西安\t1\n")!=std::string::npos);
    check(std::count(evicted.begin(),evicted.end(),'\n')==2000);

#ifndef _WIN32
    // The real process test catches lost read/modify/write updates; every child
    // has an independent engine and native file lock. Readers race replacements.
    check(lexi_clear_history(history)==0);
    std::vector<pid_t> children;
    for(int child=0;child<4;++child) {
        pid_t pid=fork();check(pid>=0);
        if(pid==0) {
            void* writer=lexi_create();bool ok=lexi_load(writer,dictionary.string().c_str())==12 &&
                lexi_history(writer,usage.string().c_str(),1)==0;
            if(!ok)std::cerr<<"History child initialization failed: "<<lexi_error(writer)<<"\n";
            for(int i=0;i<25 && ok;++i) {
                lexi_query(writer,"xian","pinyin","off",0);
                ok=lexi_record_selection(writer,"xian","pinyin","西安")==1;
                if(!ok)std::cerr<<"History child recording failed: "<<lexi_error(writer)<<"\n";
            }
            lexi_destroy(writer);_exit(ok?0:1);
        }
        children.push_back(pid);
    }
    for(int i=0;i<100;++i) {
        check(lexi_history(history,nullptr,0)==0);
        check(lexi_history(history,usage.string().c_str(),1)==0);hquery();
    }
    for(pid_t child:children) {
        int status=0;pid_t waited;
        do{waited=waitpid(child,&status,0);}while(waited<0 && errno==EINTR);
        check(waited==child&&WIFEXITED(status)&&WEXITSTATUS(status)==0);
    }
    check(readFile(usage)=="西安\t100\n");hquery();check(first()=="西安");
    std::filesystem::remove(usage);hquery();check(first()=="先");
    // A FIFO makes an accidental disabled read observable as a hang; symlinks
    // are rejected for enabled history without modifying their target.
    auto fifo=workspace.path/"disabled-fifo.tsv";check(mkfifo(fifo.c_str(),0600)==0);
    check(lexi_history(history,fifo.string().c_str(),0)==0);hquery();check(choose("西安")==0);
    check(!std::filesystem::exists(fifo.string()+".lock"));
    put(usage,"西安\t2\n");auto symlink=workspace.path/"linked-history.tsv";
    std::filesystem::create_symlink(usage,symlink);
    check(lexi_history(history,symlink.string().c_str(),1)==-1);hquery();check(choose("西安")==-1);
    check(readFile(usage)=="西安\t2\n");
#else
    std::cout<<"Cross-process fork test skipped on Windows; native Windows locking requires Windows validation.\n";
#endif
    lexi_destroy(history);lexi_destroy(reloaded);
    auto start=std::chrono::steady_clock::now();for(int i=0;i<1000;++i)lexi_query(e,"woxihuanxuexiyingyu","pinyin","en",1);
    std::cout<<checks<<" behavior checks passed; "<<lexi_count(e)<<" entries; long-input mean "<<std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()/1000<<" ms (seed pack only)\n";
    lexi_destroy(e);std::filesystem::remove(bad);std::filesystem::remove(invalid);std::filesystem::remove(pages);
}
