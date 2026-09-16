# 0.1.6 启动状态与诊断界面验证

日期：2026-09-16。本记录仅覆盖主 App、诊断模型兼容性和合成示例界面；管线、ReplayKit 与真机验证由对应记录说明。未将用户视频或私人聊天用作夹具。

## 修复与设计

- 原先首页仅区分有没有图片分块，停止按钮无条件称“停止并生成长图”，起步一直没有确认连续滚动时缺少解释。现在候选单屏不算连续内容；首页显示“等待目标内容”，提示进入目标页面缓慢上下滚动，停止按钮显示“停止捕捉”。已确认内容后才显示正在保留内容。
- 只有尚无确认图片且适配器记录的起步有效等待达到 8 秒时，解释“当前尚未形成长图”。短暂启动不报故障，不自动结束。系统暂停与恢复重叠状态优先显示各自提示，不在暂停时催促滚动。没有跨 App 浮层或新增通知权限。
- 新增可选持久化字段 `receivedVideoSamples`、`startupRecoveryMethod`、`startupWaitingState`、`startupWaitingSeconds`、`stableCandidateFrameCount`；旧诊断缺失时保留 nil/未记录，不把未知的接收样本数伪填为零。既有处理、衔接、拒绝、跳过、起点替换、最长耗时与暂停计数继续使用。
- 捕捉详情展示接收/跳过样本、处理/衔接/未衔接、起点替换与起步方式、起步状态与不含暂停的等待时间、当前稳定帧数。内容可在最高 240pt 的区域滚动，保留预览和保存/分享入口。
- 详情起点警告与示例说明允许自然换行，避免展开信息后被压缩。起点更换仍显示“请检查开头”，不宣称未采到的开头已完整保留。
- 兼容 `systemStop` / `systemEnded` 并支持新 `systemEntryStop`，详情统一说明系统入口也可能由用户手动停止；主文案为“广播已结束。”，历史持久化“捕捉已由系统结束。”在展示时同样转换，不修改原记录。指南不再无条件宣称停止后长图就绪。
- 上述新增界面文案均提供简体中文与英文。演示诊断仅在 DEBUG、`--demo`、`--uitesting` 加显式启动参数时生成，并保存在隔离的示例仓库。

## 验证结果

环境：项目 `scripts/xcode-env.sh` 选择 Xcode；专用模拟器 `Longlet-CIShareRegression`（`8B2EABE2-CC9C-41E3-9171-275D7345EEF5`），iOS 26.3.1。独立 DerivedData 为 `.work/DerivedData-Beta7-UI`，Debug 配置；不修改全局 xcode-select。

| 检查 | 结果与证据 |
| --- | --- |
| `CaptureNoticeTests` | 9/9 通过；包含旧诊断 JSON 解码/往返、未记录语义、短暂启动与 8 秒提示、暂停优先、已确认内容不再等待、系统入口新旧原因双语本地化。`.work/beta7-ui-unit.xcresult` / `.log` |
| 等待/暂停主界面 | 简中/英文四种状态均通过；实际检查文案与停止按钮，并截图。`.work/beta7-ui-flow.xcresult` 中对应测试通过 |
| 使用指南 | 系统启动、滚动和模拟器边界用例通过；同上 |
| 诊断详情 | 修正测试 AX 定位后双语通过；滚动至末尾暂停计数，预览高度与保存/分享可点击断言通过。`.work/beta7-ui-flow-recheck.xcresult` / `.log` |
| PNG/JPEG 保存与系统分享 | 补齐专用模拟器照片添加授权前置后通过；实际完成两种格式保存、打开系统分享并等到 Copy 动作可用。重跑包 2/2 通过 |
| 资源与差异 | 两份 Localizable.strings 的 plutil 检查通过，各 348 个唯一键，无重复；`git diff --check` 通过 |

最终示例说明换行调整后的诊断布局检查 1/1 通过（用例包含简中与英文两轮），记录在 `.work/beta7-ui-final-layout.xcresult` / `.log`。

