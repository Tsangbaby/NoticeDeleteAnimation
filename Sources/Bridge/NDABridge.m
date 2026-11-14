#import "NDABridge.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>
#import <string.h>
#import <stdlib.h>

extern void NDASwiftStart(void);
__attribute__((constructor)) static void NDABootstrap(void) { NDASwiftStart(); }

static NDAPrepareEffect prepareEffect;
static NDAFinishEffect finishEffect;
static void (*originalRequestRemoval)(id, SEL, id);
static void (*originalListRemoval3)(id, SEL, NSUInteger, BOOL, BOOL);
static void (*originalListRemoval2)(id, SEL, NSUInteger, BOOL);
static void (*originalGroupRemoval)(id, SEL, id);

@interface NDARequestScope : NSObject
@property(nonatomic, strong) id request;
@property(nonatomic, strong) NSHashTable *seenViews;
@property(nonatomic) NSUInteger attempts;
@end
@implementation NDARequestScope
@end
// All scope and UIKit work is main-thread-only. Not a global time-window trigger:
// unrelated asynchronous list operations are intentionally left native.
static NSMutableArray<NDARequestScope *> *scopes;

static const char *NDAUnqualified(const char *type) {
    while (*type && strchr("rnNoORV", *type)) ++type;
    return type;
}
static BOOL NDAHasABI(Class cls, SEL selector, const char *result,
                      NSUInteger count, const char **arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != count + 2) return NO;
    char *ret = method_copyReturnType(method);
    BOOL valid = ret && strcmp(NDAUnqualified(ret), result) == 0;
    free(ret);
    for (NSUInteger i = 0; valid && i < count; ++i) {
        char *type = method_copyArgumentType(method, (unsigned int)i + 2);
        const char *plain = type ? NDAUnqualified(type) : "";
        // Object encodings can include quoted class names. Blocks (@?) are not objects here.
        valid = strcmp(arguments[i], "@") == 0
            ? plain[0] == '@' && plain[1] != '?'
            : strcmp(plain, arguments[i]) == 0;
        free(type);
    }
    return valid;
}
static id NDAObjectGetter(id object, NSString *name) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(name);
    if (!NDAHasABI(object_getClass(object), selector, "@", 0, NULL)) return nil;
    return ((id (*)(id, SEL))[object methodForSelector:selector])(object, selector);
}

static id NDAPrepare(UIView *cell, UIView *surface) {
    NDARequestScope *scope = scopes.lastObject;
    if (!scope || ![cell isKindOfClass:UIView.class]) { NDARecordEvent(@"cell.missing"); return nil; }
    if (scope.attempts >= 8 || [scope.seenViews containsObject:cell]) { NDARecordEvent(@"cell.duplicate"); return nil; }
    [scope.seenViews addObject:cell];
    ++scope.attempts;
    @try {
        // Do not animate group containers or unrelated removed cells. The request
        // must be IDENTICAL to the specific removeNotificationRequest: argument.
        id controller = NDAObjectGetter(cell, @"notificationViewController");
        if (!controller) controller = NDAObjectGetter(cell, @"contentViewController");
        if (![controller isKindOfClass:UIViewController.class]) { NDARecordEvent(@"cell.controller"); return nil; }
        id request = NDAObjectGetter(controller, @"notificationRequest");
        if (request != scope.request) { NDARecordEvent(@"cell.request_mismatch"); return nil; }
        UIView *source = [(UIViewController *)controller viewIfLoaded];
        if (!source || ![source isDescendantOfView:cell]) { NDARecordEvent(@"cell.source"); return nil; }
        return prepareEffect(source, surface);
    } @catch (__unused NSException *exception) {
        NDARecordEvent(@"cell.exception");
        return nil;
    }
}

static void NDAWithRequest(id self, SEL cmd, id request, void (*original)(id, SEL, id)) {
    if (!NSThread.isMainThread || !request) {
        NDARecordEvent(NSThread.isMainThread ? @"request.nil" : @"request.off_main");
        original(self, cmd, request);
        return;
    }
    // Nested group/top-level removal of the same request shares one dedupe set.
    NDARequestScope *scope = scopes.lastObject;
    if (scope.request == request) {
        original(self, cmd, request);
        return;
    }
    scope = [NDARequestScope new];
    scope.request = request;
    scope.seenViews = [NSHashTable weakObjectsHashTable];
    [scopes addObject:scope];
    @try { original(self, cmd, request); }
    @finally { [scopes removeLastObject]; }
}
static void NDARequestRemoval(id self, SEL cmd, id request) {
    NDARecordEvent(@"request.top");
    NDAWithRequest(self, cmd, request, originalRequestRemoval);
}
static void NDAGroupRemoval(id self, SEL cmd, id request) {
    NDARecordEvent(@"request.group");
    NDAWithRequest(self, cmd, request, originalGroupRemoval);
}

