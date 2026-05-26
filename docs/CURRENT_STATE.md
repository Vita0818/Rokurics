# CURRENT_STATE

最近一次自查日期：2026-05-26

## 当前工作区状态摘要

启动检查结果：

```text
pwd: /Users/vita/Vitemis/Vela/Rokurics
git root: /Users/vita/Vitemis/Vela/Rokurics
```

自查开始前 `git status --short` 已存在以下用户改动；本轮不回退、不覆盖这些业务源码、配置、脚本或测试改动：

```text
 M Rokurics.xcodeproj/project.pbxproj
 M Rokurics.xcodeproj/xcshareddata/xcschemes/RokuricsMac.xcscheme
 M Rokurics/AudioFileStore.swift
 M Rokurics/ConnectionSyncStateStores.swift
 M Rokurics/RecordingManager.swift
 M Rokurics/RecordingMetadata.swift
 M Rokurics/RecordingUploadClient.swift
 M Rokurics/RecordingUploadCoordinator.swift
 M Rokurics/RokuricsApp.swift
 M Rokurics/SecureMacConnectionSettings.swift
 M Rokurics/SecureMacUploadClient.swift
 M Rokurics/StudyLibrarySyncCoordinator.swift
 M Rokurics/StudyLibrarySyncModels.swift
 M RokuricsMac/ConnectionSyncStateStores.swift
 M RokuricsMac/MacAppStorageProfile.swift
 M RokuricsMac/MacIdentityManager.swift
 M RokuricsMac/MacRecordingFileStore.swift
 M RokuricsMac/PairedDeviceStore.swift
 M RokuricsMac/PairingManager.swift
 M RokuricsMac/RecordingReceiveResult.swift
 M RokuricsMac/RequestVerifier.swift
 M RokuricsMac/SecureLocalHTTPSServer.swift
 M RokuricsMac/SecureReceiverService.swift
 M RokuricsMac/StudyLibrarySyncModels.swift
 M RokuricsMacTests/RokuricsMacTests.swift
 M RokuricsMacTests/StudyLibraryStoreTests.swift
 M RokuricsMacTests/StudyLibrarySyncTests.swift
 M RokuricsTests/RokuricsTests.swift
 M Scripts/embed_whisper_helper.sh
```

本轮只新增/更新项目文档，不修改业务源码、Xcode 构建逻辑、测试源码或脚本。

## 当前已实现能力

- iPhone 录音：`RecordingManager` 管理录音状态、权限、暂停/恢复、保存、Live Activity、metadata 刷新。
- iPhone 本地存储：`AudioFileStore` 写入录音文件和 metadata JSON，并对相对路径/删除路径做仓内根目录校验。
- iPhone 学习库：`StudyLibraryStore` 能从录音 metadata 和 stored study metadata 构造学习库，支持 filing candidates、folders、items、trash/restore/permanent delete。
- iPhone 到 Mac 配对：`SecureMacConnectionStore`、`SecureMacUploadClient` 支持配对信息解析、HTTPS health check、certificate pinning、pair endpoint、Keychain 持久化。
- iPhone 上传：`RecordingUploadCoordinator` 与 `RecordingUploadClient` 支持 metadata 上传、小文件单请求 audio 上传、大文件 resumable chunk 上传、ledger、retry、progress。
- Mac HTTPS receiver：`SecureReceiverService` 和 `SecureLocalHTTPSServer` 支持 TLS listener、health/fingerprint/pair/upload/sync/heartbeat routes。
- Mac 请求鉴权：`RequestVerifier` 校验 method、path、content-type、body size、security headers、timestamp、nonce、body hash 和 HMAC。
- Mac 收件箱：`MacRecordingFileStore` 保存 metadata/audio/receive.json/index/log，支持冲突检测、可恢复上传 session、soft delete/restore/permanent delete。
- Mac 学习库：`StudyLibraryStore` 支持 receive.json 派生 item、stored item/folder metadata、移动/重命名/颜色/废纸篓、sync manifest。
- 转写：`TranscriptionCoordinator` 支持 mock 与 whisper.cpp provider；`LongAudioTranscriptionPlanner` 对长录音分块；`TranscriptStore` 写 JSON/Markdown。
- 音频预处理：`AudioPreprocessor` 默认 native conversion，必要时支持 ffmpeg；安全范围书签和 sandbox 诊断有测试覆盖。
- 笔记生成：`NoteGenerationCoordinator` 支持 mock、OpenAI-compatible、Anthropic Messages；长 transcript 可分段生成并组合最终 note。
- AI Chat：`ChatCoordinator` 支持会话、上下文导入、附件本地保存、provider 调用、标题生成；共享模型在 `RokuricsShared/ChatModels.swift`。
- 本地网络同步：iPhone active 时通过 heartbeat、inventory、metadata/artifact diff、artifact download、缺失 audio upload 进行同步；Git-backed sync 默认禁用。
- Live Activity：iPhone app 与 extension 共享 `RecordingLiveActivityAttributes`。

