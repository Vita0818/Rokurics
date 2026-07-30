# CURRENT_STATE

最近一次自查日期：2026-07-25

## 2026-07-25 活动同步同秒冲突修复

活动 old-kernel 同步此前把业务 `updatedAt` 在 Store JSON、签名 HTTP JSON、reconciliation ledger 和 planner 中统一压成 Unix 整秒。双端即使都在前台、同一局域网且传输完全正常，只要在同一秒内先后产生两个不同内容，真实先后关系也会在进入 planner 前丢失；planner 只能看到“时间相同 + hash 不同”，因而必然 deferred。这不是锁屏、后台或网络条件造成的失败。

共享 `SyncTimestampPolicy` 现在把活动同步业务时间规范化为最接近的 Unix 微秒，并固定编码为 6 位小数 ISO-8601；decoder 同时接受历史无小数整秒 payload。iPhone/Mac 的 Study Store、inventory/signed request/response、reconciliation record、上传版本 CAS/ledger，以及 Mac Git-backed metadata 都使用同一策略。`SyncReconciliationPlanner` 比较、写 record 和生成 record ID 时也使用相同微秒版本，因此同一秒内 `x.100000` 与 `x.900000` 可稳定选出真正较新的 source，传输方向翻转不改变 winner。

范围仍保持窄化：内容不同且业务时间精确相同到同一微秒时继续 deferred，不按 device ID、hash、请求方向或本地优先级任意选 winner；要解决这种真正同版本号分叉需要独立逻辑版本/HLC，不属于本轮。inventory checksum 的历史整秒投影暂不改动，以保持 checksum schema；它只校验 payload 完整性，不作为 LWW decision clock。默认关闭的 canonical pipeline 及其 equal-time 规则也未修改。新端可读取旧整秒数据，但旧端未承诺可读取新的小数 wire，因此本修复按用户要求以 iPhone 与 Mac 同时升级到最新构建为运行前提。

## 2026-07-25 generated artifact 时间戳 P1-2 修复

双端 generated artifact inventory 目前都以最终文件的 `modificationDate` 作为该内容版本的 `updatedAt`。旧接收路径虽然校验了 source hash/size，却在替换文件后留下本机接收时刻；于是一次传输会把“网络到达时间”伪装成业务修改时间。相同 hash/size 的紧邻下一轮本来仍会收敛，但只要之后任一端再次生成不同内容，LWW 就可能把旧接收副本误判为更新版本，反转真正 winner。

共享 `SyncArtifactModifiedAtPolicy` 现在把源时间按 `SyncReconciliationPlanner` 相同的微秒精度规范化，拒绝非有限或超出整数范围的时间，在最终文件上设置并读回校验 `.modificationDate`。Mac `/sync/artifact-put` 对 transcript/note/summary 的小文件、分块 finalization 和 `acceptedExisting` 重试都使用请求已有的 `updatedAt`；iPhone 小文件与分块下载落盘使用 peer inventory 中已经校验过的 artifact `updatedAt`。双端 `SyncStorageAdapter.atomicApply` 也遵守同一规则。`metadataJSON`、receiver-local `receiveJSON` 与 audio 不参与 generated-object reconciliation，因此不会被本策略改写。

本轮不改 wire schema、inventory hash、artifact ID、路径校验、route 或 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`。连接页“立即同步”仍是 discovery + 双向 action-scoped metadata apply，不会因此恢复自动内容传输。默认关闭的 canonical root-bound generated-artifact cutover payload 目前仍不携带 source `modifiedAt`，不是本轮活动路径，也不能被描述为已覆盖。

本地验证：iOS 与 Mac `build-for-testing` 均通过；iOS 正式标识定向测试 4/4 通过，覆盖时间规范化/fail-closed、iPhone adapter 替换落盘、后续 LWW winner、稳定跨端对象身份和旧 peer-newer fixture；`SyncReconciliationClosedLoopTests` 的 15 个唯一用例全部通过。Mac 定向测试 3/3 通过，直接覆盖小文件 replace、`acceptedExisting` 时间修复、分块 finalization 及 core inventory 回归。paired iPhone/Mac 真机测试尚未运行。

## 2026-07-25 同步对象身份 P1-1/P1-3 修复

同步 inventory 现在明确区分“业务对象身份”和“本机文件投影”。`metadata.json`、`receive.json` 与 audio 文件仍作为 `inventory.artifacts` 中的 transport/file facts 保留，继续携带应用根目录内的相对路径，并继续供 artifact lookup、kind/path allowlist、root containment 与 `artifactID = SHA256(kind|ownerID|logicalPathToken)` 校验使用；但它们不再被二次投影为 reconciliation `objects`。录音 metadata/audio 的跨端身份只使用 `recordingMetadata:<recordingID>` 与 `recordingAudio:<recordingID>`，因此 iPhone 的 `Recordings/...` 与 Mac 的 `audio/inbox/...` 不会再被误判为两个业务对象。

`receive.json` 一并排除是必要的同类修复：它由 Mac 接收端创建并持续更新，包含接收时间、awaiting-audio、last-attempt 等 receiver-local 事实，正常 iPhone -> Mac 场景天然只有 Mac 存在。若继续放进 reconciliation，即使同一局域网、双端前台也会永久产生单边 pending transfer。transcript/note/summary 等真正可移植的 generated artifact 仍保留对象级 reconciliation，不借本次修复静默隐藏。

兼容策略不改 wire schema：新构建器不再生成上述三类伪对象；解码旧版本 inventory 时仍原样保留 payload 中的 `objects`，确保发送端声明的 `inventoryHash` 可以按原 payload 复算，随后只在 `syncCoreInventory` 只读桥接处过滤。`SyncReconciliationStore.apply` 还会在原有锁与原子写内拒绝新写入并清理历史 `artifact_* + recordingMetadata/recordingAudio/receiveRecord` 记录，避免过滤后旧 ledger 永久残留。TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、route、artifact ID 公式和相对路径安全校验均未改变。

本地验证已覆盖：iOS 与 Mac `build-for-testing` 均通过；iOS 5 项定向测试 5/5 通过，覆盖新 inventory、不同双端路径收敛、旧 wire hash 兼容、旧 ledger 迁移和上一轮双向 metadata 回归；Mac 实际 inventory 构建用例通过，确认 receive/audio 仍在 artifacts、稳定 recording 对象仍在 objects、transcript 对象仍可同步。扩大测试仍会复现仓库已记录的旧断言/诊断失败，详见 `TESTING.md`，因此不声明完整 suite 全绿。paired iPhone/Mac 真机测试尚未运行。

## 2026-07-25 双端最新 metadata 的 P0 修复

`LocalNetworkSyncDiffPlanner` 的 compatibility 映射此前把所有 `.updateMetadata` 都放进 `uploadMetadataActions`，即使 core reconciliation 已明确标记 `.download`。因此 Mac 较新的同 ID 对象会被错误反向上传，Mac 独有的 metadata 也无法在 iPhone 落地。iPhone 与 Mac 两份 `StudyLibrarySyncModels.swift` 现在都显式按 action direction 分桶；缺失方向 fail closed 为 conflict，tombstone 同样不再把 nil 方向默认为 download。

活动 tick 现在在 inventory、单次 diff、reconciliation 和 conflict isolation 后，先把 `downloadMetadataActions` 对应的 peer manifest 裁剪并交给 iPhone `StudyLibraryStore.applySyncManifest`，再把 `uploadMetadataActions` 对应的本地 manifest 经既有 `/sync/apply-metadata` 发给 Mac。同一轮可同时处理 iPhone winner、Mac winner 与 Mac-only metadata；两个方向都只消费同一个 conflict-isolated execution plan。artifact/audio request/put、placeholder、物理删除、upload job、retry/finalize 和内容完成证明仍不执行。

本地验证已完成：iOS `build-for-testing` 通过；iPhone 17 / iOS 26.5 Simulator 上 4 项定向测试 4/4 通过，覆盖 peer-newer/download 分桶、混合双向实际 Store apply、原有 iPhone->Mac metadata shell 与 conflict isolation；Mac Debug build 通过。iOS `RokuricsTests` 完整单元组执行 219 项：202 通过、7 失败、10 跳过；本轮方向测试已由旧失败转为通过，新增混合双向测试通过，剩余失败未在本轮扩范围修复。未运行 paired iPhone/Mac 真机测试。真机必须重新构建并安装双端 App，验证同一局域网、双端前台时双方业务 metadata 最终收敛且内容 bytes 仍只由学习库“上传”触发。

## 2026-07-17 历史冲突隔离与失效 run 终止消费

本轮只修同步内核，不新增或改写 Mac UI。`LocalNetworkSyncEngine` 仍保留完整 discovery plan 作为本轮差异结果、reconciliation 依据和诊断摘要；在执行 action-scoped metadata apply 前，另由既有 `conflictIsolatedExecutionPlan` 生成可执行 plan。任何与 conflict 处于同一 folder/item/recording/artifact 依赖闭包的 metadata action 都从本次双向 apply 中排除，conflict 本身继续作为成功 diff 返回；与历史 conflict 无关的新对象仍可独立物化到较旧端的既有学习库。真实 manifest 构造、传输、验证或 Store apply 失败仍会使本轮失败，没有被降级为成功。

同步 tick 现在显式返回 `completed`、`retryableFailure` 或 `terminalObsolete`。只有已通过现有安全链路返回的精确 server reject `stale_sync_run` 会进入 terminal-obsolete：这表示该 `syncRunID` 已被 Mac 的更新 run 取代。两条 durable drain 路径都会将它从 in-flight 终止消费并写入有界 completed-ID 去重集合，不再放回 pending、增加失败退避或被后续 heartbeat 重试；但也不会写 `lastSuccessfulSyncAt` 或伪装成同步成功。网络、鉴权、解码、metadata partial failure 等其他错误仍按 retryable failure 回到 pending。

本轮没有修改 route、payload/schema、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、上传触发规则或任何 View。iOS `build-for-testing` 已通过；5 个新增测试与 5 个关键回归测试在 iPhone 17 / iOS 26.5 Simulator 上实际执行，结果 10/10 通过。paired iPhone/Mac 真机复测仍需重新构建并安装 iPhone App 后进行。

## 2026-07-16 同步 run 竞态、瞬断恢复与 Mac 现有录音卡片恢复

7 月 15 日首个失败已定位为同一设备上的同步 owner 竞争：Mac 通过 heartbeat 下发带 `syncRunID` 的 start signal 时，iPhone 的 foreground/timer tick 可能先创建另一轮，令前一轮 inventory 到达 Mac 时被判为 `stale_sync_run`；另有一次 `/sync/inventory` 响应结束阶段的短连接丢失。当前两条 heartbeat consumer 都会先把 correlated run 持久排队，再发布 online 并 ACK；同一响应中的 generic/status hint 只合并到该 run。correlated drain 原样复用 Mac 给出的 ID 执行 inventory，不再生成第二个 ID，也不会二次调用 `/sync/start`。App 每次激活或配对/连接意图变化后，旧的 online 快照不能启动 scheduler、retry drainer 或即时队列，必须等本轮新 heartbeat 成功。手动 coordinator 与 AppService scheduler 还共享单一 FIFO run execution gate，手动 follow-up 每轮释放并重新排队；foreground/timer 在 gate 忙时直接跳过，periodic 首 tick 延后一个完整 interval，correlated run 可替换无 ID generic hint 且优先于普通事件。持久 run 只有在 inventory tick 真实成功后才完成；等 gate 时转后台、掉线或执行失败都会回到队首，并等待下一次 heartbeat/状态或显式事件触发，不做热循环重试。

`/sync/inventory` 客户端只对 `NSURLErrorNetworkConnectionLost` 与 `NSURLErrorTimedOut` 做一次有界重试，复用相同 local inventory 与 `syncRunID`；取消、安全错误、解码错误和 server reject 不重试。Mac 对已验证的相同 device/run/peer-inventory-hash 同时提供 in-flight 合并与有界 completed-response cache：并发或随后重试返回完全相同响应，只构建一次 inventory、只 apply 一次 reconciliation；进行中或已完成请求的 hash 改变/无效返回 `sync_run_inventory_mismatch`，已被新 run supersede 时返回 `stale_sync_run`。HTTPS JSON response 使用 final message 完整结束，并记录真实网络错误 domain/code。

7 月 15 日第二个文件其实已被 reconciliation 发现；真正断点是 active sync 不再发送原有的 action-scoped metadata manifest，导致 Mac `StudyLibraryStore` 没有形成带 receiver-local `syncedMetadataOnly` 的 metadata shell，既有学习库列表没有数据可渲染。7 月 16 日先恢复了针对 `plan.uploadMetadataActions` 的单次 `/sync/apply-metadata`；7 月 25 日再补齐方向映射和 `downloadMetadataActions` 的 iPhone 本地 apply。Mac 继续沿 `StudyLibraryStore.applySyncManifest` -> `effectiveStudyItems` -> `MacStudyRecordingCard` -> `StudyRecordingTransferProgressView` 的原有链路显示缺少本地音频的录音。未新增 View projection、section、card 或文案；同步不传 audio/artifact bytes，不创建 placeholder、upload job，也不执行内容 retry/finalize。实际音频仍必须由来源端学习库明确点击“上传”才传输。

## 2026-07-12 同步差异判定与待传输闭环已完成代码级收口

项目现已确认三层产品定义：连接只做短握手与可信在线检查；连接页“立即同步”交换学习库 inventory 的稳定标识、逻辑文件名、hash、byte size、业务修改时间、版本和 tombstone 等短字段，完成差异发现、LWW 来源判定和逐对象待处理标记，并且只允许按 winner 方向应用 conflict-isolated、action-scoped metadata shell，以让较旧端获得最新业务 metadata；学习库内用户点击“上传”后，才允许双向传输实际文件内容。同步不创建 placeholder、不传 artifact/audio bytes，也不自动创建上传任务。

共享 `SyncReconciliationPlanner` 现按稳定 `objectID` 对齐版本：较新的微秒级业务 `modifiedAt` 必然成为 source，即使双方都修改也仍按 LWW；相同 hash + 名称变化为 rename-only；相同 hash + 仅时间变化不重复传输；hash 不同且时间精确相同到微秒、或缺少必要 hash/size 时 deferred；tombstone 与 live version 同样按 LWW，较新 live 可恢复，较新 tombstone 可删除，真正时间并列不静默覆盖。请求方向不会改变 winner 或 record ID。

双端各自使用 `SyncReconciliationStore` 将相关记录原子持久化到应用根目录的 `Sync/Reconciliation/records.json`。记录包含 source、target、expected hash/size/modifiedAt、difference、reason、状态和完成证明，不含文件 bytes、正文、绝对路径或密钥；存储有 schema version、4096 条默认上限、幂等替换、无关对象保留和损坏 fail-closed。下一轮 inventory 已收敛时只清除本轮已评估且一致的对象记录。

iPhone -> Mac 与 Mac -> iPhone 上传入口均已改为消费 reconciliation record。来源端按钮才可创建任务；目标端 metadata-only item 进入既有 `MacStudyRecordingCard`，但不得据此显示音频已存在或传输已完成。创建前校验来源版本，过期则写 `staleSourceVersion` 且不创建 job；上传协议携带 record ID 与目标旧版本 proof，接收端在替换前执行 target CAS、checksum/size 和 no-overwrite 校验；成功后写 `transferredAwaitingVerification` 完成证明，下一轮两端 inventory 一致后清除记录。稳定 recording ID 在 Mac -> iPhone 替换时保留，不再通过新 ID 制造重复对象。

源码已按该产品定义拆层。`LocalNetworkSyncEngine.performTick` 现在只构建一次本端 runtime inventory snapshot、交换一次对端 inventory、执行一次 shared reconciliation plan，并持久化有界 run 摘要和逐对象 record；旧 canonical 二次 planner、shadow migration 和逐对象重算不再进入 active discovery。`downloadMetadataActions` 非空时，路径将 peer manifest 裁剪后本地 Store apply；`uploadMetadataActions` 非空时，路径发送一次本地 action-scoped metadata manifest。两者都只读取 conflict-isolated plan；placeholder、artifact request/put、generated artifact download、缺失 audio upload、upload job、retry/finalize 和文件内容完成证明仍不进入 sync。deferred 是成功同步得到的业务结果；成功终态不要求任何文件传输完成。

上传任务创建已收窄为学习库明确上传按钮：iPhone -> Mac 继续复用现有安全上传链路；retry drainer 只能恢复由按钮创建的 durable job。Mac -> iPhone 新增 Mac 学习库按钮、持久 `MacToIPhoneUploadStore`、heartbeat 小型 offer、iPhone 分块 pull 和独立 ACK；heartbeat 不携带文件 bytes，Mac 不反向拨号 iPhone。分块/ACK route 继续通过 TLS/HMAC/timestamp/nonce/body hash/`RequestVerifier`，目标端校验 chunk checksum、整文件 checksum/size 并 no-overwrite 落盘。

hash cache 本身在问题日志中正常命中：iPhone 54 次、Mac 53 次，未见 miss/stale/recompute。修复保留该 cache，并通过单轮 snapshot 消除了 sync tick 内的重复内容 lookup。2026-07-12 最新验证：iOS `SyncReconciliationClosedLoopTests` 13 项全部通过，覆盖 LWW、rename-only、缺 hash、时间并列、删除/恢复、防复活、双端方向一致、跨重启、幂等/supersede/有界/损坏 fail-closed、缺标记拒绝、stale source 拒绝和完成 proof；iOS 测试构建随 targeted test 成功，Mac Debug build 成功。paired iPhone/Mac 真机往返和大文件体验证据仍未采集，不能据此声称真机已验证。

## 2026-07-12 开发会话日志收集与存储系统

新增 `RokuricsShared/DevelopmentDiagnostics.swift`，在 DEBUG 构建中提供双端统一的开发会话日志。iPhone 进程生成 `test-*` 会话 ID，并通过可选 `X-Rokurics-Development-Session-ID` 请求头传给 Mac；Mac 收到后采用同一 ID。连接/同步事件由双端 `ConnectionDiagnosticsStore` 镜像，上传事件由 `UploadFlightRecorder` 镜像，`syncRunID` 与 `traceID` 继续作为子关联键。

会话日志使用独立串行 utility queue，单卷 10 MB、4 个备份、8192 事件队列，每端最多保留 20 个会话并清理超过 14 天的旧会话，同时保存 session manifest 与 writer health。只在 DEBUG 写入，不新增 UI，不改变连接方向、route、请求 body/schema、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain 或 pairing 凭据。

新增 `Scripts/collect_development_diagnostics.sh`，通过 `devicectl` 收集 iPhone Diagnostics/Sync、Mac local/production Diagnostics/Sync、旧 upload trace，并生成 collection manifest、warning 和逐文件 JSONL 完整性报告。详细流程见 `docs/DEVELOPMENT_DIAGNOSTICS.md`。

## 2026-07-08 Rokurics v10.0 / Mac 首页与共享录音实时转写保留范围

当前工作区以 `4a940f6 v9.24` 为基线，只保留 v10.0 的 Mac 首页、本地录音、共享录音界面和模拟实时转写改动。此前临时出现的 no-legacy fallback / canonical runtime / 设置页切换删除 / 测试 source regression 改动已按文件级恢复到 v9.24，不再是当前源码事实。

保留的 v10.0 行为是：Mac 默认进入 `MacHomeView`，侧边栏新增首页入口，点击共享录音 orb 打开 `MacRecordingSessionView` 并启动 `MacRecordingManager` 本地录音。Mac 录音使用 `AVAudioRecorder` 生成 m4a，新增麦克风 entitlement 与 `NSMicrophoneUsageDescription`，保存时复用 `MacRecordingFileStore.saveMetadata`、`temporaryAudioUploadURL`、`checksumForTemporaryAudioUpload` 和 `saveAudio(temporaryFileURL:)`，不新增 route、反向连接、上传协议或收件箱 schema。

实时转写当前仍是模拟 provider：`RokuricsShared/SharedLiveTranscriptionModels.swift` 提供 `RokuricsSimulatedLiveTranscriptionSession`，录音期间发布增量文本给共享录音界面。Mac 保存时把模拟 snapshot 写入 `TranscriptStore` 并更新 transcription status；iPhone `RecordingManager` 也复用同一模拟 session 只用于录音界面显示，不改 `RecordingMetadata`、上传队列、同步 proof 或学习库 schema。该状态不代表真实 OpenAI Realtime、FunASR 或 whisper streaming 已接入。

## 2026-07-04 Rokurics v9.24 / 双端中英显示文案

本轮新增共享语言开关 `RokuricsShared/RokuricsCopy.swift`。策略为读取系统首选语言，中文环境继续显示中文，其他语言统一显示英文；该 helper 只返回展示文案和展示用 locale，不改变任何持久化 schema、sync/upload 状态枚举、route、安全校验或业务协议。

iPhone 侧主要覆盖首页、录音会话、学习库、录音列表、上传状态、AI 对话、设置页、录音标题/错误、学习文档详情等可见文案。Mac 侧主要覆盖侧边栏、Dashboard、音频收件箱、学习库、连接页、AI 对话、设置页、转写/whisper.cpp/AI provider 配置、笔记/转写文档详情和 receiver/status 卡片。双端标题组件在非中文环境下不再强制中英混排，并为长英文保留 line limit / scale / compact wording，降低溢出风险。

旧 Markdown 笔记/转写解析键、canonical/debug 诊断常量、日志、schema/raw value 和安全链路文本未作为协议字段改名；展示层只在可见文案处包语言分支。已验证 Mac scheme 与 iPhone simulator generic scheme 均可构建。全局 `git diff --check` 仍被既有 `RokuricsMac/SecureLocalHTTPSServer.swift` 尾随空白阻断；本轮相关文件的 scoped `git diff --check` 通过。

## 2026-06-18 Canonical v9.17 / Real Path State Fix

本轮只修真实路径断点，不新增 route、schema、runtime harness、gate/evidence/scorecard 或 SyncCore facade。`realDeviceEvidencePresent=false` 仍为当前真实状态，不能把 code-level READY 当作真机通过。

录音音频上传、canonical transfer、finalize proof、status fact 与 UI display cache 的 audio key 已统一到 `recordingAudio:<recordingID>`。iPhone `RecordingUploadCoordinator` 的 canonical transfer blocked/failed/retry job objectID、`IPhoneCanonicalTransferAdapter` 的 transfer runtime objectID、Mac `SecureLocalHTTPSServer` finalize proof fact objectID 均使用 canonical audio key；adapter 仍在调用 existing secure upload route 前剥离 `recordingAudio:` 前缀，route path/schema/security 不变。

status truth projection 回灌到上传 UI：`StudyLibrarySyncCoordinator` 的直接 fact produce、heartbeat/status exchange delta consume、local-network inventory fact produce 与 inventory envelope consume 会读取 `CanonicalStatusTruthRuntime.projectionSnapshot`，同步写入 `StudyLibraryStore.effectiveSyncStatusByObjectID` 和 `RecordingUploadCoordinator.displaySyncStateByObjectID`。View getter 仍只读 cache，不触发 reconciliation、manifest/hash、diagnostics sync write、upload job 或 retry drain。Ack alone 不桥接为 completed；metadataOnly、partialReceive、completedLedgerOnly 仍不能显示 completed。

上传按钮 early return 现在会把 blocker 写入可见 display/progress cache：mac not paired、metadata/local audio missing、active upload/transfer in-flight、ledger in-flight/retry pending、trigger/view refresh forbidden、peerUnknown deferred、production port unavailable、conflict/no-overwrite 等不会 silent no-op。仍不在 `canCreateUploadJob`/owner/gate 不允许时创建新 upload job。

Mac 手动同步仍保持 server-only，不新增 Mac -> iPhone 反向连接。`prepareManualStudyLibrarySync` 返回的 `DeviceConnectionStatus` 会立即触发 `presenceObservationRevision` 发布；`MacIPhoneConnectionView` 保留返回的 revision。pending lifecycle 继续由 `DeviceConnectionStatusStore` 发布 requested、duplicate waiting、heartbeat consumed、inventory observed 和 timeout/stale。

## 2026-06-17 Canonical v9.15 / R6-R7 Prove-or-Fix Before Real-Device Trial

本轮以代码路径、grep 和 targeted tests 为准，不以旧 v9.10-v9.13 文档中的 READY/closure 自报为准。旧 `CanonicalFourDomain*`、fake harness、Evidence package、CompletionGate/FinalScorecard/RealDeviceTrialGate 类文件若已被删除或未跟踪，不得恢复或当作 R7 证明来源。

R6 code-level 修复：`CanonicalConnectionRuntime` 已在 iPhone `StudyLibrarySyncCoordinator`/heartbeat monitor 与 Mac `SecureReceiverService` -> `SecureLocalHTTPSServer` app path 中使用。`canonicalDecisionOnly` 与 `canonicalApplyNoAudio` 现在启用 diagnostics-only connection carrier，用于 heartbeat/status envelope shadow/carrier；它们仍不 apply、不 upload，`canonicalApplyNoAudio` 仍 hard-block audio transfer。`oldKernel` connection/transfer 仍 disabled，legacy owner/fallback 保留。

R6 transfer app path 仍为 `RecordingUploadCoordinator` -> `CanonicalTransferRuntime` -> `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient`/`RecordingUploadClient` -> existing Mac upload start/status/chunk/finalize routes -> `RequestVerifier` -> `MacRecordingFileStore`。`RecordingUploadCoordinator` 只在 `canonicalFullSync` 且 DEBUG/internal、owner approval、manual confirmation、legacy fallback、route/security unchanged 和 readiness gate 满足时进入 transfer runtime；view refresh 不创建 upload job，retry drainer 只恢复 existing eligible job。

R7 code-level 修复：现有 `CanonicalRealDeviceTrialReadinessGate` 增加 v9.15 fail-closed gate。新 READY 字符串为 `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`，并逐项检查 R1 diagnostics async hot path、R2 content-stable cache key、R3 no-freeze evidence、R4 EffectiveStatus UI binding、R5 realtime status exchange、R6 connection app path、R6 transfer app path、fake/testOnly production transfer、finalize proof -> StatusTruth、route/security/RequestVerifier、Mac reverse connection、heartbeat heavy sync、view refresh upload job、retry fresh job、metadataOnly/completed ledger/partial receive peer-proof misuse、default/release oldKernel、legacy fallback、no legacy retirement 和 build/test summary。

本轮验证结果：`git diff --check` 通过；no-new-scaffold grep 为空；macOS targeted tests 通过。iOS targeted tests 已成功编译并进入测试启动阶段，但 simulator 基础设施失败：`Failed to prepare device 'Clone 1 of iPhone 17' ... Timed out trying to boot simulator after waiting 60.00s`。因此本轮不能声明 all targeted tests pass，v9.15 final state 是 `NOT_READY`，不能进入 `canonicalFullSync` paired real-device trial。

当前真实边界：`realDeviceEvidencePresent=false`。即使 v9.15 gate 在 code-level 输入全绿时可返回 `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`，该 READY 也只表示 paired-device DEBUG/internal trial readiness，不是 release-ready，不是真机已通过，不是 legacy-retirement-ready。本轮未新增 route，未改 upload route schema，未绕过 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash，Mac 不新增反向连接 iPhone，default/release 仍必须为 `oldKernel`，legacy fallback 必须保留。

工作区注意：本轮审计到多项 R6/R7 canonical 源文件和 targeted test 文件在当前 Git status 中仍显示为 untracked；在它们被纳入索引之前，只能把当前工作区视为本地 code-level evidence，不能把仓库 tracked baseline 视为已完成。

## 2026-06-16 Canonical v9.13 / Post-audit Final Real Wiring 条件状态

v9.10 post-audit found R4/R6/R3 evidence incomplete. 旧 v9.10/v9.12 的 gate、harness、scorecard 或本地 targeted test 只能视为 code-level evidence，不得解读为内核全量落地、可发布、真机已通过或可退休 legacy。

v9.13 closes code-level R4/R6/R3 only if tests/grep pass. R4 UI final display 必须追溯到 cached `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` snapshot；R6 transfer commit 只允许 `canonicalFullSync` 且 debug/internal、owner approval、manual confirmation、legacy fallback、route/security unchanged 全部满足；R3 no-freeze 仍以 UI read/Store getter/View refresh 不触发 reconciliation、diagnostics sync write、manifest/hash、upload job 或 retry drain 为验收边界。

`realDeviceEvidencePresent=false`。没有 paired iPhone/Mac redacted jsonl 时，不得声明真机 no-freeze、状态收敛、文件不卡顿、canonical 内核完成、release/default canonical 或 legacy retirement。

## 2026-06-16 Canonical v9.12 / Post-v9.10 Audit Closure B: R6 Owner + R7 Final Gate

v9.12 收口 v9.10 之后 Claude/Codex 总表剩余项：R6 Connection/Transfer runtime owner 与 R7 four-domain final gate/harness。v9.11 已完成 R4 UI EffectiveStatus binding 与 R3 no-freeze 反证；R1/R2/R5 仍作为 gate 回归证据保留。

Connection owner 继续只在 `canonicalFullSync` 且 debug/internal、owner、manual confirmation、legacy fallback、route/security、domain readiness 全绿时启用。真实 app path 已由 `StudyLibrarySyncCoordinator`、`SecureReceiverService` 与 `SecureLocalHTTPSServer` 引用 `CanonicalConnectionRuntime`；runtime 只拥有 peer liveness、heartbeat envelope、syncRequested/status request、status exchange carrier 与 diagnostics。Mac 仍不主动连接 iPhone，heartbeat/status callback 只 enqueue existing sync/status work，不 inline inventory/apply/upload/file/hash。

Transfer owner 继续只在 `canonicalFullSync` allowed 时由 `RecordingUploadCoordinator` 进入 `CanonicalTransferRuntime`。真实执行路径为 `RecordingUploadCoordinator` -> `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient` -> existing Mac upload start/status/chunk/finalize routes；Mac finalize route 仍在 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash 通过后经 `MacRecordingFileStore` 产生 receiver accepted proof。finalize proof 写入 v9.4 `CanonicalStatusTruthRuntime`，UI completed/peerVerified 仍只读 `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState`。

旧 migration facade 的 in-memory upload ledger 已改为显式 `testOnly` 命名；`fakeLedger` production-looking token 已移除。production port injection 不会选择 test-only upload port；若 gate evidence 指示 `productionUploadPortNotTestOnlyFake=false`，completion gate 与 real-device trial gate 均返回 unsafe，不允许 READY。

R7 gate 不再只依赖粗粒度自报 bool。`CanonicalFourDomainGateEvidence` 现在能表达 Connection、Transfer、Sync、File 与 cross-domain 总表核心行：真实 app runtime 引用、heartbeat/status exchange、secure upload path、finalize proof -> StatusTruth、retry existing-only、UI EffectiveStatus、read cache、diagnostics async writer、file hot-path guard、kernel switch mode boundary、legacy fallback/no-retirement 等。缺 R6/R7 核心 evidence 返回 `PARTIAL_WITH_BLOCKERS` 或 `UNSAFE_TO_TRY_ON_DEVICE`。

Deterministic two-node harness 补齐 diagnostics storm async/backpressure、status exchange duplicate/stale/conflict deterministic policy 和完整 mode sequence `oldKernel -> canonicalShadow -> canonicalDecisionOnly -> canonicalApplyNoAudio -> canonicalFullSync -> oldKernel`；harness 仍是 fake/local code-level evidence，不是真机 evidence。

本轮不执行 legacy retirement，不新增 route，不改 `/device/status`、`/connection/heartbeat`、upload route schema 或安全链路。`realDeviceEvidencePresent=false` 仍是当前真实状态；READY 只表示可以进入 paired-device debug/internal app trial，不表示真机已通过。

## 2026-06-16 Canonical v9.11 / R4 UI EffectiveStatus Closure and R3 No-Freeze Proof

v9.11 收敛 Claude 审计打回的 R4 与 R3 证据缺口：真实 UI/status model 的最终同步状态现在读取缓存的 `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` snapshot，而不是 View 层从 upload ledger、receive record、metadataOnly、本地文件存在等多源拼 completed/audioAvailable。`R6` 不在本轮执行，`ownerApprovedCanonicalTransfer`、Connection Kernel owner、Transfer owner、upload route、heartbeat route、Mac reverse connection 和 `SecureMacUploadClient` path 不接管、不扩展。

iPhone 侧 `StudyLibraryStore` 暴露只读 `effectiveSyncStatusByObjectID`、`effectiveSyncStatus(for:)`、`canonicalDisplaySyncState(for:)`；getter 只读缓存字典。`RecordingUploadCoordinator` 暴露同类 snapshot，并把 `displaySyncState(for:)` 改成先读 `displaySyncStateByObjectID`，无缓存时只走 conservative canonical-equivalent fallback；getter 不读 `jobStore`、不触发 status reconciliation、diagnostics write、sync/upload/retry drain、file IO 或 network IO。显式 ledger refresh 只保留在 `refreshDisplaySnapshot(for:)` / 初始化预载路径，不在 View getter 内发生。

Mac 侧 `StudyLibraryStore` 与 `SecureReceiverService` 暴露只读 effective status snapshot；`SecureReceiverService` 只缓存已有 status truth projection，不改 server/route 行为。`MacRecordingInboxItem` 在 model 初始化时生成并持有 `canonicalDisplaySyncState`，`MacStudyLibraryView` 与 `MacAudioInboxView` 的播放/转写可用性改读 `displayAudioAvailable`，不再把 raw `hasAudio` 当最终 peer audio proof。

R4 hard proof rule 仍由 shared projection 保证：displayed complete/peerVerified/audioAvailable 只能来自 accepted finalize proof、peer inventory hash-size match、same hash+byteSize 或 StatusTruth 已验证等价 proof chain。metadataOnly、metadataOnlyLedger、receiveRecordOnly、completed ledger alone、partialReceive、local file exists only、expected manifest hash only、peerUnknown、status ack alone 不得显示 completed/peerVerified/audioAvailable；existing different audio 仍显示 conflict/no-overwrite 且不覆盖。

R3 no-freeze 证据补强：`CanonicalMainActorHotPathGuard` 现在覆盖 diagnosticsWrite、fileTreeSnapshot、manifestBuild、fullHash、readProjectionRebuild、statusTruthReconciliation、effectiveStatusProjection 七类计数。v9.10 gate/evidence/scorecard 新增 code-level evidence 字段：`uiEffectiveStatusBindingEvidence`、`viewLayerNoDirectPeerProofEvidence`、`noMainActorStatusReconciliationEvidence`、`noViewRefreshUploadJobEvidence`、`diagnosticsAsyncHotPathEvidence`、`contentStableCacheKeyEvidence`。缺 R4、View 层直接拼 peer proof、MainActor status reconciliation 或 View refresh 创建 upload job 均不能 READY，安全违规进入 UNSAFE/NOT_READY。

本轮验证已通过 iPhone 与 Mac targeted tests：双端 UI/status projection tests、FileKernel/R3 hot-path guard tests、ReadRuntime/R2 cache key tests、StatusTruth projection tests、v9.10/v9.11 gate tests。仍未运行完整全量 suite，未产生 paired iPhone/Mac real-device redacted jsonl；不得声明真机 no-freeze、真机状态收敛、canonical kernel 完成或 R6 完成。

## 2026-06-15 Canonical v9.10 / Real-Device Trial Gate, Evidence Package, Cleanup, No-Retirement Lock

v9.10 合并最终 trial gate、redacted evidence package、final scorecard、cleanup audit 和 no-retirement lock，但仍不扩展 runtime 行为，不启用 release/default canonical，不删除 legacy，也不表示内核全量落地。`realDeviceEvidencePresent` 继续保持 `false`；READY 只表示可以进入人工 paired iPhone/Mac app trial 准备。

新增 shared report-only 文件位于 `RokuricsShared/SyncCore/`：`CanonicalFourDomainRealDeviceTrialGate.swift`、`CanonicalFourDomainEvidencePackage.swift`、`CanonicalFourDomainEvidenceRedaction.swift`、`CanonicalFourDomainFinalScorecard.swift`。这些类型只接收 code-level evidence、redacted summary、build/test summary、cleanup audit 和 no-retirement lock，不调用真实 network/store/route/upload/apply，也不引用 Rokurics local HTTPS/TLS/HMAC concrete classes。

v9.10 Gate 四态为 `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_TRY_ON_DEVICE`。READY 要求 v9.5 diagnostics/cache/status truth、v9.6 UI source、v9.7 realtime exchange、v9.8 connection/transfer owner、v9.9 harness、default/release oldKernel、legacy fallback、route/security/RequestVerifier unchanged、Mac no reverse connection、heartbeat no heavy sync、view refresh no upload job、retry storm guard、diagnostics redacted、switch-back proof 和 build/test summary。build/test summary 缺失返回 NOT_READY；缺某个非安全四域证据返回 PARTIAL；unsafe blocker 直接返回 UNSAFE。

Unsafe blockers 明确包括 release/default canonical、route/security bypass、RequestVerifier bypass、missing legacy fallback、upload route schema change、metadataOnly/completed ledger alone/partial receive treated as peer audio proof、existing different audio overwrite、UI refresh creates upload job、diagnostics leak、MainActor hot path violation、oldKernel switch-back failure、Mac reverse connection attempt、heartbeat heavy sync 和 no-retirement lock broken。

Evidence package 只包含 redacted summaries 和计数：mode transitions、cache hit/miss/rebuild、diagnostics write queue/drop/flush duration、MainActor violation counts、status fact/delta/ack/request counts、finalize proof count、metadataOnly/completed ledger/partial receive rejected counts、peer proof unavailable count、route/security unchanged proof summary、switch-back proof summary 和 build/test summary。Redaction detector 阻断 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio、full transcript/note/summary/provider response 和 full generated content。

No-retirement lock 固定要求 `legacyDeleted=false`、`legacyDisabled=false`、`retirementExecutionPerformed=false`、`readyToRetireLegacyReportOnly=false`、release/default oldKernel，且 `canonicalFullSync` 只能 debug/internal + owner + manual + all gates。本轮明确 no legacy retirement performed。

新增双端 targeted tests：`RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests.swift` 与 `RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests.swift`，覆盖 READY with code-level evidence and no real-device evidence、PARTIAL when one domain missing、NOT_READY when build/test summary missing、每类 unsafe blocker、evidence redaction、cleanup audit 和 no-retirement lock。新增 runbook：`docs/Rokurics_Canonical_FourDomain_Kernel_Runbook_v9.md`。

本轮验证：`xcodebuild -list` 通过；iPhone v9.10 targeted tests 在 `iPhone 17, OS 26.5` simulator 上通过 6 个 Swift Testing 用例；Mac v9.10 targeted tests 在 `platform=macOS`、`-parallel-testing-enabled NO` 下通过 6 个 Swift Testing 用例。`CanonicalFourDomain.*Facade|v9.*Facade|Facade.*v9` 搜索无命中，`git diff --check` 通过。仍未运行完整全量 suite，未产生 paired iPhone/Mac real-device redacted jsonl。

## 2026-06-15 Canonical v9.9 / Four-Domain Gate and Deterministic Harness

v9.9 建立 code-level `CanonicalFourDomainCompletionGate` 与 deterministic fake two-node harness，但仍不表示 canonical kernel 完成，也不是真机 evidence。四域 gate 现在把 Connection、Transfer、Sync、File 作为一等域检查；`READY` 仅表示 v9.5-v9.8 的代码级 evidence 全绿，`PARTIAL` 表示至少一个非安全域缺失，`UNSAFE` 表示 route/security/default canonical/peer proof/MainActor/no-freeze 等硬不变量被破坏。`realDeviceEvidencePresent` 继续固定为 `false`。

新增 shared fake harness 文件位于 `RokuricsShared/SyncCore/`：`CanonicalFourDomainRuntimeHarness.swift`、`CanonicalFourDomainFakeConnectionCarrier.swift`、`CanonicalFourDomainFakeTransferPort.swift`、`CanonicalFourDomainFakeFileRuntime.swift`、`CanonicalFourDomainCompletionGate.swift`。Fake carrier 只记录 heartbeat/status delta/ack/syncRequested/proof-request envelope、storm coalescing、Mac reverse-connection attempt count 和 heartbeat heavy-sync attempt count；fake transfer port 只在内存中产生 receiver accepted finalize proof、partial receive 和 existing-different-audio conflict/no-overwrite；fake file runtime 只维护内存 checksum/read cache、async diagnostics queue proof 和 hot-path attempt counters。

Harness 覆盖 10 个确定性场景：metadataOnly peer + local audio -> uploadNeeded -> transfer finalize -> status exchange -> completed；peerUnknown deferred；completed ledger alone unverified/request peer proof；partial receive not completed；existing different audio conflict/no-overwrite；generated artifact available status delta 且 provider rerun=0；cache hit skips hash；repeated UI read no rebuild；event storm coalesced；oldKernel -> fullSync -> oldKernel switch-back no migration。No-freeze assertions 要求 diagnosticsWrite/fileTree/manifest/hash/statusReconcile hot-path attempt count 全为 0、cache hit skips hash、async diagnostics queue used、repeated UI read no rebuild。Proof assertions 要求所有 displayed completed 都引用 finalizeProof 或 peerInventoryHashSizeMatch，metadataOnly/completedLedger/partialReceive rejection diagnostics 存在，status exchange ack alone 不能 completed。

本轮只新增 shared fake harness/gate 与双端 tests，没有新增 route、没有修改 upload route schema、没有修改 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain、pairing 或 Mac server/iPhone client 拓扑；default/release 仍 `oldKernel`，legacy fallback 保留，Mac 仍不主动连接 iPhone。Mac test host 在 scheme 启动时会打印现有 receiver/app 日志，但新增 harness 自身不使用真实网络、不写 production root。

新增 targeted tests：`RokuricsTests/CanonicalFourDomainRuntimeHarnessTests.swift` 与 `RokuricsMacTests/CanonicalFourDomainRuntimeHarnessTests.swift`。双端 tests 已通过，覆盖 harness scenarios、no-freeze/proof assertions、Gate READY/PARTIAL/UNSAFE 和 `realDeviceEvidencePresent=false`。仍未运行完整全量 suite，未产生 paired iPhone/Mac redacted jsonl，不得声明真机 no-freeze、状态收敛、文件不卡顿或 canonical kernel 完成。

## 2026-06-15 Canonical v9.8 / Connection and Transfer Runtime Owner Wiring

v9.8 把 `canonicalFullSync` 档下的 Connection Kernel 与 Transfer Kernel 接到真实 runtime owner，但仍不表示 canonical kernel 完成。File 域完整 root-bound/no-freeze 组合验证、Sync 域全量 event-driven 收敛和 paired-device 真机 redacted evidence 仍未完成；default/release 继续 `oldKernel`，legacy fallback 保留。

Connection runtime 新增在 `RokuricsShared/SyncCore/CanonicalConnectionRuntime.swift`，由 `CanonicalKernelSwitch` 输出 mode-gated configuration。`oldKernel`/blocked 下 disabled，shadow/diagnostics 下 carrier diagnostics only，`canonicalFullSync` 且 owner/manual/readiness/fallback/domain gates 通过时才进入 `connectionOwnerWithLegacyFallback`。runtime 只拥有 peer liveness、heartbeat envelope、status request 和 `syncRequested` envelope；heartbeat callback 仍只 enqueue，不 inline heavy sync。

iPhone 侧 `StudyLibrarySyncCoordinator` 与 `LocalNetworkHeartbeatMonitor` 在现有 `/device/status` 和 `/connection/heartbeat` carrier 上生成/消费 canonical connection envelope。Mac 侧 `SecureReceiverService` 创建同一个 shared runtime，`SecureLocalHTTPSServer` 只在既有 request/response path、既有 verifier 通过后记录 inbound liveness 与 syncRequested/status request；Mac 仍不主动连接 iPhone，未新增 route，未修改安全层。

Transfer runtime 在 `canonicalFullSync` 且 transfer owner gate 通过时由 `RecordingUploadCoordinator` 调用 `CanonicalTransferRuntime`。真实执行通过 `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient` 复用现有 start/status/chunk/finalize upload routes；runtime owns session start/status/chunk/finalize、confirmedBytes monotonic、resume/status refresh、retry/backoff、idempotency 和 finalize proof。`canonicalApplyNoAudio` 阻断 audio transfer；shadow/decisionOnly 不 commit transfer。

如果 production audio port 未启用，v9.8 fail closed，不把 fake ledger 当 readiness。view refresh 不创建 upload job；retry drainer 只能恢复 existing eligible job。Transfer finalize proof 必须是 receiver accepted proof，随后写入 v9.4 `CanonicalStatusTruthRuntime`，再由 truth engine 决定 completed/peerVerified；completed ledger alone、metadataOnly、partial receive 和 receive record alone 仍不是 peer audio proof。

Mac upload route handler path 保持原样，`RequestVerifier`、TLS/HMAC/pinning/nonce/body hash 仍在既有 route 前置路径。`SecureLocalHTTPSServer` 只在既有 finalize route 成功、response completed 且 checksum/fileSize 与请求匹配后，把 receiver accepted finalize proof 作为 status truth fact；partial receive 不 completed，existing different audio 继续 conflict/no-overwrite。

本轮补充双端 targeted tests：iPhone 覆盖 switch mode mapping、connection runtime enqueue-only/liveness、existing heartbeat carrier、fullSync 进入 canonical transfer runtime、applyNoAudio/oldKernel/blocked 边界；Mac 覆盖 route list unchanged、RequestVerifier 仍在 path、Mac no reverse connection、finalize route proof 进入 truth runtime、partial receive/completed ledger not proof、existing different audio no-overwrite。双端 targeted tests 已通过；仍未运行完整全量 suite，也未产生 paired iPhone/Mac real-device redacted jsonl。

## 2026-06-14 Canonical v9.7 / Realtime Status Exchange Runtime Wiring

v9.7 把 v9.0 定义的 `CanonicalStatusExchangeEnvelope` / Delta / Ack / Request 接到真实 iPhone/Mac app path，但仍不表示 canonical kernel 完成。Connection、Transfer、Sync、File 四域 owner、paired-device 真机 evidence、完整 production cutover 和完整 no-freeze 组合验证仍未完成；default/release 继续 `oldKernel`，legacy fallback 保留。

新增 portable shared runtime `RokuricsShared/SyncCore/CanonicalStatusExchangeRuntime.swift`。runtime 从 v9.4 `CanonicalStatusTruthRuntime` fact store snapshot 生成 outgoing delta，维护 sender-local monotonic sequence、duplicate delta idempotency、stale/expired/wrong-destination reject、pending ack/request 队列，并把 incoming delta merge 回 truth engine。Ack 只表示 observed/incorporated/rejected，不作为 peer audio proof；`runSyncSoon` 只返回 enqueue action；`sendAudioProof` 只返回 lightweight proof request action，不创建 fresh upload job。

承载层没有新增 route，也没有修改 upload route schema。iPhone 侧 `/device/status` heartbeat request、`/connection/heartbeat` request、`/sync/inventory` request 使用 optional `statusExchangeEnvelope`；Mac 侧对应 heartbeat/status response 和 inventory response 返回 optional envelope。Optional decode 对旧 peer missing field 安全，upload start/status/chunk/finalize routes 不承载 status exchange。

iPhone app path 已接入 `StudyLibrarySyncCoordinator`、`LocalNetworkHeartbeatMonitor`、`LocalNetworkSyncEngine` 和 `SecureMacUploadClient`。本地 inventory/upload ledger/generated artifact facts 会进入 truth runtime 并通过 heartbeat/inventory 发送；收到 Mac envelope 后 merge truth engine，记录 statusDelta/Ack/Request sent/received 和 carrier diagnostics，`runSyncSoon`/`fullInventory` 只投递现有 sync status refresh event，不 inline heavy sync。

Mac app path 已接入 `SecureReceiverService`、`SecureLocalHTTPSServer` 和 `ConnectionSyncStateStores`。Mac 仍只作为 HTTPS server 响应 iPhone 请求，不主动连接 iPhone；`/device/status`、`/connection/heartbeat`、`/sync/inventory` 在既有 `RequestVerifier` 通过后消费 optional envelope，并在 response optional envelope 中回传 delta/request/ack。Mac 收到 `runSyncSoon` 只记录 pending sync request，等待下一次 iPhone heartbeat/inventory。

本轮新增 diagnostics case：`statusRequestSent`、`statusRequestReceived`、`statusEnvelopeCarriedOverHeartbeat`、`statusEnvelopeCarriedOverInventory`、`fullInventoryRequested`、`redactionViolationBlocked`，并继续使用 bounded/redacted `ConnectionDiagnosticsStore`/canonical diagnostics。Diagnostics 不写 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio 或完整 transcript/note/summary/provider response。

本轮补充 iPhone 与 Mac targeted tests：`CanonicalStatusExchangeRuntimeTests` 覆盖 old peer optional decode、iPhone inventory carrier delta、Mac incoming finalizeProof completed、metadataOnly not complete、runSyncSoon/sendAudioProof action-only、duplicate/stale policy、ack-alone not proof、route list unchanged、`RequestVerifier` 仍在 path 内和真实 app path 引用。双端 targeted tests 已通过；仍未运行完整全量 suite，也未产生 paired iPhone/Mac real-device redacted jsonl，因此不得声明真机状态收敛或 canonical kernel 完成。

## 2026-06-14 Canonical v9.6 / Effective Status Binding Cutover

v9.6 只把已有 UI 状态字段的数据来源切到 `CanonicalEffectiveSyncStatus` -> `CanonicalDisplaySyncState`，不表示 canonical kernel 完成。Connection、Transfer、Sync、File 四域 owner、实时 status exchange、paired-device 真机 evidence 和完整 no-freeze 验证仍需后续组合验证。default/release 继续 `oldKernel`，legacy fallback 保留；本轮未新增 route、未修改 upload route schema、未绕过 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash，Mac 仍不主动连接 iPhone，且没有视觉 UI 改动。

新增 `RokuricsShared/SyncCore/CanonicalEffectiveStatusUIProjection.swift`，将 `CanonicalEffectiveSyncStatus` 收窄为 UI 可消费的 `CanonicalDisplaySyncState`，并提供 `LegacySyncStatusToCanonicalEffectiveStatusAdapter`。projection 边界再次强制 complete/peerVerified 必须有 accepted finalize proof、peer inventory/hash-size proof、same hash+byteSize 或 dualAck proof chain；metadataOnly、receiveRecordOnly、completed ledger alone、partial receive、local file exists 和 expected manifest hash 仍不得显示 completed/audio available。

iPhone `RecordingUploadCoordinator.displayStatus(for:)` 不再直接把 `RecordingMetadata.uploadStatus == uploaded` 显示为已上传，而是通过 canonical display state 映射回既有 `RecordingUploadStatus`。`RecordingLibraryView` 与 `RecordingStudyDetailPage` 的 action area 改读 canonical display projection；按钮、文案、颜色、布局、间距和导航未改。旧内核/blocked/fallback 仍走 legacy adapter 的等价 display model，但 legacy adapter 会拒绝 ledger-only/metadata-only/partial proof。

Mac `MacRecordingInboxItem` 新增 canonical display state，并让详情页的 audio “可用/缺失”字段读取 `displayAudioStatusText`。`receiveStatus == completed`、receive record only、metadataOnly 或本地文件存在但缺 hash+size proof 时不再显示 audio available；partial receive 仍显示接收进度，不显示 completed。播放/转写操作流程未在本轮重写。

本轮补充 iPhone 与 Mac targeted tests：`CanonicalEffectiveStatusUIProjectionTests` 覆盖 metadataOnly、receiveRecordOnly、completed ledger alone、partial receive、finalize proof、peer inventory/hash-size proof、peerUnknown、view refresh no upload job、legacy uploaded requires proof 和 Mac inbox audio status projection。仍未运行 paired iPhone/Mac 真机验证，不能声明 canonical kernel 完成或真机状态收敛完成。

## 2026-06-14 Canonical v9.5 / No-Freeze Hot Path Recovery

v9.5 只修 canonicalFullSync 相关 no-freeze 热路径，不表示 canonical kernel 完成。Connection、Transfer、Sync、File 四域 owner、实时 status exchange、paired-device 真机 evidence 和生产切换仍需后续阶段组合验证。default/release 继续 `oldKernel`，legacy fallback 保留；本轮未新增 route、未修改 upload route schema、未绕过 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash，Mac 仍不主动连接 iPhone，UI 视觉和既有 sync/apply/upload 业务语义未变。

双端 `ConnectionDiagnosticsStore.record(...)` 已改为 non-blocking hot-path facade：调用方不需要 `await`，record 路径只做脱敏、bounded in-memory recent buffer/counter 和 enqueue，不再调用 `loadEntries()`，不再 JSON decode 旧 JSONL，不再 atomic rewrite 全文件，也不在 MainActor 执行文件写入。真实 IO 现在接入 `RokuricsShared/SyncCore/CanonicalAsyncDiagnosticsWriter.swift` 的 actor-backed writer，并由新增的 file sink 追加 JSONL、后台 bounded compaction；测试可用 `flushForTests()` / `drainForTests()` 验证落盘和 backpressure/drop policy。

iPhone/Mac `StudyLibraryStore` 的 canonical effective read cache key 已改为内容稳定 signature。key 不再包含 `generatedAt`/Date 类快照时间戳，而是按 deterministic sort 汇总 recordings、folders/items、artifact availability/hash prefix/byteSize、tombstone/conflict marker、upload/effective status stable fields、selected hierarchy rule、backing data revision 和 fallback legacy state。内容不变只改变 `generatedAt` 时不会 invalidate/rebuild；内容真实变化才会重建。read access 仍不得触发 sync/upload/retry drain/file IO/network IO。

`CanonicalStatusTruthRuntime` 现在维护 actor-backed projection cache。fact merge 后按 objectID/content signature 构建 deterministic effective status snapshot；重复 `effectiveStatus` 查询是 cached map/bounded lookup，不在 MainActor Store/coordinator/server 热路径反复跑 full reconciliation。运行时新增 projection version/content signature、`statusProjectionDurationMs`、`effectiveStatusProjected` 和 `mainActorStatusReconciliationAttemptCount` 诊断/指标；测试覆盖 repeated read 不增加 projected count 且 MainActor reconciliation attempt 为 0。

本轮验证已覆盖 iPhone 与 Mac targeted tests：双端 diagnostics async flush/redaction/backpressure、双端 generatedAt-stable read cache/repeated tree/read、双端 status truth projection cache/off-main guard、Mac adapter route/security text audit。Mac 组合测试在本机 `-parallel-testing-enabled NO` 下通过 27 个相关测试；仍未运行完整全量 test suite，也未产生 paired iPhone/Mac redacted jsonl，因此不得声明真机 no-freeze 已验证或 canonical kernel 完成。

## 2026-06-14 Canonical v9.4 / Sync State Truth Protocol

v9.4 实现 Sync 域的 proof-driven status truth runtime，但仍不表示 canonical kernel 完成。Connection/Transfer/Sync/File 四域 owner、实时 status exchange facts 接入、production UI cutover 和 paired-device no-freeze evidence 仍需后续阶段组合验证。

新增 shared runtime 位于 `RokuricsShared/SyncCore/CanonicalStatusTruthRuntime.swift`、`CanonicalStatusFactStore.swift`、`CanonicalStatusReconciliation.swift`、`CanonicalEffectiveSyncStatusProjection.swift`、`CanonicalStatusTruthDiagnostics.swift`、`CanonicalStatusTruthReadiness.swift`，并扩展 `CanonicalSyncStatusTruthProtocol.swift`。事实模型覆盖 `CanonicalStatusFactID`、source/proof/causality/expiry、recordingMetadata/libraryMetadata/generatedArtifacts/tombstoneConflict/audioUpload/transfer/connection/file domain，以及 absent/localOnly/peerUnknown/metadataOnly/uploadNeeded/partialReceive/finalizing/peerVerified/completed/conflict/stale 等 phase。

`CanonicalStatusTruthRuntime` 是 actor-backed in-memory fact store + reconciliation/projection owner，不新增 disk schema。fact merge 支持 `replacesFactIDs`、expiration/stale policy 和 deterministic ordering；diagnostics 只输出 redacted event/detail/hash prefix。`CanonicalEffectiveSyncStatus` 统一输出 objectID、domain、phase、displayState、proof、sourceSummary、canDisplayAsComplete、canCreateUploadJob、canSuppressLegacyDuplicate 和 blocker。

v9.4 hard rules 已固化在 reconciliation：metadataOnly、receiveRecordOnly、completed ledger alone、partial receive、local file exists、expected manifest hash 都不是 peer audio proof；same hash + same byteSize 才是 audio no-op；finalize proof、peer inventory/hash-size proof 或 dualAck proof chain 才能显示 peerVerified/completed；peerUnknown ordinary sync deferred；existing different audio conflict/no-overwrite；tombstone 阻止 generated artifact resurrection；unsupported schema blocked/fallback；stale fact 不覆盖 fresh proof；view refresh 不创建 upload job；retry drainer 不创建 fresh job，只能由外层恢复 existing eligible job。

iPhone read-only 接入点已加入 `RecordingUploadCoordinator`、`StudyLibrarySyncCoordinator`、`StudyLibraryStore`；Mac read-only 接入点已加入 `SecureReceiverService`、`SecureLocalHTTPSServer`、`StudyLibraryStore`、`MacRecordingFileStore`。这些 adapter 只 expose `produceCanonicalStatusFact` / `canonicalEffectiveStatus`，不改变 UI display 行为、不直接 execute transfer、不 mutate UI、不新增 route、不改 upload route schema、不绕过 RequestVerifier/TLS/HMAC/pinning/nonce/body hash，Mac 仍不主动连接 iPhone。

old UI status 与 legacy status path 继续共存：default/release 仍是 `oldKernel`，legacy fallback 保留，v9.4 只提供 canonical effective status source 和 upload job gate policy helper；未删除现有 `RecordingUploadCoordinator` legacy decision/upload path，也未把 UI completed 切到 canonical truth engine。

本轮验证：iPhone `RokuricsTests/CanonicalStatusTruthRuntimeTests` 已通过，覆盖 truth table、metadataOnly uploadNeeded not completed、peerUnknown deferred、completed ledger rejected、same hash+size no-op、different hash conflict、view refresh/retry drainer gate、fact store、redaction、readiness 和 iPhone read path。Mac `RokuricsMacTests/CanonicalStatusTruthRuntimeTests` 已编译通过，但两次本机执行均被 Xcode LaunchServices runner 启动失败阻断，未进入测试用例；失败点为 `IDELaunchServicesLauncher - Failed to Launch (Failed to send resume to target process ... No such process)`。

## 2026-06-14 Canonical v9.3 / Transfer Kernel Runtime

v9.3 将现有 audio upload runtime / resumable upload executor 抽象为 portable Transfer Kernel runtime owner 的第一步。新增 shared runtime 位于 `RokuricsShared/SyncCore/CanonicalTransferRuntime.swift`、`CanonicalTransferSessionStateMachine.swift`、`CanonicalTransferProof.swift`、`CanonicalTransferRetryRuntime.swift`、`CanonicalTransferDiagnostics.swift` 和 `CanonicalTransferKernelReadiness.swift`，并兼容扩展 `CanonicalTransferProtocol.swift` 的 finalize proof 与 optional local abort boundary。

Transfer state machine 现在显式覆盖 `idle`、`starting`、`started`、`chunking`、`interrupted`、`resuming`、`finalizing`、`finalized`、`failed`、`aborted`、`conflict`、`blocked`。`confirmedBytes` 单调递增，`nextChunkOffset` 由已确认字节数决定；同 offset/length/hash 的重复 chunk 是 idempotent，错误 offset 进入 interrupted 并要求 status refresh/resume；partial receive 不会被视为 finalized；finalize 需要 byteSize 与可用 hash proof；existing different hash/size 走 conflict/no-overwrite。

新增 `IPhoneCanonicalTransferAdapter` 与 `MacCanonicalTransferReceiveAdapter` 都只是薄 adapter：iPhone 侧继续包装 `IPhoneCanonicalSecureAudioUploadPort` / `RecordingSecureUploadTransport` / `SecureMacUploadClient` 的 start/status/chunk/finalize；Mac 侧继续包装 `MacAudioUploadCutoverExecutor` / `MacRecordingFileStore` 的 receive start/status/chunk/finalize。未新增 `/abort` route，未修改 upload route schema，未绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash，Mac 仍不主动连接 iPhone。

`CanonicalTransferRetryRuntime` 只允许恢复 existing eligible job。view refresh 不能创建 job；retry drainer 无既有 eligible job 时不创建 fresh job；peerUnknown、missing local audio、tombstone、conflict、security、malformed ledger fail-closed；stale interrupted session 在 status route 可用时必须先 status refresh；backoff/max attempt 防 retry storm。

`CanonicalTransferFinalizeProof` 现在包含 receiver node、session id、object id、byteSize、hash prefix、full internal hash proof、finalizedAt 和 verified flag。Transfer runtime 只输出 proof，`uiCompletedStatusMutated=false`；UI completed 仍必须由后续 v9.4 Sync Status Truth 消费 finalize proof 后决定，不能由 Transfer runtime 自行置 completed。

本轮仍不表示 canonical kernel 完成：Connection、Transfer、Sync、File 四域 owner 仍需组合验证，v9.4 状态真相尚未消费 Transfer proof，实时交换和完整 no-freeze runtime 仍需后续阶段。default/release 继续 `oldKernel`，legacy fallback 保留，`RecordingUploadCoordinator` 入口仍保留至 v9.6 切换集成。

## 2026-06-14 Canonical v9.1 / File Kernel Runtime

v9.1 将 file tree、manifest、checksum、effective read cache 诊断和 diagnostics IO 从同步外围优化提升为 File Kernel runtime owner 的第一步。新增 shared runtime 位于 `RokuricsShared/SyncCore/CanonicalFileSnapshotRuntime.swift`、`CanonicalManifestRuntime.swift`、`CanonicalChecksumRuntime.swift`、`CanonicalAsyncDiagnosticsWriter.swift` 和 `CanonicalMainActorHotPathGuard.swift`，并扩展 `CanonicalFileRuntime.swift` 的 `CanonicalFileKernelRuntimeReadiness.v910(...)` no-freeze scorecard。

File snapshot 由 `CanonicalFileTreeSnapshotBuilder` actor 构建，输入是 root token 与 safe logical scope；adapter 只暴露 logical token、stable file identity、size、mtime/contentVersion、kind、domain hint 和可选 hash proof，不把绝对路径带入 shared snapshot 或 diagnostics。builder 通过 detached utility task 执行，MainActor attempt count 来自 runtime probe，不写 hardcoded success 0。

Manifest runtime 由 `CanonicalManifestRuntimeBuilder` 纯值构建，不做 file IO。cache key 使用 root token、logical token、byte size、mtime/contentVersion、schema、domain hint 和 hash prefix，刻意不依赖 `generatedAt`。Checksum runtime 是 actor-backed cache wrapper；lookup hit 不调用 hash provider，size/mtime/contentVersion/schema/algorithm/token/root/domain 变化视为 stale，corruption fail-closed 后重建，并且 diagnostics 只允许 hash prefix。

iPhone `LocalNetworkSyncInventoryBuilder` 复用已有 background manifest/artifact input，将 artifact list 适配为 File Kernel snapshot/manifest 并只记录脱敏 diagnostics；不改变 sync plan、upload job creation、route、UI 行为或 legacy fallback。双端 `StudyLibraryStore` 保留 v8.69 effective read cache；新增 File-domain diagnostic records 只记录 cache key prefix、rebuild/invalidation reason 和 duration/count，不新增 iPhone synthetic `effectiveStudyTree` API，Mac `effectiveStudyTree` 继续一次性缓存。

Mac `/sync/inventory` 在 `policy.buildsCanonicalFacts` 分支内构建 request-scoped File Kernel snapshot/manifest；`oldKernel` 与 blocked 仍跳过 canonical file snapshot。route path、response schema、upload route、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier` 和 Mac server/iPhone client 拓扑未变。

