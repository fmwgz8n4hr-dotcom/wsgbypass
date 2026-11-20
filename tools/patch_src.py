#!/usr/bin/env python3
"""对解包后的源码打补丁：ptrace 头、MSHookFunction 兜底、fat 校验、构造器延后、扫描收窄。"""
import os, sys

root = sys.argv[1] if len(sys.argv) > 1 else 'src'

OLD_HDR = '''#else
  #define WSG_HAVE_C_HOOK 0
  static inline void wsg_hook_c(void *target, void *repl, void **orig) {
      (void)target; (void)repl;
      if (orig) *orig = NULL;
  }
#endif'''

NEW_HDR = '''#else
  // 运行期 dlsym 找 MSHookFunction（ElleKit / CydiaSubstrate / libhooker 都导出）
  typedef void (*wsg_mshook_fn)(void *, void *, void **);
  static inline wsg_mshook_fn wsg_mshook(void) {
      static wsg_mshook_fn fn = 0;
      static int probed = 0;
      if (!probed) {
          probed = 1;
          fn = (wsg_mshook_fn)dlsym(RTLD_DEFAULT, "MSHookFunction");
          if (!fn) fn = (wsg_mshook_fn)dlsym(RTLD_DEFAULT, "MSHookFunctionEx");
      }
      return fn;
  }
  #define WSG_HAVE_C_HOOK 1
  static inline void wsg_hook_c(void *target, void *repl, void **orig) {
      if (!target) return;
      wsg_mshook_fn f = wsg_mshook();
      if (f) f(target, repl, orig);
      else if (orig) *orig = NULL;
  }
  static inline BOOL wsg_c_hooks_ok(void) { return wsg_mshook() != 0; }
#endif'''

COMPAT = '''#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>

typedef struct __SecTask *SecTaskRef;
typedef struct __SecCode *SecCodeRef;
typedef struct __SecStaticCode *SecStaticCodeRef;
typedef struct __SecRequirement *SecRequirementRef;
typedef uint32_t SecCSFlags;

static inline CFStringRef _wsg_secinfo(const char *n) {
    CFStringRef v = *(CFStringRef *)dlsym(RTLD_DEFAULT, n);
    return v ? v : CFSTR("__missing__");
}
#define kSecCodeInfoIdentifier     _wsg_secinfo("kSecCodeInfoIdentifier")
#define kSecCodeInfoTeamIdentifier _wsg_secinfo("kSecCodeInfoTeamIdentifier")
#define kSecCodeInfoUnique         _wsg_secinfo("kSecCodeInfoUnique")
#define kSecCodeInfoFlags          _wsg_secinfo("kSecCodeInfoFlags")
'''

h = os.path.join(root, 'tweak', 'wsgbypass.h')
s = open(h, encoding='utf-8').read()
if OLD_HDR not in s:
    sys.exit('FAIL: wsgbypass.h anchor not found')
open(h, 'w', encoding='utf-8').write(s.replace(OLD_HDR, NEW_HDR))

p = os.path.join(root, 'tweak', 'Tweak.xm')
t = open(p, encoding='utf-8').read()
t = t.replace('#import <sys/ptrace.h>',
              '#if __has_include(<sys/ptrace.h>)\n#import <sys/ptrace.h>\n#else\n'
              'extern int ptrace(int _req, pid_t _pid, caddr_t _addr, int _data);\n#endif')
OLD_LOG = ('#if WSG_HAVE_C_HOOK\n        LOG("C 钩子可用");\n#else\n'
           '        LOG("警告：无 substrate/dobby，仅 ObjC 层生效");\n#endif')
if OLD_LOG not in t:
    sys.exit('FAIL: Tweak.xm log anchor not found')
t = t.replace(OLD_LOG, '        LOG("C hooks: %s", wsg_c_hooks_ok() ? "ON" : "OFF");')
open(p, 'w', encoding='utf-8').write(t)

open(os.path.join(root, 'tweak', 'compat_private.h'), 'w', encoding='utf-8').write(COMPAT)
print('patched ok')

