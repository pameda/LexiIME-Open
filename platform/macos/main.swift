import AppKit
import SwiftUI
import InputMethodKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var status: NSStatusItem?
    var server: IMKServer?
    let inputMode = Bundle.main.object(forInfoDictionaryKey:"InputMethodConnectionName") != nil
    func applicationDidFinishLaunching(_ notification: Notification) {
        if inputMode {
            let logger=Logger(subsystem:"local.lexiime.open",category:"server")
            let expectedController=NSStringFromClass(LexiInputController.self)
            guard let connection=Bundle.main.object(forInfoDictionaryKey:"InputMethodConnectionName") as? String,
                  let identifier=Bundle.main.bundleIdentifier,
                  let controller=Bundle.main.object(forInfoDictionaryKey:"InputMethodServerControllerClass") as? String,
                  controller==expectedController, NSClassFromString(controller) != nil else {
                logger.error("InputMethodKit bundle configuration invalid; server not started")
                NSApp.terminate(nil);return
            }
            logger.notice("InputMethodKit controller class resolved: \(expectedController, privacy: .public)")
            server=IMKServer(name:connection,bundleIdentifier:identifier)
            logger.notice("InputMethodKit server started: \(self.server != nil, privacy: .public)")
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            let menu=NSMenu();let root=NSMenuItem();menu.addItem(root)
            let appMenu=NSMenu();root.submenu=appMenu
            appMenu.addItem(withTitle:"退出词伴开源版设置",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
            let edit=NSMenu(title:"编辑");let editItem=NSMenuItem(title:"编辑",action:nil,keyEquivalent:"");editItem.submenu=edit;menu.addItem(editItem)
            edit.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
            edit.addItem(withTitle:"复制",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
            edit.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
            edit.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
            NSApp.mainMenu=menu
            status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
            if let button=status?.button {
                let iconURL=Bundle.main.url(forResource:"menu",withExtension:"tiff")
                let icon=iconURL.flatMap { NSImage(contentsOf:$0) } ?? NSImage(systemSymbolName:"keyboard",accessibilityDescription:nil)
                icon?.size=NSSize(width:18,height:18);icon?.isTemplate=true
                button.title="";button.image=icon;button.imagePosition = .imageOnly
                button.toolTip="词伴开源版 · 设置与试用";button.setAccessibilityLabel("词伴开源版设置与试用")
                Logger(subsystem:"local.lexiime.open",category:"icon").notice("Status icon ready: bundled=\(iconURL != nil, privacy: .public), image=\(icon != nil, privacy: .public), template=\(icon?.isTemplate ?? false, privacy: .public), titleLength=\(button.title.count, privacy: .public)")
            }
            let statusMenu=NSMenu();let settings=statusMenu.addItem(withTitle:"打开设置与试用",action:#selector(showSettings),keyEquivalent:"");settings.target=self
            let voice=statusMenu.addItem(withTitle:"语音输入…",action:#selector(showVoice),keyEquivalent:"");voice.target=self
            statusMenu.addItem(.separator());statusMenu.addItem(withTitle:"退出设置",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"");status?.menu=statusMenu
            if CommandLine.arguments.contains("--icon-check") {return}
            let initial=CommandLine.arguments.contains("--voice") ? "语音输入" : CommandLine.arguments.contains("--sync") ? "词库同步" : CommandLine.arguments.contains("--tools") ? "快捷工具" : CommandLine.arguments.contains("--input") ? "输入方案" : "开始"
            showWindow(initialPage:initial)
        }
    }
    @objc func showSettings() { showWindow(initialPage:"开始") }
    @objc func showVoice() {
        showWindow(initialPage:"语音输入")
        NotificationCenter.default.post(name:Notification.Name("LexiOpenVoice"),object:nil)
    }
    private func showWindow(initialPage: String) {
        if window == nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:940,height:700),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            w.title="词伴开源版 · LexiIME-Open";w.contentView=NSHostingView(rootView:SettingsView(initialPage:initialPage));w.center();w.isReleasedWhenClosed=false;window=w
        }
        window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {
        // LaunchServices can send reopen before didFinishLaunching. Let the
        // initial launch create its requested page; later reopens reveal it.
        if !inputMode,window != nil {showSettings()}
        return true
    }
    static func openSettingsApp() {
        let system=URL(fileURLWithPath:"/Applications/LexiIME-Open.app")
        let user=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LexiIME-Open.app")
        let sibling=Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("LexiIME-Open.app")
        if let target=[system,user,sibling].first(where:{FileManager.default.fileExists(atPath:$0.path)}) { NSWorkspace.shared.open(target) }
    }
}
let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
withExtendedLifetime(delegate) { app.run() }
