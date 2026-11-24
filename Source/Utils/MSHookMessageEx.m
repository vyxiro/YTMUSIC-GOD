#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "MSHookMessageEx.h"

void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result) {
    if (result) *result = NULL;
    if (!cls || !sel || !imp) return;

    // Logos already passes the metaclass for + methods.
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;

    const char *enc = method_getTypeEncoding(m);
    IMP orig = method_getImplementation(m);

    if (class_addMethod(cls, sel, imp, enc)) {
        if (result) *result = orig;
    } else {
        IMP prev = method_setImplementation(m, imp);
        if (result && prev) *result = prev;
    }
}
