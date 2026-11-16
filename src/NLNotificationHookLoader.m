//
//  NLNotificationHookLoader.m
//  NoticeListTweak — 通知消散
//
//  逆向自 1.0.1~test14。原始地址写在每个函数上方。
//

#import "NLNotificationHookLoader.h"
#import "NLPreferences.h"
#import "NLDustRenderer.h"
#import "NLWithdrawalEffect.h"
#import "NLRuntimeABI.h"

#import <objc/runtime.h>
#import <substrate.h>

// 其它模块的安装入口
BOOL NLInstallIconDustHooks(void);       // 0x9f24
BOOL NLInstallBannerDustHooks(void);     // 0xc478
void NLInstallIslandDustHooks(void);     // 0x13c70
void NLInstallLockScreenDustHooks(void); // 0x16a08

// 列表 hook 的原始实现槽（定义在此，MSHookMessageEx 的 original 输出）
IMP NLOriginalRemove;             // 0x264e8
IMP NLOriginalRemoveDisplaced;    // 0x264f0
IMP NLOriginalClearAll;           // 0x264f8

// 列表 hook 的替换实现（NLNotificationListHooks.m 定义）
extern void NLRemoveView(id self, SEL _cmd, NSUInteger index, BOOL animated);   // 0x67b4
extern void NLRemoveDisplacedView(id self, SEL _cmd, NSUInteger index,
                                  BOOL animated, BOOL displaced);               // 0x693c
extern void NLClearAll(id self, SEL _cmd);                                      // 0x6ad8

static BOOL NLNativeHooksInstalled;      // 0x264e0


@implementation NLNotificationHookLoader

// 0x58d0
+ (instancetype)sharedLoader
{
    static NLNotificationHookLoader *loader;
    if (!loader) {
        loader = [[NLNotificationHookLoader alloc] init];
    }
    return loader;
}

// 0x591c
- (void)tryInstalling
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(tryInstalling)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }

    // 已装过列表 hook 就只补其它模块
    BOOL listHooksReady = NO;
    if (NLOriginalClearAll != NULL && NLNativeHooksInstalled) {
        listHooksReady = YES;
    } else {
        listHooksReady = [self installListHooksIfPossible];
    }

    BOOL iconOK = NLInstallIconDustHooks();
    BOOL bannerOK = NLInstallBannerDustHooks();
    NLInstallIslandDustHooks();
    NLInstallLockScreenDustHooks();

    if (listHooksReady && iconOK && bannerOK) {
        // 全部就绪，摘掉启动通知的观察
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIApplicationDidFinishLaunchingNotification
                                                      object:nil];
        return;
    }

    // 还有模块没装上：3 秒后重试，最多 15 次
    if (!self.installRetryScheduled && self.installRetriesFired <= 14) {
        self.installRetryScheduled = YES;
        [self performSelector:@selector(retryInstalling) withObject:nil afterDelay:3.0];
    }
}

