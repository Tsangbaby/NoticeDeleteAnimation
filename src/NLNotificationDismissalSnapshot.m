//
//  NLNotificationDismissalSnapshot.m
//  NoticeDeleteAnimation 1.0.1~test14
//
//  Reverse-reconstructed implementation of the dismissal-snapshot object.
//  Recovered from work/listing.txt @0x46e8..0x57b8 and work/objcdump.txt.
//
//  Build notes: the original was ARC (weak ivars, objc_retainAutoreleasedReturnValue
//  everywhere, no manual dealloc). Compile this file with -fobjc-arc.
//

#import "NLNotificationDismissalSnapshot.h"
#import "NLRuntimeABI.h"

// Fixed phase counters only: distinguish a safe native fallback from success.
static NSUInteger NLListAttempts, NLListNoCard, NLListPrepared, NLListStarted;
NSDictionary *NLListSnapshotStatus(void) {
    if (![NSThread isMainThread]) return @{};
    return @{ @"attempts":@(NLListAttempts), @"noCard":@(NLListNoCard),
              @"prepared":@(NLListPrepared), @"started":@(NLListStarted) };
}

// A list accessor returns a row, including swipe actions. Only follow a known,
// ABI-checked, already-loaded controller relationship; never pick a subtree by
// size, colour or private class-name heuristics. Unknown layouts stay native.
static UIView *NLNotificationCardInRow(UIView *row, UIViewController **resolvedController)
{
    @try {
        for (NSString *key in @[@"contentViewController", @"notificationViewController",
                                @"_contentViewController", @"_notificationViewController"]) {
            id controller = NLABIReadObject(row, NSSelectorFromString(key));
            if (![controller isKindOfClass:[UIViewController class]]) continue;
            UIView *card = [(UIViewController *)controller viewIfLoaded];
            if (card && card != row && card.window == row.window &&
                [card isDescendantOfView:row] && !card.hidden && card.alpha >= 0.02) {
                if (resolvedController) *resolvedController = controller;
                return card;
            }
        }
    } @catch (NSException *exception) {
        return nil;
    }
    return nil;
}

static BOOL NLNotificationCardStillMatches(UIView *row, UIView *card, UIViewController *controller)
{
    UIViewController *current = nil;
    return NLNotificationCardInRow(row, &current) == card && current == controller;
}

// Reject shapes we cannot map without sampling concealed siblings. Translation
// and positive axis scales are safe; rotated/3-D/masked ancestor clips are not.
static CGRect NLNotificationVisibleRect(UIView *card, UIView *list, UIWindow *window)
{
    CGRect visible = CGRectIntersection([card convertRect:card.bounds toView:window],
        CGRectIntersection([list convertRect:list.bounds toView:window], window.bounds));
    UIView *node = card;
    for (NSUInteger depth = 0; node && depth < 64; ++depth, node = node.superview) {
        CGAffineTransform t = node.transform;
        if (node.hidden || node.alpha < 0.02 || !isfinite(t.a) || !isfinite(t.d) ||
            t.a <= 0 || t.d <= 0 || t.b != 0 || t.c != 0 ||
            !CATransform3DIsAffine(node.layer.transform) ||
            !CATransform3DIsIdentity(node.layer.sublayerTransform) || node.layer.mask)
            return CGRectNull;
        if (node != card && (node.clipsToBounds || node.layer.masksToBounds)) {
            if (node.layer.cornerRadius != 0) return CGRectNull;
            visible = CGRectIntersection(visible, [node convertRect:node.bounds toView:window]);
        }
        if (node == window) return visible;
    }
    return CGRectNull;
}