b = os.path.join(root, 'tools', 'build_deb.py')
s2 = open(b, encoding='utf-8').read()
OLD_V = ('    if len(data) >= 4 and struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:\n'
         '        errs.append("不是 64 位 Mach-O（magic != 0xfeedfacf）")\n'
         '    elif len(data) >= 16:\n'
         '        cputype, _, filetype = struct.unpack_from("<iiI", data, 4)\n'
         '        if cputype != 0x0100000C:\n'
         '            errs.append(f"不是 arm64（cputype={cputype:#x}）")\n'
         '        if filetype != 6:\n'
         '            errs.append(f"不是 dylib（filetype={filetype}）")')
NEW_V = ('    magic = struct.unpack_from("<I", data, 0)[0] if len(data) >= 4 else 0\n'
         '    if magic in (0xBEBAFECA, 0xBFBAFECA):\n'
         '        pass  # fat, arm64 + arm64e slices\n'
         '    elif magic != 0xFEEDFACF:\n'
         '        errs.append("neither thin nor fat Mach-O")\n'
         '    elif len(data) >= 16:\n'
         '        cputype, _, filetype = struct.unpack_from("<iiI", data, 4)\n'
         '        if cputype != 0x0100000C:\n'
         '            errs.append(f"不是 arm64（cputype={cputype:#x}）")\n'
         '        if filetype != 6:\n'
         '            errs.append(f"不是 dylib（filetype={filetype}）")')
if OLD_V not in s2:
    sys.exit('FAIL: build_deb validate anchor not found')
open(b, 'w', encoding='utf-8').write(s2.replace(OLD_V, NEW_V))
print('build_deb patched')

t = open(p, encoding='utf-8').read()
OLD_INIT = ('__attribute__((constructor))\n'
            'static void wsgbypass_init(void) {\n'
            '    @autoreleasepool {\n')
NEW_INIT = ('static void wsg_install_all(void);\n'
            '__attribute__((constructor))\n'
            'static void wsgbypass_init(void) {\n'
            '    NSLog(@"[wsgbypass] LOADED pid=%d", getpid());\n'
            '    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),\n'
            '                   dispatch_get_main_queue(), ^{\n'
            '        @try { wsg_install_all(); }\n'
            '        @catch (NSException *e) { NSLog(@"[wsgbypass] install failed: %@", e); }\n'
            '    });\n'
            '}\n'
            'static void wsg_install_all(void) {\n'
            '    @autoreleasepool {\n')
if OLD_INIT not in t:
    sys.exit('FAIL: constructor anchor not found')
t = t.replace(OLD_INIT, NEW_INIT)
open(p, 'w', encoding='utf-8').write(t)
print('constructor deferred')

t2 = open(p, encoding='utf-8').read()
OLD_KEYS = ('        "tamper", "Tamper", "jailbr", "Jailbr", "cydia", "Cydia",\n'
            '        "substrate", "Substrate", "frida", "Frida", "cycript",\n')
NEW_KEYS = ('        "tamper", "Tamper", "jailbr", "Jailbr", "cydia", "Cydia",\n'
            '        "frida", "Frida", "cycript",\n')
if OLD_KEYS not in t2:
    sys.exit('FAIL: sweep keys anchor not found')
t2 = t2.replace(OLD_KEYS, NEW_KEYS)
OLD_LOOP = ('    for (unsigned int i = 0; i < total; i++) {\n'
            '        Class c = classes[i];\n')
NEW_LOOP = ('    for (unsigned int i = 0; i < total; i++) {\n'
            '        Class c = classes[i];\n'
            '        const char *cn = class_getName(c);\n'
            '        if (!cn || (!strstr(cn, "Tamper") && !strstr(cn, "Security") &&\n'
            '                    !strstr(cn, "Safety") && !strstr(cn, "Jailbr"))) continue;\n')
if OLD_LOOP not in t2:
    sys.exit('FAIL: sweep loop anchor not found')
t2 = t2.replace(OLD_LOOP, NEW_LOOP)
open(p, 'w', encoding='utf-8').write(t2)
print('sweep narrowed')
