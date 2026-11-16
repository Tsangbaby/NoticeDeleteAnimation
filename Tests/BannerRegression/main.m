// Real UIKit/runtime; production NLBannerDust.m is compiled as a separate TU.
// Effect/Metal/dependency doubles test ONLY resolver + native forwarding contracts.
#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import "NLBannerDust.h"
#import "NLWithdrawalEffect.h"
#import "NLDustRenderer.h"
#include <stdio.h>
#include <stdlib.h>
#if !TARGET_OS_SIMULATOR
#error BannerRegression requires an iOS Simulator, never a user device
#endif

static NSUInteger checks, hooks, prepares, natives, begins, cancels, idReads, scalarReads;
static BOOL island, eligible = YES, pending, nativeThrows, beginThrows;
static int prepareMode;
static id expectedPresentable, expectedReason, expectedInfo, capturedSource;
static UIView *capturedCard;
static NLWithdrawalEffect *lastEffect;
static NSException *nativeException;
static dispatch_block_t reenter;
static NSMutableArray *animatedHistory;
static NSMutableDictionary *events;
#define CHECK(x) do { ++checks; if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); } } while (0)

BOOL NLAnimationEnabled = YES;
void NLWithdrawalRecord(NSString *event) { events[event] = @([events[event] unsignedIntegerValue] + 1); }
BOOL NLIslandDustNativeCloseInProgress(void) { return island; }
NSDictionary *NLIslandDustStatus(void) { return @{}; }
NSDictionary *NLLockScreenDustStatus(void) { return @{}; }
NSDictionary *NLListSnapshotStatus(void) { return @{}; } // isolated fixed-state dependency
BOOL NLVisible(UIView *view) { return view.window && !view.window.hidden && !view.hidden; }
@implementation NLDustRenderer
+ (BOOL)isReady { return YES; } // NO Metal execution in this harness
@end
@implementation NLWithdrawalEffect
+ (BOOL)isPendingForOwner:(id)owner payload:(id)payload { return pending; }
+ (instancetype)prepareView:(UIView *)view source:(id)source preference:(NSString *)preference {
    ++prepares; capturedCard = view; capturedSource = source;
    CHECK([preference isEqual:@"BannerKit"]);
    if (reenter) { dispatch_block_t block = reenter; reenter = nil; block(); }
    if (prepareMode == 1) @throw [NSException exceptionWithName:@"Capture" reason:nil userInfo:nil];
    if (!eligible) return nil;
    lastEffect = [self new]; lastEffect.sourceView = view;
    return lastEffect;
}
+ (void)cancelEffectsForView:(UIView *)view { if (lastEffect.sourceView == view) [lastEffect cancel]; }
- (void)beginAfterNativeRemoval {
    ++begins; CHECK(natives > 0);
    if (beginThrows) @throw [NSException exceptionWithName:@"Finalize" reason:nil userInfo:nil];
}
- (void)cancel { ++cancels; self.finished = YES; }
@end
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    CHECK(method && original && !*original);
    *original = method_getImplementation(method);
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    ++hooks;
}

