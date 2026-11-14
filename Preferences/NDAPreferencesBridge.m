#import "NDAPreferencesBridge.h"

NSMutableArray<PSSpecifier *> *NDAMakeSettingsSpecifiers(
    PSListController *target, NSString *diagnosticsFooter) {
    PSSpecifier *general = [PSSpecifier groupSpecifierWithName:@"NoticeDeleteAnimation"];
    [general setProperty:@"Author: Tsangbaby\n仅控制通知删除动画。开启不表示当前系统的 hook 已兼容。" forKey:@"footerText"];

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"Enabled（启用）"
        target:target set:@selector(nda_setEnabled:specifier:)
        get:@selector(nda_readEnabled:) detail:Nil cell:PSSwitchCell edit:Nil];
    [enabled setProperty:@"Enabled" forKey:@"key"];
    [enabled setProperty:@"com.tsangbaby.noticedeleteanimation" forKey:@"defaults"];
    [enabled setProperty:@YES forKey:@"default"];
    [enabled setProperty:@"NDAEnabled" forKey:@"id"];

    PSSpecifier *diagnostics = [PSSpecifier groupSpecifierWithName:@"只读诊断"];
    [diagnostics setProperty:diagnosticsFooter forKey:@"footerText"];

    PSSpecifier *refresh = [PSSpecifier preferenceSpecifierNamed:@"刷新诊断"
        target:target set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    refresh.buttonAction = @selector(nda_refreshDiagnostics);

    PSSpecifier *privacy = [PSSpecifier groupSpecifierWithName:@"隐私说明"];
    [privacy setProperty:@"只读取 SpringBoard 保存的运行状态摘要、更新时间及进程 PID；不读取通知正文、账户或凭据，不联网，不导出日志。刷新不会重启 SpringBoard，也不会触发通知删除。" forKey:@"footerText"];
    return [NSMutableArray arrayWithObjects:general, enabled, diagnostics, refresh, privacy, nil];
}
