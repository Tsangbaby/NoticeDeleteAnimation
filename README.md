# NoticeListTweak 逆向重建工程

> **本分支为上传源码的独立 RootHide 构建候选 `1.0.1+rebuild1`**，不是 NoticeDeleteAnimation alpha7。原始说明保留在下方；本次修正、原生编译验收及未验证行为分别见 [构建计划](Docs/BUILD-REBUILD1.md)、[变更与边界](Docs/REBUILD1-CHANGES.md)。CI 成功不等于目标设备动画已验证。

从 `通知消散 1.0.1~test14` 的已编译 deb 完整重建的可维护源码工程。

## 目录

```
notice-rebuild/
├── src/                    主插件源码（SpringBoard 注入的 dylib）
├── prefs/                  PreferenceBundle 子工程
├── layout/                 打包时原样复制的资源（plist / 图标）
├── control                 包元数据
├── Makefile                主 Makefile（theos）
├── work/                   逆向工作区（反汇编、注释、解析器、证据）
├── INDEX.md                调查索引与样本身份
└── REVERSE-NOTES.md        逆向过程与已知不确定点
```

## 构建

需要 theos + iOS SDK（16.5 或更新）以及 RootHide 打包 scheme。

```sh
export THEOS=~/theos
make clean package
```

产出 `packages/com.example.noticelisttweak_1.0.1_iphoneos-arm64e.deb`。

RootHide 打包需要在 theos 里启用 roothide scheme，`install_name` 会被改写成
`@loader_path/.jbroot/...`。原始包就是这样打出来的。

## 源码结构

| 文件 | 职责 | 对应二进制 |
|---|---|---|
| `NLDustRenderer.{h,m}` | Metal 颗粒渲染视图 | 0x76b4–0x9140 |
| `DustShader.metal` | 顶点/片元着色器（**原样恢复**） | `__const` 0x195e8 |
| `NLWithdrawalEffect.{h,m}` | 消散引擎（overlay 窗口 + 生命周期） | 0x11490–0x13bb0 |
| `NLPreferences.{h,m}` | 偏好读取、可见性判定、事件计数 | 0x6290 / 0x10a94 / 0x10c40 / 0x12b04 |
| `NLNotificationHookLoader.{h,m}` | 安装入口、重试、%ctor | 0x58d0–0x67b4 |
| `NLNotificationListHooks.{h,m}` | 通知列表 remove/clearAll hook | 0x67b4–0x75a0 |
| `NLIconDust.{h,m}` | 桌面图标消散 | 0x919c–0xc39c |
| `NLLockScreenDust.{h,m}` | 锁屏通知消散 | 0x16600–0x18c00 |
| `NLBannerDust.{h,m}` | BannerKit 横幅消散 + 诊断写入 | 0xc478–0x10a94 |
| `NLIslandDust.{h,m}` | 灵动岛（TrollOpen / Nice） | 0x13c70–0x16600 |
| `NLStatusProbe.{h,m}` | 状态探测 | 0xc39c–0xc478 |
| `NLRootListController.{h,m}` | 设置根列表 | prefs 0x6dd4–0x7120 |
| `NLBannerStatusController.m` | 横幅状态详情页 | prefs 0x5ad4–0x6dd4 |

## 验证状态（务必先读）

**本工程是静态逆向的产物，尚未编译，也未在真机验证。**

- 反汇编注释、类元数据、字符串表、着色器源码：来自二进制的直接证据。
- 各函数的控制流和常量：按反汇编逐条还原，标注了原始地址。
- 标有 `// REVERIFY:` 的地方是**推断而非证据**，见 `REVERIFY-LIST.md`。
- 没有 iOS SDK / theos，本机无法编译，也没有真机测试。

首次构建预期需要修编译错误（主要是私有 API 声明、类型签名）。
