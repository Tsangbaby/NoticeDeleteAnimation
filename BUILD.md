# 构建说明

## 前置

| 组件 | 说明 |
|---|---|
| theos | RootHide 版（含 `roothide` scheme），或官方 theos + RootHide patch |
| iOS SDK | 16.5 或更新（原包用 ios 16.5 SDK 编译） |
| Xcode Command Line Tools | 提供 clang / ld64 |
| dpkg | 打 deb |

原包的 `LC_BUILD_VERSION` 是 `platform ios, sdk 16.5`，`install_name` 为
`@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/NoticeListTweak.dylib`，
说明它是用 RootHide 的 theos scheme 打出来的。用官方 theos 打 rootful 包不会得到
同样的布局，装到 RootHide 设备上也不会被加载。

## 步骤

```sh
export THEOS=~/theos
cd notice-rebuild

# 清理并打包
make clean package

# 产物
ls packages/
# com.example.noticelisttweak_1.0.1_iphoneos-arm64e.deb
```

RootHide 打包：

```sh
make package SCHEME=roothide
# 或
export THEOS_PACKAGE_SCHEME=roothide
make package
```

## 首次构建的预期问题

本工程**从未编译过**。按经验，第一次 `make` 大概率会在以下几类地方报错：

### 1. 私有头文件缺失

`NLBannerDust.m`、`NLIslandDust.m`、`NLIconDust.m`、`NLLockScreenDust.m`
用到大量私有类（`NCNotificationListView`、`SBHIconManager`、`SBIconView`、
`BNContentViewController`、`DIMiniIslandManager` 等）。原工程应该是靠
`@class` 前向声明 + `NSClassFromString` + `performSelector` 绕过的，
不依赖私有头文件。如果子代理写的版本用了 `#import <SpringBoard/...>`，
需要改成运行时查找。

### 2. `MSHookMessageEx` 的 IMP 类型

`NLNotificationHookLoader.m` 里把 `(IMP)NLRemoveView` 传进去，签名不匹配
会产生警告（不是错误）。保持原样即可，二进制里就是这么做的。

### 3. `NLDisposition` 函数指针

`NLWithdrawalEffect.disposition` 是 `NLDisposition (*)(NLWithdrawalEffect *)`，
二进制里通过 `blraaz` 间接调用。各个 hook 传入自己的 static 函数。

### 4. Metal 着色器

`DustShader.metal` 是**运行时字符串**（`newLibraryWithSource:`），不参与编译。
源码里 `NLDustMetalSource` 需要指向它的内容：

```objc
static const char *NLDustMetalSource = "...";   // 或 extern 到 .metal 生成的 C 数组
```

原二进制把着色器源码作为普通 C 字符串放在 `__TEXT,__const`，所以最省事的做法是
把 `DustShader.metal` 转成一个 C 字符串常量文件：

```sh
python3 - <<'EOF'
src = open('src/DustShader.metal').read()
esc = src.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n"\n"')
open('src/DustShaderSource.m', 'w').write(
    'const char *NLDustMetalSource =\n"' + esc + '";\n')
EOF
```

然后 `extern const char *NLDustMetalSource;` 并在 `NLDustRenderer.m` 里使用。

## 打包后自检

```sh
dpkg-deb -c packages/*.deb
dpkg-deb -f packages/*.deb Package Version Architecture

# 架构与签名
llvm-objdump --macho --private-headers \
  <解包后的 dylib> | grep -E 'LC_BUILD_VERSION|cputype|LC_UUID'

# RootHide 布局：install_name 必须含 .jbroot
llvm-objdump --macho --dylibs-used <dylib> | head -3

# 注入 filter
python3 -c "import plistlib;print(plistlib.load(open('layout/Library/MobileSubstrate/DynamicLibraries/NoticeListTweak.plist','rb')))"
```

## 与原包的差异检查

构建出的 dylib 不可能字节级一致（编译器版本、优化选项不同）。可比的指标：

- 架构：arm64 + arm64e 双 slice
- 依赖列表：应与原包一致（libsubstrate、UIKit、Foundation、CoreFoundation、
  QuartzCore、CoreGraphics、Metal、libobjc、libSystem、libc++）
- 类名与 selector 集合：应与原包一致（用 `objcdump.py` 对比）
- 字符串常量：应与原包一致（`cstrings.txt` / `cfstrings.txt`）
- 着色器源码：应逐字节一致

`work/check_sources.py` 可以做前两项的自动比对。
