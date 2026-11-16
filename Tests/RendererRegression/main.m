// Real UIKit Simulator executable. Metal objects below are protocol fixtures,
// NOT a software GPU, shader test, or production SpringBoard integration test.
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import "../../src/NLDustRenderer.m" // execute production implementation + inject only file-static dependencies
#import "NLNotificationDismissalSnapshot.h"
#include <stdio.h>
#include <stdlib.h>

BOOL NLAnimationEnabled = YES;
double NLAnimationDuration = 1.3, NLDustDistance = 110;
NSUInteger NLDustParticleLimit = 14000, NLActiveSnapshots, NLReservedParticles, NLBatchParticleLimit;
char NLDustSnapshotKey;
BOOL NLLockScreenDustOwnsView(UIView *view) { (void)view; return NO; }
static NSUInteger checks;
static void Check(BOOL value, const char *message) {
    ++checks;
    if (!value) { fprintf(stderr, "RENDERER FAIL: %s\n", message); fflush(stderr); exit(1); }
}

@interface RRTexture : NSObject
@property(nonatomic) MTLPixelFormat pixelFormat;
@property(nonatomic) NSUInteger width, height, stride;
@property(nonatomic, strong) NSData *bytes;
@end
@implementation RRTexture
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level
            withBytes:(const void *)bytes bytesPerRow:(NSUInteger)stride {
    (void)region; (void)level; self.stride = stride;
    self.bytes = [NSData dataWithBytes:bytes length:stride * self.height];
}
@end
@interface RRDevice : NSObject
@property(nonatomic, strong) RRTexture *texture;
@end
@implementation RRDevice
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
    RRTexture *t = [RRTexture new]; t.width = descriptor.width; t.height = descriptor.height;
    t.pixelFormat = descriptor.pixelFormat; self.texture = t; return (id)t;
}
@end
@interface RREncoder : NSObject
@property(nonatomic, strong) NSData *uniforms;
@property(nonatomic) NSUInteger instances;
@end
@implementation RREncoder
- (void)setRenderPipelineState:(id)state { (void)state; }
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {
    (void)index; self.uniforms = [NSData dataWithBytes:bytes length:length];
}
- (void)setFragmentTexture:(id)texture atIndex:(NSUInteger)index { (void)texture; (void)index; }
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start
          vertexCount:(NSUInteger)count instanceCount:(NSUInteger)instances {
    (void)type; (void)start; Check(count == 6, "production tile primitive unchanged"); self.instances = instances;
}
- (void)endEncoding {}
@end
@interface RRCommand : NSObject
@property(nonatomic) MTLCommandBufferStatus status;
@property(nonatomic) BOOL noEncoder, throws, presented, committed;
@property(nonatomic, strong) MTLRenderPassDescriptor *pass;
@property(nonatomic, strong) RREncoder *encoder;
@end
@implementation RRCommand
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)pass {
    if (self.throws) [NSException raise:@"RRFixture" format:@"encoder failure"];
    self.pass = pass; self.encoder = [RREncoder new]; return self.noEncoder ? nil : (id)self.encoder;
}
- (void)presentDrawable:(id)drawable { Check(drawable != nil, "present actual fixture drawable"); self.presented = YES; }
- (void)commit { self.committed = YES; }
@end
@interface RRQueue : NSObject
@property(nonatomic) MTLCommandBufferStatus status;
@property(nonatomic) BOOL noEncoder, throws;
@property(nonatomic) NSUInteger submissions;
@property(nonatomic, strong) RRCommand *last;
@end
@implementation RRQueue
- (id<MTLCommandBuffer>)commandBuffer {
    ++self.submissions; self.last = [RRCommand new]; self.last.status = self.status;
    self.last.noEncoder = self.noEncoder; self.last.throws = self.throws; return (id)self.last;
}
@end
@interface RRDrawable : NSObject
@property(nonatomic, strong) id texture;
@end
@implementation RRDrawable @end
static BOOL noDrawable;
@interface RRLayer : CAMetalLayer
@property(nonatomic, strong) id fixtureDevice;
@end
@implementation RRLayer
- (void)setDevice:(id<MTLDevice>)device { self.fixtureDevice = device; }
- (id<MTLDevice>)device { return self.fixtureDevice; }
- (id<CAMetalDrawable>)nextDrawable {
    if (noDrawable) return nil;
    RRDrawable *drawable = [RRDrawable new]; drawable.texture = (id)[RRTexture new]; return (id)drawable;
}
@end
static Class LayerClass(id object, SEL selector) { (void)object; (void)selector; return RRLayer.class; }

