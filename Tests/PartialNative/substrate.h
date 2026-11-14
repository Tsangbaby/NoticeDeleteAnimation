#pragma once
#include <objc/runtime.h>
#ifdef __cplusplus
extern "C" {
#endif
// The only replaced dependency: real runtime IMP replacement, NOT Substrate.
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);
#ifdef __cplusplus
}
#endif
