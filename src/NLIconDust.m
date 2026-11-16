//
//  NLIconDust.m
//  NoticeListTweak — 通知消散
//
//  桌面图标卸载时的消散。逆向自 1.0.1~test14，地址见各函数。
//
//  SBHIconManager 有四条卸载路径（uninstallIcon: 三个 overload + removeIcon:options:completion:），
//  外加 iconModel:willRemoveIcon: 通知。这里 hook 全部，但只在实际移除后才播动画：
//  卸载对话框里的"取消"不会触发，因为那时图标根本没从模型里移除。
//

#import "NLIconDust.h"
#import "NLPreferences.h"
#import "NLWithdrawalEffect.h"
#import "NLDustRenderer.h"
#import "NLRuntimeABI.h"

#import <objc/runtime.h>
#import <substrate.h>

// ---------------------------------------------------------------- 全局状态
static NSMutableSet *NLIconJobs;                  // 0x26530
static char NLIconDustSnapshotKey;                // 0x26538
static BOOL NLIconHooksInstalled;                 // 0x26539
static IMP NLOriginalUninstall1;                  // 0x26540
static IMP NLOriginalUninstall2;                  // 0x26548
static IMP NLOriginalUninstall3;                  // 0x26550
static IMP NLOriginalRemove3;                     // 0x26558
static IMP NLOriginalWillRemove;                  // 0x26560

// 类型编码白名单（与列表 hook 用的是同一张表）
static const char *kNLVoidishTypes = "rnNoORV";


#pragma mark - 工具

/// 0x9a54 —— 安全地取 icon 上某个 selector 的返回值。
static id NLIconGet(id icon, SEL sel);

/// 0xa3e0 —— 从 method 的类型编码推断"这个 selector 属于哪类图标操作"。
/// 返回 1/2/3 表示 uninstall 的三个 overload，4 表示 removeIcon，0 表示不认识。
static __attribute__((unused)) int NLIconType(Method method, int argc, const char *retType)
{
    if (!method) {
        return 0;
    }
    if (method_getNumberOfArguments(method) != (unsigned)argc) {
        return 0;
    }
    char *rt = method_copyReturnType(method);
    if (!rt) {
        return 0;
    }
    BOOL ok = YES;
    for (char *p = rt; *p; p++) {
        if (memchr(kNLVoidishTypes, *p, 8)) {
            ok = NO;
            break;
        }
    }
    if (ok && retType && rt[0] != retType[0]) {
        ok = NO;
    }
    free(rt);
    return ok ? 1 : 0;
}

/// 0xa494 —— 校验 class 上 sel 的参数个数与参数类型。
static BOOL NLIconSignature(Class cls, SEL sel, unsigned int argc, const char *types)
{
    if (!cls || !sel) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != argc) {
        return NO;
    }
    char *rt = method_copyReturnType(method);
    BOOL returnsVoid = rt && NLABITypeMatches(rt, "v");
    free(rt);
    if (!returnsVoid) return NO;
    size_t want = strlen(types);
    if (argc < 3 || (argc - 2) != want) {
        return NO;
    }
    for (unsigned int i = 0; i < want; i++) {
        char *t = method_copyArgumentType(method, i + 2);
        BOOL ok = t && t[0] == types[i];
        if (t) free(t);
        if (!ok) {
            return NO;
        }
    }
    return YES;
}