// A window composite is already flattened against its backdrop. Multiplying a
// translucent interior by its source alpha would apply opacity twice. Without
// mutating the live hierarchy there is no general inverse composite: fail closed
// for such interiors, while keeping the original antialiased perimeter mask.
static BOOL NLNotificationOpaqueInterior(CGImageRef image)
{
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(image);
    CGBitmapInfo order = CGImageGetBitmapInfo(image) & kCGBitmapByteOrderMask;
    if (CGImageGetBitsPerPixel(image) != 32 ||
        !((order == kCGBitmapByteOrder32Little && alpha == kCGImageAlphaPremultipliedFirst) ||
          (order == kCGBitmapByteOrderDefault && alpha == kCGImageAlphaPremultipliedLast))) return NO;
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image));
    if (!data) return NO;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image), stride = CGImageGetBytesPerRow(image);
    const UInt8 *bytes = CFDataGetBytePtr(data);
    BOOL valid = width >= 3 && height >= 3 && stride >= width * 4 &&
        CFDataGetLength(data) >= (CFIndex)(stride * height);
    for (size_t y = 1; valid && y + 1 < height; ++y) {
        for (size_t x = 1; x + 1 < width; ++x) {
            UInt8 a = bytes[y * stride + x * 4 + 3];
            if (a == 0 || a == 255) continue;
            BOOL edge = NO;
            for (int dy = -1; dy <= 1; ++dy)
                for (int dx = -1; dx <= 1; ++dx)
                    if (bytes[(size_t)((NSInteger)y + dy) * stride + (size_t)((NSInteger)x + dx) * 4 + 3] == 0) edge = YES;
            if (!edge) { valid = NO; break; }
        }
    }
    CFRelease(data);
    return valid;
}

// Isolated UIVisualEffect/backdrop captures can contain an opaque grey fallback.
// Capture colour with the window's compositing context (cropped by the small
// bitmap), but retain the card-only alpha footprint, including rounded corners.
// No view properties are changed, no grey pixels are removed, and no wallpaper
// rectangle outside the original footprint is admitted into the texture.
static UIImage *NLNotificationCardImage(UIView *card, UIWindow *window,
                                       CGRect cardRect, CGRect visible)
{
    UIImage *mask = nil;
    UIGraphicsBeginImageContextWithOptions(visible.size, NO, 2.0);
    @try {
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (!context) return nil;
        CGContextTranslateCTM(context, cardRect.origin.x - visible.origin.x,
                              cardRect.origin.y - visible.origin.y);
        if (![card drawViewHierarchyInRect:(CGRect){CGPointZero, cardRect.size}
                        afterScreenUpdates:NO]) return nil;
        mask = UIGraphicsGetImageFromCurrentImageContext();
    } @catch (NSException *exception) {
        return nil;
    } @finally {
        UIGraphicsEndImageContext();
    }
    if (!mask.CGImage || !NLNotificationOpaqueInterior(mask.CGImage)) return nil;
    UIGraphicsBeginImageContextWithOptions(visible.size, NO, 2.0);
    @try {
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (!context) return nil;
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, -visible.origin.x, -visible.origin.y);
        BOOL drawn = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
        CGContextRestoreGState(context);
        if (!drawn) return nil;
        [mask drawInRect:(CGRect){CGPointZero, visible.size}
              blendMode:kCGBlendModeDestinationIn alpha:1.0];
        return UIGraphicsGetImageFromCurrentImageContext();
    } @catch (NSException *exception) {
        return nil;
    } @finally {
        UIGraphicsEndImageContext();
    }
}

// The tweak's own log prefix; every NSLog in this file uses it verbatim.
#define NL_LOG(fmt, ...) NSLog((@"[NoticeDeleteAnimation] " fmt), ##__VA_ARGS__)

// Associated-object key. A single byte is enough: only its *address* is used.
// 0x264c0
// NLDustSnapshotKey 定义在 NLPreferences.m

// Private UIKit accessor used to map a row index to the card view. Verified to
// exist by -[NLNotificationHookLoader tryInstalling] @0x5a00 (it checks
// -method_getNumberOfArguments == 3 and an '@' return type before hooking).
@interface UIView (NLPrivateRowAccess)
- (UIView *)_visibleViewAtIndex:(NSUInteger)index;
@end

@interface NLNotificationDismissalSnapshot ()
@property (nonatomic) CFTimeInterval frameDeadline;
@end

@implementation NLNotificationDismissalSnapshot

