//
//  NLDustRenderer.m
//  NoticeListTweak — 通知消散
//
//  逆向自 1.0.1~test14。原始地址写在每个方法上方。
//  着色器源码原样保存在 DustShader.metal（从二进制 __const 完整恢复）。
//

#import "NLDustRenderer.h"
#import <objc/runtime.h>

// ---------------------------------------------------------------- 静态状态
// 全部为文件级 static，对应二进制里的 __ZL* 变量（地址见注释）。

static id<MTLDevice> NLDustDevice;             // 0x26510
static id<MTLCommandQueue> NLDustQueue;        // 0x26518
static id<MTLRenderPipelineState> NLDustPipeline;  // 0x26520
static BOOL NLDustReady;                       // 0x26528
static BOOL NLDustPreparing;                   // 0x26529
static BOOL NLDustPrepared;                    // 0x2652a

// 0x195e8 起是内嵌的 Metal 源码字符串
extern const char *NLDustMetalSource; // deterministic source generated from DustShader.metal

static BOOL NLDustWarmupStarted;   // 0x26529 —— 与 NLDustPreparing 同字节？

// ---------------------------------------------------------------- 常量
// 0x195c0 = 0.02   （alpha 下限 / 最小可见阈值）
// 0x195c8 = 2.2    （卡片外扩边距系数）
// 0x195e0 = 0.1    （duration 下限）
// 0x4a50 起：宽>=16、高>=12；面积上限 0x4f8000000000 → 16384×16384 像素？见下
static const double kNLMinVisibleAlpha = 0.02;
static const double kNLInsetScale = 2.2;
static const double kNLMinDuration = 0.1;
static const double kNLMaxContentsScale = 2.0;

// 纹理像素上限：0x124f80 = 1,200,000（由 movz 0x4f80 + movk 0x12,lsl16 拼成）
static const NSUInteger NLDustMaxTexturePixels = 0x124f80;
// 单边上限：0x1000 = 4096
static const NSUInteger NLDustMaxTextureSide = 0x1000;


#pragma mark - NLDustWarmup

/// 后台线程上编译 Metal 管线，完成后回主线程 markReady。
@interface NLDustWarmup : NSObject
- (void)compileOnWorker;
- (void)markReady;
@end

@implementation NLDustWarmup

// 0x75a0
- (void)compileOnWorker
{
    @autoreleasepool {
        @try {
            [NLDustRenderer prepareRenderer];
        } @catch (NSException *e) {
            NSLog(@"[NoticeListTweak] dust preparation skipped (%@)", e.name);
        }
        [self performSelectorOnMainThread:@selector(markReady) withObject:nil waitUntilDone:NO];
    }
}

// 0x7684
- (void)markReady
{
    NLDustReady = (NLDustQueue != nil) && (NLDustPipeline != nil);
}

@end


#pragma mark - NLDustRenderer

@implementation NLDustRenderer

// 0x76b4
+ (Class)layerClass
{
    return [CAMetalLayer class];
}

// 0x776c
+ (BOOL)isReady
{
    return NLDustReady;
}

// 0x76c8
+ (void)prewarmRenderer
{
    if (![NSThread isMainThread]) {
        return;
    }
    if (NLDustWarmupStarted) {
        return;
    }
    NLDustWarmupStarted = YES;

    NLDustWarmup *warmup = [[NLDustWarmup alloc] init];
    [NSThread detachNewThreadSelector:@selector(compileOnWorker)
                             toTarget:warmup
                           withObject:nil];
}

// 0x7778
+ (BOOL)prepareRenderer
{
    if (NLDustPreparing) {
        return (NLDustPipeline != nil) && (NLDustQueue != nil);
    }
    NLDustPreparing = YES;

    NLDustDevice = MTLCreateSystemDefaultDevice();
    if (!NLDustDevice) {
        return NO;
    }

    MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
    options.languageVersion = MTLLanguageVersion2_1;   // 0x20001

    NSString *source = [NSString stringWithUTF8String:NLDustMetalSource];
    NSError *error = nil;
    id<MTLLibrary> library = [NLDustDevice newLibraryWithSource:source
                                                        options:options
                                                          error:&error];
    if (!library) {
        NSLog(@"[NoticeListTweak] dust shader unavailable: %@", error.localizedDescription);
        return NO;
    }

    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = [library newFunctionWithName:@"nlDustVertex"];
    desc.fragmentFunction = [library newFunctionWithName:@"nlDustFragment"];

    MTLRenderPipelineColorAttachmentDescriptor *attachment =
        desc.colorAttachments[0];
    attachment.pixelFormat = MTLPixelFormatBGRA8Unorm;   // 80
    attachment.blendingEnabled = YES;
    attachment.sourceRGBBlendFactor = MTLBlendFactorOne;
    attachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    attachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
    attachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    error = nil;
    NLDustPipeline = [NLDustDevice newRenderPipelineStateWithDescriptor:desc
                                                                 error:&error];
    if (!NLDustPipeline) {
        NSLog(@"[NoticeListTweak] dust pipeline unavailable: %@", error.localizedDescription);
        return NO;
    }

    NLDustQueue = [NLDustDevice newCommandQueue];
    return NLDustQueue != nil;
}

