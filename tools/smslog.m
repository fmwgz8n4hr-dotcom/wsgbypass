// smslog.m —— 诊断用：把短信/护照接口的请求与回执打到 Console
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define TAG @"[wsgbypass-net]"

static BOOL InterestingURL(NSString *u) {
    if (u.length == 0) return NO;
    NSString *l = u.lowercaseString;
    return ([l containsString:@"passport"] || [l containsString:@"codemt"] ||
            [l containsString:@"sms"] || [l containsString:@"login"] ||
            [l containsString:@"signin"] || [l containsString:@"verify"]);
}

static void LogBody(NSString *tag, NSData *d) {
    if (d.length == 0) return;
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!s) { NSLog(@"%@ %@ <binary %lu B>", TAG, tag, (unsigned long)d.length); return; }
    if (s.length > 800) s = [s substringToIndex:800];
    NSLog(@"%@ %@ %@", TAG, tag, s);
}

static NSURLSessionDataTask *(*o_taskCG)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
static NSURLSessionDataTask *h_taskCG(id self, SEL _cmd, NSURLRequest *req,
                                      void (^cb)(NSData *, NSURLResponse *, NSError *)) {
    if (!InterestingURL(req.URL.absoluteString)) return o_taskCG(self, _cmd, req, cb);
    NSLog(@"%@ >> %@ %@", TAG, req.HTTPMethod, req.URL.absoluteString);
    LogBody(@"REQ", req.HTTPBody);
    NSString *url = req.URL.absoluteString;
    void (^wrap)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSInteger code = [(NSHTTPURLResponse *)r statusCode];
        NSLog(@"%@ << HTTP %ld %@", TAG, (long)code, url);
        LogBody(@"RSP", d);
        if (e) NSLog(@"%@ !! %@", TAG, e.localizedDescription);
        if (cb) cb(d, r, e);
    };
    return o_taskCG(self, _cmd, req, wrap);
}

static id (*o_json)(id, SEL, NSData *, NSJSONReadingOptions, NSError **);
static id h_json(id self, SEL _cmd, NSData *d, NSJSONReadingOptions opt, NSError **err) {
    id r = o_json(self, _cmd, d, opt, err);
    if ([r isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)r;
        id code = dict[@"errno"] ?: dict[@"code"] ?: dict[@"errNo"];
        if (code) {
            id msg = dict[@"error"] ?: dict[@"errmsg"] ?: dict[@"message"] ?: @"";
            NSLog(@"%@ JSON errno=%@ msg=%@", TAG, code, msg);
        }
    }
    return r;
}

static void (*o_setText)(id, SEL, NSString *);
static void h_setText(id self, SEL _cmd, NSString *t) {
    if ([t containsString:@"\u9891\u7e41"] || [t containsString:@"\u7a0d\u540e"])
        NSLog(@"%@ UI \"%@\"", TAG, t);
    o_setText(self, _cmd, t);
}

__attribute__((constructor))
static void smslog_init(void) {
    Class s = objc_getClass("NSURLSession");
    if (s) {
        Method m = class_getInstanceMethod(s, sel_registerName("dataTaskWithRequest:completionHandler:"));
        if (m) { o_taskCG = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)h_taskCG); }
    }
    Class j = objc_getClass("NSJSONSerialization");
    if (j) {
        Method m = class_getClassMethod(j, sel_registerName("JSONObjectWithData:options:error:"));
        if (m) { o_json = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)h_json); }
    }
    Class l = objc_getClass("UILabel");
    if (l) {
        Method m = class_getInstanceMethod(l, sel_registerName("setText:"));
        if (m) { o_setText = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)h_setText); }
    }
    NSLog(@"%@ installed (session=%d json=%d label=%d)", TAG, s != nil, j != nil, l != nil);
}
