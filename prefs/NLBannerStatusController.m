//
//  NLBannerStatusController.m
//  NoticeDeleteAnimation Preferences — 通知消散
//
//  逆向自 1.0.1~test14。原始地址写在每个方法上方。
//

#import "NLRootListController.h"

static NSString *const kNLStatusPlistPath =
    @"/var/mobile/Library/Preferences/com.tsangbaby.noticedeleteanimation.banner-status.plist";
static NSString *const kNLBuildVersion __attribute__((unused)) = @"0.1.0~alpha8";

// 事件键 → 中文说明（顺序与原实现一致）
static __attribute__((unused)) NSArray<NSArray<NSString *> *> *NLEventDescriptions(void)
{
    static NSArray<NSArray<NSString *> *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @[
            @[@"withdrawal-seen",  @"收到通知收回"],
            @[@"snapshot-ready",   @"卡片快照就绪"],
            @[@"dust-started",     @"已启动颗粒"],
            @[@"skip:unavailable", @"界面、开关或 Metal 不可用"],
            @[@"skip:duplicate",   @"已由同一快照处理"],
            @[@"skip:no-real-card",@"未识别系统横幅卡片"],
            @[@"skip:snapshot-failed", @"卡片截图失败"],
            @[@"skip:metal-first-frame", @"GPU 首帧提交失败"],
            @[@"skip:effect-limit", @"达到同时播放上限"],
            @[@"skip:reused-source", @"卡片已换成新消息，取消旧效果"],
            @[@"skip:native-not-removed-or-frame", @"原卡片未撤下或首帧失败"],
            @[@"skip:trollopen-no-owned-view", @"TrollOpen 已收回，但未找到所属卡片"],
            @[@"skip:aperture-no-owned-view", @"Nice 已收回，但未找到所属卡片"],
        ];
    });
    return table;
}

// 布尔 → 接入状态文案
static NSString *NLHookState(id value)
{
    if (!value) {
        return @"未加载";
    }
    return [value boolValue] ? @"已接入" : @"未接入";
}

static NSString *NLBoolState(id value, NSString *yes, NSString *no)
{
    if (!value) {
        return @"未加载";
    }
    return [value boolValue] ? yes : no;
}

static NSString *NLCountText(NSDictionary *events, NSString *key)
{
    NSNumber *n = events[key];
    if (![n isKindOfClass:[NSNumber class]]) {
        return @"0";
    }
    return [NSString stringWithFormat:@"%lu", (unsigned long)n.unsignedIntegerValue];
}


@implementation NLBannerStatusController

// 0x5ad4
- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    // This custom status page owns a UIView, not PSListController's table view.
    [(UIViewController *)self setView:root];
    root.backgroundColor = [UIColor systemBackgroundColor];

    UITextView *text = [[UITextView alloc] initWithFrame:root.bounds];
    [self setStatusText:text];

    text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    text.editable = NO;
    text.selectable = YES;
    text.backgroundColor = [UIColor systemBackgroundColor];
    text.textColor = [UIColor labelColor];
    text.font = [UIFont systemFontOfSize:15.0];

    [root addSubview:text];

    self.title = @"横幅运行状态";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                        style:UIBarButtonItemStylePlain
                                       target:self
                                       action:@selector(refreshStatus)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"复制"
                                        style:UIBarButtonItemStylePlain
                                       target:self
                                       action:@selector(copyStatus)];
}

// 0x5fa4
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshStatus];
}

// 0x5ff4
- (void)refreshStatus
{
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kNLStatusPlistPath];
    NSDictionary *events = nil;
    if ([status[@"events"] isKindOfClass:[NSDictionary class]]) {
        events = status[@"events"];
    }

    self.statusText.text = [self statusTextForStatus:status events:events];
}