@interface RRCard : UIView
@property(nonatomic) NSInteger failure;
@end
@implementation RRCard
- (BOOL)drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)updates {
    if (self.failure == 1) return NO;
    if (self.failure == 2) [NSException raise:@"RRFixture" format:@"source draw failure"];
    if (self.failure == 3) {
        // Deliberate translucent mask: native fallback must avoid double-alpha.
        [[UIColor colorWithWhite:0.5 alpha:0.5] setFill]; UIRectFill(rect); return YES;
    }
    if (self.failure == 4) {
        self.failure = 0; // only the isolated direct draw; window draw remains real UIKit
        // Simulate an isolated material's grey fallback; the real window's
        // composited colour, not this RGB, must reach the uploaded texture.
        [UIColor.grayColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:20] fill]; return YES;
    }
    return [super drawViewHierarchyInRect:rect afterScreenUpdates:updates];
}
@end
@interface RRWindow : UIWindow
@property(nonatomic) NSInteger failure;
@end
@implementation RRWindow
- (BOOL)drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)updates {
    if (self.failure == 1) return NO;
    if (self.failure == 2) [NSException raise:@"RRFixture" format:@"window draw failure"];
    return [super drawViewHierarchyInRect:rect afterScreenUpdates:updates];
}
@end
@interface RRRow : UIView
@property(nonatomic, strong) UIViewController *contentViewController;
@end
@implementation RRRow @end
@interface RRScalarRow : UIView @end
@implementation RRScalarRow
- (NSUInteger)contentViewController { return 7; }
@end

static RRDevice *device;
static RRQueue *queue;
static RRRow *row;
static RRCard *card;
static UIView *list;
static RRWindow *window;
static void ResetQueue(void) {
    noDrawable = NO; queue.noEncoder = NO; queue.throws = NO;
    queue.status = MTLCommandBufferStatusCompleted;
}
static NLNotificationDismissalSnapshot *Snapshot(void) {
    return [NLNotificationDismissalSnapshot snapshotForList:list notificationView:row];
}
static void NoLeaks(void) {
    Check(NLActiveSnapshots == 0 && NLReservedParticles == 0, "exactly-once particle/counter release");
    Check(objc_getAssociatedObject(row, &NLDustSnapshotKey) == nil, "row association released");
    for (UIView *v in window.subviews)
        Check(![v isKindOfClass:NLNotificationDismissalSnapshot.class], "no overlay retained in window");
}
static void CheckPass(void) {
    MTLRenderPassColorAttachmentDescriptor *a = queue.last.pass.colorAttachments[0];
    Check(a.loadAction == MTLLoadActionClear && a.storeAction == MTLStoreActionStore,
          "every frame clears instead of loading a previous drawable");
    MTLClearColor c = a.clearColor;
    Check(c.red == 0 && c.green == 0 && c.blue == 0 && c.alpha == 0, "transparent black clear, not grey");
    Check(queue.last.presented && queue.last.committed, "production present/commit executed");
    Check(queue.last.encoder.instances > 0, "real production uniforms and instanced draw executed");
}
static CGImageRef Image(BOOL bgra) CF_RETURNS_RETAINED {
    const unsigned char rgba[] = {60, 30, 10, 128, 5, 20, 40, 255};
    const unsigned char bgr[] = {10, 30, 60, 128, 40, 20, 5, 255};
    CFDataRef bytes = CFDataCreate(NULL, bgra ? bgr : rgba, 8);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(bytes);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo info = bgra ? kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst : kCGImageAlphaPremultipliedLast;
    CGImageRef image = CGImageCreate(2, 1, 8, 32, 8, cs, info, provider, NULL, NO, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs); CGDataProviderRelease(provider); CFRelease(bytes); return image;
}
static NLDustRenderer *Renderer(CGImageRef image, double duration) {
    NLDustRenderer *r = [[NLDustRenderer alloc] initWithImage:image cardFrame:CGRectMake(0,0,100,40)
        particleCount:3000 duration:duration distance:110 seed:17];
    r.frame = CGRectMake(0,0,180,160); if (r) [window addSubview:r]; return r;
}