本轮仍不表示 canonical kernel 完成：Connection、Transfer、Sync、File 四域 owner、状态真相、实时交换和 no-freeze runtime 仍必须分别验证；default/release 继续 `oldKernel`，legacy fallback 保留，未执行 paired iPhone/Mac 真机卡顿验证。

## 2026-06-14 Canonical v9.0 / Kernel Contract Freeze

v9.0 只冻结 canonical kernel 四个一等域的 portable contract：Connection、Transfer、Sync、File。新增内容位于 `RokuricsShared/SyncCore/`，包括基础 identity/time/sequence/protocol/domain 类型、四域协议、status truth hard rules、realtime status exchange envelope、file tree/manifest/checksum/root-bound atomic write/no-freeze contract、diagnostics taxonomy、cross-domain invariants 和 `CanonicalKernelV9ContractReadinessGate.v900(...)`。

本轮没有接入真实 iPhone/Mac app runtime，没有新增 route，没有修改 upload route schema，没有改 `SecureLocalHTTPSServer` route allowlist，没有改 `RecordingUploadCoordinator` 执行路径，没有改 `StudyLibraryStore` read path，没有改 Settings UI，也没有改变 `CanonicalKernelSwitch` 行为。default/release 仍为 `oldKernel`，legacy fallback 必须保留。Portable contract 不绑定本项目的本地安全传输实现；Rokurics 只能在后续 runtime adapter 中实现这些 contract。

Sync truth contract 明确硬规则：`metadataOnly`、receive record only、completed ledger alone、partial receive、local file exists 和 expected manifest hash 都不是 peer audio proof；same hash + same byteSize 才是 audio no-op；finalize proof 或 peer hash-size proof 才能显示 peer verified/completed；peerUnknown 必须 defer；existing different audio 必须 conflict/no-overwrite；view refresh 不得创建 upload job；retry drainer 只能恢复 existing eligible job。

Diagnostics taxonomy 覆盖 performance、convergence 和 redaction 三类。禁止泄漏绝对路径、完整 hash、secret、完整 fingerprint、完整 metadata JSON、request/response body、raw audio、完整 transcript/note/summary/provider response。File contract 明确 file tree scan、manifest build、full-file hash、diagnostics JSONL write 不得进入 MainActor hot path。

v9.0 readiness gate 是纯 evidence-bool scorecard，只输出 `READY_FOR_V9_RUNTIME_IMPLEMENTATION`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_PROCEED`；它不执行 sync/upload/read/file/network side effect。若出现 route/security bypass、default/release canonical、legacy fallback missing、peer proof violation、MainActor heavy work allowed 或 diagnostics leak，必须返回 `UNSAFE_TO_PROCEED`。

本轮新增 iPhone 与 Mac targeted contract tests，覆盖 Codable roundtrip、proof hard rules、redaction detector、gate READY/PARTIAL/NOT_READY/UNSAFE 和 transport-independent compile boundary。该状态不表示 canonical kernel runtime 已完成；任何只改 model/projection/canary/evidence/scorecard 且未落地四域 owner、状态真相、实时交换、文件不卡顿 runtime 的工作，仍不得声明 canonical kernel 完成。

## 2026-06-13 Canonical v8.73 / Final App-State Fix, Convergence Closure, and Real-Device Trial Readiness

v8.73 是 Claude 诊断问题的最终收口轮：不新增 canonical 业务域、不重写传输层、不新增 route、不改 upload route、不改 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、不删除 legacy、不默认启用 canonical。本轮以 v8.69 read cache、v8.70 Mac inventory off-main/mode gating、v8.71 `syncRequested` heartbeat hookup、v8.72 event-driven sync/status convergence 为代码级前置，补最终 app-state readiness gate、targeted 防回归测试和真机实测 runbook。

共享层新增 `CanonicalRealDeviceTrialReadinessGate.v873(...)`，输出 v8.73 `CODE_COMPLETE_RESULT` 四态：`READY_FOR_REAL_DEVICE_APP_TRIAL`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_TRY_ON_DEVICE`。该 gate 显式检查 read cache、Mac inventory off-main、oldKernel canonical skip、`syncRequested` heartbeat、event-driven trigger、status convergence、storm protection、build/test、default/release oldKernel、5 档主开关、`canonicalFullSync` gate、legacy fallback、route/security、switch-back proof driver、diagnostics redaction 和 runbook。real-device evidence 单独记录，不作为代码级 READY 的必要条件。

代码级 READY 只表示可以安装 debug/internal build 并按 runbook 上真机试跑；不表示 paired iPhone/Mac 验证已完成。没有真实 iPhone/Mac paired redacted jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须保持 `not run; no real-device evidence produced.`。如果 gate 返回 `PARTIAL_WITH_BLOCKERS`、`NOT_READY` 或 `UNSAFE_TO_TRY_ON_DEVICE`，不得切到 `canonicalFullSync` 上机，只能先修 blocker。

v8.73 runbook 已把最终真机序列收束为：backup/test device、oldKernel baseline、switch-back proof、canonicalShadow、canonicalDecisionOnly、canonicalApplyNoAudio、canonicalFullSync、new recording/event-driven sync、metadata/status/finalize convergence、oldKernel switch-back 和 diagnostics export。必须采集 connection diagnostics、canonical shadow/switch-back proof、sync event diagnostics、read cache diagnostics、Mac inventory diagnostics、upload/finalize diagnostics 等 redacted jsonl；stop conditions 包括 Divergent、FreezeViolation、RollbackFailed、SecurityFailure、metadataOnly-as-audioAvailable、completed-ledger-alone proof、partial receive audio proof、route/security change、RequestVerifier bypass、UI freeze、upload/sync event storm、heartbeat heavy sync 和 oldKernel switch-back failure。

## 2026-06-13 Canonical v8.72 / Event-Driven Sync Trigger and Status Convergence v1

v8.72 只补第二层触发问题：新录音、录音 metadata、学习库 metadata、generated artifact availability、tombstone/conflict、upload/finalize/retry/status、Mac receive/finalize/apply、transcription/note status 等本地状态变化会进入统一 event-driven immediate sync/status convergence queue。触发点只 schedule，不在 callback 内直接跑 heavy sync。

3 秒 heartbeat 仍只是探活/status 与 `syncRequested` hint carrier，不交换 inventory、不传文件；240 秒 periodic sync 仍保留为 fallback。queued event tick 复用现有 sync engine path，并继续受 current kernel switch mode、legacy/canonical decision、apply/read/upload/security gates、offline/background policy、running/pending gate 约束。

统一 queue 支持 debounce、duplicate reason coalescing、max frequency、storm suppression、sync in-flight follow-up tick 和 offline/background defer。status convergence 只刷新本地状态投影并排队收敛；不会把 local UI status 当 peer proof，也不会把 `metadataOnly`、completed ledger alone 或 partial receive 当成 audio proof。finalize proof 才能推进 uploaded verified 类状态。

Mac 仍不能主动连接 iPhone。Mac 侧事件只能设置既有 `syncRequested` hint、更新 pending state 等待下一次 iPhone heartbeat/inventory，或做 local-only status projection refresh；不新增 reverse connection，不新增 route，不改 `/sync/inventory`、receive.json/audio inbox 语义、upload route、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、pairing、certificate 或 Keychain。

新增 bounded/redacted diagnostics 覆盖 event trigger received/coalesced/queued/started/completed/failed/debounced/already-running/deferred/storm-suppressed/follow-up，以及 status convergence projection/finalize-proof/peer-proof-unavailable 和 Mac event hint set/consumed。没有真实 iPhone/Mac paired jsonl 时，不得声明状态收敛真机验证完成；下一轮 v8.73 建议补真机观察 runbook 与 diagnostics gate。

## 2026-06-13 Canonical v8.71 / Live Heartbeat Consumes syncRequested

v8.71 只修 Mac 手动同步后 iPhone 当前运行中的 live heartbeat 不消费 `syncRequested` 的触发层断点。Mac 仍是 HTTPS server，iPhone 仍是 client；Mac 不主动连接 iPhone。Mac 手动同步继续通过 heartbeat/status response 暴露 `syncRequested`/start-signal hint，请求 iPhone 尽快发起下一次现有同步。

