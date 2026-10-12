#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

static NSString* sourceID(TISInputSourceRef source) {
    return source ? (__bridge NSString*)TISGetInputSourceProperty(source,kTISPropertyInputSourceID) : @"";
}
static TISInputSourceRef findSource(NSString* identifier) {
    NSDictionary* filter=@{(__bridge NSString*)kTISPropertyInputSourceID:identifier};
    CFArrayRef list=TISCreateInputSourceList((__bridge CFDictionaryRef)filter,true);
    TISInputSourceRef result=NULL;
    if(list && CFArrayGetCount(list)>0)result=(TISInputSourceRef)CFRetain(CFArrayGetValueAtIndex(list,0));
    if(list)CFRelease(list);return result;
}
static void pump(double seconds) {
    NSDate* end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(end.timeIntervalSinceNow>0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:end];
        [NSThread sleepForTimeInterval:0.005];
    }
}

@interface TestDelegate:NSObject<NSApplicationDelegate>
@property NSWindow* window;
@property NSTextView* text;
@property NSSecureTextField* secure;
@property NSTextField* other;
@end
@implementation TestDelegate
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,720,500) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"词伴开源版 · 专用自动测试文档（无私人内容）";
    NSView* content=self.window.contentView;
    NSTextField* label=[NSTextField labelWithString:@"仅此窗口接收测试字符。测试结束后恢复原输入源与设置；不使用麦克风或云服务。"];
    label.frame=NSMakeRect(20,445,680,40);[content addSubview:label];
    NSButton* probe=[NSButton buttonWithTitle:@"测试启用词伴开源版" target:self action:@selector(probeSource:)];probe.frame=NSMakeRect(20,400,180,28);probe.accessibilityIdentifier=@"lexi-probe-source";[content addSubview:probe];
    NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(20,130,680,260)];scroll.hasVerticalScroller=YES;
    self.text=[[NSTextView alloc] initWithFrame:scroll.bounds];self.text.richText=NO;self.text.font=[NSFont systemFontOfSize:23];
    self.text.automaticSpellingCorrectionEnabled=NO;self.text.automaticQuoteSubstitutionEnabled=NO;self.text.automaticDashSubstitutionEnabled=NO;
    self.text.accessibilityIdentifier=@"lexi-test-document";scroll.documentView=self.text;[content addSubview:scroll];
    self.other=[[NSTextField alloc] initWithFrame:NSMakeRect(20,75,680,35)];self.other.placeholderString=@"测试用第二输入位置";self.other.accessibilityIdentifier=@"lexi-other";[content addSubview:self.other];
    self.secure=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(20,25,680,35)];self.secure.placeholderString=@"仅填测试字符的密码框";self.secure.accessibilityIdentifier=@"lexi-secure";[content addSubview:self.secure];
    [self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[self.window makeFirstResponder:self.text];
    {
        __block NSInteger received=0;
        void (^state)(void)=^{
            TISInputSourceRef current=TISCopyCurrentKeyboardInputSource();
            NSDictionary* value=@{@"active":@(NSApp.isActive),@"keyWindow":@(self.window.isKeyWindow),@"firstResponder":NSStringFromClass(self.window.firstResponder.class),@"text":self.text.string,@"marked":@(self.text.hasMarkedText),@"keyEventsReceived":@(received),@"otherText":self.other.stringValue,@"secureTestText":self.secure.stringValue,@"secureEventInput":@(IsSecureEventInputEnabled()),@"source":sourceID(current)};
            if(current)CFRelease(current);
            NSURL* url=[[[NSBundle mainBundle].bundleURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"system-test/fixture-state.json"];
            [[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToURL:url options:NSDataWritingAtomic error:nil];
        };
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown|NSEventMaskKeyUp|NSEventMaskFlagsChanged handler:^NSEvent*(NSEvent* event){++received;dispatch_async(dispatch_get_main_queue(),state);return event;}];
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer* timer){state();}];
    }
}
- (void)probeSource:(id)sender {
    NSMutableDictionary* probe=[NSMutableDictionary dictionary];
    TISInputSourceRef before=TISCopyCurrentKeyboardInputSource();probe[@"before"]=sourceID(before);
    NSURL* input=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Input Methods/LexiIME-Open Input.app"] isDirectory:YES];
    probe[@"register"]=@(TISRegisterInputSource((__bridge CFURLRef)input));
    TISInputSourceRef parent=findSource(@"local.inputmethod.lexiime.open");
    if(parent){probe[@"enableParent"]=@(TISEnableInputSource(parent));CFRelease(parent);pump(2.0);}
    parent=findSource(@"local.inputmethod.lexiime.open");
    if(parent){probe[@"parentEnabled"]=(__bridge NSNumber*)TISGetInputSourceProperty(parent,kTISPropertyInputSourceIsEnabled);CFRelease(parent);}
    TISInputSourceRef source=findSource(@"local.inputmethod.lexiime.open.pinyin");
    if(source){probe[@"enableSource"]=@(TISEnableInputSource(source));pump(0.5);probe[@"select"]=@(TISSelectInputSource(source));CFRelease(source);pump(1.0);}
    TISInputSourceRef current=TISCopyCurrentKeyboardInputSource();probe[@"selected"]=sourceID(current);if(current)CFRelease(current);
    if(![probe[@"selected"] isEqual:@"local.inputmethod.lexiime.open.pinyin"] && before)TISSelectInputSource(before);
    if(before)CFRelease(before);
    NSURL* url=[[[NSBundle mainBundle].bundleURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"system-test/probe-input.json"];
    [[NSJSONSerialization dataWithJSONObject:probe options:NSJSONWritingPrettyPrinted error:nil] writeToURL:url options:NSDataWritingAtomic error:nil];
    [self.window makeFirstResponder:self.text];
}
@end
int main(int argc,const char** argv){@autoreleasepool{NSApplication* app=NSApplication.sharedApplication;TestDelegate* delegate=[TestDelegate new];app.delegate=delegate;[app run];}}
