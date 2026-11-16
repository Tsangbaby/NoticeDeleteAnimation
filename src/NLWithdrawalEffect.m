//
//  NLWithdrawalEffect.m
//  NoticeListTweak — 通知消散
//
//  逆向自 1.0.1~test14。原始地址写在每个函数上方。
//

#import "NLWithdrawalEffect.h"
#import "NLDustRenderer.h"
#import "NLPreferences.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// ---------------------------------------------------------------- 常量

// 全局配置变量定义在 NLPreferences.m

// 静态阈值（0x195xx 常量池）
static const double kNLMinVisibleAlpha = 0.02;     // 0x195c0
static const double kNLFullscreenFactor = 0.8;     // 0x195d0
static const double kNLMaxOverlayScale = 2.0;
static const double kNLFrameTimeout = 0.6;         // 0x3fe3333333333333
static const double kNLFinishGrace = 0.15;         // 0x3fc3333333333333
static const double kNLMinDuration = 0.7;
static const double kNLMaxDuration = 2.5;
static const double kNLMinDistance = 20.0;
static const double kNLMaxDistance = 200.0;
static const NSUInteger kNLMaxTexturePixels = 1200000;   // 0x41324f8000000000
static const NSUInteger kNLMaxEffects = 6;
static const NSUInteger kNLPrepareParticles = 7000;      // 0x1b58

// ---------------------------------------------------------------- 全局状态
// 注：NLPreferenceEnabled / NLPreferenceBanner / NLPreferenceReadAt 与
// NLEvents / NLLastEvent 定义在 NLPreferences.m（声明见 NLPreferences.h）。
static NSMutableArray<NLWithdrawalEffect *> *NLEffects;   // 0x265d0
static id NLLastSource;            // 0x265e8
static NSString *NLLastView;       // 0x265f0
char NLSourceEffectKey;            // 0x265f8（定义，声明见 NLPreferences.h）


#pragma mark - NLWithdrawalWindow

@implementation NLWithdrawalWindow

// 0x11490
- (BOOL)canBecomeKeyWindow
{
    return NO;
}

// 0x11498
- (BOOL)_canShowWhileLocked
{
    return YES;
}

@end


#pragma mark - NLWithdrawalEffect

@implementation NLWithdrawalEffect

// 0x114a0
+ (BOOL)isActiveForView:(UIView *)view
{
    return objc_getAssociatedObject(view, &NLSourceEffectKey) != nil;
}

// 0x114e4
+ (BOOL)isPendingForOwner:(id)owner payload:(id)payload
{
    for (NLWithdrawalEffect *effect in [NLEffects copy]) {
        if (effect.finished) {
            continue;
        }
        if (effect.owner != owner) {
            continue;
        }
        if (effect.payload != payload) {
            continue;
        }
        return YES;
    }
    return NO;
}

// 0x116fc
+ (void)cancelEffectsForView:(UIView *)view
{
    for (NLWithdrawalEffect *effect in [NLEffects copy]) {
        if (effect.sourceView == view) {
            [effect cancel];
        }
    }
}

// 0x118a0
+ (instancetype)prepareView:(UIView *)view
                     source:(id)source
                 preference:(NSString *)preference
{
    return [self prepareView:view
                 cachedImage:nil
                 screenFrame:CGRectZero
                      source:source
                  preference:preference];
}