iPhone `StudyLibrarySyncCoordinator.performHeartbeat()` 现在解析 `/device/status` 的 `DeviceStatusResponse.syncRequested` 和可选 `syncStartSignal`。缺失字段按 `false` 兼容旧 response，`ok` 和 device status summary 语义不变。收到 hint 后只排队 immediate sync tick，不在 heartbeat callback 内直接执行 heavy sync。

queued tick 复用现有 sync path：oldKernel 走 legacy local-network/manual sync，canonicalShadow、canonicalDecisionOnly、canonicalApplyNoAudio、canonicalFullSync 继续通过现有 kernel switch、decision、read、apply、upload 和 security gates。`syncInterval` 仍是 240 秒；heartbeat 仍是 3 秒探活，不变成 inventory exchange；本轮不新增 route、不改 upload route、不改 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`/pairing/Keychain，不做新录音或状态变化 event-driven trigger。

新增 bounded/redacted diagnostics 覆盖 heartbeat hint received/ignored/deferred/queued/deduped/started/completed/failed，以及 Mac manual sync pending set/advertised/consumed/inventory observed/cleared。Mac `/sync/inventory` 观察到带 `syncRunID` 的 iPhone 请求时，会把 pending 手动同步状态推进到可观察的“iPhone 已开始同步”状态或清理对应 pending signal。

状态收敛仍未完整解决：v8.71 只解决“Mac 点同步拉不起 iPhone”的 live heartbeat hookup；新录音/状态变化触发真同步和更系统的 event-driven convergence 仍留给 v8.72。没有真实 iPhone/Mac paired jsonl 时，不得声明状态收敛真机验证完成。

## 2026-06-12 Canonical v8.70 / Mac Server Inventory Off-Main + Kernel-Mode Build Gating

v8.70 只修 Mac server `/sync/inventory` 的 inventory/manifest/canonical facts 构建位置与 kernel-mode gating。范围不包含 `syncRequested`、heartbeat、sync interval、event-driven sync trigger、sync decision、read/apply/upload runtime 语义、upload job、route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、主开关 mode 语义、legacy 删除或 legacy fallback 禁用。

Mac `/sync/inventory` 现在按 `SecureReceiverService` 解析出的 `CanonicalKernelSwitchMode` 做 route-level gating；server 默认与 release/default 仍为 `oldKernel`。`oldKernel` 和 blocked mode 下完全跳过 canonical recording/library/generated artifact/tombstoneConflict object 构建、canonical manifest 构建和 canonical seam diagnostics/readiness 评估，legacy response 继续保持原 schema 与行为。

canonical modes 只构建该 mode 必需的 canonical facts：`canonicalShadow`/`diagnosticsOnly` 可用于 shadow/diff，`canonicalDecisionOnly` 只跑 decision 必需 seam，`canonicalApplyNoAudio` 不跑 audio commit/read seam，`canonicalFullSync` 构建 full facts 但每个 inventory request 只构建一次 canonical snapshot，后续 seam 复用同一 request context。seam 不再自己重复调用 adapter/build manifest。

Mac inventory manifest path 继续使用 v8.64 的 background input；server route 不再直接在 MainActor path 同步调用 `StudyLibraryStore.makeSyncManifest(...)` 来构造 inventory response。canonical adapter conversion 与 `CanonicalInventoryBuilderContract().build(...)` 被移入 background task；MainActor 只保留 route verification、轻量 result publish 和 bounded diagnostics。

新增 Mac inventory diagnostics/metrics 覆盖 route/manifest/canonical build started/completed/off-main/skipped/reused/duplicate-prevented/seam shared snapshot，以及 routeDurationMs、manifestBuildDurationMs、canonicalBuildDurationMs、canonical object/artifact counts、skipped/reused/duplicate counts 和 MainActor manifest/canonical/hash/scan attempt counts。diagnostics bounded/redacted，不写绝对路径、完整 hash、secret、完整 fingerprint、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body、raw audio bytes 或 full local audio path。

状态不收敛问题仍未在本轮解决。`syncRequested` 心跳接线仍按 v8.71 处理，legacy trigger/topology 仍需 v8.71/v8.72 后续修复。没有真实 iPhone/Mac paired jsonl，本轮不得声明 Mac 卡顿已真机验证完成。

## 2026-06-12 Canonical v8.69 / Canonical Read Effective Projection Cache

v8.69 只修 `canonicalFullSync` 下 UI 交互卡顿的第一直接根因：双端 `StudyLibraryStore` 的 canonical effective read projection 不再在每次 UI 读取时重算。范围不包含 sync trigger、heartbeat、sync interval、sync decision、apply runtime、upload runtime、upload job、route/security、TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、主开关 mode 语义、业务域扩展、legacy 删除或 legacy fallback 禁用。

iPhone `StudyLibraryStore` 现在把 canonical served read 的 `effectiveStudyItems` 与 `effectiveStudyFolders` 缓存在 store 内部；canonical snapshot/config/backing refresh/fallback 状态变化时一次性重建 items+folders，重复访问只命中 cache。当前 iPhone 源码没有 `effectiveStudyTree` 属性或 `VirtualStudyTreeBuilder` read path，UI 通过 `StudyLibraryBrowserView` 消费 items/folders；因此本轮以源码为准，没有新增 iPhone tree API。

Mac `StudyLibraryStore` 现在把 canonical served read 的 `effectiveStudyItems`、`effectiveStudyFolders` 与 `effectiveStudyTree` 作为同一 projection 一次性缓存；tree 不再通过属性链重复触发 items/folders conversion。`oldKernel`、read failure、divergence 或 legacy fallback 仍直接返回 legacy backing arrays / stored `studyTree`，不触发 canonical conversion。

新增 canonical read effective cache diagnostics/metrics：cache hit/miss/invalidated/rebuilt/tree rebuilt/fallback legacy/repeated access avoided rebuild/rebuild duration，以及 projection/tree/cache/invalidation counters、last rebuild reason 和 duration。diagnostics bounded/redacted，不写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、transcript/note/summary/provider response 或 raw audio bytes。

状态不收敛问题仍未在本轮解决。Mac server inventory off-main 仍按 v8.70 处理，`syncRequested` 心跳接线仍按 v8.71 处理，legacy trigger/topology 仍需 v8.71/v8.72 后续修复。没有真实 iPhone/Mac paired jsonl 时，不得声明卡顿真机验证完成。

## 2026-06-12 Canonical v8.68 / T7 Single Kernel Switch UI + Final Code Completion Gate

v8.68 只处理 Claude 代码完工任务卡 T7：单一主开关 UI 收口与最终代码完工门。范围不包含 inventory MainActor 逻辑、read runtime 接线、recording ReadSeam 接线、apply/upload runtime 业务实现、audio commit executor、production-root write gate 语义、主开关底层 mode 语义、业务域扩展、route/security、TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、legacy 删除或 legacy fallback 禁用。

iPhone/Mac Settings 的 DEBUG `Debug · 同步内核` 区现在以一个 `内核模式` 选择器作为用户可见主开关，手动可选 5 档：`oldKernel`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`。`diagnosticsOnly` 仍作为内部兼容的安全 no-op mode 保留，但不再出现在 T7 手动主开关选项中。默认与 release/default 仍解析为 `oldKernel`。

选择 `canonicalFullSync` 必须二次确认。确认文案明确：只在 gates 允许时启用 canonical decision/read/apply/audio commit；legacy fallback 保留；可以立即切回 `oldKernel`；应先备份或使用测试设备；应先运行切回证明；出现 Divergent、FreezeViolation、RollbackFailed、SecurityFailure、ExistingDifferentAudioBlocked 必须停止。切回 `oldKernel` 会立即清除 fullSync confirmation。

旧的 libraryMetadata debug pilot 等分散开关继续保留为 DEBUG 高级限制/诊断入口，UI 文案标注其只能降级、阻断或生成诊断，不能把 `oldKernel`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio` 提权，不能单独打开 productionRoot write，也不能越过 owner approval/manual confirmation。Path B 传输仍复用 legacy TLS/HMAC/上传 route，`RequestVerifier` 未改。

`CanonicalSyncKernelCompletionScorecard.v868(...)` 现在汇总 T1–T6、默认/release oldKernel、5 档 UI、fullSync confirmation、decision/read/apply/audio/existence 映射、oldKernel 回 legacy/nil、legacy fallback、Path B transport、route/security、diagnostics redaction、switch-back proof driver、real-device evidence 与最终 code-completion status。`READY_FOR_REAL_DEVICE_CANONICAL_SWITCH` 的含义是代码级可进入真机测试，不表示 paired-device 验证完成；没有真实 iPhone/Mac paired jsonl 时仍必须写 `realDeviceEvidencePresent=false`。

下一步仍是用户按 runbook 从 `oldKernel` -> `canonicalShadow` -> `canonicalDecisionOnly` -> `canonicalApplyNoAudio` -> `canonicalFullSync` 逐档真机试运行并导出 redacted jsonl。不得把本地 build/test、simulator、fixture root 或 realistic-root proof 当作 paired-device real-device evidence。

## 2026-06-12 Canonical v8.67 / T6 Debug Switch-Back Proof Driver

v8.67 只处理 Claude 代码完工任务卡 T6：把已有 realistic-root switch-back harness 接成 Debug 可点入口。范围不包含 inventory MainActor、read runtime 接线、recording ReadSeam、apply runtime、upload runtime、audio commit executor、`canonicalFullSync` production-root gate、主开关 mode 语义、业务域扩展、route/security、TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、legacy 删除或 legacy fallback 禁用。

共享层新增 `CanonicalSwitchBackProofDiagnostics.swift`，提供 Debug-only redacted JSONL writer、`CanonicalSwitchBackProofDebugRunner` 和 UI-safe summary。iPhone 新增 `IPhoneCanonicalSwitchBackProofDriver`，Mac 新增 `MacCanonicalSwitchBackProofDriver`，二者只把当前 app data root 作为 source root 传入 shared runner；proof root 始终由 `CanonicalRealisticRootSwitchBackProofDriver` clone 到 system temp 下的 explicit test clone，再调用 `CanonicalSwitchBackRealisticRootHarness.runKernelSwitchBackProof()` 执行 oldKernel -> canonicalFullSync -> oldKernel -> canonicalFullSync switch-back proof（existing sequence proof 还保留 shadow/decision/applyNoAudio 中间阶段）。

Debug Settings 的 `Debug · 同步内核` 区现在有“运行新旧内核切回证明”按钮和 redacted summary。按钮只在 DEBUG 编译出现；点击后显示 running/passed/failed/blocked、clone root token、domain matrix、crash/restart、old/canonical/read switch-back summary、blocker 和 `temp/CanonicalSwitchBackProofDebugRunner/<redacted-token>/Diagnostics/canonical-switch-back-proof.jsonl` 形式的 redacted evidence path。它不自动切主开关，不触发 sync/upload，不改 read/apply/upload runtime，不写业务域或 source root；Mac 侧不重启 `SecureLocalHTTPSServer`，不改变 `/sync/inventory` route、receiver route/security、`receive.json`、audio inbox、pending sync、transcription 或 note generation。

`CanonicalSwitchBackRootSafetyGuard` 继续拒绝 `/`、home、repo root、Documents/Application Support production root 和未标记非 temp root；本轮补强为拒绝 Documents/Application Support production 子路径和 Desktop production root。证据 JSONL event 只写 timestamp、nodeRole、runID、status、rootKind、redactedRootToken、modeSequence summary、domain/crash counts、blocker enum、evidenceKind 和 relative evidence path；不写绝对路径、完整 hash、metadata JSON、transcript/note/summary/provider response、request/response body、secret、fingerprint、delete target path、full local audio path 或 raw audio bytes。

当前 evidence kind 是 `realisticRoot`，`realDeviceEvidencePresent=false`。没有 paired iPhone/Mac jsonl 时，不得声明真机 switch-back proof 完成，也不得把 simulator、unit test fixture、temp realistic-root proof 或 local build/test 当成 real-device evidence。下一轮 v8.68 才做 T7：单一主开关 UI 收口和最终 code-completion gate。

## 2026-06-12 Canonical v8.66 / T4-T5 Executor and Port Injection + Gated Production-Root Write

v8.66 只处理 Claude 代码完工任务卡 T4/T5：按 `CanonicalKernelSwitch` effective mode 注入 production ports/executors，并把 production-root RealApplyPort write 解锁收敛到 `canonicalFullSync` gate。范围不包含 inventory MainActor、read runtime 接线、recording ReadSeam 接线、sync decision 语义、route/security、TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、业务域扩展、canary/evidence/landing/retirement 类型或 legacy 删除。

iPhone 侧新增 `IPhoneCanonicalProductionPortFactory`，Mac 侧新增 `MacCanonicalProductionPortFactory`，共享 `CanonicalProductionPortInjectionPolicy`。app construction 与 refresh path 现在从 `CanonicalKernelSwitchEffectiveConfiguration` 推导 executor/port availability：`oldKernel`、blocked、diagnostics/shadow/decision modes 不构造 production-root writable ports；`canonicalApplyNoAudio` 可注入 non-audio apply/existence path 但 audio upload executor 保持 disabled；`canonicalFullSync` 只有在 DEBUG/internal、ownerApproved、manualConfirmation、legacy fallback、legacy-readable、readiness、route/security 和 root safety gate 全部满足时，才允许 `allowProductionRootWrites=true`。

iPhone `MacConnectionView`、`StudyLibrarySyncCoordinator`、`LocalNetworkSyncEngine` 和 `RecordingUploadCoordinator` 现在以主开关输出刷新 recording/library/generated/tombstone executor slots；audio upload 仍复用 `RecordingUploadCoordinator` -> `IPhoneAudioUploadCutoverExecutor` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient` 的 existing secure path，且 factory gate 不允许 `canonicalApplyNoAudio` 或 unsafe root 创建 canonical upload job。

Mac `RokuricsMacApp`、`SecureReceiverService` 和 `SecureLocalHTTPSServer` 现在按主开关注入 recording/library/generated/tombstone executors、`canonicalRecordingExistenceApplyPort` 和 `MacAudioUploadCutoverExecutor` holder。`oldKernel` 下 existence port 为 nil；`canonicalApplyNoAudio`/`canonicalFullSync` gate allowed 时可注入 metadata-only existence ledger，但 metadataOnly 仍不等于 audioAvailable，不写 audio bytes、不创建 fake audio file。服务器 route behavior、`/sync/inventory`、`/sync/apply-metadata`、audio start/status/chunk/finalize route 和 `RequestVerifier` 未改。

production root URL 来自现有 Store/recording file store root，进入 RealApplyPort constructor 前必须通过 root safety guard；diagnostics 只输出 redacted mode/root-safety/blocker summary，不写绝对路径。release/default 仍为 `oldKernel`，未确认或未 owner approval 的 `canonicalFullSync` 仍 blocked/dry-run。当前验证仍是本地 build/test；未运行 paired iPhone/Mac 真机，不能声明真机 production-root write 或 audio upload evidence。下一轮 v8.67 做 T6：切回证明 driver。

## 2026-06-12 Canonical v8.65 / T2-T3 Master Switch Read + recordingMetadata ReadSeam Runtime Wiring

v8.65 只处理 Claude 代码完工任务卡 T2/T3：主开关驱动双端 `StudyLibraryStore` read runtime configuration，以及 iPhone/Mac recordingMetadata ReadSideSeam 接入真实 read runtime。范围不包含 inventory MainActor、apply runtime、upload runtime、audio commit executor、`canonicalFullSync` production-root write gate、route/security 或主开关 mode 语义变更。

iPhone 和 Mac 的主开关 refresh / service construction path 现在消费 `CanonicalKernelSwitchEffectiveConfiguration.readRuntimeConfiguration` 并传入各自 `StudyLibraryStore.setCanonicalReadRuntimeConfiguration(...)`。`oldKernel`、disabled 和 blocked read configuration 会清空 canonical read override，使 Store 回 legacy read；`canonicalShadow` 只允许 parallel compare/non-serving read；`canonicalDecisionOnly` 与 `canonicalApplyNoAudio` 不 serve canonical read；`canonicalFullSync` 在 gate allowed 时可传 guarded canonical read config 并保留 legacy fallback。

iPhone/Mac `CanonicalReadRuntimeAdapter` 现在通过 `IPhoneRecordingMetadataReadSideSeam` / `MacRecordingMetadataReadSideSeam` 读取 recordingMetadata projection。canonical read 只进入 effective read projection；read failure、divergence、unsupported 或 missing evidence 均 fallback legacy。read path 不触发 sync/upload、不创建 upload job、不 mutate Store backing data，不改变 Mac `/sync/inventory` response、`receive.json`、audio inbox、pending sync 或 transcription/note generation。

specialized read configs 只能进一步限制主开关，不能把 `oldKernel`、`canonicalDecisionOnly` 或未过 gate 的模式升级成 canonical serving read。当前验证仍是本地 build/test；没有 paired iPhone/Mac 真机 jsonl 时，不得声明真机读切换验证完成。下一轮 v8.66 才处理 T4/T5：端口/执行器注入与 production-root gated write。

## 2026-06-12 Canonical v8.64 / T1 Inventory MainActor Residual Closure

v8.64 只处理 Claude 代码完工任务卡 T1：inventory / runtime snapshot / sync manifest 构建路径的 MainActor 重活残留。范围限定在 iPhone/Mac inventory facts 收集、runtime snapshot、checksum cache telemetry、sync manifest background snapshot 与 pure build；不改 read runtime、recording ReadSeam、apply runtime、upload runtime、audio commit executor、`canonicalFullSync` production-root gate、主开关 mode、route、upload route、TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、Keychain 或 legacy fallback。

iPhone 侧 `LocalNetworkSyncInventoryBuilder` 仍是轻量 struct，但不再承载全量 metadata/jobs load、directory scan、metadataHash 或 SHA256 重活。`loadBackgroundInput(...)` 和新增 background artifact/manifest builders 会在 detached background path 读取 `RecordingMetadata`、upload jobs、study manifest facts、audio facts、folder/item/recording metadata hashes 和 artifacts；`buildRuntimeSnapshot(...)` 只消费 immutable input 并构建 canonical-compatible snapshot。legacy inventory 输出和 `/sync/inventory` wire schema 保持兼容，same `syncRunID` snapshot reuse 语义保留。

`makeSyncManifest` 的 iPhone 主线程残留已收敛为 background snapshot -> pure build：`StudyLibraryStore.makeSyncManifestInBackground(...)` 只做轻量 root 配置读取，实际 recordings load 与 `StudyLibrarySyncManifest` 构建在 background path 完成；inventory legacy build 也改为使用 `LocalNetworkSyncInventoryBackgroundInput`。纯构建不访问 MainActor store、不做网络、不创建 upload job。

Mac `/sync/inventory` 的 T1 MainActor blocker 已清理到 background facts path：`SecureLocalHTTPSServer` 的 Mac inventory input 现在在 background path 构建 manifest facts、folder/item/recording metadata hashes 和 artifacts，route 只消费 immutable input；不改变 `/sync/inventory` response schema，也不改变 `RequestVerifier` 或任何安全/上传 route 行为。

Telemetry 现在增加并输出真实 `manifestBuildDurationMs`、`hashSkippedByCacheHitCount`、`mainActorManifestBuildAttemptCount`，并继续保留 `inventoryBuildDurationMs`、`metadataLoadDurationMs`、`jobsLoadDurationMs`、`directoryScanDurationMs`、`hashDurationMs`、cache hit/miss/stale、hash computed、MainActor metadata/jobs/hash/scan attempts、duplicate snapshot build 和 snapshot reuse 等计数。正常路径为 0 的 MainActor attempt 由 detector/路径统计得出，不以 hardcoded 0 冒充成功；diagnostics 继续 redacted，不写绝对路径、完整 hash、完整 metadata JSON、secret、fingerprint、request/response body、provider 内容或 raw audio bytes。

本轮验证仍是本地 build 与 targeted tests；未运行 paired iPhone/Mac 真机，未产生 jsonl real-device evidence，不能声称真机卡顿已验证完成。下一轮 v8.65 才处理 T2/T3：主开关驱动 read 与 recording ReadSeam 接入。

## 2026-06-12 Canonical v8.58 / RecordingMetadata RealApplyPort + ReadSideSeam

v8.58 只补 `recordingMetadata` 域的最低真机灰度缺口：新增 `Rokurics/IPhoneRecordingMetadataRealApplyPort.swift`、`RokuricsMac/MacRecordingMetadataRealApplyPort.swift`、`Rokurics/IPhoneRecordingMetadataReadSideSeam.swift` 和 `RokuricsMac/MacRecordingMetadataReadSideSeam.swift`。本轮不扩展到 audio bytes、audio upload、upload ledger、generated artifacts、library metadata、tombstone/conflict、transcript/note/summary/provider 内容、connection/security 或新 route。

iPhone/Mac recording metadata RealApplyPort 现在提供双端真实写入端口，沿用 root-bound metadata write core：只写 title/name、legacy-compatible recording metadata、business modifiedAt fact 和 stable business metadataHash，具备 atomic write、rollback checkpoint、postcondition verification、rollback failure fatal blocker 和 redacted diagnostics。canonical 写入保持 legacy-readable，且 canonical reader 可读取同一业务 metadata；不写 audio、不创建 upload job、不改 upload ledger、不写 standalone note 或 generated content。

iPhone/Mac recording metadata ReadSideSeam 现在提供双端读侧 seam，按 `CanonicalKernelSwitch` 映射：`oldKernel` 默认 legacy read，`canonicalShadow`/`canonicalDecisionOnly` 只 diff，`canonicalApplyNoAudio` 可 diff 但不默认 serve canonical，`canonicalFullSync` 只有在 gate allowed 且 diff clean 时可 serve canonical recording metadata projection。任何 divergence、read failure、unsupported/missing evidence 或 release/default 均 fallback legacy；read 不触发 sync/upload、不 mutate Store、不改 Mac inventory response、`receive.json` 或 audio inbox。

主开关仍是唯一行为入口：default/release 继续 `oldKernel`，legacy fallback 和 legacy recording metadata path 保留，specialized recording config 不能绕过主开关。当前验证是本地 build 与 targeted tests；未运行 paired iPhone/Mac 真机灰度，也未产生 jsonl real-device evidence。

## 2026-06-11 Canonical v8.57 / P3-2 Realistic Library Root Switch-Back Proof

v8.57 / P3-2 只做 realistic app-data-root / test-cloned library root 级别的 switch-back 证明，不新增业务域、不新增 route、不改 upload route、不改连接安全层、不改变主开关语义、不删除 legacy。本轮把 v8.44/v8.45 的 synthetic compatibility proof 扩展为 `CanonicalSwitchBackRootSafetyGuard`、`CanonicalRealisticLibraryRootFixture`、`CanonicalRealisticAppDataRootClone`、`CanonicalSwitchBackRealisticRootHarness.runKernelSwitchBackProof()`、`CanonicalDomainSwitchBackMatrix`、`CanonicalKernelSwitchSequenceProof` 和 `CanonicalSwitchBackEvidenceExporter`。

realistic root fixture 只允许 temp/test-cloned root；guard 会拒绝 `/`、home、repo root、Documents/App Support 生产路径和未显式标记的非 temp root。fixture deterministic 地覆盖 study library folders/items/standalone-note metadata、recording metadata、generated artifact metadata 与安全内容 fixture、tombstone/conflict/resurrection block marker、canonical existence ledger、audio inbox receive metadata、小 audio fixture、upload ledger/job、retry、checksum cache、diagnostics、legacy-compatible store、canonical supplemental 和 schema/version marker。diagnostics 只输出 redacted root token，不写绝对路径、完整 hash、完整 metadata JSON、transcript/note/summary/provider 内容、request/response body、secret、fingerprint 或 raw audio bytes。

P3-2 domain switch-back matrix 固定覆盖五个业务域：`recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload`。每个域证明 legacy write -> canonical read、canonical write -> legacy/oldKernel read、oldKernel write -> canonicalFullSync read、oldKernel/canonicalFullSync 双向安全继续写、无需 migration、无 canonical-only mandatory field、无 legacy-incompatible disk format、fallback 保留且 diagnostics redacted。crash/restart proof 覆盖 12 个 crash point，包括 checkpoint 前后、read projection、inventory snapshot、audio session/chunk/finalize、finalize 后本地 ledger 前、retry persist 和 diagnostics write；partial state 不得被当成 completed 或 audioAvailable，不得产生 duplicate job storm，不得 physical delete。

`CanonicalSyncKernelCompletionScorecard.v857(...)` 在 realistic-root proof 通过但没有 paired-device jsonl 时仍返回 `codeCompleteNeedsDeviceEvidence`；若 switch-back proof 缺失/失败则 blocked/incomplete，legacy fallback 缺失、release/default canonical、安全绕过或 diagnostics 泄漏则 unsafe。当前源码只提供 code-level / realistic-root proof；未运行真实 iPhone/Mac paired-device trial，不产生 real-device evidence。下一阶段仍是 P4 observation with paired devices。

## 2026-06-11 Canonical v8.56 / P3-1 Unified Master Kernel Switch Consolidation

v8.56 / P3-1 只做主开关收敛，不新增业务域、不新增 route、不改连接安全层、不重写 upload/read/apply 业务实现。本轮把 inventory runtime、sync decision runtime、recordingMetadata、libraryMetadata、generatedArtifacts、tombstoneConflict、audioUpload、existence/apply bridge、non-audio apply、audio upload、read runtime、diagnostics/shadow 与 completion/switch-back policy 继续收口到统一 `CanonicalKernelSwitchConfiguration.resolve()` / `CanonicalKernelSwitchEffectiveConfiguration`。

主开关 mode 固定为 `oldKernel`、`diagnosticsOnly`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`、`blocked`。默认和 release/default 仍是 `oldKernel`；`oldKernel` 关闭所有 canonical owner；`diagnosticsOnly` 与 `canonicalShadow` 不写、不上传、不 serve canonical read；`canonicalDecisionOnly` 只允许 canonical decision；`canonicalApplyNoAudio` 允许 gated non-audio apply 但明确禁用 canonical audio upload；`canonicalFullSync` 才映射 decision/apply/audio upload/read 全 runtime，且必须 DEBUG/internal、manual confirmation、owner approval、legacy fallback、legacy read/write/upload path、domain readiness、diagnostics redaction、route/security unchanged 和 switch-back preconditions 全部通过。

本轮新增主开关 gate/report/diagnostics contract：`CanonicalKernelSwitchGate`、`CanonicalKernelSwitchGateResult`、`CanonicalKernelSwitchGateState`、`CanonicalKernelSwitchReport`、`CanonicalKernelSwitchDiagnosticKind`。`CanonicalKernelSwitchPolicy` 增加 P3-1 readiness/security/switch-back blocker 字段；advanced overrides 只能降权或限制，不能在 master switch 之外提升 sync/apply/existence/audio/read/libraryMetadata pilot 权限。旧 libraryMetadata debug pilot 不能越过 `oldKernel` 或 production-root safety；Mac app 启动路径改为传入 master effective pilot config，而不是直接把旧 UserDefaults pilot 作为 production owner。

本轮新增/更新双端 `CanonicalKernelSwitchTests`，覆盖 default/release oldKernel、fullSync 缺 debug/owner/confirmation blocker、domain/audio/read/apply/switch-back readiness blocker、applyNoAudio audio block、advanced override 降权、unsafe same-mode policy blocked、libraryMetadata production-root pilot 不能 override oldKernel、report diagnostics redaction 和 builder/gate contract。没有运行真实 iPhone/Mac 手动切换；v8.57/P3-2 仍负责 realistic library root switch-back proof。

## 2026-06-11 Canonical v8.55 / P2-5 audioUpload Domain Readiness

v8.55 / P2-5 只推进第五个同步业务域 `audioUpload`。本轮不重写 v8.49 的 resumable commit executor，也不重写 v8.50 的 retry/state truth；新增的是该域的 readiness contract、主决策接线、read/status 投影字段、ownership policy wrapper、runtime diagnostics scope、kernel switch scope 和 domain readiness scorecard。

audioUpload contract 固定为 `canonical-audio-upload-v1`。域字段只包含 recordingID/objectID、local audio existence/byteSize/hash prefix/safe token、peer existence/audio availability、proven peer byteSize/hash prefix、redacted session prefix、confirmedBytes、finalize proof accepted、retry state、conflict state 和 mtime/status summary。完整本地路径、完整 hash、raw audio bytes、完整 metadata JSON、request/response body、secret、fingerprint、transcript/note/summary/provider 内容都不得进入 diagnostics 或 read projection。

状态证明规则保持 v8.49/v8.50 口径：metadataOnly、receiveRecordOnly、studyItemOnly、metadata uploaded、UI uploaded、completed ledger alone 和 expected manifest hash/size 都不是 audioAvailable/no-op/completed proof；peerUnknown deferred；same hash + same byteSize 才 no-op；different hash/size 或 existing different Mac audio 必须 conflict/no-overwrite；partial/failed session 不是 audioAvailable；uploaded/completed 只能在 Mac finalized proof 或 peer finalized same hash+byteSize proof 后成立。

主开关语义不变：default/release 仍是 `oldKernel`；diagnosticsOnly/canonicalShadow 只比较不建 job；canonicalDecisionOnly 可评估 audioUpload decision 但不发网络；canonicalApplyNoAudio 明确阻止 canonical audio upload；canonicalFullSync 在 DEBUG/internal、owner approval、manual confirmation、legacy fallback 和 gate 允许时，可让 audioUpload canonical decision/commit/read-status 成为主路径。legacy fallback、legacy upload client/path、switch-back proof 和 legacy-readable status 均保留。

本轮新增/更新 targeted tests 覆盖 v8.55 contract/read status、peerUnknown no fallback overwrite、runtime audioUpload scope/diagnostics、kernel switch fullSync/applyNoAudio mapping 和 scorecard report-only readiness。没有 paired iPhone/Mac real-device evidence；`readyForManualSwitchTrial` 与 `readyToRetireLegacyReportOnly` 仍不能作为自动切换或 legacy retirement 信号。

## 2026-06-11 Canonical v8.54 / P2-4 tombstoneConflict Domain Readiness

v8.54 / P2-4 只推进第四个同步业务域 `tombstoneConflict`。本轮把软墓碑 marker、library/object tombstone marker、冲突记录和 resurrection block record 固化为独立 domain contract：markerID、objectID、objectKind、markerKind、conflictKind、tombstoneState、displayState、businessModifiedAt、actorDeviceRole、parentObjectID 和 conflictResolutionState。physical/delete target path、local/resource/absolute path、完整 metadata/content、standalone note 正文、generated transcript/note/summary 内容、provider response、audio hash/path/byteSize、upload/receive 状态、observedAt/receivedAt、UI-only 状态和 diagnostics 都不进入 hash。

canonical hash schema 固定为 `canonical-tombstone-conflict-v1`。`CanonicalTombstoneConflictCandidate` 的 marker hash/payload 现在也派生自同一 `CanonicalTombstoneConflictBusinessFields`，不再维护旧的 v8-11 内部 hash 口径。soft object/library tombstone marker、conflict record 和 resurrection block record 可执行；generated artifact tombstone marker 仍是 report-only/unsupported，不会物理删除 artifact 或生成物内容。

ModifiedAt/logical-time policy 使用 tombstone/conflict 的业务 modifiedAt 或等价 logical event time。hash 相同为 no-op；peer/local 逻辑时间较新时选择对应 marker；equal logical time 且 hash 不同 deterministic defer/write conflict record；missing logical time、schema mismatch 或 unsupported marker 必须 fallback/block legacy。restore、clear tombstone、physical delete、permanent delete 和 tombstone GC 请求在本域内均被阻断；stale live resurrection 写 resurrection block record 或 conflict record，不恢复已墓碑对象。

sync runtime 现在把 `tombstoneConflict` 列入默认 enabled decision scope，并在 explicit debug/internal primary gate 下检查 tombstoneConflict schema。apply runtime 继续使用既有 root-bound tombstone/conflict executor、rollback、postcondition、success-only duplicate suppression 和 anti-resurrection guard。read runtime 增加 `canonicalTombstoneConflictRead*` diagnostics；iPhone/Mac Store/UI 已通过既有 effective study items/folders 和 tombstone read projection 消费 guarded canonical projection，默认和 fallback 仍读 legacy。

本轮新增 v8.54 domain readiness scorecard 和双端 targeted tests，覆盖 hash/path/UI/upload exclusion、candidate marker hash 统一 schema、logical-time/LWW/tie、unsafe delete/restore/GC blocker、anti-resurrection、runtime schema gate、read diagnostics 和 report-only readiness。没有 paired iPhone/Mac real-device evidence；`readyForManualSwitchTrial` 与 `readyToRetireLegacyReportOnly` 仍不能作为自动切换或 legacy retirement 信号。

## 2026-06-11 Canonical v8.53 / P2-3 generatedArtifacts Domain Readiness

v8.53 / P2-3 只推进第三个同步业务域 `generatedArtifacts`。本轮把 transcript/note/summary 生成物的稳定 metadata/availability 固化为独立 domain contract：artifactID、recording objectID、kind、availability、contentHash、byteSize 和 business modifiedAt。logical/local path、observedAt、producer node、provider request/response、transcript/note/summary 正文、diagnostics、audio bytes、upload/receive state、security material 和 tombstone 都不进入 hash。

canonical hash schema 固定为 `canonical-generated-artifact-v1`。同一 object/kind 的 contentHash+byteSize 相同即为 generated artifact no-op；contentHash/byteSize 缺失、availability 不能证明文件存在、unsupported kind/audio 混入、schema mismatch 或 business modifiedAt 缺失都必须 defer/block/fallback legacy。modifiedAt/LWW 只在双方内容不同且内容 proof 完整时用于 local newer send、peer newer apply、equal modifiedAt tie deferred。

sync runtime 现在把 `generatedArtifacts` 列入默认 enabled decision scope，并在 explicit debug/internal primary gate 下检查 generated artifact schema。`canonicalDecisionOnly` 只能做 decision/no apply；`canonicalApplyNoAudio` 可在既有 root-bound generated artifact apply port 下 apply 非音频生成物；`canonicalFullSync` 可在 guarded read gate 下 serve canonical generated artifact read projection。default/release 仍为 `oldKernel`，legacy fallback、legacy artifact route 和 switch-back proof 保留。

apply/read runtime 边界不变：generated artifact apply 只使用既有 root-bound/atomic/postcondition/rollback port 写 legacy-readable generated artifact 文件，success-only duplicate suppression；不新增 route、不创建 generated artifact upload job、不触发 AI 调用/转写/笔记生成、不写 audio、不改 security。read projection 只暴露 metadata/availability/hash prefix/byteSize/kind 等摘要，新增 `canonicalGeneratedArtifactRead*` diagnostics，并明确 `contentExcluded=true`。

本轮新增 v8.53 domain readiness scorecard 和双端 targeted tests，覆盖 hash/path/provider exclusion、content identity no-op、modifiedAt/LWW、missing content/modifiedAt/unsupported blocker、runtime schema gate、duplicate guard、read diagnostics 和 report-only readiness。没有 paired iPhone/Mac real-device evidence；`readyForManualSwitchTrial` 与 `readyToRetireLegacyReportOnly` 仍不能作为自动切换或 legacy retirement 信号。

## 2026-06-11 Canonical v8.52 / P2-2 libraryMetadata Domain Readiness

v8.52 / P2-2 只推进第二个同步业务域 `libraryMetadata`。本轮把 folder/study item/standalone-note shell 的稳定业务 metadata 固化为独立 domain contract：objectID、objectKind、title/name、itemKind、parentID/hierarchy/filing/folder references、tags、color/order、associatedRecordingID、deleted metadata 和 businessModifiedAt。它不进入 note full content、generated artifacts 内容、audio facts、local/resource path、logical resource tokens、upload/receive/sync 状态、provider request/response、diagnostics 或 security secrets。

canonical hash schema 固定为 `canonical-library-metadata-v1`，iPhone/Mac 通过同一 `CanonicalLibraryMetadataBusinessFields` / `CanonicalLibraryMetadataHashSchema` path 计算 `metadataHash`。此前 `CanonicalProjectionContract` 的 study item hash payload 会包含 `resourceTokens`，这与 P2-2 “资源路径变化不改变 libraryMetadata hash” 冲突；本轮已改为同一 canonical business fields hash 输入，resource/logical tokens 和路径变化不再改变 libraryMetadata metadataHash。

libraryMetadata decision ownership 由 `CanonicalLibraryMetadataModifiedAtPolicy` 明确：metadataHash 相等为 no-op；businessModifiedAt 新的一侧获胜；equal modifiedAt 且 hash 不同 deterministic defer/conflict；modifiedAt 缺失或 schema mismatch 必须 fallback/block legacy。`CanonicalLibrarySyncPlanner` 调用该 policy，`CanonicalSyncRuntime` 增加 libraryMetadata schema gate 与 `canonicalLibraryMetadataDecision*` diagnostics。default/release 仍为 `oldKernel`，diagnostics/shadow 只比较，primary/apply/read 仍需 explicit debug/internal gate、legacy fallback 和 switch-back proof。

apply/read runtime 仍沿用既有安全边界：libraryMetadata apply 只允许 root-bound metadata write、atomic/postcondition/rollback 和 success-only duplicate suppression；不得移动 resource、写 standalone note content、写 audio/upload/receive 状态或触发 generated content。read runtime 增加 `canonicalLibraryMetadataRead*` diagnostics；Store/UI 已通过 effective study items/folders 消费 guarded canonical projection，但任何 divergence、unsupported object、missing evidence、schema mismatch 或 release/default 都必须 fallback legacy。

本轮新增 v8.52 domain readiness scorecard 和双端 targeted tests，覆盖 hash contract、resource token exclusion、businessModifiedAt/LWW policy、runtime schema gate、read diagnostics 和 report-only readiness。没有 paired iPhone/Mac real-device evidence；`readyForManualSwitchTrial` 与 `readyToRetireLegacyReportOnly` 仍只能作为报告字段，未执行 legacy retirement。

## 2026-06-11 Canonical v8.51 / P2-1 recordingMetadata Domain Readiness

v8.51 / P2-1 只推进第一个同步业务域 `recordingMetadata`。本轮把录音标题/名称、study/folder filing relation 中属于录音 metadata 的字段、tags、deleted metadata、createdAt/duration 只读事实，以及 stable business `metadataHash` / business `modifiedAt` / LWW policy 固化为该域 contract；不进入 audio bytes、audio upload、upload ledger、receive session/chunk/finalize、transcript/note/summary/generated content、libraryMetadata、tombstone/conflict 或 connection/security route。

canonical hash schema 固定为 `canonical-recording-business-metadata-v1`，只 hash stable business metadata：objectID、title、filing components、tags、isDeleted、deletedAt。createdAt、modifiedAt、duration 是 read/decision facts，不进入 hash；upload progress、upload ledger、receive status、receivedAt、observedAt、local/audio path、audio hash/size、processing status、diagnostics、provider response 和 transcript/note/summary/generated content 均不进入 recordingMetadata hash。iPhone/Mac 通过同一 `CanonicalRecordingMetadata` normalization/hash path 计算，locale-independent 且 app restart stable。

ModifiedAt/LWW policy 使用业务 modifiedAt；不得使用 receivedAt、observedAt 或 upload time。当前旧 iPhone `RecordingMetadata` 没有独立 business modifiedAt，adapter 仍采用 documented createdAt/deletedAt fallback；主 decision gate 在 `canonicalModifiedAtSemanticsAvailable=false` 且未显式允许 fallback 时必须 fallback/block legacy。equal modifiedAt 且 metadataHash 不同会 deterministic defer/conflict，不自动覆盖。

主开关语义保持：default/release 仍是 `oldKernel`；`diagnosticsOnly`/`canonicalShadow` 只比较不写不切 read；`canonicalDecisionOnly` 可让 recordingMetadata decision 成为主决策但不写；`canonicalApplyNoAudio` 可在 gate 允许时执行该域 metadata apply 且不碰 audio；`canonicalFullSync` 可在 guarded gate 下 serve canonical recordingMetadata read projection。任一 canonical/legacy divergence、schema mismatch、missing snapshot、unsupported object、missing modifiedAt policy 或 read/apply failure 都必须 fallback/block legacy。

本轮新增 recordingMetadata 专属 diagnostics alias、P2-1 contract/scorecard 类型，以及 iPhone/Mac Store effective read overlay，使 guarded canonical read served 时已有录音条目可消费 canonical recordingMetadata title/tags/duration/deleted projection。legacy fallback、legacy-readable disk format、switch-back proof 和 duplicate suppression success-only 均保留。没有真机 paired-device evidence；`readyToRetireLegacy` 仍仅 report-only，不执行 legacy retirement。

## 2026-06-11 Canonical v8.50 / P1-3 Upload Retry Drain and State Consistency

v8.50 / P1-3 收齐 v8.48 `manifest.recordings` apply 与 v8.49 audio upload commit executor 之后的上传状态口径。本轮新增 shared `CanonicalUploadStateTruth` / `CanonicalUploadStateReconciliationReport`、`CanonicalUploadRetryDrainerPolicy` 和 `CanonicalUploadDuplicateJobGuard`，并在 iPhone canonical upload runtime path 进入既有 executor 前输出 redacted state/projection diagnostics。该接线只解释并约束状态，不新增 route、不改 read path、不改 UI、不重写连接安全层。

统一状态规则：local audio missing 不是 candidate；peerUnknown deferred；metadataOnly、receiveRecordOnly、studyItemOnly、metadata uploaded、UI uploaded、completed ledger alone 都不是 `audioAvailable` 或 completed proof；expected manifest hash/size 也不是 peer proof。same hash + same byteSize 才是 audio no-op；different hash/size 或 Mac existing different audio 必须 conflict/no-overwrite。upload completed verified 只能来自 Mac finalized proof，或来自 peer inventory 已证明的 finalized same hash+byteSize；ledger completed without peer proof 会被拒绝并重新归入 needs upload/deferred/conflict。

retry drainer policy 明确只恢复 existing eligible canonical/legacy job：view refresh 不能 drain，retry drainer 不能创建 unrelated fresh job，peerUnknown/missing local audio/tombstoned/conflict/security failure/malformed ledger 都 fail closed，backoff 与 max retry 会阻止 retry storm。stale interrupted session 在已有 status route 支持时先要求 status refresh，再从 confirmedBytes 继续；不会绕过 `RecordingUploadClient`、`SecureMacUploadClient` 或 existing secure routes。

ownership 规则明确：`oldKernel` 只有 legacy owner；`diagnosticsOnly`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio` 不允许 canonical audio upload job；`canonicalFullSync` 只有 gate 允许时可选 canonical owner。canonical job started/finalized proof accepted 后抑制 exact legacy fresh duplicate；canonical start 前 blocked 或 peer-data 写入前失败可安全 fallback legacy；security failure 与 conflict 不允许 fallback bypass/overwrite；legacy job 已运行时 canonical 不开 duplicate。

