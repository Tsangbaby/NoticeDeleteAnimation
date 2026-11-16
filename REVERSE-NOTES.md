# 逆向记录：NoticeListTweak 1.0.1~test14

## 1. 样本身份

| 项 | 值 |
|---|---|
| 文件 | `通知消散1.0.1~test14_iphoneos-arm64e(1).deb` |
| SHA-256 | `d236a27a4381a08bcd91090a0d312908deff25dca0c8991756107105e08a73df` |
| 大小 | 225538 B |
| 包名 | `com.example.noticelisttweak` |
| 版本 | 1.0.1~test14 |
| Architecture | iphoneos-arm64e（RootHide） |
| Depends | mobilesubstrate, preferenceloader |

## 2. 二进制

| 项 | 主插件 dylib | 设置 bundle |
|---|---|---|
| 路径 | `Library/MobileSubstrate/DynamicLibraries/NoticeListTweak.dylib` | `Library/PreferenceBundles/NoticeListTweak.bundle/NoticeListTweak` |
| fat 大小 | 431152 B | 169216 B |
| slices | arm64 (202528 B) + arm64e (201776 B) | arm64 (71072) + arm64e (70912) |
| UUID (arm64) | `9632797E-3942-3970-AD1F-16709C0C0343` | — |
| 构建 SDK | ios 16.5 | — |
| 最低系统 | 15.0（由依赖与 API 使用推断） | — |
| 语言 | 纯 ObjC + C++ | 纯 ObjC |
| 符号 | **未剥离**，245 个函数符号 | 未剥离，11 个 |
| 链接方式 | `LC_DYLD_CHAINED_FIXUPS`（arm64e 认证指针） | 经典 `LC_DYLD_INFO_ONLY` |
| 依赖 | libsubstrate, UIKit, Foundation, CoreFoundation, QuartzCore, CoreGraphics, Metal, libobjc, libSystem, libc++ | Preferences, UIKit, Foundation, CoreFoundation |

主插件 `install_name` 为 `@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/NoticeListTweak.dylib`，确认是 RootHide 布局。

## 3. 恢复手段

符号未剥离是这次能重建的关键。做法：

1. **自写 `LC_DYLD_CHAINED_FIXUPS` 解析器**（`machofix.py`）。arm64e 的指针槽是认证指针 + 32 位目标 + 链式步长，r2 默认视图不应用重定位，直接读原始 8 字节只会得到编码值。解析后能把任意 `ldr xN, [xM, #off]` 解析到 class / selector / CFString / 全局变量。
2. **反汇编注释器**（`annotate.py`）。逐指令跟踪 `adrp/add/ldr/mov/str`，把 `objc_msgSend` 调用点还原成 `=> [receiver selector]` 形式，21041 行输出里 1130 个调用点被识别。
3. **ObjC 元数据导出器**（`objcdump.py`）。解析 `class_ro_t`（注意 arm64e 的布局：name 在 +0x18，methods 在 +0x20，ivars 在 +0x30，properties 在 +0x40），还原 ivar 偏移与类型编码。方法列表是**相对方法列表**（`entsize` 最高位为 1，name/types/imp 都是相对偏移）。
4. **经典 dyld 版本**（`annotate_classic.py`）用于设置 bundle，走 bind/lazy-bind/rebase 表。
5. **着色器**：`#include <metal_stdlib>` 起始的完整 Metal 源码以 NUL 结尾字符串形式内嵌在 `__TEXT,__const`（VA 0x195e8），`strings` 直接可见，完整原样导出。

## 4. 架构还原

```
%ctor (0x658c)  —— 仅 com.apple.springboard
 ├─ NLLoadPreferences()                       0x6290
 ├─ 注册 3 个通知观察（didFinishLaunching / prefsChanged / didBecomeActive）
 ├─ [loader tryInstalling]                    0x591c
 │    ├─ installListHooksIfPossible           0x5968–0x61b8
 │    │    ├─ NCNotificationListView 签名校验
 │    │    ├─ MSHookMessageEx removeViewAtIndex:animated:                → NLRemoveView
 │    │    ├─ MSHookMessageEx removeViewAtIndex:animated:isHorizontallyDisplaced: → NLRemoveDisplacedView
 │    │    └─ MSHookMessageEx clearAll (NCNotificationMasterList)        → NLClearAll
 │    ├─ NLInstallIconDustHooks()             0x9f24
 │    ├─ NLInstallBannerDustHooks()           0xc478
 │    ├─ NLInstallIslandDustHooks()           0x13c70
 │    └─ NLInstallLockScreenDustHooks()       0x16a08
 └─ [loader prepareDustRenderer] afterDelay:2.0  → NLDustRenderer prewarm
```