@synthesize counted           = _counted;
@synthesize cleanedUp         = _cleanedUp;
@synthesize dustRenderer      = _dustRenderer;
@synthesize effectDuration    = _effectDuration;
@synthesize reservedParticles = _reservedParticles;
@synthesize sourceView        = _sourceView;
@synthesize sourceList        = _sourceList;
@synthesize removalDeadline   = _removalDeadline;
@synthesize waitingForRemoval = _waitingForRemoval;
@synthesize animationStarted  = _animationStarted;

#pragma mark - Factory

// 0x46e8  +[NLNotificationDismissalSnapshot snapshotForList:notificationView:]
//
// Returns nil unless every precondition of the dust effect holds. The guard
// order matters: cheap checks first, then geometry, then the (expensive) Metal
// readiness probe, then the particle budget, and only then the render pass.
+ (instancetype)snapshotForList:(UIView *)list notificationView:(UIView *)view
{
    // --- gates that never touch the view hierarchy -------------------------
    if (![NSThread isMainThread])                                          // 0x4740
        return nil;
    NLListAttempts = MIN(1000000UL, NLListAttempts + 1);
    if (UIAccessibilityIsReduceMotionEnabled() || NLActiveSnapshots > 5)    // 0x4754
        return nil;
    if (![view isKindOfClass:[UIView class]])                              // 0x4770
        return nil;
    if (view.isHidden)                                                     // 0x479c
        return nil;
    if (view.alpha < 0.02)                                                 // 0x47b4 (0x195c0)
        return nil;
    if (NLLockScreenDustOwnsView(view))                                    // 0x47d4
        return nil;
    // Already has a live snapshot attached -> never stack two effects.
    if (objc_getAssociatedObject(view, &NLDustSnapshotKey) != nil)         // 0x47e0
        return nil;

    // Keep the row for de-duplication/removal semantics; capture only its card.
    UIView *sourceRow = view;
    UIViewController *capturedController = nil;
    view = NLNotificationCardInRow(sourceRow, &capturedController);
    if (!view) {
        NLListNoCard = MIN(1000000UL, NLListNoCard + 1);
        return nil;
    }
    if (!isfinite(NLAnimationDuration) || !isfinite(NLDustDistance))
        return nil;

    // --- the card must really be on screen, inside the same window --------
    UIWindow *window = view.window;                                        // 0x4850
    if (window == nil)
        return nil;
    if (list.window != window)                                             // 0x4874
        return nil;
    if (window.isHidden)                                                   // 0x48a0
        return nil;
    if (![view isDescendantOfView:list])                                   // 0x48c0
        return nil;

    // Intersect [view in window] with every clipping ancestor and the window.
    CGRect capturedWindowBounds = window.bounds;
    CGRect viewRect = [view convertRect:view.bounds toView:window];        // 0x48d4
    CGRect visible = NLNotificationVisibleRect(view, list, window);
    if (CGRectIsNull(visible))                                             // 0x49a0
        return nil;
    if (CGRectIsEmpty(visible))                                            // 0x49b8
        return nil;

    // Reject NaN / infinity explicitly; UIKit can hand back garbage rects
    // while the list is mid-layout.
    if (isnan(visible.origin.x) || isinf(visible.origin.x) ||
        isnan(visible.origin.y) || isinf(visible.origin.y) ||
        isnan(visible.size.width) || isinf(visible.size.width) ||
        isnan(visible.size.height) || isinf(visible.size.height))          // 0x49d4..0x4a4c
        return nil;

    if (visible.size.width < 16.0)                                          // 0x4a54
        return nil;
    if (visible.size.height < 12.0)                                         // 0x4a60
        return nil;

    // Backing-store budget: ceil(2*w) * ceil(2*h) must stay <= 1,200,000 px
    // (a 2x-scale context, i.e. ~400x300 @3x). 0x41324f8000000000 == 1200000.0
    if (ceil(visible.size.width  * 2.0) *
        ceil(visible.size.height * 2.0) > 1200000.0)                        // 0x4a6c..0x4a90
        return nil;

    // --- Metal renderer + particle budget ---------------------------------
    BOOL rendererReady = [NLDustRenderer isReady];                          // 0x4a94 (class ref 0x25e98)
    // Hard ceiling on the reserved-particle pool: (reserved >> 4) > 2624.
    // REVERIFY: the shift-by-4 form is odd; it is exactly what the binary does
    // (lsr x9, x8, #4 ; cmp x9, #0xa40), so it is kept rather than rewritten
    // as "reserved > 41984".
    if ((NLReservedParticles >> 4) > 2624)                                  // 0x4ab0
        return nil;
    if (!rendererReady)                                                     // 0x4ac0
        return nil;

    // Per-batch cap. Faithful to `sub x11, x9, #1 ; cmp x11, x10 ;
    // csel x9, x9, x10, lo`: a zero (unset) batch limit underflows and therefore
    // falls back to NLDustParticleLimit, as does anything above it.
    NSUInteger cap = NLBatchParticleLimit;
    if (cap == 0 || (cap - 1) >= NLDustParticleLimit)                       // 0x4ac8..0x4ae0
        cap = NLDustParticleLimit;

    // Then clamp by what is left of the 42,000-particle global pool.
    NSUInteger particleCount = MIN(cap, (NSUInteger)42000 - NLReservedParticles); // 0x4ae4..0x4af0
    if (particleCount < 3000)                                               // 0x4af4
        return nil;

    // --- rasterise the card ------------------------------------------------
    UIImage *image = NLNotificationCardImage(view, window, viewRect, visible);
    if (image == nil || image.CGImage == NULL ||
        !NLNotificationCardStillMatches(sourceRow, view, capturedController) || view.window != window ||
        list.window != window || !CGRectEqualToRect(window.bounds, capturedWindowBounds) ||
        ![sourceRow isDescendantOfView:list] ||
        !CGRectEqualToRect(viewRect, [view convertRect:view.bounds toView:window]) ||
        !CGRectEqualToRect(visible, NLNotificationVisibleRect(view, list, window)))
        return nil;

    // --- geometry of the particle field ------------------------------------
    // The renderer view is inflated by (distance * 2.2 + 10) on every side so
    // dust can fly outwards, then clipped to the window.
    CGFloat inflation = NLDustDistance * 2.2 + 10.0;                         // 0x4b90 (0x263b8, 0x195c8)
    CGRect cardFrame = CGRectInset(visible, -inflation, -inflation);          // 0x4bb0
    cardFrame = CGRectIntersection(cardFrame, window.bounds);                 // 0x4bd8
    // Renderer-local coordinates: the visible rect is offset by the frame origin.
    CGRect localRect = CGRectOffset(visible, -cardFrame.origin.x,
                                             -cardFrame.origin.y);            // 0x4c14

    NLDustRenderer *renderer =
        [[NLDustRenderer alloc] initWithImage:image.CGImage                       // 0x4c40
                                   cardFrame:localRect
                               particleCount:particleCount
                                    duration:NLAnimationDuration              // 1.3
                                    distance:NLDustDistance                   // 110.0
                                        seed:(float)arc4random_uniform(10000)]; // 0x4c6c
    if (renderer == nil)                                                       // 0x4cac
        return nil;

    NLNotificationDismissalSnapshot *snapshot =
        [[self alloc] initWithFrame:cardFrame];                                // 0x4cb0
    [snapshot setUserInteractionEnabled:NO];                                   // 0x4cd8
    [snapshot setAccessibilityElementsHidden:YES];                             // 0x4ce8
    [snapshot setIsAccessibilityElement:NO];                                   // 0x4cfc
    [snapshot setBackgroundColor:[UIColor clearColor]];                        // 0x4d10
    [snapshot setClipsToBounds:YES];                                           // 0x4d4c
    [snapshot setDustRenderer:renderer];                                       // 0x4d60
    [snapshot setEffectDuration:NLAnimationDuration];                          // 0x4d74
    [snapshot setReservedParticles:particleCount];                             // 0x4d8c
    renderer.frame = snapshot.bounds;                                          // 0x4d9c
    [snapshot addSubview:renderer];                                            // 0x4dbc
    [window addSubview:snapshot];                                              // 0x4dd0

    // Completion owns prompt overlay/accounting teardown, not a later watchdog.
    __weak NLNotificationDismissalSnapshot *weakSnapshot = snapshot;
    renderer.completion = ^{ [weakSnapshot cleanUp]; };
    BOOL primed = NO;
    @try { primed = [renderer primeFrame]; }
    @catch (NSException *exception) { primed = NO; }
    if (!primed || !NLNotificationCardStillMatches(sourceRow, view, capturedController) || view.window != window ||
        list.window != window || ![sourceRow isDescendantOfView:list] ||
        !CGRectEqualToRect(window.bounds, capturedWindowBounds) ||
        objc_getAssociatedObject(sourceRow, &NLDustSnapshotKey) != nil ||
        !CGRectEqualToRect(viewRect, [view convertRect:view.bounds toView:window]) ||
        !CGRectEqualToRect(visible, NLNotificationVisibleRect(view, list, window))) {
        [snapshot cleanUp];
        return nil;
    }

    // --- publish -----------------------------------------------------------
    [snapshot setSourceView:sourceRow];                                         // row, not content card
    [snapshot setSourceList:list];                                             // 0x4e0c (weak)
    objc_setAssociatedObject(sourceRow, &NLDustSnapshotKey, snapshot,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);               // 0x4e1c
    [snapshot setCounted:YES];                                                 // 0x4e38
    NLActiveSnapshots   += 1;                                                  // 0x4e48
    NLReservedParticles += particleCount;                                      // 0x4e54
    // Safety net: if nothing ever calls cleanUp, drop the overlay slightly
    // after the animation would have finished (1.3 + 0.3).
    [snapshot performSelector:@selector(cleanUp)
                   withObject:nil
                   afterDelay:NLAnimationDuration + 0.3];                      // 0x4e64..0x4e94
    NLListPrepared = MIN(1000000UL, NLListPrepared + 1);
    return snapshot;
}

