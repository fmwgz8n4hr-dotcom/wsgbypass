// devreset.m —— 设备身份重置：首次运行清空 App 钥匙串 + 伪造 IDFV
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>

static NSString *DRMarker(void) {
    NSString *doc = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    return [doc stringByAppendingPathComponent:@"wsgbypass.devreset"];
}

static void DRWipeKeychain(void) {
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecClassInternetPassword,
                          (__bridge id)kSecClassKey ];
    for (id cls in classes) {
        NSDictionary *q = @{ (__bridge id)kSecClass : cls };
        OSStatus st = SecItemDelete((__bridge CFDictionaryRef)q);
        NSLog(@"[wsgbypass-reset] SecItemDelete %@ -> %d", cls, (int)st);
    }
}

static NSUUID *gFakeIDFV = nil;
static id (*o_idfv)(id, SEL);
static id h_idfv(id self, SEL _cmd) {
    if (!gFakeIDFV) {
        NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:@"wsg_fake_idfv"];
        if (s.length == 0) {
            s = [[NSUUID UUID] UUIDString];
            [[NSUserDefaults standardUserDefaults] setObject:s forKey:@"wsg_fake_idfv"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        gFakeIDFV = [[NSUUID alloc] initWithUUIDString:s];
    }
    return gFakeIDFV;
}

__attribute__((constructor))
static void devreset_init(void) {
    @try {
        BOOL done = [[NSFileManager defaultManager] fileExistsAtPath:DRMarker()];
        NSLog(@"[wsgbypass-reset] loaded, alreadyReset=%d", done);
        if (!done) {
            DRWipeKeychain();
            NSString *doc = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
            [[NSFileManager defaultManager] createDirectoryAtPath:doc
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:NULL];
            [[NSFileManager defaultManager] createFileAtPath:DRMarker() contents:[NSData data] attributes:nil];
            NSLog(@"[wsgbypass-reset] keychain wiped, marker written");
        }
        Class d = objc_getClass("UIDevice");
        if (d) {
            Method m = class_getInstanceMethod(d, sel_registerName("identifierForVendor"));
            if (m) {
                o_idfv = (void *)method_getImplementation(m);
                method_setImplementation(m, (IMP)h_idfv);
                NSLog(@"[wsgbypass-reset] identifierForVendor hooked");
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[wsgbypass-reset] failed: %@", e);
    }
}
