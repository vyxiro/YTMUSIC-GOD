#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "MSHookMessageEx.h"

void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result) {
    if (!_class || !sel || !imp) return;
    
    Method method = class_getInstanceMethod(_class, sel);
    BOOL isClassMethod = NO;
    if (!method) {
        method = class_getClassMethod(_class, sel);
        isClassMethod = YES;
    }
    if (!method) return;

    Class targetClass = isClassMethod ? object_getClass((id)_class) : _class;
    const char *typeEncoding = method_getTypeEncoding(method);

    IMP originalImp = method_getImplementation(method);
    if (result) {
        *result = originalImp;
    }

    if (class_addMethod(targetClass, sel, imp, typeEncoding)) {
        // Method was newly added to targetClass, pointing to new imp
    } else {
        // Method already existed on targetClass, replace implementation
        IMP previous = method_setImplementation(method, imp);
        if (result && previous) {
            *result = previous;
        }
    }
}
