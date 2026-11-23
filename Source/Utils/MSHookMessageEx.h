#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result);

#ifdef __cplusplus
}
#endif
