# 用户滚动未起拼调查

日期：2026-09-16。任务是分析用户提供的视频及结果截图，定位为什么滚动后只得到一张单屏。本轮不修改产品逻辑，不归档或分发新版。

## 当前判断

最符合现有证据的路径是：广播启动时，把系统广播面板或应用切换器保存成待定起点；进入目标页面后，起点替换条件没有满足，后续滚动一直在与无关的旧画面比较，最终保留旧单屏。

代码存在明确的起步限制：只有新场景的**连续三次已处理灰度帧完全相同**，才能在起拼前替换旧起点。滚动中的相邻目标帧即使彼此有可靠重叠，也不会据此建立新的起点。这是可以用合成输入单独验证的代码行为；不能凭外拍视频断言测试手机确切收到多少帧，或哪一次回调触发了哪个分支。

核查基线为仓库 `e1b9e1d`，工程版本 0.1.5（6）。`CaptureFramePipeline.swift`、`SampleHandler.swift`、`CaptureLifecyclePolicy.swift` 与 0.1.5 发布源码 `4eb8a64` 无差异。用户及测试者的实际安装版本、机型、系统版本暂未取得；不能把仓库版本当成测试者已安装版本。

## 视频与截图证据

原始视频约 27.20 秒、1280×720、外部相机拍摄。只观察广播操作、页面运动和结果状态，未把视频画面作为算法输入或私人聊天夹具。抽帧保存在本机被 Git 忽略的 `.work/user-scroll-investigation-20260916/`，正文不收录聊天文字或用户原图。

| 视频约时点 | 可确认现象 | 含义与边界 |
| --- | --- | --- |
| 0–4 秒 | 从 Longlet 打开系统广播面板，面板随后显示 Stop Broadcast | 广播已启动；不证明当时已有正确的正文参考帧 |
| 5–7.5 秒 | 关闭面板，经过 Longlet 首页和应用切换器，进入目标应用 | 捕捉开始和正文出现之间有多个不同场景 |
| 8–13 秒 | 用户连续滑动，消息区域可见纵向位移，广播指示仍在 | 用户确实进行了滚动；不能从外拍视频恢复扩展实际接收帧或精确位移 |
| 约 13.5–14.5 秒 | 点按顶部广播指示，系统弹出停止询问，再点 Stop | 这次停止由用户主动操作触发，不能把“由系统结束”解释成进程被杀 |
| 约 21–27 秒 | 结果显示 Single screen saved、886×1918，图片是应用切换器 | 这次没有得到已确认的连续长图，最终保留了错误场景的单屏 |

另附截图中保留的是系统 Screen Broadcast 面板，结果同样为单屏。截图时钟与视频不同，应作为另一份结果证据，不能把两者当成同一份会话清单。两份结果都与“待定起点未切到目标正文”相容。

## 代码原因

### 1. 第一帧直接成为待定起点

`iOS/Shared/CaptureFramePipeline.swift:79` 在还没有候选和已开始状态时直接 `arm`。没有就绪条件区分启动面板、应用切换器和目标内容。`arm` 保存一张候选 PNG，并用同一帧建立所有区域探针。

保留第一张单屏是合理的中断兜底，但该帧不能因此变成跨场景滚动的永久参照。

### 2. 替换起点要求全帧逐像素相等

`iOS/Shared/CaptureFramePipeline.swift:280` 的 `stableSceneReplacement` 使用：

```swift
previous.pixels.elementsEqual(analysis.pixels)
```

计数达到 3 才重新 `arm`；任何一个灰度像素不同，计数重新变成 1。比较覆盖整个分析帧，尚未排除状态栏等固定 UI。滚动、动画、加载变化或者局部指示变化，都可能使条件不成立；这些变化在测试手机上是否发生、持续多久，尚无内部帧证据。

普通滚动匹配仍使用旧候选和旧探针；连续被拒绝的目标帧之间没有独立的滚动验证路径。因此，即使目标帧彼此完全可以拼接，也可能全部被旧场景拒绝。这里需要改的是起点建立与跨场景恢复，不能仅靠放宽正常拼接误差阈值来解决。

