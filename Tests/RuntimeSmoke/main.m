// Real iOS Simulator runtime, production loader/ABI header; no UIApplicationMain.
// Only installer idempotency is exercised. Deletion bodies, renderer, preferences,
// other hook modules and Substrate are explicitly test-only dependency shims.
#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#import <objc/runtime.h>
#import "NLNotificationHookLoader.h"
#import "NLNotificationListHooks.h"
#import "NLRuntimeABI.h"
#import "substrate.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !TARGET_OS_SIMULATOR
#error RuntimeSmoke must be built for a real iOS Simulator SDK/runtime
#endif

@interface NLNotificationHookLoader (RuntimeSmokePrivate)
- (BOOL)installListHooksIfPossible;
@end

static NSUInteger NLChecks, NLDependencyCalls;
static void NLCheck(BOOL ok, const char *expression, int line) {
    if (!ok) {
        fprintf(stderr, "RUNTIME NATIVE FAIL: line %d: %s\n", line, expression);
        exit(1);
    }
    ++NLChecks;
}
#define CHECK(expression) NLCheck(!!(expression), #expression, __LINE__)

// Link dependency shims only; production NLDustRenderer.m is NOT linked.
@interface NLDustRenderer : UIView
+ (void)prewarmRenderer;
@end
@implementation NLDustRenderer
+ (void)prewarmRenderer { ++NLDependencyCalls; }
@end
void NLLoadPreferences(void) { ++NLDependencyCalls; }
BOOL NLInstallIconDustHooks(void) { ++NLDependencyCalls; return YES; }
BOOL NLInstallBannerDustHooks(void) { ++NLDependencyCalls; return YES; }
void NLInstallIslandDustHooks(void) { ++NLDependencyCalls; }
void NLInstallLockScreenDustHooks(void) { ++NLDependencyCalls; }

static NSUInteger NLYesCalls, NLNoCalls, NLLegacyCalls;
static NSUInteger NLObjectCalls, NLIntegerCalls, NLDoubleCalls, NLExtraCalls;
@interface NLABIProbe : NSObject
- (BOOL)yesFlag;
- (BOOL)noFlag;
- (signed char)legacyFlag;
- (id)objectValue;
- (NSInteger)integerState;
- (double)doubleValue;
- (BOOL)flagWithExtra:(NSUInteger)value;
@end
@implementation NLABIProbe
- (BOOL)yesFlag { ++NLYesCalls; return YES; }
- (BOOL)noFlag { ++NLNoCalls; return NO; }
- (signed char)legacyFlag { ++NLLegacyCalls; return 1; }
- (id)objectValue { ++NLObjectCalls; return @"object-fixture"; }
- (NSInteger)integerState { ++NLIntegerCalls; return -42; }
- (double)doubleValue { ++NLDoubleCalls; return 13.25; }
- (BOOL)flagWithExtra:(NSUInteger)value { ++NLExtraCalls; return value != 0; }
@end

