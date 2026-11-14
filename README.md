# NoticeDeleteAnimation

Swift 编写的系统通知删除粒子消散插件源码候选。

| 项目 | 值 |
|---|---|
| 插件名 | NoticeDeleteAnimation |
| Package | com.tsangbaby.noticedeleteanimation |
| Author / Maintainer | Tsangbaby |
| 源码版本 | 0.1.0-alpha2 |
| 最低 deployment target | iOS 15.0 |
| 架构目标 | arm64 / arm64e |
| 注入目标 | 仅 SpringBoard |

**alpha1 已通过云端原生构建，但用户在 RootHide iOS16.0.3 安装并注销后反馈无效果。alpha2 是诊断修复候选，不是已证实解决设备问题的版本。** iOS 15.0+ 是目标范围，不表示已经逐版本实测；没有最高系统版本硬拦截。私有接口不匹配时保留系统行为。具体构建证据及真机边界见 `Docs/`。

## 效果与范围

参考用户提供的短视频：通知在移除后分成细小碎片，主要向上飘散，消散前沿从右向左推进。Swift 根据固定种子生成分块、位移、旋转、缩放及透明度关键帧，Core Animation 渲染约 1.35 秒。

首版使用最多约 900 个共享快照的纹理分块，而非逐像素物理粒子。它是独立实现的颗粒化近似，**没有逐帧一致或性能已达标的承诺**。最多同时 2 个效果、总共 1800 个纹理分块；超预算走原生删除。系统负责后续通知补位，不重写列表布局。

当前只在 `removeNotificationRequest:` 同步调用范围内、列表确实移除且卡片 request 对象身份一致时触发。滚动回收、一般视图消失、分组切换不作为触发器。清空全部/分组卡片/异步批量更新不保证覆盖；拒绝不确定目标优先于误动画。

## 结构

- `Sources/Core/`：纯 Swift 粒子数学、参数消毒、资源租约账本。
- `Sources/Tweak/`：Swift/UIKit 快照、CALayer 渲染、生命周期与隐私回收、Swift 启动入口。
- `Sources/Bridge/`：少量 Objective-C，处理 constructor、Substrate IMP、精确 ABI 预检和 ObjC 异常边界。不是 Logos/Orion 工程，动画和资源策略不在桥里。
- `Tests/CoreTests/`：为原生 Swift 环境编写的 XCTest。
- `Tests/UIKit/`：需 Xcode/iOS 测试宿主的真实 UIKit 滚动坐标回归测试，不覆盖生产渲染器和私有 hook。
- `Scripts/check_source.py`：本地 Swift 语法/元数据/安全契约检查，不是编译器。
- `Docs/`：计划、接口证据、已知限制和验证状态。

## 构建（本轮未执行）

需要 macOS/Xcode 命令行工具、iOS SDK、支持 Swift 的 Theos 及匹配的 substrate 头/库。根 Makefile 明确最低 iOS 15.0 与 Swift 5 模式。

```sh
# 用匹配工具链选择布局，不通过手工改包路径冒充适配。
make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
# rootful 使用相应 upstream Theos：
make clean package THEOS_PACKAGE_SCHEME= FINALPACKAGE=1
# RootHide 必须使用真正 RootHide Theos 及其 SDK/打包流程：
make clean package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
```

这些是构建入口，不是已经通过的命令记录。`control` 中 `iphoneos-arm` 是源模板，最终架构字段由所选 Theos scheme 处理，须检查最终包。arm64e 必须用兼容 Apple 工具链，不能篡改 Mach-O subtype 代替构建。

纯 Swift 核心可在支持 Swift 5.7+ 的宿主执行：

```sh
swift test
# 本地语法及契约检查，需 tree-sitter 与 tree-sitter-swift：
python3 Scripts/check_source.py
```

## 安全与开关

- 默认启用；设置 → NoticeDeleteAnimation 提供启用开关和诊断，读取相同的 `com.tsangbaby.noticedeleteanimation` 偏好域。主插件不依赖 Preferences framework，独立 Swift 设置包依赖 Preferences/PreferenceLoader。
- 开关下一次删除生效，无需为了改开关再次注销。诊断刷新可显示 SpringBoard PID、更新时间及固定故障码计数；这些值是上次插件成功写入的状态，不把旧时间戳当成当前加载成功的证明。
- 开启“减弱动态效果”、资源预算不足、快照失败、ABI 缺失时，保留系统移除。录屏不会单独禁用效果，仍遵循原通知表面的可见性。
- 不记录通知正文、不保存图片、不上传数据。不创建全局覆盖窗口；效果附着于原通知列表，失去表面/窗口/前台、滚动或旋转改变 bounds、内存警告等都会回收。
- 不延后删除、不重插通知；原系统删除调用恰好一次。仅成功准备的现代列表卡片关闭原卡退场动画，保留系统布局补位。

## 停止点

本轮修复保持在新分支，按既有授权推送至用户公开仓库并构建 RootHide 测试包。未连接或操作设备，安装、注销和真机验收由用户进行。历史首版验证记录保留于 Docs，不替代 alpha2 的实际构建结果。
