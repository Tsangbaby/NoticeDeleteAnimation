//
//  NLStatusProbe.h
//  NoticeDeleteAnimation — 通知消散
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单例探针：周期性刷新诊断 plist，并在启动后补装横幅 hook。
@interface NLNotificationStatusProbe : NSObject
+ (instancetype)shared;   // 0xc39c
- (void)scan;             // 0xc3ec
@end

NS_ASSUME_NONNULL_END
