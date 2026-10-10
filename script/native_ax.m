#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static id attribute(AXUIElementRef e, CFStringRef name) {
    CFTypeRef value=NULL;
    AXError error=AXUIElementCopyAttributeValue(e,name,&value);
    return error==kAXErrorSuccess && value ? CFBridgingRelease(value) : nil;
}
static void emit(id object) {
    NSData* data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);
}
static BOOL allowed(NSString* bundle) {
    return [@[@"com.apple.systempreferences",@"local.lexiime.open.systemtest",@"local.lexiime.open.settings"] containsObject:bundle];
}
static NSMutableArray* nodes;
static BOOL includeSidebar=NO;
static NSArray* childrenOf(AXUIElementRef e) {
    NSMutableArray* children=[NSMutableArray array];
    for(NSString* key in @[@"AXChildren",@"AXContents",@"AXVisibleChildren",@"AXWindows"]) {
        id value=attribute(e,(__bridge CFStringRef)key);
        if([value isKindOfClass:NSArray.class])for(id child in value)
            if(CFGetTypeID((__bridge CFTypeRef)child)==AXUIElementGetTypeID()
               && !CFEqual(e,(__bridge CFTypeRef)child) && ![children containsObject:child])[children addObject:child];
    }
    return children;
}
static void inspect(AXUIElementRef e,int depth) {
    if(depth>32 || nodes.count>1600)return;
    if([attribute(e,kAXRoleAttribute) isEqual:@"AXMenuBar"] || (!includeSidebar && [attribute(e,CFSTR("AXIdentifier")) isEqual:@"com.apple.settings.sidebar.collectionView"]))return;
    NSMutableDictionary* node=[NSMutableDictionary dictionary];
    for(NSString* key in @[@"AXRole",@"AXTitle",@"AXDescription",@"AXValue",@"AXIdentifier",@"AXEnabled"]) {
        if([key isEqual:@"AXValue"] && [attribute(e,kAXSubroleAttribute) isEqual:@"AXSecureTextField"])continue;
        id value=attribute(e,(__bridge CFStringRef)key);
        if([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class])node[key]=value;
    }
    node[@"depth"]=@(depth);[nodes addObject:node];
    NSArray* children=childrenOf(e);
    if([children isKindOfClass:NSArray.class])for(id child in children)inspect((__bridge AXUIElementRef)child,depth+1);
}
static AXUIElementRef match(AXUIElementRef e,NSString* identifier,int depth) {
    if(depth>32)return NULL;
    if([attribute(e,kAXRoleAttribute) isEqual:@"AXMenuBar"])return NULL;
    for(NSString* key in @[@"AXTitle",@"AXDescription",@"AXIdentifier",@"AXValue"])
        if([attribute(e,(__bridge CFStringRef)key) isEqual:identifier])return (AXUIElementRef)CFRetain(e);
    NSArray* children=childrenOf(e);
    if([children isKindOfClass:NSArray.class])for(id child in children) {
        AXUIElementRef result=match((__bridge AXUIElementRef)child,identifier,depth+1);if(result)return result;
    }
    return NULL;
}
int main(int argc,const char** argv) { @autoreleasepool {
    if(argc<2)return 2;
    NSString* command=@(argv[1]);
    if([command isEqual:@"trust"]) {emit(@{@"accessibility":@(AXIsProcessTrusted()),@"postEvents":@(CGPreflightPostEventAccess())});return 0;}
    if([command isEqual:@"session"]) {
        NSDictionary* session=CFBridgingRelease(CGSessionCopyCurrentDictionary());
        emit(@{@"onConsole":session[(__bridge NSString*)kCGSessionOnConsoleKey]?:[NSNull null],@"loginDone":session[(__bridge NSString*)kCGSessionLoginDoneKey]?:[NSNull null],@"screenLocked":session[@"CGSSessionScreenIsLocked"]?:@NO,@"displayAsleep":@(CGDisplayIsAsleep(CGMainDisplayID())),@"displayOnline":@(CGDisplayIsOnline(CGMainDisplayID()))});return 0;
    }
    if(argc<3 || !allowed(@(argv[2])))return 2;
    if(!AXIsProcessTrusted()){emit(@{@"error":@"Accessibility permission is unavailable"});return 1;}
    NSArray* apps=[NSRunningApplication runningApplicationsWithBundleIdentifier:@(argv[2])];
    if(apps.count!=1){emit(@{@"error":@"Expected one allowed app",@"count":@(apps.count)});return 1;}
    NSRunningApplication* app=apps.firstObject;
    AXUIElementRef element=AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementSetMessagingTimeout(element,3.0);
    if([command isEqual:@"activate"]){BOOL result=[app activateWithOptions:0];[NSThread sleepForTimeInterval:0.5];emit(@{@"activated":@(result)});}
    else if([command isEqual:@"keyboard"] && [@(argv[2]) isEqual:@"com.apple.systempreferences"]){includeSidebar=YES;nodes=[NSMutableArray array];inspect(element,0);NSMutableArray* matches=[NSMutableArray array];for(NSDictionary* n in nodes){if([n[@"AXDescription"] isEqual:@"键盘"] || [n[@"AXTitle"] isEqual:@"键盘"])[matches addObject:n];}emit(matches);}
    else if([command isEqual:@"tree"]){nodes=[NSMutableArray array];inspect(element,0);emit(nodes);}
    else if([command isEqual:@"press"] && argc==4) {
        if([@(argv[2]) isEqual:@"local.lexiime.open.settings"] && ![@[@"开始",@"语音输入",@"重新检查",@"重新检查语音资源"] containsObject:@(argv[3])]){CFRelease(element);return 2;}
        AXUIElementRef target=match(element,@(argv[3]),0);
        if(!target){emit(@{@"error":@"Control not found"});CFRelease(element);return 1;}
        AXError error=AXUIElementPerformAction(target,kAXPressAction);[NSThread sleepForTimeInterval:0.5];CFRelease(target);emit(@{@"status":@(error)});
    } else if([command isEqual:@"filter-input-sources"] && argc==4 && [@(argv[2]) isEqual:@"com.apple.systempreferences"] && [@[@"词伴开源版",@"LexiIME-Open"] containsObject:@(argv[3])]) {
        AXUIElementRef target=match(element,@"使用关键词过滤输入法",0);
        if(!target){CFRelease(element);return 1;}
        AXError error=AXUIElementSetAttributeValue(target,kAXValueAttribute,(__bridge CFStringRef)@(argv[3]));
        CFRelease(target);[NSThread sleepForTimeInterval:0.7];emit(@{@"status":@(error)});
    } else if([command isEqual:@"select-row"] && argc==4 && [@(argv[2]) isEqual:@"com.apple.systempreferences"] && [@[@"简体中文",@"其他",@"词伴开源版",@"LexiIME-Open Input"] containsObject:@(argv[3])]) {
        AXUIElementRef target=match(element,@(argv[3]),0);
        if(!target){CFRelease(element);return 1;}
        for(int i=0;i<5 && ![attribute(target,kAXRoleAttribute) isEqual:@"AXRow"];++i){
            id parent=attribute(target,kAXParentAttribute);
            if(!parent)break;
            AXUIElementRef next=(AXUIElementRef)CFRetain((__bridge CFTypeRef)parent);CFRelease(target);target=next;
        }
        AXError error=AXUIElementSetAttributeValue(target,kAXSelectedAttribute,kCFBooleanTrue);
        CFRelease(target);[NSThread sleepForTimeInterval:0.7];emit(@{@"status":@(error)});
    } else if([command isEqual:@"key"] && argc==5 && [@(argv[2]) isEqual:@"local.lexiime.open.systemtest"]) {
        if(!CGPreflightPostEventAccess() || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=app.processIdentifier){emit(@{@"error":@"Test app is not foreground or posting is unauthorized"});CFRelease(element);return 1;}
        int code=atoi(argv[3]);if(code<0||code>127){CFRelease(element);return 2;}
        CGEventFlags flags=strtoull(argv[4],NULL,10);
        CGEventRef down=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)code,true),up=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)code,false);
        // Unicode payloads and direct PID delivery bypass the active IME.
        // Use the system input path only after the test app foreground guard.
        CGEventSetFlags(down,flags);CGEventSetFlags(up,0);
        if(code==56 || code==60){CGEventSetType(down,kCGEventFlagsChanged);CGEventSetType(up,kCGEventFlagsChanged);}
        CGEventSetIntegerValueField(down,kCGEventTargetUnixProcessID,app.processIdentifier);CGEventSetIntegerValueField(up,kCGEventTargetUnixProcessID,app.processIdentifier);
        CGEventPost(kCGHIDEventTap,down);[NSThread sleepForTimeInterval:0.08];CGEventPost(kCGHIDEventTap,up);
        [NSThread sleepForTimeInterval:0.4];CFRelease(down);CFRelease(up);emit(@{@"postedWhileTestPIDForeground":@(app.processIdentifier)});
    } else if([command isEqual:@"focus"] && argc==4 && [@(argv[2]) isEqual:@"local.lexiime.open.systemtest"]) {
        AXUIElementRef target=match(element,@(argv[3]),0);if(!target){CFRelease(element);return 1;}
        [app activateWithOptions:0];AXError error=AXUIElementSetAttributeValue(target,kAXFocusedAttribute,kCFBooleanTrue);CFRelease(target);emit(@{@"status":@(error)});
    } else if([command isEqual:@"clear"] && [@(argv[2]) isEqual:@"local.lexiime.open.systemtest"]) {
        AXUIElementRef target=match(element,@"lexi-test-document",0);if(!target){CFRelease(element);return 1;}
        AXError error=AXUIElementSetAttributeValue(target,kAXValueAttribute,CFSTR(""));CFRelease(target);emit(@{@"status":@(error)});
    } else {CFRelease(element);return 2;}
    CFRelease(element);return 0;
}}
