//
//  NLIslandDust.h
//  NoticeListTweak — 通知消散
//
//  灵动岛（TrollOpen / Nice "Aperture"）通知的消散。逆向自 1.0.1~test14。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 0x13c70 —— 安装灵动岛 hook。
void NLInstallIslandDustHooks(void);

/// 0x13c5c —— 是否正处于"灵动岛原生收起"过程中。
/// 横幅 hook 用它避让，避免同一次收起播两遍。
BOOL NLIslandDustNativeCloseInProgress(void);

/// 0x149fc —— 灵动岛诊断字典。
NSDictionary *NLIslandDustStatus(void);

NS_ASSUME_NONNULL_END
