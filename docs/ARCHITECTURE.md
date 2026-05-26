# ARCHITECTURE

最近自查日期：2026-05-26

## 总体架构

Rokurics 是一个 Swift/Xcode 多端项目：

- iPhone app 负责本地录音、录音 metadata、学习库浏览、Mac 配对、上传录音、展示 Mac 侧同步回来的转写/笔记、以及前台心跳/本地网络同步。
- macOS app 负责生成本机 TLS 身份、启动本地 HTTPS receiver、配对 iPhone、验证 HMAC 签名、接收 metadata/audio、维护 Audio Inbox/学习库、调用 whisper.cpp 或 mock 转写、调用本地/云端兼容 LLM 生成笔记、提供 AI Chat。
- `RokuricsShared/` 承担跨端 UI 和共享模型。当前共享边界还不完整，iPhone/Mac 两边仍有部分同名模型或 store 文件。
- Live Activity extension 展示录音状态，attributes 放在 `RokuricsLiveActivitiesShared/`。

## 模块边界

### iPhone 侧

- UI 层：`RokuricsHomeView`、`RecordingSessionView`、`RecordingLibraryView`、`RecordingStudyDetailPage`、`MacConnectionView`、`IPhoneSettingsView`、`IPhoneAIChatView`。
- 录音域：`RecordingManager` 使用 `AVAudioRecorder` 管理状态机、计时、暂停/恢复、保存与 Live Activity 更新。
- 本地存储：`AudioFileStore` 管理 app Documents 下 `Rokurics/Recordings` 和 `Rokurics/Metadata`；所有相对路径都基于 Rokurics 根目录校验。
- 学习库：`StudyLibraryStore` 在本地 `study/` 下维护 items/folders/index/hierarchy rules，并从录音 metadata 合并视图。
- 上传：`RecordingUploadCoordinator` 管理 job ledger、重试和状态；`RecordingUploadClient` 决定单请求上传或 resumable chunk 上传；`SecureMacUploadClient` 负责 HTTPS、证书 pinning、HMAC header。
- 连接状态：`SecureMacConnectionStore` 将 host/port/name 等写入 UserDefaults，将 device id、shared secret、fingerprint 写入 Keychain。
- 同步：`LocalNetworkSyncAppService` 由 `RokuricsApp` 在 app active 时启动，组合心跳、inventory diff、metadata/artifact 同步与缺失音频上传。

### Mac 侧

- UI 层：`MacRootView` 使用 `NavigationSplitView` 组织 dashboard、iPhone connection、study library、AI chat、settings。
- HTTPS receiver：`SecureReceiverService` 持有 identity、paired devices、request verifier、file stores 和 `SecureLocalHTTPSServer`。
- 路由层：`SecureLocalHTTPSServer` 直接基于 Network.framework 处理 TLS listener、HTTP parsing、health/fingerprint/pair/upload/sync routes。
- 安全层：`MacIdentityManager` 生成/加载本机 signing key、TLS private key 和自签证书；`RequestVerifier` 执行 path/content-type/body-size/header/HMAC/timestamp/nonce 校验。
- 文件层：`MacRecordingFileStore` 管理 Application Support 下 audio inbox、upload sessions、transcripts、metadata index、receive log；`AudioInboxStore` 将文件状态映射到 UI。
- 转写层：`TranscriptionCoordinator` 读取收件箱 source，使用 `TranscriptionSettingsStore` 选择 mock 或 whisper.cpp provider，输出到 `TranscriptStore`。
- 音频预处理：`AudioPreprocessor` 对非 wav 输入生成 whisper-compatible WAV；默认 native preferred，可按配置使用 ffmpeg。
- 笔记层：`NoteGenerationCoordinator` 加载 transcript，按长度选择单次或分段生成，输出到 `NoteStore`。
- 聊天层：`ChatCoordinator` 管理会话、上下文、附件、本地保存和 provider 调用；共享模型在 `RokuricsShared/ChatModels.swift`。
- 学习库层：`StudyLibraryStore` 从 receive.json、transcript/note 结果和 stored metadata 构造学习库，支持文件夹、标签、移动、重命名、废纸篓和 sync manifest。

## 主要数据模型

