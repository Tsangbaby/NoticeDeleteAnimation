//
//  NLWithdrawalEffect.h
//  NoticeListTweak — 通知消散
//
//  逆向自 1.0.1~test14。
//
//  这是所有消散动画的公共引擎：把某个 source view 的位图快照放到一个独立的
//  全屏 overlay 窗口里，用 NLDustRenderer 播放颗粒消散，同时把原 view 用
//  CALayer mask 隐藏起来。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NLDustRenderer, NLWithdrawalWindow, NLWithdrawalEffect;

/// 消散的结束方式，由调用方（各 hook）提供，tick 里轮询。
typedef NS_ENUM(NSInteger, NLDisposition) {
    NLDispositionPending = 0,     // 还没决定，继续等
    NLDispositionProceed = 1,     // 原生动画已经移除，可以开始
    NLDispositionAbort = 2,       // 放弃，直接 finish
};

/// tick 里回调，返回当前 disposition。
typedef NLDisposition (*NLDispositionFn)(NLWithdrawalEffect *effect);

@interface NLWithdrawalEffect : NSObject

// —— 工厂 ——
/// 无缓存快照版本，等价于传 CGRectZero 的 cachedImage 版本。
+ (nullable instancetype)prepareView:(nullable UIView *)view
                              source:(nullable id)source
                          preference:(NSString *)preference;

/// 主工厂。屏幕坐标系下的快照会被换算到 overlay 窗口坐标系。
/// @param view        要消散的源视图（必须可见、有 window）
/// @param cachedImage 已有快照（用于 preswipe 缓存）；nil 则现抓
/// @param screenFrame 快照对应的屏幕矩形；CGRectZero 表示"用 view.bounds 现抓"
/// @param source      归属对象（请求/图标/manager），用于去重
/// @param preference  偏好键（@"list" / @"banner" / @"icon" / @"lockScreen" / @"island"）
+ (nullable instancetype)prepareView:(nullable UIView *)view
                         cachedImage:(nullable UIImage *)cachedImage
                         screenFrame:(CGRect)screenFrame
                              source:(nullable id)source
                          preference:(NSString *)preference;

+ (BOOL)isActiveForView:(nullable UIView *)view;
+ (BOOL)isPendingForOwner:(nullable id)owner payload:(nullable id)payload;
+ (void)cancelEffectsForView:(nullable UIView *)view;

// —— 生命周期 ——
/// 原生删除动画已结束，建立 CADisplayLink 并立即 tick 一次。
- (void)beginAfterNativeRemoval;
- (void)cancel;     // == finish
- (void)finish;

// —— 属性 ——
@property (nonatomic, strong, nullable) id owner;
@property (nonatomic, strong, nullable) id payload;
@property (nonatomic, weak,   nullable) id context;
@property (nonatomic, copy,   nullable) NSString *identity;
@property (nonatomic, strong, nullable) UIView *sourceView;
@property (nonatomic, assign, nullable) NLDispositionFn disposition;
@property (nonatomic) BOOL wasRegistered;
@property (nonatomic) BOOL requiresRemovalConfirmation;

@property (nonatomic, strong, nullable) NLWithdrawalWindow *overlay;
@property (nonatomic, strong, nullable) UIImageView *cover;
@property (nonatomic, strong, nullable) NLDustRenderer *renderer;
@property (nonatomic, strong, nullable) CADisplayLink *link;
@property (nonatomic) double preparedAt;
@property (nonatomic) double startedAt;
@property (nonatomic) double duration;
@property (nonatomic, copy,   nullable) NSString *preference;
@property (nonatomic) BOOL finished;
@property (nonatomic) BOOL nativeCompleted;
@property (nonatomic, strong, nullable) CALayer *sourceCoverMask;
@property (nonatomic, strong, nullable) CALayer *savedSourceMask;
@property (nonatomic) BOOL removalConfirmed;
@property (nonatomic) BOOL preswipeCached;

@end

/// 承载消散动画的独立窗口，层级比源窗口高 1。
@interface NLWithdrawalWindow : UIWindow
@end

NS_ASSUME_NONNULL_END
