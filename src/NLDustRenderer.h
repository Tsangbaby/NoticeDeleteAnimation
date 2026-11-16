//
//  NLDustRenderer.h
//  NoticeDeleteAnimation — 通知消散
//
//  由 1.0.1~test14 二进制逆向重建。原始地址见各实现文件注释。
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// 一个把整张卡片位图切成 tiles、再按 Metal 顶点着色器逐块抛出/淡出的渲染视图。
/// 它是 UIView 子类，layerClass 为 CAMetalLayer。
/// 线程约束：所有实例方法都必须在主线程调用（内部依赖 window/bounds）。
@interface NLDustRenderer : UIView

/// 全局预热：主线程调用，首次时把 Metal 管线编译丢到后台线程。
+ (void)prewarmRenderer;

/// 全局就绪状态（NLDustReady 且 NLDustPipeline 非空）。
+ (BOOL)isReady;

/// 同步创建 MTLDevice / 编译着色器 / 建立管线。可重复调用，返回是否成功。
/// 内部用 NLDustPreparing 做一次性守卫，失败后不会重试。
+ (BOOL)prepareRenderer;

/// 指定初始化器。
/// @param image          源卡片位图（CGImageRef，会拷进 MTLTexture）
/// @param cardFrame      卡片在本视图坐标系里的矩形
/// @param particleCount  期望颗粒数（tiles 总数），会被 columns×rows 向下取整修正
/// @param duration       动画时长（秒）
/// @param distance       飘散距离（pt）
/// @param seed           随机种子
/// @return 失败（图像不可用 / 纹理过大 / 管线未就绪）时返回 nil
- (nullable instancetype)initWithImage:(CGImageRef)image
                             cardFrame:(CGRect)cardFrame
                         particleCount:(NSUInteger)particleCount
                              duration:(double)duration
                              distance:(double)distance
                                  seed:(float)seed;

/// 在首帧真正画出来之前，先画一帧 progress=0，确保纹理正确显示。
- (BOOL)primeFrame;

/// 最近一次 commit 的 command buffer 状态 == MTLCommandBufferStatusCompleted。
- (BOOL)hasCompletedFrame;

/// 最近一次 commit 的 command buffer 状态 == MTLCommandBufferStatusError，
/// 或根本没有 command buffer（视为失败）。
- (BOOL)hasFailedFrame;

/// 建立 CADisplayLink（60fps，common modes）并记录 startTime。
/// 已有 displayLink 时直接返回。
- (void)start;

/// 终止时先隐藏并移除 CAMetalLayer 宿主，再释放资源；幂等，不可重新启动。
- (void)invalidate;

/// 完成、失败或主动终止后调用一次（主线程）；先清空回调再调用以允许 owner 清理。
@property (nonatomic, copy, nullable) void (^completion)(void);

/// 绘制一帧。返回 NO 表示这一帧没有画出来（会被计入 skippedFrames）。
- (BOOL)drawProgress:(float)progress;

// —— 只读属性，逆向自 ivar ——
@property (nonatomic, strong, nullable) id<MTLTexture> texture;
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic) CGRect cardFrame;
@property (nonatomic) NSUInteger columns;
@property (nonatomic) NSUInteger rows;
@property (nonatomic) double duration;
@property (nonatomic) double distance;
@property (nonatomic) float seed;
@property (nonatomic) double startTime;
@property (nonatomic, strong, nullable) id<MTLCommandBuffer> lastCommand;
@property (nonatomic) NSUInteger skippedFrames;

@end

NS_ASSUME_NONNULL_END
