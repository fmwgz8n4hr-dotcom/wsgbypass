// fakesuccess.m v2 —— 53001 改写成成功，并补齐 App 需要的字段（time/requestid/traceid）
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static id (*o_json)(id, SEL, NSData *, NSJSONReadingOptions, NSError **);

static NSString *NowString(void) {
    static NSDateFormatter *f = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        f.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    });
    return [f stringFromDate:[NSDate date]];
}

static NSString *RandomDigits(NSUInteger n) {
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%d", arc4random_uniform(10)];
    return s;
}

static NSString *RandomHex(NSUInteger n) {
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%x", arc4random_uniform(16)];
    return s;
}

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
                m[@"time"] = NowString();
                m[@"requestid"] = RandomDigits(19);
                m[@"traceid"] = RandomHex(32);
                m[@"prompt"] = @"";
                m[@"code_type"] = @0;
                m[@"support_voice"] = @NO;
                NSMutableDictionary *dd = [d[@"data"] isKindOfClass:[NSDictionary class]]
                    ? [d[@"data"] mutableCopy] : [NSMutableDictionary dictionary];
                dd[@"code_len"] = @6;
                dd[@"code_tag"] = @"【滴滴出行】";
                m[@"data"] = dd;
                NSLog(@"[wsgbypass-fake] 53001 -> 0 (time=%@ rid=%@)", m[@"time"], m[@"requestid"]);
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
        NSLog(@"[wsgbypass-fake] installed v2");
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-fake] init failed: %@", e);
    }
}
