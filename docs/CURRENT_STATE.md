# CURRENT_STATE

最近一次自查日期：2026-06-01

## 2026-06-01 连接/上传/同步修复补充

本轮根据同步状态审计修复连接、上传和同步层：上传链路继续通过 `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` 主路径把 iPhone 录音 metadata/audio 发送到 Mac；音频上传判断仍统一在 `RecordingAudioUploadDecisionEvaluator`，并扩展了 retry drainer、peer unknown、peer conflict、fatal failure 和展示状态。

当前真实问题和风险：

- Mac 侧“立即同步”仍是 `SecureReceiverService.prepareManualStudyLibrarySync` 写 pending sync request，等待 iPhone 前台 heartbeat 收到 `syncStartSignal` 后再执行 tick；现在增加 pending 去重、超时状态、ack/tick started/completed/failed 诊断，但 iPhone 不 active 或 heartbeat 未运行时仍不会被 Mac 直接拉起。
- debug 启动、app activation、periodic sync 和手动 sync 仍属于可创建上传任务的 trigger；如果 Mac inventory 明确报告 metadata-only/missing 会补传音频。peer unknown 在普通 sync 中会 deferred，不再被当作同步收敛上传；用户手动按钮会标记为 manual force，retry drainer 会标记为 retry-drainer。
- `RecordingUploadStatus.uploaded` 是 metadata/上传显示状态，不能单独证明 Mac 已有 audio。最终 no-op 必须以 peer inventory 中同 recording 的 hash/size 与本地音频一致为准。
- retryable failure 到期后现在由 `LocalNetworkSyncAppService` 调用 `RecordingUploadCoordinator.drainEligibleRetryJobs` 重新进入同一上传主路径；未到 `nextRetryAfter` 的任务继续 backoff，不会重复建普通上传任务。
- 同步和 inventory 的 UI 卡顿风险已通过 `LocalNetworkChecksumCache` 和 off-main hash 计算降低；`StudyLibraryStore.makeSyncManifest`、recording reload、目录扫描和高频诊断写入仍需在真机长录音/大库场景继续观察。

`docs/SYNC_STATE_AUDIT.md` 已更新为修复后的触发图、真值表、no-op 边界、诊断信号、剩余风险和验证计划。

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

上方 2026-05-26 工作区列表是历史记录。本轮 2026-06-01 启动时工作区已有未提交业务源码/测试改动和 `.DS_Store`；本轮在这些既有改动之上修改了连接/上传/同步相关源码、测试和文档，不回退或清理用户已有改动。

## 当前已实现能力

- iPhone 录音：`RecordingManager` 管理录音状态、权限、暂停/恢复、保存、Live Activity、metadata 刷新。
- iPhone 本地存储：`AudioFileStore` 写入录音文件和 metadata JSON，并对相对路径/删除路径做仓内根目录校验。
- iPhone 学习库：`StudyLibraryStore` 能从录音 metadata 和 stored study metadata 构造学习库，支持 filing candidates、folders、items、trash/restore/permanent delete。
- iPhone 到 Mac 配对：`SecureMacConnectionStore`、`SecureMacUploadClient` 支持配对信息解析、HTTPS health check、certificate pinning、pair endpoint、Keychain 持久化。
- iPhone 上传：`RecordingUploadCoordinator` 与 `RecordingUploadClient` 支持 metadata 上传、小文件单请求 audio 上传、大文件 resumable chunk 上传、ledger、retry drainer、progress、冲突/致命失败展示。
- Mac HTTPS receiver：`SecureReceiverService` 和 `SecureLocalHTTPSServer` 支持 TLS listener、health/fingerprint/pair/upload/sync/heartbeat routes。
- Mac 请求鉴权：`RequestVerifier` 校验 method、path、content-type、body size、security headers、timestamp、nonce、body hash 和 HMAC。
- Mac 收件箱：`MacRecordingFileStore` 保存 metadata/audio/receive.json/index/log，支持冲突检测、可恢复上传 session、soft delete/restore/permanent delete。
- Mac 学习库：`StudyLibraryStore` 支持 receive.json 派生 item、stored item/folder metadata、移动/重命名/颜色/废纸篓、sync manifest。
- 转写：`TranscriptionCoordinator` 支持 mock 与 whisper.cpp provider；`LongAudioTranscriptionPlanner` 对长录音分块；`TranscriptStore` 写 JSON/Markdown。
- 音频预处理：`AudioPreprocessor` 默认 native conversion，必要时支持 ffmpeg；安全范围书签和 sandbox 诊断有测试覆盖。
- 笔记生成：`NoteGenerationCoordinator` 支持 mock、OpenAI-compatible、Anthropic Messages；长 transcript 可分段生成并组合最终 note。
- AI Chat：`ChatCoordinator` 支持会话、上下文导入、附件本地保存、provider 调用、标题生成；共享模型在 `RokuricsShared/ChatModels.swift`。
- 本地网络同步：iPhone active 时通过 heartbeat、inventory、metadata/artifact diff、artifact download、缺失 audio upload 和 retry drainer 进行同步；Git-backed sync 默认禁用。当前音频 no-op 只能在 Mac inventory 明确报告同 hash/size 时成立，不能假设所有双向同步状态已完全收敛。
- Live Activity：iPhone app 与 extension 共享 `RecordingLiveActivityAttributes`。

## 当前未完成或占位能力

- `TranscriptionQueue` 当前是占位状态对象，真实任务调度在 `TranscriptionCoordinator`。
- `TranscriptionProviderKind` 中存在 `mlxWhisper`、`localHTTP`、`cloudAPI`、`customCommand` 等 provider kind，但 `TranscriptionCoordinator.currentProvider()` 对这些路径抛 unsupported。
- Git-backed study sync 默认禁用；相关 store、endpoint 和测试存在，但不是默认运行路径。
- UI tests 主要是 Xcode 模板级 launch/performance，尚未覆盖真实录音、配对、上传、转写、笔记、学习库和聊天流程。
- CI/自动化构建入口未发现；当前确认的是 Xcode scheme 和本地命令。

## 当前已知 bug / 风险

- 工作区已有大量未提交改动，涉及业务源码、Xcode project、scheme、脚本和测试。未来修改前必须先确认这些改动是否属于用户正在进行的任务。
- 本地网络同步仍需真机验证：Mac 手动同步依赖 iPhone 前台 heartbeat，peer metadata-only/missing 会按 inventory 补音频，retry drainer 依赖 scheduler gate 和 backoff。
- 同步 UI 卡顿风险已降低但未消除：audio SHA256 已加 checksum cache/off-main 计算，学习库 manifest、录音 reload、Mac inbox 扫描和诊断写入仍可能成为大库瓶颈。
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

- 旧文档曾写 Mac TLS private key 在 Data Protection Keychain 中；当前源码 `MacIdentityManager` 实际使用 app-local `tls-private-key.json` 加 `SecIdentityCreate(nil, certificate, privateKey)`，测试也固定该行为。因此本轮文档改以源码为准，并把 Keychain 说法降为已纠正的旧文档冲突。
- 已有 `docs/LongRecordingTestPlan.md` 与当前 `LongProcessingModels.swift`、`TranscriptionCoordinator.swift`、`NoteGenerationCoordinator.swift` 的长录音分块思路总体一致；未发现需要在本轮标记的冲突。
- 发现构建配置/脚本中存在仓库外本地 whisper.cpp 路径依赖。为避免写入个人隐私路径，本文档只记录抽象依赖，不复制具体本机路径。
