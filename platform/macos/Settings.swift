import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @State private var page = "开始"
    @State private var code = "nihao"
    @State private var draft = ""
    @State private var apiKey = ""
    @State private var cloudResult = ""
    @State private var busy = false
    @State private var clearWords = false
    @State private var availability = InputAvailability(state:.notInstalled)
    @State private var phraseCode = ""
    @State private var phraseText = ""
    @State private var toolCode = "v500+21"
    @State private var writingSource = ""
    @State private var clearFrequency = false
    private let syncTimer=Timer.publish(every:60,on:.main,in:.common).autoconnect()
    @StateObject private var voice = VoiceInput()
    private let pages = [("开始","sparkles"),("输入方案","keyboard"),("快捷工具","bolt"),("语音输入","mic"),("词库","books.vertical"),("词库同步","arrow.triangle.2.circlepath"),("学习记录","graduationcap"),("云端辅助","cloud")]
    init(initialPage: String = "开始") { _page=State(initialValue:initialPage) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "character.bubble.fill").font(.system(size: 30)).foregroundStyle(.teal)
                    VStack(alignment: .leading) { Text("词伴开源版").font(.title2.bold()); Text("LexiIME-Open · 开发预览").font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 24)
                ForEach(pages, id: \.0) { item in
                    Button { page = item.0; store.refreshWords() } label: {
                        Label(item.0, systemImage: item.1).frame(maxWidth: .infinity, alignment: .leading).padding(11)
                            .background(page == item.0 ? Color.teal.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("离线优先", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Text("0.1.1 · 原创示例词库").font(.caption2).foregroundStyle(.secondary)
            }.padding(20).frame(width: 180).background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch page {
                        case "输入方案": inputSettings
                        case "快捷工具": quickTools
                        case "词库同步": synchronization
                        case "词库": dictionaries
                        case "学习记录": learning
                        case "云端辅助": cloud
                        case "语音输入": VoiceView(voice:voice,use:{ text in
                            NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
                            store.status="识别文字已复制，可粘贴到需要的地方。"
                        },useTitle:"复制识别文字")
                        default: welcome
                        }
                    }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack { Text(store.status.isEmpty ? "你的输入，留在本机。云端请求仅在主动使用时发出。" : store.status).font(.caption).foregroundStyle(.secondary); Spacer() }.padding(14)
            }
        }.frame(minWidth: 880, minHeight: 640)
        .tint(.teal)
        .onAppear { availability=InputAvailability.inspect();store.syncNow() }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in availability=InputAvailability.inspect();store.syncNow() }
        .onReceive(syncTimer) { _ in store.syncNow() }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.willCloseNotification)) { _ in voice.cancel() }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("LexiOpenVoice"))) { _ in page="语音输入" }
    }
    func title(_ heading: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(heading).font(.system(size: 28, weight: .bold)); Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
    var languagePicker: some View {
        Picker("学习语言", selection: $store.preferences.language) {
            Text("英语 · English").tag("en");Text("日语 · 日本語").tag("ja");Text("西班牙语 · Español").tag("es");Text("关闭译词").tag("off")
        }.onChange(of: store.preferences.language) { _ in store.save() }
    }
    var welcome: some View {
        Group {
            title("每次打字，多认识一个词。", "先选一门语言，在下方试试候选词旁的释义。")
            GroupBox {
                VStack(alignment:.leading,spacing:10) {
                    Label(availability.heading,systemImage:availability.state == .selected ? "checkmark.circle" : "keyboard").font(.headline)
                    Text(availability.detail).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("打开键盘设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
                        Button("重新检查") { availability=InputAvailability.inspect() }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
            }
            languagePicker
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Label("应用内试用 · 不影响其他应用", systemImage: "keyboard"); Spacer(); Text("\(store.engine.count) 条词库记录").font(.caption).foregroundStyle(.secondary) }
                    TextField("用英文键盘输入 nihao / nh / woqubeijing", text: $code).textFieldStyle(.roundedBorder)
                        .onSubmit { if let item = store.engine.query(code, store.preferences).first { select(item) } }
                        .onChange(of: code) { value in if value.count > 64 { code = String(value.prefix(64)) }; cloudResult = "" }
                    let candidates = store.engine.query(code, store.preferences)
                    if candidates.isEmpty { Text("未收录这个编码。可尝试 nihao，或导入专属词库。").foregroundStyle(.secondary).padding(.vertical, 12) }
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { i, item in
                        Button { select(item) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(i+1)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 18)
                                Text(item.text).font(.title3.weight(.medium)).frame(minWidth: 90, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) { Text(item.gloss.isEmpty ? (["tool","phrase","emoji"].contains(item.kind) || store.preferences.language == "off" ? "" : "未收录译词") : item.gloss); Text(item.label).font(.caption2).foregroundStyle(.secondary) }
                                Spacer()
                                Image(systemName: "return").foregroundStyle(.tertiary)
                            }.padding(10).background(i == 0 ? Color.teal.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("固定为此编码首选") { store.candidateRule(item,code:code,hidden:false) }
                            Button("隐藏此编码的候选") { store.candidateRule(item,code:code,hidden:true) }
                        }
                    }
                    if !draft.isEmpty { Divider(); Text(draft).textSelection(.enabled); Button("清空试用文本") { draft = "" } }
                }.padding(10)
            }
        }
    }
    func select(_ item: Candidate) { draft += item.text;store.recordSelection(item,code:code);code = "" }
    var inputSettings: some View {
        Group {
            title("按你的习惯输入。", "全拼、简拼与纠错共用离线引擎；双拼和五笔能力取决于已加载的方案与码表。")
            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("输入方案", selection: $store.preferences.mode) {
                        Text("全拼（含简拼）").tag("pinyin");Text("简拼").tag("initials");Text("自定义双拼").tag("double");Text("五笔 86 码表").tag("wubi")
                    }.onChange(of: store.preferences.mode) { _ in store.save() }
                    Toggle("全拼拼写纠错", isOn: $store.preferences.correction).onChange(of: store.preferences.correction) { _ in store.save() }
                    Toggle("按本机选词频率优先排序",isOn:Binding(get:{store.preferences.frequencyRanking ?? true},set:{store.preferences.frequencyRanking=$0;store.save();store.frequencyRevision += 1}))
                    Text("经常选中的短字词逐渐排到前面，各输入方案共用；手动置顶仍优先。只记已选词，不记原始按键或长句，词频不参与云同步。关闭后停止记录并恢复默认顺序。").font(.caption).foregroundStyle(.secondary)
                    Button("清空本机词频记录") {clearFrequency=true}
                    ForEach(Array(["z / zh、c / ch、s / sh","n / l","an / ang、en / eng、in / ing"].enumerated()),id:\.offset) { i,label in
                        Toggle("模糊拼音 · " + label,isOn:Binding(get:{store.preferences.fuzzy & (1 << i) != 0},set:{ enabled in
                            store.preferences.fuzzyMask=enabled ? store.preferences.fuzzy | (1 << i) : store.preferences.fuzzy & ~(1 << i);store.save()
                        }))
                    }
                    Toggle("中文标点",isOn:Binding(get:{ store.preferences.chinesePunctuation ?? true },set:{ store.preferences.chinesePunctuation=$0;store.save() }))
                    Picker("每页候选数",selection:Binding(get:{ store.preferences.pageSize },set:{ store.preferences.candidatePageSize=$0;store.save() })) {
                        Text("5 个").tag(5);Text("9 个").tag(9)
                    }
                    Picker("候选文字大小",selection:Binding(get:{store.preferences.fontSize},set:{store.preferences.candidateFontSize=$0;store.save()})) {
                        Text("小 · 14").tag(14);Text("标准 · 17").tag(17);Text("大 · 20").tag(20);Text("特大 · 24").tag(24)
                    }
                    Text("双拼内置 10 个演示音节，可试 nihc → 你好。五笔只有少量演示编码，可试 wqiy → 你；完整使用需导入有授权的码表。").font(.callout).foregroundStyle(.secondary)
                    Button("导入自定义双拼表…") { chooseImport(layout: true) }
                }.padding(12)
            }
            GroupBox("系统输入按键") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("空格选中 · 数字选本页候选 · ↑↓ 切换候选")
                    Text("− / = 或 Page Up / Down 翻页 · 单按 Shift 切换中英文")
                    Text("Control + Shift + Space 打开语音预览，也可使用输入法菜单。")
                    Text("Enter 输出原编码 · Esc 取消 · Backspace 删除")
                    Text("Command / Control / Option 快捷键交给应用处理。")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            Text("组句为词典分词组合，显示的是逐词释义；多义词不保证匹配上下文。成熟整句语言模型、完整双拼方案与大规模五笔词库尚待接入。").font(.callout).foregroundStyle(.secondary)
        }.confirmationDialog("清空本机词频，恢复默认排序？",isPresented:$clearFrequency) {Button("清空词频",role:.destructive) {store.clearFrequency()}}
    }
    var synchronization: some View {
        Group {
            title("个人词库，随设备同行。", "通过你选择的本地同步文件夹交换自定义词库和常用语，默认关闭。")
            GroupBox {
                VStack(alignment:.leading,spacing:14) {
                    Picker("同步位置类型",selection:Binding(get:{store.preferences.syncProvider ?? "icloud"},set:{store.preferences.syncProvider=$0;store.save()})) {
                        Text("iCloud Drive").tag("icloud");Text("群晖 Synology Drive").tag("synology");Text("其他同步文件夹").tag("folder")
                    }.disabled(store.preferences.syncEnabled ?? false)
                    Text("请先在系统或官方客户端中配置好同步，再选择已同步的文件夹。这个选项只标记你选择的服务，词伴开源版不登录账号或设置 NAS。").font(.caption).foregroundStyle(.secondary)
                    Text(store.preferences.syncFolder ?? "尚未选择文件夹").textSelection(.enabled).font(.callout)
                    Button("选择同步文件夹…") {chooseSyncFolder()}.disabled((store.preferences.syncEnabled ?? false) || store.syncBusy)
                    Toggle("启用个人词库同步",isOn:Binding(get:{store.preferences.syncEnabled ?? false},set:{enabled in
                        store.preferences.syncEnabled=enabled
                        if enabled && store.preferences.syncDeviceID == nil {store.preferences.syncDeviceID=UUID().uuidString.lowercased()}
                        store.save()
                        if enabled {store.syncNow()} else {store.stopSync()}
                    })).disabled((store.preferences.syncFolder ?? "").isEmpty)
                    Text("启用后，保存/导入、打开设置以及设置应用运行期间每分钟交换一次。关闭后停止后续交换，已有同步副本保留。词库和常用语按明文文件存储，请使用私有文件夹。云端传输和另一台设备接收由同步客户端负责。").font(.caption).foregroundStyle(.secondary)
                    HStack {Button(store.syncBusy ? "正在同步…" : "立即同步") {store.syncNow()}.disabled(!(store.preferences.syncEnabled ?? false) || store.syncBusy)
                        if store.syncBusy {ProgressView().controlSize(.small)}
                    }
                    Text(store.syncStatus).font(.callout).foregroundStyle(.secondary)
                }.padding(10)
            }
            GroupBox("同步范围") {
                VStack(alignment:.leading,spacing:8) {
                    Text("包括：自定义 TSV 词库、常用语输入码及内容。")
                    Text("留在本机：词频、学习记录、置顶/隐藏偏好、API 密钥、服务配置、语音术语及录音。")
                    Text("添加内容会合并；不同设备的同码常用语冲突需选择版本。本机移除只排除本机副本，不删除其他设备的内容。")
                    Button("恢复本机排除的同步内容") {
                        store.preferences.syncIgnoredDictionaries=[];store.preferences.syncIgnoredPhraseCodes=[];store.preferences.syncIgnoredVariants=[];store.save();store.syncNow()
                    }.disabled(store.syncBusy)
                }.font(.callout).padding(10).frame(maxWidth:.infinity,alignment:.leading)
            }
            ForEach(store.syncConflicts) { conflict in
                GroupBox("常用语冲突 · " + conflict.code) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("本机："+(store.phrases.first(where:{$0.code==conflict.code})?.text ?? "尚未设置"))
                        Text("另一设备："+conflict.text).textSelection(.enabled)
                        HStack {Button("保留本机") {store.resolveSync(conflict,useRemote:false)};Button("采用此版本") {store.resolveSync(conflict,useRemote:true)}}.disabled(store.syncBusy)
                    }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
        }
    }
    func chooseSyncFolder() {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false;panel.canCreateDirectories=true;panel.prompt="选择文件夹"
        if panel.runModal() == .OK,let url=panel.url {
            store.preferences.syncFolder=url.path;store.save();store.syncStatus="文件夹已选择，同步仍关闭。开启开关后才交换个人词库。"
        }
    }
    var quickTools: some View {
        Group {
            title("少打几次，表达更快。", "常用语、日期时间、计算和符号都在本机完成。")
            Toggle("日期、计算、符号与表情候选",isOn:Binding(get:{store.preferences.quickTools ?? true},set:{store.preferences.quickTools=$0;store.save()}))
            Text("试试 vdate（日期）、vtime（时间）、vsymbol（符号）、vemoji（表情）、v500+21 或 v(2+3)*4。全拼、双拼和五笔均可查询；系统候选用空格选中，计算输入的 Enter 选择结果。").font(.callout).foregroundStyle(.secondary)
            GroupBox("本地工具试用") {
                VStack(alignment:.leading,spacing:10) {
                    TextField("输入工具编码",text:$toolCode).textFieldStyle(.roundedBorder).onChange(of:toolCode) { value in if value.count>64 {toolCode=String(value.prefix(64))} }
                    let results=store.engine.query(toolCode,store.preferences)
                    if results.isEmpty {Text("没有可用结果；算式仅支持 + − * /、括号和小数。").foregroundStyle(.secondary)}
                    ForEach(results) { item in Text(item.text).textSelection(.enabled).font(.title3) }
                }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("自定义常用语") {
                VStack(alignment:.leading,spacing:12) {
                    Text("例如 dz → 一段常用地址，或 mail → 邮箱。保存后，在试用区输入对应编码即可选用。内容只存本机，不生成译词。")
                    TextField("输入码 · 1–32 个小写字母",text:$phraseCode).textFieldStyle(.roundedBorder)
                    TextField("常用语内容 · 不换行",text:$phraseText).textFieldStyle(.roundedBorder)
                    Button(store.phrases.contains(where:{$0.code==phraseCode}) ? "更新常用语" : "添加常用语") {
                        let rows=store.phrases.filter{$0.code != phraseCode} + [CommonPhrase(code:phraseCode,text:phraseText)]
                        store.savePhrases(rows)
                    }.disabled(phraseCode.isEmpty || phraseText.isEmpty)
                    ForEach(store.phrases) { row in
                        HStack { Text(row.code).font(.system(.body,design:.monospaced)).frame(width:80,alignment:.leading);Text(row.text).lineLimit(2);Spacer()
                            Button("编辑") {phraseCode=row.code;phraseText=row.text}
                            Button("移除") {store.savePhrases(store.phrases.filter{$0.id != row.id})}
                        }
                    }
                }.padding(10)
            }
            GroupBox("候选偏好") {
                VStack(alignment:.leading,spacing:10) {
                    Text("右键点击试用区或系统候选，可固定首选或隐藏。只对同一方案、同一输入码生效，不删除词库原文。")
                    if (store.preferences.candidateRules ?? []).isEmpty {Text("还没有设置候选偏好。").foregroundStyle(.secondary)}
                    ForEach(store.preferences.candidateRules ?? []) { rule in
                        HStack {Text(rule.code + " · " + rule.text);Spacer();Text(rule.hidden ? "已隐藏" : "已置顶").foregroundStyle(.secondary)
                            Button("恢复") {store.preferences.candidateRules?.removeAll{$0.id == rule.id};store.save()}
                        }
                    }
                }.padding(10)
            }
        }
    }
    var dictionaries: some View {
        Group {
            title("让词库贴近你的生活。", "内置四个原创示例包。导入文件会先校验，失败时保留现有词库。")
            ForEach(store.packs, id: \.path) { url in
                Toggle(isOn: Binding(get: { !store.preferences.disabledPacks.contains(url.lastPathComponent) }, set: { enabled in
                    if enabled { store.preferences.disabledPacks.removeAll { $0 == url.lastPathComponent } } else { store.preferences.disabledPacks.append(url.lastPathComponent) }
                    store.rebuild();store.save()
                })) { VStack(alignment: .leading) { Text(String(url.deletingPathExtension().lastPathComponent.dropFirst(3))).font(.headline);Text("随应用提供 · 原创示例 · 待专业审校").font(.caption).foregroundStyle(.secondary) } }.padding(10)
            }
            Divider()
            HStack { Button("导入 TSV 词库…") { chooseImport() }; Button("查看示例文件") { NSWorkspace.shared.activateFileViewerSelecting([store.bundled.appendingPathComponent("import-example.tsv")]) } }
            Text("UTF-8，8 列：汉字 / 分音节拼音 / 五笔 / 英语 / 日语 / 西班牙语 / 频率 / 领域。列之间用 Tab 分隔；五笔和译词可留空。单文件 ≤ 8 MB，合计 ≤ 50,000 条。").font(.callout).foregroundStyle(.secondary)
            ForEach(store.imports, id: \.path) { url in HStack { Label("自定义词库 · " + String(url.lastPathComponent.prefix(8)), systemImage: "doc.text");Spacer();Button("移除") { store.removeImport(url) } } }
        }
    }
    var learning: some View {
        Group {
            title("让遇见过的词，再见一次。", "记录已选中的短词及释义。记录只保存在本机，可随时关闭和清空。")
            Toggle("保存选词学习记录", isOn: $store.preferences.study).onChange(of: store.preferences.study) { _ in store.save() }
            HStack { Text("\(store.words.count) 个词条").font(.headline);Spacer();Button("刷新") { store.refreshWords() };Button("清空记录", role: .destructive) { clearWords = true } }
            if store.words.isEmpty { Label("选中带译词的候选后，会在这里出现。", systemImage: "leaf").foregroundStyle(.secondary).padding(.vertical, 25) }
            ForEach(store.words) { word in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(word.text).font(.headline);Text(word.gloss).foregroundStyle(.secondary) }
                    Spacer();Text("\(word.language.uppercased()) · \(word.count) 次").font(.caption)
                    Button(word.reviewed ? "已掌握 ✓" : "标为掌握") { if let i = store.words.firstIndex(where: { $0.id == word.id }) { store.words[i].reviewed.toggle();store.saveWords() } }
                }.padding(.vertical, 8)
            }
        }.confirmationDialog("清空本机全部学习记录？", isPresented: $clearWords) { Button("清空", role: .destructive) { store.words=[];store.saveWords() } }
    }
    var cloud: some View {
        Group {
            title("你的服务，你来选择。", "支持兼容 Chat Completions 的个人 API。默认关闭，不经过词伴开源版服务器。")
            Text("开启后，仅在点击明确的发送按钮时请求服务。候选译词每次最多 128 字；文字处理发送你输入或转写后预览的文字（最多 4000 字）及个人术语。不会读取周围文档。服务商可能收费，结果仅供参考。").font(.callout).foregroundStyle(.secondary)
            Toggle("允许主动请求时向个人服务发送文字", isOn: $store.preferences.cloudEnabled).onChange(of: store.preferences.cloudEnabled) { _ in store.save() }
            TextField("完整 HTTPS 地址，例如 https://你的服务/v1/chat/completions", text: $store.preferences.endpoint).textFieldStyle(.roundedBorder)
            TextField("模型名称", text: $store.preferences.model).textFieldStyle(.roundedBorder)
            SecureField("API Key（留空不会覆盖已保存的密钥）", text: $apiKey).textFieldStyle(.roundedBorder)
            HStack {
                Button("保存配置") {
                    do { if !apiKey.isEmpty { try KeyVault.save(apiKey);apiKey = "" };store.save() }
                    catch { store.status = error.localizedDescription }
                }
                Button("删除已存密钥") { do { try KeyVault.save(""); store.preferences.cloudEnabled=false;store.save();store.status="密钥已删除，云端辅助已关闭。" } catch { store.status=error.localizedDescription } }
            }
            Divider()
            Text("用固定词语「你好」验证你的配置，每次点击会发起一次请求。")
            Button(busy ? "正在请求…" : "请求译词 · 你好") {
                store.save();busy=true;cloudResult=""
                Task { @MainActor in
                    do { cloudResult = try await Cloud.translate("你好", preferences: store.preferences) }
                    catch { cloudResult = error.localizedDescription }
                    busy=false
                }
            }.disabled(busy || !store.preferences.cloudEnabled)
            if !cloudResult.isEmpty { Text(cloudResult).textSelection(.enabled).padding().background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }
            Divider()
            Text("文字处理试用").font(.headline)
            TextEditor(text:$writingSource).frame(height:140).onChange(of:writingSource) {text in if text.count>4000 {writingSource=String(text.prefix(4000))}}
            WritingView(source:writingSource,use:{text in NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string);store.status="AI 结果已复制，原文保留。"},useTitle:"复制 AI 处理结果")
            Label("密钥保存在 macOS 钥匙串；离线功能不需要密钥。", systemImage: "key.fill").font(.caption).foregroundStyle(.secondary)
        }
    }
    func chooseImport(layout: Bool = false) {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.tabSeparatedText,.plainText];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
        if panel.runModal() == .OK, let url=panel.url { store.importFile(url, layout: layout) }
    }
}
