// Native UIKit regression: compiles and calls the production renderer directly.
#import "NDABridge.h"
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <stdint.h>
#import <stdbool.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

// Keep this test independently buildable while the bridge declaration is merged.
extern UIImage * _Nullable NDACaptureRegion(UIView *view, CGRect region, CGFloat scale);

static NSUInteger checks;
static void Require(BOOL ok, const char *name) {
    if (!ok) { fprintf(stderr, "FAIL capture-native: %s\n", name); exit(1); }
    ++checks;
}

@interface NDAPatternView : UIView
@property(nonatomic) NSUInteger hierarchyCalls;
@property(nonatomic) NSUInteger boundsReads;
@property(nonatomic) NSInteger failureMode; // 1: draw failure, 2: draw exception
@property(nonatomic) BOOL throwBounds;
@property(nonatomic) BOOL supplyBounds;
@property(nonatomic) CGRect suppliedBounds;
@property(nonatomic) CGFloat redEdge;
@end
@implementation NDAPatternView
- (CGRect)bounds {
    ++_boundsReads;
    if (_throwBounds) @throw [NSException exceptionWithName:@"NDATestBounds" reason:nil userInfo:nil];
    return _supplyBounds ? _suppliedBounds : [super bounds];
}
- (void)drawRect:(CGRect)dirty {
    (void)dirty;
    CGRect b = self.bounds;
    CGContextRef c = UIGraphicsGetCurrentContext();
    // Source-local, not frame/window coordinates. Hidden left 183pt is red;
    // visible right has green/blue quadrants and an asymmetric stripe boundary.
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, b);
    CGFloat middle = b.origin.y + b.size.height / 2;
    CGFloat edge = self.redEdge;
    CGContextSetRGBFillColor(c, 0, 1, 0, 1);
    CGContextFillRect(c, CGRectMake(b.origin.x + edge, b.origin.y, 276 - edge, b.size.height / 2));
    CGContextFillRect(c, CGRectMake(b.origin.x + 276, middle, b.size.width - 276, b.size.height / 2));
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, CGRectMake(b.origin.x + 276, b.origin.y, b.size.width - 276, b.size.height / 2));
    CGContextFillRect(c, CGRectMake(b.origin.x + edge, middle, 276 - edge, b.size.height / 2));
}
- (BOOL)drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)updates {
    ++_hierarchyCalls;
    if (_failureMode == 1) return NO;
    if (_failureMode == 2) @throw [NSException exceptionWithName:@"NDATestDraw" reason:nil userInfo:nil];
    return [super drawViewHierarchyInRect:rect afterScreenUpdates:updates];
}
@end

// Capture all properties the renderer must not write, on every fixture ancestor.
@interface NDAViewState : NSObject
@property(nonatomic, strong) UIView *view;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGRect frame;
@property(nonatomic) CGPoint center;
@property(nonatomic) CGAffineTransform transform;
@property(nonatomic) CATransform3D layerTransform;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL clips;
@property(nonatomic, strong) UIView *parent;
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, copy) NSArray<UIView *> *children;
+ (instancetype)take:(UIView *)view;
- (BOOL)unchanged;
@end
@implementation NDAViewState
+ (instancetype)take:(UIView *)view {
    NDAViewState *s = [self new];
    s.view = view; s.bounds = view.bounds; s.frame = view.frame; s.center = view.center;
    s.transform = view.transform; s.layerTransform = view.layer.transform;
    s.alpha = view.alpha; s.hidden = view.hidden; s.clips = view.clipsToBounds;
    s.parent = view.superview; s.window = view.window; s.children = [view.subviews copy];
    return s;
}
- (BOOL)unchanged {
    UIView *v = self.view;
    return CGRectEqualToRect(v.bounds, self.bounds) && CGRectEqualToRect(v.frame, self.frame) &&
        CGPointEqualToPoint(v.center, self.center) && CGAffineTransformEqualToTransform(v.transform, self.transform) &&
        CATransform3DEqualToTransform(v.layer.transform, self.layerTransform) && v.alpha == self.alpha &&
        v.hidden == self.hidden && v.clipsToBounds == self.clips && v.superview == self.parent &&
        v.window == self.window && [v.subviews isEqualToArray:self.children];
}
@end

