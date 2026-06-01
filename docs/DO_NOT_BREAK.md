# DO_NOT_BREAK

最近自查日期：2026-06-01

本文记录维护本项目时不应破坏的工程约束。修改前先读 `AGENTS.md`、`CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md` 和本文。

## 不得破坏的用户数据格式

- iPhone `RecordingMetadata` JSON：
  - 必须兼容缺失 `isDeleted`、`deletedAt`、`studyFiling`、upload progress 等历史字段。
  - `relativeAudioPath`、`relativeMetadataPath` 必须继续是 app Rokurics 根目录内相对路径。
  - `uploadStatus`、`transcriptionStatus`、`noteStatus` 字符串会被 UI、上传队列和 sync 使用。
- Mac `receive.json`：
  - 必须兼容旧 receive record 缺字段。
  - `recordingID`、`sanitizedRecordingID`、`metadataRelativePath`、`audioRelativePath`、`transcriptRelativePath`、`transcriptMarkdownRelativePath`、`noteRelativePath` 是核心引用。
  - `transcriptionMode`、`transcriptionChunks`、`noteGenerationMode`、`noteSections` 支撑长录音定位失败 chunk/section。
  - soft delete 字段不能被当成物理删除指令。
- 学习库 metadata：
  - `StudyItemMetadata.itemID`、`StudyFolderMetadata.folderID` 必须稳定。
  - folder rename/move/color 不应改变 itemID、folderID 或真实资源路径，除非迁移逻辑和测试明确覆盖。
  - `StudyFilingPath` 四层语义为 `type/subject/chapter/topic`。
  - `StudyHierarchyRule.defaultCourseView` 默认层级不要随意改。
- Sync manifest：
  - `StudyLibrarySyncManifest.checksum` 计算字段不能随意增删 payload；如改 schema 必须保持旧 manifest 解码兼容。
  - `pendingUploads` 不应携带 shared secret、绝对路径或完整文件内容。
- Chat 数据：
  - `ChatConversation`、`ChatContext`、`ChatAttachment` 本地 JSON 需兼容缺字段。
  - attachment `relativePath` 必须保持在 `chats/attachments/<conversationID>/` 约束内。

## 不得破坏的文件路径约定

- iPhone app Documents 下：
  - `Rokurics/Recordings/`
  - `Rokurics/Metadata/`
  - `Rokurics/study/items/`
  - `Rokurics/study/folders/`
  - `Rokurics/study/index.json`
  - `Rokurics/study/hierarchy-rules.json`
  - `Rokurics/Sync/`
- Mac Application Support 下：
  - local build folder 与 production folder 由 `MacAppStorageProfile` 决定，不要硬编码成单一目录。
  - `audio/inbox/`
  - `audio/upload-sessions/`
  - `transcripts/`
  - `notes/`
  - `metadata/recordings-index.json`
  - `system/receive-log.json`
  - `system/connection-diagnostics.jsonl`
  - `chats/conversations/`
  - `chats/contexts/`
  - `chats/attachments/`
- Mac security directory：
  - `mac-identity.json`
  - `tls-certificate.der`
  - `tls-private-key.json`

当前源码的 TLS private key 是 app-local JSON 文件，不是 Data Protection Keychain 条目。文档或代码如要改回 Keychain 方案，必须同步更新 `MacIdentityManager`、pairing/fingerprint 测试和 listener smoke tests。

任何文件写入、删除、移动都必须保留 `isInsideRoot` / `isInside...Directory` / safe path component 这类路径防逃逸检查。

## 不得破坏的 API / 路由 / 协议

Mac HTTPS routes：

- `GET /health`
- `GET /fingerprint`
- `POST /pair`
- `POST /upload-secure-test`
- `POST /upload-recording-metadata`
- `POST /upload-recording-audio`
- `POST /upload-recording-audio-session/start`
- `POST /upload-recording-audio-session/status`
- `POST /upload-recording-audio-session/chunk`
- `POST /upload-recording-audio-session/finalize`
- `POST /device/status`
- `POST /connection/heartbeat`
- `POST /sync/device-status`
- `POST /sync/status`
- `POST /sync/manifest`
- `POST /sync/apply`
- `POST /sync/inventory`
- `POST /sync/apply-metadata`
- `POST /sync/artifact-request`

Signed request headers：

- `X-Rokurics-Device-ID`
- `X-Rokurics-Timestamp`
- `X-Rokurics-Nonce`
- `X-Rokurics-Body-SHA256`
- `X-Rokurics-Signature`
- upload routes additionally use recording/session/chunk/upload-type headers.

