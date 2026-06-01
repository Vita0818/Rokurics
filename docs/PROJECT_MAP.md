# PROJECT_MAP

最近自查日期：2026-06-01

本文描述当前仓库结构。判断依据来自 Xcode project、scheme、Swift 源码、测试文件、脚本和现有 `docs/LongRecordingTestPlan.md`、`docs/SYNC_STATE_AUDIT.md`。

## 顶层目录树

```text
.
├── Rokurics/
├── RokuricsMac/
├── RokuricsShared/
├── RokuricsLiveActivities/
├── RokuricsLiveActivitiesShared/
├── RokuricsTests/
├── RokuricsMacTests/
├── RokuricsUITests/
├── RokuricsMacUITests/
├── RokuricsVisualDiagnostics/
├── Scripts/
├── docs/
├── Rokurics.xcodeproj/
├── RocuricsNewIcon.png
├── .gitattributes
└── .gitignore
```

排除扫描/理解优先级较低的目录：`.git/`、`.build/`、Xcode DerivedData、构建产物、依赖缓存、`xcuserdata/`、`__pycache__/` 等。

## 顶层职责

- `Rokurics/`：iPhone/iPad app 源码。包含 SwiftUI UI、录音、iPhone 本地文件存储、学习库、Mac 配对、HTTPS/HMAC 上传、本地网络同步、iPhone 侧 AI 聊天配置。
- `RokuricsMac/`：macOS app 源码。包含 SwiftUI 主界面、HTTPS 接收服务、TLS 身份、配对设备、录音收件箱、转写、笔记生成、AI 聊天、学习库、同步、本地文件和安全范围书签。
- `RokuricsShared/`：被 iPhone 与 Mac target 共同编译的共享 SwiftUI 组件和共享模型，当前包含学习库 UI、聊天模型和共享样式。
- `RokuricsLiveActivities/`：WidgetKit Live Activity extension 代码。
- `RokuricsLiveActivitiesShared/`：Live Activity attributes，供 iPhone app 与 extension 共用。
- `RokuricsTests/`：iPhone app 单元测试，使用 Swift Testing。
- `RokuricsMacTests/`：Mac app 单元测试，使用 Swift Testing，覆盖接收、安全、转写、笔记、聊天、学习库和同步。
- `RokuricsUITests/`、`RokuricsMacUITests/`：XCTest UI 测试，目前是基础 launch / performance 模板级覆盖。
- `RokuricsVisualDiagnostics/`：视觉诊断截图与 DerivedData 记录，属于诊断资产，不是运行时代码。
- `Scripts/`：辅助脚本和生成图标资产。`embed_whisper_helper.sh` 由 Mac target 构建阶段调用；`export_finder_folder_icons.swift` 生成 Finder 风格文件夹图标。
- `docs/`：项目说明文档，包含常驻上下文、架构/测试/禁区说明、长录音验证计划和连接/上传/同步状态审计。
- `Rokurics.xcodeproj/`：Xcode project。使用 file system synchronized groups；共享 scheme 为 `Rokurics` 与 `RokuricsMac`。

## Xcode target 与 scheme

`xcodebuild -list -project Rokurics.xcodeproj` 显示：

- Targets:
  - `Rokurics`
  - `RokuricsTests`
  - `RokuricsUITests`
  - `RokuricsMac`
  - `RokuricsMacTests`
  - `RokuricsMacUITests`
  - `RokuricsLiveActivities`
- Schemes:
  - `Rokurics`
  - `RokuricsMac`

target 编译边界：

- `Rokurics` target 包含 `Rokurics/`、`RokuricsShared/`、`RokuricsLiveActivitiesShared/`，并嵌入 `RokuricsLiveActivities` app extension。
- `RokuricsMac` target 包含 `RokuricsMac/`、`RokuricsShared/`，并有 `Embed whisper.cpp Helper` shell build phase。
- `RokuricsLiveActivities` target 包含 `RokuricsLiveActivities/` 和 `RokuricsLiveActivitiesShared/`。
- 测试 target 依赖各自 app target。

## 入口文件

- iPhone app：`Rokurics/RokuricsApp.swift`
  - `@main` app，创建 `LocalNetworkSyncAppService`，根据 scene phase activate/suspend。
- iPhone root UI：`Rokurics/ContentView.swift`
  - 创建 `RecordingManager`、`SecureMacConnectionStore`、`UserProfileStore`，进入 `RokuricsHomeView`。
- Mac app：`RokuricsMac/RokuricsMacApp.swift`
  - `@main` app，进入 `ContentView`。
