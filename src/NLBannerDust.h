//
//  NLBannerDust.h
//  NoticeListTweak — 通知消散
//
//  BannerKit（通知横幅）消散。逆向自 1.0.1~test14。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 0xc478 —— 安装 BNContentViewController 的三个 hook。
/// 返回是否全部装好。
BOOL NLInstallBannerDustHooks(void);

/// 0xc688 —— 把当前诊断状态写到
/// /var/mobile/Library/Preferences/com.example.noticelisttweak.banner-status.plist
void NLBannerWriteStatus(void);

NS_ASSUME_NONNULL_END
