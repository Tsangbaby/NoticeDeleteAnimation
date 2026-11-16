//
//  NLLockScreenDust.m
//  NoticeDeleteAnimation — 通知消散
//
//  锁屏通知的消散。逆向自 1.0.1~test14，地址见各函数。
//
//  锁屏和通知中心用的是同一套 NCNotificationListCell，但收起手势不同：
//  锁屏上是"向左滑出"或"清除全部"，两者都要在 cell 真的离开列表之后才播颗粒。
//  这里用 NLLockImageCache 在 pan 开始时先抓一张图，避免 cell 已经开始位移才抓，
//  那样抓到的就是位移中的画面。
//

#import "NLLockScreenDust.h"
#import "NLPreferences.h"
#import "NLWithdrawalEffect.h"
#import "NLDustRenderer.h"
#import "NLRuntimeABI.h"

#import <objc/runtime.h>
#import <substrate.h>

// ---------------------------------------------------------------- 全局状态
static NSMutableDictionary<NSString *, id> *NLLockCaches;  // 0x26640
static char NLLockCacheKey;                  // 0x26648
static IMP NLCellClearOriginal;              // 0x26650
static IMP NLCellSetContentOriginal;         // 0x26658
static IMP NLCellPanOriginal;                // 0x26660
static IMP NLCollectionDeleteOriginal;       // 0x26668
static NSUInteger NLClearDepth __attribute__((unused)); // 0x26670, recovered metadata
static NSUInteger NLLockClears;              // 0x26678
static NSUInteger NLLockCollectionDeletes;   // 0x26680

static NSString *const kNLLockPlistKey = @"lockScreen";


#pragma mark - NLLockImageCache

@interface NLLockImageCache : NSObject
@property (nonatomic, weak) id cell;
@property (nonatomic, weak) UIView *card;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) NSString *identity;
@property (nonatomic) CGRect screenFrame;
@property (nonatomic) double capturedAt;
- (void)expire;   // 0x16600
@end

@implementation NLLockImageCache

// 0x16600
- (void)expire
{
    if (self.capturedAt == 0) {
        return;
    }
    if (CACurrentMediaTime() - self.capturedAt > 2.0) {
        self.image = nil;
        self.card = nil;
        self.identity = nil;
        self.capturedAt = 0;
    }
}

@end


#pragma mark - 工具

/// 0x16800 —— view（或其子视图）是否已经被消散效果接管。
BOOL NLLockScreenDustOwnsView(UIView *view)
{
    if (![view isKindOfClass:[UIView class]]) {
        return NO;
    }
    if ([NLWithdrawalEffect isActiveForView:view]) {
        return YES;
    }
    for (UIView *sub in view.subviews) {
        if ([NLWithdrawalEffect isActiveForView:sub]) {
            return YES;
        }
        if (NLLockScreenDustOwnsView(sub)) {
            return YES;
        }
    }
    return NO;
}

/// 0x181a4 —— 从一个 cell 里找出真正承载卡片的 view。
/// 依次尝试 _notificationShortLookViewIfLoaded / _lookViewIfLoaded / lookView /
/// notificationRequest 对应的 controller.view。
static UIView *NLLockCard(id cell)
{
    if (!cell) {
        return nil;
    }
    for (NSString *key in @[@"_notificationShortLookViewIfLoaded",
                            @"_lookViewIfLoaded",
                            @"lookView",
                            @"shortLookView"]) {
        SEL sel = NSSelectorFromString(key);
        if ([cell respondsToSelector:sel]) {
            id candidate = NLABIReadObject(cell, sel);
            if ([candidate isKindOfClass:[UIView class]]) {
                return candidate;
            }
        }
    }
    // 退一步：notificationRequest → viewController → view
    SEL reqSel = NSSelectorFromString(@"notificationRequest");
    if ([cell respondsToSelector:reqSel]) {
        id request = NLABIReadObject(cell, reqSel);
        for (NSString *key in @[@"contentViewController",
                                @"notificationViewController",
                                @"_contentViewController",
                                @"viewController"]) {
            SEL sel = NSSelectorFromString(key);
            if ([request respondsToSelector:sel]) {
                id vc = NLABIReadObject(request, sel);
                if ([vc isKindOfClass:[UIViewController class]] &&
                    [(UIViewController *)vc isViewLoaded]) {
                    return [(UIViewController *)vc view];
                }
            }
        }
    }
    return nil;
}

/// 0x18448 —— tick 回调：判断 cell 是否已经从列表里撤掉。
static NLDisposition NLLockState(NLWithdrawalEffect *effect)
{
    if (!effect) {
        return NLDispositionAbort;
    }
    UIView *source = effect.sourceView;
    if (!source) {
        return NLDispositionProceed;
    }
    if (effect.preswipeCached) {
        // preswipe 路径：只要原生动画开始就可以播
        return effect.nativeCompleted ? NLDispositionProceed : NLDispositionPending;
    }
    // 普通路径：源视图必须已经不可见
    if (!NLVisible(source)) {
        return NLDispositionProceed;
    }
    return NLDispositionPending;
}