static id NDAListPrepare(id self, NSUInteger index) {
    NDARecordEvent(@"list.enter");
    if (!NSThread.isMainThread) { NDARecordEvent(@"list.off_main"); return nil; }
    if (!scopes.lastObject) { NDARecordEvent(@"list.no_scope"); return nil; }
    @try {
        SEL getter = NSSelectorFromString(@"_visibleViewAtIndex:");
        const char *args[] = { @encode(NSUInteger) };
        if (!NDAHasABI(object_getClass(self), getter, "@", 1, args)) {
            NDARecordEvent(@"list.getter_abi"); return nil;
        }
        id cell = ((id (*)(id, SEL, NSUInteger))[self methodForSelector:getter])(self, getter, index);
        return NDAPrepare(cell, self);
    } @catch (__unused NSException *exception) {
        NDARecordEvent(@"list.getter_exception"); return nil;
    }
}

static void NDAListRemoval3(id self, SEL cmd, NSUInteger index, BOOL animated, BOOL displaced) {
    id handle = NDAListPrepare(self, index);
    BOOL success = NO;
    @try {
        originalListRemoval3(self, cmd, index, handle ? NO : animated, displaced);
        success = YES;
    } @finally { if (handle) finishEffect(handle, success); }
}
static void NDAListRemoval2(id self, SEL cmd, NSUInteger index, BOOL animated) {
    id handle = NDAListPrepare(self, index);
    BOOL success = NO;
    @try {
        originalListRemoval2(self, cmd, index, handle ? NO : animated);
        success = YES;
    } @finally { if (handle) finishEffect(handle, success); }
}

BOOL NDAInstallHooks(NDAPrepareEffect prepare, NDAFinishEffect finish) {
    static BOOL topInstalled = NO, groupInstalled = NO, twoInstalled = NO, threeInstalled = NO;
    if (!NSThread.isMainThread || !prepare || !finish) return NO;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return NO;
    prepareEffect = [prepare copy];
    finishEffect = [finish copy];
    if (!scopes) scopes = [NSMutableArray array];
    Class structured = NSClassFromString(@"NCNotificationStructuredListViewController");
    Class group = NSClassFromString(@"NCNotificationGroupList");
    const char *objectArgs[] = { "@" };
    SEL requestSelector = NSSelectorFromString(@"removeNotificationRequest:");
    BOOL topRequest = NDAHasABI(structured, requestSelector, "v", 1, objectArgs);
    BOOL groupRequest = NDAHasABI(group, requestSelector, "v", 1, objectArgs);
    Class list = NSClassFromString(@"NCNotificationListView");
    const char *threeArgs[] = { @encode(NSUInteger), @encode(BOOL), @encode(BOOL) };
    const char *twoArgs[] = { @encode(NSUInteger), @encode(BOOL) };
    const char *getterArgs[] = { @encode(NSUInteger) };
    SEL three = NSSelectorFromString(@"removeViewAtIndex:animated:isHorizontallyDisplaced:");
    SEL two = NSSelectorFromString(@"removeViewAtIndex:animated:");
    BOOL listGetter = [list isSubclassOfClass:UIScrollView.class] &&
        NDAHasABI(list, NSSelectorFromString(@"_visibleViewAtIndex:"), "@", 1, getterArgs);
    BOOL modern3 = listGetter && NDAHasABI(list, three, "v", 3, threeArgs);
    BOOL modern2 = listGetter && NDAHasABI(list, two, "v", 2, twoArgs);
    if (!topRequest && !groupRequest) NDARecordEvent(@"install.wait_request");
    if (!modern3 && !modern2) NDARecordEvent(@"install.wait_list");
    if (topRequest && !topInstalled) {
        MSHookMessageEx(structured, requestSelector, (IMP)NDARequestRemoval, (IMP *)&originalRequestRemoval);
        topInstalled = YES; NDARecordEvent(@"install.top");
    }
    if (groupRequest && !groupInstalled) {
        MSHookMessageEx(group, requestSelector, (IMP)NDAGroupRemoval, (IMP *)&originalGroupRemoval);
        groupInstalled = YES; NDARecordEvent(@"install.group");
    }
    // Some releases route different callers through different overloads. Shared
    // scope.seenViews prevents double capture if these overloads call each other.
    if (modern3 && !threeInstalled) {
        MSHookMessageEx(list, three, (IMP)NDAListRemoval3, (IMP *)&originalListRemoval3);
        threeInstalled = YES; NDARecordEvent(@"install.list3");
    }
    if (modern2 && !twoInstalled) {
        MSHookMessageEx(list, two, (IMP)NDAListRemoval2, (IMP *)&originalListRemoval2);
        twoInstalled = YES; NDARecordEvent(@"install.list2");
    }
    BOOL ready = (topInstalled || groupInstalled) && (twoInstalled || threeInstalled);
    static BOOL readyAnnounced = NO;
    if (ready && !readyAnnounced) {
        readyAnnounced = YES;
        NDARecordEvent(@"install.ready");
    }
    return ready;
}
