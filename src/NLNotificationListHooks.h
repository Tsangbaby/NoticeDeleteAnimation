//
//  NLNotificationListHooks.h
//  NoticeListTweak — 通知消散
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

// 原始实现槽（MSHookMessageEx 写入）
extern IMP NLOriginalRemove;             // 0x264e8
extern IMP NLOriginalRemoveDisplaced;    // 0x264f0
extern IMP NLOriginalClearAll;           // 0x264f8

// 替换实现
extern void NLRemoveView(id self, SEL _cmd, NSUInteger index, BOOL animated);      // 0x67b4
extern void NLRemoveDisplacedView(id self, SEL _cmd, NSUInteger index, BOOL animated, BOOL displaced); // 0x693c
extern void NLClearAll(id self, SEL _cmd);                                         // 0x6ad8

NS_ASSUME_NONNULL_END
