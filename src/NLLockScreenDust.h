//
//  NLLockScreenDust.h
//  NoticeListTweak — 通知消散
//
//  锁屏通知的消散。逆向自 1.0.1~test14。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 0x16a08 —— 安装锁屏 hook。
void NLInstallLockScreenDustHooks(void);

/// 0x16800 —— 这个视图是否已经被锁屏消散接管（避免与列表路径重复）。
BOOL NLLockScreenDustOwnsView(UIView *_Nullable view);

/// 0x17a78 —— 锁屏诊断字典。
NSDictionary *NLLockScreenDustStatus(void);

NS_ASSUME_NONNULL_END
