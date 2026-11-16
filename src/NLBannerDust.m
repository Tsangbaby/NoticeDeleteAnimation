//
//  NLBannerDust.m
//  NoticeDeleteAnimation — 通知消散
//
//  BannerKit（通知横幅）消散。逆向自 1.0.1~test14，地址见各函数。
//
//  横幅和通知列表走的是完全不同的私有类：BannerKit 的 BNContentViewController
//  管理 presentable 栈，卡片视图藏在它自己的 view 层级里。这里的核心工作就是
//  从一个 presentable 反查出真正承载卡片的 UIView，再交给 NLWithdrawalEffect。
//

#import "NLBannerDust.h"
#import "NLPreferences.h"
#import "NLWithdrawalEffect.h"
#import "NLDustRenderer.h"
#import "NLRuntimeABI.h"
#import "NLNotificationListHooks.h"
#import "NLNotificationDismissalSnapshot.h"
#import "NLStatusProbe.h"
#import "NLLockScreenDust.h"
#import "NLIslandDust.h"

#import <objc/runtime.h>
#include <unistd.h>
#import <substrate.h>

static NSString *const kNLStatusPlistPath =
    @"/var/mobile/Library/Preferences/com.tsangbaby.noticedeleteanimation.banner-status.plist";

// ---------------------------------------------------------------- 全局状态
static BOOL NLBannerInstalled;                   // 0x265c8
static IMP NLDismissOriginal;                    // 0x265b0
static IMP NLPresentOriginal;                    // 0x265b8
static IMP NLAddOriginal;                        // 0x265c0

static NSMutableDictionary<NSString *, NSNumber *> *NLBannerCounters;  // 0x26568
static NSString *NLBannerLastEvent;              // 0x26570
static NSString *NLBannerLastView;               // 0x26578
static NSString *NLBannerLastReason;             // 0x26580
static NSString *NLBannerLastResolver;           // fixed diagnostic reason only
static BOOL NLBannerDismissInProgress;           // covers prepare before effect registration
static NSDictionary *NLBannerLastHierarchy;      // 0x26590

// 签名白名单：返回类型必须是 void，参数类型必须精确匹配
static const char *kNLBannerDismissTypes = "@@B@";   // 0x1cf50
static const char *kNLBannerPresentTypes = "@Q@";    // 0x1cf55
static const char *kNLBannerAddTypes     = "@@B";    // 0x1cf59


#pragma mark - 诊断

/// 0xdca4 —— 主线程累加横幅事件计数。
static void NLBannerRecord(NSString *event)
{
    if (![NSThread isMainThread] || !event) {
        return;
    }
    if (!NLBannerCounters) {
        NLBannerCounters = [NSMutableDictionary dictionary];
    }
    NSUInteger count = [NLBannerCounters[event] unsignedIntegerValue];
    NLBannerCounters[event] = [NSNumber numberWithUnsignedLong:count + 1];
    NLBannerLastEvent = event;
    NLWithdrawalRecord(event);
}

/// 0xcfc0 —— 校验某个方法存在、返回 void、参数类型精确匹配。
static BOOL NLBannerSignature(Class cls, SEL sel, const char *returnType,
                              const char *argTypes)
{
    if (!cls || !sel) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        return NO;
    }
    char *types = method_copyReturnType(method);
    BOOL ok = types && strcmp(types, returnType) == 0;
    if (types) {
        free(types);
    }
    if (!ok) {
        return NO;
    }
    // 参数类型：逐参数比对（跳过 self/_cmd）
    unsigned int count = method_getNumberOfArguments(method);
    size_t want = strlen(argTypes);
    if (count < 3 || (count - 2) != want) {
        return NO;
    }
    for (unsigned int i = 0; i < want; i++) {
        char *t = method_copyArgumentType(method, i + 2);
        char expected[2] = { argTypes[i], '\0' };
        ok = t && NLABITypeMatches(t, expected);
        if (t) {
            free(t);
        }
        if (!ok) {
            return NO;
        }
    }
    return YES;
}