@interface FixtureRequest : NSObject
@end
@implementation FixtureRequest
- (id)notificationIdentifier { ++idReads; return @"same"; }
- (id)sectionIdentifier { ++idReads; return @"same"; }
@end
@interface FixtureHost : UIViewController
@property(nonatomic, strong) id notificationRequest;
@property(nonatomic) NSUInteger loads;
@end
@implementation FixtureHost
- (void)loadView { ++_loads; [super loadView]; }
@end
@interface FixtureWrapper : NSObject
@property(nonatomic, strong) id notificationRequest;
@property(nonatomic, strong) UIViewController *viewController;
@end
@implementation FixtureWrapper
@end
@interface FixtureScalar : NSObject
@end
@implementation FixtureScalar
- (NSUInteger)notificationRequest { ++scalarReads; return 0x12345678; }
- (NSUInteger)viewController { ++scalarReads; return 0x12345678; }
@end
@interface FixtureBN : UIViewController
@property(nonatomic, copy) NSArray *presentedPresentables;
- (void)_dismissPresentable:(id)object withReason:(id)reason animated:(BOOL)animated userInfo:(id)info;
- (void)presentPresentable:(id)object withOptions:(NSUInteger)options userInfo:(id)info;
- (void)_addPresentable:(id)object withTransitioningDelegate:(id)delegate incrementingTier:(BOOL)flag;
@end
@implementation FixtureBN
- (void)_dismissPresentable:(id)object withReason:(id)reason animated:(BOOL)animated userInfo:(id)info {
    ++natives; CHECK(object == expectedPresentable && reason == expectedReason && info == expectedInfo);
    [animatedHistory addObject:@(animated)];
    if (nativeThrows) @throw nativeException;
    self.presentedPresentables = @[];
}
- (void)presentPresentable:(id)object withOptions:(NSUInteger)options userInfo:(id)info {}
- (void)_addPresentable:(id)object withTransitioningDelegate:(id)delegate incrementingTier:(BOOL)flag {}
@end
static NSUInteger WrongDismiss(id object, SEL cmd, id presentable, id reason, BOOL animated, id info) { return 0; }
static Class Define(NSString *name, Class parent) {
    CHECK(!NSClassFromString(name)); // never replace actual private OS classes
    Class cls = objc_allocateClassPair(parent, name.UTF8String, 0);
    CHECK(cls != Nil); objc_registerClassPair(cls); return cls;
}
static void Reset(id presentable) {
    prepares = natives = begins = cancels = 0; capturedSource = nil; capturedCard = nil;
    lastEffect = nil; eligible = YES; pending = island = nativeThrows = beginThrows = NO;
    prepareMode = 0; reenter = nil; animatedHistory = [NSMutableArray array];
    expectedPresentable = presentable; expectedReason = @"arbitrary-click-reason";
    expectedInfo = [NSObject new];
}
static void Dismiss(FixtureBN *bn, BOOL animated) {
    bn.presentedPresentables = expectedPresentable ? @[expectedPresentable] : @[];
    [bn _dismissPresentable:expectedPresentable withReason:expectedReason animated:animated userInfo:expectedInfo];
}
static void NativeOnly(FixtureBN *bn, BOOL animated) {
    Dismiss(bn, animated);
    CHECK(natives == 1 && prepares == 0 && begins == 0);
    CHECK([animatedHistory isEqual:@[@(animated)]]);
}
static void Success(FixtureBN *bn, UIView *card, id request, BOOL animated) {
    Dismiss(bn, animated);
    CHECK(natives == 1 && prepares == 1 && begins == 1 && cancels == 0);
    CHECK(capturedSource == request && capturedCard == card);
    CHECK(lastEffect.owner == bn && lastEffect.payload == expectedPresentable);
    CHECK(lastEffect.requiresRemovalConfirmation && lastEffect.disposition);
    CHECK(lastEffect.disposition(lastEffect) == NLDispositionProceed);
    bn.presentedPresentables = @[expectedPresentable];
    CHECK(lastEffect.disposition(lastEffect) == NLDispositionPending);
    CHECK([animatedHistory isEqual:@[@NO]]);
}