static void NLTestABI(void) {
    CHECK(strcmp(NLABIUnqualified(NULL), "") == 0);
    CHECK(strcmp(NLABIUnqualified("rnNoORVB"), "B") == 0);
    CHECK(NLABITypeMatches("rv", "v"));
    CHECK(NLABITypeMatches("r@\"NSObject\"", "@"));
    CHECK(NLABITypeMatches("@", "@"));
    CHECK(!NLABITypeMatches("@?", "@"));
    CHECK(NLABITypeMatches("r@?", "@?"));
    CHECK(!NLABITypeMatches("@\"NSObject\"", "@?"));
    CHECK(NLABITypeMatches("rB", "B"));
    CHECK(NLABITypeMatches("c", "B"));
    CHECK(!NLABITypeMatches("C", "B"));
    CHECK(!NLABITypeMatches("Bgarbage", "B"));
    CHECK(!NLABITypeMatches("q", "Q"));
    CHECK(!NLABITypeMatches("d", "B"));
    CHECK(!NLABITypeMatches("^@", "@"));
    CHECK(!NLABITypeMatches(NULL, "@"));
    CHECK(NLABITypeMatches("rd", "d"));
    CHECK(!NLABITypeMatches("f", "d"));

    Class cls = [NLABIProbe class];
    const char *indexArgument[] = { @encode(NSUInteger) };
    const char *signedIndexArgument[] = { @encode(NSInteger) };
    CHECK(NLABIMethod(cls, @selector(yesFlag), "B", 0, NULL));
    CHECK(NLABIMethod(cls, @selector(noFlag), "B", 0, NULL));
    CHECK(NLABIMethod(cls, @selector(legacyFlag), "B", 0, NULL));
    CHECK(NLABIMethod(cls, @selector(objectValue), "@", 0, NULL));
    CHECK(NLABIMethod(cls, @selector(integerState), @encode(NSInteger), 0, NULL));
    CHECK(NLABIMethod(cls, @selector(doubleValue), "d", 0, NULL));
    CHECK(!NLABIMethod(cls, @selector(doubleValue), "f", 0, NULL));
    CHECK(!NLABIMethod(cls, @selector(integerState), @encode(NSUInteger), 0, NULL));
    CHECK(!NLABIMethod(cls, @selector(yesFlag), "@", 0, NULL));
    CHECK(!NLABIMethod(cls, @selector(objectValue), "B", 0, NULL));
    CHECK(!NLABIMethod(cls, @selector(flagWithExtra:), "B", 0, NULL));
    CHECK(NLABIMethod(cls, @selector(flagWithExtra:), "B", 1, indexArgument));
    CHECK(!NLABIMethod(cls, @selector(flagWithExtra:), "B", 1, signedIndexArgument));
    CHECK(!NLABIMethod(cls, @selector(yesFlag), "B", 1, indexArgument));
    CHECK(!NLABIMethod(Nil, @selector(yesFlag), "B", 0, NULL));
    CHECK(!NLABIMethod(cls, NSSelectorFromString(@"missingFlag"), "B", 0, NULL));

    NLABIProbe *probe = [NLABIProbe new];
    CHECK(NLABIReadBool(probe, @selector(yesFlag)));
    CHECK(!NLABIReadBool(probe, @selector(noFlag)));
    CHECK(NLABIReadBool(probe, @selector(legacyFlag)));
    CHECK(NLYesCalls == 1 && NLNoCalls == 1 && NLLegacyCalls == 1);
    CHECK(!NLABIReadBool(nil, @selector(yesFlag)));
    CHECK(!NLABIReadBool(probe, NSSelectorFromString(@"missingFlag")));
    CHECK(!NLABIReadBool(probe, @selector(objectValue)));
    CHECK(!NLABIReadBool(probe, @selector(integerState)));
    CHECK(!NLABIReadBool(probe, @selector(doubleValue)));
    CHECK(!NLABIReadBool(probe, @selector(flagWithExtra:)));
    CHECK(NLObjectCalls == 0 && NLIntegerCalls == 0 && NLDoubleCalls == 0 && NLExtraCalls == 0);
    CHECK(NLYesCalls == 1 && NLNoCalls == 1 && NLLegacyCalls == 1);
}

typedef struct {
    NSUInteger count;
    __unsafe_unretained id receiver;
    SEL selector;
    NSUInteger index;
    BOOL animated, displaced;
} NLCall;
static NLCall NLNativeBasicCall, NLNativeDisplacedCall, NLNativeClearCall;
static NLCall NLReplacementBasicCall, NLReplacementDisplacedCall, NLReplacementClearCall;
static SEL NLVisibleSelector, NLBasicSelector, NLDisplacedSelector, NLClearSelector;
static NSUInteger NLBasicHooks, NLDisplacedHooks, NLClearHooks;
static NSUInteger NLVisibleCalls, NLInvalidVisibleCalls, NLMasterGetterCalls;
static id NLListFixture;

static void NLRecord(NLCall *call, id receiver, SEL selector, NSUInteger index,
                     BOOL animated, BOOL displaced) {
    ++call->count;
    call->receiver = receiver;
    call->selector = selector;
    call->index = index;
    call->animated = animated;
    call->displaced = displaced;
}
static void NLCheckCall(NLCall *call, id receiver, SEL selector, NSUInteger count,
                        NSUInteger index, BOOL animated, BOOL displaced) {
    CHECK(call->count == count);
    CHECK(call->receiver == receiver);
    CHECK(sel_isEqual(call->selector, selector));
    CHECK(call->index == index);
    CHECK(call->animated == animated);
    CHECK(call->displaced == displaced);
}
static id NLVisible(id self, SEL cmd, NSUInteger index) {
    ++NLVisibleCalls;
    return @"visible-object-fixture";
}
static long long NLInvalidVisible(id self, SEL cmd, NSUInteger index) {
    ++NLInvalidVisibleCalls;
    return -1;
}
static void NLNativeRemove(id self, SEL cmd, NSUInteger index, BOOL animated) {
    NLRecord(&NLNativeBasicCall, self, cmd, index, animated, NO);
}
static void NLNativeDisplaced(id self, SEL cmd, NSUInteger index, BOOL animated, BOOL displaced) {
    NLRecord(&NLNativeDisplacedCall, self, cmd, index, animated, displaced);
}
static void NLNativeClear(id self, SEL cmd) {
    NLRecord(&NLNativeClearCall, self, cmd, 0, NO, NO);
}
static id NLMasterListView(id self, SEL cmd) {
    ++NLMasterGetterCalls;
    return NLListFixture;
}

