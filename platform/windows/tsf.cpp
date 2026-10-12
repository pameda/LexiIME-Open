#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <msctf.h>
#include <inputscope.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <fstream>
#include <filesystem>
#include <atomic>
#include <algorithm>
#include <utility>
#include "../../core/lexi.h"
#include "candidate_layout.h"

// Original, minimal desktop TSF integration. Store/UWP and secure-field behavior
// must pass the documented Windows release gates before distribution.
static const CLSID CLSID_Lexi={0x58e6cd1e,0xa983,0x4f79,{0x9a,0x75,0x41,0x6f,0x76,0xc7,0x34,0x05}};
static const GUID PROFILE_Lexi={0x7c7f5039,0xee48,0x4337,{0xa6,0x23,0xa1,0x07,0xad,0x5a,0x12,0x13}};
static HMODULE module;
static std::atomic<long> objects{0};
// Internal finish action: focus changes and shortcuts commit raw text, never a tool.
static constexpr WPARAM commitRaw=0;
static std::filesystem::path moduleDir(){wchar_t p[32768];DWORD n=GetModuleFileNameW(module,p,32768);return std::filesystem::path(std::wstring(p,n)).parent_path();}
static std::filesystem::path userDir(){PWSTR p=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&p)))return {};auto result=std::filesystem::path(p)/L"LexiIME-Open";CoTaskMemFree(p);return result;}
static std::wstring wide(const char* utf){int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,utf,-1,nullptr,0);if(n<=1)return L"";std::wstring out(size_t(n),L'\0');MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,utf,-1,out.data(),n);out.pop_back();return out;}
static std::filesystem::file_time_type modified(const std::filesystem::path& path){std::error_code error;auto time=std::filesystem::last_write_time(path,error);return error?std::filesystem::file_time_type::min():time;}
using DictionaryStamp=std::vector<std::pair<std::filesystem::path,std::filesystem::file_time_type>>;
static DictionaryStamp dictionaryStamp(){
    DictionaryStamp stamp;
    try{auto dir=userDir()/L"Dictionaries";if(std::filesystem::exists(dir))for(auto& f:std::filesystem::directory_iterator(dir))
        if(f.path().extension()==L".tsv")stamp.emplace_back(f.path(),modified(f.path()));
        std::sort(stamp.begin(),stamp.end());
    }catch(...){stamp.emplace_back(L"!unavailable",std::filesystem::file_time_type::min());}
    return stamp;
}
static bool modifierKey(WPARAM key){return key==VK_SHIFT||key==VK_LSHIFT||key==VK_RSHIFT||key==VK_CONTROL||key==VK_LCONTROL||key==VK_RCONTROL||key==VK_MENU||key==VK_LMENU||key==VK_RMENU||key==VK_LWIN||key==VK_RWIN;}
template<class T>static void release(T*& p){if(p){p->Release();p=nullptr;}}
struct Session;
struct Service final:ITfTextInputProcessorEx,ITfKeyEventSink,ITfCompositionSink {
    std::atomic<ULONG> refs{1};ITfThreadMgr* manager=nullptr;TfClientId id=TF_CLIENTID_NULL;
    ITfComposition* composition=nullptr;ITfContext* activeContext=nullptr;
    void* engine=nullptr;HWND popup=nullptr;std::string buffer,language="en",mode="pinyin";bool correction=true,tools=true,learning=true;int fuzzy=0,selected=0;
    bool preferencesLoaded=false,candidatesStale=false;DictionaryStamp dictionaryFiles;
    std::filesystem::file_time_type configTime=std::filesystem::file_time_type::min(),phraseTime=std::filesystem::file_time_type::min();
    Service(){++objects;engine=lexi_create();}
    ~Service(){if(popup)DestroyWindow(popup);release(composition);release(activeContext);release(manager);lexi_destroy(engine);--objects;}
    STDMETHODIMP QueryInterface(REFIID iid,void** out)override{if(!out)return E_POINTER;*out=nullptr;
        if(iid==IID_IUnknown||iid==IID_ITfTextInputProcessor||iid==IID_ITfTextInputProcessorEx)*out=static_cast<ITfTextInputProcessorEx*>(this);
        else if(iid==IID_ITfKeyEventSink)*out=static_cast<ITfKeyEventSink*>(this);else if(iid==IID_ITfCompositionSink)*out=static_cast<ITfCompositionSink*>(this);
        if(!*out)return E_NOINTERFACE;AddRef();return S_OK;}
    STDMETHODIMP_(ULONG) AddRef()override{return ++refs;}STDMETHODIMP_(ULONG) Release()override{ULONG n=--refs;if(!n)delete this;return n;}
    void history(){
        auto root=userDir();
        if(root.empty()){lexi_history(engine,nullptr,0);return;}
        // Disabled configuration performs no history reads or writes. Core owns refresh/locking.
        lexi_history(engine,(root/L"usage.tsv").u8string().c_str(),learning?1:0);
    }
    void load(){
        void* next=lexi_create();bool ok=true;
        try{for(auto dir:{moduleDir()/L"data",userDir()/L"Dictionaries"})if(std::filesystem::exists(dir))for(auto& f:std::filesystem::directory_iterator(dir)){
            auto name=f.path().filename().u8string();if(f.path().extension()!=L".tsv"|| (dir==moduleDir()/L"data" && (name.empty()||name[0]<'0'||name[0]>'9')))continue;
            if(lexi_load(next,f.path().u8string().c_str())<0)ok=false;
        }
        auto custom=userDir()/L"layout.tsv";auto layout=std::filesystem::exists(custom)?custom:moduleDir()/L"data/layout.tsv";
        if(lexi_load_layout(next,layout.u8string().c_str())<0)ok=false;
        auto phrases=userDir()/L"phrases.tsv";if(std::filesystem::exists(phrases)&&lexi_load_phrases(next,phrases.u8string().c_str())<0)ok=false;
        lexi_set_fuzzy(next,fuzzy);lexi_set_tools(next,tools?1:0);
        }catch(...){ok=false;}
        if(ok){lexi_destroy(engine);engine=next;history();}else lexi_destroy(next);
    }
    void preferences(bool force=false){
        auto root=userDir();auto nextConfigTime=modified(root/L"settings.ini"),nextPhraseTime=modified(root/L"phrases.tsv");
        auto nextDictionaryFiles=dictionaryStamp();
        bool dictionariesChanged=force||!preferencesLoaded||nextDictionaryFiles!=dictionaryFiles;
        bool configChanged=force||!preferencesLoaded||nextConfigTime!=configTime;
        bool phrasesChanged=force||!preferencesLoaded||nextPhraseTime!=phraseTime;
        if(!configChanged&&!phrasesChanged&&!dictionariesChanged)return;
        if(configChanged){
            language="en";mode="pinyin";correction=true;fuzzy=0;tools=true;learning=true;
            std::ifstream f(root/L"settings.ini");std::string line;
            while(std::getline(f,line)){
                if(!line.empty()&&line.back()=='\r')line.pop_back();auto eq=line.find('=');if(eq==std::string::npos)continue;auto k=line.substr(0,eq),v=line.substr(eq+1);
                if(k=="language"&&(v=="en"||v=="ja"||v=="es"||v=="off"))language=v;
                if(k=="mode"&&(v=="pinyin"||v=="initials"||v=="double"||v=="wubi"))mode=v;
                if(k=="correction"&&(v=="0"||v=="1"))correction=v=="1";
                if(k=="fuzzy"&&v.size()==1&&v[0]>='0'&&v[0]<='7')fuzzy=v[0]-'0';
                if(k=="tools"&&(v=="0"||v=="1"))tools=v=="1";
                if(k=="learning"&&(v=="0"||v=="1"))learning=v=="1";
            }
            lexi_set_fuzzy(engine,fuzzy);lexi_set_tools(engine,tools?1:0);history();
        }
        // Rebuilding also clears phrases when the file disappears. Invalid files
        // cannot replace a previously loaded engine or its phrases.
        if((phrasesChanged||dictionariesChanged)&&!force)load();
        preferencesLoaded=true;configTime=nextConfigTime;phraseTime=nextPhraseTime;dictionaryFiles=std::move(nextDictionaryFiles);
        candidatesStale=true; // Lookup is deferred until the input scope is checked inside edit().
    }
    bool expression()const{
        return tools&&!buffer.empty()&&buffer[0]=='v'&&std::all_of(buffer.begin()+1,buffer.end(),[](char c){return (c>='0'&&c<='9')||c=='+'||c=='-'||c=='*'||c=='/'||c=='('||c==')'||c=='.';});
    }
    char expressionCharacter(WPARAM key)const{
        if(!expression())return 0;
        BYTE state[256];if(!GetKeyboardState(state))return 0;wchar_t text[4]{};HKL layout=GetKeyboardLayout(0);
        // Flag 4 leaves dead-key/keyboard state unchanged (Windows 10 1607+).
        int n=ToUnicodeEx(UINT(key),MapVirtualKeyExW(UINT(key),MAPVK_VK_TO_VSC,layout),state,text,4,4,layout);
        if(n!=1)return 0;wchar_t c=text[0];return ((c>=L'0'&&c<=L'9')||c==L'+'||c==L'-'||c==L'*'||c==L'/'||c==L'('||c==L')'||c==L'.')?char(c):0;
    }
    STDMETHODIMP Activate(ITfThreadMgr* mgr,TfClientId client)override{return ActivateEx(mgr,client,0);}
    STDMETHODIMP ActivateEx(ITfThreadMgr* mgr,TfClientId client,DWORD flags)override{
        if(!mgr)return E_INVALIDARG;if(manager)return E_UNEXPECTED;
        // No custom popup in UI-less/secure activation. These modes need a separate adapter.
        if(flags & (TF_TMAE_SECUREMODE|TF_TMAE_UIELEMENTENABLEDONLY))return E_FAIL;
        manager=mgr;manager->AddRef();id=client;preferences(true);load();ITfKeystrokeMgr* keys=nullptr;
        HRESULT hr=manager->QueryInterface(IID_PPV_ARGS(&keys));if(SUCCEEDED(hr)){hr=keys->AdviseKeyEventSink(id,this,TRUE);keys->Release();}
        if(FAILED(hr)){release(manager);id=TF_CLIENTID_NULL;}return hr;
    }
    STDMETHODIMP Deactivate()override;
    bool allowed(ITfContext* context){
        if(!context)return false;
        TF_STATUS status{};if(FAILED(context->GetStatus(&status))||(status.dwDynamicFlags&TF_SD_READONLY))return false;
        ITfCompartmentMgr* compartments=nullptr;
        if(SUCCEEDED(context->QueryInterface(IID_PPV_ARGS(&compartments)))){
            bool disabled=false;for(const GUID* guid:{&GUID_COMPARTMENT_KEYBOARD_DISABLED,&GUID_COMPARTMENT_EMPTYCONTEXT}){
                ITfCompartment* c=nullptr;if(SUCCEEDED(compartments->GetCompartment(*guid,&c))){VARIANT value;VariantInit(&value);if(SUCCEEDED(c->GetValue(&value))&&value.vt==VT_I4&&value.lVal!=0)disabled=true;VariantClear(&value);c->Release();}
            }compartments->Release();if(disabled)return false;
        }
        return true;
    }
    bool handles(ITfContext* c,WPARAM key){
        if(!allowed(c)||(GetKeyState(VK_CONTROL)&0x8000)||(GetKeyState(VK_MENU)&0x8000)||(GetKeyState(VK_LWIN)&0x8000)||(GetKeyState(VK_RWIN)&0x8000))return false;
        if(GetKeyState(VK_CAPITAL)&1)return false;
        preferences();
        if(key>='A'&&key<='Z')return true;
        if(buffer.empty())return false;
        if(expressionCharacter(key))return true;
        return key==VK_BACK||key==VK_ESCAPE||key==VK_RETURN||key==VK_SPACE||key==VK_UP||key==VK_DOWN||key==VK_PRIOR||key==VK_NEXT||key==VK_OEM_7||(((key==VK_OEM_MINUS||key==VK_OEM_PLUS)||(key>='1'&&key<='5'))&&!(GetKeyState(VK_SHIFT)&0x8000));
    }
    STDMETHODIMP OnSetFocus(BOOL foreground)override;
    STDMETHODIMP OnTestKeyDown(ITfContext* c,WPARAM key,LPARAM,BOOL* eaten)override{if(!eaten)return E_POINTER;*eaten=handles(c,key);return S_OK;}
    STDMETHODIMP OnTestKeyUp(ITfContext*,WPARAM,LPARAM,BOOL* eaten)override{if(!eaten)return E_POINTER;*eaten=FALSE;return S_OK;}
    STDMETHODIMP OnKeyUp(ITfContext*,WPARAM,LPARAM,BOOL* eaten)override{if(!eaten)return E_POINTER;*eaten=FALSE;return S_OK;}
    STDMETHODIMP OnPreservedKey(ITfContext*,REFGUID,BOOL* eaten)override{if(!eaten)return E_POINTER;*eaten=FALSE;return S_OK;}
    STDMETHODIMP OnKeyDown(ITfContext* c,WPARAM key,LPARAM,BOOL* eaten)override;
    STDMETHODIMP OnCompositionTerminated(TfEditCookie,ITfComposition* ended)override{if(ended==composition){release(composition);release(activeContext);buffer.clear();if(popup)ShowWindow(popup,SW_HIDE);}return S_OK;}
    HRESULT edit(ITfContext* context,TfEditCookie cookie,WPARAM key);
    std::vector<LexiCandidateLayout::Range> candidatePages()const {
        std::vector<std::wstring> words;
        for(int i=0;i<lexi_candidate_count(engine);++i)words.push_back(wide(lexi_candidate_field(engine,i,0)));
        return LexiCandidateLayout::pages(words);
    }
    void show(ITfContext* c,TfEditCookie cookie,ITfRange* range){
        if(buffer.empty()){if(popup)ShowWindow(popup,SW_HIDE);return;}
        std::wstring text=wide(buffer.c_str())+L"\r\n";
        int count=lexi_candidate_count(engine);auto visible=LexiCandidateLayout::range(candidatePages(),selected);
        int start=visible.first,end=visible.second;
        for(int i=start;i<end;++i) {
            text+=(i==selected?L"› ":L"  ")+std::to_wstring(i-start+1)+L"  "+LexiCandidateLayout::compact(wide(lexi_candidate_field(engine,i,0)),28)+L"\r\n";
            auto gloss=LexiCandidateLayout::compact(wide(lexi_candidate_field(engine,i,1)),end-start==1?64:32);
            text+=L"     "+gloss+L"\r\n";
        }
        if(count>end-start)text+=std::to_wstring(start+1)+L"–"+std::to_wstring(end)+L" / "+std::to_wstring(count)+(expression()?L"  PgUp / PgDn 翻页":L"  - / = 翻页");
        if(count==0)text+=L"未收录 · Enter 输出编码";
        if(!popup){popup=CreateWindowExW(WS_EX_TOPMOST|WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW,L"STATIC",L"",WS_POPUP|WS_BORDER|SS_LEFT,0,0,500,100,nullptr,nullptr,module,nullptr);if(popup)SendMessageW(popup,WM_SETFONT,reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)),TRUE);}
        RECT caret{};BOOL clipped=FALSE;ITfContextView* view=nullptr;if(SUCCEEDED(c->GetActiveView(&view))){view->GetTextExt(cookie,range,&caret,&clipped);view->Release();}
        MONITORINFO info{sizeof(MONITORINFO)};GetMonitorInfoW(MonitorFromRect(&caret,MONITOR_DEFAULTTONEAREST),&info);
        int height=24*(2*(end-start)+3),x=caret.left,y=caret.bottom+4;x=(std::max)(info.rcWork.left,(std::min)(x,info.rcWork.right-500));y=(std::max)(info.rcWork.top,(std::min)(y,info.rcWork.bottom-height));
        SetWindowTextW(popup,text.c_str());SetWindowPos(popup,HWND_TOPMOST,x,y,500,height,SWP_NOACTIVATE|SWP_SHOWWINDOW);
    }
};
struct Session final:ITfEditSession {
    std::atomic<ULONG> refs{1};Service* service;ITfContext* context;WPARAM key;
    Session(Service* s,ITfContext* c,WPARAM k):service(s),context(c),key(k){++objects;s->AddRef();c->AddRef();}
    ~Session(){service->Release();context->Release();--objects;}
    STDMETHODIMP QueryInterface(REFIID iid,void**out)override{if(!out)return E_POINTER;*out=nullptr;if(iid!=IID_IUnknown&&iid!=IID_ITfEditSession)return E_NOINTERFACE;*out=static_cast<ITfEditSession*>(this);AddRef();return S_OK;}
    STDMETHODIMP_(ULONG) AddRef()override{return ++refs;}STDMETHODIMP_(ULONG) Release()override{ULONG n=--refs;if(!n)delete this;return n;}
    STDMETHODIMP DoEditSession(TfEditCookie cookie)override{return service->edit(context,cookie,key);}
};
static HRESULT runEdit(Service* s,ITfContext* c,WPARAM key){auto session=new Session(s,c,key);HRESULT result=E_FAIL;HRESULT hr=c->RequestEditSession(s->id,session,TF_ES_SYNC|TF_ES_READWRITE,&result);session->Release();return FAILED(hr)?hr:result;}
HRESULT Service::OnSetFocus(BOOL foreground){if(!foreground){if(activeContext)runEdit(this,activeContext,commitRaw);if(popup)ShowWindow(popup,SW_HIDE);}return S_OK;}
HRESULT Service::Deactivate(){
    if(activeContext)runEdit(this,activeContext,commitRaw);
    if(manager){ITfKeystrokeMgr* keys=nullptr;if(SUCCEEDED(manager->QueryInterface(IID_PPV_ARGS(&keys)))){keys->UnadviseKeyEventSink(id);keys->Release();}}
    release(composition);release(activeContext);release(manager);id=TF_CLIENTID_NULL;buffer.clear();if(popup){DestroyWindow(popup);popup=nullptr;}return S_OK;
}
HRESULT Service::OnKeyDown(ITfContext* c,WPARAM key,LPARAM,BOOL* eaten){
    if(!eaten)return E_POINTER;*eaten=FALSE;
    if(activeContext&&activeContext!=c){runEdit(this,activeContext,commitRaw);if(activeContext)return S_OK;}
    // Pass modifiers through without ending composition: Shift is needed for
    // +, *, and parentheses. An actual Ctrl/Alt/Win shortcut still passes through.
    if(!handles(c,key)){if(!modifierKey(key)&&activeContext&&!buffer.empty())runEdit(this,activeContext,commitRaw);return S_OK;}
    HRESULT hr=runEdit(this,c,key);*eaten=hr==S_OK;return S_OK;
}
HRESULT Service::edit(ITfContext* context,TfEditCookie cookie,WPARAM key){
    TF_SELECTION sel{};ULONG fetched=0;HRESULT hr=context->GetSelection(cookie,TF_DEFAULT_SELECTION,1,&sel,&fetched);if(FAILED(hr)||!fetched)return E_FAIL;
    // Password input scopes are checked inside an edit session before looking up or showing candidates.
    bool privateScope=false;ITfReadOnlyProperty* prop=nullptr;
    HRESULT scopeResult=context->GetAppProperty(GUID_PROP_INPUTSCOPE,&prop);
    if(FAILED(scopeResult))privateScope=true;
    else if(prop){
        VARIANT v;VariantInit(&v);scopeResult=prop->GetValue(cookie,sel.range,&v);
        if(FAILED(scopeResult))privateScope=true;
        else if(v.vt==VT_UNKNOWN&&v.punkVal){
            ITfInputScope* scope=nullptr;
            if(FAILED(v.punkVal->QueryInterface(IID_PPV_ARGS(&scope))))privateScope=true;
            else{InputScope* values=nullptr;UINT n=0;
                if(FAILED(scope->GetInputScopes(&values,&n)))privateScope=true;
                else for(UINT i=0;i<n;++i)if(values[i]==IS_PASSWORD)privateScope=true;
                CoTaskMemFree(values);scope->Release();
            }
        }
        VariantClear(&v);prop->Release();
    }
    if(privateScope){buffer.clear();release(composition);release(activeContext);if(popup)ShowWindow(popup,SW_HIDE);sel.range->Release();return S_FALSE;}
    if(candidatesStale&&!buffer.empty()){history();lexi_query(engine,buffer.c_str(),mode.c_str(),language.c_str(),correction?1:0);selected=0;}
    candidatesStale=false;
    // Copy before SetText/EndComposition can reenter TSF and clear our buffer.
    const std::string originalCode=buffer,originalMode=mode;
    bool chosen=false;std::string chosenText;
    std::string next=buffer;bool finish=false;char arithmetic=expressionCharacter(key);
    // Digits/operators must be appended before number selection and -/= paging.
    if(arithmetic){if(next.size()>=64){sel.range->Release();return S_OK;}next+=arithmetic;selected=0;}
    else if(key>='A'&&key<='Z'){if(next.size()>=64){sel.range->Release();return S_OK;}next+=char(key-'A'+'a');selected=0;}
    else if(key==VK_OEM_7){if(next.size()<64)next+='\'';}
    else if(key==VK_BACK){if(!next.empty())next.pop_back();}
    else if(key==VK_ESCAPE){next.clear();finish=true;}
    else if(key==VK_RETURN||key==commitRaw){
        if(key==VK_RETURN&&tools)for(int i=0;i<lexi_candidate_count(engine);++i)if(std::string(lexi_candidate_field(engine,i,2))=="tool"){next=lexi_candidate_field(engine,i,0);break;}
        finish=true;
    }
    else if(key==VK_UP)selected=(std::max)(0,selected-1);
    else if(key==VK_DOWN)selected=(std::min)((std::max)(0,lexi_candidate_count(engine)-1),selected+1);
    else if(key==VK_PRIOR||key==VK_OEM_MINUS)selected=LexiCandidateLayout::next(candidatePages(),selected,-1);
    else if(key==VK_NEXT||key==VK_OEM_PLUS)selected=LexiCandidateLayout::next(candidatePages(),selected,1);
    else if(key==VK_SPACE||(key>='1'&&key<='5')){
        auto visible=LexiCandidateLayout::range(candidatePages(),selected);
        if(key!=VK_SPACE&&int(key-'1')>=visible.second-visible.first){sel.range->Release();return S_FALSE;}
        int pick=key==VK_SPACE?selected:visible.first+int(key-'1');if(pick<0||pick>=lexi_candidate_count(engine)){if(key!=VK_SPACE){sel.range->Release();return S_FALSE;}}
        else{next=lexi_candidate_field(engine,pick,0);chosenText=next;
            std::string kind=lexi_candidate_field(engine,pick,2);
            chosen=kind!="tool"&&kind!="emoji"&&kind!="segments";
        }finish=true;
    }
    if(next.empty())finish=true;
    ITfRange* range=nullptr;
    if(composition){hr=composition->GetRange(&range);sel.range->Release();}
    else {range=sel.range;ITfContextComposition* cc=nullptr;hr=context->QueryInterface(IID_PPV_ARGS(&cc));if(SUCCEEDED(hr)){hr=cc->StartComposition(cookie,range,this,&composition);cc->Release();}if(SUCCEEDED(hr)&&composition){activeContext=context;activeContext->AddRef();}else if(SUCCEEDED(hr))hr=E_FAIL;}
    if(FAILED(hr)||!range){release(range);return E_FAIL;}
    auto value=wide(next.c_str());hr=range->SetText(cookie,0,value.c_str(),LONG(value.size()));
    if(SUCCEEDED(hr)){
        ITfRange* end=nullptr;if(SUCCEEDED(range->Clone(&end))){end->Collapse(cookie,TF_ANCHOR_END);TF_SELECTION selection{};selection.range=end;selection.style.ase=TF_AE_NONE;context->SetSelection(cookie,1,&selection);end->Release();}
        buffer=finish?"":next;
        if(finish){
            ITfComposition* ended=composition;composition=nullptr;
            HRESULT committed=ended->EndComposition(cookie);
            if(FAILED(committed)){composition=ended;buffer=originalCode;hr=committed;}
            else{ended->Release();release(activeContext);if(popup)ShowWindow(popup,SW_HIDE);
                // Only explicit numeric/space candidate choices, after both TSF operations succeed.
                // Core excludes tool/emoji/segments/long text and checks the original query.
                if(chosen&&learning){
                    auto root=userDir();std::error_code error;
                    if(!root.empty()){
                        // Creating the history parent is allowed only after an actual successful selection.
                        std::filesystem::create_directories(root,error);
                        if(!error)lexi_record_selection(engine,originalCode.c_str(),originalMode.c_str(),chosenText.c_str());
                    }
                }
            }
        }
        else{history();lexi_query(engine,buffer.c_str(),mode.c_str(),language.c_str(),correction?1:0);selected=(std::min)(selected,(std::max)(0,lexi_candidate_count(engine)-1));show(context,cookie,range);}
    }
    range->Release();return hr;
}
struct Factory final:IClassFactory {
    std::atomic<ULONG> refs{1};Factory(){++objects;}~Factory(){--objects;}
    STDMETHODIMP QueryInterface(REFIID iid,void**out)override{if(!out)return E_POINTER;*out=nullptr;if(iid!=IID_IUnknown&&iid!=IID_IClassFactory)return E_NOINTERFACE;*out=static_cast<IClassFactory*>(this);AddRef();return S_OK;}
    STDMETHODIMP_(ULONG) AddRef()override{return ++refs;}STDMETHODIMP_(ULONG) Release()override{ULONG n=--refs;if(!n)delete this;return n;}
    STDMETHODIMP CreateInstance(IUnknown* outer,REFIID iid,void**out)override{if(outer)return CLASS_E_NOAGGREGATION;auto s=new Service;HRESULT hr=s->QueryInterface(iid,out);s->Release();return hr;}
    STDMETHODIMP LockServer(BOOL lock)override{if(lock)++objects;else --objects;return S_OK;}
};
extern "C" BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH){module=h;DisableThreadLibraryCalls(h);}return TRUE;}
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid,REFIID iid,void**out){if(clsid!=CLSID_Lexi)return CLASS_E_CLASSNOTAVAILABLE;auto f=new Factory;HRESULT hr=f->QueryInterface(iid,out);f->Release();return hr;}
extern "C" HRESULT __stdcall DllCanUnloadNow(){return objects.load()==0?S_OK:S_FALSE;}
static std::wstring classKey(){wchar_t guid[40];StringFromGUID2(CLSID_Lexi,guid,40);return std::wstring(L"CLSID\\")+guid;}
extern "C" HRESULT __stdcall DllUnregisterServer(){
    HRESULT init=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);ITfInputProcessorProfiles* profiles=nullptr;
    if(SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles)))){profiles->Unregister(CLSID_Lexi);profiles->Release();}
    ITfCategoryMgr* category=nullptr;if(SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&category)))){category->UnregisterCategory(CLSID_Lexi,GUID_TFCAT_TIP_KEYBOARD,CLSID_Lexi);category->Release();}
    RegDeleteTreeW(HKEY_CLASSES_ROOT,classKey().c_str());if(SUCCEEDED(init))CoUninitialize();return S_OK;
}
extern "C" HRESULT __stdcall DllRegisterServer(){
    wchar_t path[32768];GetModuleFileNameW(module,path,32768);HKEY key=nullptr;
    auto name=classKey()+L"\\InprocServer32";LONG result=RegCreateKeyExW(HKEY_CLASSES_ROOT,name.c_str(),0,nullptr,0,KEY_WRITE,nullptr,&key,nullptr);if(result!=ERROR_SUCCESS)return HRESULT_FROM_WIN32(result);
    result=RegSetValueExW(key,nullptr,0,REG_SZ,reinterpret_cast<const BYTE*>(path),DWORD((wcslen(path)+1)*sizeof(wchar_t)));
    if(result==ERROR_SUCCESS)result=RegSetValueExW(key,L"ThreadingModel",0,REG_SZ,reinterpret_cast<const BYTE*>(L"Apartment"),sizeof(L"Apartment"));RegCloseKey(key);if(result!=ERROR_SUCCESS)return HRESULT_FROM_WIN32(result);
    HRESULT init=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);ITfInputProcessorProfiles* profiles=nullptr;
    HRESULT hr=CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles));
    if(SUCCEEDED(hr)){hr=profiles->Register(CLSID_Lexi);if(SUCCEEDED(hr))hr=profiles->AddLanguageProfile(CLSID_Lexi,0x0804,PROFILE_Lexi,L"词伴开源版 LexiIME-Open",ULONG(wcslen(L"词伴开源版 LexiIME-Open")),path,ULONG(wcslen(path)),0);if(SUCCEEDED(hr))hr=profiles->EnableLanguageProfile(CLSID_Lexi,0x0804,PROFILE_Lexi,TRUE);profiles->Release();}
    ITfCategoryMgr* category=nullptr;if(SUCCEEDED(hr)){hr=CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&category));if(SUCCEEDED(hr)){hr=category->RegisterCategory(CLSID_Lexi,GUID_TFCAT_TIP_KEYBOARD,CLSID_Lexi);category->Release();}}
    if(SUCCEEDED(init))CoUninitialize();if(FAILED(hr))DllUnregisterServer();return hr;
}
