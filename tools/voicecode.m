// voicecode.m v3 —— 停用：不改写任何请求，只记录 codeMT 的真实请求体
// （v1/v2 把 code_type 改成语音，会挡住短信，已停用）
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSURLSessionDataTask *(*o_task)(id, SEL, NSURLRequest *);

static NSURLSessionDataTask *h_task(id self, SEL _cmd, NSURLRequest *req) {
    @try {
        if ([req.URL.absoluteString containsString:@"codeMT"]) {
            NSData *body = req.HTTPBody;
            if (body.length > 0) {
                NSString *s = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
                if (s) {
                    NSString *t = s.length > 300 ? [s substringToIndex:300] : s;
                    NSLog(@"[wsgbypass-voice] codeMT body=%@", t);
                } else {
                    NSLog(@"[wsgbypass-voice] codeMT body=<binary %lu B, encrypted>", (unsigned long)body.length);
                }
            } else {
                NSLog(@"[wsgbypass-voice] codeMT body=<empty>");
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-voice] failed: %@", e);
    }
    return o_task(self, _cmd, req);
}

__attribute__((constructor))
static void voicecode_init(void) {
    @try {
        Class s = objc_getClass("NSURLSession");
        if (!s) return;
        Method m = class_getInstanceMethod(s, sel_registerName("dataTaskWithRequest:"));
        if (!m) return;
        o_task = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)h_task);
        NSLog(@"[wsgbypass-voice] observe only (SMS untouched)");
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-voice] init failed: %@", e);
    }
}
