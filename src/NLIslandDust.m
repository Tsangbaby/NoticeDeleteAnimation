//
//  NLIslandDust.m
//  NoticeDeleteAnimation — 通知消散
//
//  灵动岛（TrollOpen / Nice "Aperture"）通知的消散。逆向自 1.0.1~test14。
//
//  两个第三方插件都不公开类名（混淆成 UCS240tlDBfdslUVYSGXDYAqOH /
//  UCS242OHlvEPuegiMfCkCzhpxN），所以只能 NSClassFromString 硬编码。
//  它们的收起路径都是在 manager 上调用 invalidate / dismiss，然后由
//  各自的 content view controller 把卡片从视图树里摘掉。
//

#import "NLIslandDust.h"
#import "NLPreferences.h"
#import "NLWithdrawalEffect.h"
#import "NLDustRenderer.h"
#import "NLRuntimeABI.h"

#import <objc/runtime.h>
#import <substrate.h>

// ---------------------------------------------------------------- 全局状态
static IMP NLTOCurrentOriginal;      // 0x26610
static IMP NLTOElementOriginal;      // 0x26618
static IMP NLAPDismissOriginal;      // 0x26628
static NSUInteger NLIslandDepth;     // 0x26608
static NSUInteger NLTOSeen;          // 0x26630
static NSUInteger NLAPSeen;          // 0x26638
static NSMutableArray *NLTOWithdrawals;   // 0x266a0
static NSMutableArray *NLAPWithdrawals;   // 0x266a8

static NSString *const kNLIslandPrefTrollOpen = @"TrollOpen";
static NSString *const kNLIslandPrefAperture = @"Aperture";


#pragma mark - 工具

/// 0x1544c —— 收集一个 provider 对象拥有的所有 view。
static void NLOwnedViews(id provider, NSMutableArray *out)
{
    if (!provider || !out) {
        return;
    }
    for (NSString *key in @[@"view",
                            @"providedView",
                            @"notificationView",
                            @"runtimeView",
                            @"nativeLeadingView",
                            @"runtimeLeadingView",
                            @"runtimeTrailingView"]) {
        SEL sel = NSSelectorFromString(key);
        if (![provider respondsToSelector:sel]) {
            continue;
        }
        id candidate = NLABIReadObject(provider, sel);
        if ([candidate isKindOfClass:[UIView class]]) {
            [out addObject:candidate];
        }
    }
}

/// 0x15b54 —— 从一个 element 上按 provider 键名找承载视图。
static UIView *NLProviderView(id element, NSUInteger depth, NSHashTable *seen)
{
    if (!element || depth > 4) {
        return nil;
    }
    if (seen && [seen containsObject:element]) {
        return nil;
    }
    if (seen) {
        [seen addObject:element];
    }

    NSMutableArray *views = [NSMutableArray array];
    NLOwnedViews(element, views);
    for (UIView *view in views) {
        if (view.window && !view.isHidden && view.alpha >= 0.02) {
            return view;
        }
    }

    // provider 链
    for (NSString *key in @[@"contentProvider",
                            @"miniContentProvider",
                            @"viewProvider",
                            @"leadingContentViewProvider",
                            @"trailingContentViewProvider",
                            @"primaryContentViewProvider",
                            @"minimalContentViewProvider",
                            @"actionContentViewProvider",
                            @"secondaryContentViewProvider",
                            @"normalViewProvider"]) {
        SEL sel = NSSelectorFromString(key);
        if (![element respondsToSelector:sel]) {
            continue;
        }
        id provider = NLABIReadObject(element, sel);
        UIView *found = NLProviderView(provider, depth + 1, seen);
        if (found) {
            return found;
        }
    }

    // 最后退回递归 subviews
    if ([element isKindOfClass:[UIView class]]) {
        for (UIView *sub in [(UIView *)element subviews]) {
            if (sub.window && !sub.isHidden && sub.alpha >= 0.02 &&
                sub.bounds.size.width >= 16.0 && sub.bounds.size.height >= 16.0) {
                return sub;
            }
        }
    }
    return nil;
}

/// 0x16258 —— Aperture 的 tick 回调。
static NLDisposition NLAPState(NLWithdrawalEffect *effect)
{
    if (!effect) {
        return NLDispositionAbort;
    }
    if (!effect.sourceView || !NLVisible(effect.sourceView)) {
        return NLDispositionProceed;
    }
    return NLDispositionPending;
}

/// 0x15004 —— TrollOpen 的 tick 回调。
static NLDisposition NLTOState(NLWithdrawalEffect *effect)
{
    if (!effect) {
        return NLDispositionAbort;
    }
    if (!effect.sourceView || !NLVisible(effect.sourceView)) {
        return NLDispositionProceed;
    }
    return NLDispositionPending;
}