// 0x7bb8
- (instancetype)initWithImage:(CGImageRef)image
                    cardFrame:(CGRect)cardFrame
                particleCount:(NSUInteger)particleCount
                     duration:(double)duration
                     distance:(double)distance
                         seed:(float)seed
{
    self = [super initWithFrame:CGRectZero];
    if (!image || !self) {
        return nil;
    }

    if (![[self class] isReady]) {
        return nil;
    }

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);

    // 像素总数上限 0x124f80 = 1,200,000
    if (width * height > NLDustMaxTexturePixels) {
        return nil;
    }
    // 宽高各自 <= 4096（(w-1)|(h-1) <= 0xfff）
    if (((width - 1) | (height - 1)) > 0xfff) {
        return nil;
    }

    // 只接受 32bpp / 8bpc，且位图格式能直接对应 Metal 纹理。
    // 0x7cd0 分支：(bitmapInfo & 0x7000) == 0x2000 且 alphaInfo == 2
    //            → kCGBitmapByteOrder32Little + kCGImageAlphaPremultipliedFirst → BGRA8Unorm(80)
    // 0x7cf0 分支：(bitmapInfo & 0x3000) == 0 且 alphaInfo == 1
    //            → 默认字节序 + kCGImageAlphaPremultipliedLast → RGBA8Unorm(70)
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(image);
    MTLPixelFormat pixelFormat;
    if ((bitmapInfo & 0x7000) == 0x2000 && alphaInfo == kCGImageAlphaPremultipliedFirst) {
        pixelFormat = MTLPixelFormatBGRA8Unorm;   // 0x50 = 80
    } else if ((bitmapInfo & 0x3000) == 0 && alphaInfo == kCGImageAlphaPremultipliedLast) {
        pixelFormat = MTLPixelFormatRGBA8Unorm;   // 0x46 = 70
    } else {
        return nil;
    }

    if (CGImageGetBitsPerPixel(image) != 32) {
        return nil;
    }
    if (CGImageGetBitsPerComponent(image) != 8) {
        return nil;
    }

    size_t bytesPerRow = CGImageGetBytesPerRow(image);
    CGDataProviderRef provider = CGImageGetDataProvider(image);
    CFDataRef data = CGDataProviderCopyData(provider);
    if (bytesPerRow < width * 4 || !data) {
        if (data) CFRelease(data);
        return nil;
    }
    if (CFDataGetLength(data) < (CFIndex)(bytesPerRow * height)) {
        CFRelease(data);
        return nil;
    }

    MTLTextureDescriptor *texDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;   // 1
    texDesc.storageMode = MTLStorageModeShared;  // 0

    id<MTLTexture> texture = [NLDustDevice newTextureWithDescriptor:texDesc];
    self.texture = texture;

    if (self.texture) {
        MTLRegion region = MTLRegionMake2D(0, 0, width, height);
        [self.texture replaceRegion:region
                        mipmapLevel:0
                          withBytes:CFDataGetBytePtr(data)
                        bytesPerRow:bytesPerRow];
    }
    CFRelease(data);

    if (!self.texture) {
        return nil;
    }

    self.cardFrame = cardFrame;
    // columns = max(1, floor(sqrt(max(w,1)/max(h,1) * particleCount)))
    double aspect = fmax(cardFrame.size.width, 1.0) / fmax(cardFrame.size.height, 1.0);
    NSUInteger columns = (NSUInteger)floor(sqrt(aspect * (double)particleCount));
    self.columns = columns > 1 ? columns : 1;
    NSUInteger rows = particleCount / self.columns;
    self.rows = rows > 1 ? rows : 1;
    self.duration = duration;
    self.distance = distance;
    self.seed = seed;

    self.userInteractionEnabled = NO;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    self.accessibilityElementsHidden = YES;

    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    layer.device = NLDustDevice;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.opaque = NO;
    layer.maximumDrawableCount = 2;
    layer.allowsNextDrawableTimeout = YES;

    return self;
}