// Request identity is the object itself, never an identifier string or a controller.
// Only inspect the presentable's own object-returning links; never UIApplication roots.
static id NLBannerTypedRequest(id object)
{
    Class cls = NSClassFromString(@"NCNotificationRequest");
    return cls && [object isKindOfClass:cls] ? object : nil;
}

static NSArray<NSString *> *NLBannerControllerGetters(void)
{
    return @[@"viewController", @"notificationViewController", @"_notificationViewController",
             @"contentViewController", @"_contentViewController"];
}

static UIViewController *NLBannerVC(id presentable)
{
    if ([presentable isKindOfClass:[UIViewController class]]) return presentable;
    for (NSString *key in NLBannerControllerGetters()) {
        id vc = NLABIReadObject(presentable, NSSelectorFromString(key));
        if ([vc isKindOfClass:[UIViewController class]]) return vc;
    }
    return nil;
}

// Bounded, cycle-safe resolution. A wrapper's notificationRequest is authoritative.
// A controller-only presentable must resolve to a UNIQUE request, not the first child.
static id NLBannerResolveRequest(id object, NSUInteger depth, NSHashTable *seen,
                                  NSUInteger *budget, BOOL *ambiguous)
{
    if (!object || [seen containsObject:object]) return nil;
    if (depth > 4 || *budget == 0) { *ambiguous = YES; return nil; }
    --*budget;
    [seen addObject:object];
    id direct = NLBannerTypedRequest(object);
    if (direct) return direct;
    id own = NLABIReadObject(object, NSSelectorFromString(@"notificationRequest"));
    if (own) return NLBannerResolveRequest(own, depth + 1, seen, budget, ambiguous);

    NSMutableArray *links = [NSMutableArray array];
    if ([object isKindOfClass:[UIViewController class]]) {
        [links addObjectsFromArray:((UIViewController *)object).childViewControllers];
    }
    for (NSString *key in NLBannerControllerGetters()) {
        id vc = NLABIReadObject(object, NSSelectorFromString(key));
        if ([vc isKindOfClass:[UIViewController class]]) [links addObject:vc];
    }
    id result = nil;
    for (id link in links) {
        id candidate = NLBannerResolveRequest(link, depth + 1, seen, budget, ambiguous);
        if (candidate && result && candidate != result) *ambiguous = YES;
        if (candidate) result = candidate;
    }
    return *ambiguous ? nil : result;
}

static BOOL NLBannerCardGeometry(UIView *view, CGRect *outRect);

// This is NOT a size-based "first visible view" search. Accept only a real short
// look class inside the exact request owner's loaded view, excluding child VCs.
static UIView *NLBannerCardInView(UIView *view, id request, NSHashTable *childRoots,
                                  NSUInteger depth, NSUInteger *budget)
{
    if (![view isKindOfClass:[UIView class]] || depth > 6 || *budget == 0 ||
        [childRoots containsObject:view]) return nil;
    --*budget;
    if (view.isHidden || view.alpha < 0.02) return nil;
    Class cardClass = NSClassFromString(@"NCNotificationShortLookView");
    if (cardClass && [view isKindOfClass:cardClass]) {
        id own = NLABIReadObject(view, NSSelectorFromString(@"notificationRequest"));
        return (!own || own == request) && NLBannerCardGeometry(view, NULL) ? view : nil;
    }
    for (UIView *sub in view.subviews) {
        UIView *card = NLBannerCardInView(sub, request, childRoots, depth + 1, budget);
        if (card) return card;
    }
    return nil;
}

