# TESTING

最近自查日期：2026-05-26

## 环境要求

- macOS 与 Xcode：项目由 `Rokurics.xcodeproj` 管理，project `LastUpgradeCheck` 为 2640，target `CreatedOnToolsVersion` 为 26.4.1。
- iOS deployment target：26.4。
- macOS deployment target：26.4。
- Swift build setting：`SWIFT_VERSION = 5.0`。
- Mac app 需要 App Sandbox entitlements：`RokuricsMac/RokuricsMac.entitlements`。
- Mac 转写的 whisper.cpp helper：
  - 构建阶段执行 `Scripts/embed_whisper_helper.sh`。
  - 脚本优先读取 `WHISPER_CPP_ROOT`，否则回落到仓库外本地默认位置。
  - 需要已编译的 `whisper-cli` 和相关 dylib。
  - 文档不记录具体个人路径。
- iOS 测试需要可用 iOS Simulator；具体 simulator 名称本轮未确认。

## 依赖安装方式

未发现 `Package.swift`、`Package.resolved`、CocoaPods、Carthage checkout、npm/yarn/pnpm 等依赖入口。当前项目主要依赖 Apple SDK/frameworks 和仓库外 whisper.cpp 编译产物。

需要后续确认：

- whisper.cpp 在新机器或 CI 上的安装/编译方式。
- 是否存在未提交或未纳入仓库的本地依赖准备步骤。

## 构建命令

已确认 project 和 scheme 名称，但本轮未实际运行 build。

iPhone app build：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
```

Mac app build：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
```

注意：

- `RokuricsMac` build 会执行 `Embed whisper.cpp Helper`，缺少仓库外 whisper.cpp 产物或 `WHISPER_CPP_ROOT` 时可能失败。
- Mac Debug product name 在 scheme 中显示为 `RokuricsMac Local.app`。

## 单元测试命令

iPhone 单元/UI scheme 测试：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=<已安装模拟器名称>' test
```

Mac 单元/UI scheme 测试：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test
```

可按文件或测试名在 Xcode 中定向运行，或后续用 `-only-testing:` 缩小范围。具体 `-only-testing:` 标识本轮未验证。

## 集成测试命令

没有发现独立集成测试 runner。当前集成性质覆盖分布在：

- `RokuricsTests/RokuricsTests.swift`：上传队列、resumable upload、本地网络同步、heartbeat、sync manifest。
- `RokuricsMacTests/RokuricsMacTests.swift`：HTTPS receiver、pairing、HMAC、resumable route、delete/restore。
- `RokuricsMacTests/StudyLibrarySyncTests.swift`：Git-backed sync 和本地网络同步 endpoint。

建议使用上面的 scheme test 命令，或在 Xcode 中定向运行相关 test file。

## UI 测试命令

UI tests 包含在两个 app scheme 的 TestAction 中：

- `RokuricsUITests`
- `RokuricsMacUITests`

命令同上 `xcodebuild ... test`。当前 UI 测试主要是 launch/performance 模板，真实业务 flow 仍需要手动验证。

## 静态检查 / lint / format

未发现 SwiftLint、SwiftFormat、format/lint 脚本或 package manifest。

基础文档/空白检查：

```sh
git diff --check
```

Swift 编译级静态检查建议使用对应 `xcodebuild ... build` 或 `xcodebuild ... test`。

## 手动验证矩阵

### iPhone 录音

- 首次麦克风授权。
- 开始、暂停、恢复、停止录音。
- 低电量/后台 audio mode 下计时和状态。
- 保存时选择 filing：type/subject/chapter/topic。
- 录音列表、学习库、废纸篓、恢复、永久删除。

### iPhone 到 Mac 配对和上传

- Mac 启动 HTTPS receiver，复制 pairing info。
- iPhone 粘贴 pairing info，确认 host/port/code/fingerprint 解析。
- `/health` 指纹 pinning 成功和失败。
- pairing code 过期、错误 code、重新配对。
- 小文件单请求上传。
- 大文件 resumable 上传、断点重试、冲突处理。
- 上传成功后 iPhone metadata 变为 uploaded，Mac Audio Inbox 出现 recording。

### Mac 转写和笔记

- Mock transcription。
- whisper.cpp bundled helper。
- 外部 debug fallback。
- m4a 转 WAV。
- 35-45 分钟触发 chunked transcription。
- 2-3 小时长录音按 `docs/LongRecordingTestPlan.md` 验证。
- note generation mock/OpenAI-compatible/Anthropic。
- 长 transcript 分段生成 sections 后合并 final note。

### 学习库和同步

- iPhone/Mac 两端相同 filing 层级浏览。
- metadata-only sync 不删除真实 audio。
- transcript/note artifact 自动下载。
- audio 不自动下载，只通过上传队列补齐。
- folder rename/move/color/trash 不改变 itemID 和资源路径。
- 冲突场景保留可诊断状态。

### AI Chat

- 新建/切换/删除会话。
- 从学习库 folder/item 导入上下文。
- note summary 优先，transcript preview fallback。
- 大上下文截断。
- 附件保存和不支持附件时本地保留提示。
- provider 配置缺失、超时、空响应。

## 常见失败原因

- Mac build 找不到仓库外 whisper.cpp 编译产物；需要设置 `WHISPER_CPP_ROOT` 或准备本机 helper/dylib。
- iOS test 未指定存在的 simulator 名称。
- Mac sandbox 缺少安全范围书签，导致 whisper-cli/model/ffmpeg 访问失败。
- TLS identity 未生成或 Data Protection Keychain 中 SecIdentity 不可用，导致 HTTPS listener 启动失败。
- iPhone 保存的 certificate fingerprint 与 Mac 当前 TLS certificate 不一致，导致 pinning failure。
- HMAC 请求 timestamp 超过窗口、nonce 重放、body hash 不匹配、content type 不匹配、路径不在 allowlist。
- 长录音转写 provider timeout 或模型路径/权限错误。
- LLM provider base URL、model name、API key、max_tokens 配置错误。

## 本轮是否实际运行命令

本轮实际运行：

- `pwd`
- `git rev-parse --show-toplevel`
- `git status --short`
- `xcodebuild -list -project Rokurics.xcodeproj`
- 多个只读 `find`、`rg`、`sed`、`wc`、`diff -q`
- 写入文档后运行的验证命令见最终报告。

本轮未运行完整构建/测试。