本轮仍没有 paired iPhone/Mac real-device evidence。当前完成度是源码与 targeted tests 证明状态真相、retry/drain/ownership policy 和 diagnostics redaction；true completion 仍需真机中断上传、app restart、existing-job resume、confirmedBytes、finalize proof、metadataOnly not audio、peerUnknown deferred、different hash/size conflict 和 view refresh no-job 的成对验证。

## 2026-06-11 Canonical v8.49 / P1-2 Audio Upload Commit Executor

v8.49 / P1-2 补强 canonical audio upload commit executor 的执行层正确性。源码盘点显示，仓库中已存在 `CanonicalAudioUploadCommitExecutor` 等价类型（`CanonicalAudioUploadRuntimeExecutor` typealias）和 v8.41 之后的真实 resumable commit runtime；本轮以当前源码为准，补齐 commit-facing result/postcondition/blocker 类型、v8.49 diagnostics、iPhone/Mac targeted tests 和文档边界，而不是重写连接层。

canonical audio upload 仍默认/release disabled。只有 explicit DEBUG/internal owner-approved runtime config 或 test transport 才能让 canonical upload owner 执行；任一 blocker、未授权配置、verification failure 或安全失败都会保留 legacy fallback。`diagnosticsOnly` 与 `noCommit` 只评估 would-upload，不创建 job、不发网络、不写对端。

真实传输继续复用既有安全链路：iPhone 通过 `RecordingUploadClient` / `SecureMacUploadClient` 的 resumable start/status/chunk/finalize；Mac 继续由 `SecureLocalHTTPSServer` existing handlers、`RequestVerifier`、`MacRecordingFileStore` 处理。没有新增 upload route，没有新增 abort route，没有改变 route contract，也没有绕过 TLS pinning、HMAC、nonce、body hash 或 request verification。大音频按 bounded chunk streaming 读取，不一次性读完整文件。

resumable session 保持 start/status/chunk/resume/finalize 语义：confirmedBytes 单调、offset deterministic、duplicate chunk 在同 offset/length/hash 时 idempotent、wrong offset 走 status/resume 或 fail-safe retry。finalize 必须证明 Mac success、byteSize 匹配，且 expected hash 可用时 hash 匹配；只有 finalize proof 后才 mark uploaded、清 retry job、允许 duplicate legacy suppression。hash/size mismatch、existing different audio、peer different hash/size 均 conflict/no-overwrite，不 fallback 成覆盖上传。

候选集成继续依赖 v8.48 existence truth：local audio + peer metadataOnly/receiveRecordOnly/studyItemOnly without audio 可成为 upload candidate；same hash+same byteSize 才 no-op；peerUnknown deferred；local audio missing blocked；tombstoned parent blocked；metadataOnly、receiveRecordOnly、completed ledger alone 都不是 `audioAvailable` 或 audio uploaded proof。view refresh 不创建 fresh upload job；retry drainer 只处理 existing eligible canonical retry。

真实 completion 仍缺 paired-device evidence。本轮已通过 simulator/macOS build 与 targeted tests，但没有运行 iPhone/Mac 真机长录音或新录音流程；不能声称 release/default canonical 或真机完成。

## 2026-06-11 Canonical v8.48 / P1-1 Manifest Recordings Apply Consumption

v8.48 / P1-1 修执行层正确性的第一个缺口：Mac server apply path 现在在默认安全路径下消费 incoming `manifest.recordings`，并通过既有 canonical recording existence ledger 创建或更新 metadata-only recording existence record。旧 manifest 没有 `recordings` 时仍 decode 为 empty 且行为不变。

metadata-only existence record 只证明“对端知道该 recording object 存在”，不写 audio bytes、不创建 fake audio file、不写 legacy `receive.json`、不标记 upload completed，也不把 metadataOnly 当 `audioAvailable`。Mac inventory 会合并 canonical ledger，把该 recording 暴露为 exists 且 `audioAvailable=false`；无真实 audio file 时不报告 audio path/contentHash/byteSize 为本地音频证明。same hash+size 仍是唯一 audio no-op；different hash/size 仍 conflict；peerUnknown 继续 deferred；completed ledger alone 不是 audio proof。

iPhone 侧继续使用现有 upload evaluator / `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` 作为执行路径。local audio exists + peer metadataOnly/receiveRecordOnly/studyItemOnly 会产生 upload candidate；view refresh 不创建 upload job；retry drainer 只重放已有 eligible retry，不创建 unrelated fresh job。本轮不实现 canonical audio upload commit executor；v8.49 / P1-2 才处理 canonical audio commit。

本轮不改变 route/security/read path/master switch 语义：没有新增 route，没有修改 upload route，没有绕过 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`，没有删除或禁用 legacy fallback。真实完成仍需要 paired-device 新录音测试：iPhone 发出 `manifest.recordings`、Mac 写 metadata-only existence、Mac inventory 暴露 `audioAvailable=false`、iPhone 看到 peer metadataOnly 并通过 existing legacy upload path 产生 candidate，随后确认音频是否经 legacy uploader 到达。

## 2026-06-11 Canonical v8.46 Sync Kernel Completion

v8.46 继续按 completion 指令补齐 canonical sync kernel 的剩余代码缺口，但仍不改变 release/default 行为。默认与 release 仍保持 `oldKernel`；legacy planner/store/route/read/write/apply/upload/fallback 全部保留；未执行 commit、push、PR 或 legacy retirement。

iPhone inventory runtime 已把本地 inventory 输入收集与 manifest 构建移到 detached utility background path，使用 URL/file IO 读取录音 metadata、学习库 metadata、tombstone、pending upload 与 manifest recording 等事实，避免在 inventory hash/scan 路径调用 MainActor-isolated store API。`CanonicalInventoryRuntimeReport` 新增真实诊断字段 `mainActorHashAttemptCount`、`mainActorScanAttemptCount`、`metadataLoadDurationMs`；iPhone 正常 background path 记录 attempt/block 为 0，不再发出 fake `count=0` telemetry。同一 `syncRunID`/node/source 的 duplicate build 通过 runtime build cache 复用，第二次同 tick 构建报告 `reusedWithinTick=true` 与 `duplicateBuildCount=1`。

Mac `StudyLibraryStore.applySyncManifest` 现在可以在显式配置 `CanonicalExistenceApplyRuntimeConfiguration` 且注入 `MacCanonicalRecordingExistenceApplyPort` 时消费 `manifest.recordings`，通过 `CanonicalRecordingManifestApplyBridge` 写入 metadata-only canonical existence ledger。默认 store 构造仍 disabled/nil，不写 canonical ledger；显式 apply 不写 audio、不写 legacy `receive.json`、不创建 upload completed proof，metadata-only 记录保持 `audioAvailable=false`。

Mac inventory 路径删除了 hardcoded fake zero main-actor telemetry；当前 Mac `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 仍是 `@MainActor`，因此真实报告 `mainActorHashAttemptCount=1`、`mainActorScanAttemptCount=1` 且 blocker count 为 1。这是 v8.46 的剩余 blocker，不得报告为已完成 off-main Mac inventory。

本轮新增/更新测试覆盖 iPhone inventory telemetry/reuse、Mac manifest recordings explicit/default apply、completion scorecard targeted tests。没有 paired iPhone/Mac 真机证据；本地 simulator/macOS tests 与 builds 不能替代 real-device evidence。

## 2026-06-08 Canonical Sync Kernel Finalization

本轮按最新任务完成同步链路 code-complete 收尾：read runtime 已实际接入 iPhone/Mac `StudyLibraryStore` effective read path 和主要 UI/read adapter；audio upload canonical commit executor 已由 `RecordingUploadCoordinator` 在主开关允许时接管真实 resumable upload owner，并复用现有 secure upload transport/routes；master switch 继续保持 default/release `oldKernel`，`canonicalFullSync` 仍要求 DEBUG/internal、owner approval、manual confirmation、legacy fallback 和 switch-back proof。

新增/扩展的完成证明包括 `CanonicalSwitchBackRealisticRootHarness`、`CanonicalKernelSwitchBackProof`、expanded `CanonicalSyncKernelCompletionDomainReadiness`、`unsafe` status、realistic-root manual gate readiness、iPhone/Mac read Store tests、iPhone/Mac realistic-root switch-back tests。runbook 已补 `ExistingDifferentAudioBlocked` 和 security route failure stop condition。

当前真实状态：代码和本地 builds 已达到可进入真机 manual switch trial 的候选状态，但本工作区没有运行 paired iPhone/Mac 真机流程，没有产生 real-device evidence。不得把 synthetic/unit/test-cloned-root evidence 报告为真机证据。release/default 仍是 `oldKernel`；legacy fallback 和 legacy path 仍保留；未执行 legacy retirement。

文档冲突记录：下方 2026-06-07 v8.45 段落写的是“本轮不新增 runtime 功能，不改默认 app 接线”，这是上一轮 gate-only 状态；本轮源码以 2026-06-08 最新任务为准，已新增 read/audio owner 接线，但仍不改变 release/default 和 legacy safety 边界。

## 2026-06-07 Canonical v8.45 Sync Kernel Completion Gate and Manual Switch Runbook

v8.45 把 v8.37-v8.44 的同步新内核收束成 completion gate、domain scorecard、redacted evidence package、manual switch gate 和真机手动开关 runbook。本轮不新增 runtime 功能，不改默认 app 接线，不删除 legacy path，不执行 legacy retirement。

共享层新增 `CanonicalSyncKernelCompletionScorecard`、`CanonicalSyncKernelCompletionStatus`、`CanonicalSyncKernelCompletionBlocker`、`CanonicalSyncKernelDomainReadyToRetireReport`、`CanonicalSyncKernelEvidencePackage`、`CanonicalSyncKernelEvidenceExporter` 和 `CanonicalSyncKernelManualSwitchGate`。Scorecard 覆盖 inventory runtime、diff/LWW runtime、existence truth、non-audio apply runtime、audio upload runtime、read runtime、master switch、legacy compatibility proof、switch-back proof、diagnostics redaction 和 real-device evidence。代码完成但缺真机日志时状态固定为 `codeCompleteNeedsDeviceEvidence`。

Domain ready-to-retire report 覆盖 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload` 和 `recordingExistence/sync engine`，只报告 write executor、read cutover、canonical runtime owner、legacy fallback、switch-back、diagnostics、real-device evidence 和 report-only readiness。报告固定不执行退役：`retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`。

Manual switch gate 只允许手动 trial，不允许 release default。Gate 要求 scorecard code complete、compatibility proof、switch-back proof、default oldKernel、release oldKernel、diagnostics redacted、legacy fallback、无 unresolved blocker、owner approval 和 manual backup acknowledgement。新增 runbook：`docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`，包含 oldKernel baseline 到 canonicalFullSync、switch-back、paired-device 新录音、metadata-only existence、upload candidate、Mac receive audio、read projection、divergence monitor、stop/rollback 和 evidence package 的 0-18 阶段。

当前真实状态：v8.45 代码和文档可作为手动试跑闸门；仍不能声称 release default canonical、legacy retirement 或真实 paired-device evidence 已完成。主要 blocker 仍是真机 paired-device runbook 证据与人工审核。

## 2026-06-07 Canonical v8.44 Legacy Compatibility and Switch-Back Proof

v8.44 新增 legacy compatibility proof 层，目标是证明手动切到 `canonicalFullSync` 写入后，再切回 `oldKernel` 仍能用旧内核读写同一份数据，不需要 schema migration、转换、重写、删除或手动清理。本轮不新增 canonical 业务功能，不改默认 app 接线，不删除 legacy path。

共享层新增 `CanonicalLegacyCompatibilityMatrix`、`CanonicalLegacyCompatibilityDomain`、`CanonicalLegacyCompatibilityResult`、`CanonicalLegacyCompatibilityBlocker` 和内存 `CanonicalLegacySwitchBackHarness`。矩阵覆盖 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`recordingExistence`、`audioUpload`、`readRuntime` 七个域。每个域必须同时证明 canonical write format legacy-readable、legacy write format canonical-readable、switch-back no migration、无 canonical-only required field、unknown fields ignored/backward compatible、rollback available、diagnostics redacted。

Switch-back harness 使用 legacy-v1 必需字段模拟双向读写：canonical 写入只能附加 legacy 可忽略字段，legacy 修改可以丢弃 unknown canonical 字段但仍保持 canonical 可读；diagnostics 写入独立 redacted 日志，不改变数据格式 fingerprint。Crash/restart 模拟覆盖 before checkpoint、after checkpoint before write、after write before postcondition、after postcondition before duplicate suppression，以及 oldKernel/canonicalFullSync 两种 restart mode；要求 no data loss、old kernel can read、incomplete state blocked or recovered safely、no physical delete。

双端新增 `CanonicalLegacyCompatibilityTests`，覆盖 matrix、roundtrip、partial canonical write rollback、diagnostics no format mutation、oldKernel after canonicalFullSync no crash、crash/restart safety 和完整 switch-back old -> canonical 比较。当前 blockers to main switch 仍是需要真实 paired-device full-sync 诊断和人工确认；legacy deletion 仍未发生，也不允许在本阶段发生。

## 2026-06-07 Canonical v8.43 Unified Manual Kernel Switch

v8.43 新增统一手动主开关，把此前分散的 canonical runtime/debug 配置收敛到 `CanonicalKernelSwitchConfiguration`。默认和 release 行为仍为 `oldKernel`，所有 canonical owner disabled；该开关是行为 owner 开关，不是数据格式开关，切回旧内核不需要数据转换。

共享层新增 `CanonicalKernelSwitchMode`、`CanonicalKernelSwitchPolicy`、`CanonicalKernelSwitchResult`、`CanonicalKernelSwitchBlocker`、`CanonicalKernelSwitchReversibilityGate` 和 `CanonicalKernelSwitchReversibilityProof`。Reversibility gate 必须证明 legacy read/write path 仍存在、canonical writes 仍 legacy-readable 或双写兼容、切回旧内核不需要 migration、没有 canonical-only required field、没有 physical move/delete、诊断 redacted、canonical owner active 时 shadow compare 仍可保留。

主开关现在适配出 v8.37 inventory、v8.38 sync runtime、v8.40 apply runtime、v8.39 existence apply、v8.41 audio upload runtime、v8.42 read runtime、libraryMetadata debug pilot 和 migration matrix policy 摘要。invalid mixed advanced override 会进入 `blocked`，不会让细开关与主开关矛盾。

| Mode | Owner state | Effective mapping |
| --- | --- | --- |
| `oldKernel` | `oldKernel` | 所有 canonical owner disabled；legacy read/write/apply/upload owner |
| `diagnosticsOnly` | `canonicalNoWrite` | inventory diagnostics + sync/apply/existence/audio diagnostics；read disabled；libraryMetadata diagnostics |
| `canonicalShadow` | `shadow` | canonical plan/apply/existence/audio noCommit；read parallel compare；legacy execution/read owner |
| `canonicalDecisionOnly` | `canonicalNoWrite` | sync primary decision with legacy fallback；apply/read/upload disabled |
| `canonicalApplyNoAudio` | `canonicalReadWrite` | sync primary + non-audio apply/existence production-root with legacy fallback；audio/read legacy |
| `canonicalFullSync` | `canonicalReadWrite` | sync primary + non-audio apply/existence + audio upload + guarded read, all with fallback; DEBUG/internal + confirmation only |
| `blocked` | `blocked` | invalid/release/full-sync/no fallback/no reversibility/contradictory override blocks all canonical configs |

iPhone Settings 与 Mac Settings 在 `DEBUG` 下新增 `Debug · 同步内核`；Release 隐藏。切换到 `canonicalFullSync` 需要二次确认；切回 `oldKernel` 立即清除确认并发出配置变更通知。既有 `Debug · 学习库迁移试点` 保留，但标注为高级专项开关。

iPhone `MacConnectionView`、`StudyLibrarySyncCoordinator`、`LocalNetworkSyncAppService` 和 `LocalNetworkSyncEngine` 已从主开关解析 sync/apply effective config；engine 每次 tick 前刷新。Mac `RokuricsMacApp`、`SecureReceiverService` 和 `SecureLocalHTTPSServer` 已接收 sync/apply/existence effective config；receiver 监听主开关通知并在 HTTPS server 已启动时重建 server 实例。双端 read adapter 新增从主开关构造的 factory。

## 2026-06-07 Canonical v8.42 Read Runtime v1

v8.42 adds a default-off canonical read runtime so Store/UI-facing read callers can be routed through a single adapter under explicit debug/internal configuration. Default and release behavior remains legacy read path. This is not a read cutover, not legacy retirement, and not a sync/apply/upload trigger.

Shared SyncCore now includes `CanonicalReadRuntimeConfiguration`, `CanonicalReadRuntimeMode`, `CanonicalReadRuntimePolicy`, `CanonicalReadRuntimeResult`, `CanonicalReadSnapshot` and per-domain projections for recording metadata, library metadata, generated artifact metadata/availability, tombstone/conflict display state, audio existence/upload status and sync engine summary. Modes are `disabled`, `parallelCompare`, `canonicalReadCandidate`, `guardedCanonicalReadWithLegacyFallback` and `blocked`; `disabled` is the default and returns legacy. `parallelCompare` returns legacy while comparing canonical, and `canonicalReadCandidate` builds canonical without serving it.

`guardedCanonicalReadWithLegacyFallback` can serve canonical output only for explicit debug/internal owner-approved configuration with v8.37 inventory snapshot evidence, v8.38 plan authority evidence, v8.39 existence truth evidence, v8.40 non-audio apply evidence, v8.41 audio/upload-status evidence, divergence count zero, legacy fallback available, no conflicting domains, non-release/default policy and manual owner approval. Any blocker falls back to legacy. Canonical-vs-legacy comparison still runs while canonical is served.

Unified read diffs are modeled by `CanonicalReadRuntimeDiff`, `CanonicalReadRuntimeDivergence` and `CanonicalReadRuntimeEquivalenceReport`. Divergences include missing object, metadata mismatch, title/tags/folder mismatch, artifact availability mismatch, tombstone/conflict mismatch, audio availability mismatch, upload status mismatch, unsupported object and path/content leak risk. Any divergence blocks guarded read unless an explicit test-only policy allows divergent guarded read.

iPhone and Mac now have read adapters (`IPhoneCanonicalReadRuntimeAdapter`, `MacCanonicalReadRuntimeAdapter`) around existing manifest/inventory read boundaries. They build sanitized canonical read snapshots from existing in-memory read inputs only. Reads do not mutate store, do not create upload jobs, do not move resources, do not write production data, do not mutate inventory responses or `receive.json`, do not touch audio inbox, and do not trigger transcription/note generation.

New diagnostics cover `canonicalReadRuntimeModeEvaluated`, `canonicalReadRuntimeServedCanonical`, `canonicalReadRuntimeServedLegacyFallback`, `canonicalReadRuntimeDiffEquivalent`, `canonicalReadRuntimeDiffDivergent`, `canonicalReadRuntimeBlocked` and `canonicalReadRuntimeReportBuilt`. Diagnostics and read projections are redacted: no absolute paths, full hashes, secrets, request/response bodies, full transcript/note/summary/provider responses or generated content are emitted.

## 2026-06-07 Canonical v8.41 Audio Upload Runtime Commit v1

v8.41 adds the first canonical audio upload runtime commit executor, but it is still default/release disabled. The production owner remains the legacy `RecordingUploadCoordinator` unless an explicit debug/internal/test configuration selects the canonical runtime. Legacy fallback is retained and is the default result for disabled or safely blocked modes.

Shared SyncCore now includes `CanonicalAudioUploadRuntimeConfiguration`, runtime modes/policy/result, `CanonicalAudioUploadRuntimeExecutor`, resumable session/chunk/offset/finalize/abort/retry models, `CanonicalAudioUploadJobStore`, `CanonicalAudioUploadRetryPolicy` and `CanonicalAudioUploadResumeToken`. Modes are `disabled`, `diagnosticsOnly`, `noCommit`, `testTransportUpload`, `canonicalUploadWithLegacyFallback` and `blocked`; `disabled` is the default. `diagnosticsOnly` and `noCommit` create no upload job and perform no network request. `testTransportUpload` is for fake/test transport. `canonicalUploadWithLegacyFallback` is debug/internal only and requires explicit owner approval plus a non-dry-run existing secure upload port.

The runtime uses existing resumable secure upload operations only: start, status, chunk and finalize. It does not add an abort route; abort is local session/job cleanup before finalize. The iPhone adapter wraps the existing `RecordingUploadClient` / `SecureMacUploadClient` path, so TLS certificate pinning, HMAC, nonce, body hash and existing request construction remain in force. Mac receive behavior remains the existing `SecureLocalHTTPSServer` / `RequestVerifier` / `MacRecordingFileStore` path; final audio is stored only after verified finalize.

The new session state machine tracks idle, starting, started, chunking, interrupted, resuming, finalizing, finalized, failed, aborted, conflict and blocked. Chunk offsets are deterministic, confirmed bytes are monotonic, duplicate chunks with the same offset/length/hash are idempotent in the test/runtime adapter, wrong offsets schedule retry/failure, and finalize requires byte size plus SHA256 proof. A finalize hash/size mismatch becomes conflict/failure and does not mark audio uploaded. The runtime streams chunks from a `CanonicalAudioUploadByteSource` and must not read a full large audio file into memory.

Upload-candidate decisions preserve the v8.39 existence truth: local audio plus peer metadataOnly/receiveRecordOnly/studyItemOnly may become an upload candidate; local audio plus peer same hash+size is the only no-op; peerUnknown is deferred; different hash/size is conflict; metadataOnly or completed ledger alone is rejected as audio no-op. View refresh cannot create a fresh job. Retry drainer can only replay an existing eligible retry record and cannot create an unrelated fresh job.

Retry persistence stores redacted job records with objectID, sessionID, confirmed offset, chunk size, content hash prefix, byte size and state. It does not store absolute paths or full hashes. Resume after restart refreshes existing session status through the existing route, then continues from the confirmed offset. Terminal conflict records do not loop forever. Upload ledger completion and iPhone uploaded state are written only after Mac finalize proof is accepted.

New diagnostics cover mode evaluation, candidate selection, start/chunk/confirm/resume/finalize, retry scheduling, legacy fallback, peerUnknown defer, conflict blocking, existing different audio blocking and completed-ledger-as-no-op rejection. Diagnostics are redacted: no full hash, absolute path, secret, fingerprint, request/response body, transcript/note/summary/provider output or audio bytes.

Current validation proves the new shared/iPhone/Mac unit coverage and selected v8.38/v8.39 regressions. A long-recording paired-device upload was not run in this workspace, so true end-to-end validation still requires the documented long-recording real-device test.

## 2026-06-07 Canonical v8.40 Apply Runtime Owner v1

v8.40 turns `CanonicalApplyPlan` from a bridge hint into an executable runtime owner for selected non-audio domains under explicit configuration. Default and release behavior is still legacy apply owner; legacy fallback is retained; read path, UI, upload runtime, route schema and security boundaries remain unchanged.

Shared SyncCore now includes `CanonicalApplyRuntimeOwner`, configuration/mode/policy/result/report/blocker types, `CanonicalApplyRuntimeGate`, and `CanonicalApplyRuntimeExecutorRegistry`. Supported modes are `disabled`, `diagnosticsOnly`, `noCommit`, `testRootApply`, `productionRootApplyWithLegacyFallback` and `blocked`, with `disabled` as the default. The gate requires v8.38 plan authority or noCommit, a valid v8.37 inventory snapshot, explicit enabled domains, matching executor, root-bound apply capability for commit modes, rollback/postcondition capability, legacy fallback, redacted diagnostics, `runtimeSwitch=false`, legacy read path and no forbidden operation.

The registry maps `recordingMetadata`, `libraryMetadata`, `generatedArtifacts`, `tombstoneConflict` and `recordingExistence` onto existing cutover/bridge executors. `audioUpload` is explicitly unsupported in v8.40 and must block. Execution is sequential per action: precondition, rollback checkpoint, commit, postcondition and diagnostics. First failure stops later actions; rollback failure is fatal; duplicate legacy suppression is success-only and exact-match only.

iPhone `StudyLibrarySyncCoordinator.performTick` now evaluates v8.40 after the v8.38 canonical runtime plan and before legacy apply execution. The default config is disabled. Explicit debug/internal test-root or production-root-with-legacy-fallback modes can execute enabled non-audio domains through the registry, then suppress only matching legacy duplicates that canonical successfully committed. The apply runtime does not create upload jobs, does not change retry draining, does not write audio bytes and does not switch UI/read path.

Mac `SecureReceiverService` and `SecureLocalHTTPSServer` carry the same default-disabled config. The Mac route path remains synchronous and unchanged; v8.40 uses the shared gate/registry boundary around the existing v8.39 recording existence metadata-only bridge, then delegates to the existing ledger bridge when allowed. It does not add routes, change route schemas, bypass `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash, mutate `receive.json` outside documented legacy behavior or the v8.39 canonical ledger, write audio bytes, or trigger transcription/note generation.

New diagnostics cover apply runtime mode evaluation, gate allowed/blocked, action started/completed/failed, rollback started/completed/failed, legacy fallback, duplicate suppression, audio action blocked and report built. Diagnostics are redacted: no full metadata JSON, full hash, absolute path, secret, fingerprint, request/response body, transcript/note/summary/provider output or standalone note content. True validation still requires paired-device apply diagnostics; current build and simulator/macOS tests do not prove real-device end-to-end apply.

## 2026-06-07 Canonical v8.39 Existence Truth + Apply Bridge Runtime v1

v8.39 建立 recording object 的 canonical existence truth，并把 `manifest.recordings` 接到 Mac 侧 metadata-only existence apply bridge。当前实现保持默认/release disabled，legacy diff/apply/upload/read path 仍是生产 owner；本轮只是补上学习库 manifest 录音存在性与 Mac peer inventory 之间的闭环。

共享层新增/扩展 `CanonicalRecordingExistenceTruth`、existence state/source/decision/blocker 与 `CanonicalExistenceApplyRuntimeConfiguration`。规则明确：study item only、metadataOnly、receiveRecordOnly 和 completed ledger 都不是 audio uploaded；只有相同 hash + 相同 byteSize 才是 audio no-op；peerUnknown 继续 deferred；different hash/size 是 conflict；tombstoned parent 阻断 apply/upload candidate。

`StudyLibrarySyncManifest` 现在包含兼容旧 checksum 的 `recordings` 数组。iPhone 与 Mac manifest 生成会带出 recording existence facts；Mac `SecureLocalHTTPSServer` 在 apply manifest 后可通过 `CanonicalRecordingManifestApplyBridge` 消费这些 facts。由于现有 inbox `receive.json` 会进入 Mac read path，本轮采用单独 canonical metadata-only existence ledger：`sync/canonical-recording-existence/records/`，不写 `audio/inbox`、不写 audio bytes、不创建 fake audio、不标记 upload completed。

Mac inventory 在显式非 disabled 配置下把 canonical existence ledger 合并为 peer recording exists，但 `audioAvailable=false`，且没有 proven audio 时不报告 hash、byteSize 或 audio path。existing same placeholder no-op；existing same audio hash+size no-op；existing different audio conflict/blocker；receive.json 行为保持 legacy，未切 read path。

iPhone sync tick 增加 v8.39 existence truth diagnostics，并把既有 `RecordingAudioUploadDecisionEvaluator` 的结果映射到 `canonicalExistencePeerMetadataOnlyUploadCandidate`、`canonicalExistencePeerAbsentMetadataBridgeRequired`、`canonicalExistencePeerUnknownDeferred`、`canonicalExistenceAudioSameNoOp` 和 `canonicalExistenceAudioConflict`。真实音频上传仍走 legacy `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` secure upload path，不改 route/security。

新增测试覆盖 shared existence truth、Mac metadata-only ledger apply/rollback/inventory merge 与 diagnostics redaction。代码层已能证明 bridge 不写音频、不把 metadataOnly 当 audioAvailable、不把 completed ledger 单独当 no-op；但当前没有本轮真机新录音 iPhone->Mac evidence，因此不能声称真实端到端修复已经完成。

## 2026-06-11 Canonical v8.47 P0-2 Persistent Checksum Cache Real Hit

v8.47 / P0-2 只落在 inventory/canonical snapshot 性能发动机：持久化 checksum cache、真实 cache hit、真实 telemetry 和性能诊断。默认 sync decision、apply、upload、read path、主开关语义、`/sync/inventory` route/security、legacy fallback 均保持不变；本轮不进入 P1，不修 `manifest.recordings` apply，不写 audio upload commit executor，不新增 migration domain/stage、canary/evidence/landing/retirement 类型或 route。

`CanonicalChecksumCacheStore` 的 key 至少覆盖 safe logical token、byte size、mtime/contentVersion、hash algorithm、schema version、node role/platform role 和可选 store namespace。record 内部保存完整 hash，但 diagnostics/export 只允许 hash prefix；record 还包含 byte size、mtime/contentVersion、computedAt、schemaVersion、source role 和 validation state。cache hit 直接复用内部 hash，不调用 hash provider；logical token 变化是 miss，size/mtime/contentVersion/algorithm/schema 变化是 stale，miss/stale 都在 cache actor + detached hash 路径重算并 atomic persist。cache root/record 损坏 fail closed：忽略损坏 record 或重建缓存，继续 sync，不能把 `hashUnavailable` 当 equality proof。