Signature payload currently是：

```text
METHOD
PATH
TIMESTAMP
NONCE
BODY_SHA256
```

修改任一字段必须双端同步修改并补测试。

## 不得绕过的安全机制

- 不关闭 HTTPS 或 certificate pinning。
- 不把 `SecureMacUploadClient.isHTTPSUploadEnabled` 改成明文上传路径。
- 不绕过 `RequestVerifier`。
- 不扩大 route allowlist、content type allowlist、body size limit，除非测试覆盖风险。
- 不移除 timestamp window、nonce replay cache、constant-time signature compare。
- 不把 shared secret、device id、fingerprint 从 Keychain 降级存到 UserDefaults。
- 不在日志、文档、诊断报告中输出完整 shared secret、API key、证书私钥、完整 provider response JSON、完整 transcript。
- 不在日志、文档、诊断报告中输出 TLS private key JSON 的 base64 私钥内容。
- 不删除 Mac sandbox entitlements 中 user-selected executable/read-only、app-scope bookmarks、network client/server，除非有替代权限设计。
- 不绕过安全范围书签访问 whisper-cli/model/ffmpeg。

## 不得随意重构的核心模块

修改以下模块前必须先读相关测试，并计划双端回归：

- `Rokurics/RecordingManager.swift`
- `Rokurics/AudioFileStore.swift`
- `Rokurics/RecordingUploadCoordinator.swift`
- `Rokurics/RecordingUploadClient.swift`
- `Rokurics/SecureMacUploadClient.swift`
- `Rokurics/SecureMacConnectionSettings.swift`
- `Rokurics/StudyLibraryStore.swift`
- `Rokurics/StudyLibrarySyncModels.swift`
- `Rokurics/StudyLibrarySyncCoordinator.swift`
- `RokuricsMac/SecureReceiverService.swift`
- `RokuricsMac/SecureLocalHTTPSServer.swift`
- `RokuricsMac/RequestVerifier.swift`
- `RokuricsMac/MacRecordingFileStore.swift`
- `RokuricsMac/MacIdentityManager.swift`
- `RokuricsMac/PairingManager.swift`
- `RokuricsMac/StudyLibraryStore.swift`
- `RokuricsMac/TranscriptionCoordinator.swift`
- `RokuricsMac/WhisperCppTranscriptionProvider.swift`
- `RokuricsMac/AudioPreprocessor.swift`
- `RokuricsMac/NoteGenerationCoordinator.swift`
- `RokuricsMac/ChatCoordinator.swift`
- `RokuricsShared/ChatModels.swift`
- `Rokurics/StudyFilingModels.swift`

## 不得删除或覆盖的资源

- `Rokurics/Assets.xcassets/` 下 AppIcon、AccentColor、Finder folder imagesets。
- `RokuricsMac/Assets.xcassets/` 下 AppIcon、AccentColor。
- `RokuricsLiveActivitiesShared/RecordingLiveActivityAttributes.swift`。
- `Scripts/GeneratedFinderFolderIcons/` 已存在的生成图标备份，删除前需确认是否可再生且用户同意。
- `RokuricsVisualDiagnostics/StudyLibrary/` 截图资产，删除前需确认其诊断价值和替代方案。

## 不得引入的架构倒退

- 不把 Mac receiver 改回明文 HTTP 或不校验 fingerprint 的 HTTPS。
- 不把大音频上传改回一次性读入内存后发送；当前大文件路径应保持 resumable chunk。
- 不让 transcript/note artifact 同步自动下载 audio；audio 自动下载当前明确禁止。
- 不在 metadata/inventory/sync manifest 中携带绝对本机路径或 secrets。
- 不让学习库移动/重命名真实移动 transcript/note/audio 资源，除非实现完整迁移和回滚。
- 不把 mock provider 当成真实生产 provider 结果写死。
- 不把 `TranscriptionQueue` 当成真实任务引擎；真实转写当前在 `TranscriptionCoordinator`。

## 同步/上传状态机禁区