// TEST-ONLY deletion bodies: count, capture all arguments, then forward directly
// to the saved native IMP with its exact ABI. Never perform deletion/rendering.
void NLRemoveView(id self, SEL cmd, NSUInteger index, BOOL animated) {
    CHECK(NLOriginalRemove && NLOriginalRemove != (IMP)NLRemoveView);
    CHECK(NLReplacementBasicCall.count < 4); // fail boundedly even on a regression
    NLRecord(&NLReplacementBasicCall, self, cmd, index, animated, NO);
    ((void (*)(id, SEL, NSUInteger, BOOL))NLOriginalRemove)(self, cmd, index, animated);
}
void NLRemoveDisplacedView(id self, SEL cmd, NSUInteger index, BOOL animated, BOOL displaced) {
    CHECK(NLOriginalRemoveDisplaced && NLOriginalRemoveDisplaced != (IMP)NLRemoveDisplacedView);
    CHECK(NLReplacementDisplacedCall.count < 4);
    NLRecord(&NLReplacementDisplacedCall, self, cmd, index, animated, displaced);
    ((void (*)(id, SEL, NSUInteger, BOOL, BOOL))NLOriginalRemoveDisplaced)(self, cmd, index, animated, displaced);
}
void NLClearAll(id self, SEL cmd) {
    CHECK(NLOriginalClearAll && NLOriginalClearAll != (IMP)NLClearAll);
    CHECK(NLReplacementClearCall.count < 4);
    NLRecord(&NLReplacementClearCall, self, cmd, 0, NO, NO);
    ((void (*)(id, SEL))NLOriginalClearAll)(self, cmd);
}

// TEST-ONLY Substrate substitute: real Method/IMP lookup and runtime replacement.
// No idempotency guard here: a duplicate installation really overwrites *original
// with the previous replacement, so production guard regressions cannot be hidden.
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    CHECK(cls && selector && replacement && original);
    Method method = class_getInstanceMethod(cls, selector);
    CHECK(method != NULL);
    IMP previous = method_getImplementation(method);
    *original = method_setImplementation(method, replacement);
    CHECK(*original == previous);
    CHECK(method_getImplementation(method) == replacement);
    if (sel_isEqual(selector, NLBasicSelector)) ++NLBasicHooks;
    else if (sel_isEqual(selector, NLDisplacedSelector)) ++NLDisplacedHooks;
    else if (sel_isEqual(selector, NLClearSelector)) ++NLClearHooks;
    else CHECK(NO);
}