static void Run(FixtureBN *bn, FixtureHost *host, UIView *card, Class requestClass) {
    id a = [requestClass new], b = [requestClass new];
    host.notificationRequest = a;
    FixtureWrapper *wrapper = [FixtureWrapper new]; wrapper.notificationRequest = a; wrapper.viewController = host;
    Reset(wrapper); Success(bn, card, a, YES);
    Reset(wrapper); Success(bn, card, a, NO); // never force YES for a native NO
    Reset(wrapper); expectedReason = [NSObject new]; expectedInfo = nil; Success(bn, card, a, YES);
    Reset(wrapper); expectedReason = nil; Success(bn, card, a, NO);
    Reset(a); Success(bn, card, a, YES); // direct request has NO viewController
    wrapper.notificationRequest = nil;
    Reset(wrapper); Success(bn, card, a, YES); // controller-owned request
    wrapper.notificationRequest = b;
    Reset(wrapper); NativeOnly(bn, YES); // identical identifiers do NOT establish ownership
    wrapper.notificationRequest = @"not a request";
    Reset(wrapper); NativeOnly(bn, YES);
    wrapper.notificationRequest = wrapper;
    Reset(wrapper); NativeOnly(bn, YES); // cycle
    wrapper.notificationRequest = a;
    FixtureWrapper *chain = wrapper;
    for (int i = 0; i < 6; ++i) { FixtureWrapper *next = [FixtureWrapper new]; next.notificationRequest = chain; chain = next; }
    Reset(chain); NativeOnly(bn, YES); // bounded recursion
    Reset([FixtureScalar new]); NativeOnly(bn, YES); CHECK(scalarReads == 0);
    Reset(nil); NativeOnly(bn, NO);

    FixtureHost *unloaded = [FixtureHost new]; unloaded.notificationRequest = a;
    wrapper.viewController = unloaded;
    // Make BN's loaded host unrelated: no loadView side effect is allowed.
    host.notificationRequest = b;
    Reset(wrapper); NativeOnly(bn, YES); CHECK(unloaded.loads == 0 && !unloaded.isViewLoaded);
    wrapper.viewController = host; host.notificationRequest = a;
    UIView *root = host.view;
    for (int mode = 0; mode < 5; ++mode) {
        CGRect saved = card.frame;
        if (mode == 0) card.hidden = YES;
        if (mode == 1) root.alpha = 0;
        if (mode == 2) card.frame = CGRectOffset(saved, 0, 10000);
        if (mode == 3) card.frame = root.bounds; // even known card class cannot be fullscreen
        if (mode == 4) [card removeFromSuperview]; // generic visible root must not be captured
        Reset(wrapper); NativeOnly(bn, YES);
        card.hidden = NO; root.alpha = 1; card.frame = saved;
        if (!card.superview) [root addSubview:card];
    }
    FixtureHost *other = [FixtureHost new]; other.notificationRequest = b;
    [host addChildViewController:other]; other.view.frame = root.bounds;
    [root addSubview:other.view]; [other didMoveToParentViewController:host];
    [other.view addSubview:card];
    Reset(wrapper); NativeOnly(bn, YES); // do not descend into another request's card
    [root addSubview:card]; [other.view removeFromSuperview]; [other removeFromParentViewController];

    UIViewController *multi = [UIViewController new];
    FixtureHost *one = [FixtureHost new], *two = [FixtureHost new];
    one.notificationRequest = a; two.notificationRequest = b;
    [multi addChildViewController:one]; [multi addChildViewController:two];
    FixtureWrapper *ambiguous = [FixtureWrapper new]; ambiguous.viewController = multi;
    Reset(ambiguous); NativeOnly(bn, YES);
    for (int flag = 0; flag < 2; ++flag) {
        Reset(wrapper); eligible = NO; Dismiss(bn, flag);
        CHECK(prepares == 1 && natives == 1 && begins == 0);
        CHECK([animatedHistory isEqual:@[@(flag != 0)]]); // prepare nil preserves both flags
        Reset(wrapper); island = YES; NativeOnly(bn, flag);
        Reset(wrapper);
        dispatch_sync(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ NativeOnly(bn, flag); });
    }
    Reset(wrapper); pending = YES; NativeOnly(bn, YES);
    Reset(wrapper); prepareMode = 1; Dismiss(bn, YES);
    CHECK(natives == 1 && prepares == 1 && begins == 0 && [animatedHistory isEqual:@[@YES]]);
    Reset(wrapper); nativeThrows = YES;
    nativeException = [NSException exceptionWithName:@"Native" reason:nil userInfo:nil];
    BOOL caught = NO;
    @try { Dismiss(bn, YES); } @catch (NSException *exception) { caught = exception == nativeException; }
    CHECK(caught && natives == 1 && begins == 0 && cancels == 1);
    Reset(wrapper); beginThrows = YES; Dismiss(bn, YES);
    CHECK(natives == 1 && begins == 1 && cancels == 1);
    Reset(wrapper);
    reenter = ^{ Dismiss(bn, YES); };
    Dismiss(bn, YES);
    CHECK(natives == 2 && prepares == 1 && begins == 1);
    CHECK(([animatedHistory isEqual:@[@YES, @NO]]));
    Reset(wrapper); Success(bn, card, a, YES); // guard restored after every exceptional path
    CHECK(idReads == 0 && scalarReads == 0);
    for (NSString *key in @[@"requestresolved", @"no_request", @"nohost", @"capturefail", @"clickpathunknown"]) {
        CHECK([events[key] unsignedIntegerValue] > 0);
    }
    CHECK(hooks == 3 && NLInstallBannerDustHooks() && hooks == 3);
    printf("BANNER NATIVE PASS: %lu checks (fake effect; no Metal/Substrate/private SpringBoard/click routing)\n", (unsigned long)checks);
    fflush(stdout); exit(0);
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    events = [NSMutableDictionary dictionary];
    CHECK(!NLInstallBannerDustHooks()); // class absent
    Class requestClass = Define(@"NCNotificationRequest", [FixtureRequest class]);
    Class cardClass = Define(@"NCNotificationShortLookView", [UIView class]);
    SEL dismiss = @selector(_dismissPresentable:withReason:animated:userInfo:);
    Class invalidBase = Define(@"FixtureBNWrongAccessorBase", [FixtureBN class]);
    CHECK(class_addMethod(invalidBase, dismiss, (IMP)WrongDismiss, "Q@:@@B@"));
    Class bnClass = Define(@"BNContentViewController", invalidBase);
    CHECK(!NLInstallBannerDustHooks() && hooks == 2); // present/add alone are not installed
    Method original = class_getInstanceMethod([FixtureBN class], dismiss);
    // Add a correctly typed local override. Replacing an existing local method
    // changes its IMP, not its old type encoding, and would be an invalid control.
    CHECK(class_replaceMethod(bnClass, dismiss, method_getImplementation(original), method_getTypeEncoding(original)) == NULL);
    CHECK(NLInstallBannerDustHooks() && hooks == 3);
    CHECK(NLInstallBannerDustHooks() && hooks == 3); // partial repair must not re-hook present/add
    FixtureBN *bn = [bnClass new];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = bn;
    FixtureHost *host = [FixtureHost new];
    [bn addChildViewController:host]; host.view.frame = bn.view.bounds;
    [bn.view addSubview:host.view]; [host didMoveToParentViewController:bn];
    UIView *card = [[cardClass alloc] initWithFrame:CGRectMake(0, 70, 390, 80)];
    card.backgroundColor = UIColor.redColor; [host.view addSubview:card];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            CHECK(!self.window.hidden && card.window == self.window);
            Run(bn, host, card, requestClass);
        } @catch (NSException *exception) {
            fprintf(stderr, "FAIL uncaught fixture exception: %s\n", exception.name.UTF8String); exit(1);
        }
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class])); }
}