- 不在 view lifecycle、folder/list/detail onAppear、study library refresh、Mac Audio Inbox refresh 中创建 recording audio upload job。
- 不把 metadata uploaded、manifest applied、receive record existing 或 UI “已上传”显示状态当成 audio uploaded。
- 不把 completed upload ledger 单独当成 no-op；只有 peer inventory 明确报告同 recording 的 `audioAvailable=true` 且 hash/size 与本地一致，才可视为 audio no-op。
- 不把 peer audio unknown 当成普通 sync 下的可补传事实；普通 sync 应 deferred，只有显式用户手动上传或 retry drainer 可以带明确 reason 继续。
- 不覆盖 Mac 已有但 hash/size 不同的 recording audio；该场景必须保留 conflict/fatal 诊断和人工可见状态。
- 不让 UI display state 反向驱动上传、重试或 sync tick。展示状态只能来自业务状态，不能成为业务状态源。
- 不在主线程/主 actor 路径做全量大文件 SHA256、全量 inventory、全量 inbox 扫描或高频 JSON 诊断写入；如必须读取，应使用 checksum cache、增量状态或后台执行。
- 不让 retry pending 永久只显示等待；`nextRetryAfter` 到期后必须由 retry drainer/queue drain 去重后重新进入上传主路径。
- 不把 Mac 手动同步实现成直接假定 iPhone 已同步。Mac 只能发 pending signal；必须保留 pending created、heartbeat consumed、iPhone acked、tick started/completed/failed/timeout 的状态回执。

## 修改前必须阅读的关键源码位置

按任务类型选择：

- 录音/metadata：`Rokurics/RecordingManager.swift`、`Rokurics/AudioFileStore.swift`、`Rokurics/RecordingMetadata.swift`。
- 上传/配对：`Rokurics/RecordingUploadCoordinator.swift`、`Rokurics/RecordingUploadClient.swift`、`Rokurics/SecureMacUploadClient.swift`、`Rokurics/SecureMacConnectionSettings.swift`。
- Mac receiver：`RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`、`RokuricsMac/RequestVerifier.swift`、`RokuricsMac/MacRecordingFileStore.swift`。
- 学习库：`Rokurics/StudyFilingModels.swift`、`Rokurics/StudyLibraryStore.swift`、`RokuricsMac/StudyLibraryStore.swift`。
- 同步：两端 `StudyLibrarySyncModels.swift`、两端 `ConnectionSyncStateStores.swift`、`Rokurics/StudyLibrarySyncCoordinator.swift`、`RokuricsMac/GitBackedStudyMetadataStore.swift`。
- 转写：`RokuricsMac/TranscriptionCoordinator.swift`、`RokuricsMac/WhisperCppTranscriptionProvider.swift`、`RokuricsMac/AudioPreprocessor.swift`、`RokuricsMac/TranscriptStore.swift`、`RokuricsMac/LongProcessingModels.swift`。
- 笔记：`RokuricsMac/NoteGenerationCoordinator.swift`、`RokuricsMac/NoteStore.swift`、`RokuricsMac/OpenAICompatibleNoteGeneration*`、`RokuricsMac/AnthropicMessages*`。
- 聊天：`RokuricsMac/ChatCoordinator.swift`、`RokuricsMac/ChatProvider.swift`、`RokuricsShared/ChatModels.swift`。
- 构建/权限：`Rokurics.xcodeproj/project.pbxproj`、`RokuricsMac/RokuricsMac.entitlements`、`Scripts/embed_whisper_helper.sh`。

## 回归验证要求

按变更范围选择最小充分验证：

- 文档-only：`git diff --check`、`git status --short`，并抽查文档链接/文件名。
- iPhone 录音/学习库：运行 `RokuricsTests` 中相关 Swift Testing；手动验证录音保存、列表、学习库和废纸篓。
- 上传/安全：运行 iPhone upload tests 和 Mac receiver/security tests；手动验证 pairing、health、small upload、resumable upload。
- Mac receiver：运行 `RokuricsMacTests/RokuricsMacTests.swift` 中 pairing/HMAC/resumable/delete 相关测试。
- 转写/音频：运行 `AudioPreprocessorTests`、`NativeAudioPreprocessorTests`、`WhisperCppRuntimeResolverTests`、`LongProcessingTests` 中相关测试；必要时手动跑 mock/whisper。
- 笔记/AI：运行 `LongProcessingTests`、`ChatFeatureTests`、note generation provider 相关测试；手动验证 provider 配置错误和成功路径。
- 同步：运行两端 sync tests；手动验证 metadata-only sync 不删音频、artifact download 不含 audio、peer unknown deferred、retry drainer 到期恢复、Mac 手动同步 pending/ack/timeout。
- UI：运行对应 scheme UI tests；关键 flow 仍需手动验证。
