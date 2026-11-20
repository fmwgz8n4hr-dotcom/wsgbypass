// lcfix.m v3 —— 只探测不修改：确认是否在 LiveContainer 里，绝不 hook scene 方法
// v1/v2 试图绕过 LiveContainer 的 scene hook，均导致递归崩溃，已放弃
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

__attribute__((constructor))
static void lcfix_init(void) {
    @try {
        Class c = objc_getClass("UIApplication");
        if (!c) return;
        BOOL hasHook = [c instancesRespondToSelector:
                        sel_registerName("hook__connectUISceneFromFBSScene:transitionContext:")];
        BOOL hasOrig = [c instancesRespondToSelector:
                        sel_registerName("_connectUISceneFromFBSScene:transitionContext:")];
        NSLog(@"[wsgbypass-lc] probe only: hookMethod=%d origMethod=%d (no patching)",
              hasHook, hasOrig);
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-lc] probe failed: %@", e);
    }
}