#pragma mark - Animation

// 0x4fa4  -[NLNotificationDismissalSnapshot startRemovalAnimation]
- (void)startRemovalAnimation
{
    if (self.cleanedUp)                                                        // 0x4fbc
        return;
    if (self.superview == nil)                                                 // 0x4fcc
        return;
    if (!NLAnimationEnabled) {                                                 // 0x4fec (0x263c8)
        [self cleanUp];                                                        // 0x5018
        return;
    }
    if (self.animationStarted)                                                 // 0x4ffc
        return;
    // Submission is not first-frame completion. Do not start the dissolve clock
    // until the primed command has completed; a stuck GPU must fail closed.
    if ([self.dustRenderer hasFailedFrame]) {
        [self cleanUp];
        return;
    }
    if (![self.dustRenderer hasCompletedFrame]) {
        CFTimeInterval now = CACurrentMediaTime();
        if (self.frameDeadline == 0) self.frameDeadline = now + 0.35;
        if (now >= self.frameDeadline) { [self cleanUp]; return; }
        [NSObject cancelPreviousPerformRequestsWithTarget:self
            selector:@selector(startRemovalAnimation) object:nil];
        [self performSelector:@selector(startRemovalAnimation) withObject:nil afterDelay:0.016];
        return;
    }

    self.animationStarted  = YES;                                              // 0x5038
    NLListStarted = MIN(1000000UL, NLListStarted + 1);
    self.waitingForRemoval = NO;                                               // 0x504c
    self.hidden            = NO;                                               // 0x5060
    [self.dustRenderer start];                                                 // 0x5074
}