所有 hook 最终都汇聚到同一个引擎：

```
NLWithdrawalEffect +prepareView:...  (0x118e8)
  ├─ 前置门控：主线程 / 偏好 / 减弱动态 / 可见性 / Metal 就绪 / 去重 / 并发≤6
  ├─ 快照：drawViewHierarchyInRect 或复用 cachedImage
  ├─ NLWithdrawalWindow（独立 UIWindow，level = 源窗口 +1）
  ├─ NLDustRenderer（Metal 颗粒）
  ├─ cover（UIImageView，原图盖住源视图）
  └─ primeFrame 成功后返回
      ↓ 调用方在原生动画结束时
  -beginAfterNativeRemoval (0x12f00) → CADisplayLink 60fps → -tick:
      ↓ tick 轮询 disposition（调用方给的回调）
      ↓ removalConfirmed && hasCompletedFrame
  CALayer mask 遮住源视图 → renderer start → cover 移除 → "dust-started"
      ↓ 时长到 / 失败
  -finish (0x13648) → 还原 mask、拆窗口、清关联对象、从 NLEffects 移除
```

## 5. 关键常量

| 名称 | 值 | 地址 |
|---|---|---|
| NLDustParticleLimit | 14000（默认） | 0x263b0 |
| NLDustDistance | 110.0 | 0x263b8 |
| NLAnimationDuration | 1.3 | 0x263c0 |
| NLAnimationEnabled | true | 0x263c8 |
| NLIconDustEnableState | true | 0x26490 |
| NLIconDustDuration | 1.3 | 0x26498 |
| NLIconDustDistance | 110.0 | 0x264a0 |
| NLIconDustParticles | 6000 | 0x264a8 |
| 纹理像素上限 | 1200000 | — |
| 同时播放上限 | 6 | — |
| prepare 时请求粒子数 | 7000 | — |
| 快照缩放上限 | 2.0 | — |
| 首帧等待上限 | 0.6s | — |
| finish 宽限 | 0.15s | — |
| 偏好缓存节流 | 0.25s | — |
| 可见性 alpha 下限 | 0.02 | 0x195c0 |
| 最小可见尺寸 | 16×12 pt | — |

## 6. 诊断通道

SpringBoard 侧把状态写到
`/var/mobile/Library/Preferences/com.example.noticelisttweak.banner-status.plist`，
键包括 `events`（事件计数）、`installed`、`metalReady`、`reduceMotion`、`lastSource`、
`lastViewClass`、`lastEvent`、`build`、`updatedAt`、`pid` 等。
设置页的「横幅运行状态」读这个 plist 渲染成文本。

事件名（`NLWithdrawalRecord` 的入参）：
`withdrawal-seen`、`snapshot-ready`、`dust-started`、`skip:unavailable`、`skip:duplicate`、
`skip:no-real-card`、`skip:snapshot-failed`、`skip:metal-first-frame`、`skip:effect-limit`、
`skip:reused-source`、`skip:native-not-removed-or-frame`、`skip:trollopen-no-owned-view`、
`skip:aperture-no-owned-view`、`native-dismiss-seen`、`trollOpenWithdrawals`、
`apertureWithdrawals`、`clearCalls`、`deleteCalls`。

## 7. 证据目录

```
work/
├── main-arm64              arm64 slice（已解 fat）
├── main.dylib              fat 原文件
├── prefs-arm64             设置 bundle arm64 slice
├── machofix.py             chained fixup 解析器
├── annotate.py             主插件反汇编注释器
├── annotate_classic.py     设置 bundle 反汇编注释器
├── objcdump.py             ObjC 元数据导出器
├── check_sources.py        源码 ↔ 二进制交叉校验
├── listing.txt             主插件 245 函数带注释反汇编（21041 行）
├── funcs/                  按函数拆分 + index.tsv
├── skeletons.txt           每函数调用骨架
├── shader.metal            完整 Metal 源码
├── cstrings.txt            208 条 C 字符串
├── cfstrings.txt           193 条 CFString
├── objcdump.txt            全部类/ivar/方法/属性
├── prefs-listing.txt       设置 bundle 带注释反汇编
├── prefs-cstrings.txt      设置 bundle 字符串
└── INDEX.md                调查索引
```

## 8. 不能声称的

- 没有 iOS SDK / theos，**本机无法编译**，因此没有任何编译验证。
- 没有真机，**没有任何功能验证**。
- 反汇编还原的是「代码意图」，不等于运行时行为。尤其是私有 API 的
  实际签名、系统版本差异、Swift/ObjC 桥接边界。
- 图标与横幅模块的私有类方法名来自字符串表，方法是否存在于特定 iOS 版本
  由运行时的 `class_getInstanceMethod` 结果决定，静态无法证明。
