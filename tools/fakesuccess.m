// fakesuccess.m —— 把 codeMT 的 53001 改写成成功，让 App 进入验证码输入界面
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static id (*o_json)(id, SEL, NSData *, NSJSONReadingOptions, NSError **);

static id h_json(id self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err) {
    id r = o_json(self, _cmd, data, opt, err);
    @try {
        if ([r isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)r;
            id code = d[@"errno"];
            if (code && [code respondsToSelector:@selector(intValue)] && [code intValue] == 53001) {
                NSMutableDictionary *m = [d mutableCopy];
                m[@"errno"] = @0;
                m[@"error"] = @"成功";
                NSMutableDictionary *data2 = [d[@"data"] isKindOfClass:[NSDictionary class]]
                    ? [d[@"data"] mutableCopy] : [NSMutableDictionary dictionary];
                data2[@"code_len"] = @6;
                data2[@"code_tag"] = @"【滴滴出行】";
                m[@"data"] = data2;
                m[@"support_voice"] = @NO;
                m[@"code_type"] = @0;
                NSLog(@"[wsgbypass-fake] 53001 -> 0, force code input");
                return m;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-fake] failed: %@", e);
    }
    return r;
}

__attribute__((constructor))
static void fakesuccess_init(void) {
    @try {
        Class j = objc_getClass("NSJSONSerialization");
        if (!j) return;
        Method m = class_getClassMethod(j, sel_registerName("JSONObjectWithData:options:error:"));
        if (!m) return;
        o_json = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)h_json);
        NSLog(@"[wsgbypass-fake] installed");
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-fake] init failed: %@", e);
    }
}