static NSArray<NDAViewState *> *States(NSArray<UIView *> *views) {
    NSMutableArray<NDAViewState *> *states = [NSMutableArray array];
    for (UIView *v in views) [states addObject:[NDAViewState take:v]];
    return states;
}
static void CheckStates(NSArray<NDAViewState *> *states) {
    for (NDAViewState *s in states) Require(s.unchanged, "no source/ancestor geometry, appearance or hierarchy mutation");
}
static UIImage *Capture(UIView *view, CGRect region, CGFloat scale, NSArray<UIView *> *chain) {
    NSArray<NDAViewState *> *states = States(chain);
    UIImage *image = NDACaptureRegion(view, region, scale);
    CheckStates(states);
    return image;
}

// Normalize the CGImage into known RGBA8 bytes in memory only. No image files,
// UIKit mocks, private views, personal content, arbitrary text or network I/O.
static uint8_t *RGBA(CGImageRef image) {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    Require(w > 0 && h > 0 && w <= 4096 && h <= 4096 && w * h <= 220000, "bounded readback");
    uint8_t *bytes = calloc(w * h, 4);
    Require(bytes != NULL, "readback allocation");
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(bytes, w, h, 8, w * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    Require(c != NULL, "RGBA8 context");
    CGContextSetBlendMode(c, kCGBlendModeCopy);
    CGContextDrawImage(c, CGRectMake(0, 0, w, h), image);
    CGContextRelease(c);
    return bytes;
}

static void CheckReadbackOrientation(void) {
    // Independent raw 2x2 top-row red/green, bottom-row blue/white proves the
    // readback's row/channel convention before checking production snapshots.
    const uint8_t sample[] = {255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,255,255};
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, sample, sizeof(sample), NULL);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(2, 2, 8, 32, 8, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider, NULL, false, kCGRenderingIntentDefault);
    Require(image != NULL, "readback control image");
    uint8_t *actual = RGBA(image);
    Require(memcmp(actual, sample, sizeof(sample)) == 0, "readback top/bottom and RGBA channels verified");
    free(actual); CGImageRelease(image); CGColorSpaceRelease(space); CGDataProviderRelease(provider);
}

static void VerifyPattern(UIImage *image, CGRect region, CGRect bounds, CGFloat scale, BOOL noRed, CGFloat redEdge) {
    Require(image != nil && image.CGImage != NULL, "production snapshot exists");
    size_t w = (size_t)(region.size.width * scale), h = (size_t)(region.size.height * scale);
    Require(CGImageGetWidth(image.CGImage) == w && CGImageGetHeight(image.CGImage) == h,
        "CGImage dimensions equal crop, not source/parent/screen");
    Require(image.scale == scale && image.imageOrientation == UIImageOrientationUp, "scale and orientation");
    uint8_t *pixels = RGBA(image.CGImage);
    size_t reds = 0, greens = 0, blues = 0, expectedRed = 0, mismatches = 0;
    size_t topMatches = 0, bottomMatches = 0, cornerMatches = 0;
    uint8_t maximumRed = 0;
    for (size_t y = 0; y < h; ++y) {
        for (size_t x = 0; x < w; ++x) {
            CGFloat localX = region.origin.x - bounds.origin.x + ((CGFloat)x + 0.5) / scale;
            CGFloat localY = region.origin.y - bounds.origin.y + ((CGFloat)y + 0.5) / scale;
            int color = localX < redEdge ? 0 : ((localX < 276) == (localY < bounds.size.height / 2) ? 1 : 2);
            const uint8_t *p = pixels + (y * w + x) * 4;
            if (p[0] > maximumRed) maximumRed = p[0];
            BOOL red = p[0] >= 235 && p[1] <= 20 && p[2] <= 20 && p[3] >= 245;
            BOOL green = p[0] <= 20 && p[1] >= 235 && p[2] <= 20 && p[3] >= 245;
            BOOL blue = p[0] <= 20 && p[1] <= 20 && p[2] >= 235 && p[3] >= 245;
            reds += red; greens += green; blues += blue; expectedRed += color == 0;
            BOOL matches = color == 0 ? red : (color == 1 ? green : blue);
            mismatches += !matches;
            if (!matches && mismatches <= 8) {
                fprintf(stdout, "PIXEL mismatch x=%zu y=%zu expected=%d rgba=%u,%u,%u,%u source_local=%.4f,%.4f\n",
                    x, y, color, p[0], p[1], p[2], p[3], (double)localX, (double)localY);
            }
            if (y == 0) topMatches += matches;
            if (y == h - 1) bottomMatches += matches;
            if ((x == 0 || x == w - 1) && (y == 0 || y == h - 1)) cornerMatches += matches;
        }
    }
    fprintf(stdout, "PIXEL crop=%.4f,%.4f,%.4f,%.4f bounds=%.4f,%.4f scale=%.4f pixels=%zux%zu mismatch=%zu colors=%zu,%zu,%zu maxred=%u\n",
        (double)region.origin.x, (double)region.origin.y, (double)region.size.width, (double)region.size.height,
        (double)bounds.origin.x, (double)bounds.origin.y, (double)scale, w, h, mismatches, reds, greens, blues, maximumRed);
    fflush(stdout);
    free(pixels);
    Require(mismatches == 0, "all pixels match independently computed source-local pattern");
    Require(topMatches == w && bottomMatches == w && cornerMatches == 4, "first/last rows and all four corners");
    Require(reds == expectedRed && reds + greens + blues == w * h, "actual color counts, no transparent/foreign pixels");
    if (noRed) {
        Require(reds == 0 && greens > 0 && blues > 0, "no hidden red pixels anywhere in crop");
        Require(maximumRed == 0, "no high-contrast hidden-edge red bleed, including mixed pixels");
    }
}