#pragma mark - Native-removal handshake

// 0x50c4  -[NLNotificationDismissalSnapshot waitForNativeRemoval]
//
// Called after the list has been told to remove the row: the real card is
// hidden, the snapshot is shown in its place, and we poll until the list has
// actually taken the row out of the hierarchy.
- (void)waitForNativeRemoval
{
    if (self.animationStarted)                                                 // 0x50dc
        return;

    self.waitingForRemoval = YES;                                              // 0x50f8
    self.hidden            = YES;                                              // 0x510c
    self.removalDeadline   = CACurrentMediaTime() + 0.35;                      // 0x511c (0x3fd6666666666666)

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(cleanUp)
                                               object:nil];                    // 0x5144
    [self performSelector:@selector(cleanUp)
                   withObject:nil
                   afterDelay:self.effectDuration + 0.8];                      // 0x516c (0x195d0)
    [self pollNativeRemoval];                                                  // 0x51a0
}

// 0x51b8  -[NLNotificationDismissalSnapshot pollNativeRemoval]
//
// One poll tick. Starts the effect as soon as the original card is gone (or
// faded out), and gives up when the deadline passes.
- (void)pollNativeRemoval
{
    if (self.cleanedUp)                                                        // 0x51d8
        return;

    UIView *view = self.sourceView;                                            // 0x51fc (weak -> strong)
    UIView *list = self.sourceList;                                            // 0x5218 (weak -> strong)

    if (view != nil && list != nil &&                                          // 0x5230
        [view isDescendantOfView:list]) {                                      // 0x5240
        UIWindow *window = view.window;                                        // 0x5258
        if (window != nil && !view.isHidden) {                                 // 0x5270, 0x5278
            CGFloat alpha = view.alpha;                                        // 0x52f0
            if (alpha >= 0.02) {                                               // 0x530c (0x195c0)
                CFTimeInterval now = CACurrentMediaTime();                      // 0x5318
                if (now < self.removalDeadline) {                               // 0x5324
                    [self performSelector:@selector(pollNativeRemoval)
                               withObject:nil
                               afterDelay:0.016];                              // 0x533c (0x195d8)
                    return;
                }
                // Deadline blown: tear the snapshot down instead of waiting
                // forever for a row that is never going to disappear.
                [self cleanUp];                                                // 0x5360
                return;
            }
        }
    }

    // The card is gone (or was never really on screen): play the effect now.
    self.waitingForRemoval = NO;                                               // 0x5294
    self.hidden            = NO;                                               // 0x52a8
    [self startRemovalAnimation];                                              // 0x52bc
}