- Mac root UI：`RokuricsMac/ContentView.swift`、`RokuricsMac/MacRootView.swift`
  - `MacRootView` 创建 `SecureReceiverService`、`AudioInboxStore`、转写/笔记/聊天 coordinator、设置 store 和用户 profile store。
- Live Activity extension：`RokuricsLiveActivities/RecordingLiveActivityWidget.swift`
  - `@main` widget bundle。

## iPhone 关键文件

- UI 与体验：
  - `RokuricsHomeView.swift`
  - `RecordingSessionView.swift`
  - `RecordingLibraryView.swift`
  - `RecordingStudyDetailPage.swift`
  - `StudyReadingPages.swift`
  - `MacConnectionView.swift`
  - `IPhoneSettingsView.swift`
  - `IPhoneAIChatView.swift`
- 录音与本地存储：
  - `RecordingManager.swift`
  - `AudioFileStore.swift`
  - `RecordingMetadata.swift`
  - `RecordingUploadStatus.swift`
  - `RecordingTitleEditing.swift`
- 上传与配对：
  - `SecureMacConnectionSettings.swift`
  - `SecureMacUploadClient.swift`
  - `RecordingUploadClient.swift`
  - `RecordingUploadCoordinator.swift`
  - `RecordingUploadPayload.swift`
  - `SecureUploadUtilities.swift`
  - `KeychainStore.swift`
- 学习库与同步：
  - `StudyFilingModels.swift`
  - `StudyLibraryStore.swift`
  - `StudyLibrarySyncModels.swift`
  - `StudyLibrarySyncCoordinator.swift`
  - `ConnectionSyncStateStores.swift`
  - `RecordingUploadCoordinator.swift` 中的 retry drainer 继续复用上传主路径。
- Live Activity：
  - `RecordingLiveActivityController.swift`
  - `RokuricsLiveActivitiesShared/RecordingLiveActivityAttributes.swift`

## Mac 关键文件

- UI：
  - `MacRootView.swift`
  - `MacSidebarView.swift`
  - `MacDashboardView.swift`
  - `MacIPhoneConnectionView.swift`
  - `MacStudyLibraryView.swift`
  - `MacAIChatView.swift`
  - `MacSettingsView.swift`
  - `MacTranscriptionSettingsView.swift`
  - `MacNoteGenerationSettingsView.swift`
  - `MacWhisperCppSettingsView.swift`
- HTTPS 接收与安全：
  - `SecureReceiverService.swift`
  - `SecureLocalHTTPSServer.swift`
  - `RequestVerifier.swift`
  - `PairingManager.swift`
  - `PairedDeviceStore.swift`
  - `MacIdentityManager.swift`
  - `SelfSignedCertificateBuilder.swift`
  - `MacSecurityUtilities.swift`
  - `RokuricsMac.entitlements`
- Mac 文件/收件箱：
  - `MacAppStorageProfile.swift`
  - `MacRecordingFileStore.swift`
  - `RecordingReceiveResult.swift`
  - `IncomingRecordingMetadata.swift`
  - `AudioInboxStore.swift`
  - `MacRecordingInboxItem.swift`
  - `ReceivedFileStore.swift`
- 转写：
  - `TranscriptionCoordinator.swift`
  - `TranscriptionProvider.swift`
  - `TranscriptionSettingsStore.swift`
  - `WhisperCppTranscriptionProvider.swift`
  - `WhisperCppRuntimeResolver.swift`
  - `WhisperCppTranscriptionConfiguration.swift`
  - `AudioPreprocessor.swift`
  - `NativeAudioConverter.swift`
  - `FFmpegAudioConverter.swift`
  - `TranscriptStore.swift`
  - `LongProcessingModels.swift`
- 笔记生成：
  - `NoteGenerationCoordinator.swift`
  - `NoteGenerationProvider.swift`
  - `NoteGenerationSettingsStore.swift`
  - `OpenAICompatibleNoteGeneration*`
  - `AnthropicMessages*`
  - `NoteGenerationTranscriptLoader.swift`
  - `NoteStore.swift`
- AI 聊天：
  - `ChatCoordinator.swift`
  - `ChatProvider.swift`
  - `RokuricsShared/ChatModels.swift`
  - `RokuricsShared/SharedChatComponents.swift`
- 学习库与同步：
  - `StudyLibraryStore.swift`
  - `StudyLibraryModels.swift`
  - `StudyLibrarySyncModels.swift`
  - `GitBackedStudyMetadataStore.swift`
  - `ConnectionSyncStateStores.swift`
  - `SecureLocalHTTPSServer.swift` 的 `/sync/inventory` 构建和 manual sync ack/tick 诊断。

