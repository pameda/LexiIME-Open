#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>
#import <AppKit/AppKit.h>

static id prop(TISInputSourceRef source,CFStringRef key) {
    void* value=TISGetInputSourceProperty(source,key);
    return value ? (__bridge id)value : [NSNull null];
}
static NSDictionary* record(TISInputSourceRef source) {
    return @{ @"id":prop(source,kTISPropertyInputSourceID),
              @"name":prop(source,kTISPropertyLocalizedName),
              @"bundle":prop(source,kTISPropertyBundleID),
              @"category":prop(source,kTISPropertyInputSourceCategory),
              @"type":prop(source,kTISPropertyInputSourceType),
              @"enabled":prop(source,kTISPropertyInputSourceIsEnabled),
              @"enableCapable":prop(source,kTISPropertyInputSourceIsEnableCapable),
              @"selected":prop(source,kTISPropertyInputSourceIsSelected),
              @"selectable":prop(source,kTISPropertyInputSourceIsSelectCapable) };
}
static void output(id value) {
    NSData* data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);
}
static BOOL enabledForSelection(NSArray* sources) {
    BOOL parentEnabled=NO, usable=NO, hasModes=NO;
    for(NSDictionary* source in sources) {
        if(![source[@"id"] isKindOfClass:NSString.class]
           || ![source[@"type"] isKindOfClass:NSString.class]
           || ![source[@"category"] isEqual:(__bridge NSString*)kTISCategoryKeyboardInputSource])return NO;
        BOOL enabled=[source[@"enabled"] isEqual:@YES];
        BOOL selectable=[source[@"selectable"] isEqual:@YES];
        if([source[@"type"] isEqual:(__bridge NSString*)kTISTypeKeyboardInputMethodModeEnabled]) {
            hasModes=YES;parentEnabled=enabled;
        }
        usable=usable || (enabled && selectable);
    }
    return usable && (!hasModes || parentEnabled);
}
static void settle(void) {
    NSDate* end=[NSDate dateWithTimeIntervalSinceNow:3.0];
    while([end timeIntervalSinceNow]>0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:end];
        [NSThread sleepForTimeInterval:0.05];
    }
}
int main(int argc,const char**argv) { @autoreleasepool {
    NSApplicationLoad();
    if(argc<2)return 2;
    NSString* command=@(argv[1]);
    if([command isEqual:@"verify-enabled"] && argc==3) {
        NSDictionary* filter=@{(__bridge NSString*)kTISPropertyBundleID:@(argv[2])};
        CFArrayRef list=TISCreateInputSourceList((__bridge CFDictionaryRef)filter,true);
        NSMutableArray* matches=[NSMutableArray array];
        if(list) {
            for(CFIndex i=0;i<CFArrayGetCount(list);++i)[matches addObject:record((TISInputSourceRef)CFArrayGetValueAtIndex(list,i))];
            CFRelease(list);
        }
        BOOL verified=enabledForSelection(matches);
        output(@{@"operation":command,@"verified":@(verified),@"sources":matches});return verified?0:1;
    }
    if([command isEqual:@"current"]) {
        TISInputSourceRef source=TISCopyCurrentKeyboardInputSource();
        if(!source)return 1;output(record(source));CFRelease(source);return 0;
    }
    if(([command isEqual:@"register"] || [command isEqual:@"register-enable"]) && argc==3) {
        NSURL* url=[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
        OSStatus launchStatus=LSRegisterURL((__bridge CFURLRef)url,true);
        OSStatus status=launchStatus==noErr ? TISRegisterInputSource((__bridge CFURLRef)url) : launchStatus;
        NSMutableArray* matches=[NSMutableArray array];
        CFArrayRef list=TISCreateInputSourceList(NULL,true);
        NSString* bundleID=[NSBundle bundleWithURL:url].bundleIdentifier;
        if(list)for(CFIndex i=0;i<CFArrayGetCount(list);++i) {
            TISInputSourceRef source=(TISInputSourceRef)CFArrayGetValueAtIndex(list,i);
            if([prop(source,kTISPropertyBundleID) isEqual:bundleID]) {
                if([command isEqual:@"register-enable"]) {
                    OSStatus enable=TISEnableInputSource(source);if(enable!=noErr)status=enable;
                }
            }
        }
        if(list)CFRelease(list);
        if([command isEqual:@"register-enable"])settle();
        // Read a new snapshot after settling; the enable return code alone is
        // not evidence that the input source became available in the system.
        list=TISCreateInputSourceList(NULL,true);
        if(list)for(CFIndex i=0;i<CFArrayGetCount(list);++i) {
            TISInputSourceRef source=(TISInputSourceRef)CFArrayGetValueAtIndex(list,i);
            if([prop(source,kTISPropertyBundleID) isEqual:bundleID]) [matches addObject:record(source)];
        }
        if(list)CFRelease(list);
        BOOL verified=status==noErr && matches.count>0;
        if([command isEqual:@"register-enable"])verified=verified && enabledForSelection(matches);
        NSMutableDictionary* result=[@{@"operation":command,@"status":@(status),@"sources":matches,@"verified":@(verified)} mutableCopy];
        if(!verified)result[@"error"]=@"The input source was not verified as enabled. Registration return codes alone do not mean it is usable.";
        output(result);return verified?0:1;
    }
    CFArrayRef sources=TISCreateInputSourceList(NULL,true);
    if(!sources)return 1;
    if([command isEqual:@"list"]) {
        NSMutableArray* values=[NSMutableArray array];
        for(CFIndex i=0;i<CFArrayGetCount(sources);++i) {
            TISInputSourceRef source=(TISInputSourceRef)CFArrayGetValueAtIndex(sources,i);
            [values addObject:record(source)];
        }
        output(values);CFRelease(sources);return 0;
    }
    if(argc!=3){CFRelease(sources);return 2;}
    NSString* wanted=@(argv[2]);
    for(CFIndex i=0;i<CFArrayGetCount(sources);++i) {
        TISInputSourceRef source=(TISInputSourceRef)CFArrayGetValueAtIndex(sources,i);
        if(![prop(source,kTISPropertyInputSourceID) isEqual:wanted])continue;
        OSStatus status=-1;
        if([command isEqual:@"enable"])status=TISEnableInputSource(source);
        else if([command isEqual:@"select"])status=TISSelectInputSource(source);
        else if([command isEqual:@"disable"])status=TISDisableInputSource(source);
        settle();output(@{@"operation":command,@"status":@(status),@"source":record(source)});
        CFRelease(sources);return status==noErr?0:1;
    }
    output(@{@"error":@"Input source not found",@"id":wanted});CFRelease(sources);return 1;
}}