- `RecordingMetadata`：iPhone 录音 metadata。包含 id、title、relative audio/metadata path、created/ended/duration、format/codec、upload/transcription/note status、tags、study filing、upload progress、soft delete 字段。
- `IncomingRecordingMetadata`：Mac 接收 iPhone metadata 的 payload 模型。
- `RecordingReceiveRecord`：Mac `receive.json` 记录。包含 source device、status、processing status、audio/metadata/transcript/note relative path、checksum、studyFiling、chunk metadata、delete state、last upload state。
- `StudyFilingPath`：四层学习路径：`type`、`subject`、`chapter`、`topic`。
- `StudyItemMetadata`：学习库 item，可表示录音 bundle 或 standalone note；包含资源相对路径、tags、folderIDs、sync fields、trash state。
- `StudyFolderMetadata`：学习库 folder metadata，基于 level/path 生成稳定 folderID。
- `StudyLibrarySyncManifest`：跨设备学习库同步包，包含 items/folders/tombstones/pendingUploads 和 checksum。
- `LocalNetworkSyncInventory`：本地网络同步 inventory，包含 device、recordings、folders、studyItems、artifacts 和可选 manifest。
- `ChatConversation`、`ChatContext`、`ChatAttachment`：AI Chat 本地会话、学习库上下文、附件模型。

## 关键业务链路

### 录音保存链路

1. `RokuricsApp` 创建 `ContentView`。
2. `ContentView` 创建 `RecordingManager`。
3. 用户在 `RokuricsHomeView` / `RecordingSessionView` 触发录音。
4. `RecordingManager` 请求麦克风权限，配置 `AVAudioRecorder`，写入 `.m4a`。
5. 停止录音后进入 filing/saving，使用 `AudioFileStore` 生成 `Recordings/*.m4a` 和 `Metadata/<id>.json`。
6. `StudyLibraryStore` 刷新后把录音合并为学习库 item。

### iPhone 到 Mac 安全配对

1. Mac `SecureReceiverService.beginPairing()` 确保 HTTPS listener ready 后通过 `PairingManager` 生成 6 位 pairing code。
2. Mac pairing payload 包含 host、port、pairing code、certificate fingerprint。
3. iPhone `RokuricsPairingInfoParser` 解析配对信息。
4. iPhone `SecureMacUploadClient.pair()` 以 HTTPS 调用 `/pair`，同时做证书指纹 pinning。
5. Mac `PairingBootstrapRouteHandler` 校验 pairing code，生成 device id 和 shared secret。
6. iPhone `SecureMacConnectionStore.savePairing()` 把 device id/shared secret/fingerprint 写入 Keychain，把 host/port/name 写入 UserDefaults。

### 上传录音链路

1. iPhone `RecordingUploadCoordinator` 创建/读取上传 job ledger。
2. `RecordingUploadClient` 先上传 metadata 到 `/upload-recording-metadata`。
3. 小于阈值的音频走 `/upload-recording-audio` 文件上传。
4. 大音频走 resumable session：`/upload-recording-audio-session/start`、`status`、`chunk`、`finalize`。
5. 每个 signed request 使用 `X-Rokurics-*` headers，签名 payload 为 method/path/timestamp/nonce/bodySHA256。
6. Mac `RequestVerifier` 校验 method、path、content type、body size、设备、timestamp window、nonce replay、body hash、HMAC。
7. Mac `MacRecordingFileStore` 写入 audio inbox，维护 metadata/audio/receive.json/index/log。
8. iPhone 根据 Mac 响应更新 metadata upload status 和 progress。

### Mac 转写链路

1. `MacStudyLibraryView` 或 Audio Inbox 触发 `TranscriptionCoordinator.startTranscription(recordingID:)`。
2. `TranscriptionCoordinator` 将 receive.json status 写为 queued/transcribing。
3. 读取 `MacRecordingFileStore.transcriptionSource`，决定输出目录。
4. `LongAudioTranscriptionPlanner` 对超过 30 分钟的音频使用 15 分钟 chunk plan。
5. `WhisperCppTranscriptionProvider` 解析 runtime：优先 app bundle 内 `Contents/Helpers/rokurics-whisper`，否则使用外部 debug 配置。
6. `AudioPreprocessor` 将 m4a/aac 等转换为 WAV，chunk 模式按时间段转换。
7. `TranscriptStore` 写入 `transcript.json`、`transcript.md`，chunk 模式还写入 `chunks/chunk_*.json/md`。
8. `MacRecordingFileStore.updateTranscriptionStatus` 回写 receive.json。

### Mac 笔记生成链路

