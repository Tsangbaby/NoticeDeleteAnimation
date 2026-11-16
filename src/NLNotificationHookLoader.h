//
//  NLNotificationHookLoader.h
//  NoticeDeleteAnimation — 通知消散
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 全局单例，负责在 SpringBoard 里安装全部 hook，并在失败时最多重试 15 次。
@interface NLNotificationHookLoader : NSObject

+ (instancetype)sharedLoader;

/// 0x591c —— 主线程安装入口。非主线程会转发到主线程。
/// 会先校验 NCNotificationListView 的 removeViewAtIndex: 签名，
/// 再调用 NLInstallIconDustHooks / NLInstallBannerDustHooks 等。
- (void)tryInstalling;

/// 0x61d4 —— 3 秒后重试，最多 15 次。
- (void)retryInstalling;

/// 0x6238 —— 后台预编译 Metal 管线。
- (void)prepareDustRenderer;

- (void)applicationDidBecomeActive:(NSNotification *)note;
- (void)preferencesChanged:(NSNotification *)note;

@property (nonatomic) BOOL installRetryScheduled;
@property (nonatomic) NSUInteger installRetriesFired;

@end

NS_ASSUME_NONNULL_END