// 0x817c
- (BOOL)primeFrame
{
    return [self drawProgress:0.0f];
}

// 0x818c
- (BOOL)hasCompletedFrame
{
    id<MTLCommandBuffer> cmd = self.lastCommand;
    if (!cmd) {
        return NO;
    }
    return cmd.status == MTLCommandBufferStatusCompleted;   // 4
}

// 0x8244
- (BOOL)hasFailedFrame
{
    id<MTLCommandBuffer> cmd = self.lastCommand;
    if (!cmd) {
        return YES;    // 没有 command buffer 视为失败
    }
    return cmd.status == MTLCommandBufferStatusError;       // 5
}

// 0x82fc
- (void)start
{
    if (self.displayLink) {
        return;
    }
    self.startTime = CACurrentMediaTime();

    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    self.displayLink = link;
    link.preferredFramesPerSecond = 60;
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

// 0x847c
- (void)tick:(CADisplayLink *)link
{
    if (!self.window || self.window.isHidden) {
        [self invalidate];
        self.hidden = YES;
        return;
    }

    double now = CACurrentMediaTime();
    double elapsed = now - self.startTime;
    double duration = fmax(self.duration, kNLMinDuration);
    float progress = (float)(elapsed / duration);
    if (progress >= 1.0f) {
        [self invalidate];
        self.hidden = YES;
        return;
    }

    if (![self drawProgress:progress]) {
        self.skippedFrames = self.skippedFrames + 1;
        if (self.skippedFrames >= 7) {
            [self invalidate];
            self.hidden = YES;
        }
    }
}

// 0x8650
- (BOOL)drawProgress:(float)progress
{
    id<MTLTexture> texture = self.texture;
    if (!texture || !NLDustPipeline) {
        return NO;
    }
    CGSize boundsSize = self.bounds.size;
    if (boundsSize.width < 1.0 || boundsSize.height < 1.0) {
        return NO;
    }
    // 上一帧还没完成就不提交新帧
    id<MTLCommandBuffer> last = self.lastCommand;
    if (last) {
        MTLCommandBufferStatus status = last.status;
        if (status == MTLCommandBufferStatusError) {
            return NO;
        }
        if (status < MTLCommandBufferStatusScheduled) {   // 4 = scheduled
            return YES;    // 上一帧在飞，跳过这一帧但仍算成功
        }
    }

    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGFloat scale = self.window.screen.scale;
    if (scale == 0) {
        scale = [UIScreen mainScreen].scale;
    }
    scale = fmin(scale, kNLMaxContentsScale);
    layer.contentsScale = scale;

    CGSize currentSize = layer.drawableSize;
    CGFloat wantW = ceil(scale * boundsSize.width);
    CGFloat wantH = ceil(scale * boundsSize.height);
    if (currentSize.width != wantW || currentSize.height != wantH) {
        layer.drawableSize = CGSizeMake(wantW, wantH);
    }

    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) {
        return NO;
    }

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;   // 2
    pass.colorAttachments[0].storeAction = MTLStoreActionStore; // 1
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);

    id<MTLCommandBuffer> commandBuffer = [NLDustQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) {
        return NO;
    }

    // DustUniforms: viewport(float2) origin(float2) cardSize(float2)
    //               columns(uint) rows(uint) time(float) distance(float) seed(float) pad
    struct {
        float viewport[2];
        float origin[2];
        float cardSize[2];
        uint32_t columns;
        uint32_t rows;
        float time;
        float distance;
        float seed;
        float pad;
    } uniforms = {0};

    uniforms.viewport[0] = (float)boundsSize.width;
    uniforms.viewport[1] = (float)boundsSize.height;
    uniforms.origin[0] = (float)self.cardFrame.origin.x;
    uniforms.origin[1] = (float)self.cardFrame.origin.y;
    uniforms.cardSize[0] = (float)self.cardFrame.size.width;
    uniforms.cardSize[1] = (float)self.cardFrame.size.height;
    uniforms.columns = (uint32_t)self.columns;
    uniforms.rows = (uint32_t)self.rows;
    uniforms.time = progress;
    uniforms.distance = (float)self.distance;
    uniforms.seed = self.seed;

    [encoder setRenderPipelineState:NLDustPipeline];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setFragmentTexture:texture atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:self.columns * self.rows];
    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    self.lastCommand = commandBuffer;
    [commandBuffer commit];

    return YES;
}

// 0x8e98
- (void)invalidate
{
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.texture = nil;
    self.lastCommand = nil;
}

// 0x8f38
- (void)dealloc
{
    [self invalidate];
}

// 0x9140

@end