1. `NoteGenerationCoordinator.startNoteGeneration(recordingID:)` 要求 transcriptionStatus 为 `transcribed`。
2. `NoteGenerationTranscriptLoader` 加载 transcript JSON 或 markdown。
3. `LongNoteGenerationPlanner` 对超过阈值的 transcript 使用分段生成。
4. Provider 可为 mock、OpenAI-compatible 或 Anthropic Messages。
5. `NoteStore` 写入 `note.md`、`summary.json`；chunk 模式写入 `sections/section_*.md` 后组合最终 note。
6. receive.json 更新 note status、provider、model、endpoint description、sections。

### 本地网络同步链路

1. iPhone `LocalNetworkSyncAppService` 在 app active 且已配对时启动 heartbeat 和 periodic sync。
2. 心跳使用 `/connection/heartbeat`，只传连接状态，不带文件或秘密。
3. sync tick 构造 `LocalNetworkSyncInventory`，调用 `/sync/inventory`。
4. `LocalNetworkSyncDiffPlanner` 对 recordings/folders/studyItems/artifacts 计算 upload/download/conflict/no-op。
5. metadata 通过 `/sync/apply-metadata` 传 manifest；artifact 通过 `/sync/artifact-request` 取 base64 数据。
6. transcript/note artifact 可自动下载；audio 不自动下载，只通过上传队列补齐。

### AI Chat 链路

1. Mac `MacAIChatView` 使用 `ChatCoordinator`。
2. 用户可从学习库导入 folder/item，上下文由 `StudyLibraryContextExporter` 和 `ChatContextBuilder` 生成。
3. `ChatCoordinator` 保存 conversations/contexts/attachments 到 Application Support `chats/`。
4. Provider 与笔记生成设置共用：mock、OpenAI-compatible、Anthropic Messages。
5. 当前 provider 只发送文字和支持的附件；不支持的附件保留本地并给提示。

## 本地存储与路径约定

- iPhone 默认根：Documents 下 `Rokurics/`。
  - `Recordings/`
  - `Metadata/`
  - `study/items/`
  - `study/folders/`
  - `study/index.json`
  - `study/hierarchy-rules.json`
  - `Sync/`
- Mac 默认根：Application Support 下 bundle-profile 名称。
  - local build 使用 `RokuricsLocal`，production 使用 `Rokurics`。
  - security directory local/production 分别使用 Mac security profile 名称。
  - `audio/inbox/`
  - `audio/upload-sessions/`
  - `transcripts/`
  - `notes/`
  - `metadata/`
  - `system/`
  - `chats/conversations/`
  - `chats/contexts/`
  - `chats/attachments/`

所有关键 store 都有路径内包含校验，修改路径逻辑时必须保留这些约束。

## 安全、鉴权与权限机制

- iPhone 到 Mac 使用 HTTPS，本机 Mac 生成自签 TLS certificate。
- iPhone 使用 certificate SHA256 fingerprint pinning；fingerprint 长度必须为 64 hex。
- 已配对请求使用 shared secret HMAC-SHA256，headers 包括 device id、timestamp、nonce、body SHA256、signature。
- Mac `RequestVerifier` 有 timestamp window 和 per-device nonce replay cache。
- shared secret、device id、fingerprint 在 iPhone Keychain 中保存，不应回落到 UserDefaults。
- Mac TLS private key 使用 Data Protection Keychain；签名 identity 文件只保存在本地 security directory。
- Mac sandbox entitlements 包含 network client/server、user-selected executable/read-only 和 app-scope bookmarks。
- whisper.cpp/ffmpeg/model 访问依赖安全范围书签或 bundle helper。

## 当前架构风险与不确定点

- iPhone 与 Mac 有部分同名模型/store 源码但内容不同，例如 `StudyLibrarySyncModels.swift`、`ConnectionSyncStateStores.swift`、`RecordingTitleEditing.swift`。修改协议或数据结构时必须双端审查。
- Git-backed study sync 默认禁用，但代码和测试仍存在；不要误以为本地网络同步和 Git-backed sync 是同一套开关。
- Mac build phase 依赖仓库外本地 whisper.cpp 编译产物或 `WHISPER_CPP_ROOT`；新机器/CI 可复现性需要确认。
- `TranscriptionQueue` 目前只是占位状态对象，真实转写由 `TranscriptionCoordinator` 执行。
- UI 测试覆盖很轻，核心保障主要来自 Swift Testing 单元测试。
- `RokuricsVisualDiagnostics/` 和顶层图标源的维护策略需要人工确认。
