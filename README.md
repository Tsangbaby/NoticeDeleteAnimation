# NoticeDeleteAnimation

作者 / 维护者：**Tsangbaby**

Package：`com.tsangbaby.noticedeleteanimation`
当前候选：`0.1.0~alpha8`，iOS15+、RootHide arm64/arm64e。

本分支把已在用户设备生效的重建实现维护为 NoticeDeleteAnimation。alpha8 的目标是改善删除通知时的灰块、修正系统横幅请求解析，并统一所有安装与运行身份。内部 `NL*` 符号属于实现细节，不是另一个已安装插件。

## 构建

在云端 Mac / Xcode 和固定官方 RootHide Theos 下运行，不把 Linux 桩头语法检查当成原生编译：

```sh
python3 Scripts/generate_shader.py --check
python3 Scripts/check_source.py
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

CI 使用真实 Apple SDK、最低 iOS15.0，输出 `com.tsangbaby.noticedeleteanimation_0.1.0~alpha8_iphoneos-arm64e.deb`。通过实际包解析、注册/依赖及逐页签名验证后才交付。

## 身份及升级

插件显示名、dylib、设置 bundle/可执行、PreferenceLoader注册、偏好域/通知和诊断路径均使用 NoticeDeleteAnimation 身份。作者/维护者为Tsangbaby。新包 `Conflicts/Replaces: com.example.noticelisttweak`，避免与前一重建包双重注入。现有 NoticeDeleteAnimation 同包名正常升级，不保留两套可执行文件。

偏好域为 `com.tsangbaby.noticedeleteanimation`；状态文件为该域的 `.banner-status.plist`。不自动读取或写入旧域，不搬运通知内容或旧诊断。其他功能相同的通知动画插件应禁用以免重复处理。

## 验证与边界

[alpha8目标与证据](Docs/ALPHA8-PLAN.md)记录当前视频事实和门禁。设备视频显示通知行和操作按钮一起形成早期灰块，不是仅有最终帧残留；未展示点击横幅。点击路径须由源码、合成运行回归和后续设备状态区分，不能用假点击测试冒充真机通过。

功能修改会有直接执行生产函数的原生回归，所有依赖替身明确标注。Metal源码能编译不等于实际GPU动画/所有材质正确。真机视觉和私有通知路径仍需用户验收。

历史重建资料、地址注释及 `REVERIFY`保留为维护依据，不把它们伪装成已验证的行为。原始上传二进制不参与构建、不会混入新包。原件和视频均只保留本地。
