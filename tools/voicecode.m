// voicecode.m —— 把 codeMT 的 code_type 从 0(短信) 改成 1(语音外呼)
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSURLSessionDataTask *(*o_task)(id, SEL, NSURLRequest *);

static NSURLSessionDataTask *h_task(id self, SEL _cmd, NSURLRequest *req) {
    @try {
        NSString *u = req.URL.absoluteString;
        if ([u containsString:@"codeMT"] && req.HTTPBody.length > 0) {
            NSString *body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
            NSLog(@"[wsgbypass-voice] codeMT body=%@", body.length > 200 ? [body substringToIndex:200] : body);
            if (body && ([body containsString:@"code_type=0"] || [body containsString:@"codeType=0"])) {
                NSString *nb = [body stringByReplacingOccurrencesOfString:@"code_type=0" withString:@"code_type=1"];
                nb = [nb stringByReplacingOccurrencesOfString:@"codeType=0" withString:@"codeType=1"];
                NSMutableURLRequest *m = [req mutableCopy];
                m.HTTPBody = [nb dataUsingEncoding:NSUTF8StringEncoding];
                NSLog(@"[wsgbypass-voice] rewritten to VOICE (code_type=1)");
                return o_task(self, _cmd, m);
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
        NSLog(@"[wsgbypass-voice] installed");
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-voice] init failed: %@", e);
    }
}
