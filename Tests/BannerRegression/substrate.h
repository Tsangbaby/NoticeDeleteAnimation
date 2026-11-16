// Test-only IMP shim declaration. NOT Substrate.
#import <objc/runtime.h>
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);