#pragma mark - 准备

/// 0x17c9c —— 核心：给一个 cell 准备消散效果。
static void NLPrepareCell(id cell, NSString *identity)
{
    if (![NSThread isMainThread]) {
        return;
    }
    if (!NLPreference(@"Enabled")) {
        return;
    }
    if (![cell isKindOfClass:NSClassFromString(@"NCNotificationListCell")]) {
        return;
    }
    if (![NLDustRenderer isReady]) {
        return;
    }

    UIView *card = NLLockCard(cell);
    if (!card) {
        NLWithdrawalRecord(@"skip:no-real-card");
        return;
    }

    // 优先用 preswipe 缓存（pan 开始时抓的图）
    NLLockImageCache *cache = (NLLockImageCache *)NLLockCaches[identity ?: @""];
    if (cache) {
        [cache expire];
        if (cache.image.CGImage && cache.card == card &&
            [cache.identity isEqual:identity]) {
            NLWithdrawalEffect *effect =
                [NLWithdrawalEffect prepareView:card
                                    cachedImage:cache.image
                                    screenFrame:cache.screenFrame
                                         source:identity
                                     preference:kNLLockPlistKey];
            if (effect) {
                effect.owner = cell;
                effect.payload = identity;
                effect.identity = identity;
                effect.disposition = NLLockState;
                effect.requiresRemovalConfirmation = YES;
                effect.context = ((UIView *)cell).superview;
                NLWithdrawalRecord(@"lockscreen-preswipe-cached");
            }
            return;
        }
    }

    NLWithdrawalEffect *effect =
        [NLWithdrawalEffect prepareView:card
                                 source:identity
                             preference:kNLLockPlistKey];
    if (!effect) {
        return;
    }
    effect.owner = cell;
    effect.payload = identity;
    effect.identity = identity;
    effect.disposition = NLLockState;
    effect.requiresRemovalConfirmation = YES;
    effect.context = ((UIView *)cell).superview;
}


#pragma mark - hooks

