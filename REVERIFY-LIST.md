# REVERIFY 清单

以下位置是从反汇编**推断**而非直接证据的地方。首次真机验证时优先看这些。

| 文件:行 | 内容 |
|---|---|
| src/NLNotificationDismissalSnapshot.h:9 | ". |
| src/NLBannerDust.m:110 | `%lu` 的确切来源没完全定死，这里是"两个标识符长度的组合"， |
| src/NLBannerDust.m:245 | 0.48/0.45 的语义按"屏幕占比下限"还原， |
| src/NLNotificationListHooks.m:123 | the binary logs `exception.name` from the catch pad and |
| src/NLNotificationListHooks.m:157 | the landing pad is a catch-all (no type filter) that |
| src/NLNotificationListHooks.m:202 | see NLRemoveView |
| src/NLNotificationListHooks.m:298 | catch-all pad: every queued snapshot is torn down, the |
| src/NLNotificationDismissalSnapshot.m:110 | the shift-by-4 form is odd; it is exactly what the binary does |
| src/NLNotificationDismissalSnapshot.m:335 | _sourceList is *not* cleared here in the binary; it is only |
| src/NLNotificationHookLoader.m:128 | 二进制在 0x5cbc 用 `cmp w23,#0x40`（'@'）判定 accessor 返回值， |
