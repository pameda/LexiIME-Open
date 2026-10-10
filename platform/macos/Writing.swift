import SwiftUI
import AppKit

final class WritingPreview: ObservableObject {
    @Published private(set) var result = ""
    @Published private(set) var status = ""
    @Published private(set) var busy = false
    private var generation = 0
    private var task: Task<Void,Never>?
    func reset() {
        generation += 1;task?.cancel();task=nil;result="";status="";busy=false
    }
    func run(_ source: String, preferences: Preferences, action: WritingAction, style: String) {
        reset();busy=true;status="正在处理，原文保留…"
        let current=generation
        task=Task { @MainActor [weak self] in
            do {
                let output=try await WritingAction.perform(source,preferences:preferences,action:action,style:style)
                guard let self, !Task.isCancelled, self.generation==current else {return}
                self.result=output;self.status="AI 参考结果，请核对事实和措辞。";self.busy=false
            } catch {
                guard let self, !Task.isCancelled, self.generation==current else {return}
                self.status="处理失败：" + error.localizedDescription;self.busy=false
            }
        }
    }
    deinit {task?.cancel()}
}

struct WritingView: View {
    let source: String
    let use: (String) -> Void
    let useTitle: String
    @ObservedObject var store=Store.shared
    @StateObject private var preview=WritingPreview()
    @State private var action=WritingAction.tidy
    @State private var style="natural"
    var body: some View {
        GroupBox("AI 文字处理 · 可选") {
            VStack(alignment:.leading,spacing:12) {
                Text("仅点击发送时，才把上方文字与个人术语发送到你配置的 API。原文保留，确认结果后再使用；可能产生费用。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("处理方式",selection:$action) {ForEach(WritingAction.allCases) {item in Text(item.title).tag(item)}}
                if action == .translate {
                    Picker("翻译目标",selection:$store.preferences.language) {
                        Text("英语").tag("en");Text("日语").tag("ja");Text("西班牙语").tag("es")
                    }.onChange(of:store.preferences.language) { _ in store.save() }
                }
                if action == .polish {
                    Picker("表达语气",selection:$style) {Text("自然").tag("natural");Text("正式").tag("formal");Text("友好").tag("friendly")}
                }
                if !store.preferences.cloudEnabled {Text("先在「云端辅助」保存个人 API 并开启主动发送。离线转写仍可单独使用。").font(.caption).foregroundStyle(.secondary)}
                HStack {
                    Button("发送这段文字给个人 API（可能收费）") {preview.run(source,preferences:store.preferences,action:action,style:style)}
                        .disabled(preview.busy || !store.preferences.cloudEnabled || source.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || source.count>4000 || (action == .translate && store.preferences.language == "off"))
                    if preview.busy {Button("取消请求") {preview.reset()};ProgressView().controlSize(.small)}
                }
                if !preview.status.isEmpty {Text(preview.status).font(.caption).foregroundStyle(.secondary)}
                if !preview.result.isEmpty {
                    ScrollView {Text(preview.result).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(10)}
                        .frame(maxHeight:180).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8))
                    Button(useTitle) {use(preview.result)}
                }
            }.padding(10)
        }
        .onChange(of:source) { _ in preview.reset() }
        .onChange(of:action) { _ in preview.reset() }
        .onChange(of:style) { _ in preview.reset() }
        .onChange(of:store.preferences.language) { _ in preview.reset() }
        .onChange(of:store.preferences.cloudEnabled) { _ in preview.reset() }
        .onDisappear {preview.reset()}
    }
}