static void NLAssertInstalled(Class listClass, Class masterClass) {
    CHECK(NLBasicHooks == 1 && NLDisplacedHooks == 1);
    CHECK(NLClearHooks == (masterClass ? 1u : 0u));
    CHECK(NLOriginalRemove == (IMP)NLNativeRemove);
    CHECK(NLOriginalRemoveDisplaced == (IMP)NLNativeDisplaced);
    CHECK(method_getImplementation(class_getInstanceMethod(listClass, NLBasicSelector)) == (IMP)NLRemoveView);
    CHECK(method_getImplementation(class_getInstanceMethod(listClass, NLDisplacedSelector)) == (IMP)NLRemoveDisplacedView);
    if (masterClass) {
        CHECK(NLOriginalClearAll == (IMP)NLNativeClear);
        CHECK(method_getImplementation(class_getInstanceMethod(masterClass, NLClearSelector)) == (IMP)NLClearAll);
    } else CHECK(NLOriginalClearAll == NULL);
}
static void NLAddMethod(Class cls, SEL selector, IMP implementation, NSString *types) {
    CHECK(class_addMethod(cls, selector, implementation, types.UTF8String));
}
static void NLExerciseRemovals(id list, NSUInteger count, NSUInteger index, BOOL animated, BOOL displaced) {
    // Message lookup goes through the real installed methods; only forwarding uses
    // NLOriginal*. A high-bit NSUInteger also catches accidental index truncation.
    ((void (*)(id, SEL, NSUInteger, BOOL))[list methodForSelector:NLBasicSelector])
        (list, NLBasicSelector, index, animated);
    ((void (*)(id, SEL, NSUInteger, BOOL, BOOL))[list methodForSelector:NLDisplacedSelector])
        (list, NLDisplacedSelector, index - 1, animated, displaced);
    NLCheckCall(&NLReplacementBasicCall, list, NLBasicSelector, count, index, animated, NO);
    NLCheckCall(&NLNativeBasicCall, list, NLBasicSelector, count, index, animated, NO);
    NLCheckCall(&NLReplacementDisplacedCall, list, NLDisplacedSelector, count, index - 1, animated, displaced);
    NLCheckCall(&NLNativeDisplacedCall, list, NLDisplacedSelector, count, index - 1, animated, displaced);
}
static void NLExerciseClear(id master, NSUInteger count) {
    ((void (*)(id, SEL))[master methodForSelector:NLClearSelector])(master, NLClearSelector);
    NLCheckCall(&NLReplacementClearCall, master, NLClearSelector, count, 0, NO, NO);
    NLCheckCall(&NLNativeClearCall, master, NLClearSelector, count, 0, NO, NO);
}