/// 0x16bfc —— 替换 -[NCNotificationListCell _executeClearAction]
static void NLCellClear(id self, SEL _cmd)
{
    NLLockClears = NLLockClears + 1;
    NLWithdrawalRecord(@"lockscreen-cell-clear");

    // 清除动作：先抓图再调原实现
    NLLockImageCache *cache = [[NLLockImageCache alloc] init];
    UIView *card = NLLockCard(self);
    if (card && card.window) {
        CGRect bounds = card.bounds;
        UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 2.0);
        BOOL ok = [card drawViewHierarchyInRect:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                             afterScreenUpdates:NO];
        cache.image = ok ? UIGraphicsGetImageFromCurrentImageContext() : nil;
        UIGraphicsEndImageContext();
        cache.card = card;
        cache.capturedAt = CACurrentMediaTime();
        cache.identity = [NSString stringWithFormat:@"cell-%p", (void *)self];
        cache.screenFrame = [card convertRect:bounds toView:nil];
        if (cache.image.CGImage) {
            if (!NLLockCaches) {
                NLLockCaches = [NSMutableDictionary dictionary];
            }
            NLLockCaches[cache.identity] = cache;
            objc_setAssociatedObject(self, &NLLockCacheKey, cache,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    ((void (*)(id, SEL))NLCellClearOriginal)(self, _cmd);

    if (cache.identity) {
        NLPrepareCell(self, cache.identity);
    }
}

/// 0x16d58 —— 替换 -[NCNotificationListCell setContentViewController:]
static void NLCellSetContent(id self, SEL _cmd, id controller)
{
    // 内容变了说明 cell 被复用给另一条通知：取消旧效果
    [NLWithdrawalEffect cancelEffectsForView:NLLockCard(self)];
    ((void (*)(id, SEL, id))NLCellSetContentOriginal)(self, _cmd, controller);
}

/// 0x16ee8 —— 替换 -[NCNotificationListCell _handlePanGesture:]
/// 在滑动开始时先抓一张图，滑动结束如果 cell 被移除就用这张图。
static void NLCellPan(id self, SEL _cmd, id gesture)
{
    UIGestureRecognizerState state = UIGestureRecognizerStatePossible;
    if (gesture && NLABIMethod(object_getClass(gesture), @selector(state), @encode(NSInteger), 0, NULL)) {
        state = ((NSInteger (*)(id, SEL))[gesture methodForSelector:@selector(state)])(gesture, @selector(state));
    }

    if (state == UIGestureRecognizerStateBegan) {
        UIView *card = NLLockCard(self);
        if (card && card.window) {
            CGRect bounds = card.bounds;
            UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 2.0);
            BOOL ok = [card drawViewHierarchyInRect:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                 afterScreenUpdates:NO];
            UIImage *image = ok ? UIGraphicsGetImageFromCurrentImageContext() : nil;
            UIGraphicsEndImageContext();

            if (image.CGImage) {
                NLLockImageCache *cache = [[NLLockImageCache alloc] init];
                cache.image = image;
                cache.card = card;
                cache.capturedAt = CACurrentMediaTime();
                cache.identity = [NSString stringWithFormat:@"pan-%p", (void *)self];
                cache.screenFrame = [card convertRect:bounds toView:nil];
                if (!NLLockCaches) {
                    NLLockCaches = [NSMutableDictionary dictionary];
                }
                NLLockCaches[cache.identity] = cache;
                objc_setAssociatedObject(self, &NLLockCacheKey, cache,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }

    ((void (*)(id, SEL, id))NLCellPanOriginal)(self, _cmd, gesture);

    if (state == UIGestureRecognizerStateEnded ||
        state == UIGestureRecognizerStateCancelled) {
        NLLockImageCache *cache = objc_getAssociatedObject(self, &NLLockCacheKey);
        if (cache && cache.identity) {
            NLPrepareCell(self, cache.identity);
        }
    }
}

/// 0x175dc —— 替换 -[UICollectionView deleteItemsAtIndexPaths:]
/// 锁屏"清除全部"走这条路。
static void NLCollectionDelete(id self, SEL _cmd, id indexPaths)
{
    NLLockCollectionDeletes = NLLockCollectionDeletes + 1;
    NLWithdrawalRecord(@"lockscreen-collection-delete");

    // 先把要删的 cell 全抓一遍图
    NSMutableArray *cells = [NSMutableArray array];
    if ([self isKindOfClass:[UICollectionView class]] &&
        [indexPaths isKindOfClass:[NSArray class]]) {
        for (NSIndexPath *path in indexPaths) {
            UICollectionViewCell *cell = [(UICollectionView *)self cellForItemAtIndexPath:path];
            if (cell) {
                [cells addObject:cell];
            }
        }
    }

    ((void (*)(id, SEL, id))NLCollectionDeleteOriginal)(self, _cmd, indexPaths);

    for (id cell in cells) {
        NLLockImageCache *cache = objc_getAssociatedObject(cell, &NLLockCacheKey);
        NSString *identity = cache.identity
            ?: [NSString stringWithFormat:@"delete-%p", (void *)cell];
        NLPrepareCell(cell, identity);
    }
}


#pragma mark - 安装

// 0x16a08
void NLInstallLockScreenDustHooks(void)
{
    if (![NSThread isMainThread]) {
        return;
    }

    Class cellClass = NSClassFromString(@"NCNotificationListCell");
    if (cellClass) {
        SEL clearSel = NSSelectorFromString(@"_executeClearAction");
        SEL setContentSel = NSSelectorFromString(@"setContentViewController:");
        SEL panSel = NSSelectorFromString(@"_handlePanGesture:");

        if (!NLCellClearOriginal && class_getInstanceMethod(cellClass, clearSel)) {
            MSHookMessageEx(cellClass, clearSel, (IMP)NLCellClear, &NLCellClearOriginal);
        }
        if (!NLCellSetContentOriginal && class_getInstanceMethod(cellClass, setContentSel)) {
            MSHookMessageEx(cellClass, setContentSel, (IMP)NLCellSetContent, &NLCellSetContentOriginal);
        }
        if (!NLCellPanOriginal && class_getInstanceMethod(cellClass, panSel)) {
            MSHookMessageEx(cellClass, panSel, (IMP)NLCellPan, &NLCellPanOriginal);
        }
    }

    // UICollectionView 的 deleteItemsAtIndexPaths: —— 只在有 cell hook 时才装
    if (cellClass && !NLCollectionDeleteOriginal) {
        Class collectionClass = [UICollectionView class];
        SEL deleteSel = NSSelectorFromString(@"deleteItemsAtIndexPaths:");
        Method method = class_getInstanceMethod(collectionClass, deleteSel);
        if (method && method_getNumberOfArguments(method) == 3) {
            MSHookMessageEx(collectionClass, deleteSel,
                            (IMP)NLCollectionDelete, &NLCollectionDeleteOriginal);
        }
    }
}

// 0x17a78
NSDictionary *NLLockScreenDustStatus(void)
{
    return @{
        @"cellClearHook": @(NLCellClearOriginal != NULL),
        @"preswipeCacheHook": @(NLCellPanOriginal != NULL),
        @"collectionDeleteHook": @(NLCollectionDeleteOriginal != NULL),
        @"clearCalls": @(NLLockClears),
        @"deleteCalls": @(NLLockCollectionDeletes),
    };
}