static void RendererTests(void) {
    for (NSUInteger bgra = 0; bgra < 2; ++bgra) {
        CGImageRef image = Image(bgra != 0);
        NLDustRenderer *r = Renderer(image, 1.3); CGImageRelease(image);
        Check(r != nil && !r.hidden, "prime host is not hidden prematurely");
        Check(device.texture.pixelFormat == (bgra ? MTLPixelFormatBGRA8Unorm : MTLPixelFormatRGBA8Unorm),
              "real CG bitmap byte order selects matching Metal format");
        const unsigned char *p = device.texture.bytes.bytes;
        Check(p[0] == (bgra ? 10 : 60) && p[1] == 30 && p[2] == (bgra ? 60 : 10) && p[3] == 128,
              "premultiplied RGB/alpha uploaded unmodified");
        Check([r primeFrame] && [r hasCompletedFrame] && ![r hasFailedFrame], "prime completion status");
        CheckPass();
        for (NSUInteger status = MTLCommandBufferStatusNotEnqueued; status <= MTLCommandBufferStatusScheduled; ++status) {
            queue.last.status = status; NSUInteger count = queue.submissions;
            Check(![r hasCompletedFrame] && ![r hasFailedFrame], "pending is neither completed nor error");
            Check([r drawProgress:0.3] && queue.submissions == count, "all in-flight states, including Scheduled, skip submission");
        }
        queue.last.status = MTLCommandBufferStatusCompleted;
        Check([r drawProgress:0.4], "completed frame permits next draw");
        __block NSUInteger callbacks = 0;
        __weak id textureCache = r.texture, commandCache = r.lastCommand;
        r.completion = ^{ ++callbacks; Check(r.hidden && !r.superview && !r.texture && !r.lastCommand,
                                           "resources/visible host released before owner callback"); };
        [r invalidate]; [r invalidate]; [r start];
        device.texture = nil; queue.last = nil; // release fixture-only observation retains
        Check(textureCache == nil && commandCache == nil, "renderer retains no texture/command cache after invalidate");
        Check(callbacks == 1 && !r.displayLink && !r.completion, "invalidate is exactly once and cannot restart");
        Check(![r drawProgress:0.5], "no draw after destruction");
    }
    CGImageRef image = Image(NO);
    Check(Renderer(image, INFINITY) == nil && Renderer(image, NAN) == nil, "non-finite duration rejected");
    NLDustRenderer *r = Renderer(image, 1.3);
    Check(![r drawProgress:NAN], "non-finite progress rejected");
    noDrawable = YES; Check(![r primeFrame], "missing drawable fails prime"); noDrawable = NO;
    queue.noEncoder = YES; Check(![r primeFrame], "nil encoder fails prime"); queue.noEncoder = NO;
    queue.throws = YES; Check(![r primeFrame], "encoder exception fails without escaping"); queue.throws = NO;
    [r invalidate]; CGImageRelease(image); NoLeaks();
}

