#ifndef NL_STUB_SUBSTRATE_H
#define NL_STUB_SUBSTRATE_H
#include <objc/runtime.h>
void MSHookMessageEx(Class cls, SEL sel, IMP replacement, IMP *original);
void MSHookFunction(void *symbol, void *replacement, void **original);
#endif
