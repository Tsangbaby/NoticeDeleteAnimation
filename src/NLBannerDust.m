//
//  NLBannerDust.m
//  NoticeListTweak — 通知消散
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
#import "NLNotificationListHooks.h"
#import "NLStatusProbe.h"
#import "NLLockScreenDust.h"
#import "NLIslandDust.h"

#import <objc/runtime.h>
#include <unistd.h>
#import <substrate.h>

static NSString *const kNLStatusPlistPath =
    @"/var/mobile/Library/Preferences/com.example.noticelisttweak.banner-status.plist";

// ---------------------------------------------------------------- 全局状态
static BOOL NLBannerInstalled;                   // 0x265c8
static IMP NLDismissOriginal;                    // 0x265b0
static IMP NLPresentOriginal;                    // 0x265b8
static IMP NLAddOriginal;                        // 0x265c0

static NSMutableDictionary<NSString *, NSNumber *> *NLBannerCounters;  // 0x26568
static NSString *NLBannerLastEvent;              // 0x26570
static NSString *NLBannerLastView;               // 0x26578
static NSString *NLBannerLastReason;             // 0x26580
static NSString *NLBannerLastResolver;           // 0x26588
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
        ok = t && t[0] == argTypes[i];
        if (t) {
            free(t);
        }
        if (!ok) {
            return NO;
        }
    }
    return YES;
}

/// 0xe164 —— 从一个 NCNotificationRequest 生成稳定 key：`%lu:%@%@`
///
/// 二进制的字段来源（0x21008/0x21028/0x21048/0x21068）：
///   - 先校验对象是 NCNotificationRequest
///   - notificationIdentifier（string，走 methodForSelector 校验）
///   - sectionIdentifier（string）
///   - 第一个 %lu 用的是两个字符串 length 的组合（二进制里是 length 比较后
///     取某个长度值），不是 index 属性。
/// REVERIFY: `%lu` 的确切来源没完全定死，这里是"两个标识符长度的组合"，
/// 只要同一 request 每次得到同一个 key 就满足去重用途。
static NSString *NLBannerRequestKey(id request)
{
    if (!request) {
        return nil;
    }
    Class requestClass = NSClassFromString(@"NCNotificationRequest");
    if (requestClass && ![request isKindOfClass:requestClass]) {
        return nil;
    }

    NSString *identifier = nil;
    NSString *section = nil;

    SEL idSel = NSSelectorFromString(@"notificationIdentifier");
    if ([request respondsToSelector:idSel]) {
        id value = [request performSelector:idSel];
        if ([value isKindOfClass:[NSString class]]) {
            identifier = value;
        }
    }
    SEL sectionSel = NSSelectorFromString(@"sectionIdentifier");
    if ([request respondsToSelector:sectionSel]) {
        id value = [request performSelector:sectionSel];
        if ([value isKindOfClass:[NSString class]]) {
            section = value;
        }
    }
    if (!identifier && !section) {
        return nil;
    }

    NSUInteger bucket = identifier.length + section.length;
    return [NSString stringWithFormat:@"%lu:%@%@", (unsigned long)bucket,
            section ?: @"", identifier ?: @""];
}

/// 0xe804 —— 从一个 presentable 拿到它的 viewController。
static UIViewController *NLBannerVC(id presentable)
{
    if (!presentable) {
        return nil;
    }
    for (NSString *key in @[@"viewController",
                            @"notificationViewController",
                            @"_notificationViewController",
                            @"contentViewController",
                            @"_contentViewController"]) {
        if ([presentable respondsToSelector:NSSelectorFromString(key)]) {
            id vc = [presentable performSelector:NSSelectorFromString(key)];
            if ([vc isKindOfClass:[UIViewController class]]) {
                return vc;
            }
        }
    }
    return nil;
}