cache 文件位于 app data/cache 根下的 runtime cache 文件，不放在用户可见学习库内容目录；维护只重写/修剪 cache record，不删除用户数据。schemaVersion bump 会让旧缓存 ignored/stale；store 支持 `maxRecords`/`maxBytes`，按最旧 `computedAt` 修剪，并记录 redacted prune diagnostics。测试支持 fake hash provider count、fake clock、fake metadata provider、fake persistent cache root，以及用同一 root 重建 store 模拟 app restart。

真实 telemetry 新增/补齐 `inventoryBuildDurationMs`、metadata/jobs/file scan/hash/cache load/cache write/cache prune durations、cache hit/miss/stale/error、hash computed/failed/unavailable、duplicate build、snapshot reuse、mainActor hash/scan/metadata/jobs attempts 和 redaction violation count。所有 duration 来自真实 clock 或测试注入 fake clock，count 来自实际路径/检测器；允许正常路径为 0，但禁止写硬编码 fake success 事件，例如 `MainActorHashBlocked count=0` 或 `MainActorScanBlocked count=0`。diagnostics 必须包含 syncRunID/nodeRole，且 bounded/redacted，不输出绝对路径、完整 hash、secret、完整 fingerprint、完整 metadata JSON 或内容。

iPhone `performTick` 使用 cache-backed runtime snapshot，并在同一 `syncRunID` 复用 snapshot，cache hit 会真实跳过 hash；end-of-tick success/shadow/readiness 复用 snapshot 或 cache-backed facts，不创建 upload job，不改变 retry drainer/UI/read path/sync plan。Mac `/sync/inventory` response schema 与 RequestVerifier/TLS/HMAC/pinning/nonce/body hash/route allowlist 保持不变；Mac inventory 现在使用同一持久化 checksum cache 产出 audio/artifact facts，但 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 仍是 `@MainActor` 源码事实，main-actor attempt diagnostics 必须如实报告，不能把 0 当通过信号。

完成状态说明：仓库单元测试可证明跨 tick/root 重建的 cache hit、hit 跳过 fake hash provider、mtime/size/schema stale、corrupt cache fail closed、atomic temp file 不破坏命中、prune 不删非 cache 文件和 fake clock telemetry。真实完成仍需要真机前后对比 diagnostics 与体感 latency 检查；没有真机日志时只能报告 `not run; no real-device evidence produced.`

## 2026-06-07 Canonical v8.38 Sync Decision Runtime v1

v8.38 把 canonical planner 从 shadow/bridge 进一步封装成受控同步决策运行时候选，但默认与 release 行为仍是 legacy owner。新增 `CanonicalSyncRuntimeConfiguration`、runtime mode/policy/result、`CanonicalSyncPlanAuthorityGate` 和 `CanonicalSyncRuntimeDuplicateExecutionGuard`；默认 mode 为 `disabled`，`runtimeSwitchEnabled` 仍为 false，read path 仍为 legacy。

运行时 mode 分为 `disabled`、`diagnosticsOnly`、`canonicalPlanNoCommit`、`canonicalPlanPrimaryWithLegacyFallback` 和 `blocked`。只有 explicit debug/internal policy、owner approval、非 release/default、legacy fallback 可用、diagnostics redacted、v8.37 inventory snapshot 可用、local/peer canonical manifest 有效、metadataHash schema 匹配、canonical modifiedAt 语义可用、unsupported/fallbackRequired/conflict/peerUnknown 均为 0 时，`canonicalPlanPrimaryWithLegacyFallback` 才能把 canonical diff/LWW 用作本 tick 的受控 decision owner。任一 blocker 都 fallback legacy。

本轮统一 recording metadata canonical hash 口径为 `canonical-recording-business-metadata-v1`：hash 只覆盖稳定业务字段，modifiedAt/LWW 只使用业务修改时间，不使用 receivedAt/observedAt/upload progress/处理状态。相同 canonical metadataHash 会被视为 metadata no-op；即使 legacy `RecordingMetadata` 与 `StudyItemMetadata` hash 不同，canonical primary metadata scope 下也不会因此重复 metadata transfer。iPhone 旧模型缺少严格 business modifiedAt 时只走已记录 fallback/warning，默认仍阻断 primary，除非 explicit internal policy 允许 documented fallback。

iPhone `StudyLibrarySyncCoordinator.performTick` 继续构建 legacy plan 作为 fallback 和 diagnostics，随后构建 canonical plan、apply plan、library plan 与 v8.37 snapshot 并评估 authority gate。`diagnosticsOnly` 与 `canonicalPlanNoCommit` 不改变执行 owner；primary allowed 时只接管 metadata/library/recording existence scope 的决策，并用 duplicate guard 阻止 exact same object/action/scope 的 legacy duplicate。它不接管大文件 audio upload runtime，不创建新的 upload job，不执行 production apply，不写 production root，不切 UI/read path。

Mac inventory/server 侧只在现有 inventory runtime 后评估 canonical runtime readiness/plan diagnostics。`/sync/inventory` response schema、routes、RequestVerifier、TLS/HMAC/pinning/nonce/body hash、`receive.json`、audio inbox、pending sync 和 transcription/note generation 均未改变。真实 inventory request 没有 peer snapshot 时 primary 必须 blocked/fallback/report-only。

新增 redacted diagnostics 包括 `canonicalSyncRuntimeModeEvaluated`、`canonicalSyncRuntimeAuthorityGateAllowed/Blocked`、`canonicalSyncRuntimePlanUsed/NoCommit/Fallback/Blocked`、`canonicalSyncRuntimeLegacyHashMismatchIgnored`、`canonicalSyncRuntimeUnsupportedObjectBlocked`、`canonicalSyncRuntimeConflictBlocked`、`canonicalSyncRuntimePeerSnapshotUnavailable`、`canonicalSyncRuntimeDuplicateLegacySuppressed` 和 `canonicalSyncRuntimeDuplicateExecutionPrevented`。输出只允许 syncRunID、mode、count、objectID/action/scope 和 hash prefix，不包含完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint 或 request/response body。v8.39 前 apply/existence bridge 仍未执行 production apply。

## 2026-06-07 Canonical v8.37 Inventory Runtime v1

v8.37 开始构建 inventory runtime v1，但只处理运行时卡顿和重复构建问题，不接管 diff/apply owner。默认/release 行为仍是 legacy owner，`/sync/inventory` 外部 wire schema 不变，legacy inventory builder/fallback 保留，upload job 创建、retry drainer、Mac pending sync、read path、UI、routes 和 RequestVerifier/TLS/HMAC/nonce/body hash 均不改变。

共享层新增 `CanonicalInventoryRuntimeSnapshot`、runtime builder/reuse helper、persistent `CanonicalChecksumCacheStore` 与 redacted report/exporter。checksum cache key 覆盖 logical token、byte size、mtime、hash algorithm、schema version 和 node role；hit 不重新 hash，size/mtime/algorithm/schema 变化视为 stale 并后台重算，cache 损坏 fail closed 为重新 hash 或 hashUnavailable，不把 hashUnavailable 当 equality proof。

iPhone `performTick` 现在用 async runtime snapshot 生成 legacy-compatible local inventory；同一个 `syncRunID` 内末尾成功记录复用首次 snapshot，避免 refreshed inventory 再 hash/scan。Mac `/sync/inventory` 以及 artifact lookup/status 中需要本地 inventory 的路径复用 cache-backed checksum facts；源码上 Mac inventory builder 仍是 `@MainActor`，因此只能如实诊断剩余 blocker，不能宣称已完全 off-main。

新增 diagnostics 包括 `canonicalInventoryRuntimeSnapshotBuilt/Reused/DuplicateBuildSuppressed/DuplicateBuildDetected`、`canonicalInventoryRuntimeCacheHit/Miss/Stale`、`canonicalInventoryRuntimeHashStarted/Completed/Failed`、`canonicalInventoryRuntimeMainActorHashBlocked` 和 `canonicalInventoryRuntimeMainActorScanBlocked`。v8.37 原始预期是正常路径 blocker count 为 0；v8.46 后该说法只适用于 iPhone background inventory，Mac inventory 会真实报告剩余 `@MainActor` blocker。输出只包含 redacted counts/durations，不包含绝对路径、完整 hash、fingerprint、secret、完整 metadata JSON 或内容。真实完成仍需要真机 diagnostics 与体感 UI latency 改善证据；本仓库构建/测试不能替代真机 evidence。

## 2026-06-07 LibraryMetadata Real-Device Pilot Preflight Wiring

本轮只做真机试点前接线：iPhone 与 Mac Settings 在 `DEBUG` 下新增隐藏区 `Debug · 学习库迁移试点`，把本地 UserDefaults 模式映射到既有 `CanonicalLibraryMetadataDebugPilotConfiguration` 与双端 `LibraryMetadataProductionCanaryBootstrap.prepare(...)`。默认仍为 `off`，Release/default 不显示、不启用，app 默认行为保持 legacy。

可选模式为 `off`、`diagnosticsOnly`、`armTestRootN1`、`executeTestRootN1`、`executeProductionRootN1`。`diagnosticsOnly` 是第一步真机检查；`armTestRootN1` 与 `executeTestRootN1` 只使用系统临时目录下的 test root；`executeProductionRootN1` 必须经 UI 二次确认，并且只有该模式可传 `allowProductionRootWrites=true`。本轮不新增 migration domain/stage，不切 read path，不改 StudyLibraryStore/UI 读路径，不删除 legacy，不禁用 legacy fallback，不移动资源，不写 standalone note content，不执行 tombstone/delete。

诊断位置在设置中用相对或 `~` 形式展示：iPhone 为 `Documents/Rokurics/Sync/Diagnostics/connection-diagnostics.jsonl`，Mac 为 `~/Library/Application Support/Rokurics*/Sync/Diagnostics/connection-diagnostics.jsonl` 与 `~/Library/Application Support/Rokurics*/Sync/Diagnostics/canonical-shadow.jsonl`。Mac certificate fingerprint 日志只输出短 prefix，不输出完整 fingerprint。

重要边界：代码接线完成不等于真机验证完成。当前仍没有本轮产生的真机 `connection-diagnostics.jsonl` 或 `canonical-shadow.jsonl`，因此不能声称 diagnosticsOnly、test-root N1 或 production-root N1 已在真机验证完成。

## 2026-06-06 Canonical v8.32 LibraryMetadata N=1 Evidence Audit & N=3 Readiness Gate

v8.32 是证据审计与 readiness gate 轮，不执行新的 production-root write，不执行 N=3/allEligible，不默认启用 canary，不切 read path，不改 UI，不删除 legacy，也不禁用 legacy fallback。本轮只读取或引用 v8.31 N=1 pilot 的 redacted landing/diagnostics/safety/read-side 证据；如果没有真实 v8.31 N=1 evidence，结果必须是 `missingEvidence`，下一步是按 runbook 手动补跑 N=1，而不是进入 v8.33/N=3。

共享层新增 `CanonicalLibraryMetadataN1EvidenceBundle`、evidence source/status/validation/blocker、post-run invariant validator、`CanonicalLibraryMetadataN3ReadinessGate`、redacted exporter/redactor/importer。bundle 只保留 mode/rootMode/activePilot、candidate count/kind、commit/rollback/fallback/duplicate/read-side counts、LandingFreeze、productionRootSafetyProof、otherDomainsStaticOnly、runtimeSwitch、release/default disabled 和 redacted source ID 等摘要；不得包含完整 metadata JSON、standalone note content、transcript/note/summary/provider response、绝对路径、完整 hash、secret、fingerprint 或 request/response body。

N=3 readiness 是 report-only。只有 valid N=1 evidence、commit success 或明确 accepted no-change/no-eligible policy、rollback failure=0、read-side divergence=0、unsafe side effect=0、resource move/content write/tombstone/delete=0、其它 domains staticOnly、runtimeSwitch=false、release/default disabled、legacy fallback available、manual audit required、owner approval required 且 N=3 disabled-by-default 时，才返回 `readyForN3AfterManualAudit`。该状态不执行 N=3，不授权默认启用，也不删除或停用 legacy。

当前仓库未发现可直接采信的真实 v8.31 production-root N=1 evidence 文件；已有 claude report 明确提示真机真跑尚未完成。因此 v8.32 代码和测试固化了缺失证据会阻断 N=3 的行为，并新增 runbook：`docs/Rokurics_LibraryMetadata_Pilot_Evidence_Audit_v8_32.md`。

## 2026-06-06 Canonical v8.31 LibraryMetadata Production-Root N=1 Pilot Enablement

v8.31 在 v8.30 `diagnosticsOnly`、`armN1Canary` 和 testRoot `executeN1Canary` 通过且 owner 明确批准后，允许 `libraryMetadata` 进入一次 explicit debug/internal production-root N=1 pilot。默认、release 和普通 app 构造仍 disabled；`allowProductionRootWrites=true` 只有在 `rootMode=productionRootExplicit`、`mode=executeN1Canary`、owner-approved token、LandingFreeze green、v8.30 证据齐全、read-side divergence=0、rollback evidence 齐全、legacy fallback available、production-bound root evidence 和 injected executor 全部满足时才有效。

共享层新增 `CanonicalLibraryMetadataProductionRootGate`、gate result/blocker、`CanonicalLibraryMetadataProductionRootSafetyProof` 与 production-root 专属 diagnostics。gate 要求候选列表中恰好一个 safe metadata-only candidate；允许范围仍仅为 folder rename/color metadata、study item tags/filing/folder membership metadata、standalone note title/tags/filing metadata。resource move、standalone note content、generated artifact/audio/upload、tombstone/delete/trash/permanent delete/GC、unresolved conflict、N>1、allEligible、non-libraryMetadata active pilot、runtimeSwitch、read path/UI cutover 均 blocked。

iPhone/Mac `ProductionCanaryBootstrap` 现在只在 explicit production-root config、`allowProductionRootWrites=true` 且调用方提供显式 production root URL 时构造 productionRootBound apply port/executor；allow=false、URL 缺失或默认构造不注入。执行仍复用 N1 runner：写前建立 rollback checkpoint，root-bound atomic write，postcondition verification，read-side parallel comparison；成功后只 suppress exact matching legacy `libraryMetadata` duplicate，legacy fallback 保留。precondition/write/postcondition failure 均 rollback/fallback；rollback failure 是 fatal blocker，且不 suppress legacy。

v8.31 不切 read path，不改 UI，不删除 legacy planner/inventory/store/route/write/read/fallback，不改 retry drainer、Mac pending sync、upload routes、RequestVerifier、TLS/HMAC/nonce/body hash、audio 自动下载或资源文件位置。`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 继续 staticOnly/defaultOff，runtimeSwitch 仍 false。本轮新增 runbook：`docs/Rokurics_LibraryMetadata_Pilot_Runbook_v8_31.md`；下一步是人工执行一次并收集 redacted landing report、safety proof、read-side equivalence report 与 freeze guard report 给 Claude 审计，不是扩大代码或切 read/UI。

## 2026-06-06 Canonical v8.30 LibraryMetadata Diagnostics / Arm / Test-Root Pilot Drill

v8.30 不新增迁移域，也不继续推进 `generatedArtifacts`、`tombstoneConflict`、`audioUpload` 或 `recordingMetadata`。本轮只把 `libraryMetadata` debug pilot 调整到可验证状态：`diagnosticsOnly` 可在 app seam 中运行 LandingFreeze 且不选 candidate、不构造 write port、不 commit；`armN1Canary` 可生成 N=1 safe candidate readiness、rollback/read-side/fallback readiness report 且不执行；`executeN1Canary` 仍默认 disabled，只有显式 internal/test config + testRoot apply port 才能提交最多一个 safe metadata-only candidate。

生产根目录继续禁用。v8.30 明确阻断 `productionRootExplicit`，并阻断 `allowProductionRootWrites=true`；双端 `ProductionCanaryBootstrap` 在 production-root 模式下不会构造真实 apply port/executor。release/default 路径仍 disabled，app 入口仍不注入真实 executor，不启用 canary，不切 read path，不改 UI。legacy planner/inventory/store/route/read/write/fallback 全部保留。

`CanonicalMigrationLandingFreeze` 现在除唯一 active pilot=`libraryMetadata`、其它 domain staticOnly、runtimeSwitch=false、release/default=false、read path legacy 外，还会标记默认 production executor/root write、legacy fallback missing、N>1、allEligible、unsafe candidate、resource move、content write、tombstone/delete 等误配置。新增 `CanonicalLibraryMetadataPilotDiagnosticSummary`、`CanonicalLibraryMetadataPilotDiagnosticExporter` 和 redactor，只导出 mode/nodeRole/status/count/bool/enum 等安全摘要，不包含完整 metadata JSON、内容、绝对路径、完整 hash、secret、fingerprint 或 request/response body。

新增 runbook：`docs/Rokurics_LibraryMetadata_Pilot_Runbook_v8_30.md`。下一步 v8.31 只能在 testRoot drill 通过并经 owner 明确批准后，讨论 production-root N=1；不得自动扩大到 N>1/allEligible 或其它域。

## 2026-06-06 Canonical v8.29 LibraryMetadata Real-Device Pilot Landing

本轮把 canonical 迁移焦点收回到 `libraryMetadata`，新增 debug/internal-only real-device N=1 landing pilot。`CanonicalMigrationLandingFreeze` 明确要求唯一 active pilot 为 `libraryMetadata`；`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 和其它 domain 在 v8.29 landing 中必须保持 staticOnly/defaultOff，runtimeSwitch 和 release/default cutover 均为 false。历史 v8.22-v8.28 中的 generatedArtifacts/tombstoneConflict active-pilot 探索状态仍保留在代码和文档中，但 v8.29 landing freeze 不允许本轮使用它们作为 active pilot。

共享层新增 `CanonicalLibraryMetadataDebugPilotConfiguration` / `Mode` / `Policy`、`CanonicalLibraryMetadataDebugPilotBootstrap`、landing report 和 freeze result/violation 类型，并补齐 `canonicalLibraryMetadataLanding*` 与 `canonicalMigrationLandingFreezeViolation` diagnostics。landing wrapper 复用既有 `CanonicalLibraryMetadataProductionCanaryInjection` 和 N1 runner：默认 `.disabled`，无 UI toggle；只有显式 internal/debug config、owner token、rollback/evidence、read-side equivalence、root-bound non-dry-run apply port、local/peer snapshot 和 injected executor 全部满足时，才会选择最多一个 safe metadata-only candidate。

iPhone `StudyLibrarySyncCoordinator` 现在可显式注入 v8.29 debug pilot config 与 `CanonicalLibraryMetadataCutoverExecutor`。默认 app 构造仍 disabled/nil，不创建 apply port，不改变 legacy diff、legacy `applySyncManifest`、UI/read path、upload/retry 或 sync owner。显式 v8.29 config 会在旧 libraryMetadata seam 前独占该 run，避免 double execution；成功后只对 canonical commit success 且 pre/postcondition verified 的 matching libraryMetadata legacy duplicate 做 suppression。

Mac `SecureReceiverService` / `SecureLocalHTTPSServer` 新增同样 default-disabled config/executor pass-through。真实 `/sync/inventory` 仍没有 peer snapshot，因此显式配置时只记录 landing blocked/fallback/report diagnostics，不调用 executor、不改 response、route/security、`receive.json`、audio inbox、pending sync 或 transcription/note generation。Mac 测试可直接调用 shared bootstrap 并注入 `MacLibraryMetadataRealApplyPort(testRootURL:)` 验证 test-root N=1。

允许 candidate 只限 folder rename/color metadata、study item tags/filing/folder membership metadata、standalone note title/tags/filing metadata；resource move、folder hierarchy mutation、standalone note content、generated artifact write、audio/upload、tombstone/delete/trash/permanent delete/GC、parent missing、cycle、objectID instability、unresolved conflict、unsafe path 和 unsupported object/action 均 blocked。read-side 仍为 parallel equivalence evidence，legacy read/UI 保持不变。

新增手动 runbook：`docs/Rokurics_LibraryMetadata_Pilot_Runbook_v8_29.md`。本轮验证新增双端 `CanonicalLibraryMetadataLandingTests`，并通过 iPhone/Mac targeted landing tests。

## 2026-06-05 Canonical v8.28 TombstoneConflict Canary N=1

本轮在 v8.27 `tombstoneConflict` 唯一 active pilot / N=0 guarded seam 之后，新增严格 N=1 canary wrapper。默认仍 disabled，默认 `canaryMaxObjectsPerSyncRun=0`；只有显式 `.canaryCommit`、`domain=tombstoneConflict`、budget 正好 1、`explicitInternalTestConfiguration=true`、`allowsInternalN1Execution=true`、owner-approved token、rollback plan、NoCommit/dry-run/execution-shadow/real-data-shadow/read-side parallel/anti-resurrection evidence、legacy fallback 和 non-dry-run root-bound apply port evidence 同时满足时，才允许选择最多一个 candidate。

共享层新增/扩展 `CanonicalTombstoneConflictCanaryConfiguration`、`CanonicalTombstoneConflictCanaryMode`、`CanonicalTombstoneConflictCanaryPolicy`、`CanonicalTombstoneConflictCanaryCandidateSelector`、candidate safety/blocker、N1 runner、canary result 和 observation report。候选只允许 soft object/library tombstone marker apply/send、conflict record commit、resurrection block record；generated artifact tombstone marker 仅 unsupported/report-only，不执行 apply/download。physical delete、permanent delete、tombstone GC、restore、clear tombstone、ambiguous conflict auto-resolution、stale live resurrection、generated artifact apply/download、audio/full-content action、unsafe path、缺 rollback checkpoint 等均 blocked。

iPhone `StudyLibrarySyncCoordinator` 的 tombstoneConflict seam 现在在显式 N=1 时调用 N1 runner；默认无 executor，仍不会意外执行。测试可注入 fake/test-root executor 验证一次 soft marker/conflict record commit。成功后只 suppress matching tombstoneConflict legacy duplicate；失败、rollback、fatal rollback、no eligible、report-only 或 unsafe candidate 都保留 legacy fallback 且不 suppress。Mac 构造器保留可注入 executor，但 `/sync/inventory` 真实 seam 仍不改变 route/security/response；缺 peer snapshot 时只记录 insufficient peer snapshot / fallback diagnostics。

本轮未切 UI/read path，read-side 仍 parallel diagnostics only；未修改 retry drainer、Mac pending sync、upload routes、RequestVerifier、TLS/HMAC/nonce/body hash、audio upload、generatedArtifacts、recordingMetadata 或 libraryMetadata active pilot。其它 domain 继续 staticOnly/defaultOff，runtimeSwitch 仍 false。v8.29 只能在 v8.28 N=1 observation 人工审计通过后再考虑扩大 tombstoneConflict canary。

## 2026-06-05 Canonical v8.27 TombstoneConflict Active Pilot Guarded Seam N=0

本轮把 `tombstoneConflict` 从 v8.26 next-pilot candidate 提升为唯一 active pilot，但只允许 N=0 guarded commit gate evaluation。`generatedArtifacts` 不再是 active pilot，但其模板、write/read/observation evidence 仍是前置条件；其它 domain 继续 static/default-off，runtimeSwitch 仍为 false。

共享层新增 `CanonicalTombstoneConflictGuardedCommitSeam`、active pilot activation gate、guarded gate/evidence report、no-execution assertion、N1 readiness report 和 v8.27 diagnostics。gate 只接受 `.guardedExecuteCommit` / `.canaryCommit` 的显式评估，且 canary budget 必须为 0；N1、staged/allEligible、runtime switch、缺 owner token、缺 local/peer snapshot、缺 generatedArtifacts/library evidence、缺 rollback/root-bound/legacy fallback/evidence 都必须 blocked。

本轮显式阻断 physical delete、permanent delete、tombstone GC、restore、tombstone clear、stale live resurrection、ambiguous conflict auto-resolution、generated artifact tombstone marker apply 和 unsupported tombstone/conflict action。即使 gate allowed，结果也固定 `willExecuteNow=false`，commit/delete/restore/conflict resolution 全部 skipped，legacy fallback preserved，duplicate suppression not applied。

iPhone `StudyLibrarySyncCoordinator` 新增 default-off v8.27 seam；启用后只记录 diagnostics，不改 legacy/canonical plan、pending count、upload job、retry drainer、UI 或 store。Mac `SecureLocalHTTPSServer` 新增 default-off inventory seam；启用后因缺 peer snapshot 只报告 blocked/readiness，不改 `/sync/inventory` response、`receive.json`、audio inbox、Mac pending sync 或 route/security。

## 2026-06-05 Canonical v8.26 TombstoneConflict Template Alignment & Next Pilot Candidate

本轮把 `tombstoneConflict` 对齐到 `libraryMetadata` / `generatedArtifacts` 已验证过的模板形态，但只登记为下一试点候选，不设为 active pilot，不进入 canary，不改读路径。共享层新增 `CanonicalTombstoneConflictReadProjection`：只从 legacy/canonical snapshot、canonical manifest、apply plan、library plan 或双端 seam 转成 metadata-only tombstone/conflict projection，覆盖 object kind、tombstone state、deleted display state、tombstone timestamp summary、conflict status、active-vs-tombstone state、anti-resurrection status、soft delete marker、hash prefix 和 risk counts；明确排除完整 metadata、完整内容、绝对路径、physical delete target path、完整 hash、request/response body、secret 和用户内容。

新增 read-side parallel diff、`CanonicalTombstoneConflictTemplateReport.currentV826Audit()`、anti-resurrection template gate、observation window/gate 和 report-only retirement candidate gate。anti-resurrection gate 阻断 stale live metadata restore、absence-as-restore、缺 explicit restore signal、generated artifact / library metadata tombstone 下应用、physical/permanent delete、tombstone GC 和 auto conflict resolution。observation 默认 disabled/incomplete；retirement candidate gate 固定 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。

iPhone 新增 `IPhoneTombstoneConflictReadSideSeam`，Mac 新增 `MacTombstoneConflictReadSideSeam`。两端默认 disabled，显式 enabled 也只做 legacy/canonical tombstoneConflict snapshot 并行 diff 和 redacted diagnostics；不删除、不 restore、不清 tombstone、不 resolve conflict、不写 store、不改 UI、不创建 upload job、不改 inventory response、`receive.json`、audio inbox、transcription/note generation、retry drainer 或 Mac pending sync。

`CanonicalMigrationDomainMatrix.v826TombstoneConflictNextPilotCandidate(...)` 只在 generatedArtifacts 模板/观察证据满足时把 `tombstoneConflict.nextPilotCandidate` 标为候选。该状态仍 `activePilot=false`、`staticOnly=true`、`runtimeSwitchEnabled=false`、`readPathLegacy=true`；`generatedArtifacts` 仍是当前 active pilot，其它域保持 static/default-off。

## 2026-06-05 Canonical v8.25 GeneratedArtifacts Read-Side Guarded Seam & Observation

本轮在 v8.24 `generatedArtifacts` staged canary expansion 之后补齐读侧 guarded seam、write/read evidence linkage、observation summary 和 report-only retirement candidate gate。共享层扩展 `CanonicalGeneratedArtifactReadProjection`：projection 仍只覆盖 transcript/note/summary generated artifact 的 metadata 与 availability，新增 local downloaded state、peer authoritative state、updatedAt summary、parent active/tombstoned summary 等 redacted 字段；继续排除完整 transcript/note/summary、provider response、完整 hash、绝对路径、request/response body 和 audio bytes。

新增 `CanonicalGeneratedArtifactReadSourceProvider` / `ReadSourceConfiguration` / `ReadCutoverGate` / `ReadFallback`。默认 read source 仍为 `legacy`；`parallelCompare` 和 `canonicalCandidate` 只构建 canonical candidate 并返回 legacy；只有 explicit internal/test `guardedCanonicalRead` 且 gate 通过时，才可服务 canonical generated artifact metadata/availability output。gate 要求 `generatedArtifacts` 是唯一 active pilot、write-side staged canary evidence clean、rollback fatal 为 0、read divergence/unsupported/contentLeakRisk/unsafePathToken/parentTombstone/audioConfusion 均为 0、legacy fallback available、canonical projection complete、无 artifact route change、无 generated artifact upload job、无 global UI cutover、runtimeSwitch=false。失败或 canonical read exception 均显式 fallback legacy。

iPhone `IPhoneGeneratedArtifactReadSideSeam` 和 Mac `MacGeneratedArtifactReadSideSeam` 新增可测试 `readSource(...)` wrapper，默认 unused/legacy，不改变 UI、store、inventory response、`receive.json`、transcription/note generation、artifact request/apply、retry drainer、Mac pending sync 或 upload runtime。observation window 现在可汇总 write-side commit/rollback/fallback/suppression 与 read-side canonical served/fallback/divergence 等 redacted counts；retirement candidate gate 仍 report-only，固定 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。其它 domain 继续 staticOnly/defaultOff；下一步应先审计 v8.25 evidence，可选择延长 generatedArtifacts observation 或进入 tombstoneConflict template alignment。

## 2026-06-05 Canonical v8.24 GeneratedArtifacts Staged Canary Expansion

本轮在 v8.23 `generatedArtifacts` N=1 之后新增 staged canary expansion，但默认仍 disabled。共享层新增 `CanonicalGeneratedArtifactCanaryStageRunner`、v8.24 matrix helper、stage observation report 和 staged diagnostics；只允许 `generatedArtifacts` 作为唯一 active pilot，且必须按 `N1 -> N3 -> N10 -> allEligible` 顺序推进。`N3` 必须有 clean N1 evidence，`N10` 必须有 clean N3 evidence，`allEligible` 必须有 clean N10 evidence 和显式 `allowAllEligible=true`；不能跳 stage，也不能把 v8.23 N1 成功自动解释为全量 cutover。

stage runner 只在显式 `.canaryCommit`、`stagePolicy.allowCandidateExecution=true`、`explicitInternalTestConfiguration=true`、owner-approved token、rollback/read-side/no-commit/dry-run/execution-shadow/real-data-shadow/root-bound/read-only transport evidence、local/peer snapshot、唯一 active pilot matrix 和注入 executor 同时满足时执行。candidate 选择仍限定 existing `/sync/artifact-request` bridge 的 `generatedArtifactDownloadApply`，按稳定顺序执行；首个 commit/postcondition 失败必须 rollback、保留 legacy fallback 并停止剩余 candidate。rollback failure 是 fatal blocker；只有成功且 pre/postcondition verified 的 candidate 才能 suppress exact legacy duplicate。

iPhone `StudyLibrarySyncCoordinator` 现在把 `N3/N10/allEligible` 交给 staged runner；v8.23 N1 strict runner 仍只处理 budget 正好 1 的路径。Mac `/sync/inventory` 仍 report-only：expanded stage 配置下只记录 peer snapshot unavailable / no duplicate suppression / legacy fallback preserved diagnostics，不拉取 peer snapshot、不调用 executor、不改 inventory response。v8.24 不新增 route，不创建 generated artifact upload job，不自动下载 audio，不切 runtime switch/UI/read path，不改 retry drainer、Mac pending sync、upload ledger、`receive.json`、audio inbox、legacy planner/store/route 或安全边界。

## 2026-06-05 Canonical v8.23 GeneratedArtifacts Canary N=1

本轮在 `generatedArtifacts` 唯一 active pilot 上新增严格 N=1 canary wrapper：共享层新增 `CanonicalGeneratedArtifactCanaryConfiguration`、扩展 `CanonicalGeneratedArtifactCanaryPolicy`、`CanonicalGeneratedArtifactN1CanaryRunner`、candidate safety report、N1 observation report 和 v8.23 diagnostics。默认仍 disabled；只有显式 `.canaryCommit`、budget 正好 `N=1`、`explicitInternalTestConfiguration=true`、`allowsInternalN1Execution=true`、owner-approved token、rollback/read-side/no-commit/dry-run/execution-shadow/real-data-shadow/root-bound evidence、local/peer snapshot、唯一 active pilot matrix 和注入 executor 同时满足时，才会选择一个 generated artifact download candidate。

candidate 选择固定最多一个，且稳定优先 `summaryJSON` / `noteJSON` 等更小的 metadata-adjacent 生成物，再到 `noteMarkdown`、`transcriptJSON`、`transcriptMarkdown`。blocker taxonomy 现在区分 unsupported action/kind、hash unavailable、byte size unavailable、unsafe logical path token、content leak risk、audio confusion risk、producer ambiguous、generated artifact upload denied、wrong route、rollback checkpoint missing、peer not authoritative、parent tombstone、conflict、runtime switch、N>1/allEligible、peer snapshot/executor unavailable 等。成功后只允许 canonical commit success 且 pre/postcondition verified 的 exact matching legacy artifact action 被 suppress；失败、rollback、fallback、fatal rollback 都不 suppress。

iPhone `StudyLibrarySyncCoordinator` 的 generated artifact N1 seam 已改为只走 v8.23 strict N=1 runner；后续 staged/allEligible 由 v8.24 独立 runner 管控。Mac `SecureLocalHTTPSServer` 仍是 report-only，在缺 peer snapshot 时记录 v8.23 N1 blocked/legacy fallback/observation diagnostics 并保持 inventory response 不变。v8.23 不新增 route，不绕过 `/sync/artifact-request`、`RequestVerifier`、TLS/HMAC/nonce/body hash，不创建 generated artifact upload job，不自动下载 audio，不切 runtime switch/UI/read path，不改 retry drainer 或 Mac pending sync。

## 2026-06-05 Canonical v8.22 GeneratedArtifacts Active Pilot Guarded Commit Seam N=0

本轮把 `generatedArtifacts` 从 v8.21 next-pilot candidate 提升为唯一 active pilot，但只启用 guarded commit gate evaluation，canary budget 固定为 `N=0`。共享层新增 `CanonicalGeneratedArtifactGuardedCommitSeam`、gate/result、evidence report、no-execution assertion、N1 readiness report 和 v8.22 diagnostics；gate 只评估 transcript/note/summary JSON/Markdown 生成物 candidate 的证据与阻断原因，不执行任何 candidate。

iPhone `StudyLibrarySyncCoordinator` 在已加载 local/peer inventory、canonical manifest、canonical plans 和 legacy artifact action snapshot 后记录 v8.22 diagnostics。Mac `SecureLocalHTTPSServer` 在 `/sync/inventory` 本地 response 构建后记录 report-only diagnostics；由于 Mac inventory 没有 peer snapshot，显式启用时会阻断但 response 不变。两端默认仍 disabled；显式 `.guardedExecuteCommit` / `.canaryCommit` 也固定 `willExecuteNow=false`、`canaryMaxObjectsPerSyncRun=0`、不持有 executor。

v8.22 不调用 `/sync/artifact-request`、不下载、不 apply、不写 generated artifact、不 commit、不创建 upload job、不自动下载 audio、不新增 route、不切 runtime switch、不改 UI/read path、不改 retry drainer 或 Mac pending sync。旧 generated artifact request/apply path 和 legacy fallback 保留；N1 readiness report 只列出进入后续人工审计/N=1 前仍需满足的 blocker，不授权执行。`libraryMetadata` 在本轮不再是 active pilot，但其 observation complete 或 retirement candidate ready 仍是 `generatedArtifacts` active pilot 的前置条件；其它 domain 继续 static/default-off。

## 2026-06-05 Canonical v8.21 GeneratedArtifacts Template Alignment and Next Pilot Candidate

本轮把 `generatedArtifacts` 对齐到 `libraryMetadata` 的模板审计形态，但只做 next-pilot 准备，不执行真实 canary、read-side cutover 或 legacy retirement。共享层新增 `CanonicalGeneratedArtifactReadProjection`、read-side parallel diff、observation window/gate、report-only retirement candidate gate 和 `CanonicalGeneratedArtifactTemplateReport`，只描述 transcript/note/summary JSON/Markdown 的 metadata 与 availability；不包含 artifact content、完整 hash、绝对路径、audio bytes、provider response 或用户内容。