## 配置文件

- `Rokurics.xcodeproj/project.pbxproj`
  - Xcode object version 77。
  - iOS deployment target: 26.4。
  - macOS deployment target: 26.4。
  - Swift version: 5.0 build setting。
  - Mac Debug bundle id 使用 local 后缀；Release 使用正式 bundle id。
  - Mac target 开启 App Sandbox，并指定 `RokuricsMac/RokuricsMac.entitlements`。
  - Mac target 有 `Embed whisper.cpp Helper` build phase；该 phase 依赖仓库外本地编译的 whisper.cpp 产物或 `WHISPER_CPP_ROOT`。
- `Rokurics.xcodeproj/xcshareddata/xcschemes/Rokurics.xcscheme`
  - build/run/test `Rokurics`，测试包含 `RokuricsTests` 和 `RokuricsUITests`。
- `Rokurics.xcodeproj/xcshareddata/xcschemes/RokuricsMac.xcscheme`
  - build/run/test `RokuricsMac`，测试包含 `RokuricsMacTests` 和 `RokuricsMacUITests`。
- `Rokurics/Info.plist`
  - 麦克风权限、本地网络权限、Live Activities、后台 audio mode、ATS local networking。
- `RokuricsLiveActivities/Info.plist`
  - WidgetKit extension。
- `RokuricsMac/RokuricsMac.entitlements`
  - App Sandbox、network client/server、user-selected executable/read-only、app-scope bookmarks。
- `.gitignore`
  - 忽略 `.build/`、`xcuserdata/`、Xcode 包产物等。

## 测试目录

- `RokuricsTests/RokuricsTests.swift`
  - iPhone 侧录音 metadata、学习库、上传队列、可恢复上传、本地网络同步、心跳、AI provider 预设等。
- `RokuricsMacTests/`
  - `RokuricsMacTests.swift`：接收服务、安全、配对、HMAC、TLS、可恢复上传、删除/恢复等大覆盖。
  - `StudyLibraryStoreTests.swift`：学习库、文件夹、重命名、移动、receive.json 兼容、sync manifest。
  - `StudyLibrarySyncTests.swift`：Git-backed sync 默认禁用、本地网络同步 endpoint。
  - `LongProcessingTests.swift`：长录音分块转写、长笔记分段、敏感输出过滤。
  - `AudioPreprocessorTests.swift`、`NativeAudioPreprocessorTests.swift`、`NativeAudioConverterTests.swift`：音频转码与 whisper 调用。
  - `WhisperCpp*Tests.swift`、`SecurityScopedFileAccessTests.swift`：whisper runtime、sandbox bookmark、权限诊断。
  - `ChatFeatureTests.swift`：聊天模型、上下文导入、附件、标题、UI 策略。
- `RokuricsUITests/`、`RokuricsMacUITests/`
  - 基础 XCTest UI launch/performance。

自查时统计到约 453 个 Swift Testing/XCTest 测试函数；具体数量会随源码变化。

## 资源目录

- `Rokurics/Assets.xcassets/`：iOS app icon、AccentColor、Finder 风格文件夹 icon variants。
- `RokuricsMac/Assets.xcassets/`：macOS app icon、AccentColor。
- `Scripts/GeneratedFinderFolderIcons/`：`export_finder_folder_icons.swift` 生成的 512px 备份 PNG。
- `RocuricsNewIcon.png`：顶层图标源文件，当前含义需要后续确认。
- `RokuricsVisualDiagnostics/StudyLibrary/`：学习库视觉诊断截图。

## 生成物/缓存目录

- `.build/`：Xcode/Swift 构建与 DerivedData 缓存，已在 `.gitignore` 中，不应作为源码依据。
- `RokuricsVisualDiagnostics/DerivedData/`：诊断相关 DerivedData 信息，不应视为业务源码。
- `xcuserdata/`：Xcode 用户状态，忽略。
- `Scripts/GeneratedFinderFolderIcons/`：生成图标备份；是否视为可再生资产需要人工确认，当前已在仓库文件列表中出现。

## 不确定项

- `RocuricsNewIcon.png` 的权威来源、是否仍参与资源生成：UNKNOWN。
- `RokuricsVisualDiagnostics/` 是否应长期保留全部截图，或只作为临时诊断输出：需要后续确认。
- iPhone/Mac 两侧存在部分同名同步/标题编辑源码，且内容不完全一致；是否计划收敛到共享模块：需要后续确认。
- Mac `Embed whisper.cpp Helper` build phase 目前依赖仓库外本地 whisper.cpp 编译产物；CI/他人机器的配置方式需要后续确认。