/// 0xe430 —— 在 controller 的子控制器树里找承载该 request 的 controller。
/// 深度优先，最多 4 层。
static UIViewController *NLBannerFindRequest(id request, UIViewController *controller,
                                             NSUInteger depth)
{
    if (!request || !controller || depth > 4) {
        return nil;
    }
    if ([controller respondsToSelector:NSSelectorFromString(@"notificationRequest")]) {
        id own = [controller performSelector:NSSelectorFromString(@"notificationRequest")];
        if (own == request) {
            return controller;
        }
    }
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *found = NLBannerFindRequest(request, child, depth + 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

/// 0xf3b0 —— 在 view 的子视图树里找"像卡片"的视图：宽高比接近横幅、
/// 有 window、不隐藏、alpha 足够。返回找到的视图，并通过 count 输出候选数。
static UIView *NLBannerCardInView(UIView *view, NSUInteger depth, NSUInteger *count)
{
    if (![view isKindOfClass:[UIView class]] || depth > 6) {
        return nil;
    }
    if (count) {
        *count = *count + 1;
    }
    if (view.window && !view.isHidden && view.alpha >= 0.02) {
        CGRect screenRect = [view convertRect:view.bounds toView:nil];
        if (screenRect.size.width >= 100.0 && screenRect.size.height >= 20.0) {
            return view;
        }
    }
    for (UIView *sub in view.subviews) {
        UIView *found = NLBannerCardInView(sub, depth + 1, count);
        if (found) {
            return found;
        }
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
    if (screenRect.size.width < 16.0 || screenRect.size.height < 12.0) {
        return NO;
    }
    // 必须落在屏幕内足够大的比例（0.48 / 0.45 是二进制里的阈值）
    if (clipped.size.width < screenBounds.size.width * 0.48 ||
        clipped.size.height < screenBounds.size.height * 0.45) {
        // REVERIFY: 0.48/0.45 的语义按"屏幕占比下限"还原，
        // 也可能是相对卡片自身 bounds 的比例。
        if (clipped.size.width < screenRect.size.width * 0.48 ||
            clipped.size.height < screenRect.size.height * 0.45) {
            return NO;
        }
    }
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) {
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

/// 0xe98c —— 在一个 controller 里找承载该 request 的卡片视图。
static UIView *NLBannerCardInController(UIViewController *controller,
                                        NSString *requestKey,
                                        NSUInteger depth,
                                        NSHashTable *seen)
{
    if (!controller || depth > 6 || !requestKey) {
        return nil;
    }
    if (seen && [seen containsObject:controller]) {
        return nil;
    }
    if (seen) {
        [seen addObject:controller];
    }

    // 1) controller 自己就是承载者
    NSString *ownKey = nil;
    if ([controller respondsToSelector:NSSelectorFromString(@"notificationRequest")]) {
        id request = [controller performSelector:NSSelectorFromString(@"notificationRequest")];
        ownKey = NLBannerRequestKey(request);
    }
    if ([ownKey isEqual:requestKey] && controller.isViewLoaded) {
        NSUInteger count = 0;
        UIView *card = NLBannerCardInView(controller.view, 0, &count);
        if (card) {
            return card;
        }
    }

    // 2) 遍历 shortLookView / lookView 这类直接挂载点
    for (NSString *key in @[@"_notificationShortLookViewIfLoaded",
                            @"_lookViewIfLoaded",
                            @"shortLookView",
                            @"lookView",
                            @"notificationView",
                            @"runtimeView"]) {
        if (![controller respondsToSelector:NSSelectorFromString(key)]) {
            continue;
        }
        id candidate = [controller performSelector:NSSelectorFromString(key)];
        if (![candidate isKindOfClass:[UIView class]]) {
            continue;
        }
        NSUInteger count = 0;
        UIView *card = NLBannerCardInView(candidate, 0, &count);
        if (card) {
            return card;
        }
    }

    // 3) 递归子控制器
    for (UIViewController *child in controller.childViewControllers) {
        UIView *found = NLBannerCardInController(child, requestKey, depth + 1, seen);
        if (found) {
            return found;
        }
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
            id list = [owner performSelector:NSSelectorFromString(@"presentedPresentables")];
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

/// 0xd16c —— 替换 -[BNContentViewController _dismissPresentable:withReason:animated:userInfo:]
static void NLBannerDismiss(id self, SEL _cmd, id presentable, id reason,
                            BOOL animated, id userInfo)
{
    if (![NSThread isMainThread] || NLIslandDustNativeCloseInProgress()) {
        ((void (*)(id, SEL, id, id, BOOL, id))NLDismissOriginal)(self, _cmd, presentable, reason,
                                                                  animated, userInfo);
        return;
    }

    NLBannerRecord(@"native-dismiss-seen");

    // 记录 reason（诊断）
    if ([reason isKindOfClass:[NSString class]]) {
        NLBannerLastReason = [(NSString *)reason length] > 160
            ? [(NSString *)reason substringToIndex:160] : (NSString *)reason;
    } else {
        NLBannerLastReason = reason ? NSStringFromClass([reason class]) : nil;
    }

    UIViewController *hostVC = NLBannerVC(presentable);
    id request = nil;
    NSString *requestKey = nil;
    if (hostVC) {
        request = NLBannerFindRequest(presentable, hostVC, 0);
        requestKey = NLBannerRequestKey(request);
    }

    UIView *card = nil;
    if (hostVC && requestKey) {
        NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        card = NLBannerCardInController(hostVC, requestKey, 0, seen);
        if (!card) {
            // 退一步：直接看 presentable 自己的视图层级
            for (NSString *key in @[@"notificationViewController",
                                    @"_notificationViewController",
                                    @"contentViewController"]) {
                if ([presentable respondsToSelector:NSSelectorFromString(key)]) {
                    id vc = [presentable performSelector:NSSelectorFromString(key)];
                    if ([vc isKindOfClass:[UIViewController class]] && [(UIViewController *)vc isViewLoaded]) {
                        NSUInteger count = 0;
                        card = NLBannerCardInView([(UIViewController *)vc view], 0, &count);
                        if (card) {
                            break;
                        }
                    }
                }
            }
        }
    }

    NLWithdrawalEffect *effect = nil;
    if (card) {
        effect = [NLWithdrawalEffect prepareView:card
                                          source:request
                                      preference:@"BannerKit"];
        if (effect) {
            effect.owner = self;
            effect.payload = presentable;
            effect.disposition = NLBannerDisposition;
            effect.identity = requestKey;
            NLBannerLastView = NSStringFromClass([card class]);
        }
    } else {
        NLBannerRecord(@"skip:no-real-card");
        // 存一份层级快照供诊断
        NSMutableArray *controllers = [NSMutableArray array];
        NSMutableArray *views = [NSMutableArray array];
        NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        NSUInteger budget = 48;
        NLBannerDescribeController(hostVC, @"current-presentable-compact-root", 0,
                                   controllers, views, seen, &budget);
        NLBannerLastHierarchy = @{
            @"presentableClass": presentable ? NSStringFromClass([presentable class]) : @"nil",
            @"controllers": controllers,
            @"views": views,
        };
        NLBannerRecord(@"card-structure-captured");
    }

    // 原生收回：有自定义效果时强制 animated=NO，让位给颗粒动画
    ((void (*)(id, SEL, id, id, BOOL, id))NLDismissOriginal)(
        self, _cmd, presentable, reason, animated && (effect == nil), userInfo);

    [effect beginAfterNativeRemoval];
    NLBannerWriteStatus();
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
    if (NLBannerInstalled) {
        return YES;
    }
    if (![NSThread isMainThread]) {
        return NO;
    }

    Class cls = NSClassFromString(@"BNContentViewController");
    if (!cls) {
        return NO;
    }

    SEL dismissSel = NSSelectorFromString(@"_dismissPresentable:withReason:animated:userInfo:");
    SEL presentSel = NSSelectorFromString(@"presentPresentable:withOptions:userInfo:");
    SEL addSel = NSSelectorFromString(@"_addPresentable:withTransitioningDelegate:incrementingTier:");

    BOOL dismissOK = NLBannerSignature(cls, dismissSel, "v", kNLBannerDismissTypes);
    BOOL presentOK = NLBannerSignature(cls, presentSel, "v", kNLBannerPresentTypes);
    BOOL addOK = NLBannerSignature(cls, addSel, "v", kNLBannerAddTypes);

    if (dismissOK) {
        MSHookMessageEx(cls, dismissSel, (IMP)NLBannerDismiss, &NLDismissOriginal);
    }
    if (presentOK) {
        MSHookMessageEx(cls, presentSel, (IMP)NLBannerPresent, &NLPresentOriginal);
    }
    if (addOK) {
        MSHookMessageEx(cls, addSel, (IMP)NLBannerAdd, &NLAddOriginal);
    }

    NLBannerInstalled = dismissOK || presentOK || addOK;

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

    status[@"build"] = @"test14";
    status[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
    status[@"pid"] = @(getpid());
    status[@"installed"] = @(NLBannerInstalled);
    status[@"enabled"] = @(NLAnimationEnabled);
    status[@"metalReady"] = @([NLDustRenderer isReady]);
    status[@"reduceMotion"] = @(UIAccessibilityIsReduceMotionEnabled());
    status[@"mode"] = @"native-withdrawal";
    status[@"loaded"] = @YES;

    // 事件计数
    NSMutableDictionary *events = [NSMutableDictionary dictionary];
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

    if (NLBannerLastEvent) status[@"lastEvent"] = NLBannerLastEvent;
    if (NLBannerLastView)  status[@"lastViewClass"] = NLBannerLastView;
    if (NLBannerLastReason) status[@"lastDismissReason"] = NLBannerLastReason;
    if (NLBannerLastHierarchy) status[@"cardHierarchy"] = NLBannerLastHierarchy;

    [status writeToFile:kNLStatusPlistPath atomically:YES];
}
