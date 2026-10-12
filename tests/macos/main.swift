import Foundation
var checks = 0
func rejects(_ operation: () throws -> Void) {
    do { try operation();fatalError("Expected rejection") } catch { checks += 1 }
}
var p = Preferences()
rejects { _ = try Cloud.makeRequest("你好", preferences:p, key:"test-only") }
p.cloudEnabled=true;p.endpoint="https://example.invalid/v1/chat/completions";p.model="test-model"
for endpoint in ["http://example.invalid/v1/chat/completions","https://key@example.invalid/v1/chat/completions","https://example.invalid/v1/chat/completions?key=secret","https://example.invalid/v1/chat/completions#fragment","nonsense"] {
    var bad=p;bad.endpoint=endpoint;rejects{_ = try Cloud.makeRequest("你好",preferences:bad,key:"test-only")}
}
rejects{_ = try Cloud.makeRequest(String(repeating:"字",count:129),preferences:p,key:"test-only")}
rejects{_ = try Cloud.makeRequest("你好",preferences:p,key:nil)}
var off=p;off.language="off";rejects{_ = try Cloud.makeRequest("你好",preferences:off,key:"test-only")}
let request=try Cloud.makeRequest("你好",preferences:p,key:"test-only")
assert(request.httpMethod=="POST");assert(request.timeoutInterval==8)
let json=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
let messages=json["messages"] as! [[String:String]]
assert(messages.count==2 && messages[1]["content"]=="你好")
assert(json["model"] as? String=="test-model")
checks += 1
let success=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!
let failure=HTTPURLResponse(url:request.url!,statusCode:401,httpVersion:nil,headerFields:nil)!
let data=Data(#"{"choices":[{"message":{"content":" hello "}}]}"#.utf8)
let decoded=try Cloud.decode(data,response:success)
assert(decoded=="hello");checks += 1
rejects{_ = try Cloud.decode(data,response:failure)}
rejects{_ = try Cloud.decode(Data("{}".utf8),response:success)}
rejects{_ = try Cloud.decode(Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8),response:success)}
rejects{_ = try Cloud.decode(Data(repeating:32,count:65537),response:success)}
print("\(checks) cloud contract checks passed; no network calls, no real credentials.")
let old=Data(#"{"language":"ja","mode":"pinyin","correction":true,"study":true,"cloudEnabled":false,"endpoint":"","model":"","disabledPacks":[]}"#.utf8)
let migrated=try JSONDecoder().decode(Preferences.self,from:old)
assert(migrated.language=="ja" && migrated.pageSize==5 && migrated.speechLocale==nil)
assert(Typing.pageRange(count:0,selected:0,size:5)==0..<0)
assert(Typing.pageRange(count:12,selected:6,size:5)==5..<10)
assert(Typing.pageRange(count:12,selected:11,size:5)==10..<12)
assert(Typing.nextPage(count:12,selected:11,size:5,direction:1)==10)
assert(Typing.nextPage(count:12,selected:6,size:5,direction:-1)==0)
assert(Typing.punctuation(".")=="。" && Typing.punctuation("?")=="？" && Typing.punctuation("A")==nil)
assert(Typing.speechLocale("es-ES")=="es-ES" && Typing.speechLocale("unexpected")=="zh-CN")
print("8 typing/settings migration checks passed.")

let mixed=["修复","图标","我喜欢学习英语","同步","设置"]
let layoutPages=CandidateLayout.pages(texts:mixed,preferredCount:5,fontSize:17)
assert(layoutPages==[0..<2,2..<3,3..<5])
assert(layoutPages.flatMap{Array($0)}==Array(mixed.indices))
assert(CandidateLayout.range(pages:layoutPages,selected:2)==2..<3)
assert(CandidateLayout.next(pages:layoutPages,selected:1,direction:1)==2)
assert(CandidateLayout.next(pages:layoutPages,selected:2,direction:1)==3)
assert(CandidateLayout.next(pages:layoutPages,selected:3,direction:-1)==2)
assert(CandidateLayout.next(pages:layoutPages,selected:0,direction:-1)==0)
assert(CandidateLayout.pages(texts:[],preferredCount:5,fontSize:17).isEmpty)
let narrow=CandidateLayout.pages(texts:Array(repeating:"测试",count:9),preferredCount:9,fontSize:17,maximumWidth:330)
assert(narrow==[0..<3,3..<6,6..<9])
assert(CandidateLayout.cellWidth(String(repeating:"字",count:100),fontSize:24)==480)
assert(CandidateLayout.gloss("  repair\n and\tfix  ",single:false)=="repair and fix")
assert(CandidateLayout.gloss(String(repeating:"🙂",count:70),single:false).count==32)
assert(CandidateLayout.gloss(String(repeating:"字",count:100),single:true).count==64)
print("13 adaptive candidate paging and bounded translation checks passed.")

assert(InputAvailability.evaluate(installed:false,recognized:false,enabled:false,currentIsLexi:false).state == .notInstalled)
assert(InputAvailability.evaluate(installed:true,recognized:false,enabled:false,currentIsLexi:false).state == .unrecognized)
assert(InputAvailability.evaluate(installed:true,recognized:true,enabled:false,currentIsLexi:false).state == .needsEnable)
assert(InputAvailability.evaluate(installed:true,recognized:true,enabled:true,currentIsLexi:false).state == .enabled)
assert(InputAvailability.evaluate(installed:true,recognized:true,enabled:true,currentIsLexi:true).state == .selected)
assert(InputAvailability.evaluate(installed:false,recognized:true,enabled:true,currentIsLexi:true).state == .notInstalled)
let unavailable=VoiceInput(capabilityProvider:{ _ in VoiceCapability(checked:true,onDevice:false,available:false) })
unavailable.start(locale:"ja-JP")
assert(unavailable.phase=="error" && !unavailable.busy && unavailable.status.contains("不会改用云服务"))
assert(!unavailable.capability.onDevice && unavailable.text.isEmpty)
assert(VoiceCapability(checked:true,onDevice:true,available:true).resourceText=="本地识别资源可用")
assert(VoiceCapability(checked:true,onDevice:true,available:false).resourceText.contains("暂不可用"))
print("10 availability/voice checks passed; no permissions requested, no microphone or network calls.")
var features=0
assert(migrated.fuzzy==0 && migrated.quickTools==nil && migrated.candidateRules==nil && migrated.fontSize==17);features += 1
var custom=Preferences();custom.fuzzyMask=255;custom.candidateFontSize=100
assert(custom.fuzzy==7 && custom.fontSize==24);features += 1
let a=Candidate(text:"你好",gloss:"hello",kind:"exact"), b=Candidate(text:"您好",gloss:"hello",kind:"exact")
custom.candidateRules=PersonalCandidates.setting([],code:"NH",mode:"pinyin",text:b.text,hidden:false)
assert(PersonalCandidates.apply([a,b],code:"nh",preferences:custom).first?.text==b.text);features += 1
assert(PersonalCandidates.apply([a,b],code:"nihao",preferences:custom).first?.text==a.text);features += 1
custom.mode="wubi";assert(PersonalCandidates.apply([a,b],code:"nh",preferences:custom).first?.text==a.text);features += 1
custom.mode="pinyin";custom.candidateRules=PersonalCandidates.setting(custom.candidateRules!,code:"nh",mode:"pinyin",text:b.text,hidden:true)
assert(PersonalCandidates.apply([a,b],code:"nh",preferences:custom).map(\.text)==[a.text]);features += 1
custom.candidateRules=PersonalCandidates.setting(custom.candidateRules!,code:"nh",mode:"pinyin",text:b.text,hidden:false)
assert(custom.candidateRules?.count==1 && custom.candidateRules?.first?.hidden==false);features += 1
assert(Typing.acceptsToolCharacter("2",buffer:"v500+",enabled:true) && !Typing.acceptsToolCharacter("2",buffer:"nihao",enabled:true));features += 1
assert(!Typing.acceptsToolCharacter("2",buffer:"v",enabled:false) && !Typing.isCalculation("vemoji"));features += 1
assert(Typing.isCalculation("v(2+3)*4") && Typing.acceptsToolCharacter("-",buffer:"v2",enabled:true));features += 1
let phraseData=try CommonPhrase.encode([CommonPhrase(code:"mail",text:"demo@example.invalid")])
assert(String(data:phraseData,encoding:.utf8)=="mail\tdemo@example.invalid\n");features += 1
for row in [CommonPhrase(code:"MAIL",text:"demo"),CommonPhrase(code:"demo",text:"bad\nline"),CommonPhrase(code:"demo",text:String(repeating:"字",count:200))] {
    do {_=try CommonPhrase.encode([row]);fatalError("Invalid phrase accepted")} catch {features += 1}
}
let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("lexi-features-"+UUID().uuidString+".tsv")
try CommonPhrase.encode([CommonPhrase(code:"mail",text:"demo@example.invalid")]).write(to:temporary)
let engine=Engine();try engine.phrases(temporary)
assert(engine.query("mail",Preferences()).first?.text=="demo@example.invalid");features += 1
assert(engine.query("v500+21",Preferences()).first?.text=="521");features += 1
try Data().write(to:temporary);try engine.phrases(temporary)
assert(engine.query("mail",Preferences()).isEmpty);features += 1
try FileManager.default.removeItem(at:temporary)
print("\(features) desktop feature integration checks passed; fixture phrases only, no user settings changed.")
var writingChecks=0
for action in WritingAction.allCases {
    let r=try WritingAction.makeRequest("嗯，周五，不，是周六下午三点开会。",preferences:p,key:"test-only",action:action,style:"formal")
    let payload=try JSONSerialization.jsonObject(with:r.httpBody!) as! [String:Any]
    let messages=payload["messages"] as! [[String:String]]
    assert(messages.count==2 && messages[1]["content"]=="嗯，周五，不，是周六下午三点开会。" && r.timeoutInterval==30)
    writingChecks += 1
}
for text in ["",String(repeating:"字",count:4001)] {
    do {_=try WritingAction.makeRequest(text,preferences:p,key:"test-only",action:.tidy,style:"natural");fatalError("Invalid writing accepted")} catch {writingChecks += 1}
}
do {_=try WritingAction.makeRequest("原文",preferences:Preferences(),key:"test-only",action:.tidy,style:"natural");fatalError("Disabled cloud accepted")} catch {writingChecks += 1}
var noLanguage=p;noLanguage.language="off"
do {_=try WritingAction.makeRequest("原文",preferences:noLanguage,key:"test-only",action:.translate,style:"natural");fatalError("Translation without language accepted")} catch {writingChecks += 1}
assert(SpeechTerms.sanitized([" 词伴开源版 ","词伴开源版","","bad\nterm",String(repeating:"a",count:41)])==["词伴开源版"]);writingChecks += 1
assert(SpeechTerms.sanitized((1...120).map{"term\($0)"}).count==100);writingChecks += 1
var terms=p;terms.speechTerms=["词伴开源版","NetPlanner"]
let spelling=try WritingAction.makeRequest("固定测试原文",preferences:terms,key:"test-only",action:.tidy,style:"natural")
let spellingPayload=try JSONSerialization.jsonObject(with:spelling.httpBody!) as! [String:Any]
assert((spellingPayload["messages"] as! [[String:String]])[0]["content"]!.contains("NetPlanner"));writingChecks += 1
let writingOutput=try WritingAction.decode(data,response:success)
assert(writingOutput=="hello");writingChecks += 1
for invalid in [Data("{}".utf8),Data(#"{"choices":[{"message":{"content":" "}}]}"#.utf8)] {
    do {_=try WritingAction.decode(invalid,response:success);fatalError("Invalid AI response accepted")} catch {writingChecks += 1}
}
print("\(writingChecks) AI writing/voice vocabulary contract checks passed; no microphone, network or real credentials.")
var frequencyChecks=0
assert(migrated.frequencyRanking==nil && !(migrated.syncEnabled ?? false) && migrated.syncFolder==nil);frequencyChecks += 1
let historyFixture=FileManager.default.temporaryDirectory.appendingPathComponent("lexi-frequency-"+UUID().uuidString,isDirectory:true)
try FileManager.default.createDirectory(at:historyFixture,withIntermediateDirectories:true)
let sourceFixture=historyFixture.appendingPathComponent("dictionary.tsv")
try Data("先\txian\t\tfirst\t\t\t10000\ttest\n西安\txi an\t\tXi'an\t\t\t1\ttest\n".utf8).write(to:sourceFixture)
let adaptive=Engine();adaptive.historyURL=historyFixture.appendingPathComponent("usage.tsv");try adaptive.load(sourceFixture)
var local=Preferences();local.language="off"
let originalOrder=adaptive.query("xian",local)
assert(originalOrder.first?.text=="先" && !FileManager.default.fileExists(atPath:adaptive.historyURL!.path));frequencyChecks += 1
let chosenCity=originalOrder.first{$0.text=="西安"}!
try adaptive.recordSelection(chosenCity,code:"xian",preferences:local)
assert(adaptive.query("xian",local).first?.text=="西安");frequencyChecks += 1
let restored=Engine();restored.historyURL=adaptive.historyURL;try restored.load(sourceFixture)
assert(restored.query("xian",local).first?.text=="西安");frequencyChecks += 1
local.candidateRules=[CandidateRule(code:"xian",mode:"pinyin",text:"先",hidden:false)]
assert(restored.query("xian",local).first?.text=="先");frequencyChecks += 1
local.candidateRules=[CandidateRule(code:"xian",mode:"pinyin",text:"西安",hidden:true)]
assert(restored.query("xian",local).map(\.text)==["先"]);frequencyChecks += 1
local.candidateRules=nil;local.frequencyRanking=false
let bytesBefore=try Data(contentsOf:adaptive.historyURL!)
assert(restored.query("xian",local).first?.text=="先");frequencyChecks += 1
try restored.recordSelection(chosenCity,code:"xian",preferences:local)
let bytesAfter=try Data(contentsOf:adaptive.historyURL!)
assert(bytesBefore==bytesAfter);frequencyChecks += 1
try restored.clearHistory();local.frequencyRanking=true
assert(adaptive.query("xian",local).first?.text=="先");frequencyChecks += 1
try FileManager.default.removeItem(at:historyFixture)
print("\(frequencyChecks) Mac word-frequency integration checks passed; no real user history recorded.")
let syncChecks=try runSyncChecks()
print("\(syncChecks) folder-sync fixture checks passed; no iCloud, NAS or user sync folder modified.")
