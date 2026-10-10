import AppKit
import SwiftUI
import InputMethodKit
import Carbon
import os

struct CandidatePanelView: View {
    let code: String
    let items: [Candidate]
    let selected: Int
    let range: Range<Int>
    let fontSize: Int
    let choose: (Int) -> Void
    let preference: (Int,Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(code).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 8)
            if items.isEmpty { Text("未收录 · Enter 输出编码").foregroundStyle(.secondary).padding(8) }
            ForEach(Array(range), id: \.self) { i in
                let item=items[i]
                Button { choose(i) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i-range.lowerBound+1)").foregroundStyle(.secondary).frame(width: 12)
                        Text(item.text).font(.system(size: CGFloat(fontSize), weight: .medium)).frame(minWidth: 72, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.gloss).lineLimit(2)
                            if ["segments","ai","correction","fuzzy","phrase","tool","emoji"].contains(item.kind) { Text(item.label).font(.caption2).foregroundStyle(.secondary) }
                        }.foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected == i ? Color.teal.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                .contextMenu {
                    Button("固定为此编码首选") { preference(i,false) }
                    Button("隐藏此编码的候选") { preference(i,true) }
                }
            }
            if items.count>range.count { Text("\(range.lowerBound+1)–\(range.upperBound) / \(items.count) · − / = 翻页").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,8) }
        }.padding(8).frame(width: 430).background(.regularMaterial)
    }
}
@objc(LexiInputController)
final class LexiInputController: IMKInputController {
    private let logger=Logger(subsystem:"local.lexiime.open",category:"controller")
    private var buffer = ""
    private var items: [Candidate] = []
    private var selected = 0
    private var panel: NSPanel?
    private var cloudTask: Task<Void, Never>?
    private var generation = 0
    private var english = false
    private var shiftOnly = false
    private var voicePanel: VoicePanel?
    private var voice: VoiceInput?
    private let replacement = NSRange(location: NSNotFound, length: NSNotFound)
    override func activateServer(_ sender: Any!) { Store.shared.reload();logger.notice("Input session activated");super.activateServer(sender) }
    override func deactivateServer(_ sender: Any!) { shiftOnly=false;closeVoice();commitComposition(sender);logger.notice("Input session deactivated");super.deactivateServer(sender) }
    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue) }
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else { return false }
        Store.shared.reloadIfChanged()
        if IsSecureEventInputEnabled() { shiftOnly=false;closeVoice();reset(client, clearMarked: !buffer.isEmpty);return false }
        if event.type == .flagsChanged {
            if [56,60].contains(event.keyCode) {
                if event.modifierFlags.contains(.shift) {
                    shiftOnly=event.modifierFlags.intersection([.command,.control,.option,.capsLock]).isEmpty
                } else {
                    if shiftOnly { toggleLanguage(client) };shiftOnly=false
                }
            } else { shiftOnly=false }
            return false
        }
        guard event.type == .keyDown else {return false}
        shiftOnly=false
        let modifiers=event.modifierFlags.intersection([.command,.control,.option,.shift])
        if event.keyCode==49 && modifiers == [.control,.shift] { openVoice(nil);return true }
        if voicePanel != nil {closeVoice()}
        if !event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            if !buffer.isEmpty { commit(buffer, client: client) };return false
        }
        if english || event.modifierFlags.contains(.capsLock) { if !buffer.isEmpty {commit(buffer,client:client)};return false }
        let key = event.keyCode
        if let text=event.characters, Typing.acceptsToolCharacter(text,buffer:buffer,enabled:Store.shared.preferences.quickTools ?? true) {
            if buffer.count<64 {buffer += text;selected=0;refresh(client)}
            return true
        }
        if !buffer.isEmpty {
            switch key {
            case 53: reset(client, clearMarked: true);return true
            case 51: buffer.removeLast();refresh(client);return true
            case 36,76:
                if Typing.isCalculation(buffer), items.first?.kind == "tool" {choose(0,client:client)}
                else {commit(buffer,client:client)}
                return true
            case 49: choose(selected, client: client);return true
            case 125: selected=min(max(0,items.count-1),selected+1);show(client);return true
            case 126: selected=max(0,selected-1);show(client);return true
            case 116: selected=Typing.nextPage(count:items.count,selected:selected,size:Store.shared.preferences.pageSize,direction:-1);show(client);return true
            case 121: selected=Typing.nextPage(count:items.count,selected:selected,size:Store.shared.preferences.pageSize,direction:1);show(client);return true
            case 123,124: commit(buffer, client: client);return false
            default: break
            }
            if event.characters=="-" || event.characters=="=" {
                if event.characters=="=", Typing.isCalculation(buffer) {
                    if items.first?.kind == "tool" {choose(0,client:client)}
                    return true
                }
                selected=Typing.nextPage(count:items.count,selected:selected,size:Store.shared.preferences.pageSize,direction:event.characters=="-" ? -1 : 1);show(client);return true
            }
            let range=Typing.pageRange(count:items.count,selected:selected,size:Store.shared.preferences.pageSize)
            if let s=event.characters, let n=Int(s), n>0, n<=range.count { choose(range.lowerBound+n-1,client:client);return true }
        }
        guard let text=event.characters, text.count==1, let scalar=text.unicodeScalars.first else {
            if !buffer.isEmpty { commit(buffer,client:client) };return false
        }
        if (scalar.value>=97 && scalar.value<=122) || (scalar.value>=65 && scalar.value<=90) || (text=="'" && !buffer.isEmpty) {
            if buffer.count<64 {buffer += text.lowercased();selected=0;refresh(client)}
            return true
        }
        if !buffer.isEmpty { choose(selected,client:client) }
        if Store.shared.preferences.chinesePunctuation ?? true, let punctuation=Typing.punctuation(text) {
            client.insertText(punctuation,replacementRange:replacement);return true
        }
        return false
    }
    private func refresh(_ client: IMKTextInput) {
        generation += 1;cloudTask?.cancel()
        guard !buffer.isEmpty else { reset(client,clearMarked:true);return }
        items=Store.shared.engine.query(buffer,Store.shared.preferences);selected=min(selected,max(0,items.count-1))
        client.setMarkedText(buffer, selectionRange: NSRange(location:buffer.utf16.count,length:0), replacementRange:replacement)
        logger.debug("Composition updated; candidates: \(self.items.count,privacy:.public)")
        show(client)
    }
    private func show(_ client: IMKTextInput) {
        if panel == nil {
            let p=NSPanel(contentRect:NSRect(x:0,y:0,width:430,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.level = .popUpMenu;p.hasShadow=true;p.isOpaque=false;p.backgroundColor = .clear;p.hidesOnDeactivate=false
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel=p
        }
        guard let panel else {return}
        let range=Typing.pageRange(count:items.count,selected:selected,size:Store.shared.preferences.pageSize)
        let shownCode=buffer, token=generation
        let view=NSHostingView(rootView:CandidatePanelView(code:buffer,items:items,selected:selected,range:range,fontSize:Store.shared.preferences.fontSize,choose:{ [weak self] i in
            guard let self, let current=self.client() else{return};self.choose(i,client:current)
        },preference:{ [weak self] index,hidden in
            guard let self, self.generation==token, self.buffer==shownCode, self.items.indices.contains(index), !IsSecureEventInputEnabled(), let current=self.client() else {return}
            Store.shared.candidateRule(self.items[index],code:shownCode,hidden:hidden)
            self.selected=0;self.refresh(current)
        }))
        panel.contentView=view
        let size=view.fittingSize
        var caret=NSRect.zero
        _=client.attributes(forCharacterIndex:0,lineHeightRectangle:&caret)
        let screen=NSScreen.screens.first(where:{$0.frame.intersects(caret)}) ?? NSScreen.main
        let bounds=screen?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        var point=NSPoint(x:caret.minX,y:caret.minY-size.height-5)
        if caret == .zero {point=NSPoint(x:bounds.midX-size.width/2,y:bounds.midY)}
        if point.y<bounds.minY {point.y=caret.maxY+5}
        point.x=max(bounds.minX,min(point.x,bounds.maxX-size.width));point.y=max(bounds.minY,min(point.y,bounds.maxY-size.height))
        panel.setFrame(NSRect(origin:point,size:size),display:true);panel.orderFrontRegardless()
    }
    private func choose(_ index: Int, client: IMKTextInput) {
        guard !IsSecureEventInputEnabled() else {reset(client,clearMarked:true);return}
        guard items.indices.contains(index) else {commit(buffer,client:client);return}
        let chosen=items[index], code=buffer
        commit(chosen.text,client:client);Store.shared.recordSelection(chosen,code:code)
    }
    private func commit(_ text: String, client: IMKTextInput) {
        if !text.isEmpty {client.insertText(text,replacementRange:replacement)}
        logger.debug("Composition committed")
        reset(client,clearMarked:false)
    }
    private func reset(_ client: IMKTextInput, clearMarked: Bool) {
        generation += 1;cloudTask?.cancel();cloudTask=nil
        if clearMarked {client.setMarkedText("",selectionRange:NSRange(location:0,length:0),replacementRange:replacement)}
        buffer="";items=[];selected=0;panel?.orderOut(nil)
    }
    override func commitComposition(_ sender: Any!) {
        if let c=sender as? IMKTextInput, !buffer.isEmpty {commit(buffer,client:c)}
    }
    override func hidePalettes() {panel?.orderOut(nil)}
    override func inputControllerWillClose() {closeVoice();cloudTask?.cancel();panel?.orderOut(nil);super.inputControllerWillClose()}
    override func menu() -> NSMenu! {
        let menu=NSMenu(title:"词伴开源版")
        menu.addItem(withTitle:"词伴开源版设置…",action:#selector(openSettings(_:)),keyEquivalent:"")
        menu.addItem(withTitle:english ? "切换为中文输入" : "切换为英文输入",action:#selector(switchLanguage(_:)),keyEquivalent:"")
        menu.addItem(withTitle:"语音输入…",action:#selector(openVoice(_:)),keyEquivalent:"")
        let item=menu.addItem(withTitle:"请求当前候选的 AI 译词（可能收费）",action:#selector(requestTranslation(_:)),keyEquivalent:"")
        item.isEnabled=Store.shared.preferences.cloudEnabled && !buffer.isEmpty && !items.isEmpty
        menu.autoenablesItems=false
        return menu
    }
    @objc private func openSettings(_ sender: Any?) { AppDelegate.openSettingsApp() }
    private func toggleLanguage(_ client: IMKTextInput) {
        if !buffer.isEmpty { commit(buffer,client:client) };english.toggle()
    }
    @objc private func switchLanguage(_ sender: Any?) { if let client=client() { toggleLanguage(client) } }
    private func closeVoice() { voice?.cancel();voicePanel?.close();voicePanel=nil;voice=nil }
    @objc private func openVoice(_ sender: Any?) {
        guard !IsSecureEventInputEnabled(), let target=client() else {return}
        if !buffer.isEmpty {commit(buffer,client:target)}
        closeVoice()
        let model=VoiceInput()
        let height=min(620,max(380,(NSScreen.main?.visibleFrame.height ?? 720)-70))
        let p=VoicePanel(contentRect:NSRect(x:0,y:0,width:520,height:height),styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
        p.title="词伴开源版 · 语音输入";p.level = .popUpMenu;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
        p.becomesKeyOnlyIfNeeded=true
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        p.contentView=NSHostingView(rootView:ScrollView { VoiceView(voice:model,use:{ [weak self] text in
            guard let self, self.voice === model, !IsSecureEventInputEnabled() else {return}
            // Deactivation destroys the panel and cancels recognition. Never use a later client.
            target.insertText(text,replacementRange:self.replacement);self.closeVoice()
        },useTitle:"插入当前输入位置",editable:false) })
        voice=model;voicePanel=p;p.center();p.orderFrontRegardless()
    }
    @objc private func requestTranslation(_ sender: Any?) {
        guard items.indices.contains(selected), !IsSecureEventInputEnabled() else{return}
        let index=selected, text=items[index].text, token=generation, preferences=Store.shared.preferences
        cloudTask?.cancel()
        cloudTask=Task { @MainActor [weak self] in
            do {
                let result=try await Cloud.translate(text,preferences:preferences)
                guard let self, !Task.isCancelled, self.generation==token, self.items.indices.contains(index), self.items[index].text==text, let client=self.client() else{return}
                self.items[index].gloss=result;self.items[index].kind="ai";self.show(client)
            } catch {
                guard let self, !Task.isCancelled, self.generation==token else{return}
                Store.shared.status="AI 请求失败，离线候选仍可用。"
            }
        }
    }
}