static void Verify(UIImage *image, CGRect region, CGRect bounds, CGFloat scale, BOOL noRed) {
    VerifyPattern(image, region, bounds, scale, noRed, 183);
}

static void Settle(UIView *source) {
    [source setNeedsDisplay];
    [source.window layoutIfNeeded];
    [CATransaction flush];
    // Exercise a genuinely visible hierarchy through the main run loop; do not
    // treat an off-window black snapshot as success or use layer.render fallback.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.06]];
}

static void Reject(NDAPatternView *source, CGRect rect, CGFloat scale, NSArray<UIView *> *chain) {
    NSUInteger calls = source.hierarchyCalls;
    Require(Capture(source, rect, scale, chain) == nil, "invalid input fails closed");
    Require(source.hierarchyCalls == calls, "invalid input rejected before draw/allocation");
}

static void RunCaptureTests(UIWindow *window) {
    Require(NSThread.isMainThread && !window.hidden, "real UIKit main-thread visible window");
    CheckReadbackOrientation();
    UIView *root = window.rootViewController.view;
    root.backgroundColor = UIColor.blackColor;
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(20, 60, 187, 80)];
    wrapper.backgroundColor = UIColor.magentaColor;
    wrapper.clipsToBounds = YES;
    NDAPatternView *source = [[NDAPatternView alloc] initWithFrame:CGRectMake(-183, 0, 370, 80)];
    source.redEdge = 183;
    source.contentMode = UIViewContentModeRedraw;
    source.backgroundColor = UIColor.clearColor;
    [root addSubview:wrapper]; [wrapper addSubview:source];
    NSArray<UIView *> *chain = @[source, wrapper, root, window];
    Settle(source);
    CGRect b = source.bounds;
    CGRect observed = CGRectMake(183, 0, 187, 80);
    Verify(Capture(source, observed, 1, chain), observed, b, 1, YES);
    Verify(Capture(source, observed, 2, chain), observed, b, 2, YES);

    // Full wrapper compatibility also proves a snapshot is not the clipped
    // parent: full bounds MUST contain the known hidden left stripe.
    NSArray<NDAViewState *> *states = States(chain);
    UIImage *full = NDACaptureView(source, 1);
    CheckStates(states);
    Verify(full, b, b, 1, NO);

    source.bounds = CGRectMake(37, -11, 370, 80);
    Settle(source); b = source.bounds;
    CGRect shifted = CGRectMake(220, -11, 187, 80);
    Verify(Capture(source, shifted, 1, chain), shifted, b, 1, YES);
    Verify(Capture(source, shifted, 2, chain), shifted, b, 2, YES);
    states = States(chain);
    full = NDACaptureView(source, 2);
    CheckStates(states);
    Verify(full, b, b, 2, NO);

    // Already rounded inward to the half-point grid; no output edge expansion.
    CGRect fractional = CGRectMake(220.5, -10.5, 186, 79);
    Verify(Capture(source, fractional, 2, chain), fractional, b, 2, YES);
    // Translation and positive nonuniform scaling above/on the source must not
    // change the source-local texture or apply an extra bounds-origin offset.
    wrapper.transform = CGAffineTransformMake(1.25, 0, 0, 0.75, 11, 13);
    source.transform = CGAffineTransformMake(0.75, 0, 0, 1.25, 5, 7);
    Settle(source);
    Verify(Capture(source, shifted, 2, chain), shifted, b, 2, YES);
    Verify(Capture(source, fractional, 2, chain), fractional, b, 2, YES);
    wrapper.transform = CGAffineTransformIdentity; source.transform = CGAffineTransformIdentity;
    Settle(source);

    // Fractional source origin and a downsampled crop whose hidden red area
    // touches its left edge exactly. Count mixed red too, not just pure red.
    source.redEdge = 184;
    source.bounds = CGRectMake(37.25, -10.75, 370, 80);
    Settle(source);
    CGRect downsample = CGRectMake(221.25, -10.75, 186, 80);
    VerifyPattern(Capture(source, downsample, 0.5, chain), downsample, source.bounds, 0.5, YES, 184);
    VerifyPattern(Capture(source, downsample, 1.5, chain), downsample, source.bounds, 1.5, YES, 184);
    source.redEdge = 183;
    source.bounds = b;
    Settle(source);

    // Exact edges, not the former half-point allowance (including one ULP).
    const CGRect outside[] = {
        {{36.875, -11}, {187, 80}}, {{220, -11.125}, {187, 80}},
        {{220, -11}, {187.125, 80}}, {{220, -11}, {187, 80.125}},
        {{nextafter(37, -INFINITY), -11}, {187, 80}},
        {{220, nextafter(-11, -INFINITY)}, {187, 80}},
        {{220.125, -11}, {187, 80}}, {{220, -10.875}, {187, 80}},
        {{220, -11}, {nextafter(407, INFINITY) - 220, 80}},
        {{220, -11}, {187, nextafter(80, INFINITY)}}
    };
    for (size_t i = 0; i < sizeof(outside) / sizeof(outside[0]); ++i) Reject(source, outside[i], 2, chain);
    const CGRect invalid[] = {
        {{220, -11}, {0, 80}}, {{220, -11}, {187, 0}},
        {{220, -11}, {-1, 80}}, {{220, -11}, {187, -1}},
        {{NAN, -11}, {187, 80}}, {{220, NAN}, {187, 80}},
        {{220, -11}, {NAN, 80}}, {{220, -11}, {187, NAN}},
        {{INFINITY, -11}, {187, 80}}, {{220, -INFINITY}, {187, 80}},
        {{220, -11}, {INFINITY, 80}}, {{220, -11}, {187, INFINITY}},
        {{220, -11}, {186.25, 80}}, // not integral even at 2x: no outward rounding
        {{220, -11}, {187, 0.25}}
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i) Reject(source, invalid[i], 2, chain);
    Reject(source, CGRectNull, 1, chain); Reject(source, CGRectInfinite, 1, chain);
    const CGFloat badScales[] = {0, -1, NAN, INFINITY, -INFINITY, 2.00001, 1e300, 1e-300};
    for (size_t i = 0; i < sizeof(badScales) / sizeof(badScales[0]); ++i) Reject(source, shifted, badScales[i], chain);
    UIView *missing = nil;
    Require(NDACaptureRegion(missing, shifted, 1) == nil && NDACaptureView(missing, 1) == nil, "nil source");

    // Never feed NaN/huge geometry to UIKit setters. Override only the getter,
    // and prove invalid SOURCE bounds are refused before any hierarchy draw.
    const CGRect badBounds[] = {
        {{0, 0}, {2048.5, 80}}, {{0, 0}, {370, 2048.5}},
        {{0, 0}, {0, 80}}, {{0, 0}, {370, -1}},
        {{NAN, 0}, {370, 80}}, {{0, NAN}, {370, 80}},
        {{INFINITY, 0}, {370, 80}}, {{0, -INFINITY}, {370, 80}},
        {{0, 0}, {NAN, 80}}, {{0, 0}, {370, INFINITY}},
        {{1e308, 0}, {1e308, 80}}, {{0, 1e308}, {370, 1e308}},
        {{1e308, 0}, {370, 80}} // finite but unrepresentable right edge
    };
    for (size_t i = 0; i < sizeof(badBounds) / sizeof(badBounds[0]); ++i) {
        states = States(chain);
        NSUInteger calls = source.hierarchyCalls;
        source.suppliedBounds = badBounds[i]; source.supplyBounds = YES;
        Require(NDACaptureRegion(source, shifted, 1) == nil, "invalid source bounds rejected");
        source.supplyBounds = NO;
        Require(source.hierarchyCalls == calls, "invalid source bounds never drawn");
        CheckStates(states);
    }
    states = States(chain);
    NSUInteger calls = source.hierarchyCalls;
    source.suppliedBounds = CGRectMake(0, 0, 2048, 2048); source.supplyBounds = YES;
    Require(NDACaptureRegion(source, CGRectMake(0, 0, 1000, 221), 1) == nil, "220k pixel budget before allocation");
    Require(NDACaptureRegion(source, CGRectMake(0, 0, 550, 100.5), 2) == nil, "ceil-sized budget at 2x before allocation");
    source.supplyBounds = NO;
    Require(source.hierarchyCalls == calls, "over-budget never drawn");
    CheckStates(states);

    source.failureMode = 1;
    Require(Capture(source, shifted, 1, chain) == nil, "draw returning NO rejected");
    source.failureMode = 2;
    source.alpha = 0.73; wrapper.alpha = 0.81; source.hidden = YES;
    Require(Capture(source, shifted, 2, chain) == nil, "draw exception contained without source/ancestor writes");
    source.failureMode = 0; source.alpha = 1; wrapper.alpha = 1; source.hidden = NO;
    states = States(chain);
    source.throwBounds = YES;
    Require(NDACaptureRegion(source, shifted, 1) == nil, "bounds getter exception contained");
    Require(NDACaptureView(source, 1) == nil, "compatibility wrapper bounds exception contained");
    source.throwBounds = NO;
    CheckStates(states);

    NSUInteger reads = source.boundsReads;
    calls = source.hierarchyCalls;
    __block BOOL backgroundRejected = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            backgroundRejected = NDACaptureRegion(source, shifted, 1) == nil && NDACaptureView(source, 1) == nil;
            dispatch_semaphore_signal(done);
        }
    });
    Require(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
        "off-main rejection does not block waiting for main");
    Require(backgroundRejected && source.boundsReads == reads && source.hierarchyCalls == calls,
        "off-main rejected before any UIKit geometry/draw access");
    CheckStates(states);

    // The exact budget is admissible; a larger image is not silently rescaled.
    source.bounds = CGRectMake(0, 0, 550, 400);
    Settle(source); b = source.bounds;
    Verify(Capture(source, b, 1, chain), b, b, 1, NO);
    Reject(source, b, 2, chain);
    [wrapper removeFromSuperview];
    printf("CAPTURE NATIVE PASS: %lu checks; production NDACapture.m + real UIKit; all-pixel counts, crop edges, origins, scales, budget, exceptions, nonmutation\n", (unsigned long)checks);
    fflush(stdout);
}

@interface NDACaptureTestDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation NDACaptureTestDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    puts("CAPTURE HOST: didFinishLaunching");
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UIViewController *root = [UIViewController new];
    root.view = [[UIView alloc] initWithFrame:self.window.bounds];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:NO block:^(__unused NSTimer *timer) {
        @autoreleasepool {
            RunCaptureTests(self.window);
            exit(0);
        }
    }];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        // A broken launch/runloop must fail the gate, not hang the CI forever.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC),
            dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                fputs("FAIL capture-native: runtime watchdog\n", stderr); _Exit(1);
            });
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(NDACaptureTestDelegate.class));
    }
}
