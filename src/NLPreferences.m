//
//  NLPreferences.m
//  NoticeDeleteAnimation — 通知消散
//
//  逆向自 1.0.1~test14。原始地址写在每个函数上方。
//

#import "NLPreferences.h"
#import "NLWithdrawalEffect.h"
#import <objc/runtime.h>

NSString *const NLAppID = @"com.tsangbaby.noticedeleteanimation";

// ---------------------------------------------------------------- 全局配置
// 二进制里的 __ZL* 变量，地址见注释。全部由 NLLoadPreferences 写入。
NSUInteger NLDustParticleLimit = 14000;   // 0x263b0
double NLDustDistance = 110.0;            // 0x263b8
double NLAnimationDuration = 1.3;         // 0x263c0
BOOL NLAnimationEnabled = YES;            // 0x263c8

// 图标
BOOL NLIconDustEnableState = YES;         // 0x26490
double NLIconDustDuration = 1.3;          // 0x26498
double NLIconDustDistance = 110.0;        // 0x264a0
NSUInteger NLIconDustParticles = 6000;    // 0x264a8

// 偏好缓存（NLPreference 里 0.25s 节流）
BOOL NLPreferenceBanner = YES;            // 0x264b0
BOOL NLPreferenceEnabled = YES;           // 0x264b1
double NLPreferenceReadAt = 0.0;          // 0x26600

// 粒子预算
NSUInteger NLReservedParticles = 0;       // 0x264c8
NSUInteger NLBatchParticleLimit = 0;      // 0x264d0

// 快照关联键
char NLDustSnapshotKey;                   // 0x264c0


#pragma mark - 偏好加载

