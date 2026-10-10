import AppKit
import SwiftUI
import Speech
import AVFoundation

struct VoiceCapability {
    var checked = false
    var onDevice = false
    var available = false
    var speechPermission = "未检查"
    var microphonePermission = "未检查"
    var resourceText: String { !checked ? "正在检查本地语言资源…" : !onDevice ? "当前语言缺少本地识别支持，请更换说话语言。" : available ? "本地识别资源可用" : "已支持本地识别，语音服务暂不可用。" }
    static func inspect(locale:String) -> VoiceCapability {
        let recognizer=SFSpeechRecognizer(locale:Locale(identifier:Typing.speechLocale(locale)))
        let speech:String
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech="已允许"
        case .denied: speech="已拒绝"
        case .restricted: speech="系统限制"
        case .notDetermined: speech="尚未询问"
        @unknown default: speech="未知"
        }
        let microphone:String
        switch AVCaptureDevice.authorizationStatus(for:.audio) {
        case .authorized: microphone="已允许"
        case .denied: microphone="已拒绝"
        case .restricted: microphone="系统限制"
        case .notDetermined: microphone="尚未询问"
        @unknown default: microphone="未知"
        }
        return VoiceCapability(checked:true,onDevice:recognizer?.supportsOnDeviceRecognition ?? false,available:recognizer?.isAvailable ?? false,speechPermission:speech,microphonePermission:microphone)
    }
}

// Audio is never written to disk. Recognition is required to stay on device.
// Each window/session owns its recognizer so another field cannot receive a result.
final class VoiceInput: ObservableObject {
    @Published var text = ""
    @Published var status = "点击开始后才会使用麦克风。"
    @Published private(set) var phase = "idle"
    @Published private(set) var capability = VoiceCapability()
    var busy: Bool { ["authorizing","listening","finishing"].contains(phase) }
    var listening: Bool { phase == "listening" }
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var deadline: DispatchWorkItem?
    private var token = UUID()
    private var tapInstalled = false
    private let capabilityProvider: (String) -> VoiceCapability
    init(capabilityProvider: @escaping (String) -> VoiceCapability = { VoiceCapability.inspect(locale:$0) }) {
        self.capabilityProvider=capabilityProvider
    }

    func refreshCapability(locale:String) { capability=capabilityProvider(locale) }
    func start(locale: String, terms: [String] = []) {
        guard !busy else { return }
        refreshCapability(locale:locale)
        guard capability.onDevice else { fail("当前语言缺少本地识别支持，请更换说话语言。不会改用云服务。");return }
        cancel();text="";phase="authorizing";status="正在检查语音和麦克风权限…"
        let current=token
        Task { @MainActor [weak self] in
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning:$0) }
            }
            guard let self, self.token==current else { return }
            guard speech == .authorized else { self.fail("语音识别未获授权，请在系统设置 → 隐私与安全性中允许词伴开源版。");return }
            let microphone = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for:.audio) { continuation.resume(returning:$0) }
            }
            guard self.token==current else { return }
            guard microphone else { self.fail("麦克风未获授权，请在系统设置 → 隐私与安全性中允许词伴开源版。");return }
            self.refreshCapability(locale:locale)
            self.begin(locale:Typing.speechLocale(locale),terms:SpeechTerms.sanitized(terms),token:current)
        }
    }
    private func begin(locale: String, terms: [String], token current: UUID) {
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:locale)), recognizer.supportsOnDeviceRecognition else {
            fail("系统尚不支持此语言的本地语音识别。请安装系统语言资源或更换语言。");return
        }
        guard recognizer.isAvailable else { fail("本地语音识别暂不可用，请稍后重试。");return }
        self.recognizer=recognizer
        let audio=AVAudioEngine(), request=SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true
        request.contextualStrings=terms
        if #available(macOS 13.0, *) { request.addsPunctuation=true }
        request.taskHint = .dictation
        let input=audio.inputNode, format=input.outputFormat(forBus:0)
        guard format.sampleRate>0, format.channelCount>0 else { fail("没有可用的麦克风，请检查声音输入设备。");return }
        self.engine=audio;self.request=request
        recognition=recognizer.recognitionTask(with:request) { [weak self] result,error in
            DispatchQueue.main.async {
                guard let self, self.token==current else { return }
                if let result { self.text=String(result.bestTranscription.formattedString.prefix(4000)) }
                if result?.isFinal == true {
                    self.complete(message:self.text.isEmpty ? "没有识别到文字，可以重新开始。" : "识别完成，请检查后使用。")
                } else if error != nil {
                    self.complete(message:self.text.isEmpty ? "未能完成本地识别，请检查语言资源和输入设备。" : "识别已停止，已保留预览文字。")
                }
            }
        }
        input.installTap(onBus:0,bufferSize:1024,format:format) { buffer,_ in request.append(buffer) }
        tapInstalled=true
        do {
            audio.prepare();try audio.start();phase="listening";status="正在聆听 · 最长 60 秒 · 本地识别"
            let timeout=DispatchWorkItem { [weak self] in if self?.token==current { self?.stop() } }
            deadline=timeout;DispatchQueue.main.asyncAfter(deadline:.now()+60,execute:timeout)
        } catch { fail("麦克风启动失败，请检查输入设备后重试。") }
    }
    private func releaseMicrophone() {
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus:0);tapInstalled=false }
        engine=nil
    }
    func stop() {
        guard listening else { return }
        deadline?.cancel();releaseMicrophone();request?.endAudio()
        phase="finishing";status="正在完成识别…"
        let current=token
        let timeout=DispatchWorkItem { [weak self] in
            guard let self, self.token==current else { return }
            self.complete(message:self.text.isEmpty ? "没有识别到文字，可以重新开始。" : "已停止，请检查预览文字。")
        }
        deadline=timeout;DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:timeout)
    }
    private func complete(message: String) {
        token=UUID();deadline?.cancel();deadline=nil;releaseMicrophone()
        recognition?.cancel();recognition=nil;recognizer=nil;request=nil;phase="idle";status=message
    }
    private func fail(_ message: String) { complete(message:message);phase="error" }
    func cancel() { complete(message:"已取消，麦克风已关闭。");text="" }
    deinit { deadline?.cancel();recognition?.cancel();engine?.stop();if tapInstalled { engine?.inputNode.removeTap(onBus:0) } }
}

