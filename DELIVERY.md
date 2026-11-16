# 交付说明

## 结论

`通知消散 1.0.1~test14` 的源码已从二进制完整重建为可维护工程。
**符号未剥离**是关键前提：245 个函数符号、完整 ObjC 元数据、内嵌 Metal 着色器源码全部可用。

**当前状态：静态逆向完成 + 语法验证通过，未编译、未真机验证。**

## 做到了什么

| 项 | 状态 |
|---|---|
| 反汇编基础设施 | 自写 chained-fixup 解析器 + 注释器 + ObjC 元数据导出器 |
| 函数覆盖 | 245 / 245（主插件），11 / 11（设置 bundle） |
| Metal 着色器 | 逐字节原样恢复（71 行） |
| 类结构 | 9 个类的 ivar 偏移、方法、属性全部还原 |
| 字符串常量 | 208 条 C 字符串 + 193 条 CFString 全部还原 |
| 源码规模 | 约 5100 行 ObjC（含注释与原始地址标注） |
| 语法验证 | 15 个 .m 文件全部通过 clang `-fsyntax-only`（含 `-Wall -Wextra`） |
| 交叉校验 | 源码引用的 selector / CFString 全部在二进制中存在 |

## 没做到什么

- **没有编译过**。本机无 iOS SDK / theos。首次 `make package` 预期需要修私有 API 声明。
- **没有真机验证**。所有行为结论来自静态反汇编。
- **10 处 REVERIFY 标记**是推断而非证据，见 `REVERIFY-LIST.md`。
- 各 hook 的具体私有类方法是否存在于目标 iOS 版本，只能靠运行时的
  `class_getInstanceMethod` 结果决定，静态无法证明。

## 工程结构

```
notice-rebuild/
├── README.md               工程总览
├── BUILD.md                构建步骤 + 首次构建预期问题
├── REVERSE-NOTES.md        逆向方法、常量表、架构还原
├── REVERIFY-LIST.md        所有推断点清单
├── INDEX.md                调查索引
├── src/                    主插件 13 个源文件
├── prefs/                  PreferenceBundle 子工程
├── layout/                 打包资源（plist、图标）
├── stubs/                  clang 语法检查用的最小桩头
├── control / Makefile      打包配置
├── check-syntax.sh         语法检查
├── collect-reverify.sh     推断点汇总
└── work/                   逆向工作区（证据）
```

## 关键发现（对后续维护有用的）

1. **原实现是单个 .m 文件**。所有 `__ZL*` 变量都是同一编译单元的 file-scope 符号。
   重建时拆成了 13 个文件，变量改成了 `extern` + 单一定义。

2. **两条完全独立的消散链路**：
   - 通知列表（`NCNotificationListView`）走 `NLNotificationDismissalSnapshot`
   - 横幅/图标/锁屏/灵动岛走 `NLWithdrawalEffect`

   前者用 `CADisplayLink` + `NLDustRenderer`，后者用独立 `UIWindow` overlay。
   两者共享 `NLDustRenderer` 和 Metal 管线（全局单例）。

3. **强制 `animated:NO` 的手法**：所有 hook 在成功准备效果后，把原方法的
   `animated` 参数改成 `NO`，让系统跳过原生动画，只保留颗粒动画。
   这是"替换"而非"叠加"的关键。

4. **`rnNoORV` 字符串**是类型编码白名单（`r`/`n`/`N`/`o`/`O`/`R`/`V`），
   用来判断 method 的返回类型是否可能是 void / struct。多处复用。

5. **粒子预算三层**：单次上限 `NLDustParticleLimit`（默认 14000）、
   批次上限 `NLBatchParticleLimit`、全局池 42000。低于 3000 直接放弃。

6. **诊断通道**是纯文件式的：SpringBoard 写
   `/var/mobile/Library/Preferences/com.example.noticelisttweak.banner-status.plist`，
   设置页读。不涉及进程间通信，也不保存通知正文。

## 建议的下一步

1. 在 macOS 上用 theos + iOS 16.5 SDK 跑 `make package`，按 `BUILD.md` 修编译错误。
2. 首次安装前把 `DustShader.metal` 转成 C 字符串（`BUILD.md` 有脚本）。
3. 装上后先看设置页「横幅运行状态」是否显示 `已加载` + `Metal：就绪`，
   这一步不需要触发任何动画就能判断管线是否正常。
4. 再按单条通知删除 → 横幅收起 → 图标卸载 → 锁屏清除的顺序逐个验证。
5. 每个 `REVERIFY` 点都在真机上对照一次，确认后从清单里划掉。