/// 0x9808 —— 判断 icon 是否属于桌面（而不是文件夹/资源库/搜索/停靠栏）。
///
/// 二进制的做法：
///   folder = [manager rootFolder]                       (NLIconGet, 0x20628)
///   method = [folder methodForSelector:@selector(indexPathForIcon:)]  (0x20708)
///   校验 method 参数个数 == 3、返回类型是对象、参数类型是对象
///   ok  = [folder indexPathForIcon:icon] != nil
/// 即"这个 icon 在根文件夹里有位置"= 在桌面上。
static BOOL NLIconHomeMembership(id manager, id icon, BOOL *outIsHome)
{
    if (outIsHome) {
        *outIsHome = NO;
    }
    if (!manager || !icon) {
        return NO;
    }

    id folder = NLIconGet(manager, NSSelectorFromString(@"rootFolder"));
    if (!folder) {
        return NO;
    }

    SEL indexPathSel = NSSelectorFromString(@"indexPathForIcon:");
    Method method = class_getInstanceMethod(object_getClass(folder), indexPathSel);
    if (!method || method_getNumberOfArguments(method) != 3) {
        return NO;
    }
    char *retType = method_copyReturnType(method);
    BOOL retIsObject = retType && retType[0] == '@';
    if (retType) free(retType);
    if (!retIsObject) {
        return NO;
    }
    char *argType = method_copyArgumentType(method, 2);
    BOOL argIsObject = argType && argType[0] == '@';
    if (argType) free(argType);
    if (!argIsObject) {
        return NO;
    }

    id indexPath = NLABISendObject(folder, indexPathSel, icon);
    if (outIsHome) {
        *outIsHome = (indexPath != nil);
    }
    return YES;
}

// 0x9a54
static id NLIconGet(id icon, SEL sel)
{
    if (!icon || !sel || !NLABIMethod(object_getClass(icon), sel, "@", 0, NULL)) {
        return nil;
    }
    return ((id (*)(id, SEL))[icon methodForSelector:sel])(icon, sel);
}

/// 0xc188 —— 找同 manager + 同 icon 上还没结束的快照（去重用）。
static id NLFindPendingIcon(id manager, id icon)
{
    if (!NLIconJobs) {
        return nil;
    }
    for (id job in NLIconJobs) {
        if ([job respondsToSelector:NSSelectorFromString(@"manager")] &&
            [job respondsToSelector:NSSelectorFromString(@"icon")]) {
            id jobManager = NLABIReadObject(job, NSSelectorFromString(@"manager"));
            id jobIcon = NLABIReadObject(job, NSSelectorFromString(@"icon"));
            if (jobManager == manager && jobIcon == icon) {
                return job;
            }
        }
    }
    return nil;
}

