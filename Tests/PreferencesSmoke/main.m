// Simulator: real framework; no UIApplicationMain or fake superclass.
#import <UIKit/UIKit.h>
#import "NLRootListController.h"
#import <objc/runtime.h>

static void require(BOOL ok, NSString *why) {
    if (!ok) { fprintf(stderr, "PREFERENCES NATIVE FAIL: %s\n", why.UTF8String); exit(1); }
}
static void contains(NSString *text, NSArray<NSString *> *parts) {
    for (NSString *part in parts) require([text containsString:part], [@"missing text: " stringByAppendingString:part]);
}
int main(int argc, char **argv) {
  @autoreleasepool { @try {
    require(argc == 3, @"arguments: actual bundle, actual registration plist");
    for (Class cls in @[[PSListController class], [PSSpecifier class]]) {
        const char *image = class_getImageName(cls);
        require(image && [@(image) containsString:@"/Preferences.framework/Preferences"], @"real Preferences image required");
        printf("FRAMEWORK %s %s\n", class_getName(cls), image);
    }
    NSString *path = [@(argv[1]) stringByStandardizingPath];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    NSDictionary *entry = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])][@"entry"];
    require(bundle && [entry isKindOfClass:NSDictionary.class], @"missing bundle/entry");
    require([entry[@"bundle"] isEqual:@"NoticeListTweak"] && [entry[@"detail"] isEqual:@"NLRootListController"], @"registration identity");
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[bundle pathForResource:@"Root" ofType:@"plist"]];
    NSArray *items = plist[@"items"];
    require([items isKindOfClass:NSArray.class] && items.count > 0, @"Root.items array required");

    NSError *error = nil;
    require(bundle.isLoaded || [bundle loadAndReturnError:&error], error.description ?: @"NSBundle load failed");
    Class principal = bundle.principalClass;
    require([NSStringFromClass(principal) isEqual:@"NLRootListController"], @"principal class");
    require([principal isSubclassOfClass:PSListController.class], @"real superclass");
    require([[[NSBundle bundleForClass:principal] bundlePath] isEqual:path], @"principal bundle");
    Class selected = NSClassFromString(entry[@"detail"]);
    require(selected == principal, @"selected detail");
    printf("REGISTRATION NSBundle-principal selected=%s\n", class_getName(selected));
    NLRootListController *root = [selected new];
    NSArray *specs = root.specifiers;
    require(specs.count == items.count, @"Root.items count");
    Ivar model = class_getInstanceVariable(PSListController.class, "_specifiers");
    require(model && object_getIvar(root, model) == specs && root.specifiers == specs, @"superclass model/cache");
    NSDictionary *names = @{@"Enabled":@"通知消散", @"DustDuration":@"消散时长（秒）", @"DustDistance":@"飘散距离", @"DustParticles":@"颗粒精细度", @"BannerRuntimeStatus":@"横幅运行状态"};
    NSMutableSet *seen = [NSMutableSet set];
    for (PSSpecifier *s in specs) {
        NSString *ident = [s propertyForKey:@"key"] ?: [s propertyForKey:@"id"];
        if (ident && names[ident]) {
            require([s.name isEqual:names[ident]], @"Enabled/slider/status names");
            [seen addObject:ident];
        }
    }
    require(seen.count == names.count && [root respondsToSelector:@selector(showBannerStatus)], @"required controls and status action present");

    Class statusClass = NSClassFromString(@"NLBannerStatusController");
    require(statusClass && [NSBundle bundleForClass:statusClass] == bundle, @"actual status controller loaded");
    NLBannerStatusController *status = [statusClass new];
    // Pure formatter: no preferences IO or clipboard writes.
    NSString *empty = [status statusTextForStatus:nil events:nil];
    NSString *label = @"设置组件版本：1.0.1+rebuild1";
    contains(empty, @[label, @"尚未读到", @"SpringBoard 运行状态"]);
    NSDictionary *events = @{@"native-dismiss-seen":@7, @"snapshot-ready":@11, @"dust-started":@13};
    NSDictionary *fixture = @{@"build":@"fixture-build", @"loaded":@YES, @"updatedAt":@"fixture-time", @"installed":@YES, @"trollOpenCurrentHook":@NO, @"metalReady":@NO, @"reduceMotion":@YES, @"lastSource":@"fixture-source", @"lastViewClass":@"FixtureCard", @"events":events};
    contains([status statusTextForStatus:fixture events:events], @[label, @"桌面运行版本：fixture-build已加载", @"更新：fixture-time", @"系统横幅：已接入", @"TrollOpen：未接入", @"Metal：未就绪", @"减弱动态效果：开（跳过效果）", @"系统收回：7 次", @"快照就绪：11 次", @"启动颗粒：13 次", @"来源：fixture-source", @"卡片类：FixtureCard"]);
    contains([status statusTextForStatus:@{} events:@{@"dust-started":@"invalid"}], @[label, @"桌面运行版本：未知（请重新载入桌面）", @"系统收回：0 次", @"启动颗粒：0 次", @"Metal：未加载", @"来源：未知"]);
    UIApplication *app = [UIApplication sharedApplication];
    if (app.connectedScenes.count && ![[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/Preferences/com.example.noticelisttweak.banner-status.plist"]) {
        [root loadViewIfNeeded];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
        [root showBannerStatus];
        require([nav.topViewController isKindOfClass:statusClass], @"status action pushes actual controller");
        NLBannerStatusController *shown = (id)nav.topViewController;
        [shown loadViewIfNeeded];
        [shown refreshStatus];
        contains(shown.statusText.text, @[label, @"尚未读到"]);
    } else puts("UI SKIP: no safe empty-data UIApplication scene");
    printf("PREFERENCES NATIVE PASS: %lu specifiers; NSBundle-principal, real framework/model, empty/synthetic status\n", (unsigned long)specs.count);
    return 0;
  } @catch (NSException *e) {
    fprintf(stderr, "PREFERENCES NATIVE FAIL: %s: %s\n", e.name.UTF8String, e.reason.UTF8String);
    return 1;
  } }
}
