#import "TestBridge.h"
#import "substrate.h"
#import <QuartzCore/QuartzCore.h>
#import <stdio.h>
#import <stdlib.h>

static NSUInteger hookCount;
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || !original) abort();
    *original = method_getImplementation(method);
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    ++hookCount;
}
NSUInteger NDATestHookCount(void) { return hookCount; }

// A unique installed UIKit host cannot register itself as a system application.
// Adapt ONLY this process's main-bundle getter after normal app launch. This is
// an explicit test dependency in addition to the runtime hook shim, not a claim
// that the host is SpringBoard or that Substrate/private integration was tested.
static BOOL testSpringBoardIdentity;
static IMP realBundleIdentifier;
static NSString *TestBundleIdentifier(id self, SEL cmd) {
    if (testSpringBoardIdentity && self == NSBundle.mainBundle) return @"com.apple.springboard";
    return ((NSString *(*)(id, SEL))realBundleIdentifier)(self, cmd);
}
void NDATestUseSpringBoardIdentity(BOOL enabled) {
    if (!realBundleIdentifier) {
        Class cls = object_getClass(NSBundle.mainBundle);
        Method m = class_getInstanceMethod(cls, @selector(bundleIdentifier));
        if (!m) abort();
        realBundleIdentifier = method_getImplementation(m);
        class_replaceMethod(cls, @selector(bundleIdentifier), (IMP)TestBundleIdentifier, method_getTypeEncoding(m));
    }
    testSpringBoardIdentity = enabled;
}

// Synthetic names/ABIs that the UNMODIFIED production installer discovers.
// These are not private SpringBoard implementations or actual notifications.
@class NCNotificationGroupList, NCNotificationStructuredListViewController;
@interface NDATestController : UIViewController
@property(nonatomic, strong) id notificationRequest;
@end
@implementation NDATestController
@end
@interface NDATestCell : UIView
@property(nonatomic, strong) NDATestController *notificationViewController;
@end
@implementation NDATestCell
@end
@interface NCNotificationListView : UIScrollView
@property(nonatomic, weak) NDATestFixture *fixture;
- (UIView *)_visibleViewAtIndex:(NSUInteger)index;
- (void)removeViewAtIndex:(NSUInteger)index animated:(BOOL)animated;
- (void)removeViewAtIndex:(NSUInteger)index animated:(BOOL)animated isHorizontallyDisplaced:(BOOL)displaced;
@end
@interface NCNotificationGroupList : NSObject
@property(nonatomic, weak) NDATestFixture *fixture;
- (void)removeNotificationRequest:(id)request;
@end
@interface NCNotificationStructuredListViewController : UIViewController
@property(nonatomic, weak) NDATestFixture *fixture;
- (void)removeNotificationRequest:(id)request;
@end
@interface NDATestFixture ()
@property(nonatomic, strong, readwrite) UIWindow *window;
@property(nonatomic, strong, readwrite) UIView *host;
@property(nonatomic, strong, readwrite) UIScrollView *list;
@property(nonatomic, strong, readwrite) UIView *cell;
@property(nonatomic, strong, readwrite, nullable) UIView *source;
@property(nonatomic, readwrite) NSUInteger draws;
@property(nonatomic, strong) id request;
@property(nonatomic, strong) NDATestController *controller;
@property(nonatomic, strong) NCNotificationGroupList *group;
@property(nonatomic, strong) NCNotificationStructuredListViewController *top;
@property(nonatomic) BOOL three, nested, animated, displaced, mutateDraw;
@property(nonatomic) NSUInteger index;
@property(nonatomic) NDATestAction action;
@property(nonatomic, copy) void (^onDraw)(void);
@end
@implementation NDATestFixture
- (void)dealloc { _window.hidden = YES; }
@end

@interface NDATestPattern : UIView
@property(nonatomic, weak) NDATestFixture *fixture;
@end
@implementation NDATestPattern
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGRect b = self.bounds;
    [UIColor.redColor setFill]; UIRectFill(b);
    [UIColor.greenColor setFill];
    UIRectFill(CGRectMake(b.origin.x + 183, b.origin.y, b.size.width - 183, b.size.height));
}
- (BOOL)drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)updates {
    self.fixture.draws += 1;
    BOOL result = [super drawViewHierarchyInRect:rect afterScreenUpdates:updates];
    if (self.fixture.mutateDraw) self.bounds = CGRectOffset(self.bounds, 1, 0);
    if (self.fixture.onDraw) self.fixture.onDraw();
    return result;
}
@end