/// 0xf754 —— 计算卡片在屏幕坐标系里的矩形。返回 NO 表示几何不可用。
static BOOL NLBannerCardGeometry(UIView *view, CGRect *outRect)
{
    if (![view isKindOfClass:[UIView class]] || !view.window) {
        return NO;
    }
    UIView *node = view;
    while (node) {
        if (node.isHidden || node.alpha < 0.02) {
            return NO;
        }
        node = node.superview;
    }
    UIScreen *screen = view.window.screen;
    CGRect screenRect = [view convertRect:view.bounds toCoordinateSpace:screen.coordinateSpace];
    CGRect screenBounds = screen.bounds;
    CGRect clipped = CGRectIntersection(screenRect, screenBounds);

    if (!isfinite(screenRect.origin.x) || !isfinite(screenRect.origin.y) ||
        !isfinite(screenRect.size.width) || !isfinite(screenRect.size.height)) {
        return NO;
    }
    // A banner must not be a fullscreen container; require enough of the card,
    // not a percentage of the whole display, to be on screen.
    if (screenRect.size.width < 100.0 || screenRect.size.height < 20.0 ||
        screenRect.size.height > screenBounds.size.height * 0.6 ||
        CGRectIsNull(clipped) || CGRectIsEmpty(clipped) ||
        clipped.size.width < screenRect.size.width * 0.48 ||
        clipped.size.height < screenRect.size.height * 0.45) {
        return NO;
    }
    if (outRect) {
        *outRect = screenRect;
    }
    return YES;
}

/// 0x105a0 —— 把 view 的结构描述塞进字典（诊断用）。
static NSDictionary *NLBannerViewInfo(UIView *view, NSString *path)
{
    if (![view isKindOfClass:[UIView class]]) {
        return @{@"path": path ?: @"?", @"class": @"nil"};
    }
    CGRect screenRect = CGRectZero;
    BOOL fits = NLBannerCardGeometry(view, &screenRect);
    return @{
        @"path": path ?: @"?",
        @"class": NSStringFromClass([view class]),
        @"bounds": NSStringFromCGRect(view.bounds),
        @"screenFrame": NSStringFromCGRect(screenRect),
        @"hidden": @(view.isHidden),
        @"alpha": @(view.alpha),
        @"fitsCard": @(fits),
    };
}

/// 0x10320 —— 递归描述 view 树。
static void NLBannerDescribeView(UIView *view, NSString *path, NSUInteger depth,
                                 NSMutableArray *out, NSUInteger *budget)
{
    if (!view || depth > 8 || !budget || *budget == 0) {
        return;
    }
    *budget = *budget - 1;
    [out addObject:NLBannerViewInfo(view, path)];
    NSUInteger i = 0;
    for (UIView *sub in view.subviews) {
        NSString *childPath = [path stringByAppendingFormat:@"/%u", (unsigned)i];
        NLBannerDescribeView(sub, childPath, depth + 1, out, budget);
        i++;
    }
}

/// 0xfba4 —— 递归描述 controller 树。
static void NLBannerDescribeController(UIViewController *controller, NSString *path,
                                       NSUInteger depth, NSMutableArray *controllers,
                                       NSMutableArray *views, NSHashTable *seen,
                                       NSUInteger *budget)
{
    if (!controller || depth > 6 || !budget || *budget == 0) {
        return;
    }
    if ([seen containsObject:controller]) {
        return;
    }
    [seen addObject:controller];
    *budget = *budget - 1;

    [controllers addObject:@{
        @"path": path ?: @"?",
        @"class": NSStringFromClass([controller class]),
        @"loaded": @(controller.isViewLoaded),
    }];
    if (controller.isViewLoaded) {
        NLBannerDescribeView(controller.view, path, 0, views, budget);
    }
    NSUInteger i = 0;
    for (UIViewController *child in controller.childViewControllers) {
        NSString *childPath = [path stringByAppendingFormat:@"/child%u", (unsigned)i];
        NLBannerDescribeController(child, childPath, depth + 1,
                                   controllers, views, seen, budget);
        i++;
    }
}

