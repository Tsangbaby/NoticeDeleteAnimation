# NoticeListTweak 逆向重建 · 调查索引

样本：`通知消散1.0.1~test14_iphoneos-arm64e(1).deb`
SHA-256：`d236a27a4381a08bcd91090a0d312908deff25dca0c8991756107105e08a73df`

## 样本身份

| 项 | 值 |
|---|---|
| 包名 | `com.example.noticelisttweak` |
| 显示名 | 通知消散 |
| 版本 | 1.0.1~test14 |
| 架构（包） | iphoneos-arm64e |
| 架构（Mach-O） | fat：arm64 + arm64e 双 slice |
| 主插件 | `Library/MobileSubstrate/DynamicLibraries/NoticeListTweak.dylib` 431152 B（fat），arm64 slice 202528 B |
| 设置 bundle | `Library/PreferenceBundles/NoticeListTweak.bundle/NoticeListTweak` 169216 B（fat） |
| UUID (arm64 slice) | 9632797E-3942-3970-AD1F-16709C0C0343 |
| 构建 SDK | ios 16.5 |
| 语言 | 纯 Objective-C / C++，无 Swift |
| 符号 | 未剥离，245 个函数符号完整 |
| 依赖 | libsubstrate, UIKit, Foundation, CoreFoundation, QuartzCore, CoreGraphics, Metal, libobjc, libSystem, libc++ |
| 布局 | RootHide（install_name `@loader_path/.jbroot/...`） |

## 反编译基础设施

| 文件 | 作用 |
|---|---|
| `machofix.py` | LC_DYLD_CHAINED_FIXUPS 解析（arm64e 认证指针 + 普通指针），指针槽到目标/导入符号解析 |
| `annotate.py` | 反汇编注释器：classref/selref/CFString/adrp+add/栈槽/msgSend 调用点还原 |
| `objcdump.py` | ObjC class_ro_t 元数据导出（ivar/方法/属性，支持相对方法列表） |
| `listing.txt` | 245 个函数带注释反汇编，21041 行 |
| `funcs/` | 按函数拆分 |
| `skeletons.txt` | 每函数调用骨架 |
| `shader.metal` | 从 `__const` 完整还原的 Metal 着色器源码 |
| `cstrings.txt` / `cfstrings.txt` | 字符串常量全表 |
