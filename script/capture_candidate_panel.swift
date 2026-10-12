import AppKit
import ScreenCaptureKit

// Only captures this project's candidate popup while its disposable test is active.
// Never requests permission or saves a desktop/application-client screenshot.
@main struct CaptureCandidate {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard CommandLine.arguments.count==2,CGPreflightScreenCaptureAccess() else {print("Candidate capture unavailable; permission not requested");exit(1)}
        let output=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        guard output.deletingLastPathComponent().path==root.appendingPathComponent("build/system-test").path else {exit(2)}
        let fixture=root.appendingPathComponent("build/system-test/fixture-state.json")
        let before=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture)) as! [String:Any]
        guard before["active"] as? Bool == true,before["keyWindow"] as? Bool == true,before["marked"] as? Bool == true,
              let code=before["text"] as? String,["xiufu","woxihuanxuexiyingyu"].contains(code) else {exit(2)}
        let bundle=root.lastPathComponent=="LexiIME-Open" ? "local.inputmethod.lexiime.open":"local.inputmethod.lexiime"
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard let window=content.windows.first(where:{$0.owningApplication?.bundleIdentifier==bundle && $0.title=="词伴候选" && $0.frame.width<=650 && $0.frame.height<=300}) else {print("Own candidate popup not found");exit(1)}
        let filter=SCContentFilter(desktopIndependentWindow:window)
        let config=SCStreamConfiguration();config.width=Int(window.frame.width*2);config.height=Int(window.frame.height*2);config.showsCursor=false;config.ignoreShadowsSingleWindow=true
        let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
        let after=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture)) as! [String:Any]
        guard after["active"] as? Bool == true,after["keyWindow"] as? Bool == true,after["marked"] as? Bool == true,after["text"] as? String==code else {print("Test focus changed; screenshot discarded");exit(2)}
        let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!
        try data.write(to:output)
        print("Saved only the candidate popup from the disposable test")
    }
}