/// Find only controllers that own this exact request. Loading views or falling
/// back to an unrelated presentable's root would animate the wrong notification.
static UIView *NLBannerCardInController(UIViewController *controller, id request,
                                        NSUInteger depth, NSHashTable *seen,
                                        NSUInteger *budget)
{
    if (![controller isKindOfClass:[UIViewController class]] || !request || depth > 6 ||
        *budget == 0 || [seen containsObject:controller]) return nil;
    --*budget;
    [seen addObject:controller];
    id own = NLABIReadObject(controller, NSSelectorFromString(@"notificationRequest"));
    if (own == request && NLBannerTypedRequest(own) && controller.isViewLoaded) {
        UIView *root = controller.viewIfLoaded;
        NSHashTable *childRoots = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        for (UIViewController *child in controller.childViewControllers) {
            if (child.isViewLoaded) [childRoots addObject:child.viewIfLoaded];
        }
        NSUInteger viewBudget = 48;
        UIView *card = NLBannerCardInView(root, request, childRoots, 0, &viewBudget);
        if (card) return card;
    }
    for (UIViewController *child in controller.childViewControllers) {
        UIView *card = NLBannerCardInController(child, request, depth + 1, seen, budget);
        if (card) return card;
    }
    return nil;
}


#pragma mark - disposition 回调

/// 0xddf8 —— tick 里判断这个横幅效果该继续还是收尾。
static NLDisposition NLBannerDisposition(NLWithdrawalEffect *effect)
{
    if (!effect) {
        return NLDispositionAbort;
    }
    id owner = effect.owner;
    id payload = effect.payload;

    // owner（BNContentViewController）已经不在 presentable 栈里 → 原生收回完成
    if (owner) {
        if ([owner respondsToSelector:NSSelectorFromString(@"presentedPresentables")]) {
            id list = NLABIReadObject(owner, NSSelectorFromString(@"presentedPresentables"));
            if ([list isKindOfClass:[NSArray class]]) {
                if ([list indexOfObjectIdenticalTo:payload] == NSNotFound) {
                    return NLDispositionProceed;
                }
                return NLDispositionPending;
            }
        }
    }
    // 拿不到栈信息：看 sourceView 是否还在屏幕上
    UIView *source = effect.sourceView;
    if (!source || !NLVisible(source)) {
        return NLDispositionProceed;
    }
    return NLDispositionPending;
}


#pragma mark - hooks

static void NLBannerResolverEvent(NSString *event)
{
    NLBannerLastResolver = event; // caller supplies fixed strings, never request data
    @try { NLBannerRecord(event); }
    @catch (__unused NSException *exception) { /* do not block native dismissal */ }
}

static void NLBannerCancel(NLWithdrawalEffect *effect, UIView *card)
{
    @try {
        if (effect) [effect cancel];
        else if (card) [NLWithdrawalEffect cancelEffectsForView:card];
    } @catch (__unused NSException *exception) { /* cleanup must not replace native */ }
}

