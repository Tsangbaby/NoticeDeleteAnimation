//
//  NLStatusProbe.m
//  NoticeListTweak — 通知消散
//
//  逆向自 1.0.1~test14。
//

#import "NLStatusProbe.h"
#import "NLBannerDust.h"

static NLNotificationStatusProbe *NLProbeInstance;   // 0x26598
static BOOL NLProbeScheduled;                        // 0x265a0
static NSUInteger NLBannerProbeCount;                // 0x265a8


@implementation NLNotificationStatusProbe

// 0xc39c
+ (instancetype)shared
{
    if (!NLProbeInstance) {
        NLProbeInstance = [NLNotificationStatusProbe new];
    }
    return NLProbeInstance;
}

// 0xc3ec
- (void)scan
{
    NLProbeScheduled = NO;
    NLBannerProbeCount = NLBannerProbeCount + 1;

    // 0xc41c: cmp count,#0x14 ; ccmp (count&3),#0,#4,hs ; b.ne skip
    // 即 count < 20 时每次都装，count >= 20 后每 4 次装一次。
    if (NLBannerProbeCount < 20 || (NLBannerProbeCount & 3) == 0) {
        NLInstallBannerDustHooks();
    }

    NLBannerWriteStatus();

    if (!NLProbeScheduled) {
        NLProbeScheduled = YES;
        [self performSelector:@selector(scan) withObject:nil afterDelay:2.0];
    }
}

@end