static void CaptureAndLifecycleTests(void) {
    // Numeric-only diagnostics for this synthetic source, never persist an image.
    UIGraphicsBeginImageContextWithOptions(card.bounds.size, NO, 2);
    BOOL maskDrawn = [card drawViewHierarchyInRect:(CGRect){CGPointZero, card.bounds.size} afterScreenUpdates:NO];
    UIImage *maskFixture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRef maskImage = maskFixture.CGImage;
    Check(maskDrawn && maskImage != NULL, "synthetic source mask exists before numeric audit");
    fprintf(stdout,"FIXTURE MASK: drawn=%d size=%zux%zu bpp=%zu info=0x%x alpha=%u\n",maskDrawn,
        CGImageGetWidth(maskImage),CGImageGetHeight(maskImage),CGImageGetBitsPerPixel(maskImage),
        (unsigned)CGImageGetBitmapInfo(maskImage),(unsigned)CGImageGetAlphaInfo(maskImage));
    CFDataRef maskData=CGDataProviderCopyData(CGImageGetDataProvider(maskImage));
    const UInt8 *maskBytes=CFDataGetBytePtr(maskData);size_t maskStride=CGImageGetBytesPerRow(maskImage);
    NSUInteger fractional=0,farFractional=0;
    for(size_t yy=1;yy+1<CGImageGetHeight(maskImage);++yy) for(size_t xx=1;xx+1<CGImageGetWidth(maskImage);++xx) {
        unsigned aa=maskBytes[yy*maskStride+xx*4+3]; if(aa==0||aa==255)continue;
        ++fractional;BOOL edge=NO;
        for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx)
            if(maskBytes[(size_t)((NSInteger)yy+dy)*maskStride+(size_t)((NSInteger)xx+dx)*4+3]==0)edge=YES;
        if(!edge){++farFractional;if(farFractional<=3)fprintf(stdout,"FIXTURE MASK partialinterior x=%zu y=%zu alpha=%u\n",xx,yy,aa);}
    }
    fprintf(stdout,"FIXTURE MASK: fractional=%lu farther_than_one_zero_pixel=%lu\n",(unsigned long)fractional,(unsigned long)farFractional);
    fflush(stdout);CFRelease(maskData);
    CGRect original = card.frame; CGFloat alpha = card.alpha;
    NLNotificationDismissalSnapshot *s = Snapshot();
    if (!s) fprintf(stdout, "FIXTURE CAPTURE STAGE: %s\n", [NLListSnapshotStatus() description].UTF8String);
    Check(s != nil, "real UIKit material/card capture produced production snapshot");
    NLDustRenderer *r = s.dustRenderer; RRTexture *t = device.texture;
    Check(t.width == 400 && t.height == 160, "card-only 2x texture excludes sibling swipe actions");
    Check(s.sourceView == row && objc_getAssociatedObject(row, &NLDustSnapshotKey) == s,
          "deduplication/removal identity remains the original row");
    Check(Snapshot() == nil, "duplicate row snapshot rejected");
    NSData *baselinePixels = [t.bytes copy];
    const unsigned char *pixels = baselinePixels.bytes;
    Check(pixels[3] == 0, "rounded card corner stays transparent, no wallpaper rectangle");
    NSUInteger center = 80 * t.stride + 200 * 4;
    Check(pixels[center + 3] == 255, "opaque card interior preserved without blanket opacity reduction");
    // Read actual UIKit's window-composited colour independently. Comparing raw
    // pixels here validates capture/alpha/texture upload; this is NOT GPU readback.
    s.hidden = YES; // reference excludes only our fake-Metal overlay, never the source
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, 2.0);
    Check([window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO], "real window reference draw");
    UIImage *reference = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    s.hidden = NO;
    CGDataProviderRef provider = CGImageGetDataProvider(reference.CGImage);
    CFDataRef data = CGDataProviderCopyData(provider);
    CGRect rect = [card convertRect:card.bounds toView:window];
    size_t stride = CGImageGetBytesPerRow(reference.CGImage);
    const UInt8 *ref = CFDataGetBytePtr(data);
    size_t position = (size_t)((rect.origin.y + 40) * 2) * stride + (size_t)((rect.origin.x + 100) * 2) * 4;
    Check(memcmp(pixels + center, ref + position, 4) == 0, "uploaded colour equals real window composition, not isolated grey source");
    CFRelease(data);
    Check(CGRectEqualToRect(card.frame, original) && card.alpha == alpha && card.superview == row,
          "capture never hides/reparents/modifies native source");
    CheckPass();
    [s startRemovalAnimation]; Check(s.animationStarted, "first completed frame permits start");
    r.startTime = CACurrentMediaTime() - 2;
    [r tick:nil];
    Check(s.cleanedUp && r.hidden && !r.superview && !s.superview && !r.texture && !r.lastCommand,
          "normal finish removes renderer and owner immediately, not watchdog delay");
    [s cleanUp]; NoLeaks();

    card.failure = 3;
    Check(Snapshot() == nil, "half-alpha interior fails closed instead of applying composited opacity twice");
    card.failure = 0; NoLeaks();
    card.failure = 4; s = Snapshot();
    Check(s != nil && memcmp(device.texture.bytes.bytes + center, baselinePixels.bytes + center, 4) == 0,
          "isolated grey material RGB is replaced by actual window colour, without a grey-pixel filter");
    [s cleanUp]; NoLeaks();
    for (UIView *v in card.subviews) v.hidden = YES;
    card.backgroundColor = UIColor.grayColor; s = Snapshot();
    Check(s != nil, "legitimate opaque grey content is not rejected");
    const UInt8 *grey = (const UInt8 *)device.texture.bytes.bytes + center;
    Check(grey[0] == grey[1] && grey[1] == grey[2] && grey[3] == 255,
          "legitimate grey RGB and full alpha survive unchanged");
    [s cleanUp]; card.backgroundColor = UIColor.whiteColor;
    for (UIView *v in card.subviews) v.hidden = NO;
    NoLeaks();
    CGRect listBounds = list.bounds; list.clipsToBounds = YES;
    list.bounds = CGRectMake(0,0,150,300); s = Snapshot();
    Check(s != nil && device.texture.width == 280, "clipping ancestor excludes concealed card pixels");
    [s cleanUp]; list.bounds = listBounds;
    list.layer.cornerRadius = 3;
    Check(Snapshot() == nil, "unknown rounded ancestor clip stays native");
    list.layer.cornerRadius = 0; list.clipsToBounds = NO;
    card.transform = CGAffineTransformMakeRotation(0.1);
    Check(Snapshot() == nil, "non-axis-aligned source stays native"); card.transform = CGAffineTransformIdentity; NoLeaks();

    queue.status = MTLCommandBufferStatusScheduled; s = Snapshot(); r = s.dustRenderer;
    [s startRemovalAnimation]; Check(!s.animationStarted && !s.cleanedUp, "scheduled prime is not first-frame confirmation");
    [s setValue:@(CACurrentMediaTime() - 1) forKey:@"frameDeadline"];
    [s startRemovalAnimation]; Check(s.cleanedUp, "stuck first frame has finite deadline"); NoLeaks();
    ResetQueue(); s = Snapshot(); r = s.dustRenderer;
    queue.last.status = MTLCommandBufferStatusError;
    [s startRemovalAnimation]; Check(s.cleanedUp && !r.superview, "GPU error tears down owner before start"); NoLeaks();

    for (NSUInteger mode = 0; mode < 5; ++mode) {
        ResetQueue();
        if (mode == 0) noDrawable = YES;
        if (mode == 1) queue.noEncoder = YES;
        if (mode == 2) queue.throws = YES;
        if (mode == 3) card.failure = 1;
        if (mode == 4) card.failure = 2;
        CGContextRef before = UIGraphicsGetCurrentContext();
        Check(Snapshot() == nil, "prime/source draw failure returns nil without publishing");
        Check(UIGraphicsGetCurrentContext() == before, "source context restored after failure/exception");
        card.failure = 0; ResetQueue(); NoLeaks();
    }
    for (NSInteger mode = 1; mode <= 2; ++mode) {
        window.failure = mode; CGContextRef before = UIGraphicsGetCurrentContext();
        Check(Snapshot() == nil, "window draw failure/exception fails closed");
        Check(UIGraphicsGetCurrentContext() == before, "window context restored after failure/exception");
        window.failure = 0; NoLeaks();
    }
    s = Snapshot(); r = s.dustRenderer; [s startRemovalAnimation];
    queue.last.status = MTLCommandBufferStatusError; [r tick:nil];
    Check(s.cleanedUp, "runtime command error cleanup callback"); NoLeaks();
    ResetQueue(); s = Snapshot(); r = s.dustRenderer; [s startRemovalAnimation];
    noDrawable = YES;
    for (NSUInteger i = 0; i < 6; ++i) [r tick:nil];
    Check(!s.cleanedUp, "transient drawable failures retain bounded retry");
    [r tick:nil]; Check(s.cleanedUp, "seven consecutive draw failures clean owner exactly once");
    ResetQueue(); NoLeaks();
    s = Snapshot(); r = s.dustRenderer;
    window.hidden = YES; [r tick:nil]; window.hidden = NO;
    Check(s.cleanedUp && !r.superview, "hidden-window termination removes visible host"); NoLeaks();
    s = Snapshot(); r = s.dustRenderer;
    NSObject *newer = [NSObject new];
    objc_setAssociatedObject(row, &NLDustSnapshotKey, newer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [s cleanUp]; Check(objc_getAssociatedObject(row, &NLDustSnapshotKey) == newer, "cleanup cannot erase a newer association");
    objc_setAssociatedObject(row, &NLDustSnapshotKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); NoLeaks();
    Check([NLNotificationDismissalSnapshot snapshotForList:list notificationView:list] == nil, "unknown whole-row hierarchy stays native");
    RRScalarRow *scalar = [[RRScalarRow alloc] initWithFrame:CGRectMake(0,200,100,50)]; [list addSubview:scalar];
    Check([NLNotificationDismissalSnapshot snapshotForList:list notificationView:scalar] == nil, "scalar getter never treated as controller object");
    [scalar removeFromSuperview]; NoLeaks();
}