/// Existing BN dismissal entry, for EVERY reason; no guessed tap/UIControl hook.
static void NLBannerDismiss(id self, SEL _cmd, id presentable, id reason,
                            BOOL animated, id userInfo)
{
    if (![NSThread isMainThread] || NLIslandDustNativeCloseInProgress() ||
        NLBannerDismissInProgress) {
        ((void (*)(id, SEL, id, id, BOOL, id))NLDismissOriginal)(
            self, _cmd, presentable, reason, animated, userInfo);
        return;
    }

    NLBannerDismissInProgress = YES; // prepare may reenter before registration
    NLWithdrawalEffect *effect = nil;
    UIView *card = nil;
    @try {
        @try {
            NLBannerRecord(@"native-dismiss-seen");
            // Preserve the existing reason-only diagnostic; never read request IDs/body.
            NLBannerLastReason = [reason isKindOfClass:[NSString class]]
                ? ([(NSString *)reason length] > 160 ? [(NSString *)reason substringToIndex:160] : reason)
                : (reason ? NSStringFromClass([reason class]) : nil);
            NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
            NSUInteger budget = 32;
            BOOL ambiguous = NO;
            id request = NLBannerResolveRequest(presentable, 0, seen, &budget, &ambiguous);
            UIViewController *hostVC = NLBannerVC(presentable);
            if (!request || ambiguous) {
                NLBannerResolverEvent(@"no_request");
            } else if ([NLWithdrawalEffect isPendingForOwner:self payload:presentable]) {
                NLBannerResolverEvent(@"skip:duplicate");
            } else {
                NLBannerResolverEvent(@"requestresolved");
                [seen removeAllObjects];
                budget = 48;
                card = NLBannerCardInController(hostVC, request, 0, seen, &budget);
                // A request can itself be the presentable, without viewController.
                // Only inspect this BN controller's children, still requiring exact identity.
                if (!card && [self isKindOfClass:[UIViewController class]]) {
                    card = NLBannerCardInController(self, request, 0, seen, &budget);
                }
                if (card) {
                    effect = [NLWithdrawalEffect prepareView:card source:request preference:@"BannerKit"];
                    if (effect) {
                        effect.owner = self;
                        effect.payload = presentable;
                        effect.disposition = NLBannerDisposition;
                        effect.requiresRemovalConfirmation = YES;
                        NLBannerLastView = NSStringFromClass([card class]);
                        NLBannerResolverEvent(@"prepared");
                    } else {
                        NLBannerResolverEvent(@"capturefail");
                    }
                } else {
                    NLBannerResolverEvent(@"nohost");
                }
            }
            if (!card) {
                NLBannerRecord(@"skip:no-real-card");
                NSMutableArray *controllers = [NSMutableArray array];
                NSMutableArray *views = [NSMutableArray array];
                [seen removeAllObjects];
                budget = 48;
                NLBannerDescribeController(hostVC, @"current-presentable-compact-root", 0,
                                           controllers, views, seen, &budget);
                NLBannerLastHierarchy = @{
                    @"presentableClass": presentable ? NSStringFromClass([presentable class]) : @"nil",
                    @"controllers": controllers, @"views": views,
                };
            }
        } @catch (__unused NSException *exception) {
            NLBannerCancel(effect, card);
            effect = nil;
            NLBannerResolverEvent(@"capturefail");
        }

        // Exactly one native invocation, outside the capture exception handler.
        // Forward original objects untouched; suppress animation only after real prepare.
        @try {
            ((void (*)(id, SEL, id, id, BOOL, id))NLDismissOriginal)(
                self, _cmd, presentable, reason, effect ? NO : animated, userInfo);
        } @catch (__unused NSException *exception) {
            NLBannerCancel(effect, card);
            @throw; // preserve native exception, never retry original
        }
        @try {
            [effect beginAfterNativeRemoval];
        } @catch (__unused NSException *exception) {
            NLBannerCancel(effect, card);
            NLBannerResolverEvent(@"finalizefail");
        }
    } @finally {
        NLBannerDismissInProgress = NO;
        @try { NLBannerWriteStatus(); }
        @catch (__unused NSException *exception) { /* diagnostics are best effort */ }
    }
}

/// 0xdb14 —— 替换 -[BNContentViewController presentPresentable:withOptions:userInfo:]
static void NLBannerPresent(id self, SEL _cmd, id presentable, NSUInteger options, id userInfo)
{
    NLBannerRecord(@"present");
    ((void (*)(id, SEL, id, NSUInteger, id))NLPresentOriginal)(self, _cmd, presentable,
                                                                options, userInfo);
    NLBannerWriteStatus();
}

/// 0xdbdc —— 替换 -[BNContentViewController _addPresentable:withTransitioningDelegate:incrementingTier:]
static void NLBannerAdd(id self, SEL _cmd, id presentable, id delegate, BOOL incrementingTier)
{
    NLBannerRecord(@"add");
    ((void (*)(id, SEL, id, id, BOOL))NLAddOriginal)(self, _cmd, presentable,
                                                      delegate, incrementingTier);
    NLBannerWriteStatus();
}


#pragma mark - 安装