static void NLTestInstaller(BOOL invalidAccessor) {
    NLVisibleSelector = NSSelectorFromString(@"_visibleViewAtIndex:");
    NLBasicSelector = NSSelectorFromString(@"removeViewAtIndex:animated:");
    NLDisplacedSelector = NSSelectorFromString(@"removeViewAtIndex:animated:isHorizontallyDisplaced:");
    NLClearSelector = NSSelectorFromString(@"clearAll");
    CHECK(NSClassFromString(@"NCNotificationListView") == Nil);
    CHECK(NSClassFromString(@"NCNotificationMasterList") == Nil);
    CHECK(NLOriginalRemove == NULL && NLOriginalRemoveDisplaced == NULL && NLOriginalClearAll == NULL);

    NLNotificationHookLoader *loader = [NLNotificationHookLoader sharedLoader];
    CHECK(![loader installListHooksIfPossible]); // no list class yet
    CHECK(NLBasicHooks == 0 && NLDisplacedHooks == 0 && NLClearHooks == 0);
    NSString *accessorTypes = [NSString stringWithFormat:@"@@:%s", @encode(NSUInteger)];
    Class superclass = [UIView class];
    if (invalidAccessor) {
        // class_replaceMethod does NOT change the encoding of an existing local
        // method. Inherit the wrong getter so replacement adds a correctly typed
        // local override instead of silently keeping the old 'q' encoding.
        superclass = objc_allocateClassPair(superclass, "NLInvalidAccessorBase", 0);
        CHECK(superclass != Nil);
        NLAddMethod(superclass, NLVisibleSelector, (IMP)NLInvalidVisible,
                    [NSString stringWithFormat:@"q@:%s", @encode(NSUInteger)]);
        objc_registerClassPair(superclass);
    }
    Class listClass = objc_allocateClassPair(superclass, "NCNotificationListView", 0);
    CHECK(listClass != Nil);
    if (!invalidAccessor) NLAddMethod(listClass, NLVisibleSelector, (IMP)NLVisible, accessorTypes);
    NLAddMethod(listClass, NLBasicSelector, (IMP)NLNativeRemove,
                [NSString stringWithFormat:@"v@:%s%s", @encode(NSUInteger), @encode(BOOL)]);
    NLAddMethod(listClass, NLDisplacedSelector, (IMP)NLNativeDisplaced,
                [NSString stringWithFormat:@"v@:%s%s%s", @encode(NSUInteger), @encode(BOOL), @encode(BOOL)]);
    objc_registerClassPair(listClass);
    CHECK([listClass isSubclassOfClass:[UIView class]]);
    const char *indexArgument[] = { @encode(NSUInteger) };
    if (invalidAccessor) {
        CHECK(NLABIMethod(listClass, NLVisibleSelector, "q", 1, indexArgument));
        CHECK(!NLABIMethod(listClass, NLVisibleSelector, "@", 1, indexArgument));
        // 'q' passes the old loose return scan but must fail the exact object ABI.
        for (NSUInteger i = 0; i < 2; ++i) CHECK(![loader installListHooksIfPossible]);
        CHECK(NLBasicHooks == 0 && NLDisplacedHooks == 0 && NLClearHooks == 0);
        CHECK(NLOriginalRemove == NULL && NLOriginalRemoveDisplaced == NULL && NLOriginalClearAll == NULL);
        CHECK(method_getImplementation(class_getInstanceMethod(listClass, NLBasicSelector)) == (IMP)NLNativeRemove);
        CHECK(method_getImplementation(class_getInstanceMethod(listClass, NLDisplacedSelector)) == (IMP)NLNativeDisplaced);
        CHECK(NLInvalidVisibleCalls == 0);
        CHECK(class_replaceMethod(listClass, NLVisibleSelector, (IMP)NLVisible, accessorTypes.UTF8String) == NULL);
        CHECK(method_getImplementation(class_getInstanceMethod(listClass, NLVisibleSelector)) == (IMP)NLVisible);
    }
    CHECK(NLABIMethod(listClass, NLVisibleSelector, "@", 1, indexArgument));
    CHECK([loader installListHooksIfPossible]);
    NLAssertInstalled(listClass, Nil);
    CHECK([loader installListHooksIfPossible]); // immediate second attempt
    NLAssertInstalled(listClass, Nil);
    // Bounded synchronous retries, not delayed selectors/run-loop scheduling.
    for (NSUInteger i = 0; i < 16; ++i) {
        CHECK([loader installListHooksIfPossible]);
        NLAssertInstalled(listClass, Nil);
    }
    NLListFixture = [[listClass alloc] initWithFrame:CGRectZero];
    CHECK(NLListFixture != nil);
    NLExerciseRemovals(NLListFixture, 1, NSUIntegerMax - 23, YES, NO);

    CHECK(NSClassFromString(@"NCNotificationMasterList") == Nil);
    Class masterClass = objc_allocateClassPair([NSObject class], "NCNotificationMasterList", 0);
    CHECK(masterClass != Nil);
    NLAddMethod(masterClass, NLClearSelector, (IMP)NLNativeClear, @"v@:");
    NLAddMethod(masterClass, NSSelectorFromString(@"masterListView"), (IMP)NLMasterListView, @"@@:");
    objc_registerClassPair(masterClass);
    CHECK([loader installListHooksIfPossible]); // only the newly available hook
    NLAssertInstalled(listClass, masterClass);
    id master = [masterClass new];
    NLExerciseClear(master, 1);
    CHECK([loader installListHooksIfPossible]);
    NLAssertInstalled(listClass, masterClass);
    for (NSUInteger i = 0; i < 16; ++i) {
        CHECK([loader installListHooksIfPossible]);
        NLAssertInstalled(listClass, masterClass);
    }
    NLExerciseRemovals(NLListFixture, 2, NSUIntegerMax - 47, NO, YES);
    NLExerciseClear(master, 2);
    CHECK(NLVisibleCalls == 0 && NLInvalidVisibleCalls == 0 && NLMasterGetterCalls == 0);
    CHECK(!loader.installRetryScheduled && loader.installRetriesFired == 0);
    CHECK(NLDependencyCalls == 0);
}

int main(int argc, char **argv) {
    @autoreleasepool { @try {
        CHECK(argc == 1 || (argc == 2 && strcmp(argv[1], "--invalid-accessor") == 0));
        BOOL invalidAccessor = argc == 2;
        CHECK([NSThread isMainThread]);
        CHECK(![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]);
        CHECK(NLDependencyCalls == 0); // production constructor must stay dormant
        const char *image = class_getImageName([UIView class]);
        CHECK(image && (strstr(image, "/UIKitCore.framework/") || strstr(image, "/UIKit.framework/")));
        printf("FRAMEWORK UIView %s\n", image);
        NLTestABI();
        NLTestInstaller(invalidAccessor);
        puts("SCOPE: production loader/ABI; test-only deletion/dependency/Substrate shims; no renderer, shader, or private SpringBoard validation");
        printf("RUNTIME NATIVE CASE PASS: %s %lu checks\n",
               invalidAccessor ? "repaired-accessor" : "valid-accessor", (unsigned long)NLChecks);
        return 0;
    } @catch (NSException *exception) {
        fprintf(stderr, "RUNTIME NATIVE FAIL: %s: %s\n", exception.name.UTF8String, exception.reason.UTF8String);
        return 1;
    } }
}