struct VoiceView: View {
    @ObservedObject var voice: VoiceInput
    @ObservedObject var store = Store.shared
    let use: (String) -> Void
    let useTitle: String
    var editable = true
    @State private var termDraft=""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("语音输入",systemImage:"mic.fill").font(.title2.bold())
            Text(editable ? "选择说话语言，开始后讲话。识别文字可以修改，确认后再使用。" : "选择说话语言，开始后讲话。检查预览，再插入当前输入位置。").foregroundStyle(.secondary)
            Picker("说话语言",selection:Binding(get:{ Typing.speechLocale(store.preferences.speechLocale) },set:{ store.preferences.speechLocale=$0;store.save() })) {
                Text("普通话").tag("zh-CN");Text("英语").tag("en-US");Text("日语").tag("ja-JP");Text("西班牙语").tag("es-ES")
            }.disabled(voice.busy)
            VStack(alignment:.leading,spacing:6) {
                Label(voice.capability.resourceText,systemImage:voice.capability.onDevice ? "checkmark.circle" : "exclamationmark.circle")
                Text("语音权限：\(voice.capability.speechPermission) · 麦克风：\(voice.capability.microphonePermission)").font(.caption).foregroundStyle(.secondary)
                Button("重新检查语音资源") { voice.refreshCapability(locale:Typing.speechLocale(store.preferences.speechLocale)) }.disabled(voice.busy)
            }.font(.callout)
            HStack {
                Button(voice.listening ? "停止录音" : "开始语音输入") {
                    if voice.listening { voice.stop() } else { voice.start(locale:Typing.speechLocale(store.preferences.speechLocale),terms:store.preferences.speechTerms ?? []) }
                }.disabled((voice.busy && !voice.listening) || (voice.capability.checked && !voice.capability.onDevice))
                Button("取消并清空") { voice.cancel() }
                if voice.busy { ProgressView().controlSize(.small) }
            }
            Text(voice.status).font(.callout).foregroundStyle(.secondary)
            if editable {
                TextEditor(text:$voice.text).font(.body).frame(minHeight:160,maxHeight:260).disabled(voice.busy)
            } else {
                ScrollView { Text(voice.text.isEmpty ? "识别文字将在这里出现…" : voice.text).frame(maxWidth:.infinity,alignment:.leading).padding(12) }
                    .frame(height:180).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8))
            }
            Button(useTitle) { let text=voice.text.trimmingCharacters(in:.whitespacesAndNewlines);voice.cancel();use(text) }
                .disabled(voice.busy || voice.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            if !voice.busy {
                WritingView(source:voice.text,use:{ text in if !editable {voice.cancel()};use(text) },useTitle:editable ? "复制 AI 处理结果" : "插入 AI 处理结果")
            }
            if editable {
                GroupBox("个人语音术语") {
                    VStack(alignment:.leading,spacing:10) {
                        Text("每行一个名字或短词，最多 100 个。用于本地识别提示；使用上方 AI 时也会作为拼写参考发送。效果依赖识别服务，并不保证正确。").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text:$termDraft).frame(height:80).disabled(voice.busy)
                        Button("保存术语") {store.preferences.speechTerms=SpeechTerms.sanitized(termDraft.components(separatedBy:.newlines));store.save();termDraft=(store.preferences.speechTerms ?? []).joined(separator:"\n")}.disabled(voice.busy)
                    }.padding(8)
                }
            }
            Label("仅本地识别 · 不保存录音 · 不自动发送给 AI",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
            Text("可用语言依赖系统的本地识别资源。首次授权后，如窗口已关闭，请重新打开语音输入。").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
        .onAppear { voice.refreshCapability(locale:Typing.speechLocale(store.preferences.speechLocale));termDraft=(store.preferences.speechTerms ?? []).joined(separator:"\n") }
        .onChange(of:store.preferences.speechLocale) { value in if !voice.busy {voice.refreshCapability(locale:Typing.speechLocale(value))} }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in if !voice.busy {voice.refreshCapability(locale:Typing.speechLocale(store.preferences.speechLocale))} }
        .onDisappear { voice.cancel() }
    }
}

final class VoicePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