/// 0xc478
BOOL NLInstallBannerDustHooks(void)
{
    if (![NSThread isMainThread]) {
        return NO;
    }
    if (NLDismissOriginal && NLPresentOriginal && NLAddOriginal) return YES;

    Class cls = NSClassFromString(@"BNContentViewController");
    if (!cls || ![cls isSubclassOfClass:[UIViewController class]]) {
        return NO;
    }

    SEL dismissSel = NSSelectorFromString(@"_dismissPresentable:withReason:animated:userInfo:");
    SEL presentSel = NSSelectorFromString(@"presentPresentable:withOptions:userInfo:");
    SEL addSel = NSSelectorFromString(@"_addPresentable:withTransitioningDelegate:incrementingTier:");

    BOOL dismissOK = NLBannerSignature(cls, dismissSel, "v", kNLBannerDismissTypes);
    BOOL presentOK = NLBannerSignature(cls, presentSel, "v", kNLBannerPresentTypes);
    BOOL addOK = NLBannerSignature(cls, addSel, "v", kNLBannerAddTypes);

    if (dismissOK && !NLDismissOriginal) {
        MSHookMessageEx(cls, dismissSel, (IMP)NLBannerDismiss, &NLDismissOriginal);
        NLBannerRecord(@"clickpathunknown"); // capability unknown, NOT a tap observation
    }
    if (presentOK && !NLPresentOriginal) {
        MSHookMessageEx(cls, presentSel, (IMP)NLBannerPresent, &NLPresentOriginal);
    }
    if (addOK && !NLAddOriginal) {
        MSHookMessageEx(cls, addSel, (IMP)NLBannerAdd, &NLAddOriginal);
    }

    NLBannerInstalled = NLDismissOriginal != NULL; // present/add alone cannot withdraw

    // 启动状态探测（NLNotificationStatusProbe 见 NLStatusProbe.m）
    Class probeClass = NSClassFromString(@"NLNotificationStatusProbe");
    if (probeClass) {
        id probe = [probeClass performSelector:@selector(shared)];
        [probe performSelector:@selector(scan) withObject:nil afterDelay:1.5];
    }

    return NLBannerInstalled;
}

/// 0xc688 —— 写诊断 plist。所有值都来自内存计数，不含通知正文。
void NLBannerWriteStatus(void)
{
    if (![NSThread isMainThread]) {
        return;
    }

    NSMutableDictionary *status = [NSMutableDictionary dictionary];

    status[@"build"] = @"0.1.0~alpha8";
    status[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
    status[@"pid"] = @(getpid());
    status[@"installed"] = @(NLBannerInstalled);
    status[@"enabled"] = @(NLAnimationEnabled);
    status[@"metalReady"] = @([NLDustRenderer isReady]);
    status[@"reduceMotion"] = @(UIAccessibilityIsReduceMotionEnabled());
    status[@"mode"] = @"native-withdrawal";
    status[@"loaded"] = @YES;
    status[@"dismissHook"] = @(NLDismissOriginal != NULL);
    status[@"clickPath"] = @"unverified";
    status[@"listSnapshot"] = NLListSnapshotStatus();

    // Fixed reason counters; clickpathunknown counts hook capability declarations,
    // not clicks. Request identifiers/content are neither read nor serialized.
    NSMutableDictionary *events = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"requestresolved", @"no_request", @"nohost", @"capturefail", @"clickpathunknown"]) {
        events[key] = @0;
    }
    for (NSString *key in NLBannerCounters) {
        events[key] = NLBannerCounters[key];
    }
    status[@"events"] = events;

    // 各子系统状态
    NSDictionary *islands = NLIslandDustStatus();
    NSDictionary *lock = NLLockScreenDustStatus();
    status[@"islands"] = islands;
    status[@"lockScreen"] = lock;
    status[@"trollOpenPresent"] = islands[@"trollOpenCurrentHook"];
    status[@"aperturePresent"] = islands[@"apertureDismissHook"];
    status[@"cellClearHook"] = lock[@"cellClearHook"];
    status[@"collectionDeleteHook"] = lock[@"collectionDeleteHook"];

    if (NLBannerLastResolver) status[@"lastResolver"] = NLBannerLastResolver;
    if (NLBannerLastEvent) status[@"lastEvent"] = NLBannerLastEvent;
    if (NLBannerLastView)  status[@"lastViewClass"] = NLBannerLastView;
    if (NLBannerLastReason) status[@"lastDismissReason"] = NLBannerLastReason;
    if (NLBannerLastHierarchy) status[@"cardHierarchy"] = NLBannerLastHierarchy;

    [status writeToFile:kNLStatusPlistPath atomically:YES];
}
