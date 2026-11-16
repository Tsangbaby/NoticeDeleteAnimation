//
//  NLPreferences.h
//  NoticeListTweak — 通知消散
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NLAppID;   // @"com.example.noticelisttweak"

// 全局配置（二进制里的 __ZL* 变量）
extern NSUInteger NLDustParticleLimit;   // 0x263b0
extern double     NLDustDistance;        // 0x263b8
extern double     NLAnimationDuration;   // 0x263c0
extern BOOL       NLAnimationEnabled;    // 0x263c8
extern BOOL       NLIconDustEnableState; // 0x26490
extern double     NLIconDustDuration;    // 0x26498
extern double     NLIconDustDistance;    // 0x264a0
extern NSUInteger NLIconDustParticles;   // 0x264a8
extern BOOL       NLPreferenceBanner;    // 0x264b0
extern BOOL       NLPreferenceEnabled;   // 0x264b1
extern double     NLPreferenceReadAt;    // 0x26600
extern NSUInteger NLReservedParticles;   // 0x264c8
extern NSUInteger NLBatchParticleLimit;  // 0x264d0
extern char       NLDustSnapshotKey;     // 0x264c0
extern char       NLSourceEffectKey;     // 0x265f8（定义在 NLWithdrawalEffect.m）

/// 0x6290 —— 读取全部偏好到 static 缓存，并做范围钳制。
void NLLoadPreferences(void);

/// 0x10a94 —— 带 0.25s 节流的开关查询。key 为 @"Enabled" 时返回总开关，
/// 其余（@"banner"/@"list"/…）返回 @"BannerDustEnabled"。
BOOL NLPreference(NSString *key);

/// 0x10c40 —— 主线程累加事件计数（诊断用）。
void NLWithdrawalRecord(NSString *event);

/// 0x57b8 —— view 或任一祖先上是否已挂着 NLDustSnapshotKey 关联对象。
BOOL NLExistingNotificationSnapshotActive(UIView *_Nullable view);

/// 0x12b04 —— 视图在屏幕上是否真实可见（含祖先 hidden/alpha 与屏幕交集）。
BOOL NLVisible(UIView *_Nullable view);

NS_ASSUME_NONNULL_END