iPhone 新增 `IPhoneGeneratedArtifactReadSideSeam`，Mac 新增 `MacGeneratedArtifactReadSideSeam`。两端配置默认 disabled；显式启用时也只消费当前 sync/inventory 已加载的 legacy artifact inventory 与 canonical manifest facts，记录 redacted diagnostics，并固定不下载、不 apply、不写 store、不改 UI、不创建 upload/apply job、不改 inventory response、`receive.json`、audio inbox、transcription/note generation 或 retry/Mac pending sync。

`CanonicalMigrationDomainMatrix` 增加 `nextPilotCandidate` 状态和 v8.21 blocker。`generatedArtifacts` 只有在 `libraryMetadata` observation complete 或 retirement candidate ready 后才可标为 `nextPilotCandidate`；该状态不是 active pilot，不计入 canary/cutover，不打开 runtime switch。`libraryMetadata` 仍是唯一 active pilot，其它 domain 继续 static/default-off；`audioUpload`、`tombstoneConflict`、`legacyRetirement` 不得在本轮变 active。

## 2026-06-05 Canonical v8.20 LibraryMetadata Observation Window and Retirement Candidate Gate

本轮在 v8.19 guarded read-source 之后新增 `libraryMetadata` observation window 与 report-only retirement candidate gate。共享层新增 `CanonicalLibraryMetadataObservationWindow` / `ObservationPolicy` / `ObservationGate` / `ObservationFailure`，记录 write-side canonical commit、rollback、legacy fallback、duplicate suppression、read candidate/read served/fallback、divergence、unsupported/path leak 和 unsafe side-effect 计数。默认 policy 仍 disabled；只有 explicit internal/test configuration 才记录观测事件。

retirement candidate gate 只读取 observation gate 结果，不执行 retirement。`CanonicalLibraryMetadataRetirementCandidateGate` / `CanonicalLibraryMetadataRetirementCandidateReport` 固定 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`reportOnly=true`，并保留 `manualAuditRequired=true`。gate 要求唯一 active pilot `libraryMetadata`、其它 domain static/default-off、write/read evidence、zero divergence、zero rollback failure、zero unsupported/path leak、legacy fallback、runtimeSwitch=false、无 default cutover、无 resource move/content write/tombstone delete/sync-upload/UI mutation。

新增 `CanonicalLibraryMetadataRollbackDrillSummary` 与 `CanonicalLibraryMetadataEndToEndPilotReport` 汇总 v8.20 E2E 状态，最终状态只会到 `pilotObservationReady` 或 `pilotRetirementCandidateReady`，不会产生 `retired`。`CanonicalMigrationStageStatus` 增加 observation/report 状态，`CanonicalMigrationDomainMatrix.v820LibraryMetadataObservationReport(...)` 仅把 `libraryMetadata` 标为 observation complete / retirement candidate ready report，`libraryMetadataPilotComplete` 仍为 false，其它 domain 保持 static-only。

iPhone `IPhoneLibraryMetadataReadSideSeam` 与 Mac `MacLibraryMetadataReadSideSeam` 新增默认关闭的 `observeReadSource(...)` hook，只把已生成的 read-source result 写入 observation window；hook 不读取 store、不触发 sync/upload、不移动资源、不写内容、不改 UI。默认 UI/Store 绑定仍是 legacy，`StudyLibraryStore` legacy read implementation、legacy planner/inventory/write/read path 均未删除。下一步应先人工审计 observation report，再决定是否进入 v8.21；不得自动继续 legacy retirement 或扩到其它 domain。

## 2026-06-05 Canonical v8.19 LibraryMetadata Guarded Read-Side Cutover Seam

本轮在 v8.18 `libraryMetadata` real canary N=1 之后新增 guarded read-side seam，但默认 read source 仍是 legacy。共享层新增 `CanonicalLibraryMetadataReadSource` / `ReadSourceMode` / `ReadSourceProvider` / `ReadSourceResult` / `ReadFallback`，以及 `CanonicalLibraryMetadataReadCutoverGate` / gate result / blocker。`legacy` 是默认模式；`parallelCompare` 与 `canonicalCandidate` 只构建 canonical metadata snapshot 并返回 legacy；只有显式 internal/test `guardedCanonicalRead` 且 gate 全部通过时，才可返回 canonical library metadata read output。

read cutover gate 只服务唯一 active pilot `libraryMetadata`，要求 write-side canary success evidence、rollback fatal count 为 0、read-side divergence 为 0、unsupported/pathLeakRisk 为 0、legacy fallback 可用、canonical projection complete、objectID stable、无 resource move、无 content write、无 tombstone/delete candidate、无 unresolved conflict、explicit internal/test config、UI cutover 非 global、runtimeSwitch=false。任一 blocker、canonical projection missing 或 canonical read exception 都显式 fallback legacy 并记录诊断。

iPhone `IPhoneLibraryMetadataReadSideSeam` 与 Mac `MacLibraryMetadataReadSideSeam` 新增可选 `readSource(...)` provider 包装，复用调用方已持有的 legacy manifest 与 canonical manifest facts。默认 UI/Store 绑定未改，`StudyLibraryStore` legacy read implementation 未删除，`RecordingLibraryView` / `MacStudyLibraryView` 仍读取 `allStudyItems` / `allStudyFolders`。本轮不触发 sync/upload、不移动资源、不写 standalone note content、不改 inventory response、receive.json、audio inbox、transcription/note generation、retry drainer、Mac pending sync、route/security 或 upload runtime。

retirement candidate 增加 guarded read-source evidence 输入，但仍 report-only：即使 write-side canary、guarded read evidence、observation、fallback、zero divergence、zero unsupported、zero conflict、zero rollback fatal、read source stable 和其它域 unaffected 均满足，也只返回 candidate/readiness report，`legacyDeleted=false`、`legacyDisabled=false`。下一步应先做 `libraryMetadata` observation/audit，再讨论 retirement candidate；不应扩到 generatedArtifacts/tombstoneConflict/audioUpload/recordingMetadata。

## 2026-06-05 Canonical v8.18 LibraryMetadata Production Canary Enablement N=1

本轮在 v8.17 read-side evidence 之后新增 `libraryMetadata` production canary 外层配置和注入报告，但默认仍 disabled。共享 `CanonicalLibraryMetadataProductionCanaryConfiguration` 固定 domain 为 `libraryMetadata`、`canaryMaxObjectsPerSyncRun == 1`，并显式阻断 N>1、allEligible、runtime switch、release/default enablement、非 `libraryMetadata` active pilot、缺 owner token、缺 rollback/evidence、缺 read-side parallel equivalence、缺 non-dry-run root-bound apply port 或缺 executor。

新增 `CanonicalLibraryMetadataProductionCanaryInjection` 只在 `.canaryN1Execute` + explicit internal/debug configuration + owner-approved token + rollback/read-side/write-side evidence + injected executor 同时满足时调用既有 N=1 runner。`.canaryN1Armed` 只报告 armed/no-execution，不 commit、不 suppress legacy；`.diagnosticsOnly` 只记录 diagnostics。成功后仍只 suppress matching legacy libraryMetadata duplicate；失败、rollback、fatal blocker、unsafe/no-eligible candidate 或 gate blocked 均保留 legacy fallback 且不 suppress。

iPhone 新增 `IPhoneLibraryMetadataProductionCanaryBootstrap`，Mac 新增 `MacLibraryMetadataProductionCanaryBootstrap`。两端默认 bootstrap 不注入 executor/apply port；显式 test-root 配置才构造 `IPhoneLibraryMetadataRealApplyPort` / `MacLibraryMetadataRealApplyPort` 与 cutover executor，并把 evidence 标成 test-root-bound。production root 必须使用 `.productionRootExplicit` 且 `allowProductionRootWrites=true`，否则仍是 `productionRootDisabled`/blocked；本轮没有把该 bootstrap 接到默认 app init、UI 或 runtime switch。

新增 `CanonicalLibraryMetadataRealCanaryObservationReport` 和 v8.18 diagnostics：记录 injection configured/armed/blocked/execution started/completed/failed、production root write guard、rollback、legacy fallback、success-only duplicate suppression、read-side equivalent/divergent 和 fatal blocker。报告保持 `uiMutated=false`、`resourceMoved=false`、`uploadJobCreated=false`，不切 read path，不触发 sync/upload，不修改 route/security/retry/Mac pending sync，不移动资源，不写 standalone note content，不删除 legacy。

## 2026-06-05 Canonical v8.17 LibraryMetadata Read-Side Pilot Completion

本轮在 v8.16 staged expanded canary 之后新增 `libraryMetadata` read-side evidence 层，默认仍 disabled。共享 `CanonicalLibraryMetadataReadProjection` 从 legacy manifest 与 canonical library objects 构建 metadata-only read snapshot，只覆盖 folder、study item、standalone note 的业务 metadata、folder membership、filing/tags/color/trash state、business modified time 与 redacted logical resource token summary；不包含 standalone note 全文、真实资源路径、完整 hash、provider response 或本机隐私路径。

`CanonicalLibraryMetadataReadSideParallelDiff` 只做 legacy/canonical read snapshot 并行比较，输出 divergence taxonomy、equivalence、unsupported/path-leak blocker 和 bounded summary。`CanonicalLibraryMetadataReadSideCutoverEvaluator` 新增 default-off read cutover candidate：`parallelOnly` 只记录 diff；`canonicalReadCandidate` / `guardedCanonicalRead` 需要 `libraryMetadata` sole active pilot、v8.16 write-side staged canary evidence、zero divergence、legacy fallback 可用且无 unsupported/path-leak blocker。即使 candidate ready，本轮结果也固定 `readPathSwitched=false`、`uiMutated=false`、`syncOrUploadTriggered=false`。

iPhone `StudyLibrarySyncCoordinator` 新增默认关闭的 `IPhoneLibraryMetadataReadSideSeam`，在 sync tick 中复用已加载 inventory/canonical manifest facts 记录 diagnostics；Mac `SecureLocalHTTPSServer` 新增默认关闭的 `MacLibraryMetadataReadSideSeam`，在 `/sync/inventory` response 构建过程中复用本地 inventory/canonical manifest facts 记录 connection diagnostics。两端 seam 均不改变 legacy/canonical plan、read model、UI、inventory response、state store、upload ledger、retry queue、Mac pending sync、route/security、真实 store 或 `receive.json`。

新增 `CanonicalLibraryMetadataRetirementCandidateEvaluator` 只输出 report-only readiness。它把 write-side staged evidence、read-side cutover evidence、observation window、fallback 和 divergence 作为 blocker 输入，但始终保持 `legacyDeleted=false`、`legacyDisabled=false`、`reportOnly=true`。v8.17 不启用其它 domain，不移动资源，不写 standalone note content，不触发 sync/upload，不删除或禁用 legacy。

## 2026-06-05 Canonical v8.16 LibraryMetadata Expanded Canary

本轮在 v8.15 strict N=1 旁新增 `libraryMetadata` staged expanded canary，默认仍 disabled。共享 `CanonicalLibraryMetadataCanaryStagePolicy` 支持 `n3`、`n10`、`allEligible`，并由 `CanonicalLibraryMetadataCanaryStageRunner` 按 v8.13 matrix、owner token、rollback/evidence、root-bound non-dry-run apply port、legacy fallback、read-side parallel equivalence 和 previous-stage observation evidence 进行 gate。`n3` 必须有 clean N1 evidence，`n10` 必须有 clean N3 evidence，`allEligible` 必须有 clean N10 evidence；不能跳 stage。

候选仍只限 folder/studyItem/standalone note metadata apply/send。selector 继续按 object kind、objectID、actionID 稳定排序；`n3`/`n10` 只取预算内 candidate，`allEligible` 只取本 run 所有 eligible metadata candidate。不安全候选（resource move、folder hierarchy mutation/cycle、objectID instability、tombstone/delete/conflict、parent missing、unsupported action、view refresh、retry drainer）只记录 skipped/fallback，不提交。

iPhone `performTick` 只有显式 `.canaryCommit` + stagePolicy 请求 `n3`/`n10`/`allEligible` + `allowCandidateExecution=true` + owner-approved token + 完整 evidence + 注入 executor 时才进入 v8.16 runner。runner 顺序执行候选；首个 commit/postcondition 失败后 rollback 并停止后续候选，rollback 失败记 fatal blocker。duplicate suppression 改为 per-candidate success-only：已成功 canonical candidate 可 suppress 匹配 legacy metadata action，失败、未执行、跳过和不匹配 candidate 保留 legacy fallback。

Mac `/sync/inventory` 真实 seam 仍缺 peer snapshot；显式 v8.16 stage 时只记录 stage evaluated/blocked、peerSnapshotUnavailable、legacyFallbackPreserved 和 observation diagnostics，不提交、不 suppress legacy、不改 response/route/security。共享 runner 在 Mac fake peer + fake executor 测试中覆盖同样的 staged execution 语义。

新增 observation report 记录 stage、budget、selected/executed/success/failure/rollback/rollbackFailure/fallback/suppression/skipped/noEligible/unsafeSkipped/read-side parallel 等计数，以及 `nextStageEligible`、blockers、recommendation。所有 diagnostics 只写 redacted syncRunID、domain/object/action/hash prefix/blocker/计数，不写完整 metadata JSON、完整 hash、payload、绝对路径、secret、fingerprint 或用户内容。v8.16 不改其它 domain、UI/read path、retry drainer、Mac pending sync、upload route、resource file、standalone note content、tombstone/delete/GC、audio/generated/recordingMetadata。

## 2026-06-05 Canonical v8.15 LibraryMetadata Canary N=1

本轮在 v8.13/v8.14 前置条件之上新增 `libraryMetadata` 单对象 N=1 canary，但默认仍 disabled。共享 `CanonicalLibraryMetadataCutover.swift` 现在包含 `CanonicalLibraryMetadataCanaryConfiguration` / `Mode`、扩展后的 `CanonicalLibraryMetadataCanaryPolicy`、candidate safety report、N1 observation report、`CanonicalLibraryMetadataN1CanaryRunner` 和 v8.15 diagnostics taxonomy。严格 gate 要求 domain 固定为 `libraryMetadata`、`canaryMaxObjectsPerSyncRun == 1`、显式 internal/test 配置、owner-approved token、rollback plan/evidence、NoCommit/dry-run/execution-shadow/real-data-shadow/read-side parallel evidence、non-dry-run root-bound apply port、legacy fallback 和 v8.13 matrix 仍只有 `libraryMetadata` active pilot。

iPhone `LocalNetworkSyncEngine.performTick` 在 legacy diff 后、final plan 前接入 v8.15 分支。只有显式 `.canaryCommit` + N=1 + `allowsInternalN1Execution` + `explicitInternalTestConfiguration` + 注入 `CanonicalLibraryMetadataCutoverExecutor` 时，才会调用 N1 runner；N=0 仍走 v8.14 report-only seam。候选选择每 run 最多提交 1 个 folder/studyItem/standaloneNote metadata apply/send candidate；resource token 变化、folder hierarchy mutation、tombstone/delete、conflict、cycle、parent missing、objectID instability、view refresh/retry drainer、N>1、allEligible、runtime switch 或非 libraryMetadata active pilot 都会 blocked/fallback。成功后才 suppress 同 object/action 的 duplicate legacy metadata action；失败、rollback、gate blocked 或 no eligible candidate 不 suppress。

Mac `/sync/inventory` 仍没有 peer snapshot，因此 app seam 在显式 N=1 下只记录 `canonicalLibraryMetadataN1MacPeerSnapshotUnavailable`、legacy fallback preserved 和 observation diagnostics，并继续返回原 inventory response。Mac 共享 runner 可在测试/内部 fake peer + fake executor 下验证 N=1 commit 语义，但真实 inventory route 不提交、不 suppress legacy、不改 route/response/security/pending sync。

v8.15 不新增 route、不发送 `/sync/apply-metadata`、不调用 `StudyLibraryStore.applySyncManifest`、不移动 audio/transcript/note/summary/resource 文件、不做 UI/read-side cutover、不改 retry drainer/Mac pending sync/upload route、不做 physical/permanent delete/tombstone GC/legacy retirement。新增测试：`RokuricsTests/CanonicalLibraryMetadataCanaryTests.swift` 和 `RokuricsMacTests/CanonicalLibraryMetadataCanaryTests.swift`。

## 2026-06-05 Canonical v8.14 LibraryMetadata Guarded Commit Seam N=0

v8.14 继续以 v8.13 matrix 为前置条件：`libraryMetadata` 仍是唯一 active pilot domain，其它 domain 继续 static-only / blocked-for-real-migration。本轮新增共享 `CanonicalLibraryMetadataGuardedCommitSeam`，把 folder、study item、standalone note metadata 的 guarded commit seam 固定为 report-only、canary budget `N=0`。该 seam 没有 executor 参数，不调用 production commit、不调用 real apply port、不写 production root、不发送 `/sync/apply-metadata`、不调用 `StudyLibraryStore.applySyncManifest`。

iPhone `StudyLibrarySyncCoordinator` 在 legacy diff 后、最终 plan 选择前评估 v8.14 seam。它复用当前 local/peer canonical manifest、library plan、candidate 和 legacy action snapshot，记录 gate/evidence/readiness diagnostics，然后返回 `nil`，因此 legacy duplicate suppression 不会发生，legacy/canonical plan、action count、pending count、upload job、retry drainer、UI 和 audio/generated/tombstone/conflict 域都保持原状。

Mac `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 在 inventory response 构建后评估同一 report-only seam。Mac inventory route 没有 peer snapshot，因此显式启用时会把 peer snapshot missing 记录为 blocker/readiness gap，但继续返回原 inventory response；不改 route、response shape、`RequestVerifier`、nonce/HMAC/TLS/body-hash、pending sync、receive JSON 或 inbox。

新增 `CanonicalLibraryMetadataNoExecutionAssertion` 用于验证 v8.14 的 no-execution 不变量：`commitAttemptedCount=0`、`committedObjectCount=0`、`productionCommitCalled=false`、`realApplyPortCommitCalled=false`、`networkSendCalled=false`、`applySyncManifestCalled=false`、`metadataJSONWritten=false`、`duplicateLegacySuppressedActionIDs=[]`、`legacyFallbackPreserved=true`、`runtimeSwitchEnabled=false`。新增 `CanonicalLibraryMetadataN1ReadinessReport` / `Status` / `Blocker` 只报告进入 N1 前仍需显式 enablement、canary budget 从 0 改到 1、保持 duplicate suppression disabled 等 blocker，不授权 N1 执行。

v8.14 diagnostics 新增 `canonicalLibraryMetadataV814SeamStarted`、`canonicalLibraryMetadataV814SeamCompleted`、`canonicalLibraryMetadataV814SeamBlocked`、`canonicalLibraryMetadataV814GateEvaluated`、`canonicalLibraryMetadataV814GateAllowedBudgetZero`、`canonicalLibraryMetadataV814GateBlocked`、`canonicalLibraryMetadataV814CanaryBudgetZero`、`canonicalLibraryMetadataV814CommitNotExecuted`、`canonicalLibraryMetadataV814LegacyFallbackPreserved`、`canonicalLibraryMetadataV814DuplicateSuppressionNotApplied`，并保留 N=0 状态事件 `canonicalLibraryMetadataCanaryBudgetZero`、`canonicalLibraryMetadataGateAllowedButNoExecution`、`canonicalLibraryMetadataCommitSkippedBecauseCanaryBudgetZero`。diagnostics 只写 redacted domain/object/action/gate/readiness 摘要，不写完整 metadata JSON、完整 hash、request/response body、secret、fingerprint 或本机路径。

## 2026-06-05 Canonical v8.13 Migration Matrix Freeze and LibraryMetadata Pilot

本轮停止继续横向扩域，新增共享 `CanonicalMigrationMatrix.swift`，把后续迁移收束成统一 domain x stage matrix。matrix 覆盖 `recordingMetadata`、`generatedArtifacts`、`libraryMetadata`、`tombstoneConflict`、`audioUpload`、`uiProjection` 和 `legacyRetirement`，stage 覆盖 `notStarted`、`projected`、`planned`、`noCommit`、`realApplyPort`、`commitExecutor`、`appSeamDefaultOff`、`canaryN0`、`canaryN1`、`expandedCanary`、`domainCutover`、`readSideParallel`、`readSideCutover`、`retirementCandidate` 和 `retired`。

v8.13 的唯一 active pilot domain 是 `libraryMetadata`。其它 domain 在本阶段只能是 `staticOnly` 或 `blockedForRealMigration`：只做代码完整性、静态审查、测试补齐和 default-off 断言，不进入真实 migration/canary/cutover。`CanonicalMigrationGlobalConfigValidator` 会把多个 active pilot、非 `libraryMetadata` active pilot、`runtimeSwitchEnabled=true`、release/default enabled cutover、pilot 完成前启用 `generatedArtifacts` / `tombstoneConflict` / `audioUpload`、以及 read-side cutover 前 legacy retirement 都标为 violation。

本轮只新增 diagnostics/test-only 的 matrix、global config guard、`CanonicalLibraryMetadataPilotReport` readiness audit 和其它 domain static audit。没有执行 canary，没有 production commit，没有切 UI，没有迁移读路径，没有删除 legacy，没有改 retry drainer、Mac pending sync、upload route 或 audio upload runtime。所有 app seam 默认仍 disabled，executor 默认仍 nil，runtime switch 仍 false，读路径仍 100% legacy。

`libraryMetadata` pilot 当前路线被固定为：N0 gate -> N1 canary -> expanded canary -> domain write cutover -> read-side parallel -> read-side cutover -> retirement candidate。`CanonicalLibraryMetadataPilotReport` 会检查 canonical projection、planner、apply plan bridge、NoCommit executor、real apply port、Commit executor、app seam default-off、canary policy、rollback plan、failure injection、legacy fallback、success-only duplicate suppression、read-side parallel projection、no resource move guard、no physical delete guard、tests 和 docs。缺 read-side parallel、tests、NoCommit、real apply port、commit executor 或 app seam 时只报告 blocker，不启用迁移。

其它域状态按源码为准：`recordingMetadata`、`generatedArtifacts` 已有 default-off app seam 和 tests；`tombstoneConflict` 有 NoCommit/real apply/Commit 机器件但当前源码没有接入 iPhone tick / Mac inventory app seam；`audioUpload` 只有 shadow/preparation 与 NoCommit 级 app seam，没有 production commit executor。`audioUpload` 仍是最后处理的最高风险域；`tombstoneConflict` / delete 仍 blocked，直到 `libraryMetadata` pilot 证明完整 pipeline。

## 2026-06-04 Canonical v8.12 Audio Upload Runtime Shadow and Canary Preparation

本轮为最高风险 `audio upload runtime` 增加 default-off/shadow-only 的 cutover preparation。共享层新增 `CanonicalAudioUploadCutover.swift`，集中定义 audio upload domain model、local/peer/ledger/retry truth、candidate/evidence report、diagnostics taxonomy、canary stage policy、gate、NoCommit runner、shadow receiver/rehearsal wrapper、abort/rollback policy 和 read-side parallel projection。v8.12 只表达准备态，不执行 production audio upload cutover。

iPhone 新增 `IPhoneAudioUploadNoCommitExecutor`，Mac 新增 `MacAudioUploadNoCommitExecutor`。双端 app seam 都默认 disabled；显式启用时只记录 gate/no-commit diagnostics。iPhone seam 位于 legacy diff 后、真实 upload plan 执行前，不改变 `LocalNetworkSyncDiffPlan`、不创建 upload job、不 suppress legacy；Mac `/sync/inventory` seam 因没有 peer snapshot 只记录 peer-unknown/blocked/fallback diagnostics 并返回原 inventory response。

v8.12 证据规则明确：peer same hash+size 才能 no-op；peer missing/metadataOnly 只能成为 shadow/canary candidate；peer unknown 必须 deferred；view refresh、显式 manual upload button 和 retry drainer fresh job 不由 canonical 创建新上传；completed ledger、metadata uploaded、receive record 和 UI uploaded 都不能单独证明 audio 已在 Mac。different hash/size 只进入 conflict，不覆盖 Mac 既有音频。

v8.12 没有修改 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient`、Mac resumable routes、upload job/session/chunk/finalize、Mac inbox writes、`receive.json`、upload ledger、retry drainer、Mac pending sync、UI、auto audio download、TLS/HMAC/nonce/body-hash/Keychain 或 route allowlist。新增 diagnostics 只写 redacted trigger/nodeRole/domain/objectID、peer state、ledger phase、action、result/reason/hash prefix；不写完整 hash、完整 request/response body、绝对路径、secret、fingerprint 或用户内容。

## 2026-06-04 Canonical v8.11 Tombstone and Conflict Domain Migration

本轮把 soft tombstone 与 conflict record 的 production execution 语义推进到 default-off 的 cutover seam。共享层新增/扩展 `CanonicalTombstoneConflictCutover.swift`，集中定义 `CanonicalTombstoneConflictDomain`、candidate、action kind、gate、canary stage policy、NoCommit summary、commit result、diagnostics taxonomy、read-side parallel projection、success-only legacy duplicate suppression、app seam configuration 和 root-bound tombstone/conflict marker/ledger write/rollback core。范围只包含 object/library soft tombstone marker、active-vs-tombstone/metadata/generated artifact conflict ledger record、anti-resurrection blocking record 和 generated artifact tombstone unsupported marker；不做 physical delete、permanent delete、tombstone GC、restore cutover 或 conflict auto-resolution。

iPhone 新增 `IPhoneTombstoneConflictNoCommitExecutor`、`IPhoneTombstoneConflictRealApplyPort`、`IPhoneTombstoneConflictCutoverExecutor`；Mac 新增 `MacTombstoneConflictNoCommitExecutor`、`MacTombstoneConflictRealApplyPort`、`MacTombstoneConflictCutoverExecutor`。NoCommit 只写临时 staging summary，显式记录 `applySyncManifestCalled=false`、network send/receive JSON mutation/generated artifact deletion/audio deletion 均 suppressed，且不 suppress legacy。real apply port 默认 disabled，`productionRootURL` 默认 `productionRootDisabled`；只有测试/内部显式 `testRootURL` 写临时 root 下的 tombstone marker 或 conflict ledger JSON，并提供 checkpoint rollback restore/remove。

v8.11 commit executor 只允许 `.tombstoneMark` 与 `.conflictRecord` side effect；commit 前必须有 explicit token、owner approval、NoCommit/dry-run/execution-shadow/real-data-shadow evidence、root-bound non-dry-run apply port、atomic replace、rollback checkpoint、rollback verification、soft marker store/conflict ledger 支持、tombstone newer-wins policy 和 rollback evidence。`resurrectionBlocked` 被视为安全的 anti-resurrection ledger action；真正 stale live metadata risk、ambiguous conflict policy、physical/permanent delete attempt、tombstone GC attempt、unsupported restore 和 generated artifact tombstone apply 都会 gate blocked。只有 commit 成功且 postcondition 通过后才 suppress 同 object/domain/action/conflict kind 的 duplicate legacy action。

v8.11 没有接入 iPhone tick 或 Mac inventory 默认生产路径，没有修改 `/sync/apply-metadata`、`/sync/artifact-request`、upload routes、`RequestVerifier`、TLS/HMAC/nonce/body-hash/Keychain，没有切 UI owner、retry drainer、Mac pending sync、audio upload、generated artifact download/apply、folder/studyItem metadata 或 legacy retirement。新增 diagnostics 只写 redacted syncRunID、trigger、nodeRole、domain、object/artifact id、action kind、tombstone state、conflict kind/policy、hash prefix 和 result/reason，不写完整 hash、完整 metadata JSON、transcript/note/summary/provider response、绝对路径、secret、fingerprint 或 request/response body。

## 2026-06-04 Canonical v8.10 Folder and StudyItem Metadata Domain Migration

本轮把 folder、study item、standalone note 的 metadata 域推进到 default-off 的 cutover seam。共享层新增 `CanonicalLibraryMetadataCutover.swift`，集中定义 library metadata cutover domain、candidate、gate、NoCommit evidence、canary stage policy、root-bound metadata write/rollback core、commit runner、legacy duplicate suppression 和 UI parallel read-only diagnostics。范围只包含 folder rename/move/color/trash metadata、study item metadata、standalone note metadata；不移动 audio/transcript/note/summary/resource 文件，不改 `folderID` / `itemID` 生成规则，不做 permanent delete，不做 tombstone GC。

iPhone 新增 `IPhoneLibraryMetadataNoCommitExecutor`、`IPhoneLibraryMetadataRealApplyPort`、`IPhoneLibraryMetadataCutoverExecutor`，并在 `LocalNetworkSyncEngine.performTick` 中增加 library metadata NoCommit/cutover seam。默认 configuration 仍 disabled、canary `N=0`、executor 为 nil；显式 NoCommit 只写临时 staging summary 并立即 cleanup；显式 canary 只有在 N=1 内部开关或 staged canary policy、完整 evidence、owner-approved token 和注入 executor 同时满足时才可能执行。commit 成功必须满足 precondition、postcondition、root-bound metadata hash verification 与 rollback checkpoint；只有成功后才 suppress 同 folder/studyItem/standalone note metadata 的 duplicate legacy action。

Mac 新增 `MacLibraryMetadataNoCommitExecutor`、`MacLibraryMetadataRealApplyPort`、`MacLibraryMetadataCutoverExecutor`，并在 `/sync/inventory` 构建后接入 library metadata diagnostics seam。Mac inventory route 没有 peer snapshot，因此显式启用时只记录 peer-snapshot-unavailable gate/fallback diagnostics，不提交、不 suppress legacy、不改变 inventory response。双端 real apply port 默认 disabled；`productionRootURL` 默认 `productionRootDisabled`，只有测试/内部显式 `testRootURL` 写临时 root。

v8.10 没有迁移 audio、generated artifact、recordingMetadata、tombstone/conflict production execution、UI owner、retry drainer、Mac pending sync、security route 或物理存储 schema。新增 diagnostics 只写 redacted domain、object id/kind、action、hash prefix、parent/tag/filing summary、gate/fallback/rollback result，不写完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint、完整 request/response body 或用户内容。

## 2026-06-04 Canonical v8.9 Generated Artifacts Domain Migration

本轮把 generated artifact 域推进到 default-off 的 cutover seam，但范围只限五类 Mac 生成产物：transcript JSON、transcript Markdown、note Markdown、note JSON、summary JSON。共享层新增 `CanonicalGeneratedArtifactCutover.swift`，集中定义 generated artifact cutover domain、candidate、gate、NoCommit evidence、root-bound apply/write/rollback core、commit runner、legacy duplicate suppression 和 UI parallel read-only diagnostics。既有 `CanonicalProjectionContract.generatedArtifactKinds`、`CanonicalSyncPlanner` 与 `CanonicalApplyPlan` 已能表达这五类 artifact 的 projection、download/no-op/defer/conflict 与 apply action；本轮没有新增 artifact kind 或 route。

iPhone 新增 `IPhoneGeneratedArtifactNoCommitExecutor`、`IPhoneGeneratedArtifactRealApplyPort`、`IPhoneGeneratedArtifactCutoverExecutor`，并在 `LocalNetworkSyncEngine.performTick` 中增加 generated artifact NoCommit/cutover seam。默认 configuration 仍 disabled、canary `N=0`、executor 为 nil；显式 NoCommit 只写临时 staging summary 并立即 cleanup，显式 canary 只有在 N=1 且带内部开关和 executor 时才可能运行。commit 成功必须同时满足 precondition、postcondition、hash/size verification 与 rollback checkpoint；只有成功后才 suppress 同 artifact 的 legacy `/sync/artifact-request` download action。失败、rollback、fallback、gate blocked 或缺 executor 时不 suppress legacy。

Mac 新增 `MacGeneratedArtifactNoCommitExecutor`、`MacGeneratedArtifactRealApplyPort`、`MacGeneratedArtifactCutoverExecutor`，并在 `/sync/inventory` 构建完成后接入 generated artifact diagnostics seam。Mac inventory route 没有 peer snapshot，因此默认与显式配置下都保持 report/fallback 语义，不新增 production route，不触发 artifact request，不改变 inventory response，不改 pending sync 或 `RequestVerifier`。双端 real apply port 默认 disabled；`productionRootURL` 默认 `productionRootDisabled`，只有测试/内部显式 `testRootURL` 写临时 root。

v8.9 没有迁移 audio upload/download，没有创建 generated artifact upload job，没有新增 `/sync/artifact-request` 以外的 route，没有改 TLS/HMAC/nonce/body-hash/Keychain/route allowlist，没有切 UI owner、retry drainer、Mac pending sync、folder/studyItem/tombstone/delete/conflict/legacy retirement 或物理存储 schema。新增 diagnostics 只写 kind、object/artifact id、byte size、hash prefix、route summary、gate/fallback/rollback result，不写完整 transcript/note/summary/provider response、完整 hash、绝对路径、secret、fingerprint 或完整 request/response body。

## 2026-06-04 Canonical v8.6 App Seam Guarded Commit Wiring, Canary N=0

本轮把 `recordingMetadata` guarded commit 的 app seam 接到双端默认同步路径，但仍保持 default-off、diagnostics-only、canary `N=0`。共享层新增 `CanonicalRecordingMetadataGuardedCommitSeam`、guarded commit context、gate、evidence report、canary policy、apply/transport/rollback readiness summary 和 `canonicalV86*` / `canonicalRecordingMetadata*` diagnostics。该 runner 没有 executor 参数，不调用 `CanonicalRecordingMetadataCutoverRunner.run`，因此无法执行真实 commit。

iPhone `LocalNetworkSyncEngine.performTick` 现在在 legacy diff 后、live read-only probe 和 canonical/legacy plan 选择前，只有显式 `CanonicalCutoverAppSeamConfiguration` 进入 `guardedExecuteCommit` 或 `canaryCommit` 时才记录 v8.6 guarded report。它复用已经加载的 local/peer canonical manifest、canonical sync/apply plan、legacy recording metadata action snapshot 和 cutover evidence；NoCommit seam 现在只在 `.guardedExecuteNoCommit` 下运行，避免 commit-mode canary 同时发出旧 NoCommit diagnostics。

Mac `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 在 inventory 构建完成后记录同一 v8.6 report；由于 `/sync/inventory` 只有本地 snapshot，显式启用时会把 missing peer snapshot 作为 nonfatal gate blocker 记录，并继续返回原 inventory response。双端 v8.6 report 均明确 `commitAttemptedCount=0`、`productionCommitCalled=false`、`realApplyPortCommitCalled=false`、`networkSendCalled=false`、`applySyncManifestCalled=false`、`metadataJSONWritten=false`、`runtimeSwitchEnabled=false`、`duplicateLegacySuppressedActionIDs=[]`。

v8.6 没有执行 real commit、没有写 production root、没有调用 `StudyLibraryStore.applySyncManifest`、没有发送 `/sync/apply-metadata`、没有 suppress duplicate legacy、没有改变 UI、retry drainer、Mac pending sync、upload routes/security、audio/generated/folder/studyItem/tombstone/conflict 域或 legacy planner 执行。新增双端 `CanonicalRecordingMetadataGuardedCommitSeamTests` 覆盖 default-off、证据齐全但 N=0 不执行、unsafe mode/trigger/evidence blocker、redaction、iPhone tick plan/client side effects unchanged、Mac inventory response unchanged/missing peer snapshot nonfatal。

## 2026-06-04 Canonical v8.5 Real Root-Bound RecordingMetadata Apply Port

本轮实现 default-off 的真实 root-bound `recordingMetadata` apply/send port 合同。共享层新增 `CanonicalRootBoundMetadataWrite.swift`，提供 `CanonicalRecordingMetadataApplyPortMode`、root-bound metadata target/write/checkpoint/result/rollback result、失败分类、root containment 校验、atomic replace、read-back postcondition verification、checkpoint restore rollback 和 redacted side-effect trace。逻辑路径只允许 root token 下的相对 token，拒绝绝对路径、scheme/`file://`、`.`/`..` traversal 和 root escape。