/// 0x5ff4 的文本拼装部分（原实现内联在 refreshStatus 里）。
- (NSString *)statusTextForStatus:(NSDictionary *)status
                           events:(NSDictionary *)events
{
    if (!status) {
        return @"设置组件版本：0.1.0~alpha8\n\n"
                "尚未读到 SpringBoard 运行状态。\n"
                "安装后请重新载入桌面，回到这里点刷新。若仍没有状态，请检查插件是否已启用 SpringBoard 注入。";
    }

    NSMutableString *out = [NSMutableString string];

    NSString *build = status[@"build"];
    if (![build isKindOfClass:[NSString class]]) {
        build = @"未知";
    }
    NSString *loaded = status[@"loaded"] ? @"已加载，等待通知收回" : @"（请重新载入桌面）";
    NSString *updated = status[@"updatedAt"] ? [status[@"updatedAt"] description] : @"未知";

    [out appendFormat:@"设置组件版本：0.1.0~alpha8\n桌面运行版本：%@%@\n更新：%@\n\n",
                     build, loaded, updated];

    [out appendString:@"模式：原生收回时消散\n插件倒计时：已取消\n\n"];

    [out appendFormat:@"系统横幅：%@\n"
                      @"TrollOpen：%@\n"
                      @"Nice 灵动通知：%@\n"
                      @"锁屏清除入口：%@\n"
                      @"通知集合删除：%@\n"
                      @"Metal：%@\n"
                      @"减弱动态效果：%@\n\n",
                     NLHookState(status[@"installed"]),
                     NLHookState(status[@"trollOpenCurrentHook"]),
                     NLHookState(status[@"apertureDismissHook"]),
                     NLHookState(status[@"cellClearHook"]),
                     NLHookState(status[@"collectionDeleteHook"]),
                     NLBoolState(status[@"metalReady"], @"就绪", @"未就绪"),
                     NLBoolState(status[@"reduceMotion"], @"开（跳过效果）", @"关")];

    NSDictionary *listStatus = [status[@"listSnapshot"] isKindOfClass:NSDictionary.class] ? status[@"listSnapshot"] : @{};
    [out appendFormat:@"列表尝试／无卡片／准备／启动：%@／%@／%@／%@\n",
        NLCountText(listStatus, @"attempts"), NLCountText(listStatus, @"noCard"),
        NLCountText(listStatus, @"prepared"), NLCountText(listStatus, @"started")];
    [out appendFormat:@"横幅请求解析／无请求／无卡片／捕获失败：%@／%@／%@／%@\n",
        NLCountText(events, @"requestresolved"), NLCountText(events, @"no_request"),
        NLCountText(events, @"nohost"), NLCountText(events, @"capturefail")];
    [out appendString:@"点击路由：尚未真机确认；unknown 是能力声明，不是点击次数。\n\n"];

    [out appendFormat:@"系统收回：%@ 次\n"
                      @"TrollOpen 收回：%@ 次\n"
                      @"Nice 收回：%@ 次\n"
                      @"锁屏清除：%@ 次\n"
                      @"通知项删除：%@ 次\n"
                      @"快照就绪：%@ 次\n"
                      @"启动颗粒：%@ 次\n\n"
                      @"来源：%@\n卡片类：%@\n\n",
                     NLCountText(events, @"native-dismiss-seen"),
                     NLCountText(events, @"trollOpenWithdrawals"),
                     NLCountText(events, @"apertureWithdrawals"),
                     NLCountText(events, @"clearCalls"),
                     NLCountText(events, @"deleteCalls"),
                     NLCountText(events, @"snapshot-ready"),
                     NLCountText(events, @"dust-started"),
                     status[@"lastSource"] ?: @"未知",
                     status[@"lastViewClass"] ?: @"未知"];

    [out appendString:@"按原来的方式收起横幅、上岛通知或删除锁屏通知，再点刷新。"
                      @"计数代表代码阶段，不代表真机动画已验证；原始诊断不保存消息内容。\n\n"
                      @"原始诊断：\n"];
    [out appendString:[status description]];

    return out;
}

// 0x6d08
- (void)copyStatus
{
    [UIPasteboard generalPasteboard].string = self.statusText.text;
}

// 0x6dc0

@end