@interface RRAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) RRWindow *window;
@end
@implementation RRAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    method_setImplementation(class_getClassMethod(NLDustRenderer.class, @selector(layerClass)), (IMP)LayerClass);
    device = [RRDevice new]; queue = [RRQueue new]; ResetQueue();
    NLDustDevice = (id)device; NLDustQueue = (id)queue; NLDustPipeline = (id)[NSObject new]; NLDustReady = YES;
    window = [[RRWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window = window;
    UIViewController *root = [UIViewController new]; window.rootViewController = root;
    root.view.backgroundColor = [UIColor colorWithRed:0.85 green:0.1 blue:0.5 alpha:1];
    list = [[UIView alloc] initWithFrame:CGRectMake(0,100,320,300)]; [root.view addSubview:list];
    row = [[RRRow alloc] initWithFrame:CGRectMake(0,20,320,80)]; [list addSubview:row];
    UIView *actions = [[UIView alloc] initWithFrame:CGRectMake(220,0,100,80)]; actions.backgroundColor = UIColor.redColor; [row addSubview:actions];
    card = [[RRCard alloc] initWithFrame:CGRectMake(10,0,200,80)]; card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 20; card.clipsToBounds = YES;
    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
    material.frame = card.bounds; [card addSubview:material]; [row addSubview:card];
    row.contentViewController = [UIViewController new]; row.contentViewController.view = card;
    [window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        @try {
            [window layoutIfNeeded]; RendererTests(); CaptureAndLifecycleTests();
            printf("RENDERER NATIVE PASS: %lu checks; real UIKit + Metal protocol fixtures; NO GPU render/readback claim\n", (unsigned long)checks);
            fflush(stdout); exit(0);
        } @catch (NSException *e) { fprintf(stderr, "RENDERER EXCEPTION: %s\n", e.description.UTF8String); exit(1); }
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(RRAppDelegate.class)); }
}