// 0x53ac  -[NLNotificationDismissalSnapshot animationDidStop:finished:]
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished
{
    // Both arguments are ignored in the binary: any stop tears the effect down.
    [self cleanUp];
}

#pragma mark - Teardown

// 0x53cc  -[NLNotificationDismissalSnapshot cleanUp]
- (void)cleanUp
{
    if (self.cleanedUp)                                                        // 0x53e8
        return;
    self.cleanedUp = YES;                                                      // 0x5408
    self.hidden = YES;
    self.waitingForRemoval = NO;

    // Cancel every pending performSelector (the 1.6 s safety net and any
    // in-flight poll tick).
    [NSObject cancelPreviousPerformRequestsWithTarget:self];                   // 0x541c

    if (self.counted) {                                                        // 0x5434
        self.counted = NO;                                                     // 0x5448
        if (NLActiveSnapshots != 0)                                            // 0x545c
            NLActiveSnapshots -= 1;
        NSUInteger reserved = self.reservedParticles;                           // 0x5470
        if (reserved > NLReservedParticles)                                     // 0x5488
            NLReservedParticles = 0;   // defensive: never go negative
        else
            NLReservedParticles -= reserved;                                    // 0x5498
    }

    self.dustRenderer.completion = nil;
    [self.dustRenderer invalidate];                                             // 0x54b0
    self.dustRenderer = nil;                                                    // 0x54e0

    // Detach the associated object, but only if it is still *this* snapshot
    // (a newer snapshot may already have replaced us).
    UIView *view = self.sourceView;                                             // 0x54f4
    if (view != nil) {                                                          // 0x550c
        if (objc_getAssociatedObject(view, &NLDustSnapshotKey) == self)         // 0x5510
            objc_setAssociatedObject(view, &NLDustSnapshotKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);        // 0x5538
    }
    self.sourceView = nil;                                                      // 0x5554
    self.sourceList = nil;

    [self.layer removeAllAnimations];                                           // 0x5568
    [self removeFromSuperview];                                                 // 0x5598
}

@end