// 0x6290
void NLLoadPreferences(void)
{
    CFStringRef appID = (__bridge CFStringRef)NLAppID;
    CFPreferencesAppSynchronize(appID);

    // 默认值
    NLAnimationEnabled = YES;
    NLAnimationDuration = 1.3;
    NLDustDistance = 110.0;
    double particles = 14000.0;

    CFTypeRef enabledRef = CFPreferencesCopyAppValue(CFSTR("Enabled"), appID);
    CFTypeRef durationRef = CFPreferencesCopyAppValue(CFSTR("DustDuration"), appID);
    CFTypeRef distanceRef = CFPreferencesCopyAppValue(CFSTR("DustDistance"), appID);
    CFTypeRef particlesRef = CFPreferencesCopyAppValue(CFSTR("DustParticles"), appID);

    if (enabledRef && CFGetTypeID(enabledRef) == CFBooleanGetTypeID()) {
        NLAnimationEnabled = CFBooleanGetValue(enabledRef) ? YES : NO;
    }
    if (durationRef && CFGetTypeID(durationRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(durationRef, kCFNumberDoubleType, &NLAnimationDuration);
    }
    if (distanceRef && CFGetTypeID(distanceRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(distanceRef, kCFNumberDoubleType, &NLDustDistance);
    }
    if (particlesRef && CFGetTypeID(particlesRef) == CFNumberGetTypeID()) {
        CFNumberGetValue(particlesRef, kCFNumberDoubleType, &particles);
    }

    if (enabledRef) CFRelease(enabledRef);
    if (durationRef) CFRelease(durationRef);
    if (distanceRef) CFRelease(distanceRef);
    if (particlesRef) CFRelease(particlesRef);

    // 时长钳制到 [0.7, 2.5]，否则回落 1.3
    if (!isfinite(NLAnimationDuration) ||
        NLAnimationDuration < 0.7 || NLAnimationDuration > 2.5) {
        NLAnimationDuration = 1.3;
    }
    // 距离钳制到 [40, 200]，否则回落 110
    if (!isfinite(NLDustDistance) ||
        NLDustDistance < 40.0 || NLDustDistance > 200.0) {
        NLDustDistance = 110.0;
    }
    // 粒子钳制到 [4000, 20000]，否则回落 14000
    if (!isfinite(particles) || particles < 4000.0 || particles > 20000.0) {
        particles = 14000.0;
    }
    NLDustParticleLimit = (NSUInteger)particles;
}


#pragma mark - 偏好查询

// 0x10a94
BOOL NLPreference(NSString *key)
{
    double now = CACurrentMediaTime();
    if (NLPreferenceReadAt > 0 && (now - NLPreferenceReadAt) < 0.25) {
        return [key isEqual:@"Enabled"] ? NLPreferenceEnabled : NLPreferenceBanner;
    }
    NLPreferenceReadAt = now;

    CFStringRef appID = (__bridge CFStringRef)NLAppID;
    CFPreferencesAppSynchronize(appID);

    CFTypeRef bannerRef = CFPreferencesCopyAppValue(CFSTR("BannerDustEnabled"), appID);
    CFTypeRef enabledRef = CFPreferencesCopyAppValue(CFSTR("Enabled"), appID);

    if (bannerRef && CFGetTypeID(bannerRef) == CFBooleanGetTypeID()) {
        NLPreferenceBanner = CFBooleanGetValue(bannerRef) ? YES : NO;
    } else {
        NLPreferenceBanner = YES;
    }
    if (enabledRef && CFGetTypeID(enabledRef) == CFBooleanGetTypeID()) {
        NLPreferenceEnabled = CFBooleanGetValue(enabledRef) ? YES : NO;
    } else {
        NLPreferenceEnabled = YES;
    }

    if (bannerRef) CFRelease(bannerRef);
    if (enabledRef) CFRelease(enabledRef);

    return [key isEqual:@"Enabled"] ? NLPreferenceEnabled : NLPreferenceBanner;
}


#pragma mark - 状态记录

// 0x10c40
static NSMutableDictionary<NSString *, NSNumber *> *NLEvents;   // 0x265d8
static NSString *NLLastEvent;                                   // 0x265e0

void NLWithdrawalRecord(NSString *event)
{
    if (!event || ![NSThread isMainThread]) {
        return;
    }
    if (!NLEvents) {
        NLEvents = [NSMutableDictionary dictionary];
    }
    NSUInteger count = [NLEvents[event] unsignedIntegerValue];
    NLEvents[event] = [NSNumber numberWithUnsignedLong:count + 1];
    NLLastEvent = event;
}


#pragma mark - 可见性 / 重复检测

// 0x57b8
BOOL NLExistingNotificationSnapshotActive(UIView *view)
{
    if (![view isKindOfClass:[UIView class]]) {
        return NO;
    }
    UIView *node = view;
    while (node) {
        if (objc_getAssociatedObject(node, &NLDustSnapshotKey) != nil) {
            return YES;
        }
        node = node.superview;
    }
    return NO;
}

// 0x12b04
BOOL NLVisible(UIView *view)
{
    if (![view isKindOfClass:[UIView class]]) {
        return NO;
    }
    if (!view.window || view.window.isHidden) {
        return NO;
    }

    UIView *node = view;
    while (node) {
        if (node.isHidden) {
            return NO;
        }
        if (node.alpha < 0.02) {          // 0x195c0
            return NO;
        }
        node = node.superview;
    }

    UIScreen *screen = view.window.screen;
    CGRect inScreen = [view convertRect:view.bounds
                      toCoordinateSpace:screen.coordinateSpace];
    CGRect clipped = CGRectIntersection(inScreen, screen.bounds);

    if (!isfinite(inScreen.origin.x) || !isfinite(inScreen.origin.y) ||
        !isfinite(inScreen.size.width) || !isfinite(inScreen.size.height)) {
        return NO;
    }
    // 0x12dd8: 高 >= 12；0x12de4: 宽 >= 16
    if (inScreen.size.height < 12.0 || inScreen.size.width < 16.0) {
        return NO;
    }
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) {
        return NO;
    }
    return YES;
}
