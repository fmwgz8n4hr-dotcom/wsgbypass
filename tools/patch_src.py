#!/usr/bin/env python3
"""对解包后的源码打两处补丁：ptrace 头 + 运行期 MSHookFunction 兜底。"""
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