`SampleHandler.swift:61` 还会丢弃距上次接纳不足 0.15 秒的样本，后续分析串行完成。因此“三帧”指三次真正经过管线的采样，不是视频的三帧，也不等于肉眼静止一定时间。少于三次调用时，单纯经过时间不会更新候选。

ReplayKit 的可变输入帧率也见 [Twilio 官方 ReplayKit 示例说明](https://github.com/twilio/video-quickstart-ios/blob/master/ReplayKitExample/README.md#replaykitvideosource)。该示例只能佐证不应假定固定回调频率，不能用于推断本例的实际 FPS，也不采用其中旧系统版本的帧率上限作为当前设备结论。

`git blame` 将完全相等的三帧条件定位到 `c973333`，对应 0.1.3，当前 0.1.5 仍沿用。其原意是防止把不断变化的无关画面当作新起点；安全目的合理，但起拼前没有另一条经可靠重叠验证后建立新起点的恢复路径。

### 3. 起拼失败期间缺少及时的用户反馈

`CaptureContinuityPolicy.reject` 在 `hasStarted == false` 时直接返回。现有 8 秒连续性保护只覆盖开始后的拼接或恢复状态，不处理普通起步卡住。`SampleHandler` 的空闲停止也需要 `didMove == true`。因此，起步一直失败可以持续到用户停止或到达总时长上限，而没有明确提示目标内容尚未进入拼接。

这解释了为什么用户看到广播仍在继续，却直到结束才知道没有获得长图。

### 4. 暂停恢复还存在一条需要单独验证的卡住路径

`SampleHandler.swift:87` 用 `hasReference` 决定暂停后是否必须找回重叠，而 `hasReference` 包括仅有待定候选、尚未起拼的状态。恢复后，`SampleHandler.swift:174` 禁止替换候选；如果暂停前候选恰好是系统面板，目标页面即使稳定多帧也不能成为新起点。

这条路径在代码上存在，应与已成功起拼后的严格恢复保护分开设计。**本视频不能证明发生过 `broadcastPaused` / `broadcastResumed`，不可把它写成此次用户失败的已确认直接原因。**

### 5. “由系统结束”不表示系统异常

`SampleHandler.swift:108` 的 `broadcastFinished()` 在没有应用自己的 `stop.request` 时统一记录 `systemStop`。视频里用户通过系统停止按钮结束广播，正会走这个分支。结束后未确认拼接时，`finishSession` 取待定单屏，`CaptureSessionManifest.finalizeCapture` 生成截图中看到的结果提示。

## 为什么已有测试和开发者本人可能正常

`CaptureFramePipelineTests.testAppSwitchBeforeFirstScrollReplacesCandidateAndPreservesTargetBeginning` 明确连续注入三次完全相同的目标首帧，然后才滚动，因此满足了苛刻的换起点条件。

原生短消息验收和模拟器滚动注入从目标测试页面开始输入，没有覆盖“系统面板 → 应用切换器 → 目标页面立即滚动”的真实启动前置过程。因此，之前的拼接、像素与界面验收通过，不代表真实广播的跨应用起步已覆盖。

开发者测试成功的一种解释是首个处理帧已在目标页面，或切换后恰好收到了足够的相同帧。这个解释需要同条件对照才能确认，不能据此断言双方手速、机型或系统版本就是根因。

## 本次验证

使用项目 Xcode 选择脚本，针对现有 iOS 原生 `CaptureFramePipelineTests` 和 `CaptureLifecyclePolicyTests` 运行 Release 模拟器测试。临时诊断扩展加入原有测试文件，使用既有确定性合成场景，不使用用户聊天；完成后恢复原测试文件，避免把当前缺陷的行为断言当作应永久保留的产品契约。

诊断扩展：`.work/user-scroll-investigation-20260916/StartupAnchorInvestigation.swift`。运行日志：同目录 `startup-probe.log`；结果包：`startup-probe.xcresult`；源码指纹：`source-fingerprints.json`。

结果：**29 / 29 通过，0 失败、0 跳过**。包括原有管线测试 13 项、生命周期测试 11 项和本轮临时诊断 5 项。`test-summary.json` 已核对实际执行设备为 Longlet-Beta2、iOS 26.3.1、arm64、iOS Simulator。Xcode 26.3，Release，仅测试时设置 `ENABLE_TESTABILITY=YES`。

| 对照输入 | 当前生产管线实际结果 |
| --- | --- |
| 直接输入目标页面，以 +12 或 -12 行滚动 5 次 | 两方向均确认 5 次衔接 |
| 相同目标序列前加一张无关宿主画面 | 两方向均 0 次衔接、6 次拒绝，兜底图片像素与宿主原图一致 |
| 宿主 → 目标首帧完全重复 2 次 → 相同滚动序列 | 0 次衔接、0 次候选替换 |
| 宿主 → 目标首帧完全重复 3 次 → 相同滚动序列 | 5 次衔接、1 次候选替换 |
| 宿主 → 静止目标 8 帧，每帧仅左上角 1 个灰度像素不同 → 滚动 | 0 次衔接、0 次候选替换，保留宿主单屏 |
| 仅保存宿主待定帧 → 模拟暂停恢复策略 → 目标完全相同 5 帧 | 0 次衔接、0 次候选替换，持续等待旧画面重叠 |
| 起拼前拒绝 120 次，传入逻辑时间 0–119 秒 | 连续性策略始终不触发结束；不是实际等待两分钟的真机测试 |

这些测试**通过表示成功复现并核对了当前缺陷**，不表示缺陷已修复。合成图为 48×120 灰度画面，两个滚动方向每步保留 90% 全帧重叠；它们用于隔离起点前置条件，不用于评估真实画面的识别率、ReplayKit 回调频率、内存或速度。测试直接调用真实 `CaptureFramePipeline`、生成并读取实际候选 PNG，未模拟完整系统广播服务；暂停分支按适配器的参数规则调用真实生命周期策略，不代表收到过真实暂停回调。

实际命令（临时追加诊断扩展后执行）：

```sh
source scripts/xcode-env.sh
xcodebuild -project ScrollCapture.xcodeproj -scheme ScrollCapture \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=AC2AD83E-C984-4EA6-AA49-FADDB04717E4' \
  -derivedDataPath .work/DerivedData-Beta6-Optimized \
  -resultBundlePath .work/user-scroll-investigation-20260916/startup-probe.xcresult \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  -parallel-testing-enabled NO \
  -only-testing:ScrollCaptureTests/CaptureFramePipelineTests \
  -only-testing:ScrollCaptureTests/CaptureLifecyclePolicyTests test
```

测试结束后，已按原始字节恢复 `CaptureFramePipelineTests.swift`，并核对三个产品源码指纹均未改变。未把用户媒体提交到仓库，未运行云端 CI，未变更发布状态。

## 修复方向与最终定位所需信息

1. 将启动候选与已确认的连续内容分开。起拼前允许以目标页面相邻帧的可靠重叠重新建立起点；仍不得把旧面板与新正文跨接，也不能无条件用每一张拒绝帧覆盖候选。
2. 稳定性识别允许合理的局部变化，不把全屏逐像素相等作为唯一入口，并兼容静止时采样较少的情况。已拼接后的未知缺口继续严格拒绝。
3. 区分仅有待定帧与已写入连续内容的暂停恢复策略，补齐对应回归。
4. 起步长时间没有确认正文时提供清晰状态，并记录已接收／已处理／已拒绝帧数、候选替换次数、连续稳定采样数和暂停恢复次数。这些是数值诊断，不采集聊天内容。
5. 补充带广播面板和应用切换过程的真机验证，分别测试进入目标后立即滚动、停留后滚动及页面存在局部动画；合成或模拟器注入不能替代这项证据。

当前还缺测试者该次作品的 Capture details 展开信息，特别是已处理／已衔接／未衔接帧数、停止阶段、单帧最长处理时间和系统暂停次数，以及双方的机型、iOS、App 构建号。前者可区分“后续帧很少进入”与“进入后持续匹配失败”，并核对是否走过恢复分支。

本轮交付为问题定位和本地复现证据，不是修复已发布。临时让目标页面稳定后再慢速滚动可用于对照，但等待本身不保证收到三次相同帧，不能作为正式解决方案。
