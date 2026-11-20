// lcfix.m v2 —— 绕过 LiveContainer 的 scene hook，带防重复安装与防递归
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gInstalled = NO;

static void h_connect(id self, SEL _cmd, id scene, id ctx) {
    // 交换后 hook__xxx 指向 UIKit 原始实现
    SEL orig = sel_registerName("hook__connectUISceneFromFBSScene:transitionContext:");
    if ([self respondsToSelector:orig]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, orig, scene, ctx);
        return;
    }
    NSLog(@"[wsgbypass-lc] no original impl, skipped");
}

__attribute__((constructor))
static void lcfix_init(void) {
    @try {
        if (gInstalled) { NSLog(@"[wsgbypass-lc] already installed, skip"); return; }
        Class c = objc_getClass("UIApplication");
        if (!c) return;
        SEL hookSel = sel_registerName("hook__connectUISceneFromFBSScene:transitionContext:");
        SEL origSel = sel_registerName("_connectUISceneFromFBSScene:transitionContext:");
        BOOL hasHook = [c instancesRespondToSelector:hookSel];
        Method m = class_getInstanceMethod(c, origSel);
        IMP cur = m ? method_getImplementation(m) : NULL;
        NSLog(@"[wsgbypass-lc] hasHookMethod=%d hasOrig=%d selfInstalled=%d",
              hasHook, m != NULL, cur == (IMP)h_connect);
        if (!m) return;
        if (cur == (IMP)h_connect) { gInstalled = YES; return; }
        if (!hasHook) { NSLog(@"[wsgbypass-lc] not under LiveContainer, skip"); return; }
        method_setImplementation(m, (IMP)h_connect);
        gInstalled = YES;
        NSLog(@"[wsgbypass-lc] LiveContainer scene hook bypassed");
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-lc] failed: %@", e);
    }
}
