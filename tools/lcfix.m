// lcfix.m —— 绕过 LiveContainer 那个会崩的 UIApplication scene hook
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static IMP gOrigConnect = NULL;

static void h_connect(id self, SEL _cmd, id scene, id ctx) {
    // LiveContainer 用 method_exchangeImplementations：
    // 交换后 hook__xxx 指向原始实现，_xxx 指向它的 hook
    SEL orig = sel_registerName("hook__connectUISceneFromFBSScene:transitionContext:");
    if ([self respondsToSelector:orig]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, orig, scene, ctx);
        return;
    }
    if (gOrigConnect) ((void (*)(id, SEL, id, id))gOrigConnect)(self, _cmd, scene, ctx);
}

__attribute__((constructor))
static void lcfix_init(void) {
    @try {
        Class c = objc_getClass("UIApplication");
        if (!c) return;
        SEL hookSel = sel_registerName("hook__connectUISceneFromFBSScene:transitionContext:");
        SEL origSel = sel_registerName("_connectUISceneFromFBSScene:transitionContext:");
        if (![c instancesRespondToSelector:hookSel]) {
            NSLog(@"[wsgbypass-lc] not under LiveContainer, skip");
            return;
        }
        Method m = class_getInstanceMethod(c, origSel);
        if (!m) { NSLog(@"[wsgbypass-lc] scene selector missing"); return; }
        gOrigConnect = method_getImplementation(m);
        method_setImplementation(m, (IMP)h_connect);
        NSLog(@"[wsgbypass-lc] LiveContainer scene hook bypassed");
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-lc] failed: %@", e);
    }
}