双端 `IPhoneCanonicalProductionApplyPort` / `MacCanonicalProductionApplyPort` 现在除默认 disabled 与 `fakeInMemory` 外，新增显式 `testRootURL` 构造和默认禁用的 `productionRootURL` 构造。`testRootBound` 只在测试/内部 harness 中写临时 root；`productionRootURL` 默认 `productionRootDisabled`，除显式 `allowProductionRootWrites` 外会阻断写入。默认 app port set、migration facade、`CanonicalKernelFacade`、UI、retry drainer、Mac pending sync 和 canary 默认路径仍不会构造或调用真实 root-bound port；v8.6 app seam 只读取这些 evidence/readiness 作为诊断，不调用 port。

v8.5 只覆盖 `recordingMetadataApply` / `recordingMetadataSend` 的 metadata bytes 写入能力；send port 仍不发送网络，只记录 no-network metadata side effect。它不调用 `StudyLibraryStore.applySyncManifest`，不写 `receive.json`，不创建 upload job，不改 upload routes/security，不迁移 audio/generated/folder/studyItem/tombstone/conflict/UI，不删除 legacy，也不 suppress app legacy duplicate。新增 gate evidence 要求 real root-bound port、non-dry-run root-bound mode、root-bound write、atomic replace、rollback checkpoint、rollback verified、production root default-disabled 和 test root evidence。

新增双端 `CanonicalRecordingMetadataRealApplyPortTests` 覆盖 unsafe logical path 拒绝、失败分类、默认 disabled、production root default-disabled、temp test root atomic write、rollback restore、postcondition mismatch rollback、checkpoint failure、root escape、audio/ledger/generated boundary untouched、commit executor 可使用 test-root real port、default port set 不使用 real port，以及 v8.5 gate evidence blocker。

## 2026-06-04 Canonical v8.4 Commit Failure Injection & fakeInMemory Hardening

本轮只加固 `recordingMetadata` Commit executor 的 fake/in-memory 执行路径。`CanonicalRecordingMetadataCommitFailureInjection` 现在显式覆盖 precondition/postcondition mismatch、transport before/accepted-after failure、apply before/after partial mutation、rollback failure、duplicate/idempotent replay、unsupported/unexpected side effect 和 missing rollback checkpoint；双端 `IPhoneRecordingMetadataCutoverExecutor` / `MacRecordingMetadataCutoverExecutor` 会在 fake commit 成功后才返回 duplicate legacy suppression candidate，失败、rollback、missing checkpoint 或 forbidden side effect 均不 suppress。

双端 `IPhoneCanonicalProductionApplyPort(fakeInMemory:)` 与 `MacCanonicalProductionApplyPort(fakeInMemory:)` 仍只保存 actor 内存状态，不写 Documents/Application Support，不调用 `applySyncManifest`，不发送真实 `/sync/apply-metadata`，不创建 upload job。v8.4 为 fake port 增加 checkpoint -> action 映射、per-object fake action inspection、idempotent same action replay、rollback restore fake state、rollback failure/missing checkpoint failure、pre/postcondition/apply failure injection 和 forbidden side-effect simulation；这些能力只用于测试/内部 fake harness。

v8.4 没有实现真实 root-bound apply port，没有把 Commit 接到默认 app path，没有写 production root，没有改变 legacy planner/inventory/store/route/upload coordinator/client、UI、retry drainer、Mac pending sync、audio/generated/folder/studyItem/tombstone/conflict 域或安全边界。下一步仍是 v8.5：设计并实现 default-off 的真实 root-bound `recordingMetadata` apply port，且仍需 rollback checkpoint、atomic replace、postcondition verify 和人工/Claude 审计。

## 2026-06-04 Canonical v8.3 Recording Metadata Commit Executor

本轮实现第一个 single-domain Commit executor，但范围只限 `recordingMetadata` 的 apply/send candidate。新增 `IPhoneRecordingMetadataCutoverExecutor` 与 `MacRecordingMetadataCutoverExecutor`，并复用 `CanonicalRecordingMetadataCutoverRunner` 的显式 token、owner approval、rollback plan、real-data shadow copy、execution shadow、dry-run equivalence、read-only probe、non-dry-run port、legacy fallback 和 production execution guard。默认构造仍使用 disabled/dry-run production port set，因此真实 app 默认会以 `InternalFakeApplyPort` requirement 阻断，不会写真实 store、发真实网络或调用 `applySyncManifest`。

executor 的可执行路径只接受测试/内部显式注入的 fake non-dry-run apply port 与 fake transport port。apply commit 只调用 `applyMetadata`，send commit 只通过 `.applyMetadata` route projection 映射既有 `/sync/apply-metadata`，再调用 `sendMetadata`；没有新增 Mac route、没有扩大 route allowlist、没有修改 `SecureLocalHTTPSServer`、`RequestVerifier`、TLS pinning、HMAC、nonce、body hash、Keychain、upload route 或 legacy upload/apply pipeline。当前真实 `StudyLibraryStore` 没有公开 single-object checkpoint/rollback API，无法安全做真实生产回滚，所以真实 store commit 仍被明确阻断。

v8.3 对 commit 增加 precondition/postcondition、rollback checkpoint、rollback execution、side-effect whitelist、idempotent retry 和 failure injection 覆盖。precondition 会检查 action/domain、objectID、canonical/local/peer metadata hash、unresolved conflict、send route/transport、bridge hint、modifiedAt 方向和 tombstone state；postcondition 失败、partial commit、transport/apply failure 都会 rollback，rollback 失败会成为 fatal blocker。side-effect trace 只允许 `metadataApply`、`.applyMetadata` network request 和 diagnostics write；upload、generated artifact、file write、tombstone physical change、conflict write 等副作用会阻断并回滚。

canary 默认仍为 `N=0`，预算耗尽时记录 canary budget exhausted、legacy fallback preserved 和 duplicate suppression skipped。只有 canonical commit 成功后才 suppress 同 action 的 duplicate legacy recording metadata；任何 gate blocked、precondition/postcondition/transport/apply/rollback failure 都保留 legacy fallback，不 suppress duplicate。新增 diagnostics taxonomy 覆盖 executor created、precondition evaluated/failed、postcondition verified/failed、rollback checkpoint created、rollback fatal blocker、legacy fallback preserved、duplicate suppression allowed/skipped 和 canary budget exhausted。未实现 audio/generated/folder/studyItem/UI、retry drainer、Mac pending sync、legacy retirement、性能优化或真实生产 store cutover。

## 2026-06-03 Canonical v8.2 NoCommit Hardening & Migration Config Consolidation

本轮只加固 `recordingMetadata` NoCommit app seam，没有实现真实 Commit executor，没有执行 `guardedExecuteCommit` / `productionExecute`，也没有默认启用任何 runtime switch。`CanonicalNoCommitV82.swift` 新增 NoCommit staging root lifecycle、cleanup/retention policy、structured evidence report 和 migration stage configuration summary；这些都是诊断与未来 gate evidence，不会触发 production write/network/apply。

双端 NoCommit executor 现在默认写系统临时 staging root，并在 stage 结束后立即 cleanup；只有显式 `retainForDiagnostics(maxAge:maxCount:maxBytes:)` 才 bounded 保留 staging root。cleanup 会拒绝 production root 或 production root 子路径，diagnostics/evidence 只输出 root kind、root id、计数、byte count、status、policy 和 redacted reason，不写绝对路径、完整 metadata JSON、完整 hash、secret、fingerprint、request/response body 或用户内容。

`CanonicalRecordingMetadataNoCommitRunner` 现在返回 `CanonicalNoCommitEvidenceReport`，并追加 v8.2 diagnostics：staging root created/cleaned/cleanup failed、evidence report built、equivalent/divergent、commit suppressed、legacy duplicate preserved、config stage resolved/blocked。旧 `canonicalV8RecordingMetadataNoCommit*` diagnostics 保留，legacy fallback 仍 preserved，`duplicateLegacySuppressedActionIDs` 仍为空，blocked seam 不发 commit-suppressed execution signal。

`CanonicalMigrationStageConfiguration` 默认 `.off`，并把 diagnostics-only、decision shadow、execution shadow、real-data shadow copy、read-only transport probe、recording metadata NoCommit 和 future guarded commit 的 allowed side effects / required evidence / domain policy 汇总为只读 config descriptor。`recordingMetadataNoCommit` 只允许 diagnostics + staging root write，不允许 production commit；`recordingMetadataGuardedCommit` 仅描述 future gate requirements，不会执行。

## 2026-06-03 Canonical Recording Metadata Controlled Cutover Candidate v1

本轮只推进第 7 步中的 `recordingMetadata` 单域 candidate，新增 `RokuricsShared/SyncCore/CanonicalRecordingMetadataCutover.swift`，并在 `CanonicalIPhoneMigrationFacade` / `CanonicalMacMigrationFacade` 暴露显式注入的 `runRecordingMetadataCutover` 测试入口。默认配置仍是 disabled；没有 UI toggle、release 默认开启、runtime switch、全量 cutover 或 legacy retirement。

`CanonicalSingleDomainCutoverConfiguration` / `CanonicalCutoverDomain` / `CanonicalCutoverMode` / `CanonicalCutoverPolicy` / `CanonicalCutoverGate` / `CanonicalCutoverResult` / `CanonicalCutoverFailure` 现在表达单域切换合同。可执行模式仅允许 `guardedExecuteCommit` 和 `canary`，且本轮只支持 `domain == recordingMetadata`；audio upload、generated artifact、folder/studyItem、tombstone GC、retry drainer、Mac pending sync、full UI、physical storage 和 legacy planner 仍不切。

cutover gate 必须同时具备 explicit token、owner approval、rollback plan 覆盖 `recordingMetadata`、real-data shadow copy evidence、execution shadow evidence、dry-run equivalence、无 blocking divergence、无 unresolved conflict、send 所需 read-only transport probe、non-dry-run production port availability、legacy fallback availability、rollback rehearsal、production execution guard pass，并拒绝 `viewRefresh` / `retryDrainer`。任一条件失败时 canonical production 不执行，可保留 legacy fallback，并记录 redacted blocker diagnostics。

canary 默认 `N=0`，即便 gate 通过也不执行对象；v8.7 只允许显式内部 `N=1` 对一个 recording metadata apply/send candidate 调用注入的 executor，`N=1` 缺内部开关和 `N>1` 都必须 blocked。canonical commit 成功后才 suppress 同 action 的 legacy duplicate；precondition/postcondition/transport/apply failure 会 rollback，rollback 成功后使用 legacy fallback，rollback 失败则标记 fatal blocker。UI parallel projection 只读诊断，`mutatedUI=false`；retirement readiness 只输出该域 candidate/blocker，不会删除、禁用或停止 legacy。

production route projection 增加 `CanonicalTransportRoute.applyMetadata`，双端 production transport adapter 将其映射到既有 `/sync/apply-metadata`。这不是新增真实 route，也未修改 `SecureLocalHTTPSServer`、`RequestVerifier` route allowlist、upload route、TLS pinning、HMAC、nonce、body hash 或 Keychain。`CanonicalKernelFacade` 对 `recordingMetadataSend` 使用 apply port 的 `sendMetadata` 合同，避免把 send 误路由成本地 apply；测试仍使用 fake executor/fake apply port，不触碰真实 store/network。

## 2026-06-02 Canonical Execution Shadow Preparation v1

本轮在 Canonical Shadow Migration Wiring v1 之上新增 execution-level shadow preparation。共享层新增 `CanonicalExecutionShadow.swift`，`CanonicalKernelFacade` 新增 `executionShadowDryRun`、`executionShadowWithShadowFileStore`、`executionShadowWithReadOnlyTransportProbe` 模式；双端新增 `IPhoneCanonicalShadowFilePort.swift`、`IPhoneCanonicalShadowTransportPort.swift`、`MacCanonicalShadowFilePort.swift`、`MacCanonicalShadowTransportPort.swift`，并扩展 shadow port factory 与 migration facade guard。该能力用于在 shadow root、shadow receiver 和 in-memory apply store 中排练 file/upload/apply/rollback，不是 production cutover。

execution shadow 默认仍关闭，只在显式 enabled shadow configuration 下从 iPhone `performTick` 的 legacy diff 后诊断 seam 或 Mac `/sync/inventory` 的本地 inventory 完成后诊断 seam 进入。iPhone/Mac on-device role 可以运行 execution shadow preparation，但仍不得进入 `productionExecute`；`productionExecute` 对非 testHarness 继续返回 `blockedProductionExecute`，side effects 为空。

file rehearsal 只允许写 shadow root，禁止 shadow root 等于或落在 production root 内，logical path escape/hash mismatch 会被拒绝，tombstone 只做 shadow marker/soft contract，不做真实物理删除。upload rehearsal 只使用 shadow receiver 与 canonical resumable upload runtime，覆盖 interruption/resume、same-hash no-op、different-hash conflict 和 finalize hash mismatch；不会创建真实 upload job，不调用 `RecordingUploadCoordinator`、`RecordingUploadClient` 或 `SecureMacUploadClient`，也不会写 `receive.json` 或 inbox。apply rehearsal 只写 in-memory shadow apply store，不调用真实 `StudyLibraryStore.applySyncManifest`，不写 study store、generated artifact 目标路径或 `receive.json`。

transport rehearsal 只构造 signed request projection、route classification 和 read-only probe report；默认不发送网络。即使显式启用 probe，也只能接受 read-only allowlist，upload/apply/mutating route 必须拒绝。新增 diagnostics 事件包括 `canonicalExecutionShadowStarted`、`canonicalExecutionShadowCompleted`、`canonicalExecutionShadowBlocked`、`canonicalExecutionShadowFileWriteSuppressed`、`canonicalExecutionShadowFileWriteToShadowRoot`、`canonicalExecutionShadowTransportProbeSuppressed`、`canonicalExecutionShadowTransportProbeCompleted`、`canonicalExecutionShadowUploadRehearsed`、`canonicalExecutionShadowApplyRehearsed`、`canonicalExecutionShadowRollbackRehearsed`、`canonicalExecutionShadowDivergenceDetected`、`canonicalExecutionShadowEquivalent`、`canonicalExecutionShadowProductionExecuteBlocked`；事件只写 redacted mode/role/domain/count/reason/hash prefix 等摘要，不写完整路径、完整 hash、secret、fingerprint、请求体、transcript/note/summary 或 provider response。

## 2026-06-02 Canonical Production Adapter Skeletons & Migration Facade v1

本轮在 Canonical Production Runtime API & Port Contract v1 之上新增双端 production adapter skeleton 与 migration facade。iPhone 新增 `IPhoneCanonicalProductionFilePort.swift`、`IPhoneCanonicalProductionTransportPort.swift`、`IPhoneCanonicalProductionUploadPort.swift`、`IPhoneCanonicalProductionApplyPort.swift`、`CanonicalIPhoneMigrationFacade.swift`；Mac 新增 `MacCanonicalProductionFilePort.swift`、`MacCanonicalProductionTransportPort.swift`、`MacCanonicalProductionUploadPort.swift`、`MacCanonicalProductionApplyPort.swift`、`CanonicalMacMigrationFacade.swift`。这些文件是生产迁移边界的可编译骨架，不是 legacy runtime 替换。

双端 file port 默认 disabled/dry-run，只允许测试显式构造的 temp-root fake mode；logical path token 必须绑定 root token 并做路径逃逸校验，resolution token 和 diagnostics 只输出 redacted 摘要。本轮没有写入真实 iPhone Documents 或 Mac Application Support，没有扫描真实 store，没有计算新的全量大文件 hash，也没有执行物理删除、permanent delete 或 tombstone GC。

双端 transport port 只映射既有 route path：`/sync/inventory`、`/sync/apply`、`/sync/apply-metadata`、`/sync/artifact-request`、`/upload-recording-audio-session/start`、`/upload-recording-audio-session/status`、`/upload-recording-audio-session/chunk`、`/upload-recording-audio-session/finalize`。默认真实网络发送被抑制；fake responder 只用于测试内存回环。没有新增 route、没有修改 upload route、没有替代 `SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier`、TLS pinning、HMAC、nonce、body hash 或 Keychain。

双端 upload port 只提供内存 session/ledger fake，实现 offset、chunk hash、total hash/size、confirmed bytes 和 finalize 合同验证；不会创建真实 upload job，不调用 `RecordingUploadCoordinator`、`RecordingUploadClient` 或 `SecureMacUploadClient`，不会自动下载 audio。双端 apply port 只在内存中记录 metadata/generated/tombstone/conflict/pre/postcondition 结果；不会调用真实 `StudyLibraryStore.applySyncManifest`，不会写 `receive.json`、study store 或 generated artifact 文件。

`CanonicalIPhoneMigrationFacade` 与 `CanonicalMacMigrationFacade` 默认 mode 仍为 disabled，runtime switch 仍为 false。`executeWithGuard` 必须同时具备测试 harness configuration、testHarness token 和 fake/in-memory port set 才能执行测试路径；默认或 production token 不会放行。本轮没有把 facade 接入 `LocalNetworkSyncEngine.performTick`、heartbeat、periodic/manual sync、retry drainer、Mac pending sync、UI button、真实 HTTPS route、真实 upload client 或真实 store。

## 2026-06-02 Canonical Production Runtime API & Port Contract v1

本轮在 canonical production ports/dry-run migration 层之上新增稳定的生产运行时外观 API 与真实端口方法合同。`CanonicalKernelFacade.swift` 现在提供外部调用面：`buildSnapshot`、`buildManifest`、`planSync`、`buildApplyPlan`、`buildLibraryPlan`、`buildTransferProjection`、`buildObjectProjection`、`buildRuntimeReadiness`、`buildProductionReadiness`、`dryRunMigration`、`compareLegacy`、`executeOffline`、`executeProduction` 和 `rollbackPreview`。执行模式明确为 `disabled`、`dryRun`、`offlineRuntime`、`productionShadow`、`productionExecute`，默认仍是 `disabled`；默认配置不会产生真实写入、网络发送、上传或 apply side effect。

`CanonicalProductionPorts.swift` 的 file/transport/upload/apply/diagnostics/clock/capability port 保留原 dry-run projection 方法，同时新增真实执行方法合同：root-bound metadata/artifact read/write/hash/rollback，signed request build/send/receive/verify，manifest/artifact/apply metadata exchange，resumable upload start/query/chunk/finalize/cancel，upload ledger/retry/rollback，metadata/generated/tombstone/conflict apply，pre/post condition verify，production diagnostics 和 capability/schema validation。现有 iPhone/Mac dry-run ports 通过协议默认实现继续编译并保持 suppressed；本轮没有实现真实 production adapter。

`CanonicalProductionExecution.swift` 新增 production execution result、redacted side-effect trace、guard token/policy/audit、rollback plan/checkpoint/action/result/audit 合同。`executeProduction` 必须先通过 `CanonicalProductionExecutionGuard`：要求 `productionExecute` 模式、显式 token、owner approval、operation allowlist、rollback plan 覆盖 required domain、dry-run equivalence report 与 token 匹配且无 blocking divergence、无 unresolved conflict、所需端口为 non-dry-run、migration gate 未阻塞。guard 失败时 side effects 为空并只返回 rejection reasons。

本轮测试只使用双端新增 fake production ports 验证 API 与合同：它们在内存中模拟 file/transport/upload/apply，不读取真实 store、不调用真实 HTTPS route、不上传真实 audio、不调用 `applySyncManifest`。真实 production execution 仍未接入 `LocalNetworkSyncEngine.performTick`、UI、retry drainer、Mac pending sync、真实 route、真实 upload client、真实 store 或物理文件迁移。

## 2026-06-02 Canonical Production Ports & Dry-Run Migration Readiness v1

本轮在离线 canonical runtime kernel 之上新增生产边界合同与 dry-run 迁移评估层：`CanonicalProductionPorts.swift` 定义 file/transport/upload/apply/clock/diagnostics/capability port、production snapshot、legacy action snapshot、port readiness 与 redacted diagnostics；`CanonicalDryRunMigrationPlanner.swift` 只比较 canonical dry-run action 与 legacy action snapshot 的等价性、风险、blocker 和 migration gate。该层仍只使用 Foundation 风格共享模型，不导入 AppKit/UIKit/AVFoundation/Network.framework，不接入真实 route、upload client、store 或 UI。

双端新增 `IPhoneCanonicalProductionSnapshotAdapter.swift`、`MacCanonicalProductionSnapshotAdapter.swift`、`IPhoneCanonicalDryRunPorts.swift`、`MacCanonicalDryRunPorts.swift`。snapshot adapter 只消费调用方显式传入的 legacy facts，生成 read-only `CanonicalProductionSnapshot`，不读取 store、不扫描目录、不计算大文件 hash、不写 `receive.json`、不调用 `applySyncManifest`、不创建 upload/apply job。dry-run ports 只投影“若迁移会执行什么”：file port 只做 root/logical token 校验并返回 suppressed write trace，transport/upload/apply port 均标记 would-write/would-send/would-upload/would-apply 被抑制，不发网络、不上传、不写文件、不变更 UI。

dry-run 等价报告只是 audit 证据：metadata churn suppression 可被标记为 canonical 更保守且非阻塞；canonical 会新增 legacy 没有的 upload/apply、出现 conflict、缺少 required production port/capability、存在 unsupported object 或 UI/retry/Mac pending sync/user data migration 未设计，都会阻塞。migration gate 当前最多给出 `eligibleForManualMigrationDesign`；`eligibleForRuntimeSwitch` 固定为 false，`retired` 固定为 false。legacy 仍是生产 runtime owner，真实迁移必须另行完成审计、人工批准、root-bound 生产 adapter 实现、shadow migration、rollback 方案和真实设备验证后才可设计。

安全边界保持不变：`safeLogicalPathToken` 只是路径 token 语法约束，不等同于生产 root-bound 文件 adapter；`manifestHash` 只做 manifest integrity/fingerprint，不替代 TLS pinning、HMAC、nonce、body hash、Keychain 或 RequestVerifier。新增 diagnostics 只写 event、domain、count、bool、reason、hash prefix、logical token 等摘要，不写完整 transcript/note/summary/provider response、完整 hash、绝对路径、secret、完整 fingerprint 或本机隐私路径。

## 2026-06-02 Canonical Kernel Completion v1

本轮在 Canonical Core / Sync Planner / Apply Plan 之上补齐 canonical library object 与 readiness 观测层。新增 `CanonicalLibraryObject.swift`、`CanonicalLibrarySyncPlanner.swift`、`CanonicalTransferStateMachine.swift`、`CanonicalObjectProjection.swift`、`CanonicalInventoryBuilderContract.swift`、`CanonicalRetirementReadiness.swift`，以及 `IPhoneCanonicalLibraryAdapter.swift`、`MacCanonicalLibraryAdapter.swift`。`CanonicalManifest` 兼容扩展 `libraryObjects`、`folders`、`studyItems`、`standaloneNotes`、`libraryTombstones`、`manifestCapabilities`，旧 payload 缺字段继续解码为空集合，schema 仍为 v1，不把完整 hash、绝对路径、完整 transcript/note/summary/provider response、secret、API key 或完整 fingerprint 写入 manifest。

canonical 当前可表达并规划 recordings、generated artifacts、folders、study items、standalone notes、library tombstones、conflicts、transfer state projection、read-only object projection、inventory coverage 和 retirement readiness。iPhone/Mac inventory 构建只复用已经加载的 recording facts、audio facts、generated artifact inventory facts 和 `StudyLibrarySyncManifest`，不新增文件系统扫描、大文件 hash、网络请求、upload job、`receive.json` 修改或 `applySyncManifest` 调用。

iPhone sync tick 仍先生成 legacy plan；双端 canonical manifest 有效时，再把 canonical recording plan、generated artifact plan 和 library plan 合并进桥接计划。folder/study item metadata apply/send/tombstone action 现在会映射回既有 metadata manifest 通道，并抑制同一对象的重复 legacy metadata action；实际执行仍通过 `/sync/apply-metadata` 与 `StudyLibraryStore.applySyncManifest`。audio 仍走 `RecordingUploadCoordinator` 主路径，generated artifact 仍走 `/sync/artifact-request`/apply，transfer state projection 与 object projection 不驱动 UI/sync/upload queue。

`CanonicalRetirementReadiness` 只是 diagnostics-only gate：它会明确阻塞 transport、upload runtime、physical storage 和 UI 仍由 legacy 负责的场景，不会删除或禁用 legacy planner、legacy inventory、legacy routes、retry drainer、Mac pending sync、`receive.json` 写入、物理文件或 tombstone。legacy fallback 继续保留，canonical 缺失、不兼容、capability 不足或 planner 失败时仍使用旧计划并记录 `canonicalPlanFallback`。

## 2026-06-02 Canonical Apply / Conflict / Tombstone v1

本轮在 Canonical Sync Truth v1 与 Canonical Artifact Transfer v1 之上新增 `RokuricsShared/SyncCore/CanonicalApplyPlan.swift`，把 recording metadata apply/send、Mac generated artifact download/apply、object tombstone apply/send、artifact tombstone unsupported policy 和 conflict record 统一成纯 Swift/Codable/Equatable 的 canonical apply plan。该层不访问文件系统、不发网络、不写绝对路径、不携带完整 hash、完整 transcript/note/summary/provider response、secret、API key 或完整 fingerprint；conflict 和 diagnostics 只保存 hash prefix、object/artifact id、kind、action/result/failure reason 等安全字段。

iPhone sync tick 现在在 `CanonicalSyncPlanner` 之后生成 `CanonicalApplyPlan`，再把 apply action 桥接回既有 `LocalNetworkSyncDiffPlan`：recording metadata apply/send 和 object tombstone apply/send 仍通过 `/sync/apply-metadata` + `StudyLibraryStore.applySyncManifest` 执行；generated artifact download/apply 仍通过既有 `/sync/artifact-request`、checksum/size 校验和 atomic replace 执行；audio bootstrap candidate 仍通过 `RecordingUploadCoordinator.uploadAndWait` 主路径执行。不会新增 artifact route，不会为 generated artifact 创建 upload job，不会自动下载 audio，不改变 UI、retry drainer、Mac pending sync、`receive.json` 写入或 Mac 安全 route。

Conflict model 当前是保守记录模型：metadata 同时编辑、audio hash/size mismatch、generated artifact hash/size mismatch、active-vs-tombstone 都生成 `CanonicalConflictRecord` 和 legacy conflict action，不覆盖对端文件或自动选择胜者。Tombstone model 当前只表示 soft-delete/anti-resurrection/no-physical-delete/no-permanent-delete/no-GC policy；peer tombstone 更新时只通过 metadata manifest 应用软删除，本轮不做物理删除、不做 permanent delete、不做 tombstone GC。对象 tombstone 会阻止 generated artifact download 复活已删除对象。

Mac apply bridge 仍是既有 signed `/sync/apply-metadata` route：请求继续经过 `RequestVerifier` 的 TLS/HMAC/timestamp/nonce/body hash 校验，然后调用 `StudyLibraryStore.applySyncManifest`。本轮未修改 Mac route allowlist、upload route、artifact route、pending sync 或 `applySyncManifest` 写入策略。

## 2026-06-02 Canonical Artifact Transfer v1

本轮在 Canonical Recording Semantics Hardening v1 之上，把 Mac 生成的 transcript/note/summary artifact 纳入 canonical 投影与规划。新增 `RokuricsShared/SyncCore/CanonicalProjectionContract.swift`，集中定义 generated artifact kinds、producer/capability 规则、safe logical path token 校验和 artifact id/key 合同；canonical manifest 仍不携带绝对路径、完整 hash、完整 transcript/note/summary/provider response、secret、API key 或完整 fingerprint。

Mac `/sync/inventory` 继续复用既有 legacy artifact inventory 已经加载/计算出的 checksum、size、logicalPathToken 和 `updatedAt`，将 transcript JSON/Markdown、note Markdown/JSON、summary JSON 投影为 Mac authoritative generated artifacts。iPhone inventory 只把已经下载到本地的同类 legacy artifacts 投影为 non-authoritative facts，不把这些 artifact 反向证明为 Mac 端 producer，也不新增扫描、下载 route 或写入路径。

`CanonicalSyncPlanner` 现在除了 recording metadata diff 与 recording audio bootstrap candidate，还为 Mac generated artifacts 生成 download/no-op/defer/conflict decisions。iPhone sync tick 仍先生成 legacy plan，再把 canonical generated artifact download 桥接回现有 legacy `/sync/artifact-request`/apply 执行通道；找不到可执行 legacy artifact 时记录 canonical fallback no-op。不会新增 artifact route，不会为 generated artifact 创建 upload job，不会自动下载 audio，不改变 UI、retry drainer、Mac pending sync、`applySyncManifest`、`receive.json` 或安全签名链路。

## 2026-06-02 Canonical Recording Semantics Hardening v1

本轮在既有 Canonical Sync Truth v1 之上做语义硬化，不删除 legacy planner、inventory、执行链路、状态模型、文件存储、transport 或上传路径。Canonical Artifact Transfer v1 后，canonical 接管 recording metadata diff、recording audio bootstrap candidate，以及 Mac generated transcript/note/summary artifact 的 transfer decision；folders、studyItems、非 generated artifact、UI、retry drainer、Mac pending sync、`applySyncManifest` 和 `receive.json` 写入仍由既有运行时负责。

`CanonicalRecordingMetadata.metadataHash` 现在固定为 `canonical-recording-business-metadata-v1` 合同，只覆盖同一录音的业务 metadata 等价字段：`objectID`、title、filing、规范化 tags、delete/tombstone 状态和 delete 时间。它明确排除 `createdAt`、`modifiedAt`、duration、upload/receive/processing state、ledger、local path、audio hash/size、diagnostics、`receivedAt`、`observedAt`、transcript/note 内容和 provider response。iPhone 侧 restore 场景不会把陈旧 `deletedAt` 带入 active canonical metadata。

Mac canonical adapter 现在拒绝把接收/处理时钟当成业务 `modifiedAt`：`RecordingReceiveRecord.updatedAt`、inbox fallback `StudyItemMetadata.defaultMetadata` 的即时 `updatedAt`、转写/笔记/receive status 变化都不能驱动 canonical LWW。只有 study item 业务字段相对 receive/inbox 事实发生变化、metadata-only sync item 有明确标记、study-only item 无 receive/inbox 参照，或 delete/tombstone 状态发生变化时，才使用 study item 的业务 `updatedAt` / `trashedAt`。

fallback 仍然保留 legacy plan，但 `canonicalPlanFallback` 不再只写模糊原因：现在区分 `localCanonicalManifestMissing`、`peerCanonicalManifestMissing`、`canonicalSchemaUnsupported`、`canonicalManifestValidationFailed`、`canonicalCapabilityMissing`、`canonicalPlannerFailed`，并记录 legacy fallback used、trigger、nodeRole、recording count 和 canonical object count。shadow/planner diagnostics 也新增/暴露 `canonicalMetadataHashConverged`、`canonicalCreatedAtIgnoredForMetadataHash`、`canonicalModifiedAtIgnoredProcessingState`、`canonicalMacUpdatedAtRejectedAsProcessingClock`、`canonicalBusinessModifiedAtUsed` 等语义事件。

## 2026-06-01 Canonical Sync Truth v1 补充

本轮新增 `RokuricsShared/SyncCore/CanonicalSyncPlanner.swift`。该 planner 只在双端 `LocalNetworkSyncInventory.canonicalManifest` 都存在且 schema、manifest hash、recording metadata capability 校验通过时启用；校验失败或任一端缺失 canonical manifest 时，`LocalNetworkSyncEngine` 保留并使用 legacy plan，同时记录 `canonicalPlanFallback`。

Canonical Sync Truth v1 最初的接管范围被限制在 recording metadata diff 和 recording audio bootstrap candidate；Canonical Artifact Transfer v1 继续扩展到 Mac generated artifact transfer decision。metadata diff 使用 `CanonicalRecordingObject.metadataHash` 与 `CanonicalTimestamp.modifiedAt` 判定 no-op、上传、下载或同时间戳冲突；audio bootstrap 使用 `CanonicalArtifact.contentHash` + `byteSize` + availability 判定 same no-op、missing/metadata-only/study-only bootstrap、unknown deferred 或 hash/size conflict；generated artifact 使用 canonical producer/capability/hash/size/logicalPathToken 判定 download、same no-op、peer unknown defer 或 conflict。

iPhone 侧 `LocalNetworkSyncInventoryBuilder.build` 现在把同一批已经加载的 `RecordingMetadata`、study manifest、inventory audio facts 和已存在的 generated artifact inventory facts 投影为 optional `canonicalManifest`，并继续写 canonical shadow report。`LocalNetworkSyncEngine.performTick` 先生成 legacy plan，再在 canonical 可用时桥接 canonical recording metadata/audio actions 和 generated artifact download decisions；folders、studyItems 和非 generated artifacts 仍沿用 legacy plan。

Mac 侧 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 现在把已经加载的 inbox items、study manifest、recording entries、audio facts 和 generated artifact facts 投影为 optional `canonicalManifest`，并继续写 canonical shadow report。该变更不修改 `/sync/inventory` 路由、HMAC、TLS pinning、nonce 校验、Mac pending sync、`applySyncManifest` 或 `receive.json` 写入。

audio bootstrap 不新增 client、route 或下载路径。canonical 只产出 upload candidate，最终仍走 `RecordingUploadCoordinator.uploadAndWait` -> `RecordingUploadClient` -> `SecureMacUploadClient`；普通 sync 下 peer unknown 会 deferred，view refresh 和 retry drainer 不会创建新的 canonical audio upload，peer same hash/size no-op，peer hash/size 不同保持 conflict，不覆盖 Mac 既有音频。

## 2026-06-01 Canonical Core skeleton 补充

本轮新增 `RokuricsShared/SyncCore/CanonicalCore.swift`，定义纯 Swift/Codable/Equatable 的 Canonical Core skeleton：`CanonicalNode`、`CanonicalCapability`、`CanonicalRecordingObject`、`CanonicalRecordingMetadata`、`CanonicalArtifact`、`CanonicalManifest`、`CanonicalHash`、`CanonicalTimestamp`、`CanonicalSyncState`、`CanonicalTransferState`、`CanonicalProcessingState`、`SyncDecision`、`TransferDecision`、`ConflictReason`、`ObjectProjection`。该层不访问文件系统、不发网络请求、不依赖 AVFoundation / Network.framework / AppKit / UIKit，不携带绝对路径、secret、完整 fingerprint、API key、完整 transcript 或 provider response。

本轮新增 iPhone adapter：`Rokurics/IPhoneCanonicalRecordingAdapter.swift`。它只把 `RecordingMetadata` 加调用方传入的 `CanonicalArtifactFact` 投影为 `CanonicalRecordingObject` / `CanonicalManifest`；不会扫描大文件、不会在 MainActor 上计算 SHA256、不会调用 upload coordinator、不会创建 upload job，也不会改变 UI 状态。

本轮新增 Mac adapter：`RokuricsMac/MacCanonicalRecordingAdapter.swift`。它只把 `RecordingReceiveRecord`、`StudyItemMetadata` 和调用方传入的 artifact facts join 成 `CanonicalRecordingObject` / `CanonicalManifest`；不会修改 `receive.json`、不会创建 metadata-only receive record、不会改 `applySyncManifest`、`StudyLibraryStore`、`AudioInboxStore`、转写或笔记生成行为。

## 2026-06-01 Canonical Shadow Mode 补充

本轮新增 `RokuricsShared/SyncCore/CanonicalShadowDiagnostics.swift`，定义只读 shadow report、legacy snapshot、object/artifact summary、mismatch category、report builder 和 bounded JSONL writer。report 只保存 hash prefix、object/artifact 计数、availability、byte size、逻辑文件名末段和 mismatch category；不写完整 hash、绝对路径、secret、完整 fingerprint、完整 transcript、完整 provider response 或本机隐私路径。