/// 校验并安装 NCNotificationListView / NCNotificationMasterList 的 hook。
/// 返回列表 hook 是否已就绪。
/// 对应 0x5968-0x61b8 的主干逻辑。
- (BOOL)installListHooksIfPossible
{
    Class listViewClass = NSClassFromString(@"NCNotificationListView");
    if (!listViewClass) {
        return NO;
    }
    if (![listViewClass isSubclassOfClass:[UIView class]]) {
        return NO;
    }

    // removeViewAtIndex: 的返回类型必须是 void
    Method removeMethod = class_getInstanceMethod(listViewClass,
                                                  @selector(_visibleViewAtIndex:));
    if (!removeMethod) {
        NSLog(@"[NoticeListTweak] native list accessor signature unsupported; hooks disabled");
        return NO;
    }
    if (method_getNumberOfArguments(removeMethod) != 3) {
        NSLog(@"[NoticeListTweak] native list accessor signature unsupported; hooks disabled");
        return NO;
    }
    char *returnType = method_copyReturnType(removeMethod);
    if (!returnType) {
        NSLog(@"[NoticeListTweak] native list accessor signature unsupported; hooks disabled");
        return NO;
    }
    // 返回值类型里含 rnNoORV 中任一字符（struct/void 编码）视为不可用
    BOOL badReturn = NO;
    for (char *p = returnType; *p; p++) {
        if (memchr("rnNoORV", *p, 8)) {
            badReturn = YES;
            break;
        }
    }
    free(returnType);
    if (badReturn) {
        NSLog(@"[NoticeListTweak] native list accessor signature unsupported; hooks disabled");
        return NO;
    }
    // Reconstructed calls require object return and an NSUInteger index.
    const char *indexArgument[] = { @encode(NSUInteger) };
    if (!NLABIMethod(listViewClass, @selector(_visibleViewAtIndex:), "@", 1, indexArgument)) {
        NSLog(@"[NoticeListTweak] native list accessor signature unsupported; hooks disabled");
        return NO;
    }

    Class masterClass = NSClassFromString(@"NCNotificationMasterList");
    SEL clearAllSel = NSSelectorFromString(@"clearAll");
    Method clearAllMethod = class_getInstanceMethod(masterClass, clearAllSel);
    Method masterListMethod = class_getInstanceMethod(masterClass, @selector(masterListView));

    if (!NLOriginalClearAll && clearAllMethod && masterListMethod &&
        NLABIMethod(masterClass, clearAllSel, "v", 0, NULL) &&
        NLABIMethod(masterClass, @selector(masterListView), "@", 0, NULL)) {
        // clearAll 的返回类型必须是 void（0x5c54 判 'v'）
        BOOL ok = YES;
        char *rt = method_copyReturnType(clearAllMethod);
        if (!rt) {
            ok = NO;
        } else {
            ok = (rt[0] == 'v');
            free(rt);
        }
        if (ok) {
            MSHookMessageEx(masterClass, clearAllSel, (IMP)NLClearAll, &NLOriginalClearAll);
        }
    }

    // removeViewAtIndex:animated: —— 4 个参数、返回 void
    SEL basicSel = NSSelectorFromString(@"removeViewAtIndex:animated:");
    SEL displacedSel = NSSelectorFromString(@"removeViewAtIndex:animated:isHorizontallyDisplaced:");

    const char *basicArguments[] = { @encode(NSUInteger), "B" };
    const char *displacedArguments[] = { @encode(NSUInteger), "B", "B" };
    Method basicMethod = class_getInstanceMethod(listViewClass, basicSel);
    if (!NLOriginalRemove && basicMethod && NLABIMethod(listViewClass, basicSel, "v", 2, basicArguments)) {
        char *rt = method_copyReturnType(basicMethod);
        if (rt && rt[0] == 'v') {
            MSHookMessageEx(listViewClass, basicSel, (IMP)NLRemoveView, &NLOriginalRemove);
            NLNativeHooksInstalled = YES;
        }
        if (rt) free(rt);
    }

    // removeViewAtIndex:animated:isHorizontallyDisplaced: —— 5 个参数、返回 void
    Method displacedMethod = class_getInstanceMethod(listViewClass, displacedSel);
    if (!NLOriginalRemoveDisplaced && displacedMethod &&
        NLABIMethod(listViewClass, displacedSel, "v", 3, displacedArguments)) {
        char *rt = method_copyReturnType(displacedMethod);
        if (rt && rt[0] == 'v') {
            MSHookMessageEx(listViewClass, displacedSel,
                            (IMP)NLRemoveDisplacedView, &NLOriginalRemoveDisplaced);
            NLNativeHooksInstalled = YES;
        }
        if (rt) free(rt);
    }

    NSLog(@"[NoticeListTweak] native list hooks ready: basic=%d displaced=%d",
          NLOriginalRemove != NULL, NLOriginalRemoveDisplaced != NULL);

    return NLNativeHooksInstalled;
}

// 0x61d4
- (void)retryInstalling
{
    self.installRetryScheduled = NO;
    self.installRetriesFired = self.installRetriesFired + 1;
    [self tryInstalling];
}

// 0x6238
- (void)prepareDustRenderer
{
    [NLDustRenderer prewarmRenderer];
}

// 0x624c
- (void)applicationDidBecomeActive:(NSNotification *)note
{
    NLLoadPreferences();
    [self prepareDustRenderer];
    [self tryInstalling];
}

// 0x6554
- (void)preferencesChanged:(NSNotification *)note
{
    NLLoadPreferences();
}

@end


#pragma mark - 构造入口

// 0x658c —— 由 %ctor 调用。只在 SpringBoard 进程里生效。
__attribute__((constructor))
static void NLSetup(void)
{
    @autoreleasepool {
        NSBundle *bundle = [NSBundle mainBundle];
        if (![bundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        NLLoadPreferences();

        NLNotificationHookLoader *loader = [NLNotificationHookLoader sharedLoader];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        [center addObserver:loader
                   selector:@selector(applicationDidBecomeActive:)
                       name:UIApplicationDidFinishLaunchingNotification
                     object:nil];
        [center addObserver:loader
                   selector:@selector(preferencesChanged:)
                       name:@"com.example.noticelisttweak/preferencesChanged"
                     object:nil];
        [center addObserver:loader
                   selector:@selector(applicationDidBecomeActive:)
                       name:UIApplicationDidBecomeActiveNotification
                     object:nil];

        [loader tryInstalling];
        [loader performSelector:@selector(prepareDustRenderer) withObject:nil afterDelay:2.0];
    }
}