/// 0x14cc4 —— 给一个 element 准备消散。返回创建的效果数量。
static NSUInteger NLPrepareIsland(id element, id context, NSString *preference,
                                  NLDispositionFn state)
{
    if (![NSThread isMainThread] || !element) {
        return 0;
    }
    if (!NLPreference(@"Enabled")) {
        return 0;
    }
    if (![NLDustRenderer isReady]) {
        return 0;
    }

    NSMutableArray *views = [NSMutableArray array];
    NLOwnedViews(element, views);
    if (views.count == 0) {
        UIView *fallback = NLProviderView(element, 0,
            [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]);
        if (fallback) {
            [views addObject:fallback];
        }
    }

    NSUInteger created = 0;
    for (UIView *view in views) {
        NLWithdrawalEffect *effect = [NLWithdrawalEffect prepareView:view
                                                              source:element
                                                          preference:preference];
        if (!effect) {
            continue;
        }
        effect.owner = context;
        effect.payload = element;
        effect.disposition = state;
        effect.identity = [NSString stringWithFormat:@"%@-%p", preference, (void *)element];

        if ([preference isEqual:kNLIslandPrefTrollOpen]) {
            if (!NLTOWithdrawals) {
                NLTOWithdrawals = [NSMutableArray array];
            }
            [NLTOWithdrawals addObject:effect];
        } else {
            if (!NLAPWithdrawals) {
                NLAPWithdrawals = [NSMutableArray array];
            }
            [NLAPWithdrawals addObject:effect];
        }
        created++;
    }

    if (created == 0) {
        NLWithdrawalRecord([preference isEqual:kNLIslandPrefTrollOpen]
                           ? @"skip:trollopen-no-owned-view"
                           : @"skip:aperture-no-owned-view");
    }
    return created;
}


#pragma mark - hooks

/// 0x13e30 —— 替换 -[DIMiniIslandManager invalidateCurrentWithReason:]
static void NLTOCurrent(id self, SEL _cmd, id reason)
{
    NLTOSeen = NLTOSeen + 1;
    NLIslandDepth = NLIslandDepth + 1;

    id element = nil;
    SEL currentSel = NSSelectorFromString(@"currentElement");
    if ([self respondsToSelector:currentSel]) {
        element = NLABIReadObject(self, currentSel);
    }
    if (element) {
        NLPrepareIsland(element, self, kNLIslandPrefTrollOpen, NLTOState);
    }

    ((void (*)(id, SEL, id))NLTOCurrentOriginal)(self, _cmd, reason);

    NLIslandDepth = NLIslandDepth - 1;
}

/// 0x14100 —— 替换 -[DIMiniIslandManager invalidateElement:reason:]
static void NLTOElement(id self, SEL _cmd, id element, id reason)
{
    NLTOSeen = NLTOSeen + 1;
    NLIslandDepth = NLIslandDepth + 1;

    if (element) {
        NLPrepareIsland(element, self, kNLIslandPrefTrollOpen, NLTOState);
    }

    ((void (*)(id, SEL, id, id))NLTOElementOriginal)(self, _cmd, element, reason);

    NLIslandDepth = NLIslandDepth - 1;
}

/// 0x143c0 —— 替换 Nice 的 -[<Aperture> dismissWithBNcontent:forcekill:]
static void NLAPDismiss(id self, SEL _cmd, BOOL content, BOOL forceKill)
{
    NLAPSeen = NLAPSeen + 1;
    NLIslandDepth = NLIslandDepth + 1;

    // 收集当前注册的所有 element
    NSArray *elements = nil;
    for (NSString *key in @[@"registeredElements", @"persistentElementsByIdentifier"]) {
        SEL sel = NSSelectorFromString(key);
        if (![self respondsToSelector:sel]) {
            continue;
        }
        id value = NLABIReadObject(self, sel);
        if ([value isKindOfClass:[NSArray class]]) {
            elements = value;
            break;
        }
        if ([value isKindOfClass:[NSDictionary class]]) {
            elements = [(NSDictionary *)value allValues];
            break;
        }
    }
    for (id element in elements) {
        NLPrepareIsland(element, self, kNLIslandPrefAperture, NLAPState);
    }

    ((void (*)(id, SEL, BOOL, BOOL))NLAPDismissOriginal)(self, _cmd, content, forceKill);

    NLIslandDepth = NLIslandDepth - 1;
}


#pragma mark - 安装

// 0x13c5c
BOOL NLIslandDustNativeCloseInProgress(void)
{
    return NLIslandDepth > 0;
}

// 0x13c70
void NLInstallIslandDustHooks(void)
{
    if (![NSThread isMainThread]) {
        return;
    }

    Class toClass = NSClassFromString(@"DIMiniIslandManager");
    if (toClass) {
        SEL currentSel = NSSelectorFromString(@"invalidateCurrentWithReason:");
        SEL elementSel = NSSelectorFromString(@"invalidateElement:reason:");
        if (!NLTOCurrentOriginal && class_getInstanceMethod(toClass, currentSel)) {
            MSHookMessageEx(toClass, currentSel, (IMP)NLTOCurrent, &NLTOCurrentOriginal);
        }
        if (!NLTOElementOriginal && class_getInstanceMethod(toClass, elementSel)) {
            MSHookMessageEx(toClass, elementSel, (IMP)NLTOElement, &NLTOElementOriginal);
        }
    }

    // Nice（Aperture）：类名是混淆字符串
    Class apClass = NSClassFromString(@"UCS240tlDBfdslUVYSGXDYAqOH");
    if (apClass) {
        SEL dismissSel = NSSelectorFromString(@"dismissWithBNcontent:forcekill:");
        if (!NLAPDismissOriginal && class_getInstanceMethod(apClass, dismissSel)) {
            MSHookMessageEx(apClass, dismissSel, (IMP)NLAPDismiss, &NLAPDismissOriginal);
        }
    }
}

// 0x149fc
NSDictionary *NLIslandDustStatus(void)
{
    return @{
        @"trollOpenCurrentHook": @(NLTOCurrentOriginal != NULL),
        @"trollOpenElementHook": @(NLTOElementOriginal != NULL),
        @"apertureDismissHook": @(NLAPDismissOriginal != NULL),
        @"trollOpenWithdrawals": @(NLTOWithdrawals.count),
        @"apertureWithdrawals": @(NLAPWithdrawals.count),
    };
}
