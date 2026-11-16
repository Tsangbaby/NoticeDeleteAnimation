//
//  NLRootListController.m
//  NoticeListTweak Preferences — 通知消散
//
//  逆向自 1.0.1~test14。原始地址写在每个方法上方。
//

#import "NLRootListController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const kNLPreferencesDomain = @"com.example.noticelisttweak";
static NSString *const kNLStatusPlistPath =
    @"/var/mobile/Library/Preferences/com.example.noticelisttweak.banner-status.plist";
static NSString *const kNLPreferencesChangedNotification =
    @"com.example.noticelisttweak/preferencesChanged";


#pragma mark - NLRootListController

@implementation NLRootListController

// 0x6dd4
- (NSArray *)specifiers
{
    if (!_specifiers) {
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self bundle:bundle];
        [self setTitle:@"通知消散"];
    }
    return _specifiers;
}

// 0x6ea4
- (void)showBannerStatus
{
    NLBannerStatusController *controller = [[NLBannerStatusController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

// 0x6f14 —— 覆盖 PSListController 的读取：直接从 CFPreferences 拿值，
// 避免 cfprefsd 缓存导致开关显示滞后。
- (id)readPreferenceValue:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    if (![key isKindOfClass:[NSString class]] || key.length == 0) {
        return [specifier propertyForKey:@"default"];
    }

    CFStringRef domain = (__bridge CFStringRef)kNLPreferencesDomain;
    CFPreferencesAppSynchronize(domain);
    CFTypeRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    if (value) {
        id result = (__bridge_transfer id)value;
        return result;
    }
    return [specifier propertyForKey:@"default"];
}

// 0x7034
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    if (![key isKindOfClass:[NSString class]] || key.length == 0) {
        [super setPreferenceValue:value specifier:specifier];
        return;
    }

    CFStringRef domain = (__bridge CFStringRef)kNLPreferencesDomain;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             domain);
    CFPreferencesAppSynchronize(domain);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kNLPreferencesChangedNotification,
        NULL, NULL, true);

    [super setPreferenceValue:value specifier:specifier];
}

@end
