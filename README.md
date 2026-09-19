# 续页 Longlet

<img src="iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="88" alt="续页 Longlet App 图标：青色连续折页">

像平时一样滑动，把屏幕里的内容接成一张长图。

续页是一款面向 iPhone 的实时滚动长截图 App。通过系统屏幕广播开始捕捉，切到目标应用手动滚动，结束后即可预览、裁剪、遮挡隐私并保存长图。使用 **Swift 6 / SwiftUI** 开发，最低支持 **iOS 18**；直接在本机处理屏幕帧，无需导入录屏视频。

**当前提交版本：0.1.7（构建 8）· App Store 等待审核，尚未正式上架**

[如何使用](#如何使用) · [快速开始](#快速开始) · [真机与签名](#真机与签名) · [版本记录](#版本记录) · [当前边界](#当前边界) · [隐私政策](docs/release/privacy-policy.md)

[续页 Xuye 官网](https://lzbaclz.github.io/long_screenshot_iphone/) · [使用帮助](https://lzbaclz.github.io/long_screenshot_iphone/support.html) · [网页隐私政策](https://lzbaclz.github.io/long_screenshot_iphone/privacy.html)


## 功能

| 功能 | 使用体验 |
| --- | --- |
| 实时滚动捕捉 | 从 App 首页或控制中心启动系统广播，手动滚动目标页面，结束后生成长图 |
| 上下双向拼接 | 向上翻看更早内容、向下浏览后续内容；回到已捕捉范围时去重，保持阅读顺序 |
| 固定区域处理 | 自动检测固定栏，支持手动设置；聊天画面可区分固定壁纸与滚动消息 |
| 自动接缝选址 | 在正文重叠内寻找平稳空隙，减少半透明卡片被横切的断层，保留捕捉帧像素 |
| 暂停与中断恢复 | 系统暂停后保留会话，恢复时检查画面重叠；中断后尽力保留已写入的内容 |
| 预览与精细编辑 | 缩放、分块浏览、裁剪、拼缝微调，以及不透明的隐私遮挡 |
| 图片导出 | PNG / JPEG，保存到系统相册或通过系统分享；大图可选择缩小导出 |
| 中英文界面 | 中文与英文的界面、使用指南、权限说明和错误提示 |

### 本机处理，自己掌握内容

屏幕画面在设备上分析和拼接，不上传到开发者服务器，不使用云端图像识别。无需注册账号，没有广告或第三方行为分析 SDK。系统捕捉授权与指示保持可见，音频样本不会保存。

遮挡会实际写入导出图片的像素；应用内仍保留原始画面，方便重新编辑。需要移除未遮挡原图时，可在检查导出结果后删除对应作品。更多说明见 [数据与隐私](#数据与隐私)。

### 免费导出额度

当前每周可免费导出 **50 个新作品**，按设备本地 ISO 周更新。失败、取消，以及同一作品重复导出不扣次数；升级保留已有成功导出记录。0.1.7 正式提交版本不包含 App 内购买或订阅。

## 如何使用

1. **开始捕捉**：打开续页，点按首页圆形捕捉按钮，在系统面板中选择续页并点按“开始广播”，等待系统倒计时。
2. **手动滚动**：切到目标应用，让起始画面稳定后向上或向下滑动。保持竖屏，让前后画面有重叠，等待图片加载完成后再继续。
3. **结束并返回**：点按屏幕顶部的系统捕捉指示结束，或回到续页点按停止按钮。
4. **编辑与保存**：打开生成的作品，检查首尾和接缝，按需裁剪、微调或遮挡，再选择 PNG / JPEG 保存到相册或分享。

也可以从控制中心的屏幕录制面板选择续页开始广播。开启专注模式可减少通知进入画面；捕捉期间请留意系统提示。

**真实跨应用捕捉需要 iPhone。** 模拟器可体验示例、编辑与导出；示例使用明确标注的合成素材。

## 最新更新：0.1.7

修复首次正式审核中“恢复购买”入口与后台无内购商品不一致的问题。移除未使用的购买／恢复及 StoreKit 权益代码、商品配置和 Beta 标记，免费规则明确为每周 50 个新作品，保留已有作品和导出记录。官网和中英文隐私说明同步更新。

**2026-09-19 13:45（Europe/London）已重新送审 0.1.7（8），当前等待 Apple 审核。** 本轮通过 108 项核心、17 项原生回归，iPhone/iPad 中英文设置与隐私检查，以及 iPhone PNG/JPEG 保存和系统分享；正式 IPA 审计确认无内购代码和配置。模拟器检查不代表新一轮真机捕捉验收。详见 [重新送审记录](docs/release/0.1.7-app-store.md)。

### 上一版本：0.1.6 启动恢复

修复开始广播时保留了系统面板或应用切换器、进入目标页面滚动后仍只得到单屏的问题。现在可用目标页面相邻帧的可靠重叠重新建立起点，支持上下两向及反转，保留目标首屏；起步不再只能依赖三张完全相同的静止画面。原有重叠、歧义和固定区域校验保持。

同时区分起拼前与已形成长图后的暂停恢复，允许严格有界的局部画面变化。首页新增等待目标内容的明确提示，捕捉详情可查看样本接收、跳过、起点替换和恢复方式；系统入口停止显示“广播已结束”，避免被误读成系统异常。

本轮通过 108 项核心、109 项 iOS 原生、9 条真实模拟器截图／滚动路线及相关中英文界面与保存分享验收。0.1.6（7）于 **2026-09-16** 上传成功，两个原内部组均已“正在测试”；公开外测新版已提交 Beta 审核、正在等待，旧版 0.1.5（6）继续可用。实际分发证据见 [更新记录](docs/release/0.1.6-testflight.md)。更新后请重新开始捕捉，旧图不会自动重拼；真实 iPhone 跨应用效果仍需新版本反馈。设计与证据见 [启动恢复方案](docs/beta-7-startup-recovery-plan.md)。

## 快速开始

### 环境

- macOS、完整 **Xcode 26 或更高版本**，以及可用的 iPhone 模拟器运行时。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) **2.44.0 或更高版本**，用于从 `project.yml` 生成工程。
- 当前发布构建使用 Xcode 26.3；本地原生测试使用 iOS 26.3.1 模拟器。

```sh
git clone https://github.com/lzbaclz/long_screenshot_iphone.git
cd long_screenshot_iphone

# 使用 Homebrew 安装工程生成工具
brew install xcodegen

./scripts/generate-project.sh
open ScrollCapture.xcodeproj
```

在 Xcode 中选择 **ScrollCapture** scheme 和一个 iPhone 模拟器后运行。可在 scheme 的 **Arguments Passed On Launch** 中添加以下参数：

| 参数 | 用途 |
| --- | --- |
| `--demo` | 创建明确标注的示例作品，体验预览、编辑和导出 |
| `--uitesting` | 重置专用演示目录，供界面自动化使用 |

`project.yml` 是工程配置源。调整版本号、Target 或能力后，重新运行生成脚本。项目脚本优先使用当前选定的完整 Xcode，也会查找 `/Applications/Xcode.app`；不会修改全局 `xcode-select`。若安装在其他位置，可先设置：

```sh
export DEVELOPER_DIR=/你的路径/Xcode.app/Contents/Developer
```

### 构建与测试

在仓库根目录运行基础检查，包含 Swift 核心测试、工程生成、模拟器构建与差异格式检查：

```sh
./scripts/check.sh
```

仅运行拼接核心或合成基准：

```sh
source scripts/xcode-env.sh
swift test
swift run -c release ScrollCaptureBenchmark --output .work/core-benchmark
```

运行 iOS 原生与界面测试前，先选择一台专用的 iPhone 模拟器：

```sh
source scripts/xcode-env.sh
xcrun simctl list devices available

# 将下方占位值替换为专用模拟器的 UDID
SIMULATOR_UDID="你的模拟器UDID" ./scripts/test-ios.sh -parallel-testing-enabled NO
```

该脚本会为专用模拟器中的 App 授予照片添加权限，以验证正常保存路径。照片拒绝权限和真实设备捕捉分别验收，详见 [实施状态与证据](docs/implementation-status.md) 和 [真机验证规程](docs/validation/physical-device-protocol.md)。

日常开发流程为 **本地必要验证 → 手动上传 TestFlight → 真机反馈修复**。GitHub Actions 仅保留 `workflow_dispatch` 手动触发，不随 push / PR 自动运行，也不作为日常 TestFlight 分发的前置条件。

## 真机与签名

将 `Config/Signing.example.xcconfig` 复制为被 Git 忽略的 `Config/Signing.local.xcconfig`，填写自己的付费 Apple 开发者团队。主应用与广播扩展使用相同团队及 `APP_GROUP_IDENTIFIER`；当前默认值为 `group.dev.lzbaclz.longscreenshot`。

使用其他开发者账号构建时，需在 `project.yml` 中配置自己可用的主应用和扩展 Bundle ID，并同步主应用的 `BroadcastExtensionIdentifier`；如更换 App Group，也需同步本地配置与开发者账号中的能力。签名团队、证书、描述文件和私钥不得提交到版本库。

跨 App 测试使用 **ScrollCaptureDevice** scheme 构建主应用与 **FixtureReader** 测试页。测试页由项目生成，不使用私人聊天或个人照片作为测试样本。

签名配置完成后归档：

```sh
./scripts/archive.sh
```

默认产物位于 `.work/archives/<时间>/Longlet.xcarchive`，也可用 `LONGLET_ARCHIVE_DIR` 指定目录。脚本只完成本地归档；之后通过 Xcode Organizer 上传，并在 App Store Connect 配置 TestFlight 构建与测试组。

已有内部及[公开 TestFlight 内测](https://testflight.apple.com/join/Qb5CcCep)。2026-09-16 核对时，0.1.6（7）的两个原内部组已“正在测试”；公开组仍可测试 0.1.5（6），新版 0.1.6（7）正在等待 Beta 审核。实际状态见[更新记录](docs/release/0.1.6-testflight.md)。本次分发不调整正式 App Store 审核；此前送审记录和实际进度分别见 [正式提交记录](docs/release/0.1.5-app-store.md) 与 [实施记录](docs/implementation-status.md)。[续页 Xuye 官网](https://lzbaclz.github.io/long_screenshot_iphone) 提供产品介绍、使用帮助和隐私网址。

## 项目结构

```text
iOS/
  App/                       SwiftUI 主应用、作品库、编辑器与导出
  BroadcastExtension/        ReplayKit 广播扩展，接收系统屏幕帧
  Shared/                    帧处理、分片存储、渲染与会话恢复
  Resources/                 App 图标与本地化资源
  FixtureReader/             程序生成的跨 App 验证页面
  AppTests/、SharedTests/     原生单元与像素验收
  AppUITests/                 预览、编辑、保存与分享流程测试
  DeviceUITests/             iPhone 系统广播验证
  SimulatorCaptureUITests/   模拟器真实拖动与截图注入验证
  PermissionUITests/         照片权限拒绝验证
  Experimental/              实验采集后端，默认 Beta 未启用
Sources/
  ScrollCaptureCore/         Swift 拼接核心、固定区域与前景匹配
  ScrollCaptureBenchmark/    合成样本与独立真值基准
Tests/                      Swift 核心回归测试
Config/                     权限、隐私声明与本地签名配置
scripts/                    工程生成、构建、测试与归档脚本
docs/                       计划、设计、算法、验证及发布记录
project.yml                 XcodeGen 工程配置
Package.swift               Swift Package 配置
```

界面使用 SwiftUI / UIKit，采集使用 ReplayKit，图像处理使用 Core Graphics / ImageIO，保存与分享使用 Photos 和系统分享面板。主应用与扩展通过 App Group 共享本机分片和会话记录。

## 验证与当前边界

### 已有验证

以下为 **0.1.6 本次本地验证记录**；历史基准另行注明，不是每次打开 README 时重新运行的结果：

| 验证类别 | 结果 | 证明的范围 |
| --- | --- | --- |
| Swift 核心回归 | 108 / 108 通过 | Release；核心匹配与接缝算法源码未改 |
| 合成真值基准（0.1.5 历史） | 217 / 217，共 8,776 帧 | 程序生成画面与独立真值；本轮未重跑此基准 |
| iOS 原生与像素验收 | 109 / 109 通过，0 跳过 | 起步恢复、两方向、首屏与固定栏、事务回滚及原有原生套件；包含 886×1920 和 1179×2556 素材 |
| 模拟器滚动截图注入 | 9 / 9 路线通过，0 跳过 | 新增从无关 App 首帧切入目标的 3 条路线及原固定栏／壁纸 6 条；独立 UIKit 坐标、首尾和消息像素检查 |
| 主应用状态与导出 | 4 条场景分别通过 | 等待／暂停双语、指南、诊断双语滚动、PNG／JPEG 保存及系统分享；最终详情布局再次单独通过 |

完整结果、历史失败与验收口径见 [0.1.6 发布记录](docs/release/0.1.6-testflight.md)、[启动恢复方案](docs/beta-7-startup-recovery-plan.md) 和 [界面验收](docs/validation/2026-09-16-startup-ui.md)。上述结果不代表 iPhone 真机跨应用捕捉的成功率、内存、耗电或兼容性。

### 当前边界

- **画面需要重叠**：快速跳页、完全重复的内容、缩放、横向移动或大范围异步重排，可能无法可靠定位；无法确认的中间内容不会被补造。
- **壁纸可能有接缝**：固定背景与移动消息不能同时形成一张整体平移的原图。自动选址尽量把切口移到内容空隙；保留捕捉帧像素，不重画背景，因此空隙仍可能有背景变化。
- **固定栏识别有范围**：自动检测采用保守判断，也支持手动设置；不保证适配所有应用和布局。
- **中断恢复有条件**：尽力保留已落盘内容，暂停恢复后仍需确认有效重叠，不跨未知缺口拼接。
- **真机验证仍在推进**：内部测试已收集到使用反馈，规范的设备矩阵、资源测量和长期稳定性验收尚未完成。
- **实验后端单独记录**：仓库保留 iOS 27 采集后端实验代码及历史编译证据；当前 Beta 使用 ReplayKit，未启用该实验后端。

## 数据与隐私

- 原始图片分块、编辑记录、导出文件和诊断统计保存在本机，不自动发送给开发者。
- 仅在主动保存时申请向相册添加图片的权限，不要求读取照片图库；拒绝后仍可使用系统分享。
- 作品存储目录设置为不参加系统备份，应用不提供云同步。已导出的副本可能由照片或文件服务按用户设置同步。
- 删除作品会移除应用内对应内容，不会删除已经保存到相册、文件或其他应用的副本。
- 遮挡后的导出图片不包含被遮挡区域的原始像素；可重新编辑的原图仍留在应用内，删除作品后才移除。

完整说明见 [隐私政策（中文 / English）](docs/release/privacy-policy.md)。问题反馈：[chestnutlee23@163.com](mailto:chestnutlee23@163.com)。

## 版本记录

| 版本 | 主要变化 | 详情 |
| --- | --- | --- |
| 0.1.6（7） | 跨应用起步恢复、局部变化与起拼前暂停修复、等待提示与诊断补充 | [发布记录](docs/release/0.1.6-testflight.md) |
| 0.1.5（6） | 半透明卡片接缝选址、固定背景证据范围与重复图标匹配修复、接缝明细 | [发布记录](docs/release/0.1.5-testflight.md) |
| 0.1.4（5） | 同色固定栏上滑重复修复、候选来源与起拼复核、匹配区域诊断 | [发布记录](docs/release/0.1.4-testflight.md) |
| 0.1.3（4） | 固定照片壁纸下的消息匹配、旧参考判断修复、系统暂停恢复与诊断补充 | [发布记录](docs/release/0.1.3-testflight.md) |
| 0.1.2（3） | 聊天向上起步、自动拼接区域与窄中文气泡匹配修复 | [发布记录](docs/release/0.1.2-testflight.md) |
| 0.1.1（2） | 上下双向拼接、每周 50 次测试额度与采集可靠性修复 | [发布记录](docs/release/0.1.1-testflight.md) |
| 0.1.0（1） | 首次内部 TestFlight，实时捕捉、预览编辑与图片导出 | [发布记录](docs/release/0.1.0-testflight.md) |

## 项目文档

- [项目计划书](docs/project-plan.md)
- [实施状态与验证证据](docs/implementation-status.md)
- [拼接算法说明](docs/algorithm.md)
- [采集后端选择](docs/decisions/0001-capture-backends.md)
- [真机验证规程](docs/validation/physical-device-protocol.md)
- [验证门槛与证据分类](docs/validation/gates-and-evidence.md)
- [品牌命名](docs/brand-naming.md)与[图标原图、设计思路及生成记录](docs/design/longlet-icon-prompt.md)
- [隐私政策](docs/release/privacy-policy.md)
- [商店资料与审核说明](docs/release/app-store-package.md)
