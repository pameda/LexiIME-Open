import Foundation
import Carbon

// A read-only snapshot. Neither registration return codes nor file presence
// alone mean the input source can actually be selected.
struct InputAvailability: Equatable {
    enum State { case notInstalled, unrecognized, needsEnable, enabled, selected }
    let state: State
    var heading: String {
        switch state {
        case .notInstalled: return "尚未安装系统输入组件"
        case .unrecognized: return "系统尚未完整识别词伴开源版"
        case .needsEnable: return "已安装，等待启用"
        case .enabled: return "已启用，尚未切换到词伴开源版"
        case .selected: return "系统当前选中了词伴开源版"
        }
    }
    var detail: String {
        switch state {
        case .notInstalled: return "可以先使用下方试用区。安装系统输入组件后，再到键盘设置中添加词伴开源版。"
        case .unrecognized: return "组件文件已存在，但系统输入法列表还未完整识别它。请检查键盘设置；本开发版仍在验证启用问题。"
        case .needsEnable: return "打开键盘设置 → 文字输入 → 编辑 → 添加，选择词伴开源版。"
        case .enabled: return "从系统输入法菜单选择词伴开源版，然后到空白文档试试 nihao。"
        case .selected: return "请在空白文档输入 nihao 并按空格，确认实际输出你好。当前选中状态不能代替打字验证。"
        }
    }
    static func evaluate(installed: Bool, recognized: Bool, enabled: Bool, currentIsLexi: Bool) -> InputAvailability {
        guard installed else { return InputAvailability(state:.notInstalled) }
        guard recognized else { return InputAvailability(state:.unrecognized) }
        guard enabled else { return InputAvailability(state:.needsEnable) }
        return InputAvailability(state:currentIsLexi ? .selected : .enabled)
    }
    static func inspect() -> InputAvailability {
        let fm=FileManager.default
        let candidates=[fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods/LexiIME-Open Input.app"),URL(fileURLWithPath:"/Library/Input Methods/LexiIME-Open Input.app")]
        let installed=candidates.contains { fm.fileExists(atPath:$0.appendingPathComponent("Contents/Info.plist").path) }
        let bundleID="local.inputmethod.lexiime.open"
        let modeID=bundleID+".pinyin"
        let filter=[kTISPropertyBundleID as String:bundleID] as CFDictionary
        var recognized=false, enabled=false, parentEnabled=false
        if let list=TISCreateInputSourceList(filter,true)?.takeRetainedValue() as? [TISInputSource] {
            for source in list {
                if string(source,kTISPropertyInputSourceID)==bundleID { parentEnabled=boolean(source,kTISPropertyInputSourceIsEnabled) }
                let valid=string(source,kTISPropertyInputSourceID)==modeID && boolean(source,kTISPropertyInputSourceIsSelectCapable) && string(source,kTISPropertyInputSourceCategory)==(kTISCategoryKeyboardInputSource as String)
                recognized = recognized || valid
                enabled = enabled || (valid && boolean(source,kTISPropertyInputSourceIsEnabled))
            }
        }
        let current=TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let currentIsLexi=current.map { string($0,kTISPropertyInputSourceID)==modeID } ?? false
        return evaluate(installed:installed,recognized:recognized,enabled:enabled && parentEnabled,currentIsLexi:currentIsLexi)
    }
    private static func string(_ source:TISInputSource,_ property:CFString) -> String? {
        guard let value=TISGetInputSourceProperty(source,property) else {return nil}
        let object=Unmanaged<CFTypeRef>.fromOpaque(value).takeUnretainedValue()
        return object as? String
    }
    private static func boolean(_ source:TISInputSource,_ property:CFString) -> Bool {
        guard let value=TISGetInputSourceProperty(source,property) else {return false}
        let object=Unmanaged<CFTypeRef>.fromOpaque(value).takeUnretainedValue()
        return (object as? NSNumber)?.boolValue ?? false
    }
}
