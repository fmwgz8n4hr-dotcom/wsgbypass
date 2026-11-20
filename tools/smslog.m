// smslog.m v2 —— 落盘诊断：写入 App 沙盒 Documents/wsgbypass.log
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdio.h>

static NSString *gPath = nil;
static NSInteger gLines = 0;

static void WLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[wsgbypass-net] %@", s);
    if (!gPath) {
        NSString *doc = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:doc withIntermediateDirectories:YES attributes:nil error:NULL];
        gPath = [doc stringByAppendingPathComponent:@"wsgbypass.log"];
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:gPath error:NULL];
        if ([a fileSize] > 300000) { [[NSFileManager defaultManager] removeItemAtPath:gPath error:NULL]; }
    }
    if (++gLines > 800) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                      [[NSDate date] descriptionWithLocale:nil], s];
    FILE *f = fopen(gPath.UTF8String, "a");
    if (f) { fwrite(line.UTF8String, 1, strlen(line.UTF8String), f); fclose(f); }
}

static BOOL Interesting(NSString *u) {
    if (u.length == 0) return NO;
    NSString *l = u.lowercaseString;
    return ([l containsString:@"passport"] || [l containsString:@"codemt"] ||
            [l containsString:@"sms"] || [l containsString:@"login"] ||
            [l containsString:@"signin"] || [l containsString:@"verify"] ||
            [l containsString:@"cell"] || [l containsString:@"account"]);
}

static void LogBody(NSString *tag, NSData *d) {
    if (d.length == 0) return;
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!s) { WLog(@"%@ <binary %lu B>", tag, (unsigned long)d.length); return; }
    if (s.length > 1200) s = [s substringToIndex:1200];
    WLog(@"%@ %@", tag, s);
}

static NSURLSessionDataTask *(*o_taskCG)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
static NSURLSessionDataTask *h_taskCG(id self, SEL _cmd, NSURLRequest *req,
                                      void (^cb)(NSData *, NSURLResponse *, NSError *)) {
    if (!Interesting(req.URL.absoluteString)) return o_taskCG(self, _cmd, req, cb);
    WLog(@">> %@ %@", req.HTTPMethod, req.URL.absoluteString);
    LogBody(@"REQ", req.HTTPBody);
    NSString *url = req.URL.absoluteString;
    void (^wrap)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        WLog(@"<< HTTP %ld %@", (long)[(NSHTTPURLResponse *)r statusCode], url);
        LogBody(@"RSP", d);
        if (e) WLog(@"!! %@", e.localizedDescription);
        if (cb) cb(d, r, e);
    };
    return o_taskCG(self, _cmd, req, wrap);
}

static NSURLSessionDataTask *(*o_task)(id, SEL, NSURLRequest *);
static NSURLSessionDataTask *h_task(id self, SEL _cmd, NSURLRequest *req) {
    if (Interesting(req.URL.absoluteString)) {
        WLog(@">> (delegate) %@ %@", req.HTTPMethod, req.URL.absoluteString);
        LogBody(@"REQ", req.HTTPBody);
    }
    return o_task(self, _cmd, req);
}

static id (*o_json)(id, SEL, NSData *, NSJSONReadingOptions, NSError **);
static id h_json(id self, SEL _cmd, NSData *d, NSJSONReadingOptions opt, NSError **err) {
    id r = o_json(self, _cmd, d, opt, err);
    if ([r isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)r;
        id code = dict[@"errno"] ?: dict[@"code"] ?: dict[@"errNo"];
        if (code) {
            id msg = dict[@"error"] ?: dict[@"errmsg"] ?: dict[@"message"] ?: @"";
            WLog(@"JSON errno=%@ msg=%@", code, msg);
        }
    }
    return r;
}

static void (*o_setText)(id, SEL, NSString *);
static void h_setText(id self, SEL _cmd, NSString *t) {
    if ([t containsString:@"\u9891\u7e41"] || [t containsString:@"\u7a0d\u540e"])
        WLog(@"UI \"%@\"", t);
    o_setText(self, _cmd, t);
}

__attribute__((constructor))
static void smslog_init(void) {
    WLog(@"=== LOADED v2 pid=%d bundle=%@ ===", getpid(), [[NSBundle mainBundle] bundleIdentifier]);
    WLog(@"classes: NSURLSession=%d NSJSONSerialization=%d UILabel=%d CronetEngine=%d",
         objc_getClass("NSURLSession") != nil,
         objc_getClass("NSJSONSerialization") != nil,
         objc_getClass("UILabel") != nil,
         objc_getClass("CronetEngine") != nil);
    Class s = objc_getClass("NSURLSession");
    if (s) {
        Method m = class_getInstanceMethod(s, sel_registerName("dataTaskWithRequest:completionHandler:"));
        if (m) { o_taskCG = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)h_taskCG); }
        Method m2 = class_getInstanceMethod(s, sel_registerName("dataTaskWithRequest:"));
        if (m2) { o_task = (void *)method_getImplementation(m2); method_setImplementation(m2, (IMP)h_task); }
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
    WLog(@"hooks installed");
}
