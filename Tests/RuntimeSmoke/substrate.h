// Test-only substitute for the single Substrate entry point used by the loader.
// This is NOT Substrate: main.m swaps real Objective-C Method IMPs and records them.
#ifndef NL_RUNTIME_SMOKE_SUBSTRATE_H
#define NL_RUNTIME_SMOKE_SUBSTRATE_H
#import <objc/runtime.h>
#ifdef __cplusplus
extern "C" {
#endif
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);
#ifdef __cplusplus
}
#endif
#endif