## 失败与修正如实记录

1. 首次保存测试没有准备既有脚本要求的 `photos-add` 授权，卡在系统“允许/不允许”弹窗；测试录屏抽取帧 `.work/beta7-ui-evidence/save-failure-screen.png` 已确认原因。不是产品导出错误。
2. 随后的首次授权准备命令遇到测试结束后模拟器已 Shutdown。按用户规则，与保存验收合并累计为两次失败。根据该已确认状态，执行 boot → bootstatus Finished → privacy grant，全部退出 0；之后保存用例通过，没有第三次失败或绕路重试。
3. 首次诊断 UI 用例查找 `detail.diagnostics.scroll` 失败。失败 AX 层级显示内容实际已经展开，SwiftUI 将父 DisclosureGroup 标识传播给 ScrollView，实际标识是 `detail.diagnostics`。测试改用实际 ScrollView 的类型和标识定位，第二次通过。该独立卡点累计一次失败。

首次失败包 `.work/beta7-ui-flow.xcresult` 与日志完整保留，未用重跑结果覆盖。所有附件已导出到 `.work/beta7-ui-evidence/`，`manifest.json` 和 `recheck/manifest.json` 保存测试与附件对应关系。文件均为合成示例，没有真实聊天素材。

## 实际命令

```sh
source scripts/xcode-env.sh
xcodebuild -project ScrollCapture.xcodeproj -scheme ScrollCapture -configuration Debug \
  -destination 'platform=iOS Simulator,id=8B2EABE2-CC9C-41E3-9171-275D7345EEF5' \
  -derivedDataPath .work/DerivedData-Beta7-UI \
  -resultBundlePath .work/beta7-ui-unit.xcresult \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:ScrollCaptureTests/CaptureNoticeTests test
```

UI 使用相同工程、配置、设备和 DerivedData，初次结果包为 `beta7-ui-flow.xcresult`，选择以下四项：

- `ScrollCaptureUITests/ScrollCaptureUITests/testStartupWaitingAndPausedGuidanceInBothLanguages`
- `ScrollCaptureUITests/ScrollCaptureUITests/testStartupDiagnosticsAreTranslatedScrollableAndKeepExportsReachable`
- `ScrollCaptureUITests/ScrollCaptureUITests/testSavePNGAndJPEGThenOpenSystemShare`
- `ScrollCaptureUITests/ScrollCaptureUITests/testGuideExplainsPreparationAndSimulatorBoundary`

补齐权限前置后仅重跑诊断详情与保存两项，结果包 `beta7-ui-flow-recheck.xcresult`。最终只重跑诊断布局一项，结果包 `beta7-ui-final-layout.xcresult`。

```sh
xcrun simctl boot 8B2EABE2-CC9C-41E3-9171-275D7345EEF5
xcrun simctl bootstatus 8B2EABE2-CC9C-41E3-9171-275D7345EEF5 -b
xcrun simctl privacy 8B2EABE2-CC9C-41E3-9171-275D7345EEF5 grant photos-add dev.lzbaclz.longscreenshot
plutil -lint iOS/App/Resources/en.lproj/Localizable.strings iOS/App/Resources/zh-Hans.lproj/Localizable.strings
git diff --check
```

## 截图与验证边界

便于查看的截图副本：`.work/beta7-ui-evidence/startup-waiting-{zh-Hans,en}.png`、`startup-paused-{zh-Hans,en}.png`、`startup-diagnostics-{top,bottom}-{zh-Hans,en}.png`、`guide.png`、`system-share.png`。

本轮 UI 使用合成的数值诊断和示例图，验证状态呈现、兼容性与本机编辑导出入口；它不证明 ReplayKit 已收到这些样本、不证明跨应用起点算法或 iPhone 真机效果。后台不能在目标 App 上显示本 App 的提示，需返回 Longlet 才可查看；系统捕捉指示照常保留。新版真机立即滚动、系统暂停/恢复及不同 App 的反馈仍须独立记录。