// 0x118e8
+ (instancetype)prepareView:(UIView *)view
                cachedImage:(UIImage *)cachedImage
                screenFrame:(CGRect)screenFrame
                     source:(id)source
                 preference:(NSString *)preference
{
    NLWithdrawalRecord(@"withdrawal-seen");

    if (![NSThread isMainThread]) {
        return nil;
    }

    BOOL prefEnabled = NLPreference(preference);
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    BOOL visible = NLVisible(view);

    BOOL hasCache = NO;
    BOOL hasWindow = NO;
    if (visible) {
        hasWindow = YES;
    } else if (cachedImage.CGImage != NULL) {
        hasCache = YES;
        hasWindow = (view.window != nil);
    }

    BOOL dustReady = [NLDustRenderer isReady];
    BOOL alreadyActive = [self isActiveForView:view];

    BOOL eligible = (view != nil) && prefEnabled && !reduceMotion && hasWindow && dustReady;
    if (alreadyActive || !eligible) {
        NLWithdrawalRecord(alreadyActive ? @"skip:duplicate" : @"skip:unavailable");
        return nil;
    }

    if (NLExistingNotificationSnapshotActive(view)) {
        NLWithdrawalRecord(@"skip:duplicate");
        return nil;
    }
    if (NLEffects.count >= kNLMaxEffects) {
        NLWithdrawalRecord(@"skip:effect-limit");
        return nil;
    }

    // —— 快照尺寸与缩放 ——
    CGRect bounds = view.bounds;
    CGFloat scale = view.window.screen.scale;
    if (!isfinite(bounds.size.width) || !isfinite(bounds.size.height)) {
        return nil;
    }
    if (bounds.size.width < 1.0 || bounds.size.height < 1.0) {
        return nil;
    }
    scale = fmin(scale, kNLMaxOverlayScale);
    if (ceil(bounds.size.width * scale) * ceil(bounds.size.height * scale) > kNLMaxTexturePixels) {
        return nil;
    }

    UIImage *image = cachedImage;
    if (!image) {
        UIGraphicsBeginImageContextWithOptions(bounds.size, NO, scale);
        BOOL ok = [view drawViewHierarchyInRect:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                             afterScreenUpdates:NO];
        if (ok) {
            image = UIGraphicsGetImageFromCurrentImageContext();
        }
        UIGraphicsEndImageContext();
    }

    if (!image.CGImage) {
        NLWithdrawalRecord(@"skip:snapshot-failed");
        return nil;
    }

    // —— 选择承载窗口 ——
    UIWindow *sourceWindow = view.window;
    UIWindowScene *scene = sourceWindow.windowScene;
    NLWithdrawalWindow *overlay = nil;
    BOOL matchedScene = NO;

    if (scene) {
        CGRect sceneBounds = scene.coordinateSpace.bounds;
        CGRect windowBounds = sourceWindow.coordinateSpace.bounds;
        if (windowBounds.size.width >= sceneBounds.size.width * kNLFullscreenFactor &&
            windowBounds.size.height >= sceneBounds.size.height * kNLFullscreenFactor) {
            matchedScene = YES;
        }
    } else {
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)candidate;
            if (windowScene.coordinateSpace.bounds.size.width >=
                    sourceWindow.coordinateSpace.bounds.size.width * kNLFullscreenFactor &&
                windowScene.coordinateSpace.bounds.size.height >=
                    sourceWindow.coordinateSpace.bounds.size.height * kNLFullscreenFactor) {
                scene = windowScene;
                matchedScene = YES;
                break;
            }
        }
    }

    if (matchedScene && scene) {
        overlay = [[NLWithdrawalWindow alloc] initWithWindowScene:scene];
        overlay.frame = scene.coordinateSpace.bounds;
    } else {
        overlay = [[NLWithdrawalWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        overlay.screen = UIScreen.mainScreen;
    }

    overlay.backgroundColor = [UIColor clearColor];
    overlay.userInteractionEnabled = NO;
    overlay.windowLevel = sourceWindow.windowLevel + 1.0;

    UIViewController *root = [UIViewController new];
    root.view.frame = overlay.bounds;
    root.view.backgroundColor = [UIColor clearColor];
    root.view.userInteractionEnabled = NO;
    overlay.rootViewController = root;

    // —— 计算 overlay 坐标系下的卡片矩形 ——
    CGRect cardRect;
    if (cachedImage.CGImage != NULL) {
        cardRect = screenFrame;
    } else {
        CGRect inScene = [view convertRect:view.bounds
                         toCoordinateSpace:sourceWindow.screen.coordinateSpace];
        cardRect = [overlay convertRect:inScene
                    fromCoordinateSpace:sourceWindow.screen.coordinateSpace];
    }

    // —— 读取时长 / 距离（每次现读，不受 0.25s 缓存影响）——
    double duration = NLAnimationDuration;
    CFTypeRef durRef = CFPreferencesCopyAppValue(CFSTR("DustDuration"),
                                                 (__bridge CFStringRef)NLAppID);
    if (durRef && CFGetTypeID(durRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(durRef, kCFNumberDoubleType, &duration);
    }
    if (durRef) CFRelease(durRef);
    if (!isfinite(duration) || duration < kNLMinDuration || duration > kNLMaxDuration) {
        duration = NLAnimationDuration;
    }

    double distance = NLDustDistance;
    CFTypeRef distRef = CFPreferencesCopyAppValue(CFSTR("DustDistance"),
                                                  (__bridge CFStringRef)NLAppID);
    if (distRef && CFGetTypeID(distRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(distRef, kCFNumberDoubleType, &distance);
    }
    if (distRef) CFRelease(distRef);
    if (!isfinite(distance) || distance < kNLMinDistance || distance > kNLMaxDistance) {
        distance = NLDustDistance;
    }

    NLDustRenderer *renderer =
        [[NLDustRenderer alloc] initWithImage:image.CGImage
                                    cardFrame:cardRect
                                particleCount:kNLPrepareParticles
                                     duration:duration
                                     distance:distance
                                         seed:(float)arc4random_uniform(10000)];
    if (!renderer) {
        overlay.rootViewController = nil;
        return nil;
    }

    [root.view addSubview:renderer];
    renderer.frame = cardRect;

    UIImageView *cover = [[UIImageView alloc] initWithImage:image];
    cover.frame = cardRect;
    [root.view addSubview:cover];

    overlay.hidden = NO;
    [overlay layoutIfNeeded];
    [root.view layoutIfNeeded];

    if (![renderer primeFrame]) {
        [renderer invalidate];
        overlay.hidden = YES;
        overlay.rootViewController = nil;
        NLWithdrawalRecord(@"skip:metal-first-frame");
        return nil;
    }

    NLWithdrawalEffect *effect = [[self alloc] init];
    effect.sourceView = view;
    effect.overlay = overlay;
    effect.renderer = renderer;
    effect.cover = cover;
    effect.preference = preference;
    effect.preparedAt = CACurrentMediaTime();
    effect.duration = duration;
    effect.preswipeCached = (cachedImage.CGImage != NULL);

    objc_setAssociatedObject(view, &NLSourceEffectKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (!NLEffects) {
        NLEffects = [NSMutableArray array];
    }
    [NLEffects addObject:effect];
    NLLastSource = source;
    NLLastView = NSStringFromClass([view class]);

    NLWithdrawalRecord(@"snapshot-ready");
    return effect;
}

// 0x12f00
- (void)beginAfterNativeRemoval
{
    if (self.finished || self.nativeCompleted) {
        return;
    }
    self.nativeCompleted = YES;

    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    self.link = link;
    link.preferredFramesPerSecond = 60;
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    [self tick:link];
}

// 0x130cc
- (void)tick:(CADisplayLink *)link
{
    if (self.finished) {
        return;
    }

    double now = CACurrentMediaTime();

    if (!NLPreference(self.preference)) {
        [self finish];
        return;
    }
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self finish];
        return;
    }

    NSInteger disposition = self.disposition ? self.disposition(self) : NLDispositionPending;
    if (disposition == NLDispositionAbort) {
        NLWithdrawalRecord(@"skip:reused-source");
        [self finish];
        return;
    }

    if (self.startedAt != 0) {
        if ((now - self.startedAt) > self.duration + kNLFinishGrace) {
            [self finish];
        }
        return;
    }

    BOOL visible = NLVisible(self.sourceView);
    BOOL needsConfirm = self.preswipeCached ? YES : self.requiresRemovalConfirmation;
    BOOL confirmed = (disposition == NLDispositionProceed) || !(visible || needsConfirm);

    if (confirmed) {
        self.removalConfirmed = YES;
    }

    BOOL completed = [self.renderer hasCompletedFrame];
    BOOL failed = [self.renderer hasFailedFrame];

    if (failed) {
        NLWithdrawalRecord(@"skip:native-not-removed-or-frame");
        [self finish];
        return;
    }

    double age = now - self.preparedAt;
    if (!isfinite(age) || age < 0 || age > kNLFrameTimeout) {
        NLWithdrawalRecord(@"skip:native-not-removed-or-frame");
        [self finish];
        return;
    }

    if (!(confirmed && completed)) {
        return;
    }

    if (visible) {
        CALayer *layer = self.sourceView.layer;
        self.savedSourceMask = layer.mask;

        CALayer *mask = [CALayer layer];
        mask.frame = self.sourceView.bounds;
        self.sourceCoverMask = mask;
        layer.mask = mask;
    }

    self.startedAt = now;
    [self.renderer start];

    [self.cover removeFromSuperview];
    self.cover = nil;

    NLWithdrawalRecord(@"dust-started");
}

// 0x1363c
- (void)cancel
{
    [self finish];
}

// 0x13648
- (void)finish
{
    if (self.finished) {
        return;
    }
    self.finished = YES;

    [self.link invalidate];
    self.link = nil;

    [self.renderer invalidate];
    self.renderer = nil;

    self.overlay.hidden = YES;
    self.overlay.rootViewController = nil;
    self.overlay = nil;
    self.cover = nil;

    UIView *source = self.sourceView;
    CALayer *coverMask = self.sourceCoverMask;
    if (coverMask) {
        CALayer *layer = source.layer;
        if (layer.mask == coverMask) {
            layer.mask = self.savedSourceMask;
        }
    }
    self.sourceCoverMask = nil;
    self.savedSourceMask = nil;

    if (objc_getAssociatedObject(source, &NLSourceEffectKey) == self) {
        objc_setAssociatedObject(source, &NLSourceEffectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    self.sourceView = nil;
    self.owner = nil;
    self.payload = nil;

    [NLEffects removeObjectIdenticalTo:self];
}

// 0x13bb0

@end