## 当前未完成或占位能力

- `TranscriptionQueue` 当前是占位状态对象，真实任务调度在 `TranscriptionCoordinator`。
- `TranscriptionProviderKind` 中存在 `mlxWhisper`、`localHTTP`、`cloudAPI`、`customCommand` 等 provider kind，但 `TranscriptionCoordinator.currentProvider()` 对这些路径抛 unsupported。
- Git-backed study sync 默认禁用；相关 store、endpoint 和测试存在，但不是默认运行路径。
- UI tests 主要是 Xcode 模板级 launch/performance，尚未覆盖真实录音、配对、上传、转写、笔记、学习库和聊天流程。
- CI/自动化构建入口未发现；当前确认的是 Xcode scheme 和本地命令。

## 当前已知 bug / 风险

- 工作区已有大量未提交改动，涉及业务源码、Xcode project、scheme、脚本和测试。未来修改前必须先确认这些改动是否属于用户正在进行的任务。
- Mac build phase 和 `Scripts/embed_whisper_helper.sh` 依赖仓库外本地 whisper.cpp 产物或 `WHISPER_CPP_ROOT`；不同机器可能无法直接构建 Mac app。
- iPhone/Mac 双端有部分同名但不完全一致的模型文件，改同步协议或存储 schema 时容易单端遗漏。
- 转写、笔记、聊天会写 Application Support / Documents 下真实用户数据；调试时不能随意删除、重置或迁移这些目录。
- 文档中不记录完整本机私有路径、密钥、指纹或 shared secret；源码和脚本中如已有本机路径，只在文档中抽象描述。
- UI 测试覆盖较弱，视觉/交互回归更多依赖手动验证和现有截图资产。

## 当前优先级建议

1. 先稳定当前未提交改动的意图与归属，避免后续任务混入无关文件。
2. 为 Mac build phase 补充可复现的 whisper.cpp 依赖说明或 CI 友好方案，但不要在未确认前改脚本。
3. 若继续改同步协议，先补齐 iPhone/Mac 双端模型兼容测试，再改实现。
4. 若继续改 UI，优先补关键 flow 的 UI/manual 验证记录。

## 文档可信度说明

- 高可信：target/scheme、入口文件、核心 Swift 类型、路径约定、测试目录、已存在 build phase、权限配置。
- 中等可信：手动验证矩阵、推荐命令；部分命令未实际运行构建/测试，只依据 Xcode scheme 和配置推导。
- 需要后续确认：CI 环境、具体可用 iOS simulator 名称、whisper.cpp 依赖安装约定、视觉诊断资产生命周期。

## 源码与旧文档冲突记录

- 本轮新增的常驻上下文文档此前不存在，无同名旧文档冲突。
- 已有 `docs/LongRecordingTestPlan.md` 与当前 `LongProcessingModels.swift`、`TranscriptionCoordinator.swift`、`NoteGenerationCoordinator.swift` 的长录音分块思路总体一致；未发现需要在本轮标记的冲突。
- 发现构建配置/脚本中存在仓库外本地 whisper.cpp 路径依赖。为避免写入个人隐私路径，本文档只记录抽象依赖，不复制具体本机路径。
