//
//  NLIconDust.h
//  NoticeDeleteAnimation — 通知消散
//
//  桌面图标卸载时的消散。逆向自 1.0.1~test14。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 0x9f24 —— 安装 SBHIconManager 的卸载/移除 hook。
BOOL NLInstallIconDustHooks(void);

NS_ASSUME_NONNULL_END