iPhone 侧 `LocalNetworkSyncInventoryBuilder.build` 在真实 sync tick 的 inventory 构建后，用已经加载的 `RecordingMetadata`、study manifest、inventory audio checksum/size/availability/logical token 生成 `CanonicalManifest` 和 shadow report。report 追加写入 iPhone audio store 下的 `Diagnostics/canonical-shadow.jsonl`，并记录 `canonicalShadowBuildStarted`、`canonicalShadowReportWritten`、`canonicalShadowReportWriteFailed`、`canonicalShadowBuildCompleted`、`canonicalShadowBuildDurationMs`、`canonicalShadowLegacyMismatchDetected`、`canonicalShadowStudyItemOnlyWithoutReceiveRecord`、`canonicalShadowMetadataHashConverged`、`canonicalShadowMetadataHashDiverged`、`canonicalShadowAudioConflictDetected`。该路径只新增 optional `canonicalManifest` inventory 字段；不创建 upload job、不改 UI、不改 retry drainer，也不新增大文件 hash 或目录扫描。

Mac 侧 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 只在 `/sync/inventory` 路径生成 shadow report，用已经加载的 inbox items、study manifest、inventory entries 和 artifact facts 生成 `CanonicalManifest`。report 追加写入 Mac recording library 下的 `Diagnostics/canonical-shadow.jsonl`，并通过 connection diagnostics 记录同名 canonical shadow 事件。该路径只新增 optional `canonicalManifest` inventory 字段并保持缺字段兼容；不改 `receive.json` 写入、不改 Mac pending sync、不改 upload/receive/转写/笔记行为。

当前真实事实仍是：Rokurics 还不是完整双端统一同步内核。iPhone recording model、Mac audio inbox model、Mac study item model、sync inventory/manifest、UI display state 仍多套模型并存；canonical 现在接管 recording metadata diff、recording audio bootstrap candidate、Mac generated artifact transfer decision、folder/study item metadata/tombstone planning 与 metadata manifest 桥接，其余非 generated artifacts、UI、retry、Mac pending sync、receive 写入、物理存储和完整 metadata manifest 执行仍在 legacy 运行时。

迁移方向仍是一个 Rokurics Canonical Core + 多端 capability adapters。下一阶段应先在真实 iPhone/Mac 上验证 v1 的 metadata/no-op/audio bootstrap/generated artifact download/folder/study item metadata bridge 行为稳定，再评估让 UI 读取 `ObjectProjection` 或迁移物理存储。不要先修 UI、不要先修 retry、不要先修 Mac pending sync，也不要继续在旧 `RecordingMetadata` vs `StudyItemMetadata` diff 上补丁式扩大逻辑。

## 既有连接/上传/同步状态补充

此前连接/上传/同步层已保持以下状态：上传链路继续通过 `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` 主路径把 iPhone 录音 metadata/audio 发送到 Mac；音频上传判断仍统一在 `RecordingAudioUploadDecisionEvaluator`，并扩展了 retry drainer、peer unknown、peer conflict、fatal failure 和展示状态。本轮 Canonical Sync Truth v1 没有新增 upload client、route、UI 触发或 retry 机制。

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

本轮 2026-06-02 Canonical Kernel Completion 启动时，工作区已有未提交的 Canonical Core skeleton、双端 adapter、shadow diagnostics、planner、apply plan、测试和文档变更；本轮在这些既有改动之上新增 canonical library object/planner、transfer projection、object projection、inventory builder contract、retirement readiness gate、iPhone/Mac library adapter、对应测试和文档更新。未修改 Xcode project、scheme 或构建脚本。

2026-06-02 Canonical Runtime Kernel Offline Completion v1 在 `RokuricsShared/SyncCore/` 增加纯离线 runtime kernel：root-bound in-memory file store、in-memory route/capability/hash/idempotency transport、resumable upload runtime、apply executor、conservative conflict resolver、two-node runtime harness 和 runtime readiness evaluator。该 kernel 只在新增 `CanonicalRuntimeKernelTests` 中运行；未接入 `LocalNetworkSyncEngine.performTick`、真实 `RecordingUploadCoordinator`/client、Mac HTTPS route、真实 store、UI、retry drainer 或 Mac pending sync。

2026-06-02 Canonical Production Ports & Dry-Run Migration Readiness v1 新增 production port 合同、read-only production snapshot adapter、dry-run suppressed ports、legacy equivalence report 和 migration gate 测试。该层没有启动生产迁移，没有替换 legacy planner/store/route/upload/apply/UI；新增 port/gate 只能作为后续迁移设计输入。

2026-06-02 Canonical Production Runtime API & Port Contract v1 新增 `CanonicalKernelFacade`、真实 production port 方法合同、`CanonicalProductionExecutionGuard`、rollback contract 和 redacted production side-effect/result 模型。该层仍没有 production adapter，没有 runtime switch，没有连接到 `performTick`、真实 route、真实 upload client、真实 store、UI、retry drainer 或 Mac pending sync。

2026-06-02 Canonical Production Adapter Skeletons & Migration Facade v1 新增双端 production file/transport/upload/apply adapter skeleton 和双端 migration facade。adapter 默认 disabled，只有测试显式构造 fake/temp-root/in-memory ports 时才会执行；facade 默认拒绝 production execution，未接入任何真实 trigger 或 runtime switch。

2026-06-02 Canonical Shadow Migration Wiring v1 新增默认关闭的 shadow migration 配置、双端 shadow port factory、iPhone `performTick` 诊断 seam、Mac `/sync/inventory` 诊断 seam、network-probe policy 和 redacted/bounded migration diagnostics。该 wiring 只消费已经加载的 `LocalNetworkSyncInventory.canonicalManifest` 与 legacy diff facts；不扫描额外目录、不计算额外大文件 hash、不发送真实网络 probe、不写真实 store、不上传、不调用真实 apply，也不改变 legacy plan 或 inventory response。`productionExecute` 仍只允许 testHarness 测试路径，iPhone/Mac 角色会返回 `blockedProductionExecute`。

2026-06-02 Canonical Execution Shadow Preparation v1 新增执行级 shadow 排练、双端 shadow file/transport ports、shadow upload/apply rehearsal 和 seam tests。该层默认关闭，只在 shadow root/shadow receiver/in-memory apply store/read-only transport projection 中验证执行边界；未接入真实 store、真实 route、真实 upload/apply、runtime switch、UI、retry drainer 或 Mac pending sync。

2026-06-02 Canonical Recording Metadata Single-Domain Shadow Enablement v1 新增默认关闭的 `recordingMetadata` 单域执行 shadow 开关、in-memory metadata shadow store、apply/send/tombstone marker rehearsal、pre/postcondition、rollback checkpoint 摘要、方向等价/分歧报告和 bounded diagnostics。iPhone seam 复用 tick 中已经加载的 local/peer canonical manifest、canonical sync/apply plan 和 legacy diff facts；Mac `/sync/inventory` seam 目前只有本地 snapshot，显式启用后会记录 `insufficientPeerSnapshot` 且继续返回 inventory。该层不读写真实 metadata JSON，不新增 route，不调用 `/sync/apply-metadata`、`applySyncManifest`、upload client 或真实 store，不改变 legacy plan、pending count、inventory response、receive.json、UI、retry drainer 或 Mac pending sync。

2026-06-03 Canonical Real-Data Execution Shadow & Read-Only Transport Probe v1 新增默认关闭的真实数据 shadow copy 证据层、shadow root lifecycle/cleanup 和更窄的 read-only transport probe contract。iPhone/Mac adapter 只使用调用方已经加载的 recording/receive/inbox/inventory/study facts，把 metadata、receive record、study/inventory JSON evidence 和显式 generated artifact 复制到临时 shadow root；audio 默认只写 descriptor evidence，不复制真实音频字节。shadow root cleanup 默认立即清理，可显式 bounded retain diagnostics；cleanup 会拒绝 production root 或 production root 子路径。transport probe 默认 disabled 且默认 network suppressed，只接受 health/fingerprint/sync status/sync inventory/device status，artifact request 需要显式 bounded allow；upload/apply/pair/mutating route 均拒绝，`manifestHash` 只能作为 integrity evidence，不能替代 TLS pinning、HMAC、nonce、body hash、signature 或 `RequestVerifier`。本轮没有切 production、没有真实网络发送、没有真实 upload/apply/store 写入、没有改 UI/retry/Mac pending sync/route/security。

2026-06-03 Canonical v8.0 Recording Metadata No-Commit App Seam 新增默认关闭的 `recordingMetadata` app seam，只允许 `guardedExecuteNoCommit`。共享 runner 会 gate 掉 commit/production/canary mode、非 recordingMetadata domain、view refresh、retry drainer fresh metadata、缺 local/peer snapshot、证据不足、unsupported action、unstable hash 和 unresolved conflict；allowed 时只调用 no-commit executor 写临时 staging summary，并比较 canonical apply/send 与 legacy direction/object/hash/modifiedAt/tombstone/route/payload evidence。iPhone `performTick` seam 位于 legacy diff 之后、canonical/legacy plan 选择之前，只记录 `canonicalV8*` diagnostics，不改变 plan、pending count、upload client、apply client、retry、UI 或 store。Mac `/sync/inventory` seam 只有本地 canonical snapshot，启用后记录 `insufficientPeerSnapshot`，仍返回原 inventory response。该层不调用旧 cutover commit runner、不 suppress legacy duplicate、不写 production store、不发真实网络、不调用 `applySyncManifest`、不改 route/security/receive.json/audio/generated/folder/studyItem 域。

2026-06-03 Canonical v8.1 Read-Only Transport Probe Live Wiring 新增默认关闭的 live read-only probe。共享 policy 支持 `disabled`、`classifyOnly`、`buildSignedEnvelopeOnly`、`sendReadOnlyProbe` 和 `blockedMutatingRoute`；默认不分类、不构造 envelope、不发送。iPhone sender 复用 `SecureMacUploadClient` 的 signed JSON request、TLS pinning、HMAC、timestamp、nonce 和 body hash 语义；`buildSignedEnvelopeOnly` 只构造并审计 envelope，`sendReadOnlyProbe` 仅在显式 internal config 下发送。Mac receiver 只对带 probe marker 的现有 route 做 audit，不新增 route、不扩大 mutating allowlist；marked `/sync/inventory` 通过 `RequestVerifier` 后走只读 inventory response，并记录 receive record/upload session/pending sync/study manifest snapshot 的 pre/post 对比。`/device/status`、`/sync/status` 和上传/apply/pair 等源码可见会改状态或属于 mutating，因此 live probe denylist 拒绝；`/sync/artifact-request` 只有 explicit bounded artifact flag 才允许分类通过，默认不真实 fetch。probe failure 全部 nonfatal，只写 redacted diagnostics，不写 receive.json、upload session、study store、pending sync、UI、request/response body、完整 hash、secret 或完整 fingerprint。

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
- 本地网络同步：iPhone active 时通过 heartbeat、inventory、metadata/artifact diff、artifact download、缺失 audio upload 和 retry drainer 进行同步；Git-backed sync 默认禁用。Canonical Kernel Completion v1 在双端 canonical manifest 有效时接管 recording metadata diff、audio bootstrap candidate、Mac generated artifact transfer decision、folder/study item metadata/tombstone planning 与 metadata manifest 桥接；缺失或不兼容时回退 legacy plan。
- Canonical Shadow/Diagnostics：iPhone sync tick 与 Mac `/sync/inventory` 会基于已经加载的旧模型事实生成 canonical manifest、shadow report、inventory coverage、transfer state projection、object projection 和 readiness 诊断；这些报告仅用于观察，不驱动 UI/retry/Mac pending sync/receive 写入；generated artifact/library object 诊断只写 kind、size、hash prefix、object id 和 logical name 等安全字段。
- Canonical Runtime Kernel Offline：共享 SyncCore 现在有可测试的离线 file/transport/upload/apply/conflict/harness runtime，可验证 root token/path 安全、hash/size 前后校验、no-overwrite/idempotent write、soft tombstone、route allowlist/capability/body hash/idempotency、resumable chunk offset/retry/finalize、generated artifact download/apply、metadata blob apply/send 和 unresolved conflict policy。该能力仍是离线 harness，不是生产 runtime owner。
- Canonical Production Ports/Dry-Run：共享 SyncCore 现在有生产 port contract、redacted diagnostics、dry-run migration planner、legacy equivalence report 和 migration gate；iPhone/Mac 端有 read-only snapshot adapter 与 suppressed dry-run ports。该能力只证明迁移准备度，不写真实数据、不发真实网络、不上传、不调用 `applySyncManifest`，也不能切换 runtime。
- Canonical Production Runtime API：共享 SyncCore 现在有 `CanonicalKernelFacade` 稳定调用面、真实生产端口方法合同、production execution guard、rollback plan/audit/result、redacted side-effect trace 和 guarded fake-port 测试。该能力只定义外部 API 和迁移安全门，不是生产 adapter 或生产切换。
- Canonical Production Adapter Skeletons/Migration Facade：iPhone/Mac app target 现在有 production file/transport/upload/apply adapter skeleton 与 migration facade。默认 disabled，fake/temp-root/in-memory 只用于测试；不接入 `performTick`、真实 HTTPS route、真实 upload client、真实 store、UI、retry drainer 或 Mac pending sync。
- Canonical Shadow Migration Wiring：共享 SyncCore 现在有 shadow migration mode/config/policy、suppressed side-effect summary、redacted event/report、read-only network-probe policy 和 JSONL writer；iPhone/Mac 现在有 shadow port factory，iPhone tick 与 Mac inventory 可在显式启用时记录 shadow migration started/suppressed/completed/blocked/divergence/equivalent 事件。默认配置不记录、不执行；启用后仍只做 dry-run/diagnostics，不驱动任何业务行为。
- Canonical Execution Shadow Preparation：共享 SyncCore 现在可在显式 shadow mode 下排练 file/upload/apply/rollback 和 read-only transport projection；双端 shadow file/transport ports 只能写 shadow root 或构造 suppressed probe。该能力不写真实 store、不发真实网络、不上传、不调用真实 apply，不改变 legacy plan、Mac inventory response、retry、pending sync 或 UI。
- Canonical Real-Data Execution Shadow & Read-Only Transport Probe：共享 SyncCore 现在有 real-data shadow copy policy/runner/result、shadow root cleanup/retention summary 和 read-only transport probe allowlist/denylist；双端 adapter 可把已加载 metadata/receive/inbox/inventory/study facts 与显式 generated artifact 写入 shadow root，并用 descriptor-only audio evidence 避免默认复制音频字节。该能力默认 disabled，结果只进入 diagnostics/equivalence report，不驱动 legacy plan、network send、upload/apply/store、UI、retry 或 pending sync。
- Canonical Recording Metadata Single-Domain Shadow：共享 SyncCore 现在有 `CanonicalSingleDomainShadowConfiguration`、`CanonicalRecordingMetadataExecutionShadowPlanner` 和 in-memory `CanonicalRecordingMetadataShadowStore`，可在显式启用 `recordingMetadata` 时排练 metadata apply/send/tombstone marker，并记录 no-op、equivalent、canonical more conservative/aggressive、conflict 和 production execute blocked 诊断。默认 disabled；非 `recordingMetadata` domain 不会触发该 shadow。
- Canonical v8 Recording Metadata No-Commit App Seam：共享 SyncCore 现在有 `CanonicalCutoverAppSeamConfiguration`、`CanonicalRecordingMetadataNoCommitRunner`、no-commit equivalence/result/diagnostics、v8.2 staging root lifecycle/cleanup/evidence report/migration stage descriptor，以及双端 staging executor。默认 disabled；显式 enabled 也只允许 `guardedExecuteNoCommit`，只对 `recordingMetadataApply` / `recordingMetadataSend` candidate 做 staging 与等价诊断，默认 cleanup staging root，保留 legacy fallback，不做 production commit 或 duplicate suppression。
- Canonical v8.6 Recording Metadata Guarded Commit App Seam：共享 SyncCore 现在有 `CanonicalRecordingMetadataGuardedCommitSeam`、guarded commit gate/evidence report/canary policy/diagnostics；iPhone tick 和 Mac inventory 只在显式 `guardedExecuteCommit` 或 `canaryCommit` 配置下记录 report。默认 disabled；`N=0` 时不持有 executor，不调用 production port，不执行 commit，不 suppress legacy duplicate。
- Canonical v8.7 Recording Metadata Canary N=1：共享 SyncCore 现在有 `CanonicalRecordingMetadataCanarySelector`、canary blocker taxonomy、N=1 observation report 和 N>1 hard blocker；`CanonicalSingleDomainCutoverConfiguration.canary(maxObjects:)` 默认仍不允许内部执行。只有显式 `allowsV87CanaryN1InternalExecution=true` 且预算正好为 1 时，iPhone `performTick` 可通过注入的 `CanonicalRecordingMetadataCutoverExecutor` 执行一个 `recordingMetadataApply` 或 `recordingMetadataSend` candidate。成功后只 suppress 同 object/action 的最终 metadata plan action；失败/rollback/fallback 不 suppress。Mac 侧仍 report-only，不新增 route 或安全边界变化。
- Canonical v8.17 LibraryMetadata Read-Side Pilot Completion：共享 SyncCore 现在有 `CanonicalLibraryMetadataReadProjection`、read-side parallel diff、read cutover candidate evaluator、write-side evidence linkage 和 report-only retirement evaluator；iPhone/Mac app target 有默认关闭的 read-side seam。该能力只记录 metadata-only diff/candidate/fallback/retirement diagnostics，不切 read path/UI，不触发 sync/upload，不删除 legacy，不移动资源或写 note content。
- Canonical v8.1 Live Read-Only Transport Probe：共享 SyncCore 现在有 live probe mode/policy/gate/result/failure/diagnostic taxonomy；iPhone `performTick` seam 可通过显式 internal config 调用 live sender；Mac `SecureReceiverService` 可透传默认关闭的 probe policy 给 `SecureLocalHTTPSServer`，server 对 marked request 记录 RequestVerifier boundary 与 no-mutation audit。该能力不是 cutover，不改变 legacy/canonical plan、route、security、upload/apply/store、pending sync、retry、UI 或 runtime switch。
- Live Activity：iPhone app 与 extension 共享 `RecordingLiveActivityAttributes`。

## 当前未完成或占位能力

- `TranscriptionQueue` 当前是占位状态对象，真实任务调度在 `TranscriptionCoordinator`。
- `TranscriptionProviderKind` 中存在 `mlxWhisper`、`localHTTP`、`cloudAPI`、`customCommand` 等 provider kind，但 `TranscriptionCoordinator.currentProvider()` 对这些路径抛 unsupported。
- Git-backed study sync 默认禁用；相关 store、endpoint 和测试存在，但不是默认运行路径。
- UI tests 主要是 Xcode 模板级 launch/performance，尚未覆盖真实录音、配对、上传、转写、笔记、学习库和聊天流程。
- CI/自动化构建入口未发现；当前确认的是 Xcode scheme 和本地命令。

## 当前已知 bug / 风险

- 本轮 Canonical Kernel Completion v1 变更新增源码/测试/文档文件；后续任务开始前仍需重新执行 `git status --short`，避免混入未提交工作。
- Canonical Runtime Kernel Offline Completion v1 新增的 runtime/harness 目前只由单元测试覆盖；真实 iPhone/Mac 同步仍由 legacy 网络、上传、接收、store 和 apply 路径负责。不要把 runtime readiness 通过解读为可以删除或停用 legacy。
- Canonical Production Ports & Dry-Run Migration Readiness v1 仍是 audit-only：port declared、dry-run equivalent 或 manual migration design eligible 都不能解释为生产迁移完成；legacy retirement 仍未发生，runtime switch gate 仍关闭。
- Canonical Production Runtime API & Port Contract v1 仍是 contract-only：`CanonicalKernelFacade.executeProduction` 需要显式 production token、owner approval、rollback plan、dry-run equivalence、non-dry-run ports 和 migration gate 放行；当前真实 app 没有任何 trigger 调用它，fake production ports 只用于测试合同。
- Canonical Production Adapter Skeletons & Migration Facade v1 仍是 skeleton-only：file/transport/upload/apply adapter 默认 disabled，测试 fake mode 不能解释为可替换真实 `AudioFileStore`、`MacRecordingFileStore`、`SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier`、`RecordingUploadCoordinator`、`RecordingUploadClient` 或 `StudyLibraryStore.applySyncManifest`。
- Canonical Shadow Migration Wiring v1 仍是 default-off shadow-only：diagnostics-only/dry-run/shadow read-only 都不能解释为 runtime switch、legacy retired、production execute 或真实 network probe 已启用。Mac inventory 请求没有 peer canonical snapshot，dry-run mode 应记录 `insufficientPeerSnapshot` 且继续返回 inventory。
- Canonical Execution Shadow Preparation v1 仍是 default-off shadow rehearsal：shadow root 写入、shadow receiver upload、in-memory apply 和 read-only transport projection 只能证明执行级排练可观测，不能解释为真实 production store、route、upload/apply 或 runtime owner 已迁移；decision shadow green 也不等于 execution shadow 或 production execute 可放行。
- Canonical Real-Data Execution Shadow & Read-Only Transport Probe v1 仍是 default-off 证据层：real-data copy 只能写 shadow root，audio 默认 descriptor-only，cleanup 只能处理 shadow root；read-only probe 默认不发网，且 route allowlist/denylist 不能替代 `SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier`、TLS pinning、HMAC、nonce、body hash 或 signature。shadow root retained diagnostics 不得包含完整路径、完整 hash、secret、fingerprint、request/response body、transcript/note/summary/provider response。
- Canonical Recording Metadata Single-Domain Shadow v1 仍是 default-off 单域 shadow：即使 `recordingMetadata` 显式启用，也只写 in-memory shadow record 和安全诊断；canonical 更激进 apply/send 默认 blocking，metadata conflict 和 active-vs-tombstone conflict 不 apply/send，tombstone 只写 marker，不做物理删除或真实 metadata 写入。
- Canonical v8.0/v8.2 Recording Metadata NoCommit App Seam 仍是 default-off diagnostics/staging seam：v8.2 cleanup/evidence/config consolidation 只能作为 future gate evidence 输入，不能把 `guardedExecuteNoCommit` 解释成 production cutover、canary、legacy replacement、duplicate suppression、真实 `/sync/apply-metadata`、真实 `applySyncManifest` 或 store/network/apply/upload 写入；Mac 端缺 peer snapshot 是预期的 nonfatal blocked diagnostic。
- Canonical v8.6 Guarded Commit App Seam 仍是 default-off diagnostics/evidence seam：`N=0` 只会评估 gate 和 report，不能解释成 production commit、runtime switch、legacy replacement、duplicate suppression、真实 network send、真实 root-bound apply、`applySyncManifest` 或 app default store 写入；Mac 端缺 peer snapshot 仍是 nonfatal blocked diagnostic。
- Canonical v8.7 Recording Metadata Canary N=1 仍是 explicit internal canary：默认 `N=0`，`N=1` 没有 `allowsV87CanaryN1InternalExecution` 必须 blocked，`N>1` 必须 blocked。canary 只限 iPhone tick 中的 `recordingMetadata` 单对象；不扩大到 audio/generated/folder/studyItem/tombstone/conflict/UI/retry/Mac pending sync，也不改变 `/sync/apply-metadata`、`RequestVerifier`、TLS/HMAC/nonce/body hash 或 Mac inventory response。
- Canonical v8.17 LibraryMetadata Read-Side Pilot Completion 仍是 default-off evidence/report 层：`parallelOnly` 只生成 read diff，`canonicalReadCandidate`/`guardedCanonicalRead` 也只输出 candidate/blocker/diagnostics，并显式保持 `readPathSwitched=false`、`uiMutated=false`、`syncOrUploadTriggered=false`。clean diff、write-side staged canary evidence 或 retirement candidate 不能解释为 UI/read owner 已切换或 legacy 可删除。
- Canonical v8.1 Read-Only Transport Probe Live Wiring 仍是 default-off diagnostics/live probe seam：只有 explicit internal config 才能发送 marked signed read-only request；marked mutating/unknown/default-disabled route 必须 blocked。该 probe 不新增真实 route、不绕过 `RequestVerifier`、不把 manifestHash 当 auth、不写 receive.json/upload session/study store/pending sync，也不能解释为 production cutover、runtime switch、legacy replacement、upload migration 或 apply migration。
- 本地网络同步仍需真机验证：Mac 手动同步依赖 iPhone 前台 heartbeat，peer metadata-only/missing 会按 inventory 补音频，retry drainer 依赖 scheduler gate 和 backoff。
- 同步 UI 卡顿风险已降低但未消除：audio SHA256 已加 checksum cache/off-main 计算，学习库 manifest、录音 reload、Mac inbox 扫描和诊断写入仍可能成为大库瓶颈。
- Mac build phase 和 `Scripts/embed_whisper_helper.sh` 依赖仓库外本地 whisper.cpp 产物或 `WHISPER_CPP_ROOT`；不同机器可能无法直接构建 Mac app。
- iPhone/Mac 双端有部分同名但不完全一致的模型文件，改同步协议或存储 schema 时容易单端遗漏。
- 转写、笔记、聊天会写 Application Support / Documents 下真实用户数据；调试时不能随意删除、重置或迁移这些目录。
- 文档中不记录完整本机私有路径、密钥、指纹或 shared secret；源码和脚本中如已有本机路径，只在文档中抽象描述。
- UI 测试覆盖较弱，视觉/交互回归更多依赖手动验证和现有截图资产。

## 当前优先级建议

1. 先在真实 iPhone/Mac 同步中验证 Canonical Kernel Completion v1：canonical metadata same hash 是否 no-op、modifiedAt 是否正确决定方向、peer object absent/metadata-only/missing 是否只触发现有上传主路径、peer unknown 是否 deferred、Mac generated transcript/note/summary 是否通过现有 artifact request/apply 通道下载，folder/study item metadata/tombstone 是否只通过既有 metadata manifest bridge 执行。
2. 若继续推进 canonical 生产迁移，先写迁移设计和 rollback/shadow 方案，再实现真正 root-bound production adapter；不得直接把 dry-run ports、offline runtime 或 `CanonicalKernelFacade.executeProduction` 接入 `performTick`、真实 route、真实 upload client、真实 store 或 UI。
3. 若继续推进 shadow migration，下一步应先在真实设备上观察 `recordingMetadata` 单域 shadow diagnostics，确认 no-op/apply/send/conflict/tombstone/equivalence 与 legacy 行为一致；不应直接 cutover。
4. 若继续推进 execution shadow，下一步应先做 controlled real-root execution/canary 设计、人工批准、rollback 和真实设备验证计划；不要把本轮 shadow copy/probe 结果直接接入 production runtime、UI canonical read 或 legacy retirement。
5. 若继续推进 `libraryMetadata` pilot，下一步只能在真实设备/真实数据上观察 v8.17 read-side parallel diff 与 v8.16 staged write-side evidence 的关联，确认 divergence 为 0、fallback 可用、diagnostics redacted、Mac report-only 边界稳定；不得直接切 UI/read path、默认启用 guarded read、删除 legacy 或扩到其它 domain。
6. 为 Mac build phase 补充可复现的 whisper.cpp 依赖说明或 CI 友好方案，但不要在未确认前改脚本。
7. 若继续改同步协议，先补齐 iPhone/Mac 双端模型兼容测试，再改实现。
8. 若继续改 UI，优先补关键 flow 的 UI/manual 验证记录。

## 文档可信度说明

- 高可信：target/scheme、入口文件、核心 Swift 类型、路径约定、测试目录、已存在 build phase、权限配置。
- 中等可信：手动验证矩阵、推荐命令；部分命令未实际运行构建/测试，只依据 Xcode scheme 和配置推导。
- 需要后续确认：CI 环境、具体可用 iOS simulator 名称、whisper.cpp 依赖安装约定、视觉诊断资产生命周期。

## 源码与旧文档冲突记录

- 旧文档曾写 Mac TLS private key 在 Data Protection Keychain 中；当前源码 `MacIdentityManager` 实际使用 app-local `tls-private-key.json` 加 `SecIdentityCreate(nil, certificate, privateKey)`，测试也固定该行为。因此本轮文档改以源码为准，并把 Keychain 说法降为已纠正的旧文档冲突。
- 已有 `docs/LongRecordingTestPlan.md` 与当前 `LongProcessingModels.swift`、`TranscriptionCoordinator.swift`、`NoteGenerationCoordinator.swift` 的长录音分块思路总体一致；未发现需要在本轮标记的冲突。
- 发现构建配置/脚本中存在仓库外本地 whisper.cpp 路径依赖。为避免写入个人隐私路径，本文档只记录抽象依赖，不复制具体本机路径。

## 2026-07-10 连接/同步/文件传输正确性收口

- iPhone `LocalNetworkSyncEngine.performTick` 已重新接入 artifact upload/download 和缺失 recording audio upload。只有 metadata apply、artifact、audio 全部完成且无 unresolved conflict/partial failure 时，才写 `lastSuccessfulSyncAt` 和 `syncRunCompleted`。
- legacy `StudyLibrarySyncCoordinator.performSync` 不再跳过 pending recording upload，也会验证双端 apply result。
- Release 默认使用 old kernel；Debug 只允许在有效 stored mode 且手动确认后启用试验 canonical mode。非法/缺失配置回退 old kernel。
- rename 会推进单调业务时间；restore 会清除 StudyItem tombstone/trashedAt。无持久 StudyItem 时，fallback metadata 使用 recording/inbox 中的稳定时间，不再使用每轮 `Date()`。
- 配对为两阶段 prepare/confirm：iPhone 先保存 credential，再确认 Mac commit；确认 response 丢失时，可用已签名 heartbeat proof 恢复。Mac paired-store 持久化失败会回滚并拒绝成功。
- Mac payload 使用稳定 `.local` hostname，并广播 `_rokurics._tcp`；IPv4 仅为 fallback。iPhone host normalization 支持 IPv6 authority。
- Mac manual sync-start signal 会持久保存并重投到匹配 ACK；iPhone 先入队 sync 再 ACK。ACK 失败不影响已经建立的 online presence。
- status exchange facts/request 保留到明确 ACK，并有 fact/byte batch 上限和 sender incarnation。重启后的 sequence 不再与旧 incarnation 冲突，纯 ACK 不产生 ACK loop。
- upload/transfer ledger 按当前 peer device 过滤；重配到新 Mac 会重置旧 target 的 completed/session stage。
- artifact resume 与 checksum/size 版本绑定；错误 full-size temp 会删除；`.resuming` 的 full-size offset 不能替代 server final apply ACK。
- stale/incompatible audio session 会过期并重建；自动 retry 上限为 8。音频 progress task 在写最终状态前必须停止，避免 `.complete` 被回写成 `.transferring`。
- 2026-07-10 已通过 iOS/Mac build-for-testing、iOS/Mac Release build、25 项 iOS 定向测试和 16 项 Mac 定向测试。仍无 paired 真机证据；网络切换、首次权限、后台/锁屏、长录音和 soak test 仍待验证。
- Mac pairing listener 现在只在明确 `EADDRINUSE` 时将候选端口逐次加一：8787 失败后显示并保存 8788，用户下次点击配对时尝试 8788；再次占用则变为 8789。一般 TLS/listener 错误不会错误换端口。
- 动态候选端口按 Mac app profile 持久化，重启后继续使用已经复制给 iPhone 的端口。
- Mac pairing payload 和复制文本始终使用 ready listener 的实际 active port；iPhone 粘贴解析使用文本中的动态 `Port:`，不会被默认 8787 覆盖。

## 2026-07-11 同步稳定性修复后的当前状态

- iPhone 与 Mac 的 recording、study item、folder inventory 已统一使用 `LocalNetworkBusinessSignatureV2`。签名带 `ln-business-v2:` 版本前缀，只覆盖跨设备稳定的业务字段，并对文本、tag 和集合顺序做确定性归一化；时间戳、本机路径、处理/上传/冲突状态以及可从关系重建的派生列表均不进入签名。
- `explicitBusinessCustomPropertyKeys` 当前为空，因此生产 V2 签名和业务 merge 不接受任意 custom property。以后若要同步某个 custom key，必须显式加入白名单、评估版本兼容并补双端 fixture。
- “内容是否相同”和“谁更新”已拆开：V2 签名只回答业务等价，`updatedAt`/`modifiedAt` 作为独立的持久业务时钟决定 apply 方向；接收时间、processing 状态、upload ledger、UI 状态等运行时事实不再推进业务版本。远端时钟较新才覆盖，时钟相等但 V2 业务内容不同仍报告冲突。
- canonical wire timestamp 在创建和解码时统一向下归一到整秒，匹配 JSON `.iso8601` 精度，避免同一 manifest 经 encode/decode 后 hash 漂移。
- metadata apply/upload 会把完整 manifest 裁剪为 action-scoped manifest，只携带本轮 action 直接涉及及 item↔recording 关系扩展后的对象、tombstone、pending upload 和 recording facts。计划要求的 manifest/payload 缺失会直接失败，不再静默跳过。
- 冲突对象及其依赖对象会先从可执行计划隔离；不相关的 metadata、artifact、audio 安全动作仍可继续。安全动作完成后，原始 conflict 仍使本轮以 unresolved conflict 结束，不会写 `lastSuccessfulSyncAt`。
- recording existence 已改为证据模型：parent tombstone 优先阻止 apply/upload/复活；metadata-only、receive record、study item 或 completed ledger 都不是音频存在证明；只有匹配的 hash+byte-size、finalize proof 等内容级证据才允许 audio same no-op。Mac inbox 只有 `hasAudio` 的记录才可参与音频证明。
- sync run store 记录有限集合的 superseded runID。新一轮开始可取代旧轮；旧轮后到的进度、success 或 failure 均被拒绝。iPhone heartbeat 携带当前 `LocalNetworkSyncRunStatus`，Mac 只接受符合当前 runID/代际的进度或终态，从而补齐 ACK/terminal response 丢失后的状态收敛；heartbeat 在线本身仍不等于同步成功。
- 连接诊断队列现区分 normal/critical。带 error code 的事件，以及 sync run/tick、upload/finalize、metadata apply 的成功或失败终态均为 critical；队列满时 critical 优先驱逐 normal，而后续 normal 不能驱逐 critical。优先级不绕过既有 redaction。
- 自动化已覆盖 V2 归一化和版本前缀、双端同 fixture 的跨设备等价、merge 保留本机字段、整秒 round-trip、action-scoped manifest、冲突隔离、tombstone/existence/audio proof、run supersede/heartbeat 和诊断优先级。仍需 paired 真机验证同库跨设备 V2 一致、旧版与 V2 混跑的一次性 diff、冲突伴随安全动作、metadata-only 到音频证明闭环，以及后台/网络切换下 run 收敛。

### 2026-07-11 最终修复补记

- action-scoped recording manifest 现在必须由同 ID 的 active/tombstoned recording 或有效 deletion tombstone 覆盖；StudyItem、pending upload 或其他关系记录不能替代 recording 本体。artifact conflict 找不到 owner 时执行计划 fail closed，不再让未知依赖动作继续。
- iPhone 与 Mac 都把 `syncedMetadataOnly` 作为 receiver-local receipt marker：业务相等或 peer 时钟不同都不会把另一端的 marker 覆盖到本机；真实音频出现时本机清除。foreground/background pending upload builder 通过 recordingID 反查并保留真实 StudyItem ID。
- iPhone 的两个 sync-start 消费者分别使用原子持久化 FIFO。pending/in-flight/completed、生命周期去重和重启保守重放均落盘；enqueue 持久化失败会内存回滚并拒绝 ACK，in-flight 重启后回到队首。
- Mac metadata apply 使用 lease 暂停 watchdog；apply 后刷新进度时间并恢复监督。同一 run 采用 first-terminal-wins，旧 run 迟到终态不能覆盖新 run。Mac inbox 更新通知在主线程同步刷新，metadata+audio route 完成后 UI/store 无需重启即可看见新状态。
- pairing 只在 confirm 或已签名 proof 成功后保存 iPhone connection snapshot；Mac 只有确认 durable paired-store 成功才返回完成。续传内容合同变化会启动新 session，损坏的 upload ledger 可隔离错误记录并从真实文件/metadata 重建。
- 当前代码级正常路径阻碍已闭环。iOS 主测试类记录 193 项、0 failure（3 项明确 skip）；Mac metadata/existence/manifest 相关 suite 45 项通过，另有 6 项真实 listener/route/control-plane 串行回归通过；iOS Simulator 与 macOS Debug build 均退出 0。仍缺 paired 真机、Release、TSan、弱网/后台和 soak 证据。
