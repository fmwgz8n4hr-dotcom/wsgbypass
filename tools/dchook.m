// dchook.m —— 让 DCDevice 报告"不支持"，迫使 App 回退到自己的设备 ID
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL (*o_isSupported)(id, SEL);

static BOOL h_isSupported(id self, SEL _cmd) {
    BOOL real = o_isSupported ? o_isSupported(self, _cmd) : NO;
    NSLog(@"[wsgbypass-dc] DCDevice.isSupported (real=%d) -> forcing NO", real);
    return NO;
}

__attribute__((constructor))
static void dchook_init(void) {
    @try {
        Class c = objc_getClass("DCDevice");
        if (!c) { NSLog(@"[wsgbypass-dc] DCDevice not loaded"); return; }
        Method m = class_getInstanceMethod(c, sel_registerName("isSupported"));
        if (!m) { NSLog(@"[wsgbypass-dc] isSupported not found"); return; }
        o_isSupported = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)h_isSupported);
        NSLog(@"[wsgbypass-dc] isSupported hooked");
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-dc] failed: %@", e);
    }
}