/// 0xbe9c —— 图标消散开关（含时长/距离/粒子数的范围钳制）。
static BOOL NLIconDustIsEnabled(void)
{
    CFStringRef appID = (__bridge CFStringRef)NLAppID;
    CFPreferencesAppSynchronize(appID);

    CFTypeRef enabledRef = CFPreferencesCopyAppValue(CFSTR("HomeIconDustEnabled"), appID);
    CFTypeRef durationRef = CFPreferencesCopyAppValue(CFSTR("DustDuration"), appID);
    CFTypeRef distanceRef = CFPreferencesCopyAppValue(CFSTR("DustDistance"), appID);
    CFTypeRef particlesRef = CFPreferencesCopyAppValue(CFSTR("DustParticles"), appID);

    BOOL enabled = YES;
    double duration = NLIconDustDuration;
    double distance = NLIconDustDistance;
    double particles = (double)NLIconDustParticles;

    if (enabledRef && CFGetTypeID(enabledRef) == CFBooleanGetTypeID()) {
        enabled = CFBooleanGetValue(enabledRef) ? YES : NO;
    }
    if (durationRef && CFGetTypeID(durationRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(durationRef, kCFNumberDoubleType, &duration);
    }
    if (distanceRef && CFGetTypeID(distanceRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(distanceRef, kCFNumberDoubleType, &distance);
    }
    if (particlesRef && CFGetTypeID(particlesRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(particlesRef, kCFNumberDoubleType, &particles);
    }

    if (enabledRef) CFRelease(enabledRef);
    if (durationRef) CFRelease(durationRef);
    if (distanceRef) CFRelease(distanceRef);
    if (particlesRef) CFRelease(particlesRef);

    if (!isfinite(duration) || duration < 0.7 || duration > 2.5) {
        duration = 1.3;
    }
    if (!isfinite(distance) || distance < 40.0 || distance > 200.0) {
        distance = 110.0;
    }
    if (!isfinite(particles) || particles < 4000.0 || particles > 20000.0) {
        particles = 6000.0;
    }

    NLIconDustEnableState = enabled;
    NLIconDustDuration = duration;
    NLIconDustDistance = distance;
    NLIconDustParticles = (NSUInteger)particles;

    return enabled;
}


#pragma mark - NLIconDustSnapshot

@interface NLIconDustSnapshot : NSObject
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL started;
@property (nonatomic) BOOL armed;
@property (nonatomic, strong) NLDustRenderer *renderer;
@property (nonatomic, strong) UIView *source;
@property (nonatomic, weak) UIView *iconView;
@property (nonatomic, strong) id manager;
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *overlay;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) double duration;
@property (nonatomic) double deadline;

- (void)start;            // 0x919c
- (void)waitForDetach:(double)timeout;   // 0x9308
- (void)poll;             // 0x9414
- (void)finish;           // 0x9b3c
@end


@implementation NLIconDustSnapshot

// 0x919c
- (void)start
{
    if (self.active || self.started) {
        return;
    }
    if (!self.renderer) {
        return;
    }
    self.started = YES;
    self.overlay.hidden = NO;

    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    [self.renderer start];
    [self performSelector:@selector(finish)
               withObject:nil
               afterDelay:self.duration + 0.15];
}

// 0x9308
- (void)waitForDetach:(double)timeout
{
    if (!self.active || self.started || self.armed) {
        return;
    }
    self.armed = YES;
    self.deadline = CACurrentMediaTime() + timeout;
    self.overlay.hidden = NO;
    [self performSelector:@selector(poll) withObject:nil afterDelay:0.05];
}

// 0x9414
- (void)poll
{
    if (!self.active || self.started) {
        return;
    }
    if (!self.manager || !self.icon) {
        [self finish];
        return;
    }

    // 图标是否还挂在原位置
    BOOL detached = YES;
    if ([self.manager respondsToSelector:NSSelectorFromString(@"firstIconViewForIcon:")]) {
        id view = NLABISendObject(self.manager, NSSelectorFromString(@"firstIconViewForIcon:"), self.icon);
        if ([view isKindOfClass:[UIView class]]) {
            UIView *iconView = (UIView *)view;
            if (iconView.window && !iconView.isHidden && iconView.alpha >= 0.02) {
                detached = NO;
            }
        }
    }

    if (detached) {
        // 图标已经从桌面移除，开始播消散
        [self start];
        return;
    }

    if (CACurrentMediaTime() > self.deadline) {
        [self finish];
        return;
    }
    [self performSelector:@selector(poll) withObject:nil afterDelay:0.05];
}

// 0x9b3c
- (void)finish
{
    if (!self.active) {
        return;
    }
    self.active = NO;

    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self.renderer invalidate];
    [self.overlay removeFromSuperview];

    if (self.source && [self.source respondsToSelector:NSSelectorFromString(@"layer")]) {
        CALayer *layer = [(UIView *)self.source layer];
        layer.mask = nil;
    }

    self.renderer = nil;
    self.overlay = nil;
    self.source = nil;
    self.iconView = nil;
    self.icon = nil;
    self.identifier = nil;

    if (NLIconJobs) {
        [NLIconJobs removeObject:self];
    }
}

// 0x9d14
- (void)dealloc
{
    [self finish];
}

@end


#pragma mark - 图标准备

/// 0xabf8 —— 最大的函数。校验 iconView 能力、抓快照、建 overlay、播动画。
static void NLPrepareIcon(id manager, id icon)
{
    if (![NSThread isMainThread]) {
        return;
    }
    if (!NLIconDustIsEnabled()) {
        return;
    }
    if (![NLDustRenderer isReady]) {
        return;
    }
    if (NLFindPendingIcon(manager, icon)) {
        return;   // 已在处理
    }

    // 1) 拿到承载图标的 SBIconView
    id iconView = nil;
    if ([manager respondsToSelector:NSSelectorFromString(@"firstIconViewForIcon:")]) {
        iconView = NLABISendObject(manager, NSSelectorFromString(@"firstIconViewForIcon:"), icon);
    }
    Class iconViewClass = NSClassFromString(@"SBIconView");
    if (!iconViewClass || ![iconView isKindOfClass:iconViewClass]) {
        return;
    }
    if (![iconView isKindOfClass:[UIView class]]) {
        return;
    }

    // 2) 类型与状态校验
    SEL typeSel = NSSelectorFromString(@"isApplicationIcon");
    if (!NLABIReadBool(icon, typeSel)) {
        // 文件夹 / widget 不处理
        if (NLABIReadBool(icon, NSSelectorFromString(@"isFolderIcon")) ||
            NLABIReadBool(icon, NSSelectorFromString(@"isWidgetIcon"))) {
            return;
        }
    }
    if (NLABIReadBool(iconView, NSSelectorFromString(@"isDragging"))) {
        return;   // 拖动中不播
    }

    // 3) 必须在桌面（不在文件夹/资源库/搜索里）
    BOOL isHome = NO;
    if (!NLIconHomeMembership(manager, icon, &isHome) || !isHome) {
        return;
    }

    UIView *card = (UIView *)iconView;
    if (!card.window || card.isHidden || card.alpha < 0.02) {
        return;
    }

    // 4) 抓快照
    CGRect bounds = card.bounds;
    if (bounds.size.width < 1.0 || bounds.size.height < 1.0) {
        return;
    }
    UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 2.0);
    BOOL ok = [card drawViewHierarchyInRect:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                         afterScreenUpdates:NO];
    UIImage *image = ok ? UIGraphicsGetImageFromCurrentImageContext() : nil;
    UIGraphicsEndImageContext();
    if (!image.CGImage) {
        return;
    }

    // 5) 建 overlay
    UIView *overlay = [[UIView alloc] initWithFrame:card.window.bounds];
    overlay.backgroundColor = [UIColor clearColor];
    overlay.userInteractionEnabled = NO;
    overlay.accessibilityElementsHidden = YES;
    [card.window addSubview:overlay];

    CGRect cardRect = [card convertRect:bounds toView:overlay];
    NLDustRenderer *renderer =
        [[NLDustRenderer alloc] initWithImage:image.CGImage
                                    cardFrame:cardRect
                                particleCount:NLIconDustParticles
                                     duration:NLIconDustDuration
                                     distance:NLIconDustDistance
                                         seed:(float)arc4random_uniform(10000)];
    if (!renderer) {
        [overlay removeFromSuperview];
        return;
    }
    renderer.frame = cardRect;
    [overlay addSubview:renderer];

    if (![renderer primeFrame]) {
        [renderer invalidate];
        [overlay removeFromSuperview];
        return;
    }

    // 6) 建 job，等图标从桌面消失再播
    NLIconDustSnapshot *job = [[NLIconDustSnapshot alloc] init];
    job.active = YES;
    job.manager = manager;
    job.icon = icon;
    job.iconView = card;
    job.source = card;
    job.renderer = renderer;
    job.overlay = overlay;
    job.duration = NLIconDustDuration;
    job.identifier = NLIconGet(icon, NSSelectorFromString(@"leafIdentifier")) ?: @"";

    if (!NLIconJobs) {
        NLIconJobs = [NSMutableSet set];
    }
    [NLIconJobs addObject:job];

    objc_setAssociatedObject(card, &NLIconDustSnapshotKey, job, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [job waitForDetach:NLIconDustDuration + 1.0];
}


#pragma mark - hooks

// 0xa6c0
static void NLUninstall1(id self, SEL _cmd, id icon)
{
    ((void (*)(id, SEL, id))NLOriginalUninstall1)(self, _cmd, icon);
    NLPrepareIcon(self, icon);
}

// 0xa7b8
static void NLUninstall2(id self, SEL _cmd, id icon, BOOL animate)
{
    ((void (*)(id, SEL, id, BOOL))NLOriginalUninstall2)(self, _cmd, icon, animate);
    if (animate) {
        NLPrepareIcon(self, icon);
    }
}

// 0xa8c0
static void NLUninstall3(id self, SEL _cmd, id icon, BOOL animate, void *context)
{
    ((void (*)(id, SEL, id, BOOL, void *))NLOriginalUninstall3)(self, _cmd, icon, animate, context);
    if (animate) {
        NLPrepareIcon(self, icon);
    }
}

// 0xa9d0
static void NLRemove3(id self, SEL _cmd, id icon, NSUInteger options, void *context)
{
    ((void (*)(id, SEL, id, NSUInteger, void *))NLOriginalRemove3)(self, _cmd, icon, options, context);
    NLPrepareIcon(self, icon);
}

// 0xaae0
static void NLWillRemove(id self, SEL _cmd, id model, id icon)
{
    ((void (*)(id, SEL, id, id))NLOriginalWillRemove)(self, _cmd, model, icon);
    NLPrepareIcon(self, icon);
}


#pragma mark - 安装

// 0x9f24
BOOL NLInstallIconDustHooks(void)
{
    if (NLIconHooksInstalled) {
        return YES;
    }
    if (![NSThread isMainThread]) {
        return NO;
    }

    Class cls = NSClassFromString(@"SBHIconManager");
    if (!cls) {
        return NO;
    }

    SEL uninstall1 = NSSelectorFromString(@"uninstallIcon:");
    SEL uninstall2 = NSSelectorFromString(@"uninstallIcon:animate:");
    SEL uninstall3 = NSSelectorFromString(@"uninstallIcon:animate:completion:");
    SEL remove3    = NSSelectorFromString(@"removeIcon:options:completion:");
    SEL willRemove = NSSelectorFromString(@"iconModel:willRemoveIcon:");

    if (!NLOriginalUninstall1 && NLIconSignature(cls, uninstall1, 3, "@")) {
        MSHookMessageEx(cls, uninstall1, (IMP)NLUninstall1, &NLOriginalUninstall1);
    }
    if (!NLOriginalUninstall2 && NLIconSignature(cls, uninstall2, 4, "@B")) {
        MSHookMessageEx(cls, uninstall2, (IMP)NLUninstall2, &NLOriginalUninstall2);
    }
    if (!NLOriginalUninstall3 && NLIconSignature(cls, uninstall3, 5, "@BK")) {
        MSHookMessageEx(cls, uninstall3, (IMP)NLUninstall3, &NLOriginalUninstall3);
    }
    if (!NLOriginalRemove3 && NLIconSignature(cls, remove3, 5, "@QK")) {
        MSHookMessageEx(cls, remove3, (IMP)NLRemove3, &NLOriginalRemove3);
    }
    if (!NLOriginalWillRemove && NLIconSignature(cls, willRemove, 4, "@@")) {
        MSHookMessageEx(cls, willRemove, (IMP)NLWillRemove, &NLOriginalWillRemove);
    }

    NLIconHooksInstalled = (NLOriginalUninstall1 || NLOriginalUninstall2 ||
                            NLOriginalUninstall3 || NLOriginalRemove3);

    NSLog(@"[NoticeListTweak] icon hooks: uninstall=%d/%d/%d remove=%d model=%d",
          NLOriginalUninstall1 != NULL,
          NLOriginalUninstall2 != NULL,
          NLOriginalUninstall3 != NULL,
          NLOriginalRemove3 != NULL,
          NLOriginalWillRemove != NULL);

    return NLIconHooksInstalled;
}