static void Remove(NDATestFixture *f) {
    switch (f.action) {
        case NDATestActionKeepAttached: return;
        case NDATestActionReparentSource: [f.host addSubview:f.source]; return;
        case NDATestActionThrowOriginal:
            f->trace.didThrow = YES;
            @throw [NSException exceptionWithName:@"NDATestOriginal" reason:nil userInfo:nil];
        default: break;
    }
    if (f.action == NDATestActionRemoveSource) [f.source removeFromSuperview];
    else [f.cell removeFromSuperview];
    if (f.action == NDATestActionSurfaceBounds) f.list.bounds = CGRectOffset(f.list.bounds, 0, 1);
    if (f.action == NDATestActionAncestorBounds) f.host.bounds = CGRectOffset(f.host.bounds, 1, 0);
    if (f.action == NDATestActionReparentSurface) {
        UIView *newParent = [[UIView alloc] initWithFrame:f.host.bounds];
        [f.host addSubview:newParent]; [newParent addSubview:f.list];
    }
}
@implementation NCNotificationListView
- (UIView *)_visibleViewAtIndex:(NSUInteger)index {
    NDATestFixture *f = self.fixture;
    ++f->trace.getters; f->trace.getterIndex = index;
    return f.cell;
}
- (void)removeViewAtIndex:(NSUInteger)index animated:(BOOL)animated {
    NDATestFixture *f = self.fixture;
    ++f->trace.two; f->trace.index2 = index; f->trace.animated2 = animated;
    Remove(f);
}
- (void)removeViewAtIndex:(NSUInteger)index animated:(BOOL)animated isHorizontallyDisplaced:(BOOL)displaced {
    NDATestFixture *f = self.fixture;
    ++f->trace.three; f->trace.index3 = index;
    f->trace.animated3 = animated; f->trace.displaced = displaced;
    if (f.nested) [self removeViewAtIndex:index animated:animated];
    else Remove(f);
}
@end
@implementation NCNotificationGroupList
- (void)removeNotificationRequest:(id)request {
    NDATestFixture *f = self.fixture;
    ++f->trace.group; f->trace.identities &= (request == f.request);
    NCNotificationListView *list = (NCNotificationListView *)f.list;
    if (f.three) [list removeViewAtIndex:f.index animated:f.animated isHorizontallyDisplaced:f.displaced];
    else [list removeViewAtIndex:f.index animated:f.animated];
}
@end
@implementation NCNotificationStructuredListViewController
- (void)removeNotificationRequest:(id)request {
    NDATestFixture *f = self.fixture;
    ++f->trace.top; f->trace.identities &= (request == f.request);
    [f.group removeNotificationRequest:request];
}
@end

NDATestFixture *NDATestMakeFixture(void) {
    NDATestFixture *f = [NDATestFixture new];
    CGRect viewport = CGRectMake(0, 0, 390, 844);
    f.window = [[UIWindow alloc] initWithFrame:viewport];
    f.host = [[UIView alloc] initWithFrame:viewport];
    UIViewController *root = [UIViewController new]; root.view = f.host;
    f.window.rootViewController = root;
    NCNotificationListView *list = [[NCNotificationListView alloc] initWithFrame:viewport];
    list.fixture = f; list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    list.contentSize = viewport.size; f.list = list; [f.host addSubview:list];
    f.request = [NSObject new]; f.controller = [NDATestController new];
    f.controller.notificationRequest = f.request;
    NDATestCell *cell = [[NDATestCell alloc] initWithFrame:viewport];
    cell.notificationViewController = f.controller; f.cell = cell; [list addSubview:cell];
    NDATestPattern *source = [[NDATestPattern alloc] initWithFrame:CGRectMake(-183, 521, 370, 80)];
    source.fixture = f; source.opaque = YES; source.contentMode = UIViewContentModeRedraw;
    f.source = source; f.controller.view = source; [cell addSubview:source];
    f.top = [NCNotificationStructuredListViewController new]; f.top.fixture = f;
    f.group = [NCNotificationGroupList new]; f.group.fixture = f;
    [f.window makeKeyAndVisible];
    return f;
}
void NDATestSettle(NDATestFixture *f) {
    [f.source setNeedsDisplay]; [f.window layoutIfNeeded]; [CATransaction flush];
    // Let the real constructor's async NDASwiftStart run; never replace it.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
}
BOOL NDATestInvoke(NDATestFixture *f, BOOL three, BOOL nested, NDATestAction action,
                   BOOL animated, BOOL displaced, NSUInteger index) {
    f->trace = (NDATestTrace){ .identities = YES };
    f.three = three; f.nested = nested; f.action = action;
    f.animated = animated; f.displaced = displaced; f.index = index;
    @try { [f.top removeNotificationRequest:f.request]; return NO; }
    @catch (NSException *exception) {
        if (![exception.name isEqualToString:@"NDATestOriginal"]) abort();
        return YES;
    }
}
void NDATestUnscoped(NDATestFixture *f, NSUInteger index, BOOL animated, BOOL displaced) {
    f->trace = (NDATestTrace){0}; f.action = NDATestActionRemoveCell;
    [(NCNotificationListView *)f.list removeViewAtIndex:index animated:animated isHorizontallyDisplaced:displaced];
}
NDATestTrace NDATestReadTrace(NDATestFixture *f) { return f->trace; }
void NDATestMismatchRequest(NDATestFixture *f) { f.controller.notificationRequest = [NSObject new]; }
void NDATestMutateDuringDraw(NDATestFixture *f) { f.mutateDraw = YES; }
void NDATestOnDraw(NDATestFixture *f, void (^callback)(void)) { f.onDraw = callback; }
void NDATestForgetSource(NDATestFixture *f) {
    [f.source removeFromSuperview]; f.controller.view = nil;
    ((NDATestCell *)f.cell).notificationViewController = nil; f.source = nil;
}
CGSize NDATestBackingSize(CALayer *tile) {
    CGImageRef image = (__bridge CGImageRef)tile.contents;
    return image ? CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image)) : CGSizeZero;
}
BOOL NDATestNoHiddenRed(CALayer *tile) {
    CGImageRef image = (__bridge CGImageRef)tile.contents;
    if (!image) return NO;
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    if (!w || !h || w > 4096 || h > 4096 || w * h > 220000) return NO;
    uint8_t *p = calloc(w * h, 4); if (!p) return NO;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(p, w, h, 8, w * 4, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!c) { free(p); return NO; }
    CGContextDrawImage(c, CGRectMake(0, 0, w, h), image); CGContextRelease(c);
    BOOL ok = YES;
    for (size_t i = 0; i < w * h; ++i)
        if (p[i*4] > 10 || p[i*4+1] < 245 || p[i*4+2] > 10 || p[i*4+3] < 245) { ok = NO; break; }
    free(p); return ok;
}
