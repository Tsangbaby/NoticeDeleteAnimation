//
//  NLRootListController.h
//  NoticeDeleteAnimation Preferences — 通知消散
//
//  逆向自 1.0.1~test14 的 PreferenceBundle。
//

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

NS_ASSUME_NONNULL_BEGIN

/// 根列表。specifiers 全部来自 bundle 内的 Root.plist。
@interface NLRootListController : PSListController
- (void)showBannerStatus;
@end

/// 「横幅运行状态」详情页：一个只读 UITextView 展示 SpringBoard 写下的诊断 plist。
@interface NLBannerStatusController : PSListController
@property (nonatomic, strong, nullable) UITextView *statusText;
- (void)refreshStatus;
- (void)copyStatus;
- (NSString *)statusTextForStatus:(NSDictionary *)status
                           events:(NSDictionary *)events;
@end

NS_ASSUME_NONNULL_END
