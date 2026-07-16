# ARCHITECTURE

最近自查日期：2026-07-12

## 双端交换产品契约：连接、同步、上传（2026-07-12）

本节是 iPhone 与 Mac 双端交换的产品级权威定义。本文及其他项目文档中较早的 `fullSync`、canonical sync、metadata apply、artifact download、audio bootstrap 等历史描述，只用于记录历史实现，不得覆盖本节对“连接”“同步”“上传”的定义。2026-07-12 源码已按本节完成拆层；真机运行只用于补充体验与网络证据，不是源码修复未完成项，见 `CURRENT_STATE.md` 和 `SYNC_STATE_AUDIT.md`。

| 层次 | 用户入口/触发 | 允许交换的内容 | 允许的副作用 | 成功含义 |
| --- | --- | --- | --- | --- |
| 连接（Connection） | 配对后的连接检查、heartbeat | 建立可信通信所需的短握手、身份、能力和在线状态字段 | 更新连接/presence 状态 | 两端可以在现有 TLS pinning、HMAC、timestamp、nonce、body hash 和 `RequestVerifier` 边界内通信 |
| 同步（Sync） | 连接页“立即同步” | 学习库 inventory：稳定对象/文件标识、逻辑文件名、内容 hash、byte size、业务修改时间、版本、tombstone/删除标记及计算 diff 所需的最小字段 | 更新 sync run、快照、差异结果和逐对象 reconciliation record；不写学习库内容 | 按稳定 ID 和 LWW 产出差异、source、target 与待传输/待更新标记 |
| 上传（Upload / Content Transfer） | 用户在来源端学习库对同步选定版本点击“上传” | 实际文件 bytes，以及完成该次内容传输所必需的校验、分块、续传和 finalize 字段 | 消费 reconciliation record，将内容从 source 传到 target，并在校验成功后落盘和写完成证明 | 目标端已接收并校验同步层选定的版本；下一轮一致性同步清除标记 |

连接层不得扫描学习库、构建 inventory、计算文件 hash、读写学习库对象或创建上传任务。连接成功只证明可通信，不证明同步成功，也不证明任一文件存在于对端。

同步层对学习库内容是只读发现过程，不是数据应用过程；仅 reconciliation ledger 属于允许的同步状态写入：

- 每端每个 `syncRunID` 至多构建一个一致性 inventory snapshot，并只执行一次业务 diff；同一轮中的响应和汇总诊断必须复用结果，不得再跑 canonical/legacy 双 planner、shadow migration，也不得为每个对象或 artifact 重建全库 inventory。
- 文件未变化时必须复用持久 checksum cache；cache key 至少受稳定逻辑标识、byte size、业务/文件修改事实、内容版本、算法和 schema 约束。只有 cache miss 或已证实失效的条目才允许离主线程重新读取内容计算 hash。
- wire payload 只能随对象数量和短 metadata 增长，不能随音频、转写、笔记或其他文件内容大小增长；不得包含 `dataBase64`、文件 bytes、正文或 provider response。
- diff 必须先按稳定 `objectID` 对齐，再把新增、删除、内容 hash 不同、rename-only、相同、时间并列和信息不足分别表示。稳定 ID 相同即为同一业务对象，名称和内容变化都只是版本变化。
- 两端版本可比较时统一采用业务 `modifiedAt` 的 Last-Write-Wins：较新端为 source、较旧端为 target；即使双方都修改也不因此自动成为 conflict。hash 不同且时间相同，或内容对象缺 hash/size 时必须 deferred，禁止静默覆盖。删除必须依赖 tombstone/版本事实，不能仅凭某端暂时缺少对象就执行删除。
- 双端对同一对 inventory 必须运行同一 `SyncReconciliationPlanner`，得到方向无关的确定性 record ID、source、target、expected hash/size/modifiedAt 和 reason。两端分别把相关记录原子写入 `Sync/Reconciliation/records.json`；存储有 schema version、上限和损坏 fail-closed 行为，不保存文件内容、绝对路径或凭据。
- 同步不得调用 metadata apply、artifact request/put、recording audio upload/download、学习库/内容文件写入、placeholder 创建、学习库 merge/save、物理删除、上传 retry drainer 或内容 finalize。
- conflict 是成功同步得到的一类差异结果，不是同步传输失败。同步失败只表示连接/鉴权、inventory 构建、协议解码/校验或 diff 计算本身未能完成。
- “立即同步”完成后只能展示或持久化差异与待处理标记；不得自动传输文件或执行这些差异。

上传层是独立的双向内容传输状态机。产品文案沿用“上传”，但架构含义是用户明确触发的 selected-content transfer，并不限定为 iPhone -> Mac。按钮只能读取当前设备为 `sourceDeviceID` 的有效 reconciliation record；目标端只显示等待接收，不得反向猜测方向。创建 job 前必须对来源 hash/size/modifiedAt 做 CAS 校验，job 必须保存 record ID 和目标旧版本 proof；目标端安装前再次校验 expected target，完成 checksum/size/finalize 后将记录推进为 `transferredAwaitingVerification`。来源版本已改变则标记 `staleSourceVersion` 并要求重同步。上传失败不得把已经成功产出 diff 的同步改写为失败。

Mac -> iPhone 仍保持网络拓扑为 iPhone client -> Mac HTTPS server：Mac 按钮创建 durable offer，已验证 heartbeat 只携带 transfer ID、方向、对象 ID、hash、size 等短 descriptor；iPhone 收到后通过独立 `/upload/mac-to-iphone/chunk` 拉取内容并以 `/upload/mac-to-iphone/ack` 提交最终 checksum/size proof。此设计不是 Mac 反向连接，也不属于 sync payload。

UI 语义必须固定：连接页“立即同步”只运行 inventory exchange + diff；学习库内“上传”才允许运行文件内容传输。后台 heartbeat、app activation、列表/详情刷新、周期 tick 和普通同步均不得代替用户点击学习库“上传”而创建新的内容传输任务。

## 2026-07-12 开发诊断架构

开发诊断是旁路观察层，不是连接、同步或上传状态机的真相源。iPhone Debug 进程生成 `testRunID`；现有 HTTPS 请求附带可选会话头，Mac 只把它用于选择诊断目录。连接/同步 `syncRunID`、上传 `traceID`、node、subsystem、event、severity 和脱敏 details 被写成统一 JSONL envelope。

写入链路为业务调用点 -> 内存事件 -> 独立 utility serial queue -> session JSONL。队列满、脱敏拒绝和文件写失败都进入 writer health，不改变业务调用返回值。单卷与备份数量有界，不同步重写旧 connection JSONL，不在 MainActor 扫描或解码完整日志。

收集链路独立于局域网同步：Mac 脚本读取本机 app container，并通过 USB `devicectl` 读取 iPhone app data container。因此即使配对、连接或同步本身失败，仍可收集两端证据。该层不读取安全凭据或用户文件内容。

## 2026-07-08 Rokurics v10.0 / Mac 首页与共享录音实时转写架构

v10.0 当前保留的是 UI/本地录音层改动，不改变同步、上传、安全或 canonical runtime 架构。Mac `MacRootView` 默认进入 `MacHomeView`；`MacSidebarItem.home` 只是本地导航项。点击首页的共享录音 orb 会进入 `MacRecordingSessionView`，由 `MacRecordingManager` 在本机请求麦克风权限并使用 `AVAudioRecorder` 录制 m4a。

录音 session UI 由 `RokuricsSharedRecordingSessionSurface` 统一承载。iPhone `RecordingSessionView` 和 Mac `MacRecordingSessionView` 都只注入 elapsed time、暂停/停止状态、错误文本、实时转写文本和平台动作。共享 surface 显示计时卡片、实时转写滚动框、暂停/继续、停止和禁用上传按钮；它不拥有上传、同步、归档或 provider 配置。

Mac 本地录音保存复用现有 inbox 存储语义：`IncomingRecordingMetadata` 先写入 `MacRecordingFileStore.saveMetadata`，音频进入 `temporaryAudioUploadURL`，通过 `checksumForTemporaryAudioUpload(...)` 计算 checksum 后再调用 `saveAudio(temporaryFileURL:)`。该链路写 Mac 本地 inbox 和 transcript，不调用 iPhone upload client，不新增 Mac -> iPhone 连接，不改 `/sync/*`、upload route、`RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain 或 pairing。

实时转写目前是 provider-shaped 的模拟实现。`RokuricsSimulatedLiveTranscriptionSession` 在录音期间定时发布 `RokuricsLiveTranscriptionSnapshot`，用于验证共享 UI 滚动文本和 Mac transcript 持久化链路。Mac 保存时把 snapshot 转成 `TranscriptionResult` 写入 `TranscriptStore` 并更新 receive record 的 transcription status。iPhone 只显示模拟文本，不写 transcript artifact、不改 `RecordingMetadata`、不改上传队列或同步 proof。真实 OpenAI Realtime、FunASR streaming 或 whisper streaming 接入仍是后续独立任务。

此前 no-legacy fallback / canonical runtime / 设置页切换删除方向的改动已恢复到 v9.24，不属于当前 v10.0 架构事实。当前旧内核、fallback、同步/上传/apply/read runtime 的行为以 v9.24 源码为准。

## 2026-06-16 Canonical v9.13 / post-audit real-wiring architecture status

v9.10 post-audit found R4/R6/R3 evidence incomplete. Any older v9.10/v9.12 READY or closure wording is code-level readiness language only and must not be read as four-domain kernel complete, releasable, real-device validated, or legacy-retirement eligible.

v9.13 closes code-level R4/R6/R3 only if tests/grep pass. UI final display must trace to cached `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` snapshots; Connection/Transfer runtime ownership must be real app-path wiring and mode-gated; no-freeze evidence must show UI reads, Store getters, and View refreshes do not reconcile status, write diagnostics synchronously, build manifests, hash files, create upload jobs, or drain retries.

`realDeviceEvidencePresent=false` remains the architecture state until paired iPhone/Mac redacted JSONL is supplied.

## 2026-06-16 Canonical v9.12 / post-v9.10 audit closure architecture

v9.12 closes the remaining post-v9.10 audit rows for R6 and R7 at code level. It does not retire legacy, does not enable release/default canonical, does not add routes, and does not change local HTTPS/TLS/HMAC/pinning/nonce/body-hash or `RequestVerifier` ownership.

Connection ownership is adapter-backed. `CanonicalConnectionRuntime` owns peer liveness, heartbeat envelope, status request, `syncRequested` envelope, status exchange carrier evidence, capability summary and connection diagnostics. Rokurics app paths own concrete transport: iPhone `StudyLibrarySyncCoordinator` carries envelopes over existing `/device/status` and `/connection/heartbeat`; Mac `SecureReceiverService` / `SecureLocalHTTPSServer` records incoming liveness and status requests only after existing verification. Mac remains server-only and never dials the iPhone. Heartbeat callbacks map to enqueue actions only.

Transfer ownership is runtime-backed but transport-adapter-executed. `RecordingUploadCoordinator` enters `CanonicalTransferRuntime` only for allowed `canonicalFullSync`; the runtime owns session start, status refresh/resume, chunk send, monotonic confirmedBytes, duplicate/wrong-offset handling, retry/backoff, finalize and finalize proof. Actual upload still flows through `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient` -> existing Mac upload start/status/chunk/finalize routes. The Mac receive side remains `SecureLocalHTTPSServer` -> `RequestVerifier` -> `MacRecordingFileStore`.

Finalize proof remains a Sync truth input. Receiver accepted proof is produced only after verified finalize with matching byte size and checksum, then merged into `CanonicalStatusTruthRuntime`. `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` remains the UI source; Transfer runtime never marks UI completed directly. Metadata-only, completed ledger alone, partial receive and status ack alone remain non-proof; existing different audio remains conflict/no-overwrite.

The old in-memory production upload ledger is now explicitly test-only. The former `fakeLedger` token was removed from app code. Test-only in-memory upload ports can still be constructed by tests or explicit migration harness port sets, but `CanonicalProductionPortInjectionPolicy` / app fullSync upload path do not select them. `productionUploadPortNotTestOnlyFake=false` is an unsafe final-gate blocker.

R7 gate architecture now expresses the four-domain matrix instead of a single self-reported readiness bool. `CanonicalFourDomainGateEvidence` includes row-level evidence for Connection, Transfer, Sync, File and cross-domain mode boundaries. Missing app runtime references, missing secure upload path, missing finalize proof -> StatusTruth, missing retry existing-only, missing file hot-path guard, missing UI EffectiveStatus binding or missing kernel switch mode boundary fail closed. Unsafe blockers include test-only upload port selected in production fullSync, route/security/RequestVerifier change, Mac reverse connection, heartbeat heavy sync, view refresh upload job, retry storm, proof violation, MainActor hot path violation, diagnostics leak and legacy retirement.

The deterministic two-node harness remains fake but now covers the full R7 core scenario table: metadataOnly + local audio -> transfer/finalize/status exchange/completed; peerUnknown deferred; completed ledger alone rejected; partial receive rejected; existing different audio no-overwrite; generated artifact status delta without provider rerun; cache hit skips hash; diagnostics storm async/backpressure; status exchange duplicate/stale/conflict; and mode sequence `oldKernel -> canonicalShadow -> canonicalDecisionOnly -> canonicalApplyNoAudio -> canonicalFullSync -> oldKernel` with no migration.

`realDeviceEvidencePresent=false` is still the expected architecture state until paired iPhone/Mac redacted JSONL is supplied. `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL` means code-level debug/internal trial readiness only.

## 2026-06-16 Canonical v9.11 / UI EffectiveStatus snapshot and no-freeze evidence architecture

v9.11 tightens the v9.6 UI binding architecture by making cached `CanonicalEffectiveSyncStatus` snapshots the UI/status-model boundary. It does not add visual UI, routes, upload schema, transfer ownership, connection ownership, reverse Mac connection, security bypasses, or default/release canonical behavior. `R6` owner takeover remains out of scope.

The Store/coordinator/service pattern is now explicit: app paths may produce facts asynchronously, then cache `CanonicalStatusTruthRuntime.projectionSnapshot(for:)` into an observable dictionary keyed by `CanonicalObjectID`. UI-facing getters such as `effectiveSyncStatus(for:)`, `canonicalDisplaySyncState(for:)` and `displaySyncState(for:)` are synchronous snapshot reads. They must not await actors, merge facts, reconcile status, build manifests, hash files, read ledgers, write diagnostics, start sync, create upload jobs, drain retry queues, perform file IO or perform network IO.

iPhone status architecture uses `RecordingUploadCoordinator.displaySyncState(for:)` as the existing recording-card/detail status source. When a status truth snapshot exists, the coordinator returns the cached `CanonicalDisplaySyncState`. Without a cached proof it returns a conservative canonical-equivalent display result that keeps oldKernel/fallback behavior visible without promoting legacy `uploaded` or ledger-only state to peerVerified/completed. Explicit ledger snapshot refresh is separate from View reads.

Mac status architecture uses stored display snapshots on `MacRecordingInboxItem` and Store/receiver dictionaries. `MacStudyLibraryView` and `MacAudioInboxView` read `displayAudioAvailable` from that snapshot for existing play/transcribe enablement. Raw `hasAudio`, receive records, metadata-only records and local file existence remain supporting facts, not final audio availability proof.

The proof rule architecture remains centralized in SyncCore. `CanonicalEffectiveStatusUIProjection` can show completed/peerVerified/audioAvailable only for accepted finalize proof, peer inventory hash-size match, same hash+same byteSize no-op proof, or an equivalent proof chain validated by StatusTruth. MetadataOnly, metadataOnly ledger, receiveRecordOnly, completed ledger alone, partialReceive, local file only, expected manifest hash only, peerUnknown and status ack alone are demoted to waiting/deferred/uploading/blocked/conflict display states. Existing different audio remains conflict/no-overwrite and cannot trigger overwrite or forced upload.

No-freeze evidence is now part of the same gate architecture. `CanonicalMainActorHotPathGuard` covers diagnostics write, file tree snapshot, manifest build, full hash, read projection rebuild, status truth reconciliation and effective status projection. `CanonicalFourDomainCompletionGate`, `CanonicalFourDomainEvidencePackage`, `CanonicalFourDomainRealDeviceTrialGate` and `CanonicalFourDomainFinalScorecard` require explicit v9.11 code-level evidence for UI EffectiveStatus binding, no direct View peer proof, no MainActor status reconciliation, no View refresh upload job, async diagnostics hot path and content-stable cache keys.

The trial gate is therefore no longer a hand-filled boolean surface. Missing R4 binding evidence, missing R3 no-freeze evidence, direct View-layer completed/peer proof logic, MainActor status reconciliation attempts, or View refresh upload job attempts block READY or become UNSAFE. R1/R2/R5 green alone is insufficient.

## 2026-06-15 Canonical v9.10 / real-device trial gate, evidence package, cleanup and no-retirement lock architecture

v9.10 adds a report-only trial gate layer above the v9.5-v9.9 code-level evidence. It does not change production runtime ownership, routes, upload schemas, receiver security, pairing, Keychain, file roots, UI layout or default kernel behavior. Default/release remains `oldKernel`, legacy fallback remains mandatory, and no legacy retirement is performed.

`CanonicalFourDomainRealDeviceTrialGate.v910(...)` is a pure value gate. It consumes `CanonicalFourDomainGateEvidence`, a redacted `CanonicalFourDomainEvidencePackage`, a cleanup audit and `CanonicalFourDomainNoRetirementLock`. It never calls sync/upload/read/file/network code and cannot mutate stores, create upload jobs, change routes, bypass `RequestVerifier` or start Mac reverse connections.

The v9.10 status model is intentionally separate from v9.9's internal `READY` / `PARTIAL` / `UNSAFE` harness gate. The external trial gate returns `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`, `PARTIAL_WITH_BLOCKERS`, `NOT_READY` or `UNSAFE_TO_TRY_ON_DEVICE`. Missing build/test summary is `NOT_READY`; missing non-safety domain evidence is `PARTIAL`; safety invariant failures are `UNSAFE`.

`CanonicalFourDomainEvidencePackage` is a redacted evidence envelope, not a diagnostic file writer. It summarizes mode transitions, cache hit/miss/rebuild, diagnostics queue/drop/flush duration, MainActor violation counts, status fact/delta/ack/request counts, proof/rejection counts, route/security unchanged proof, switch-back proof and build/test summary. `CanonicalFourDomainEvidenceRedaction` rejects absolute paths, full hashes, secrets, full fingerprints, full metadata JSON, request/response bodies, raw audio, full transcript/note/summary/provider response and full generated content before any summary is retained.

`CanonicalFourDomainFinalScorecard` combines the v9.10 gate, package, cleanup audit and no-retirement lock for reporting. The lock hard-codes the current non-retirement boundary: `legacyDeleted=false`, `legacyDisabled=false`, `retirementExecutionPerformed=false`, `readyToRetireLegacyReportOnly=false`, release/default `oldKernel`, and `canonicalFullSync` only under debug/internal + owner + manual + all gates.

The cleanup architecture treats v9.10 additions as report-only models, not facades. Existing v9.9 fake harness types remain test-only evidence producers; runtime owner references remain the v9.5-v9.8 app wiring already described below. Portable SyncCore protocols still do not encode Rokurics local HTTPS/TLS/HMAC/pinning/nonce/body-hash/route or `RequestVerifier` details; Rokurics app code remains the adapter layer.

## 2026-06-15 Canonical v9.9 / four-domain gate and deterministic harness architecture

v9.9 adds a code-level four-domain completion gate and a deterministic fake two-node harness. It does not change production runtime ownership, routes, upload schemas, receiver security, pairing, Keychain, file roots, UI layout or default kernel behavior. Default/release remains `oldKernel`, legacy fallback remains mandatory, and `realDeviceEvidencePresent` remains false.

`CanonicalFourDomainCompletionGate.v990(...)` is the code-level gate. It treats Connection, Transfer, Sync and File as first-class domains and checks the required v9.5-v9.8 evidence: async diagnostics hot path, content-stable cache key, status truth off-main projection, UI effective status source cutover, realtime status exchange runtime, connection/transfer owner wiring, default/release oldKernel, legacy fallback, route/security/upload schema unchanged, `RequestVerifier` unchanged, Mac no reverse connection, heartbeat no heavy sync, view refresh no upload job, retry storm guard, diagnostics redaction and oldKernel switch-back proof. Unsafe evidence such as route/security change, default canonical, peer proof violation, MainActor hot-path violation, reverse connection, heartbeat heavy sync, view-refresh upload job, retry storm, diagnostics leak or switch-back failure returns `UNSAFE`. Missing non-safety domain evidence returns `PARTIAL`.

The harness is intentionally fake and portable. `CanonicalFourDomainRuntimeHarness` uses a fake clock, deterministic sequence, `CanonicalFourDomainFakeConnectionCarrier`, `CanonicalFourDomainFakeTransferPort` and `CanonicalFourDomainFakeFileRuntime`. It has no URLSession, Network.framework, file-system root write, production scanner, TLS, HMAC, pinning, nonce, body hash or `RequestVerifier` dependency. Rokurics local HTTPS/TLS/HMAC remains adapter-owned and is not encoded in the canonical protocol.

Fake Connection records only heartbeat/status delta/status ack/syncRequested/proof-request envelopes and counters for enqueue-only behavior, storm coalescing, reverse connection attempts and heartbeat heavy sync attempts. Fake Transfer produces only in-memory receiver accepted finalize proof, partial receive and existing different audio conflict/no-overwrite results. Fake File maintains checksum/read caches and no-freeze counters; hot-path diagnostics write, file tree scan, manifest build, hash and status reconcile attempt counts stay zero in harness assertions.

Proof architecture stays proof-driven. The only displayed completed state in the harness must cite `CanonicalTransferFinalizeProof` or peer inventory hash/size match. MetadataOnly, completed ledger alone and partial receive produce rejection diagnostics. Status exchange ack alone is modeled as observation only and cannot create completed/peerVerified/audioAvailable state.

This architecture is not real-device evidence. It proves deterministic code-level cooperation among File no-freeze assertions, UI effective status projection, realtime exchange semantics, Connection/Transfer owner evidence and StatusTruth proof rules. Paired iPhone/Mac redacted JSONL is still required before any real-device no-freeze, convergence or canonical-kernel-complete claim.

## 2026-06-15 Canonical v9.8 / connection and transfer runtime owner architecture

v9.8 makes Connection and Transfer runtime-owned only in the allowed `canonicalFullSync` path. The shared protocols remain portable: `CanonicalConnectionRuntime` and `CanonicalTransferRuntime` do not embed Rokurics local HTTPS, TLS, HMAC, certificate pinning, nonce, body hash, URL route or `RequestVerifier` details. Rokurics app code adapts those runtimes to the existing secure carrier.

`CanonicalKernelSwitch` now emits explicit connection and transfer runtime configurations. `oldKernel` disables both owners and uses legacy connection/upload behavior. `canonicalShadow` and diagnostics-only modes allow carrier diagnostics only and no transfer commit. `canonicalDecisionOnly` cannot commit transfer. `canonicalApplyNoAudio` blocks audio transfer. `canonicalFullSync` can enable `connectionOwnerWithLegacyFallback` and `canonicalTransferWithLegacyFallback` only when debug/internal, owner approval, manual confirmation, legacy fallback, route/security, domain readiness and connection/transfer runtime readiness all pass. `blocked` falls back to legacy.

Connection owns liveness and status carrier semantics, not transport security. On iPhone, `StudyLibrarySyncCoordinator` and `LocalNetworkHeartbeatMonitor` ask the runtime to create heartbeat/status/syncRequested envelopes and then send them over existing `/device/status` or `/connection/heartbeat` requests. On Mac, `SecureLocalHTTPSServer` records incoming heartbeat liveness and canonical status requests only after the existing verifier has accepted the request. Heartbeat callbacks enqueue existing sync/status work; they do not inline inventory, apply, upload, file scan, hash or diagnostics writes.

Mac topology is unchanged. The Mac receiver remains a local HTTPS server, and the iPhone remains the client. A canonical connection sync request on Mac records or advertises existing pending state in the response path; it never opens a connection back to the iPhone.

Transfer owns the resumable session state machine while the adapter owns app transport. In `canonicalFullSync`, `RecordingUploadCoordinator` constructs `CanonicalTransferRuntime` with `IPhoneCanonicalTransferAdapter`. The adapter wraps `IPhoneCanonicalSecureAudioUploadPort`, which continues to call `SecureMacUploadClient` and the existing upload session start/status/chunk/finalize routes. No route or upload schema is added or changed.

`CanonicalTransferRuntime` performs start, immediate status refresh/resume, chunk sending, monotonic `confirmedBytes` updates, finalization and proof validation. `CanonicalTransferRetryRuntime` is the gate for view-refresh and retry-drainer behavior: view refresh cannot create a job, and retry drainer can only resume an existing eligible job. If the production audio executor/port is not enabled, `canonicalFullSync` fails closed instead of treating a fake ledger as ready.

Finalize proof flows into Sync truth rather than directly mutating UI status. The iPhone upload path produces a receiver-accepted `CanonicalTransferFinalizeProof` and writes it as a v9.4 status truth fact. The Mac finalize route also produces a fact only after the existing verified route has returned completed with matching checksum and byte size. Completed ledger alone, metadataOnly, receive record alone and partial receive remain non-proof; existing different audio remains conflict/no-overwrite.

Diagnostics stay bounded and redacted. Owner records may include mode, safe object/session ids, offsets, byte counts, route category and hash prefixes, but not absolute paths, full hashes, secrets, full fingerprints, request/response bodies, raw audio, full metadata JSON or provider output.

## 2026-06-14 Canonical v9.7 / realtime status exchange runtime architecture

v9.7 adds the first runtime wiring for the portable realtime status exchange contract. The shared owner is `CanonicalStatusExchangeRuntime`, an actor in `RokuricsShared/SyncCore` that depends only on `CanonicalStatusTruthRuntime` and protocol value types. It has no URLSession, Network.framework, HTTPS route, TLS, HMAC, pinning, nonce or RequestVerifier dependency.

The runtime is fact-store driven. Outgoing envelopes are generated from the v9.4 status truth snapshot as canonical deltas, plus one pending ack and one pending request when available. Sequence numbers are monotonic per local sender. Fact signatures prevent repeated unchanged fact sends; duplicate delta IDs are accepted idempotently; stale, expired and wrong-destination envelopes are rejected deterministically and queued for rejected ack.

Incoming deltas are merged through `CanonicalStatusTruthRuntime.produce(...)`, so conflict/proof semantics remain owned by v9.4 status truth. A low-proof metadataOnly fact cannot override an accepted finalize proof. Ack disposition is observed/incorporated/rejected and is never promoted to audio proof. Request handling is action-only: `runSyncSoon` maps to enqueue, `fullInventory` maps to enqueue/request inventory, and `sendAudioProof` maps to lightweight proof request diagnostics, not upload job creation.

Rokurics carrier integration is adapter-only. iPhone carries optional envelopes on existing `/device/status`, `/connection/heartbeat` and `/sync/inventory` request bodies. Mac consumes them only after existing request verification and returns optional envelopes in the existing heartbeat/status or inventory responses. Missing optional envelope fields decode as nil for old peers. Upload start/status/chunk/finalize routes do not carry status exchange.

Mac topology is unchanged. `SecureLocalHTTPSServer` and `SecureReceiverService` host the Mac runtime and only respond to iPhone requests. A status exchange `runSyncSoon` request records an existing pending sync hint through `ConnectionSyncStateStores`; it does not initiate a connection from Mac to iPhone and does not inline sync or upload work in the route handler.

Diagnostics remain bounded and redacted. Carrier diagnostics distinguish heartbeat and inventory envelopes; delta/ack/request sent and received are recorded without request/response body, full hash, absolute path, raw audio, full metadata JSON or provider output. Redaction failure is represented as blocked/rejected diagnostics rather than unsafe payload logging.

## 2026-06-14 Canonical v9.6 / effective status binding architecture

v9.6 adds a UI-facing projection boundary without changing UI hierarchy or transport/security architecture. `CanonicalEffectiveStatusUIProjection` consumes `CanonicalEffectiveSyncStatus` and returns `CanonicalDisplaySyncState`, a small display model for existing status controls. The projection is still portable shared SyncCore code; it has no HTTPS/TLS/HMAC, route, URLSession, file IO, upload execution or UI mutation dependency.

The projection is stricter than the raw display enum. A status can render as completed/peerVerified only when `canDisplayAsComplete` is true and the proof is accepted finalize proof, peer inventory/hash-size proof, same hash+byteSize proof or a valid dual-ack proof chain. `metadataOnly`, receive record only, completed ledger alone, partial receive, local file existence and expected manifest hash are demoted to waiting/uploading/blocked/conflict display states and cannot become audio availability proof.

`LegacySyncStatusToCanonicalEffectiveStatusAdapter` is the oldKernel/blocked/fallback bridge. It converts legacy upload/receive/display facts into canonical status facts, runs the same reconciliation runtime, and then uses the UI projection. This keeps legacy fallback available while preventing legacy `uploaded`, receive record, metadata-only ledger or local file existence from bypassing the proof rules.

iPhone UI binding remains shape-compatible. `RecordingUploadCoordinator.displaySyncState(for:)` is the single status source for existing recording library/detail action areas; `displayStatus(for:)` maps the canonical display state back to the existing `RecordingUploadStatus` enum so button labels, icons, colors, spacing and navigation do not change. View refresh passes through display-only projection and does not create upload jobs.

Mac UI binding is centered on `MacRecordingInboxItem.canonicalDisplaySyncState`. Existing Mac inbox/study views keep their structure, but the detail audio availability text now reads the canonical display status instead of raw `hasAudio`. A completed receive record without accepted audio proof is not rendered as audio available, and partial receive stays in the transfer/progress path.

## 2026-06-14 Canonical v9.5 / no-freeze hot path recovery architecture

v9.5 narrows the architecture change to hot-path recovery. It does not introduce a new protocol shell, route, upload schema, UI surface or business semantic change. Default/release remains `oldKernel`, legacy fallback remains mandatory, and the portable canonical layer still does not embed Rokurics HTTPS/TLS/HMAC details.

Diagnostics now follow a facade-to-writer pipeline. iPhone and Mac `ConnectionDiagnosticsStore.record(...)` remain synchronous app-facing calls, but their hot path is limited to redaction, bounded in-memory recent-entry/counter updates and enqueueing. File IO is owned by `CanonicalAsyncDiagnosticsWriter` and its actor-backed file sink, which append JSONL and perform bounded background compaction. `loadEntries()` is a readback/debug path, not the record path.

The diagnostics writer is still guarded by the shared redaction detector before any line can be enqueued or flushed. Unsafe details such as absolute paths, full hashes, secrets, full fingerprints, request/response bodies, raw audio, full metadata JSON and full provider output are rejected or replaced with redacted entries. `diagnosticsWriteDurationMs` is measured by the runtime clock or fake clock in tests.

Canonical effective read cache keys are now content signatures rather than snapshot timestamps. The iPhone and Mac `StudyLibraryStore` signatures intentionally exclude `generatedAt` and include stable recording/library/artifact/tombstone/conflict/upload/status/fallback fields plus deterministic ordering and the selected hierarchy rule where relevant. Repeated reads and Mac `tree()` use the cached projection when content is unchanged.

Status truth projection is cached inside the `CanonicalStatusTruthRuntime` actor. Fact production still merges through `CanonicalStatusFactStore`, but the runtime stores a per-object effective projection snapshot keyed by object ID and content signature. Repeated effective-status reads are cache lookups or bounded rebuilds on signature change, and MainActor Store/coordinator/server paths should only enqueue facts or read already-built snapshots.

The new projection diagnostics are performance/convergence evidence, not UI behavior. `effectiveStatusProjected`, `statusProjectionDurationMs` and `mainActorStatusReconciliationAttemptCount` describe whether reconciliation stayed off the hot path. The truth hard rules remain unchanged: metadataOnly, completed ledger alone, partial receive and local file existence are still not peer audio proof.

## 2026-06-14 Canonical v9.4 / sync state truth protocol architecture

v9.4 adds the Sync-domain status truth runtime owner. Its job is to turn multiple local and peer facts into one proof-driven effective status. It is intentionally read-only at app integration points: the truth engine does not execute transfer, mutate UI, write business data, start sync, create network requests, add routes, or bypass security.

The shared truth model is fact-based. `CanonicalStatusFact` carries objectID, domain, phase, source, producer node, logical time, proof, causality and expiry. `CanonicalStatusProof` can represent peerUnknown, metadataOnly, receiveRecordOnly, completedLedgerOnly, partialReceive, localFileExists, expectedManifestHash, peer hash/size, peer inventory hash-size match, finalize proof, same hash/byteSize, status exchange ack, dual ack proof chain, existing different audio, tombstone, unsupported schema and existing eligible retry.

`CanonicalStatusFactStore` is an actor-backed in-memory store. It merges facts deterministically, drops expired facts, supports `replacesFactIDs`, filters stale facts during reconciliation, and emits only redacted diagnostics. No new persistent schema is introduced in v9.4.

`CanonicalStatusReconciliationRuntime` hardcodes the kernel status rules. Soft evidence can explain state but cannot prove peer audio: metadataOnly, receiveRecordOnly, completed ledger alone, partial receive, local file exists and expected manifest hash are rejected as peer proof. Same hash plus same byteSize is the no-op proof. Accepted finalize proof, peer inventory/hash-size proof or dualAck proof chain can produce peerVerified/completed. Existing different audio becomes conflict/no-overwrite. Tombstone blocks generated artifact resurrection. Unsupported schema blocks/falls back. Stale facts cannot override fresher proof.

`CanonicalEffectiveSyncStatusProjection` produces the read projection consumed by adapters: objectID, domain, phase, displayState, proof, sourceSummary, `canDisplayAsComplete`, `canCreateUploadJob`, `canSuppressLegacyDuplicate` and blocker. `canCreateUploadJob` is the only canonical status-based permission to create a canonical upload job. View refresh always denies job creation. Retry drainer never creates a fresh job; it can only be represented as external resume of an existing eligible job.

Diagnostics are bounded and redacted via `CanonicalStatusTruthDiagnosticRecord`. Events include fact produced/merged/rejected, proof expired, effective projected, metadataOnly/completed-ledger/partial-receive rejection, peer proof unavailable, finalize proof accepted, existing different audio conflict and upload job creation denied. Redaction rejects unsafe details instead of logging absolute paths, full hashes, secrets, full fingerprints, full metadata JSON, request/response bodies, raw audio or full transcript/note/summary/provider output.

Rokurics adapter integration is read-only first. iPhone `RecordingUploadCoordinator`, `StudyLibrarySyncCoordinator` and `StudyLibraryStore` can produce facts and ask for effective status. Mac `SecureReceiverService`, `SecureLocalHTTPSServer`, `StudyLibraryStore` and `MacRecordingFileStore` expose the same helper surface. The old UI/upload/read status paths remain authoritative for display and behavior until a later explicit cutover; default/release remains `oldKernel` and legacy fallback remains mandatory.

This architecture keeps the portable protocol independent of Rokurics local HTTPS/TLS/HMAC. The shared truth runtime has no route or carrier binding. Existing upload start/status/chunk/finalize routes, `RequestVerifier`, TLS/HMAC/pinning/nonce/body hash and Mac server/iPhone client topology are unchanged.

## 2026-06-14 Canonical v9.3 / transfer kernel runtime architecture

v9.3 introduces the Transfer Kernel runtime owner as portable shared state machine/proof/retry/runtime code plus Rokurics adapters. The shared layer owns session state, chunk offset accounting, resume decisions, finalize proof validation, retry/backoff and diagnostics redaction. It does not import URLSession or Network.framework, does not know Rokurics HTTPS routes, and does not contain TLS/HMAC/pinning/nonce/body-hash implementation details.

`CanonicalTransferSessionStateMachine` is the deterministic transfer state owner. It makes `confirmedBytes` monotonic, derives the next chunk offset from confirmed bytes, accepts duplicate chunks only when offset/length/hash match, treats wrong offsets as interrupted/status-refresh work, refuses partial receive finalization, and turns hash/size mismatch or existing different audio into conflict/no-overwrite.

`CanonicalTransferRuntimePort` is the portable adapter boundary with start/status/sendChunk/finalize and optional local abort before finalize. `IPhoneCanonicalTransferAdapter` maps it onto the existing secure upload client stack (`IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient`). `MacCanonicalTransferReceiveAdapter` maps it onto the existing receive executor/store (`MacAudioUploadCutoverExecutor` -> `MacRecordingFileStore`). The app carrier remains unchanged: iPhone is client, Mac is server, and the existing start/status/chunk/finalize upload routes remain the only production routes.

Finalize proof is an output of Transfer, not a UI status decision. `CanonicalTransferFinalizeProof` carries receiver node, session id, object id, byteSize, hash prefix, internal full hash proof, finalizedAt and verified flag. Diagnostics expose only the prefix. v9.4 Sync Status Truth must consume this proof before any UI completed/uploaded verified state is produced.

Retry/backoff is also owned by Transfer. `CanonicalTransferRetryRuntime` only resumes existing eligible jobs, blocks view refresh fresh-job creation, blocks retry drainer fresh-job creation, requires status refresh for stale interrupted sessions when status exists, and fails closed for peerUnknown, missing local audio, tombstone, conflict, security and malformed ledger blockers.

This architecture preserves the old behavior boundary. Default/release remains `oldKernel`, legacy fallback remains available, `RecordingUploadCoordinator` remains the current entry point until a later switch integration, and v9.3 does not claim the full canonical kernel is complete.

## 2026-06-14 Canonical v9.0 / kernel contract freeze architecture

v9.0 introduces the portable canonical kernel contract layer only. It defines four first-class domains: Connection, Transfer, Sync and File. Connection owns carrier identity, pairing/liveness/status hints; Transfer owns file transfer session/chunk/offset/resume/finalize/retry protocol; Sync owns status truth, realtime status exchange, diff/LWW/apply-plan/event-driven/read-projection contracts; File owns file tree, manifest, metadata/checksum cache, root-bound atomic write/rollback and no-freeze budgets.

The new files in `RokuricsShared/SyncCore/` are pure model/protocol/rule/report types. They do not instantiate app services, do not call existing coordinators, do not mutate stores, do not create upload jobs, do not start sync, do not scan files, do not write diagnostics, and do not bind to a concrete local carrier implementation. Rokurics app/runtime code can later adapt these contracts, but this freeze does not connect them to runtime.

`CanonicalKernelModeMirror` mirrors the existing `CanonicalKernelSwitchMode` values so readiness reports can describe current switch semantics. It is not a switch owner and does not replace `CanonicalKernelSwitch`. Default/release mode remains `oldKernel`, legacy fallback remains mandatory, and `canonicalFullSync` runtime behavior is unchanged.

Sync status truth is modeled as facts plus proofs. The hard-proof rules are explicit in shared code: metadata-only, receive-record-only, completed-ledger-only, partial receive, local file exists and expected manifest hash are rejected as peer audio proof. Same hash plus same byte size is the only audio no-op. Receiver finalize proof or peer hash-size proof can support peer verified/completed state. Peer unknown defers, and existing different audio resolves to conflict/no-overwrite.

Realtime status exchange is envelope/delta/ack/request plus sequence, logical clock, stale, expire and conflict policy. The contract is transport-independent and intentionally leaves carrier verification, request signing, pinning, nonce, body hash and route handling to adapters. No route is added and no upload route schema changes.

File contract separates root-bound relative addressing from implementation. File tree snapshot, manifest build, checksum cache and atomic write/rollback are all expressed as protocol ports with `CanonicalNoFreezeBudget`; file tree scan, manifest build, full-file hash and diagnostics write are forbidden on MainActor hot paths.

Diagnostics are a taxonomy, not a writer. Performance events include read projection, study tree, file tree snapshot, manifest, checksum cache, hash, main-actor long task, route and diagnostics-write durations/counts. Convergence events include status fact/delta/ack, fact rejection, proof expiry, syncRequested hint, event trigger queue/coalesce, event-to-sync latency, peer proof unavailable and finalize proof accepted/rejected proof cases. Redaction detection forbids absolute paths, full hashes, secrets, full fingerprints, full metadata JSON, request/response bodies, raw audio and full transcript/note/summary/provider responses.

`CanonicalKernelV9ContractReadinessGate.v900(...)` is a pure bool-evidence gate for contract readiness. It returns `READY_FOR_V9_RUNTIME_IMPLEMENTATION` only when the four-domain contracts, docs/tests, transport independence, oldKernel default, legacy fallback, route/security unchanged, peer-proof rules, no-freeze rule and diagnostics redaction evidence are all present. It returns `UNSAFE_TO_PROCEED` for route/security bypass, default/release canonical, missing legacy fallback, peer proof violation, MainActor heavy work allowed or diagnostics leak.

## 2026-06-13 Canonical v8.73 / final app-state readiness architecture

v8.73 is the final code-level closure for the Claude diagnosis: read-path stutter, Mac inventory build placement, `syncRequested` heartbeat consumption, event-driven sync trigger and status convergence must be checked together before a real-device trial. It does not add a route, change route paths, change upload routes, change TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`, change pairing/Keychain, make Mac connect back to iPhone, change canonical domain semantics, remove legacy, disable fallback or enable canonical by default.

The new shared readiness layer is `CanonicalRealDeviceTrialReadinessGate.v873(...)`. It is a pure scorecard model, not a runtime owner. It receives booleans from build/test/manual audit evidence and reports `CODE_COMPLETE_RESULT` as `READY_FOR_REAL_DEVICE_APP_TRIAL`, `PARTIAL_WITH_BLOCKERS`, `NOT_READY` or `UNSAFE_TO_TRY_ON_DEVICE`. Because it has no side-effect callbacks, it cannot start sync, create upload jobs, run read projections, mutate stores, rebuild inventory or touch network/security routes.

The gate is intentionally app-state oriented rather than domain-expansion oriented. Required green signals are: canonical effective read cache ready, Mac inventory off-main/mode gated, oldKernel canonical build skipped, live heartbeat `syncRequested` queued into the existing sync path, event-driven trigger queue ready, status convergence refresh ready, storm protection ready, build/test status, default/release oldKernel, single five-mode kernel switch, gated `canonicalFullSync`, legacy fallback, route/security unchanged, switch-back proof driver available, diagnostics redacted and v8.73 runbook updated.

Unsafe signals fail closed: release/default canonical, missing legacy fallback, route/security or `RequestVerifier` bypass, unsafe production-root write, view refresh upload job creation, missing retry storm guard, metadataOnly/completed ledger/partial receive treated as audio proof, existing different audio overwrite risk, diagnostics leak, oldKernel switch-back failure, heartbeat callback doing heavy sync, or Mac reverse connection attempt. These produce `UNSAFE_TO_TRY_ON_DEVICE`, not a partial readiness state.

Real-device evidence is tracked separately. `READY_FOR_REAL_DEVICE_APP_TRIAL` means code-level build/test/gate conditions are ready for the user to run the paired iPhone/Mac debug/internal trial. It does not mean the trial has passed. Until paired redacted jsonl exists, reports must say `realDeviceEvidencePresent=false` and `REAL_DEVICE_EVIDENCE_RESULT=not run; no real-device evidence produced.`

## 2026-06-13 Canonical v8.72 / event-driven sync trigger architecture

v8.72 changes only the trigger topology and lightweight status convergence projection. It does not add routes, change route paths, change upload routes, change TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`, change pairing/Keychain, change Mac/server-client topology, change sync decision/apply/upload/read runtime semantics, change master switch mode semantics, enable canonical by default, remove legacy, or disable legacy fallback.

The iPhone now exposes a shared event contract through `SyncTriggerReason` and `LocalNetworkSyncEventTrigger`. Recording save, title/filing metadata edits, local tombstone/conflict writes, upload status/finalize/retry changes, study library folder/item writes, generated artifact availability and app foreground pending changes post lightweight events. These callbacks never perform inventory exchange or upload inline.

`LocalNetworkSyncAppService` owns the unified immediate queue. The queue aggregates reasons, debounces repeated edits, applies a max-frequency/storm guard, records offline/background deferral, and then calls the existing scheduler/engine path. The scheduler remains the in-flight gate shared by periodic sync, manual sync, heartbeat `syncRequested` and event-driven ticks; if a sync is running, pending events can produce at most one follow-up run after completion.

The 3 second heartbeat remains a liveness/status channel and hint carrier only. The 240 second `syncInterval` remains the periodic fallback. Event ticks are an earlier scheduling source for the same sync path, so oldKernel still uses legacy sync behavior and canonical modes still pass through the current kernel switch, decision, read, apply, upload and security gates.

Mac event handling stays server-side. Mac receive/finalize, study library writes, generated artifact writes, transcription/note status changes and app foreground/server-start pending state enter a Mac-local debounce queue. The Mac queue refreshes local projection and, when an eligible paired device exists, sets the existing `syncRequested` pending hint for the next iPhone heartbeat/inventory. Mac does not initiate a connection to iPhone.

Status convergence is projection refresh plus queued sync/status refresh, not a proof rewrite. Local UI upload/receive/transcription/note status is never treated as peer proof. `metadataOnly`, completed ledger alone and partial receive remain non-audio proof states; finalize proof is still required before uploaded-verified status. Status refresh does not create upload jobs and does not trigger transcription or note generation.

Diagnostics are bounded and redacted. They include trigger received/coalesced/debounced/queued/started/completed/failed/already-running/deferred/storm-suppressed/follow-up, status projection/finalize-proof/peer-proof-unavailable and Mac hint set/consumed events. Counts/durations come from actual queue paths or fake-clock tests; diagnostics exclude request/response bodies, secrets, full hashes, full fingerprints, absolute paths, full metadata JSON, provider output and raw audio.

This is still local build/test evidence unless paired iPhone/Mac redacted jsonl is produced. v8.73 should add a real-device observation runbook and diagnostics gate before any claim of complete real-device state convergence.

## 2026-06-13 Canonical v8.71 / live heartbeat syncRequested architecture

v8.71 changes only the first trigger-layer break in the existing topology: Mac manual sync pending is now consumed by the iPhone live heartbeat path and converted into a queued sync tick. It does not add routes, change route paths, change upload routes, change TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`, change pairing/Keychain, change sync decision/apply/upload/read runtime semantics, or make Mac initiate connections to iPhone.

Mac remains the HTTPS server and iPhone remains the client. `SecureReceiverService.prepareManualStudyLibrarySync` still sets a pending sync request and surfaces the waiting status. `SecureLocalHTTPSServer` advertises that pending request through existing heartbeat/status responses by setting `syncRequested` and carrying the existing start signal when available.

The iPhone `StudyLibrarySyncCoordinator` live `performHeartbeat()` decodes `syncRequested` from `/device/status`. Missing fields decode as `false` for older Mac responses. A positive hint is passed to a queue helper that validates peer/online/background state, applies pending/running/debounce gates, and schedules a sync tick. The heartbeat callback itself remains lightweight and does not perform inventory exchange inline.

The queued tick uses the existing sync execution path. Legacy `oldKernel` continues through the old local-network/manual sync path. Canonical modes continue through the current kernel switch and existing decision, read, apply, upload and security gates. The normal periodic `syncInterval` remains 240 seconds; the 3 second heartbeat remains only a liveness/status channel plus a sync-request hint carrier.

Mac manual-sync observability is advanced when the iPhone actually starts sync: `/sync/inventory` with a matching `syncRunID` records that pending manual sync was observed/consumed and updates status to an in-progress/started state. If iPhone never arrives, the pending state remains observable according to the existing pending-signal lifecycle.

Diagnostics are bounded and redacted on both sides. iPhone emits heartbeat hint received/ignored/deferred/queued/deduped/started/completed/failed events with counts/durations from the real path or fake-clock tests. Mac emits pending set/advertised/consumed/inventory observed/cleared events without request/response bodies, secrets, full hashes, full fingerprints, absolute paths, full metadata JSON, provider content or raw audio.

This is not event-driven convergence. New recording/status-change triggered sync and broader convergence work remain v8.72. Without paired iPhone/Mac redacted jsonl, v8.71 is local build/test evidence only.

## 2026-06-12 Canonical v8.70 / Mac server inventory off-main architecture

v8.70 changes only the Mac `/sync/inventory` route's inventory/manifest/canonical build placement and route-level mode gating. It does not change sync triggers, heartbeat, sync interval, event-driven sync, sync decision semantics, read/apply/upload runtime semantics, upload job creation, transport/upload routes, TLS/HMAC/pinning/nonce/body hash, `RequestVerifier`, Keychain, pairing, master switch mode semantics or legacy fallback.

The Mac receiver now passes the resolved `CanonicalKernelSwitchMode` into `SecureLocalHTTPSServer`. The server defaults to `oldKernel`, so release/default construction still returns legacy behavior. The inventory route first builds the existing background manifest/facts input, then evaluates a local canonical build policy from the effective mode.

`oldKernel` and blocked modes are hard skipped at the route level: no canonical recording objects, library objects, generated artifact facts, tombstone/conflict facts, canonical manifest or canonical seam diagnostics are built. The legacy inventory response schema and route behavior remain unchanged. Existing request verification and secure route handling stay on the same path.

Canonical modes build only the required facts. `canonicalShadow`/`diagnosticsOnly` can build facts for shadow/diff and no-commit diagnostics. `canonicalDecisionOnly` limits seam evaluation to decision diagnostics. `canonicalApplyNoAudio` allows non-audio apply/existence diagnostics but skips audio commit/read seams. `canonicalFullSync` builds the full canonical snapshot off-main and reuses it for all eligible seams.

The canonical snapshot is request-scoped. Adapter conversion and `CanonicalInventoryBuilderContract().build(...)` run in a background task from immutable Mac inventory facts; the result is stored in `MacInventoryRequestBuildContext`. Seam calls read the shared snapshot/context and do not rebuild canonical objects, canonical manifest, or full scans/hashes within the same request.

Diagnostics are bounded and redacted. Route metrics report route, manifest and canonical durations, object/artifact counts, skip/reuse/duplicate-prevented counts, seam shared-snapshot usage and MainActor manifest/canonical/hash/scan attempt counts. Duration/count values come from the actual route path or test fake clocks; no success value is hardcoded.

This architecture does not solve state convergence. `syncRequested`, heartbeat wiring and event-driven sync remain v8.71/v8.72 work. Without paired iPhone/Mac jsonl evidence, v8.70 is local build/test evidence only and cannot be described as real-device stutter validation.

## 2026-06-12 Canonical v8.69 / read effective projection cache architecture

v8.69 changes only the Store read projection cache strategy. It does not change the canonical read runtime mode semantics, master switch mapping, sync trigger, heartbeat, sync interval, sync decision, apply runtime, upload runtime, upload job creation, transport routes, upload routes, TLS/HMAC/pinning/nonce/body hash, `RequestVerifier`, Keychain, pairing, production-root write gates, legacy read path or legacy fallback.

The canonical read runtime result remains the source of truth for whether a canonical projection can be served. When `canonicalReadServed == true`, the Store builds a deterministic effective projection once for the current key. The key includes read mode/source/fallback, canonical served state, snapshot source/generatedAt/object signatures, divergence summary, backing-data revision and, on Mac, the selected hierarchy rule. If the key is unchanged, repeated UI reads return cached values.

iPhone caches `effectiveStudyItems` and `effectiveStudyFolders` together, so folders no longer call item conversion a second time. The current iPhone source has no `effectiveStudyTree` API; iPhone study UI consumes items/folders through the browser content path, so v8.69 does not introduce a synthetic tree layer.

Mac caches `effectiveStudyItems`, `effectiveStudyFolders` and `effectiveStudyTree` together. The canonical tree is built once from the cached items/folders for the selected hierarchy rule. Default `tree()` reads the cached effective tree; explicit non-selected rules may still build a one-off view from cached effective arrays. `oldKernel`, fallback legacy and read failure continue to use legacy backing arrays and stored `studyTree`.

Cache invalidation is deterministic: read runtime result/snapshot changes, read runtime config changes, legacy backing refresh, fallback state change and Mac hierarchy-rule change invalidate or rebuild the projection. Read access itself does not start sync, upload, retry drain, file IO or network IO, and does not mutate backing arrays.

Diagnostics are cache-local, bounded and redacted. They report true hit/miss/invalidation/rebuild/tree rebuild/fallback legacy/repeated access/duration counts from the code path and do not include full metadata JSON, full hashes, absolute paths, secrets, fingerprints, request/response bodies, provider content, generated content or raw audio.

This does not solve remaining state convergence work. Mac server inventory off-main remains v8.70, `syncRequested` heartbeat wiring remains v8.71, and legacy trigger/topology convergence remains v8.71/v8.72. No real-device latency claim exists without paired iPhone/Mac jsonl evidence.

## 2026-06-12 Canonical v8.68 / T7 single-kernel switch and final gate architecture

v8.68 does not add a runtime domain and does not change inventory, read, apply, upload, audio commit, production-root write semantics, routes or connection security. It tightens the app-facing control surface and final readiness reporting around the existing `CanonicalKernelSwitch`.

The visible manual switch is now a five-mode DEBUG/internal settings control named `内核模式`: `oldKernel`, `canonicalShadow`, `canonicalDecisionOnly`, `canonicalApplyNoAudio`, `canonicalFullSync`. Default construction and release/default builds still resolve to `oldKernel`. The older `diagnosticsOnly` enum path remains a safe internal compatibility mode, but it is not a selectable manual switch mode for T7.

`canonicalFullSync` remains the only mode that can map decision, guarded read, non-audio apply, existence apply and audio commit to canonical owners. It still requires DEBUG/internal context, owner approval, manual confirmation, legacy fallback, readiness gates, route/security unchanged, redacted diagnostics and switch-back proof readiness. The Settings confirmation describes those gates, backup/test-device expectations, immediate oldKernel switch-back and stop conditions.

Scattered or domain-specific switches are subordinate restrictions. The libraryMetadata debug pilot and runtime/read/apply/audio overrides may disable, narrow or produce diagnostics, but cannot upgrade a master-switch-denied mode, cannot turn `canonicalShadow` into write/upload/read serving, cannot turn `canonicalDecisionOnly` into apply/upload/read serving, cannot turn `canonicalApplyNoAudio` into canonical audio upload, and cannot enable production-root write without fullSync owner/manual gates.

`CanonicalSyncKernelCompletionScorecard.v868(...)` is the final code-completion gate for this batch. It records T1 inventory MainActor closure, T2 read mapping, T3 recording ReadSeam wiring, T4 executor/port injection, T5 production-root owner/manual gate, T6 switch-back proof driver, default/release oldKernel, five-mode selector, fullSync confirmation, decision/read/apply/audio/existence mappings, oldKernel legacy mapping, legacy fallback, Path B transport, route/security, diagnostics redaction and real-device evidence status. Its `CanonicalSyncKernelCodeCompletionResult` uses the exact four report statuses: `READY_FOR_REAL_DEVICE_CANONICAL_SWITCH`, `PARTIAL_WITH_BLOCKERS`, `NOT_READY`, `UNSAFE_TO_TRY_ON_DEVICE`.

Manual switch gate output is separate from real-device evidence. Code-level READY means the build can be handed to the user for paired-device trial; it does not mean real iPhone/Mac behavior is validated. Real-device evidence remains false until paired-device redacted jsonl exists.

## 2026-06-12 Canonical v8.67 / T6 Debug switch-back proof driver architecture

v8.67 adds a Debug-only app-callable proof path for the existing realistic-root switch-back harness. It does not change `CanonicalKernelSwitch` mode semantics, inventory, read runtime, apply runtime, upload runtime, transport routes, upload routes, TLS/HMAC/pinning/nonce/body hash, `RequestVerifier`, Keychain, pairing or legacy fallback.

The app-facing layer is deliberately thin. `IPhoneCanonicalSwitchBackProofDriver` resolves the current iPhone app data source root as `Documents/Rokurics`; `MacCanonicalSwitchBackProofDriver` resolves the current Mac source root from `MacAppStorageProfile.applicationSupportRootURL`. These source roots are read-only inputs to the proof driver. The proof itself is never run in place on either production root.

`CanonicalSwitchBackProofDebugRunner` calls the existing `CanonicalRealisticRootSwitchBackProofDriver`, which creates a fresh system-temp clone, validates the clone with `CanonicalSwitchBackRootSafetyGuard`, then calls `CanonicalSwitchBackRealisticRootHarness.runKernelSwitchBackProof()`. The proof covers oldKernel -> canonicalFullSync -> oldKernel -> canonicalFullSync through the existing kernel switch sequence proof; the wider existing sequence still includes canonicalShadow, canonicalDecisionOnly and canonicalApplyNoAudio before fullSync. The shared root guard rejects `/`, home, repo root, Documents/Application Support production roots and subpaths, Desktop production roots, unmarked non-temp roots and symlink-resolved dangerous roots.

Evidence is local diagnostics only. `CanonicalSwitchBackProofEvidenceJSONLWriter` appends redacted events to `Diagnostics/canonical-switch-back-proof.jsonl` under the temp proof-run root, never under the source production root. UI and JSONL expose only a redacted temp relative evidence path. Events contain only timestamp, nodeRole, runID, status, rootKind, redacted root token, mode-sequence summary, domain/crash counts, blocker enums, `evidenceKind=realisticRoot`, `realDeviceEvidencePresent=false` and relative evidence path. The writer rejects encoded lines that trip the shared sensitive-signal detector.

iPhone and Mac Settings surface the runner inside `Debug · 同步内核` with a “运行新旧内核切回证明” action and UI-safe summary. The action does not set the master switch, does not call sync or upload, does not create upload jobs, does not write business-domain files and does not send network requests. On Mac it also does not restart `SecureLocalHTTPSServer`, change `/sync/inventory`, alter receiver route/security, write `receive.json`, mutate audio inbox, pending sync, transcription or note generation.

The result feeds existing scorecard wiring through the shared driver result: realistic-root proof passed can satisfy the code-level switch-back prerequisite, missing/failed proof blocks, production-root rejection is a safety blocker rather than data failure, evidence redaction failure is unsafe, and paired-device evidence remains false until real iPhone/Mac logs are supplied.

## 2026-06-12 Canonical v8.66 / T4-T5 executor/port injection architecture

v8.66 introduces a small production injection layer without changing route, transport, read, inventory or sync-decision architecture. `CanonicalProductionPortInjectionPolicy` maps the already-resolved `CanonicalKernelSwitchEffectiveConfiguration` plus a store/root URL into a redacted decision: non-audio apply executor slots, existence apply port, audio upload executor, production-root write permission and root safety status. The policy does not read UserDefaults and does not mutate stores.

Platform factories adapt that decision to existing concrete types. `IPhoneCanonicalProductionPortFactory` builds iPhone recording/library/generated/tombstone cutover executors from existing RealApplyPorts. `MacCanonicalProductionPortFactory` does the same on Mac and additionally supplies the metadata-only existence ledger port and Mac audio upload executor holder. `allowProductionRootWrites=true` is only passed to RealApplyPort production-root constructors for `canonicalFullSync` after DEBUG/internal, owner approval, manual confirmation, legacy fallback, legacy-readable/readiness, route/security and root-safety checks pass.

Mode behavior is centralized. `oldKernel`, blocked, diagnostics/shadow and decision-only modes leave production ports/executors nil or diagnostics-only and keep legacy owner. `canonicalApplyNoAudio` may inject non-audio apply/existence availability but cannot create a canonical audio upload executor. `canonicalFullSync` is the only mode that can construct writable production-root RealApplyPorts and canonical audio upload executor/runtime owner. Release/default remains `oldKernel`.

The iPhone upload path remains `RecordingUploadCoordinator` -> `IPhoneAudioUploadCutoverExecutor` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient`; no route or security layer is bypassed. The Mac server stores gated canonical executor references and existence port but does not change `/sync/inventory`, `/sync/apply-metadata`, audio session start/status/chunk/finalize handlers, `receive.json`, pending sync, transcription/note generation or `RequestVerifier`.

Existence apply remains metadata-only. The Mac ledger port is nil for old/diagnostics/shadow/decision, may be present for applyNoAudio/fullSync when the existence runtime can write metadata-only records, and continues to keep `audioAvailable=false` for metadataOnly/receiveRecordOnly. Completed ledger alone is not audio proof. Diagnostics remain redacted and do not contain absolute roots.

## 2026-06-12 Canonical v8.65 / T2-T3 read runtime architecture

v8.65 limits architecture changes to the read side. The master switch effective output now owns the app-facing read runtime configuration consumed by iPhone and Mac `StudyLibraryStore`. This does not alter inventory, sync decision, apply runtime, upload runtime, upload routes, TLS/HMAC/pinning/nonce/body hash, `RequestVerifier`, Keychain, production-root write gating, mode semantics or legacy fallback.

The Store read configuration is refreshed from `CanonicalKernelSwitchEffectiveConfiguration.readRuntimeConfiguration`. `oldKernel`, disabled and blocked read config clear the Store canonical read override and resolve to legacy. `canonicalShadow` is compare/non-serving only. `canonicalDecisionOnly` and `canonicalApplyNoAudio` do not serve canonical read. `canonicalFullSync` may provide a guarded canonical read with legacy fallback when the gate allows it. Specialized read configs remain subordinate restrictions and cannot upgrade a master-switch-denied mode into canonical serving read.

The recordingMetadata read path now delegates through platform ReadSideSeams. `IPhoneCanonicalReadRuntimeAdapter` calls `IPhoneRecordingMetadataReadSideSeam`; `MacCanonicalReadRuntimeAdapter` calls `MacRecordingMetadataReadSideSeam`. The seam performs canonical-vs-legacy projection comparison and returns canonical only when the effective read policy allows serving and comparison is clean. Divergence, read failure, unsupported input or missing evidence return legacy.

Read runtime output is an effective projection only. It does not mutate Store backing arrays, start sync, create upload jobs, trigger upload, write audio bytes, write transcript/note/summary/generated content, alter Mac `receive.json` or audio inbox, or change `/sync/inventory` response. Paired-device jsonl remains required before any real-device read-switch validation claim.

## 2026-06-12 Canonical v8.64 / T1 inventory off-main architecture

v8.64 narrows the architecture work to the inventory/runtime snapshot/sync manifest construction path. It does not alter sync decision semantics, apply plans, upload ownership, read runtime, upload routes, connection security, `CanonicalKernelSwitch` modes or legacy fallback. The purpose is to remove residual MainActor-heavy work before a future `canonicalFullSync` manual trial.

On iPhone, `LocalNetworkSyncInventoryBuilder` remains a lightweight value type. Heavy facts are assembled before the build through `LocalNetworkSyncInventoryBackgroundInput`: recording metadata load, upload jobs load, study manifest facts, audio existence/size/checksum cache facts, folder/item/recording metadata hashes and generated artifact scans. The detached background builders produce immutable facts, and `buildRuntimeSnapshot(...)` consumes those facts without calling MainActor-isolated store APIs for metadata/jobs load, manifest build, directory scan or hashing.

Sync manifest construction is split into snapshot collection and pure value construction. `StudyLibraryStore.makeSyncManifestInBackground(...)` captures only the root URL on MainActor, then loads recordings and builds `StudyLibrarySyncManifest` on a background task. The same background manifest builder is reused by legacy inventory construction, so the two previous iPhone main-thread `makeSyncManifest` call sites are removed from T1 paths. The pure builder does not perform file IO, network IO or upload job creation.

On Mac, `SecureLocalHTTPSServer` now prepares `MacLocalNetworkSyncInventoryBackgroundInput` before `/sync/inventory` response assembly. Manifest facts, metadata hashes and artifacts are computed off-main and then consumed by the existing route response builder. The wire schema and route behavior stay compatible, and `RequestVerifier`, TLS/HMAC/pinning/nonce/body hash and upload routes remain untouched.

Inventory diagnostics remain bounded and redacted while becoming more explicit. Runtime reports include real duration/count fields for inventory, metadata load, jobs load, manifest build, directory scan, hash work, checksum cache hit/miss/stale, hash-computed/skipped-by-cache-hit, MainActor attempt counters, duplicate snapshot builds and snapshot reuse. Zero attempt counts are detector/path results, not fake success constants. No real-device latency claim is made without paired-device jsonl evidence.

## 2026-06-12 Canonical v8.58 / recordingMetadata real apply/read architecture

v8.58 narrows the recording metadata architecture from generic cutover scaffolding to four dedicated domain files: `IPhoneRecordingMetadataRealApplyPort`, `MacRecordingMetadataRealApplyPort`, `IPhoneRecordingMetadataReadSideSeam` and `MacRecordingMetadataReadSideSeam`. These are recording-metadata-only ports/seams; they do not add a transport route, upload route, connection/security behavior, library metadata behavior, generated artifact behavior or tombstone/conflict behavior.

The iPhone and Mac RealApplyPort implementations follow the existing library metadata real-apply pattern while using the shared root-bound recording metadata write core. The write payload is legacy-readable and canonical-readable, includes safe title/name metadata, business modifiedAt fact where available, and the stable canonical recording business metadataHash. The write boundary is atomic with rollback checkpoint and postcondition verification. Rollback failure is treated as a fatal blocker. The ports expose only redacted diagnostics and explicitly do not write audio bytes, upload jobs, upload ledger state, standalone note content, generated content, Mac `receive.json` or the Mac audio inbox.

The iPhone and Mac ReadSideSeam implementations wrap `CanonicalReadRuntimeProvider` for the recording metadata domain. `oldKernel` and release/default serve legacy. `canonicalShadow` and `canonicalDecisionOnly` compare only. `canonicalApplyNoAudio` may compare but does not serve canonical by default. `canonicalFullSync` may serve canonical recording metadata only when the master gate allows guarded read, legacy fallback is available and canonical-vs-legacy comparison is equivalent. Divergence or read failure falls back to legacy.

`CanonicalKernelSwitch` remains the single behavior owner. Specialized recording metadata apply/read wiring is subordinate to the master switch and cannot make release/default canonical. Switch-back remains migration-free because canonical recording metadata writes preserve the legacy-readable shape and legacy fallback is retained. Real-device validation still requires paired iPhone/Mac jsonl evidence before any manual gray rollout claim.

## 2026-06-11 Canonical v8.57 / P3-2 realistic root switch-back architecture

v8.57 turns the previous synthetic switch-back proof into a realistic app-data-root proof layer. `CanonicalSwitchBackRootSafetyGuard` rejects production-like roots and only allows temp/test-cloned roots. `CanonicalRealisticLibraryRootFixture` writes a deterministic legacy-readable app-data shape with study library metadata, recording metadata, generated artifact metadata/content fixtures, tombstone/conflict markers, canonical existence ledger, audio inbox receive metadata, small audio fixture, upload ledger, retry records, checksum cache, diagnostics, legacy store files, canonical supplemental files and version/schema markers.

The proof path remains local/test-only. `CanonicalSwitchBackRealisticRootHarness.runKernelSwitchBackProof()` combines root safety, fixture completeness, realistic-root legacy/canonical reads, the five-domain `CanonicalDomainSwitchBackMatrix`, 12-point `CanonicalCrashPoint` recovery, `CanonicalKernelSwitchSequenceProof` for oldKernel -> canonicalShadow -> canonicalDecisionOnly -> canonicalApplyNoAudio -> canonicalFullSync -> oldKernel -> canonicalFullSync, and redacted `CanonicalSwitchBackEvidencePackage` export. It does not mutate production root, does not add transport or upload routes, does not change TLS/HMAC/pinning/nonce/RequestVerifier, and does not delete or disable legacy fallback.

The five business domains are `recordingMetadata`, `libraryMetadata`, `generatedArtifacts`, `tombstoneConflict` and `audioUpload`. The matrix proves legacy write -> canonical read, canonical write -> legacy read, canonical write -> oldKernel read, oldKernel write -> canonicalFullSync read, both directions of continued safe writes, no migration, no canonical-only required field, no legacy-incompatible disk format, legacy fallback retained and diagnostics redacted. Audio upload proof is state-level only and preserves the existing start/status/chunk/finalize route boundary.

`CanonicalSyncKernelCompletionScorecard.v857(...)` treats P0-P3 construction as code complete when the realistic-root proof passes, but still reports `codeCompleteNeedsDeviceEvidence` without paired-device real logs. v8.57 therefore proves code-level reversibility, not real-device validation or legacy retirement.

## 2026-06-11 Canonical v8.56 / P3-1 unified master kernel switch architecture

v8.56 consolidates existing P0-P2 canonical runtime pieces behind one master switch. `CanonicalKernelSwitchConfiguration` remains the single app-facing input, and `CanonicalKernelSwitchEffectiveConfiguration` is the output consumed by inventory, sync decision, existence/apply bridge, non-audio apply, audio upload, read runtime, diagnostics/shadow and migration/scorecard policy. This round does not add a business domain, transport route, upload route, TLS/HMAC/nonce change, read projection content change or legacy retirement.

The master modes are frozen as `oldKernel`, `diagnosticsOnly`, `canonicalShadow`, `canonicalDecisionOnly`, `canonicalApplyNoAudio`, `canonicalFullSync` and `blocked`. Default construction and release/default builds resolve to `oldKernel`. `oldKernel` disables every canonical owner. `diagnosticsOnly` builds safe diagnostics only. `canonicalShadow` can compare shadows but cannot write, upload, serve canonical read or suppress legacy duplicates. `canonicalDecisionOnly` can select canonical decision where domain gates allow, while apply/upload/read remain legacy. `canonicalApplyNoAudio` can apply non-audio domains through gated runtime but canonical audio upload is disabled. `canonicalFullSync` is the only mode that maps all canonical owners.

`canonicalFullSync` is guarded by `CanonicalKernelSwitchGate` / `CanonicalKernelSwitchGateResult`. It requires DEBUG/internal context, manual confirmation, owner approval, legacy fallback, legacy read/write/apply path, legacy upload fallback, inventory readiness, sync decision readiness, non-audio apply readiness, audio upload readiness, read runtime readiness, five domain readiness, diagnostics redaction, unchanged route/security, safe production-root configuration, no unresolved conflict blocker, no switch-back hard blocker and no canonical-only disk-format blocker. Missing evidence blocks the master switch instead of silently enabling a partial canonical owner.

Advanced or older domain-specific configurations are subordinate. They may disable or narrow an effective runtime, but they cannot escalate beyond the master switch. A sync/apply/existence/audio/read/libraryMetadata override that creates more authority than the master mode, disables fallback/redaction, enables runtimeSwitch, enables unsafe production root, broadens enabled domains/scopes, or allows audio where `canonicalApplyNoAudio` forbids it becomes an invalid mixed config and resolves to `blocked`. The old libraryMetadata pilot remains a test/advanced surface, not a production-root bypass; Mac app startup passes the master effective pilot config to the receiver.

Switching back to `oldKernel` is immediate at behavior/config level because all effective canonical owners become disabled and legacy read/write/upload/apply paths remain retained. v8.56 does not claim realistic-library switch-back proof; v8.57/P3-2 must prove oldKernel can read a realistic library root after a staged canonicalFullSync write without migration, cleanup, physical delete or manual data repair.

## 2026-06-11 Canonical v8.55 / P2-5 audioUpload domain readiness architecture

v8.55 defines `audioUpload` as the fifth domain-readiness target. The domain is modeled in the existing upload truth layer with `CanonicalAudioUploadDomainFields`, `CanonicalAudioUploadProofSchema`, `CanonicalAudioUploadDecisionInput`, `CanonicalAudioUploadDecisionResult`, `CanonicalAudioUploadAvailability`, `CanonicalAudioUploadReadStatus` and `CanonicalAudioUploadOwnershipPolicy`. It reuses the v8.49 resumable upload executor and v8.50 retry/state truth rather than adding another transport or persistence stack.

The proof schema is `canonical-audio-upload-v1`. Domain fields include recordingID/objectID, local audio existence, local byteSize/hash prefix/safe token, peer recording existence, peer audio availability, proven peer byteSize/hash prefix, redacted session prefix, confirmedBytes, finalize proof, retry state, conflict state and mtime/status summary. Full paths, full hashes, raw audio bytes, full metadata JSON, secrets, fingerprints, request/response bodies and transcript/note/summary/provider content are excluded.

Decision ownership follows audio proof, then upload safety. Metadata-only, receive-record-only and study-item-only peer facts can become upload-needed when local audio exists and policy is safe, but they are not audio proof. PeerUnknown remains deferred. Same hash plus same byteSize is the only audio no-op. Different hash or byteSize is conflict/no-overwrite. Completed ledger alone and expected manifest hash/size do not mark uploaded. Upload completed requires finalized Mac proof or peer inventory proven finalized same hash+byteSize.

Sync ownership now includes `audioUpload` in `CanonicalSyncRuntimeDecisionScope`. Default/release still resolve to `oldKernel`; diagnosticsOnly and canonicalShadow compare without creating jobs; canonicalDecisionOnly can evaluate the audioUpload decision without network; canonicalApplyNoAudio blocks canonical audio upload; canonicalFullSync can select canonical audio decision/commit/read-status under the existing debug/internal owner-approved gate with legacy fallback.

Commit ownership remains the v8.49 secure resumable path. iPhone canonical upload continues through `RecordingUploadCoordinator`, `RecordingUploadClient` and `SecureMacUploadClient`; Mac receive continues through `SecureLocalHTTPSServer`, `RequestVerifier` and `MacRecordingFileStore`. Start/status/chunk/finalize routes, TLS pinning, HMAC, nonce, body hash and request verification are unchanged. No new route, no new upload route and no security bypass are introduced.

Read/status ownership exposes `CanonicalAudioUploadReadStatus` through the upload status projection and the guarded canonical read/status path. It can report notAvailable, metadataOnly, uploadNeeded, pending, uploading, interrupted, retryScheduled, finalizing, uploadedVerified, noOpSameAudio, conflict, deferredPeerUnknown, blocked or failed. Read/status evaluation must not trigger upload, retry drain, Store mutation, heavy MainActor audio hashing or UI technical diagnostics; any divergence/projection failure/release default falls back to legacy.

The domain readiness layer is report-only. `CanonicalAudioUploadDomainReadinessScorecard` records decision, commit, upload, retry, read, fallback, switch-back, diagnostics redaction, tests, docs and real-device evidence. Code can be complete without real-device evidence, but manual switch trial and legacy retirement remain blocked until paired-device long-recording evidence exists.

## 2026-06-11 Canonical v8.54 / P2-4 tombstoneConflict domain readiness architecture

v8.54 defines `tombstoneConflict` as the fourth domain-readiness target. The contract is modeled by `CanonicalTombstoneConflictBusinessFields`, `CanonicalTombstoneConflictHashSchema`, `CanonicalTombstoneConflictModifiedAtPolicy`, `CanonicalTombstoneConflictDecisionInput` and `CanonicalTombstoneConflictDecisionResult`, reusing existing tombstone/conflict objects and apply candidates rather than adding a new persistence format.

The hash schema is `canonical-tombstone-conflict-v1`. Stable business hash input includes markerID, objectID, objectKind, markerKind, conflictKind, tombstoneState, displayState, businessModifiedAt, actorDeviceRole, parentObjectID and conflictResolutionState. It intentionally excludes physical/delete target path, absolute/local/resource path, full object metadata/content, standalone note content, generated artifact content, provider response, audio path/hash/byteSize, upload progress, receive status, observedAt, receivedAt, UI-only state and diagnostics.

Decision ownership is marker-hash first, then logical time. Same marker hash is a no-op. When hashes differ and both sides have business modifiedAt/logical event time, the newer side wins; equal logical time becomes a deterministic conflict record/tie defer. Missing logical time, schema mismatch, unsupported report-only marker or unsafe write capability falls back or blocks legacy. Restore, clear tombstone, physical delete, permanent delete and tombstone GC are explicit blockers, and stale live resurrection is converted to a resurrection-block/conflict record rather than object restore.

Sync ownership now includes `tombstoneConflict` in `CanonicalSyncRuntimeDecisionScope`. The master switch still keeps default/release on `oldKernel`; diagnostics/shadow compare only; `canonicalDecisionOnly` can decide without apply; `canonicalApplyNoAudio` can use existing non-audio apply runtime; `canonicalFullSync` can combine decision, apply and guarded read under debug/internal owner-approved policy with legacy fallback.

Apply ownership uses the existing tombstone/conflict cutover executor. It remains root-bound, atomic, rollback-checkpointed, postcondition-verified and legacy-readable. It writes only soft tombstone markers, library tombstone markers, conflict records or resurrection block records. It must not perform physical delete, permanent delete, tombstone GC, generated artifact deletion, audio deletion, restore from absence, auto-resolve conflict, add routes or bypass existing route/security verification.

Read ownership uses `CanonicalReadRuntimeProvider` and `CanonicalTombstoneConflictReadProjection`. The read path can expose tombstone/conflict metadata and redacted hash prefixes only after the guarded read gate passes. Read evaluation has no side effects: no delete/restore/GC, no sync/upload/download, no Store mutation and no UI-only technical diagnostics. New `canonicalTombstoneConflictRead*` diagnostics alias the shared read runtime state and record that read did not trigger delete.

The domain readiness layer is report-only. `CanonicalTombstoneConflictDomainReadinessScorecard` records hash contract, write executor, decision runtime, apply runtime, read runtime, anti-resurrection, legacy fallback, switch-back proof, diagnostics redaction, tests, docs, real-device evidence, soft-marker/conflict-record-only scope, hash exclusions and unsafe delete/restore/GC blockers. Without paired-device evidence it can be code-complete but not a release/default cutover or legacy retirement signal.

## 2026-06-11 Canonical v8.53 / P2-3 generatedArtifacts domain readiness architecture

v8.53 defines `generatedArtifacts` as the third domain-readiness target. The contract is modeled by `CanonicalGeneratedArtifactBusinessFields`, `CanonicalGeneratedArtifactHashSchema`, `CanonicalGeneratedArtifactModifiedAtPolicy`, `CanonicalGeneratedArtifactDecisionInput` and `CanonicalGeneratedArtifactDecisionResult`, reusing existing `CanonicalArtifact` facts for transcript/note/summary artifacts instead of adding a new persistence format.

The hash schema is `canonical-generated-artifact-v1`. Stable business hash input includes artifactID, recording objectID, artifact kind, availability, content hash algorithm/value, byte size and business modifiedAt. It intentionally excludes logicalName, logicalPathToken, local/absolute path, observedAt, producedByNodeID, provider request/response, full transcript/note/summary content, diagnostics, upload ledger, receive state, audio bytes, security material and tombstone. Path movement or provider payload changes therefore cannot make a generated artifact business hash change.

Decision ownership is content-proof first, then modifiedAt. Same contentHash plus same byteSize is a no-op even when observation/path facts differ. Missing content hash/byteSize, unavailable/missing artifact content, unsupported kind/audio confusion, tombstone, schema mismatch or missing business modifiedAt blocks or falls back instead of applying. When both sides have proven different content and modifiedAt is available, newer modifiedAt wins; equal modifiedAt remains a deterministic deferred tie/conflict.

Sync ownership now includes `generatedArtifacts` in `CanonicalSyncRuntimeDecisionScope`. The master switch still keeps default/release on `oldKernel`; diagnostics/shadow modes compare only; `canonicalDecisionOnly` can make generated artifact decision primary without apply; `canonicalApplyNoAudio` can apply generated artifact downloads through the existing non-audio apply runtime; `canonicalFullSync` can combine decision, apply and guarded read. Any schema mismatch, conflict, missing evidence, divergence or release/default policy falls back/blocks legacy.

Apply ownership uses the existing generated artifact cutover/apply runtime boundary. It is still root-bound, atomic, rollback-checkpointed, postcondition-verified and legacy-readable. It can materialize/copy supported transcript/note/summary artifact files only through safe apply ports. It must not create generated artifact upload jobs, call AI providers, trigger transcription/note generation, write audio bytes, mutate receive/upload state, add routes, bypass artifact checksum/size verification or suppress legacy before successful commit.

Read ownership uses `CanonicalReadRuntimeProvider` and generated artifact metadata-only projection. The read path exposes availability, kind, IDs, byte size and hash prefixes, never full content or provider response. New `canonicalGeneratedArtifactRead*` diagnostics are aliases over the shared read runtime state and explicitly record `contentExcluded=true`. Read evaluation has no side effects: no sync/upload/download, no store mutation, no resource move and no production write.

The domain readiness layer is report-only. `CanonicalGeneratedArtifactDomainReadinessScorecard` records hash contract, decision runtime, apply runtime, read runtime, legacy fallback, switch-back proof, diagnostics redaction, tests, docs, real-device evidence, root-bound content write, content exclusion, provider-response exclusion and path exclusion. Without paired-device evidence it can be code-complete but not a release/default cutover or legacy retirement signal.

## 2026-06-11 Canonical v8.52 / P2-2 libraryMetadata domain readiness architecture

v8.52 defines `libraryMetadata` as the second domain-readiness target. The domain contract is modeled by `CanonicalLibraryMetadataBusinessFields`, `CanonicalLibraryMetadataHashSchema`, `CanonicalLibraryMetadataModifiedAtPolicy`, `CanonicalLibraryMetadataDecisionInput` and `CanonicalLibraryMetadataDecisionResult`, reusing existing `CanonicalLibraryObject` folder/study-item projections rather than introducing a parallel persistence format.

The hash schema is `canonical-library-metadata-v1`. Stable business hash input includes objectID, objectKind, title, itemKind, parentID, hierarchy path/level, filing path, folder IDs, parent references, tags, color token, ordering key, associated recording ID, deleted metadata and businessModifiedAt. It intentionally excludes note full content, generated artifact content, audio facts, local/resource paths, logical resource tokens, upload/receive/sync state, diagnostics, provider requests/responses and security material. Resource path or logical token changes therefore cannot make a libraryMetadata metadataHash change.

Decision ownership is explicit and deterministic. `CanonicalLibraryMetadataModifiedAtPolicy` treats equal hash as no-op, newer businessModifiedAt as the winning side, equal modifiedAt plus different hash as a deferred tie/conflict, and missing modifiedAt or schema mismatch as fallback/blocker. `CanonicalLibrarySyncPlanner` delegates metadata decisions to this policy, and `CanonicalSyncRuntime` gates libraryMetadata primary authority on matching `canonical-library-metadata-v1` schema when the domain is enabled.

Apply ownership uses the existing libraryMetadata cutover/apply runtime boundary. It is still root-bound, atomic, rollback-checkpointed, postcondition-verified and legacy-readable. It can apply metadata-only folder/item shell changes, but it must not move resources, write standalone note content, write generated content, write audio bytes, mutate upload/receive/session state, perform physical delete/GC, or bypass legacy fallback. Duplicate legacy suppression remains success-only and exact-match.

Read ownership uses `CanonicalReadRuntimeProvider` plus existing iPhone/Mac Store effective read paths. `canonicalFullSync` can serve canonical libraryMetadata projection only after the guarded read gate passes and divergence count is zero. Read evaluation is no-side-effect: it does not trigger sync/upload/download, does not mutate Store, does not move resources and does not expose local paths or content. New `canonicalLibraryMetadataRead*` diagnostics are domain aliases over the shared read runtime state.

The domain readiness layer is report-only. `CanonicalLibraryMetadataDomainReadinessScorecard` records hash contract, decision runtime, apply runtime, read runtime, legacy fallback, switch-back proof, diagnostics redaction, tests, docs, real-device evidence, metadata-only scope and resource-path exclusion. Without paired-device evidence it can be code-complete but not a release/default cutover or legacy retirement signal.

## 2026-06-11 Canonical v8.51 / P2-1 recordingMetadata domain readiness architecture

v8.51 defines `recordingMetadata` as the first domain-readiness target. The domain contract is modeled by `CanonicalRecordingMetadataBusinessFields`, `CanonicalRecordingMetadataHashSchema`, `CanonicalRecordingMetadataModifiedAtPolicy`, `CanonicalRecordingMetadataDecisionInput` and `CanonicalRecordingMetadataDecisionResult`, reusing the existing `CanonicalRecordingMetadata` canonical object rather than introducing a parallel format.

The hash schema is `canonical-recording-business-metadata-v1`. Its stable business hash input is objectID, title, filing type/subject/chapter/topic, normalized tags, isDeleted and deletedAt. It intentionally excludes createdAt, modifiedAt, duration, upload progress, upload ledger state, receive status, receivedAt, observedAt, local/audio path, audio hash/byteSize, processing status, diagnostics, provider response and transcript/note/summary/generated content. createdAt and duration can appear in read projection as recording facts, but they do not drive business metadata equality.

Decision ownership stays behind the main switch. `oldKernel` maps to legacy decision; diagnostics/shadow modes compare only; `canonicalDecisionOnly`, `canonicalApplyNoAudio` and `canonicalFullSync` can make recordingMetadata canonical decision primary only under explicit debug/internal owner-approved policy and legacy fallback. Missing snapshot, schema mismatch, unsupported object, modifiedAt unavailable without documented fallback, conflict or divergence falls back/blocks legacy. Duplicate legacy suppression is exact scope/object/action and only after canonical success.

Apply ownership uses the existing recordingMetadata cutover/apply machinery and `CanonicalRootBoundMetadataWrite`: root-bound target, atomic write, rollback checkpoint, postcondition verification and rollback-on-failure. It writes only legacy-readable metadata. It does not write audio bytes, create upload jobs, mutate upload ledger state, move resources, write receive session/chunk/finalize state, write standalone note/transcript/summary/generated content, perform tombstone/delete/GC, or alter route/security code.

Read ownership uses `CanonicalReadRuntimeProvider` and the iPhone/Mac Store effective read path. `canonicalFullSync` may serve canonical recordingMetadata projection only after the guarded read gate passes; default, release, shadow, decision-only and apply-no-audio read legacy unless an explicit read gate allows otherwise. Read evaluation does not trigger sync/upload/download, does not mutate store, and falls back to legacy on projection error, divergence, unsupported object, missing evidence or release/default policy. UI consumes effective recording metadata only through normal Store read models and must not display technical canonical diagnostics.

The domain matrix remains report-only. `CanonicalRecordingMetadataDomainReadinessScorecard` reports writeExecutorReady, decisionRuntimeReady, applyRuntimeReady, readRuntimeReady, legacyFallbackReady, switchBackProofReady, diagnosticsRedacted, testsPass, docsUpdated, realDeviceEvidencePresent, codeComplete and readyToRetireLegacyReportOnly. realDeviceEvidencePresent remains false until paired-device jsonl evidence exists; legacy retirement is not performed.

## 2026-06-11 Canonical v8.50 / P1-3 upload retry drain and state consistency architecture

v8.50 adds a shared upload-state truth layer above the v8.48 existence bridge and v8.49 commit executor. `CanonicalUploadStateTruth` gathers local audio existence/hash/byte size, canonical job store state, legacy upload ledger state, retry queue state, peer inventory existence, peer audio proof, Mac receive session/finalized proof, canonical existence ledger and tombstone/conflict facts. `CanonicalUploadStateReconciliationReport` projects one state and redacted diagnostics without changing the legacy read/UI path.

The state truth model treats only finalized audio proof as completion. `metadataOnly`, `receiveRecordOnly`, `studyItemOnly`, metadata uploaded and completed ledger alone are rejected as audio proof. Expected hash/size from a manifest is declarative metadata until Mac finalize or peer inventory proves finalized audio. PeerUnknown stays deferred. Same hash plus same byte size is the only no-op; different hash or size is conflict and cannot be overridden by upload job state.

`CanonicalUploadRetryDrainerPolicy` is an execution policy for retry draining, not a new transport. It can resume only existing eligible canonical or legacy retry records. It does not create fresh jobs, does not allow view refresh to create a job, skips peerUnknown/conflict/missing-local/tombstoned/security/malformed-ledger states, respects persisted backoff and max retry counts, and requires status refresh before stale interrupted sessions when the existing status route is available.

`CanonicalUploadDuplicateJobGuard` makes ownership explicit. `oldKernel` remains legacy owner. Diagnostics/shadow/decision/apply-no-audio modes create no canonical audio upload job. `canonicalFullSync` may select canonical only when the existing gate allows it; once a canonical job starts or finalize proof is accepted, exact legacy fresh duplicates are suppressed. If canonical is blocked before start or fails before writing peer data, safe legacy fallback remains available. Security failure and existing different audio conflict do not fallback by bypass or overwrite.

Existing secure boundaries are unchanged. iPhone upload still goes through `RecordingUploadCoordinator`, `RecordingUploadClient` and `SecureMacUploadClient`; Mac receive still goes through `SecureLocalHTTPSServer`, `RequestVerifier` and `MacRecordingFileStore`; upload routes remain start/status/chunk/finalize. v8.50 only adds state/projection diagnostics before the existing canonical executor path runs, and those diagnostics are redacted to object/session prefixes, state, reason, offsets, counts, sizes and hash prefixes.

## 2026-06-11 Canonical v8.49 / P1-2 audio upload commit architecture

v8.49 / P1-2 confirms and tightens the canonical audio upload commit executor instead of replacing the transport stack. The commit-facing API now exposes request/result/postcondition/blocker/fallback decision types over the existing `CanonicalAudioUploadRuntimeExecutor`; production execution remains selected only through explicit debug/internal runtime policy. Default and release configurations still resolve to disabled/legacy owner.

The runtime adapter is intentionally narrow. iPhone canonical upload calls the same secure upload abstractions already used by legacy upload: `RecordingUploadClient` and `SecureMacUploadClient` provide resumable start, status, chunk and finalize operations. The adapter does not create direct unsigned URLSession calls, does not add routes, and does not bypass certificate pinning, HMAC, nonce, body-hash signing or existing request construction.

Mac receive architecture is unchanged. `SecureLocalHTTPSServer` keeps the existing `/upload-recording-audio-session/start`, `/status`, `/chunk` and `/finalize` handlers; `RequestVerifier` remains the gate for those routes; `MacRecordingFileStore` owns partial-session storage and finalization. No `/abort` upload route exists in this implementation. Abort is therefore only a safe pre-finalize local/session cleanup concept when a port supports it, never a post-finalize delete.

Finalize is the commit boundary. Before finalize, partial upload state is not audio availability. Finalize must prove received byte count, final byte size and expected content hash when available. Only after proof can the iPhone-side upload ledger become completed, the retry job be removed/marked completed, and exact duplicate legacy upload suppression be allowed. Missing proof, byte-size mismatch or hash mismatch remains failed/conflict and does not mark uploaded.

Candidate selection consumes canonical existence truth from the v8.48 bridge. `metadataOnly`, `receiveRecordOnly` and `studyItemOnly` without audio can be upload candidates when local audio exists and policy is safe; they are not audio proof. `peerUnknown` is deferred. Same hash plus same byte size is the only audio no-op proof. Different hash/size, or Mac existing different audio, is conflict/no-overwrite. Completed upload ledger alone is explicitly rejected as no-op proof.

The session model is durable and resumable: session ID, confirmedBytes, totalBytes, chunkSize, expected hash, state and retry count persist through `CanonicalAudioUploadJobStore`/retry records. Resume refreshes server-confirmed status through the existing status route, then streams bounded chunks from the confirmed offset. Diagnostics expose only redacted object/session/state/offset/count/hash-prefix fields and never full hashes, absolute paths, secrets, fingerprints, request/response bodies or audio bytes.

## 2026-06-11 Canonical v8.48 / P1-1 manifest recordings apply architecture

v8.48 / P1-1 makes Mac apply consume `manifest.recordings` in the existing sync apply server path. The implementation reuses the canonical recording existence ledger under `sync/canonical-recording-existence/records/` and writes only metadata-only existence records. The ledger write remains root-bound, atomic, rollback-checkpointed and postcondition-verified. Old manifests without `recordings` remain backward compatible and decode to an empty list.

This is not audio upload commit. The apply bridge does not write audio bytes, create fake audio files, mutate legacy `receive.json`, mark upload completed, trigger transcription/note/chat, or make metadataOnly `audioAvailable`. It also does not change `/sync/inventory`, upload routes, route allowlists, TLS/HMAC/pinning/nonce/body-hash, `RequestVerifier`, read adapters, UI, Mac pending sync, retry draining, or master-switch mode mapping.

Mac inventory now merges canonical metadata-only existence records as recording facts: the recording exists, `audioAvailable=false`, `receiveStatus=canonicalMetadataOnly`, and no local audio checksum, byte size or audio path is reported unless a real audio file exists. Expected/declarative hash or size from the manifest stays metadata-only and is not local audio proof. Existing real audio with the same hash+size wins as no-op; different hash/size is a conflict/blocker and is not overwritten. Completed upload ledger alone is not an audio proof.

iPhone upload handoff remains legacy-execution based. The existing upload evaluator treats local audio + peer metadataOnly/receiveRecordOnly/studyItemOnly as an upload candidate, keeps peerUnknown deferred, treats same hash+size as the only no-op proof, treats different hash/size as conflict, rejects local-audio-missing candidates, and keeps view refresh/retry drainer guards. Canonical audio upload commit is intentionally out of scope for v8.48 and remains v8.49 / P1-2 work.

## 2026-06-11 Canonical v8.47 persistent checksum cache real hit

v8.47 / P0-2 is an inventory performance layer only. It does not change sync decision ownership, apply, upload, read paths, the canonical switch mode, `/sync/inventory`, routes, request verification, TLS/HMAC/pinning/nonce/body-hash, `receive.json`, audio inbox, Mac pending sync, retry draining, UI, or legacy fallback.

`CanonicalChecksumCacheStore` is the persistent checksum cache for canonical inventory facts. A cache key contains a safe logical/object-local token, byte size, mtime or contentVersion, hash algorithm, checksum schema version, node/platform role and optional store namespace. A cache record stores that key, algorithm, full hash value internally, diagnostics-only hash prefix, byte size, mtime/contentVersion, computedAt, schemaVersion, source role and validation state. Full hashes stay internal to the cache and must not be emitted in diagnostics.

The cache contract is fail-closed. A hit returns the stored hash and skips the hash provider. A logical token change is a miss; byte size, mtime/contentVersion, algorithm or schemaVersion changes are stale. Miss/stale entries recompute SHA256 off-main through the cache actor and detached hashing, then atomic-persist the record. Store/root corruption or single-record decode failure is ignored/rebuilt so sync can continue; `hashUnavailable` is never an equality proof. Pruning is bounded by configured record/byte caps, removes only cache records, and is reported with redacted diagnostics.

Runtime telemetry is measurement-backed. Inventory build, metadata load, jobs load, file scan, hash, cache load/write/prune durations are measured with a real clock or injected test clock. Cache hit/miss/stale/error, hash computed/failed/unavailable, duplicate build, snapshot reuse, main-actor hash/scan/metadata/jobs attempts and redaction violation counts come from runtime counters or detectors. Hardcoded fake success telemetry such as `MainActorHashBlocked count=0` is forbidden; a zero count is valid only when produced by the detector/counter path.

iPhone `performTick` builds one cache-backed local runtime snapshot per syncRunID and reuses it for end-of-tick success hash, canonical shadow/readiness and diagnostics. Cache hits across sync ticks or app restart avoid hash work; cache miss/stale recomputes in the background and does not affect legacy fallback. Mac `/sync/inventory` uses the same persistent checksum cache for audio/artifact facts and keeps the response schema/security boundary unchanged. The current Mac inventory method remains `@MainActor`; diagnostics must truthfully report that blocker until the Mac builder is moved off-main.

Performance reporting is diagnostic-only. `CanonicalInventoryPerformanceBudget`, `CanonicalInventoryPerformanceReport` and `CanonicalInventoryPerformanceRegressionGuard` warn on slow builds, low hit ratio, duplicate snapshots and any main-actor attempt, but they do not change business sync semantics. True completion still requires real-device before/after diagnostics and perceived UI latency comparison; simulator/unit results are not real-device evidence.

## 2026-06-11 Canonical v8.46 sync kernel completion architecture

v8.46 不改变主开关语义：`oldKernel` 仍是 default/release owner，`canonicalFullSync` 仍只允许 DEBUG/internal/manual trial，legacy fallback 必须保留。TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、upload route schema、Mac receive finalization 和 read fallback 没有变化。

iPhone inventory runtime 现在分为 MainActor 外的 background input/build path 与既有 legacy-compatible output path。调用方先解析安全 root URL，再在 detached utility task 中读取 recording metadata、study/library metadata、receive-derived item、folder、tombstone、pending upload、manifest recording 与 safe path facts，构建 `LocalNetworkSyncBackgroundStudyManifestBuild`。这条 path 不调用 MainActor-isolated `AudioFileStore.loadAllMetadata` 或 `RecordingUploadJobStore.loadJobs`，并把 metadata load、scan/hash、mainActor attempt/block 与 duplicate reuse 写入 `CanonicalInventoryRuntimeReport`。

同一 iPhone `syncRunID`、node role 与 source kind 的 runtime snapshot 由 actor cache 复用。首次构建产生真实 snapshot；同 tick 重复请求返回同一 manifest/inventory facts 并报告 duplicate build suppression/reuse。该设计的目标是减少重复扫描/hash 和 MainActor 压力，不改变 `/sync/inventory` wire schema 或 legacy diff/apply owner。

Mac `StudyLibraryStore.applySyncManifest` 现在有一个显式 existence bridge：只有调用方传入 non-disabled `CanonicalExistenceApplyRuntimeConfiguration` 和 `MacCanonicalRecordingExistenceApplyPort` 时，才消费 `manifest.recordings` 并写 canonical metadata-only existence ledger。默认 store 构造仍不写 ledger。该 bridge 只建立 recording existence truth，不写 audio bytes、不写 `receive.json`、不标记 upload completed、不触发 transcription/note/chat。

Mac inventory 仍存在架构 blocker：`SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 当前仍为 `@MainActor`。v8.46 只移除 fake zero telemetry，并用真实 attempt/block count 暴露该问题；它不是 Mac inventory off-main completion。

## 2026-06-08 Canonical sync kernel finalization wiring

本轮把 v8.45 从 report/gate-only 提升为同步链路 manual-trial code-complete wiring，但默认和 release 仍解析为 `oldKernel`。新增行为不迁移连接链路，不新增或修改 upload route，不改 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`，不删除 legacy，不禁用 fallback。

Read runtime 现在接入 iPhone `StudyLibraryStore`、Mac `StudyLibraryStore` 和主要 Store/UI read 边界。Store 保留 legacy backing arrays，并新增 effective read 输出；`oldKernel`、`canonicalShadow`、`canonicalDecisionOnly` 和默认路径返回 legacy，`canonicalFullSync` 只有在主开关 gate 允许且 diff clean 时才可 serve canonical projection，否则 fallback legacy。Read path 不触发 sync/upload，不写 store，不移动资源。

Audio upload runtime 的真实 commit executor 已由 `RecordingUploadCoordinator` 作为主开关控制的 canonical owner 分支接入。它复用 `IPhoneCanonicalSecureAudioUploadPort` 和现有 `SecureMacUploadClient` resumable start/status/chunk/finalize route；没有新增 route，也不绕过 Mac `SecureLocalHTTPSServer` / `RequestVerifier`。canonical branch 只在 `canonicalFullSync`/test transport 显式配置下进入；manual upload button、view refresh 和 retry-drainer fresh job 仍被阻断或 legacy-owned。

Switch-back proof 从内存 harness 扩展到 `CanonicalSwitchBackRealisticRootHarness`，使用 caller-provided test-cloned root 写入 legacy-v1 形状的 realistic library/app-data-root 证明文件，拒绝常见 production container root。证明仍是本地 test root，不是真机 paired-device evidence。

Completion scorecard 新增 `CanonicalSyncKernelCompletionDomainReadiness`，覆盖 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`recordingExistence`、`audioUpload`、`readRuntime`、`inventoryRuntime`、`syncDecisionRuntime`、`applyRuntime`、`kernelSwitch` 和 `legacyCompatibility`。状态新增 `unsafe`，manual switch gate 也检查 realistic-root switch-back proof readiness。缺真机日志时仍为 `codeCompleteNeedsDeviceEvidence`，不能报告 release/default canonical 或 legacy retirement。

## 2026-06-07 Canonical v8.45 sync kernel completion gate

v8.45 adds a report/gate layer above the v8.37-v8.44 canonical runtimes. It is modeled in `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`. This layer does not add a runtime owner, does not change default app wiring, does not change disk format, does not create upload jobs and does not authorize legacy retirement.

`CanonicalSyncKernelCompletionScorecard` records eleven required items: inventory runtime, diff/LWW runtime, existence truth, non-audio apply runtime, audio upload runtime, read runtime, master switch, legacy compatibility proof, switch-back proof, diagnostics redaction and real-device evidence. Status values are `incomplete`, `codeCompleteNeedsDeviceEvidence`, `readyForManualSwitchTrial`, `blocked`, `readyToRetireLegacyReportOnly` and the 2026-06-08 safety status `unsafe`. Code-complete without paired-device logs remains `codeCompleteNeedsDeviceEvidence`.

`CanonicalSyncKernelDomainReadyToRetireReport` is a domain-by-domain report for `recordingMetadata`, `libraryMetadata`, `generatedArtifacts`, `tombstoneConflict`, `audioUpload` and `recordingExistence/sync engine`. Each domain records write executor readiness, read cutover readiness, canonical runtime owner readiness, legacy fallback, switch-back proof, diagnostics cleanliness, real-device evidence and report-only ready-to-retire status. The report always keeps `retirementExecutionPerformed=false`, `legacyDeleted=false` and `legacyDisabled=false`.

`CanonicalSyncKernelEvidenceExporter` produces a bounded redacted package containing mode transitions, object counts, cache counts, plan used/fallback counts, apply success/failure, upload success/failure, read divergence, switch-back proof summary and redaction proof. It excludes absolute paths, full hashes, secrets, full fingerprints, request/response bodies, generated content/provider output and audio bytes.

`CanonicalSyncKernelManualSwitchGate` is the final pre-trial guardrail. It requires a code-complete scorecard, full legacy compatibility proof, switch-back proof, default `oldKernel`, release `oldKernel`, redacted diagnostics, legacy fallback, no unresolved blockers, owner approval and manual backup acknowledgement. Passing the gate only allows a manual trial of `canonicalFullSync`; release default remains disallowed.

The runbook for producing missing real-device evidence is `docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`. It defines phases from backup and oldKernel baseline through diagnosticsOnly, canonicalShadow, canonicalDecisionOnly, canonicalApplyNoAudio, canonicalFullSync, switch-back, paired-device new recording, Mac metadata-only existence, upload candidate, Mac audio receive, read projection, divergence monitoring, stop conditions, rollback and final evidence package.

## 2026-06-07 Canonical v8.44 legacy compatibility and switch-back proof

v8.44 adds a shared compatibility proof layer above the v8.43 manual switch. It is modeled in `RokuricsShared/SyncCore/CanonicalLegacyCompatibility.swift`. This layer does not add a new runtime owner, does not change default app wiring and does not authorize legacy deletion. Its only purpose is to prove that data written while `canonicalFullSync` is selected remains readable and writable after switching back to `oldKernel`.

The compatibility matrix covers seven domains: `recordingMetadata`, `libraryMetadata`, `generatedArtifacts`, `tombstoneConflict`, `recordingExistence`, `audioUpload` and `readRuntime`. For each domain the result records seven required proofs: canonical writes are legacy-readable, legacy writes are canonical-readable, switch-back requires no migration, there is no canonical-only required field, unknown fields are ignored or backward compatible, rollback is available and diagnostics are redacted.

The switch-back harness uses an in-memory legacy-v1 record shape with stable required fields. Canonical writes may add unknown optional fields, but old-kernel reads consume only legacy fields. Legacy writes may drop unknown fields, and canonical reads must still accept the legacy-v1 shape. Diagnostics are stored outside the data record, so diagnostic emission cannot mutate the format fingerprint. No physical delete operation exists in the harness.

Crash/restart simulation covers crash before checkpoint, after checkpoint before write, after write before postcondition and after postcondition before duplicate suppression. Restart is tested under both `oldKernel` and `canonicalFullSync`. Incomplete state must either be rolled back to the checkpoint or be complete enough for oldKernel to read; duplicate suppression is never applied after an interrupted postcondition. This is a compatibility proof, not paired-device production full-sync evidence.

## 2026-06-07 Canonical v8.43 unified manual kernel switch

v8.43 adds a single behavior-owner switch above the existing v8.37-v8.42 runtime configs. The switch is modeled in `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift` and resolves one `CanonicalKernelSwitchConfiguration` into the effective inventory/sync/apply/existence/audio/read/libraryMetadata/migration policies used by the app. It is not a disk-format switch and it does not authorize deleting legacy paths.

The mode model is `oldKernel`, `diagnosticsOnly`, `canonicalShadow`, `canonicalDecisionOnly`, `canonicalApplyNoAudio`, `canonicalFullSync` and `blocked`. Default construction and release construction resolve to `oldKernel`. `canonicalFullSync` requires debug/internal policy, owner approval, manual confirmation, non-release/default policy, legacy fallback and a successful reversibility proof.

| Mode | Owner state | Runtime ownership |
| --- | --- | --- |
| `oldKernel` | `oldKernel` | canonical owners disabled; legacy owns decision/apply/upload/read |
| `diagnosticsOnly` | `canonicalNoWrite` | diagnostics-only sync/apply/existence/audio plus inventory diagnostics; no commit/read serve |
| `canonicalShadow` | `shadow` | canonical noCommit plan/projection + read parallel compare; legacy execution/read |
| `canonicalDecisionOnly` | `canonicalNoWrite` | v8.38 primary decision with legacy apply/read fallback |
| `canonicalApplyNoAudio` | `canonicalReadWrite` | v8.40 non-audio apply/existence with legacy fallback; audio/read remain legacy |
| `canonicalFullSync` | `canonicalReadWrite` | v8.40 + v8.41 + v8.42 guarded read, all with legacy fallback |
| `blocked` | `blocked` | invalid/release/irreversible/mixed config maps every canonical owner to blocked |

`CanonicalKernelSwitchReversibilityGate` is the hard safety boundary. It requires legacy read/write path availability, legacy-readable or dual-write-compatible canonical writes, no migration required to switch back, no canonical-only required field without fallback, no physical move/delete, redacted diagnostics and retained shadow comparison while canonical owner is active.

iPhone integration injects the switch into `MacConnectionView`, `StudyLibrarySyncCoordinator`, `LocalNetworkSyncAppService` and `LocalNetworkSyncEngine`. Coordinator/engine refresh effective sync/apply configs at run/tick boundaries. Mac integration injects the switch through `RokuricsMacApp` into `SecureReceiverService` and then `SecureLocalHTTPSServer`; receiver observes the debug switch notification and rebuilds the HTTPS server when already running so the switch is bidirectional without data migration. Read adapters expose `fromCanonicalKernelSwitch(...)` factories.

Settings expose one DEBUG-only section, `Debug · 同步内核`, on iPhone and Mac. Release hides it. Switching to full sync requires confirmation; switching back to old kernel clears the confirmation and immediately posts the switch-change notification. The existing libraryMetadata pilot UI remains as an advanced specialized switch, not the primary entry.

## 2026-06-07 Canonical v8.42 read runtime v1

v8.42 introduces a unified canonical read runtime around Store/UI-facing read models. It is deliberately default-off: `CanonicalReadRuntimeConfiguration.disabled` returns the legacy read snapshot, release/default policy blocks canonical serving, and legacy fallback remains mandatory.

The shared runtime is centered on `CanonicalReadRuntimeProvider`. It is configured by `CanonicalReadRuntimeConfiguration`, `CanonicalReadRuntimeMode` and `CanonicalReadRuntimePolicy`, and returns `CanonicalReadRuntimeResult`. Modes are `disabled`, `parallelCompare`, `canonicalReadCandidate`, `guardedCanonicalReadWithLegacyFallback` and `blocked`. Disabled returns legacy. Parallel compare returns legacy and records diff/equivalence. Candidate builds canonical but does not serve it. Guarded canonical read is debug/internal owner-approved only and falls back to legacy whenever the gate fails.

`CanonicalReadSnapshot` is the unified read model. It contains `CanonicalRecordingReadProjection`, `CanonicalLibraryReadProjection`, `CanonicalArtifactReadProjection`, `CanonicalConflictReadProjection`, `CanonicalUploadReadProjection` and `CanonicalSyncEngineStatusReadProjection`. These projections are metadata/status summaries only: object IDs, titles, tags, folder summary, availability booleans, upload state, hash prefixes, counts and redacted diagnostics are allowed; absolute paths, full hashes, secrets, request/response bodies and full generated/transcript/note/summary/provider content are excluded.

The diff model is `CanonicalReadRuntimeDiff` with `CanonicalReadRuntimeDivergence` and `CanonicalReadRuntimeEquivalenceReport`. The runtime compares all six read domains: recording metadata, library metadata, generated artifacts, tombstone/conflict display state, audio/upload status and sync engine summary. Divergence kinds are missing object, metadata mismatch, title/tags/folder mismatch, artifact availability mismatch, tombstone/conflict mismatch, audio availability mismatch, upload status mismatch, unsupported object and path/content leak risk.

The read gate requires evidence from the earlier canonical runtime chain: v8.37 snapshot available, v8.38 plan authority evidence, v8.39 existence truth evidence, v8.40 apply runtime evidence for non-audio, v8.41 upload runtime evidence for audio status, divergence count zero, legacy fallback available, no conflicting domains, debug/internal policy, release/default disabled and manual owner approval. The runtime never calls apply/upload, never mutates store and never writes production data as part of read evaluation.

iPhone integration is `IPhoneCanonicalReadRuntimeAdapter`; Mac integration is `MacCanonicalReadRuntimeAdapter`. Both adapters build canonical-shaped snapshots from existing manifest/inventory inputs and pass them through the shared provider. They preserve existing app read boundaries: default legacy read remains the production owner, explicit guarded mode may serve canonical projection, and failed gates fall back to legacy while still recording canonical-vs-legacy comparison.

Mac receive architecture is unchanged. Canonical read evaluation does not mutate `/sync/inventory` responses, `receive.json`, audio inbox, pending sync, transcription, note generation, upload ledger or route/security state. iPhone evaluation similarly does not create upload jobs, drain retry jobs, move resources or write local production store state.

Diagnostics add `canonicalReadRuntime*` events for mode evaluation, canonical served, legacy fallback served, equivalent diff, divergent diff, blocked gate and report built. Output is bounded and redacted: object IDs, domains, modes, counts and safe summaries are allowed; full hashes, absolute paths, secrets, fingerprints, request/response bodies and content payloads are forbidden.

## 2026-06-07 Canonical v8.41 audio upload runtime commit v1

v8.41 introduces a canonical runtime owner for resumable audio upload execution, while keeping default/release production behavior on the legacy upload coordinator. This is not a default cutover: `CanonicalAudioUploadRuntimeConfiguration.default` is disabled, legacy fallback remains required, and release/default construction must not select canonical upload commit.

The shared runtime is centered on `CanonicalAudioUploadRuntimeExecutor`. It is configured by `CanonicalAudioUploadRuntimeConfiguration`, `CanonicalAudioUploadRuntimeMode` and `CanonicalAudioUploadRuntimePolicy`, and returns `CanonicalAudioUploadRuntimeResult`. Modes are `disabled`, `diagnosticsOnly`, `noCommit`, `testTransportUpload`, `canonicalUploadWithLegacyFallback` and `blocked`. Disabled uses legacy fallback. Diagnostics-only evaluates would-upload without job/network. NoCommit creates no job/network. Test transport is fake-loopback/test-only. Canonical upload with legacy fallback is debug/internal owner-approved only and must use an existing secure upload port.

The runtime state model is `CanonicalAudioUploadSession` plus `CanonicalAudioUploadSessionState`, `CanonicalAudioUploadChunk`, `CanonicalAudioUploadOffset`, `CanonicalAudioUploadFinalizeProof`, `CanonicalAudioUploadAbort` and `CanonicalAudioUploadRetryRecord`. States are idle, starting, started, chunking, interrupted, resuming, finalizing, finalized, failed, aborted, conflict and blocked. Confirmed bytes are monotonic; deterministic chunk offsets are derived from confirmed offset and configured chunk size; duplicate chunks with the same offset/length/hash are idempotent; wrong offsets fail or schedule retry; finalize requires matching byte size and content hash proof.

Large-file handling is streaming. `CanonicalAudioUploadByteSource` exposes byte size, checksum calculation and bounded `readChunk(offset:maxLength:)` reads. The canonical executor never needs the full audio file in memory. Retry persistence uses `CanonicalAudioUploadJobStore`, `CanonicalAudioUploadRetryPolicy` and `CanonicalAudioUploadResumeToken`; persisted records contain objectID, sessionID, offset, chunk size, hash prefix, byte size and state, but never absolute paths or full hashes.

The transport adapter deliberately sits on existing secure routes and clients. iPhone `IPhoneCanonicalSecureAudioUploadPort` wraps the existing `RecordingSecureUploadTransport` methods implemented by `RecordingUploadClient` / `SecureMacUploadClient`: resumable start, status, chunk and finalize. It does not construct unsigned requests, does not add routes, and does not bypass TLS pinning, HMAC, nonce or body hash. Abort has no network route in v8.41 and is local pre-finalize cleanup only.

Mac receive architecture is unchanged. Existing `SecureLocalHTTPSServer` resumable handlers and `RequestVerifier` remain the route and verification boundary. `MacRecordingFileStore` continues to write final audio only after finalize verifies received byte count, file size and expected checksum. Existing different audio remains a conflict/no-overwrite case. `AudioInboxStore` and receive records must reflect real audio availability only after proof, not metadata-only existence.

Candidate decisions reuse v8.39 existence truth. Local audio plus peer metadataOnly, receiveRecordOnly or studyItemOnly is an upload candidate when policy allows. Peer same hash+size is the only audio no-op. PeerUnknown is deferred. Peer different hash/size is conflict. Metadata uploaded, receive record, UI uploaded and completed ledger alone are not audio proof. View refresh cannot create a fresh upload job; retry drainer can only replay an eligible existing retry record.

Diagnostics add `canonicalAudioUploadRuntime*` events for mode, candidate, start, chunk sent/confirmed, resume, finalize, retry, fallback, peerUnknown defer, conflict, existing different audio and completed-ledger rejection. Output is redacted and bounded: object IDs, enum states, counts, byte sizes and hash prefixes are allowed; full hashes, absolute paths, secrets, fingerprints, request/response bodies, transcript/note/summary/provider output and audio bytes are forbidden.

True validation still requires a paired-device long-recording run: create or select a large local recording, observe metadata-only or receive-record-only peer truth, upload through existing secure transport, verify chunk resume/finalize, and confirm Mac hash/size plus inbox postcondition. Simulator/unit tests do not replace that evidence.

## 2026-06-07 Canonical v8.40 apply runtime owner v1

v8.40 makes `CanonicalApplyPlan` executable for selected non-audio domains, but only behind explicit runtime configuration. Default and release behavior remains legacy apply owner, legacy fallback remains available, and `runtimeSwitch`/read-side ownership stay off. This is not legacy retirement and not a UI/read-path cutover.

The shared runtime owner is `CanonicalApplyRuntimeOwner`, configured by `CanonicalApplyRuntimeConfiguration`, `CanonicalApplyRuntimeMode` and `CanonicalApplyRuntimePolicy`. Modes are `disabled`, `diagnosticsOnly`, `noCommit`, `testRootApply`, `productionRootApplyWithLegacyFallback` and `blocked`; the default is `disabled`. `diagnosticsOnly` only compares canonical apply intent with legacy apply intent, `noCommit` only reports would-apply/staging semantics, `testRootApply` may execute non-audio domains against a test root, and `productionRootApplyWithLegacyFallback` is debug/internal owner-approved only. Release/default production-root apply is always blocked.

`CanonicalApplyRuntimeGate` is the execution boundary. It requires v8.38 canonical plan authority or explicit no-commit, a valid v8.37 inventory snapshot, a valid apply plan, explicit enabled domains, a matching executor, root-bound apply capability for test/production modes, rollback and postcondition capability, legacy fallback, redacted diagnostics, `runtimeSwitch=false` and legacy read path. It blocks unresolved conflicts unless conflict-record apply is explicitly enabled, audio actions, resource moves, standalone note content writes, permanent delete/tombstone GC, unsupported domains and missing executors.

`CanonicalApplyRuntimeExecutorRegistry` maps `recordingMetadata`, `libraryMetadata`, `generatedArtifacts`, `tombstoneConflict` and `recordingExistence` to existing per-domain cutover/bridge executors. `audioUpload` is registered as unsupported in v8.40 and must block. Execution is sequential: precondition, rollback checkpoint, domain commit, postcondition, diagnostics. The first failure stops later actions unless a future policy proves safe continuation; rollback failure is fatal. Duplicate legacy suppression is allowed only after a canonical action succeeds and exactly matches the legacy action; diagnostics/noCommit/blocked/failure never suppress legacy.

iPhone integration sits in `StudyLibrarySyncCoordinator.performTick` after the v8.38 runtime plan is built and before legacy apply execution. Default remains legacy; explicit debug/internal runtime may execute enabled non-audio actions through the registry and then suppress exact successful duplicates. It does not create upload jobs outside the existing legacy upload path, does not change retry draining, does not write audio bytes and does not change UI/read path.

Mac integration keeps the existing receiver/server route and security model. `SecureReceiverService` passes default-disabled configuration into `SecureLocalHTTPSServer`; the Mac existence bridge is evaluated through the v8.40 gate/registry boundary and then delegates to the existing v8.39 metadata-only ledger bridge. No route schema changes, no RequestVerifier/TLS/HMAC/pinning/nonce/body-hash bypass, no `receive.json` mutation beyond documented legacy behavior or the separate v8.39 canonical existence ledger, no audio byte write, and no transcription/note generation trigger.

Diagnostics add `canonicalApplyRuntimeModeEvaluated`, gate allowed/blocked, action started/completed/failed, rollback started/completed/failed, legacy fallback, duplicate suppression, audio action blocked and report-built events. They are redacted and may include mode/domain/action/object IDs, counts and hash prefixes only. Full metadata JSON, full hashes, absolute paths, secrets, fingerprints, request/response bodies, transcript/note/summary/provider content and standalone note content remain forbidden. True validation still requires real-device apply diagnostics; simulator/unit tests only prove code paths and guard behavior.

## 2026-06-07 Canonical v8.39 existence/apply bridge runtime v1

v8.39 closes the existence gap between the learning-library manifest channel and the Mac audio-inbox truth channel. `StudyLibrarySyncManifest` now carries backward-compatible `recordings` facts, and the Mac canonical existence apply bridge can consume `manifest.recordings` to create a metadata-only canonical existence record. This is an existence/apply bridge only: it does not write audio bytes, does not create fake audio files, does not mark metadata as audio, does not migrate the large-file upload runtime, and does not switch UI or read path ownership.

Shared truth is modeled by `CanonicalRecordingExistenceTruth`, `CanonicalRecordingExistenceState`, `CanonicalRecordingExistenceSource`, `CanonicalRecordingExistenceDecision` and `CanonicalRecordingExistenceBlocker`. The state model distinguishes absent, metadataOnly, receiveRecordOnly, studyItemOnly, metadataAndStudyItem, audioAvailable, audioHashSizeMatched, audioConflict, peerUnknown, tombstoned and unsupported. Audio no-op requires matching hash and byte size; peerUnknown stays deferred; completed receive ledger, study item, metadataOnly and receiveRecordOnly are not audio proof; different hash or size is a conflict.

Mac apply uses `CanonicalRecordingManifestApplyBridge` plus `MacCanonicalRecordingExistenceApplyPort`. Because the existing `receive.json` inbox store feeds the Mac read path, v8.39 intentionally uses a separate canonical metadata-only existence ledger under the app root at `sync/canonical-recording-existence/records/`. The ledger is root-bound, atomic, rollback-checkpointed and postcondition-verified. It stores only redacted metadata-only existence facts and never writes `audio/inbox`, `receive.json`, upload-completed ledger state or audio bytes.

Mac inventory merges the canonical existence ledger only when `CanonicalExistenceApplyRuntimeConfiguration` is explicitly non-disabled. A merged metadata-only record appears as a peer recording that exists, but `audioAvailable=false`, and content hash, byte size and logical audio path are omitted unless proven by real audio facts. If both legacy inbox facts and canonical ledger facts exist, inventory normalizes to one recording object and reports conflict/blocker diagnostics on divergence rather than lying about audio availability.

iPhone sync diagnostics now evaluate canonical existence truth from the v8.37 snapshot plus peer inventory. Local audio plus peer metadataOnly/receiveRecordOnly/studyItemOnly can become an upload candidate through the existing legacy `RecordingUploadCoordinator` evaluator path; same hash+size is no-op; peerUnknown is deferred; different hash/size is conflict; absent peer records metadata-bridge-required diagnostics. No upload job is created from view refresh, retry draining still processes only eligible existing retries, and upload routes/security remain unchanged.

`CanonicalExistenceApplyRuntimeConfiguration` supports `disabled`, `diagnosticsOnly`, `noCommit`, `testRootApply`, `productionRootApply` and `blocked`. Default and release behavior is disabled. `productionRootApply` is only for explicit debug/internal owner-approved use with root-bound writes, rollback, atomic persistence and postconditions, and it still cannot write audio or mark audio available. Legacy apply/upload fallback remains available.

Diagnostics include the v8.39 `canonicalExistence*` taxonomy for truth evaluation, apply bridge evaluation/block/no-op/write, rollback, metadataOnly upload candidates, peerUnknown defer, same-audio no-op, conflict, manifest recordings consumed/blocked, and explicit no-audio/no-audioAvailable assertions. Diagnostics are redacted: objectID, action/state/reason, hash prefix and byte count are allowed; full metadata JSON, full hash, absolute paths, secrets, fingerprints and request/response bodies are not.

True completion still requires a new-recording iPhone-to-Mac real-device test: manifest recording consumed on Mac, metadata-only existence visible in peer inventory, peer metadataOnly upload candidate produced on iPhone, existing secure upload coordinator creates the audio job, and Mac receives the audio without peerUnknown/defer/conflict surprises.

## 2026-06-07 Canonical v8.38 sync decision runtime v1

v8.38 introduces a guarded decision-runtime layer above the v8.37 inventory runtime. It does not make canonical the default owner: default and release construction keep legacy diff/apply/read/upload ownership, with legacy fallback always retained.

The shared runtime types are `CanonicalSyncRuntimeConfiguration`, `CanonicalSyncRuntimeMode`, `CanonicalSyncRuntimePolicy`, `CanonicalSyncRuntimeResult`, `CanonicalSyncPlanAuthorityGate`, `CanonicalSyncPlanAuthorityGateResult`, `CanonicalSyncPlanAuthorityBlocker` and `CanonicalSyncRuntimeDuplicateExecutionGuard`. Supported modes are `disabled`, `diagnosticsOnly`, `canonicalPlanNoCommit`, `canonicalPlanPrimaryWithLegacyFallback` and `blocked`; the default is `disabled`.

`CanonicalSyncPlanAuthorityGate` is the authority boundary for using canonical as a primary decision owner. It requires a v8.37 inventory snapshot, valid local canonical manifest, available peer canonical manifest or explicit peer absence model, matching metadataHash schema, available canonical modifiedAt semantics, zero unsupported legacy objects for the enabled scope, zero library fallback-required objects, zero conflicts for primary mode, no peer-unknown audio interpreted as missing, legacy fallback availability, redacted diagnostics, no conflicting active migration domain, and explicit debug/internal owner approval for primary mode. Release/default primary is always blocked.

Canonical truth for recording metadata is now named by `canonical-recording-business-metadata-v1`. The hash is scoped to stable business metadata only; upload progress, receive/observe timestamps, local paths, generated content and processing state do not participate. LWW decisions use canonical business `modifiedAt`; equal modifiedAt ties remain deterministic no-op/defer/conflict policy rather than automatic overwrite. An old iPhone business-modifiedAt fallback is reportable and can block primary unless an explicit internal policy allows the documented fallback.

iPhone `StudyLibrarySyncCoordinator.performTick` still builds the legacy plan first. It then builds canonical sync/apply/library plans from the v8.37 snapshot and evaluates the authority gate. `diagnosticsOnly` compares without changing owner, `canonicalPlanNoCommit` records would-use canonical but executes legacy, and `canonicalPlanPrimaryWithLegacyFallback` can own only enabled metadata/library/recording-existence decisions when the gate allows. It does not run production apply, write production root, create upload jobs, take over audio upload runtime, change retry draining, switch read path or change UI.

Mac integration is report-only in the inventory/server context. `SecureLocalHTTPSServer` evaluates runtime plan readiness after the cache-backed inventory snapshot is built and records redacted diagnostics. It does not change `/sync/inventory` schema, routes, `RequestVerifier`, TLS/HMAC/nonce/body-hash, `receive.json`, audio inbox, pending sync or artifact/upload routes. Missing peer snapshot blocks primary and preserves legacy/report-only behavior.

The duplicate execution guard suppresses only exact duplicate legacy actions for the same object/action/scope when canonical is the actual primary owner. Diagnostics/no-commit/blocked canonical planning never suppresses legacy, and planning failures fail open to legacy fallback. This prepares the v8.39 apply/existence bridge without performing production apply in v8.38.

## 2026-06-07 Canonical v8.37 inventory runtime v1

v8.37 adds a runtime layer below the existing legacy inventory owner. It is a latency/stability change, not a diff/apply cutover: legacy inventory wire schema, `/sync/inventory`, legacy planner/apply, upload jobs, retry drainer, Mac pending sync, read path, UI, routes and security verification remain unchanged.

The shared runtime types are `CanonicalInventoryRuntimeSnapshot`, `CanonicalInventoryRuntimeBuilder`, `CanonicalInventoryRuntimeConfiguration`, `CanonicalInventoryRuntimeResult`, `CanonicalInventoryRuntimeDiagnostics`, `CanonicalInventoryRuntimeFailure`, `CanonicalInventoryRuntimeReport` and `CanonicalInventoryRuntimeReportExporter`. A snapshot records only safe facts: syncRunID, nodeRole, source kind, build timing, object counts, cache hit/miss/stale/error counts, scan/hash counts, duplicate-build count and main-actor blocker counts. It intentionally excludes absolute paths, full hashes, secrets, fingerprints, full metadata JSON, transcript/note/summary content and request/response bodies.

`CanonicalChecksumCacheStore` is the persistent checksum cache used by both iPhone and Mac inventory runtime paths. Its key includes a safe logical token, byte size, mtime, hash algorithm, schema version and node role. Cache hits return without hashing; stale/miss entries compute SHA256 in a detached utility task and persist atomically under the app data/cache root. Cache corruption fails closed by recomputing or returning hashUnavailable; hashUnavailable is never an equality proof.

iPhone `StudyLibrarySyncCoordinator.performTick` now builds one async local runtime inventory per syncRunID and reuses that result for the end-of-tick success hash instead of rebuilding. Mac `SecureLocalHTTPSServer` uses cache-backed checksum facts for `/sync/inventory` and inventory-backed artifact lookup/status, but the builder method is still `@MainActor` in current source. Canonical shadow/readiness/diagnostics must consume already-built facts and must not trigger a second inbox/audio hash pass.

Historical v8.37 expectation was zero main-actor blocker count on normal inventory paths. v8.46 supersedes that wording: iPhone background inventory should report zero main-actor attempts/blockers, while the current Mac inventory path truthfully reports a main-actor blocker until its `@MainActor` builder is moved off-main. Real validation still requires paired-device diagnostics comparing cache hit/miss/stale counts, duplicate build count and perceived sync UI latency.

## 2026-06-07 LibraryMetadata real-device debug switch wiring

The libraryMetadata pilot now has a small real-device preflight wiring layer in the app shell. iPhone and Mac Settings expose a `DEBUG`-only hidden section named `Debug · 学习库迁移试点`; release/default builds do not show it and still resolve to `.disabled` with no executor.

The switch maps local UserDefaults values to the existing `CanonicalLibraryMetadataDebugPilotConfiguration` factories and existing platform bootstraps. `off` returns `.disabled` plus nil executor. `diagnosticsOnly` returns `.diagnosticsOnly(...)` and nil executor. `armTestRootN1` and `executeTestRootN1` create a UUID test root under the system temporary directory and use `IPhoneLibraryMetadataProductionCanaryBootstrap.prepare(...)` or `MacLibraryMetadataProductionCanaryBootstrap.prepare(...)` to build the existing executor. `executeProductionRootN1` requires UI confirmation and a safe app/store root; only that mode can pass `allowProductionRootWrites=true`.

iPhone injection happens at the existing `MacConnectionView` construction of `StudyLibrarySyncCoordinator`. Mac injection happens at `RokuricsMacApp.makeSecureReceiverService()` and is forwarded through `SecureReceiverService` to `SecureLocalHTTPSServer`. This does not add a route, bypass `RequestVerifier`, change TLS/HMAC/pinning/nonce/body-hash checks, change upload routes, mutate `receive.json`, switch read path, move resources, delete legacy, disable fallback, or enable any non-libraryMetadata domain.

Diagnostics path text is shown in redacted form only. Mac certificate fingerprint logs are prefix-only. Completion still requires real-device diagnostics files; unit tests and simulator builds are not real-device pilot evidence.

## 2026-06-06 Canonical v8.32 libraryMetadata N=1 evidence audit and N=3 readiness gate

v8.32 adds a report-only audit layer above the v8.31 production-root N=1 pilot. It does not call the canary runner, does not construct an executor, does not write production root, does not execute N=3/allEligible, does not switch read source, and does not change UI or legacy ownership. Default and release architecture remains disabled; runtime switch remains false; other domains remain staticOnly/default-off.

The shared audit model is `CanonicalLibraryMetadataN1EvidenceBundle`. It can be built from existing redacted landing reports, real canary observation reports, production-root safety proof, LandingFreeze result and bounded diagnostics, or from an explicit safe test fixture. The importer treats missing reports as `missingEvidence` and never requires a production run to exist. The bundle stores only modes, enum domains/kinds, counts, booleans, redacted source IDs and redacted diagnostics summaries. It excludes full metadata JSON, note content, transcript/note/summary/provider output, absolute paths, full hashes, secrets, fingerprints and request/response bodies.

`CanonicalLibraryMetadataN1PostRunInvariantValidator` checks the post-run boundaries: zero or one executed candidate; executed domain remains `libraryMetadata`; candidate kind is metadata-only; no resource move, standalone note content write, tombstone/delete, generated artifact write, audio change, read path switch or UI mutation; runtimeSwitch=false; legacy fallback available; read-side parallel executed with divergence=0; rollback failure count=0; duplicate suppression implies commit success; other domains staticOnly; release/default disabled. Mac-specific reports can mark RequestVerifier/route boundary or `receive.json` mutation as invalid evidence without changing server routes.

`CanonicalLibraryMetadataN3ReadinessGate` consumes the evidence bundle and emits a report-only readiness result. `readyForN3AfterManualAudit` requires valid N=1 evidence, commit success or accepted no-change/no-eligible policy, zero rollback failure/divergence/unsafe side effects, static other domains, runtimeSwitch=false, release/default disabled, legacy fallback, manual audit, owner approval and N=3 disabled by default. The gate cannot execute N=3 and cannot disable legacy.

## 2026-06-06 Canonical v8.31 libraryMetadata production-root N=1 pilot

v8.31 keeps the pilot architecture scoped to `libraryMetadata`, but opens one production-root write path only behind explicit internal/debug N=1 configuration. The default and release architecture remains unchanged: app constructors pass `.disabled` config and nil executor, no runtime switch exists, read source remains legacy, UI remains unchanged and all non-libraryMetadata domains stay static/default-off.

The new `CanonicalLibraryMetadataProductionRootGate` sits in front of `CanonicalLibraryMetadataProductionCanaryInjection` when `rootMode=productionRootExplicit`. It requires `mode=executeN1Canary`, `allowProductionRootWrites=true`, owner approval, LandingFreeze green, the v8.30 diagnostics/arm/testRoot evidence set, read-side divergence zero, rollback evidence, legacy fallback, productionRootBound apply-port evidence, checkpoint availability and postcondition verification capability. It also rejects N>1, allEligible, non-libraryMetadata domain, runtime switch, release/default enablement, unsafe candidates, resource move, content write and tombstone/delete.

Execution still delegates to the strict N1 runner and existing root-bound apply ports. The write sequence is checkpoint -> atomic metadata write -> postcondition verification -> read-side parallel comparison. Success records a production-root safety proof and suppresses only the exact matching legacy `libraryMetadata` duplicate. Failure preserves legacy fallback; write/postcondition failure rolls back; rollback failure is fatal and suppresses nothing. The proof is deliberately redacted: it records containment, explicit root mode, logical token safety, checkpoint id, atomic/postcondition/rollback flags, side-effect whitelist status and a target summary without root paths or full metadata JSON.

iPhone and Mac production canary bootstraps now construct productionRootBound real apply ports only when the caller supplies explicit production-root config, `allowProductionRootWrites=true` and an explicit root URL. TestRoot construction remains separate. The Mac server route boundary, `RequestVerifier`, TLS/HMAC/nonce/body hash, upload routes, `receive.json`, audio inbox and pending sync are not part of this write path. This is not read-side cutover or retirement; legacy read/write/fallback remains the production owner outside the one approved pilot object.

## 2026-06-06 Canonical v8.30 libraryMetadata diagnostics / arm / test-root drill

v8.30 keeps the canonical pilot architecture scoped to `libraryMetadata`. It does not add new active stages for `generatedArtifacts`, `tombstoneConflict`, `audioUpload` or `recordingMetadata`. The debug pilot has three useful internal phases: `diagnosticsOnly` runs LandingFreeze and emits a redacted summary with no candidate selection; `armN1Canary` performs readiness-only N=1 candidate/rollback/read-side/fallback checks without an executor or write port; `executeN1Canary` can commit only through an explicit testRoot apply port.

The production path remains closed. `productionRootExplicit` is blocked in v8.30, and `allowProductionRootWrites=true` is a blocker rather than an override. The iPhone and Mac production-canary bootstraps therefore do not construct an apply port or executor for production-root mode. Default/release app construction still supplies `.disabled` config and nil executor, so there is no default canary, no production-root write, no UI toggle and no read-source switch.

LandingFreeze is now the architectural guard for pilot drift: it rejects multiple active pilots, non-`libraryMetadata` active pilots, non-static other domains, runtime switch, release/default enablement, non-legacy read path, default production injection/root writes, missing legacy fallback, N>1, allEligible, unsafe candidate, resource move, content write and tombstone/delete allowance. The read path remains legacy; read-side evidence stays parallel/report-only.

Safe diagnostics are separated from execution. `CanonicalLibraryMetadataPilotDiagnosticSummary` and exporter report only bounded fields such as mode, nodeRole, activePilot, freeze status, candidate selected/kind, canary/rollback/fallback booleans, duplicate-suppression count and read-side divergence count. Redaction rules exclude full metadata JSON, standalone note content, transcript/note/summary/provider output, absolute paths, full hashes, secrets, fingerprints and request/response bodies.

## 2026-06-06 Canonical v8.29 libraryMetadata real-device pilot landing

v8.29 lands on `libraryMetadata` only. The new `CanonicalMigrationLandingFreeze` is stricter than the historical matrix helpers: for this landing run the only accepted active pilot is `libraryMetadata`; `generatedArtifacts`, `tombstoneConflict`, `audioUpload`, `recordingMetadata`, `uiProjection` and `legacyRetirement` must remain static/default-off, with runtime switch, release/default cutover and non-library production injection disabled. This intentionally overrides earlier exploratory active-pilot history for the current landing scope.

The landing architecture is a wrapper, not a second write path. `CanonicalLibraryMetadataDebugPilotBootstrap` evaluates freeze/config, then delegates to the existing `CanonicalLibraryMetadataProductionCanaryInjection` and `CanonicalLibraryMetadataN1CanaryRunner`. Execution is possible only with explicit internal/debug configuration, owner-approved token, rollback plan, write-side evidence, read-side parallel equivalence, non-dry-run root-bound apply-port evidence, local/peer canonical snapshots and an injected executor. Default config is disabled and cannot create an executor or apply port.

Candidate scope is metadata-only and capped at one object per sync run. Allowed shapes are folder rename/color metadata, study item tags/filing/folder membership metadata and standalone note title/tags/filing metadata. Resource moves, folder hierarchy mutations, standalone note content writes, generated artifact writes, audio/upload actions, tombstone/delete/trash/permanent delete/GC, parent missing, cycles, objectID instability, unresolved conflicts, unsafe paths and unsupported objects/actions are blockers. Commit success requires precondition, root-bound apply, postcondition and rollback checkpoint evidence.

iPhone `StudyLibrarySyncCoordinator` has a default-disabled v8.29 config/executor injection path. When enabled explicitly, it runs before the older libraryMetadata seam and owns that run, so a v8.29 pilot cannot double-execute through v8.15/v8.16. The legacy plan remains the production fallback; duplicate suppression is success-only and applies only to exact matching libraryMetadata legacy duplicates after canonical commit success and verified postcondition. Legacy `StudyLibraryStore` read/write and UI bindings remain unchanged.

Mac `SecureReceiverService` and `SecureLocalHTTPSServer` expose the same default-disabled config/executor pass-through. The real inventory route still has no peer snapshot and therefore records blocked/fallback/report diagnostics only; it does not fetch peers, call executors, add routes, bypass `RequestVerifier`, change TLS/HMAC/nonce/body-hash checks, mutate inventory response, write `receive.json`, audio inbox, pending sync or transcription/note-generation state. Direct tests/internal harnesses can use `MacLibraryMetadataRealApplyPort(testRootURL:)` with the shared bootstrap for root-bound N=1 verification.

Read-side behavior remains parallel evidence only. The landing report records read-side equivalence/divergence and always reports `uiReadPathSwitched=false`, `legacyReadPathPreserved=true`, `resourceMoved=false` and `uploadJobCreated=false`. A successful N=1 recommends another audited N=1 rather than automatic read-side cutover or legacy retirement.

## 2026-06-05 Canonical v8.28 tombstoneConflict canary N=1

v8.28 keeps `tombstoneConflict` as the sole active pilot and adds the first executable canary path, but only behind explicit internal/test N=1 configuration. Default app and release configuration remain disabled with canary budget zero. The N1 runner requires the v8.27 active-pilot matrix, no other active pilot, owner-approved cutover token, rollback plan, NoCommit evidence, dry-run equivalence, execution shadow, real-data shadow copy, read-side parallel equivalence, anti-resurrection evidence, legacy fallback, duplicate-suppression policy and non-dry-run root-bound apply-port evidence.

Candidate selection is deterministic and capped at one executable candidate. It prefers conflict record / resurrection block records before soft tombstone markers, then treats generated artifact tombstone marker as unsupported/report-only. Executable candidates are limited to soft object/library tombstone marker apply/send, conflict record commit and resurrection block record. Physical delete, permanent delete, tombstone GC, restore, tombstone clearing, ambiguous auto-resolution, stale live resurrection, generated artifact apply/download on a tombstoned parent, audio actions, full content mutation, unsafe path token, missing rollback checkpoint and unsupported object/action are blockers.

iPhone `StudyLibrarySyncCoordinator` now routes explicit `.canaryCommit` + N=1 tombstoneConflict config to `CanonicalTombstoneConflictN1CanaryRunner` with an injected executor. The default executor remains nil, so normal construction cannot write by accident. A successful canary writes only a root-bound soft marker or conflict ledger record, verifies postcondition, records read-side parallel diagnostics and then suppresses only matching tombstoneConflict legacy duplicates. Commit failure rolls back and preserves legacy fallback; rollback failure is fatal for the canary and suppresses nothing.

Mac support remains boundary-preserving. Constructor injection exists for tests and future explicit execution, but `/sync/inventory` does not add routes, does not bypass `RequestVerifier`, does not mutate upload routes, response shape, `receive.json`, audio inbox, transcription/note generation or pending sync. If the required peer snapshot is missing, the N1 path records blocked/fallback diagnostics and performs no commit. UI/read path remains legacy; read-side parallel diagnostics never write UI state or trigger sync/upload.

## 2026-06-05 Canonical v8.27 tombstoneConflict active pilot guarded seam N=0

v8.27 promotes `tombstoneConflict` from the v8.26 next-pilot candidate to the sole active pilot, but only for guarded commit gate evaluation with canary budget fixed at `N=0`. `generatedArtifacts` is no longer the active pilot; its write/read/observation evidence remains a prerequisite. No canary execution, domain cutover, read-side cutover, runtime switch, UI change or legacy retirement is introduced.

The shared architecture adds `CanonicalTombstoneConflictGuardedCommitSeam`, active-pilot activation checks, a guarded gate, evidence report, no-execution assertion, N1 readiness report and v8.27 diagnostics. The gate accepts only explicit `.guardedExecuteCommit` / `.canaryCommit` evaluation with owner-approved token, local/peer snapshots, generatedArtifacts/library template evidence, root-bound rollback/apply evidence, conservative tombstone policy and canary budget zero. It blocks N1/staged/allEligible/runtime switch, missing evidence, unsupported domains/actions, physical delete, permanent delete, tombstone GC, restore, tombstone clear, stale-live resurrection, ambiguous conflict resolution and generated artifact tombstone marker apply.

iPhone `StudyLibrarySyncCoordinator` now has a default-off tombstoneConflict guarded seam after the generatedArtifacts guarded seam and before library/legacy action selection. Mac `SecureLocalHTTPSServer` has a default-off inventory seam that can only report because the inventory request has no peer snapshot. Both seams record redacted diagnostics and fixed no-execution state: no commit, no tombstone marker write, no tombstone clear, no restore, no physical/permanent delete, no GC, no auto conflict resolution, no duplicate suppression, no store/UI/response mutation, no upload job, no network send, no retry drainer or Mac pending sync change.

## 2026-06-05 Canonical v8.26 tombstoneConflict template alignment

v8.26 aligns `tombstoneConflict` with the migration template used by `libraryMetadata` and `generatedArtifacts`, but only as a next-pilot candidate. The active pilot does not move to `tombstoneConflict`; no canary stage, domain cutover, read-side cutover, runtime switch, UI change or legacy retirement is introduced. `generatedArtifacts` remains the active pilot from the prior stage.

The shared architecture adds `CanonicalTombstoneConflictReadProjection`, read-side parallel diff, template readiness report, anti-resurrection gate, observation window/gate and report-only retirement candidate gate. Projection is metadata-only: object id/kind, tombstone state, deleted display state, timestamp summary, conflict kind/status, active-vs-tombstone state, anti-resurrection status, soft marker presence and hash prefix. It explicitly excludes full metadata, generated content, absolute paths, delete target paths, full hashes, request/response bodies, secrets and personal file paths.

The anti-resurrection template gate is conservative by default. Stale live metadata cannot restore a tombstone; absence of a tombstone is not interpreted as restore; restore requires explicit signal; generated artifact and library metadata applies under a tombstone are blocked; newer tombstone policy remains explicit; physical delete, permanent delete, tombstone GC and auto conflict resolution remain forbidden. The observation window is disabled until explicit internal evidence is supplied. The retirement candidate gate is report-only and always keeps `retirementExecutionPerformed=false`, `legacyDeleted=false`, `legacyDisabled=false` and `manualAuditRequired=true`.

iPhone and Mac app seams are diagnostics-only wrappers: `IPhoneTombstoneConflictReadSideSeam` and `MacTombstoneConflictReadSideSeam`. They reuse existing inventory/canonical facts to build snapshots and call the shared evaluator. Default configuration is disabled; enabled mode only records redacted diagnostics and fixed no-mutation flags. The seams do not call deletion, restore, tombstone clearing, conflict resolution, upload, sync, transcription, note generation, store mutation, UI mutation, inventory response mutation, `receive.json` mutation, audio inbox writes, retry drainer or Mac pending sync.

## 2026-06-05 Canonical v8.25 generatedArtifacts read-side guarded seam and observation

v8.25 keeps `generatedArtifacts` as the only active pilot and adds the read-side half after the v8.24 write-side staged canary evidence. The shared read projection remains metadata/availability only: object/artifact id, kind, availability, byte size, hash prefix, producer summary, safe logical token summary, local downloaded state, peer authoritative state, updatedAt summary and parent active/tombstoned state. It still excludes full transcript/note/summary content, provider response, absolute path, full hash, request/response body, audio bytes and generated artifact upload state.

The new read source architecture mirrors the libraryMetadata v8.19 pattern. `CanonicalGeneratedArtifactReadSourceProvider` supports `legacy`, `parallelCompare`, `canonicalCandidate`, `guardedCanonicalRead` and `blocked`. `legacy` remains the default; parallel/candidate modes return legacy output and diagnostics. `guardedCanonicalRead` can return canonical metadata/availability output only under explicit internal/test configuration and a passing `CanonicalGeneratedArtifactReadCutoverGate`. Gate requirements are: matrix active pilot is exactly `generatedArtifacts`, other domains static/default-off, clean write-side staged canary evidence, rollback fatal count 0, read-side divergence 0, unsupported/contentLeakRisk/unsafePathToken/parentTombstone/audioConfusion counts 0, fallback available, canonical projection complete, no artifact route change, no generated artifact upload job, no global UI cutover and runtimeSwitch=false. Gate blocked, canonical projection missing or canonical read exception explicitly falls back to legacy.

iPhone and Mac app seams expose default-off `readSource(...)` wrappers for tests/internal diagnostics. They reuse already-built snapshots/inventory facts and do not trigger sync, upload, `/sync/artifact-request`, artifact download/apply, generated artifact file write, transcription/note generation, UI mutation, inventory response mutation, `receive.json` mutation, retry drainer or Mac pending sync changes. Observation now links write-side staged canary evidence with read-side evidence and counts canonical commits, rollback/fallback/suppression, canonical read served, legacy read fallback, divergence and fatal blocker categories. The retirement candidate gate is report-only: it can say candidate ready after evidence, but always reports `retirementExecutionPerformed=false`, `legacyDeleted=false`, `legacyDisabled=false` and `manualAuditRequired=true`.

## 2026-06-05 Canonical v8.24 generatedArtifacts staged canary expansion

v8.24 keeps `generatedArtifacts` as the only active pilot and expands only the write-side canary budget from the v8.23 N=1 wrapper. The shared architecture adds `CanonicalGeneratedArtifactCanaryStageRunner`, `CanonicalGeneratedArtifactCanaryStageGate`, v8.24 matrix policy helpers and a stage observation report. The stage order is fixed as `N1 -> N3 -> N10 -> allEligible`; each requested stage must carry clean previous-stage evidence with zero failure, rollback failure, divergence, conflict, postcondition failure, unsupported artifact, content leak, unsafe path, parent tombstone, audio confusion, hash unavailable and byte-size unavailable counts.

The staged runner executes only under explicit `.canaryCommit` configuration with `stagePolicy.allowCandidateExecution=true`, `explicitInternalTestConfiguration=true`, owner-approved token, v8.24 matrix allowing generatedArtifacts expanded canary, local/peer snapshots, injected executor and passing rollback/no-commit/dry-run/execution-shadow/real-data-shadow/root-bound/read-only-transport/read-side evidence. Candidate selection remains deterministic and generated-artifact-download only. Candidates execute sequentially; the first failed commit or postcondition stops later candidates, runs rollback, preserves legacy fallback and applies duplicate suppression only to prior successful candidates. Rollback failure is fatal and suppresses nothing for the failed candidate.

iPhone can execute `N3`, `N10` or `allEligible` only through the staged runner. v8.23 N1 remains a separate strict wrapper. Mac inventory remains report-only because that request context has no peer snapshot; expanded-stage config records redacted stage diagnostics and legacy fallback preservation but does not fetch peer data or call an executor. v8.24 does not add routes, upload jobs, audio autodownload, read-path cutover, UI mutation, runtime switch, retry drainer migration, Mac pending sync changes or legacy retirement.

## 2026-06-05 Canonical v8.23 generatedArtifacts canary N=1

v8.23 keeps `generatedArtifacts` as the only active pilot but moves from v8.22 N=0 evidence to an explicit internal N=1 canary path. The shared architecture now has a strict wrapper around the existing generated artifact cutover runner: `CanonicalGeneratedArtifactN1CanaryRunner` first validates migration matrix, owner token, canary policy, rollback plan, no-commit/dry-run/execution-shadow/real-data-shadow evidence, `/sync/artifact-request` route evidence, root-bound apply port evidence, read-side equivalence, local/peer snapshots and executor availability. Any missing precondition produces redacted diagnostics and preserves legacy fallback.

Candidate selection remains generated-artifact-download only and never broadens to upload/allEligible. It chooses at most one candidate with deterministic priority: `summaryJSON`, `noteJSON`, `noteMarkdown`, `transcriptJSON`, then `transcriptMarkdown`. Safety reports block audio/metadata/receiveRecord confusion, unsupported action/kind, unsafe logical path token, missing hash/size, ambiguous producer, non-authoritative peer, wrong route, missing rollback checkpoint, parent tombstone, conflict and previously failed action. Observation reports only include counts, kind, ids, route status, hash prefix, fallback/suppression booleans and recommendation; they do not include artifact content, full hash, absolute paths, transcript/note/summary text or provider response.

iPhone can execute only through an injected generated artifact executor under explicit N=1 config. Success applies exactly one root-bound generated artifact candidate and only then marks matching legacy artifact action suppression. Any commit/postcondition failure rolls back and preserves fallback; rollback failure becomes fatal and still suppresses nothing. Mac remains report-only for the inventory seam because it has no peer snapshot in that request context. No new route, no generated artifact upload job, no audio autodownload, no UI/read-path cutover, no retry drainer or Mac pending sync migration is introduced.

## 2026-06-05 Canonical v8.22 generatedArtifacts active pilot guarded commit seam

v8.22 将 `generatedArtifacts` 设置为唯一 active pilot，但架构语义仍是 N=0 guarded commit gate，而不是 artifact 执行路径切换。共享 `CanonicalGeneratedArtifactGuardedCommitSeam` 消费 local/peer canonical manifest、generated artifact cutover evidence、read-side/template/observation evidence、legacy fallback snapshot 和 canary policy，输出 gate result、no-execution assertion、N1 readiness report 与 redacted diagnostics。

gate 只允许评估 canonical generated artifact apply/download-apply candidate，并限定 artifact kind 为 transcript JSON、transcript Markdown、note Markdown、note JSON、summary JSON。unsupported kind、content leak、unsafe path token、parent tombstone、audio confusion、missing peer snapshot、N1/staged/allEligible/runtime switch/default enablement、缺 owner token、缺 rollback/root-bound/legacy fallback/evidence 都必须 blocked。即使 gate allowed，canary budget 仍固定 0，结果必须是 `allowedButCanaryBudgetZero` / no execution。

iPhone app seam 位于 generated artifact read-side diagnostics 之后、library seams 和旧 generated artifact cutover suppression 之前，只写 v8.22 diagnostics，不返回 cutover result，也不参与 duplicate suppression。Mac app seam 位于 `/sync/inventory` 本地 inventory/canonical manifest 构建后，只能记录缺 peer snapshot 或 no-execution report，不改变 response shape。v8.22 不新增 route，不调用 `/sync/artifact-request`，不下载、不 apply、不写 store、不创建 upload job、不自动下载 audio、不改 UI/read path、retry、Mac pending sync 或 runtime switch；旧 artifact request/apply 与 fallback 仍是生产路径。

matrix 增加 v8.22 helper：`generatedArtifacts` 可成为唯一 active pilot 的条件是 v8.21 next-pilot candidate 已完成、canary N0 reached、canary N1 未到达、`libraryMetadata` observation complete 或 retirement candidate ready、其它 domain static/default-off、runtime/default/release cutover 全部关闭、read path 仍 legacy、无 production injection 和无 legacy suppression。`libraryMetadata` 在 v8.22 不再是 active pilot，只保留为观察/退役候选前置证据。

## 2026-06-05 Canonical v8.21 generatedArtifacts template alignment

v8.21 只把 `generatedArtifacts` 补齐为下一试点候选模板，不改变默认执行路径。共享 `CanonicalGeneratedArtifactReadProjection` 从 canonical manifest 或 app seam 转换后的 legacy artifact facts 生成 metadata-only snapshot，字段限制为 object/artifact id、kind、availability、byte size、hash prefix、producer summary、safe logical token summary 和 local/peer availability flags。projection 明确排除 content bytes、完整 hash、完整路径、audio bytes、transcript/note/summary 正文和 provider response。

`CanonicalGeneratedArtifactReadSideParallelDiff` 比较 legacy/canonical 读侧 projection，并把 missing canonical/legacy、availability/byte/hash prefix/producer/kind mismatch、unsafe path token、content leak risk、unsupported kind、tombstoned parent resurrection 和 audio confusion 归为 blocker。`CanonicalGeneratedArtifactObservationWindow` 与 retirement candidate gate 复用 libraryMetadata 的 report-only 模式：默认 disabled/incomplete，retirement 报告固定 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。

iPhone/Mac app seam 只是 diagnostics seam。iPhone 在 sync tick 已构造 local/peer inventory 后可并行比较；Mac 在 `/sync/inventory` response 构建时只比较本地 inventory 与 canonical manifest。两端 seam 默认关闭，启用后不改变 plan、store、read owner、UI、artifact download/apply、upload job、response body、route/security 或 retry/pending sync。

matrix 新增 `nextPilotCandidate` 作为非 active、非 canary、非 cutover 状态。`CanonicalMigrationDomainMatrix.v821GeneratedArtifactsNextPilotCandidate(...)` 要求 `libraryMetadata` 已 observation complete 或 retirement candidate ready；否则产生 `generatedArtifactsNextPilotBeforeLibraryMetadataObservation`。该 helper 不把 `generatedArtifacts` 设为 active pilot，也不允许 audio/tombstone/legacy retirement 变 active。

## 2026-06-05 Canonical v8.20 libraryMetadata observation window and retirement candidate gate

v8.20 在 v8.19 guarded read-source seam 之后增加 observation/reporting 层，不改变默认执行路径。`CanonicalLibraryMetadataObservationWindow` 是纯共享模型，接收既有 write-side cutover result、read-source result、read-side cutover result 或显式 test event，并归一成 redacted 计数：canonical commit、rollback、fallback、duplicate suppression、read candidate/read served、parallel divergence、unsupported/path leak、unsafe side effect、sync/upload、UI mutation、content write、resource move 与 tombstone/delete attempt。

`CanonicalLibraryMetadataObservationGate` 是 observation 完成边界。它要求 explicit internal/test policy、唯一 active pilot `libraryMetadata`、其它 domain static-only、write/read evidence 达到阈值、legacy fallback 可用、zero divergence、zero rollback failure、zero unsupported/path leak、runtimeSwitch=false、default cutover=false，并且无 resource move、content write、tombstone/delete、sync/upload 或 UI mutation。gate 输出 `completeReadyForRetirementCandidate` 只表示报告候选就绪，不授权执行 retirement。

`CanonicalLibraryMetadataRetirementCandidateGate` 只把 observation gate 转成 report-only candidate。报告固定 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`reportOnly=true`，并保留 `manualAuditRequired=true`。`CanonicalLibraryMetadataEndToEndPilotReport` 最多表达 `pilotRetirementCandidateReady`；不会产生 retired 状态，也不会删除 legacy planner/store/route/read implementation。

iPhone/Mac read-side seam 新增 `observeReadSource(...)` hook，但默认 policy disabled。该 hook 只消费调用方已持有的 `CanonicalLibraryMetadataReadSourceResult`，不再次扫描 store，不触发 sync/upload，不写真实资源、不改 UI、不改变 read owner。matrix helper 只生成 v8.20 report matrix：`libraryMetadata` 可标记 observation complete / retirement candidate ready，其它 domain 继续 static/default-off，`libraryMetadataPilotComplete` 仍 false。

## 2026-06-05 Canonical v8.19 libraryMetadata guarded read-side cutover seam

v8.19 在 v8.17 read-side parallel evidence 与 v8.18 real canary N=1 wrapper 之后增加一个真正可服务 read output 的 guarded read-source seam，但仍不改变默认 app read owner。共享 `CanonicalLibraryMetadataReadSourceProvider` 统一处理 `legacy`、`parallelCompare`、`canonicalCandidate`、`guardedCanonicalRead` 与 `blocked`：默认 `legacy` 返回 legacy snapshot；parallel/candidate 只构建 canonical metadata candidate 并保留 legacy output；guarded 只有在显式 internal/test config 和 gate 通过时才返回 canonical snapshot。

`CanonicalLibraryMetadataReadCutoverGate` 是 read-side 放行边界。它要求 matrix 中唯一 active pilot 为 `libraryMetadata`、其它 domain 仍 static/default-off、write-side canary evidence clean、rollback fatal 为 0、read-side divergence/unsupported/pathLeakRisk 为 0、legacy fallback 可用、canonical projection complete、objectID stable、无 resource move、无 content write、无 tombstone/delete candidate、无 unresolved conflict、UI cutover 非 global 且 runtime switch 关闭。任何 gate blocker、canonical projection missing 或 canonical read exception 都返回 legacy read output，并用 fallback reason 诊断。

双端 app seam 只新增内部/test 可调用的 `readSource(...)` wrapper。它消费 `StudyLibrarySyncManifest` 与 `CanonicalManifest`，转换为 metadata-only read snapshots；不读取 standalone note 正文、不包含 audio state、不包含 generated artifact content、不移动真实资源、不写 store、不发网络。现有 `evaluate(...)` 仍保留 v8.17 diagnostics-only 语义，默认 UI 和 `StudyLibraryStore` 不接入 guarded read source。

retirement readiness 仍是候选报告。v8.19 的 guarded read evidence 可让 `libraryMetadata` retirement candidate 进入 ready 状态，但 report 固定 `legacyDeleted=false`、`legacyDisabled=false`，不会自动删除或禁用 legacy planner/store/route/read implementation。v8.19 不影响 `recordingMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`uiProjection` 或 `legacyRetirement` 的 static/default-off 状态。

## 2026-06-05 Canonical v8.18 libraryMetadata production canary N=1

v8.18 在 v8.15 strict N=1 runner 外新增 production canary wrapper，而不是扩大 canary 预算或改变 app 默认路径。`CanonicalLibraryMetadataProductionCanaryConfiguration` / `Policy` / `Mode` 将 active domain 固定为 `libraryMetadata`，预算固定为 1，并把 explicit internal/debug configuration、owner token、rollback plan、write-side evidence、read-side parallel equivalence、root-bound non-dry-run apply port、legacy fallback 和 v8.13 matrix 都作为执行前置条件。

`CanonicalLibraryMetadataProductionCanaryInjection` 负责把 production canary 状态归一成 injection result、observation report 和 diagnostics。`.disabled` 默认不配置；`.diagnosticsOnly` 只观察；`.canaryN1Armed` 只证明 executor/apply port/evidence 可注入但不提交；只有 `.canaryN1Execute` 在全部 gate 通过且存在注入 executor 时才调用既有 `CanonicalLibraryMetadataN1CanaryRunner`。该 wrapper 继承 N1 runner 的稳定候选选择、success-only duplicate suppression、failure rollback/fallback 和 read-side parallel diagnostics。

iPhone/Mac app target 新增显式 bootstrap：`IPhoneLibraryMetadataProductionCanaryBootstrap` 与 `MacLibraryMetadataProductionCanaryBootstrap`。默认 bootstrap 返回 executor/apply port nil；显式 test-root 配置才创建 root-bound real apply port 和 cutover executor，并只把 port/evidence 暴露给调用方。production root 必须是 explicit root mode 且 `allowProductionRootWrites=true`；否则 apply port 保持 `productionRootDisabled` 或被 production canary blocker 阻断。默认 app construction、`performTick`、`SecureLocalHTTPSServer` 和 UI 不会自动注入该 executor。

v8.18 observation report 只写 redacted counts/status：selected/executed/success/failure/rollback/fallback/suppression/no-eligible/unsafe/fatal/read-side。报告固定 `uiMutated=false`、`resourceMoved=false`、`uploadJobCreated=false`，因此它不改变 read path、legacy/canonical plan、inventory response、state store、upload ledger、retry queue、Mac pending sync、route/security、真实 store 或 `receive.json`。

## 2026-06-05 Canonical v8.16 libraryMetadata expanded canary

v8.16 在 v8.15 strict N=1 runner 旁新增独立 staged runner，不改变 v8.14 N0 seam 和 v8.15 N1 合同。`CanonicalLibraryMetadataCanaryStageRunner` 只服务唯一 active pilot `libraryMetadata`，stage policy 显式请求 `n3`、`n10` 或 `allEligible` 时才运行；默认 policy、runtime switch 和 release/default enablement 仍为 off。

stage gate 要求 previous-stage evidence 完整：N3 需要 N1 clean observation，N10 需要 N3 clean observation，allEligible 需要 N10 clean observation。evidence report 纳入 no-commit、dry-run equivalence、execution shadow、real-data shadow copy、read-only transport probe、rollback plan、production apply port、legacy fallback、read-side parallel equivalence、observation window、previous-stage failure/rollback/resource move/hierarchy cycle/objectID instability/unsupported object/postcondition/blocking divergence/unresolved conflict 计数。

candidate selector 继续只接受 metadata-only folder/studyItem/standalone note apply/send，并按 object kind、objectID、actionID 稳定排序。v8.16 会在预算内顺序执行；第一个失败 candidate 触发 rollback、记录 fallback 并停止后续候选。成功 candidate 的 duplicate legacy suppression 是 per-candidate success-only，因此 mixed run 中已成功 candidate 可 suppress，失败/未执行/跳过 candidate 仍走 legacy。

iPhone seam 位于 legacy diff 后、final plan duplicate suppression 前。显式 `.canaryCommit` + expanded stage policy + owner token + evidence + 注入 executor 才进入 staged runner。Mac inventory seam 仍没有 peer snapshot；真实 route 只记录 expanded stage blocked/fallback/observation diagnostics，不 await executor、不改变 inventory response、不改 route/security/pending sync。

read-side parallel 在 v8.16 仍是 affected-object diagnostics，不切 UI/read owner。stage observation report 输出 stage、budget、selected/executed/success/failure/rollback/fallback/suppression/skipped/read-side 等 redacted 计数和下一阶段建议。v8.16 没有 domain cutover、read-side cutover、legacy retirement，也不触碰 audio/generated/recordingMetadata/tombstone/delete/GC/upload/retry/Mac pending sync。

## 2026-06-05 Canonical v8.15 libraryMetadata canary N=1

v8.15 在 v8.14 N0 seam 旁新增独立的 N=1 canary runner，而不是改变 `CanonicalLibraryMetadataGuardedCommitSeam` 的 no-execution 语义。共享层的 `CanonicalLibraryMetadataN1CanaryRunner` 先验证 v8.13 matrix、strict N=1 config、owner token、rollback/evidence、root-bound apply port、read-side parallel 和 legacy fallback，再用 candidate safety report 选出最多 1 个 metadata-only candidate，最后才调用既有 `CanonicalLibraryMetadataCutoverRunner` 与注入 executor。

候选安全层只允许 metadata apply/send：folder rename/color metadata、studyItem tags/filing/folder membership metadata、standalone note title/tags/filing metadata。它会阻断 resource token/path 变化、folder hierarchy mutation、tombstone/delete、conflict、cycle、parent missing、objectID instability、unsupported action 和 prior failed candidate。standalone note content bytes 不在 canary payload 中，observation report 固定记录 `contentBytesMutated=false`。

iPhone seam 位于 `LocalNetworkSyncEngine.performTick` 的 legacy diff 后、legacy duplicate suppression 前。显式 `.canaryCommit` 且 policy 正好 N=1、`allowsInternalN1Execution=true`、`explicitInternalTestConfiguration=true` 时才进入 N1 runner；默认 disabled、N=0 或缺 executor 都不会提交。成功 commit 后返回 cutover result，后续 `suppressCanonicalLibraryMetadataDuplicateLegacyActions` 只按 successful commit 移除匹配 folder/studyItem/standaloneNote metadata action。

Mac inventory seam 仍同步构建 response，不能 await production runner，也没有 peer snapshot。因此真实 `/sync/inventory` 中显式 N=1 只记录 peer-snapshot-unavailable/fallback/observation diagnostics。Mac role 的 fake peer + fake executor N=1 commit 只在测试中通过共享 runner 验证。

v8.15 没有新增 route、没有改变 `/sync/apply-metadata`、`RequestVerifier`、TLS/HMAC/nonce/body hash、Keychain、pending sync、retry drainer、upload runtime、UI read path、read-side owner 或 legacy retirement。read-side parallel diagnostics 仍只比较/记录，不驱动 UI。

## 2026-06-05 Canonical v8.14 libraryMetadata guarded commit seam

v8.14 的架构目标是把 `libraryMetadata` pilot 的第一个 N0 gate 接到双端 app seam，但保持 no-execution。共享层在 `CanonicalLibraryMetadataCutover.swift` 中新增 `CanonicalLibraryMetadataGuardedCommitSeam`、guarded commit context/gate/evidence report、no-execution assertion、N1 readiness report/status/blocker 和 v8.14 diagnostics taxonomy。该 seam 只评估 folder metadata、study item metadata 和 standalone note metadata candidate，不持有 executor，不调用 `CanonicalLibraryMetadataCutoverRunner`，也不调用 apply/transport production port。

iPhone seam 位于 `LocalNetworkSyncEngine.performTick` 的 legacy diff 后、final plan 确定前。显式 `.guardedExecuteCommit` 或 `.canaryCommit` 配置时，它读取 current local/peer canonical manifest、library sync plan、candidate、legacy action snapshot 和 cutover evidence，输出 v8.14 gate/evidence/readiness diagnostics。返回值固定不提供 suppression report，因此 `suppressCanonicalLibraryMetadataDuplicateLegacyActions` 不会移除 legacy action；原 legacy/canonical plan、pending counts、upload job、retry drainer 和 UI owner 不变。

Mac seam 位于 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` response 构建后。由于 `/sync/inventory` 是本地 snapshot route，peer snapshot 在该 seam 中不可用，gate 会记录 missing peer snapshot blocker 和 N1 readiness gap，但 response body、route handling、`RequestVerifier`、TLS/HMAC/nonce/body-hash、Mac pending sync、receive JSON、audio inbox 和 artifact routes 不变。

N=0 是 v8.14 的强不变量：`commitAttemptedCount` 与 `committedObjectCount` 固定为 0，production commit、real apply port、network send、`applySyncManifest`、metadata JSON write、duplicate suppression 和 runtime switch 全部为 false。`CanonicalLibraryMetadataNoExecutionAssertion` 在共享测试和双端 seam 测试中校验该不变量；`CanonicalLibraryMetadataN1ReadinessReport` 只描述是否具备进入后续 N1 的证据与 blocker，不允许本阶段执行 N1。

## 2026-06-05 Canonical v8.13 migration matrix freeze

v8.13 的架构目标从继续扩域改为收束配置：共享层新增 `CanonicalMigrationDomainMatrix`、`CanonicalMigrationDomain`、扩展后的 `CanonicalMigrationStage`、`CanonicalMigrationStageStatus`、`CanonicalMigrationDomainPolicy`、`CanonicalMigrationDomainBlocker` 和 `CanonicalMigrationMatrixReport`。它们是纯模型和 diagnostics-only validator，不接入 iPhone `performTick`、Mac `/sync/inventory` response owner、任何 executor、真实 store、network route、UI、retry drainer 或 Mac pending sync。

当前唯一 active pilot domain 是 `libraryMetadata`。matrix 明确 `recordingMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`uiProjection` 和 `legacyRetirement` 在 v8.13 只能保持 static-review-only / blocked-for-real-migration。所有 domain cutover 默认关闭；没有 runtime switch；没有 read-side cutover；没有 legacy retirement；read path 继续 legacy。`CanonicalMigrationGlobalConfigValidator` 只在被测试或配置审计路径显式调用时返回 violation，不会自动启停任何 runtime。

pilot 路径被固定为：N0 gate -> N1 canary -> expanded canary -> domain write cutover -> read-side parallel -> read-side cutover -> retirement candidate。matrix 阻止跳 stage：canary 需要 previous stage evidence，read-side cutover 需要 write-side cutover success，retired 需要 read-side cutover、observation window 和 fallback readiness。`audioUpload` 在 `libraryMetadata` pilot 完成前不能成为 active pilot；`generatedArtifacts` 和 `tombstoneConflict` 在本阶段也不能进入真实 canary/cutover。

`CanonicalLibraryMetadataPilotReport` 是 library metadata pilot 的 readiness gap audit。它只检查 projection、planner、apply bridge、NoCommit、real apply port、Commit executor、default-off app seam、canary policy、rollback、failure injection、legacy fallback、success-only duplicate suppression、read-side parallel readiness、no resource move guard、no physical delete guard、tests 和 docs，并输出 redacted blocker summary。它不执行 canary、不调用 apply port、不 suppress legacy。

其它域使用 `CanonicalOtherDomainsStaticAuditReport` 做 static-complete/default-off audit：报告 machine parts、app seam、default-off、no production injection、read path legacy、tests present、static review recommended 和 real migration blocked。该报告只描述当前代码状态，不把 audio upload 推进到真实迁移，不新增 route，不改变 upload runtime。

## 2026-06-04 Canonical v8.12 audio upload shadow/canary preparation

v8.12 只把 audio upload 纳入 shadow/canary preparation 架构，不把 canonical runtime 切到生产上传。共享 `CanonicalAudioUploadCutover.swift` 把 audio upload truth 拆为 local audio、peer audio、ledger、retry 和 trigger 五类证据；candidate 只允许表达 no-op、shadow/canary candidate、peer-unknown deferred、conflict 或 unsupported，不执行真实 upload。

NoCommit executor 只生成 suppressed summary，固定 `calledProductionUploadCoordinator=false`、`calledRecordingUploadClient=false`、`calledSecureMacUploadClient=false`、`createdUploadJob=false`、`wroteProductionInbox=false`、`wroteReceiveJSON=false`、`mutatedUploadLedger=false`、`mutatedRetryDrainer=false`、`runtimeSwitchEnabled=false` 和 `suppressedLegacyDuplicate=false`。shadow rehearsal 只用 `CanonicalShadowUploadReceiver` 与 in-memory resumable runtime 排练 chunk/resume/no-op/conflict/hash mismatch，不触碰 Mac inbox 或 `receive.json`。

iPhone seam 位于 legacy diff 后、真实 upload 执行前，默认 disabled；显式启用时也只记录 diagnostics/no-commit，不改变最终 diff plan 或 pending counts。Mac seam 位于 `/sync/inventory` response 构建后，默认 disabled；显式启用时缺 peer snapshot 只记录 blocked/fallback diagnostics，不改变 response body、resumable upload route 或 receiver store。v8.12 canary policy 默认 disabled/N=0；任何 N>0 production canary 在本阶段都必须 blocked。

音频 no-op 的唯一强证据仍是 peer `audioAvailable` 同时具备相同 hash 和 size。metadata uploaded、manifest applied、receive record existing、UI uploaded、completed ledger、Mac inbox refresh 或 peer unknown 都不能当作 audio proof。peer missing/metadataOnly 只可成为 shadow/canary candidate；peer unknown deferred；hash/size 不同进入 conflict；view refresh、manual upload button、retry drainer fresh job 不由 canonical 创建新上传。

## 2026-06-04 Canonical v8.11 tombstone/conflict cutover seam

v8.11 把 tombstone/conflict 域纳入 controlled cutover 合同，但架构 owner 仍被收窄到 soft tombstone marker 与 conflict ledger record。共享 `CanonicalTombstoneConflictCutover.swift` 接受 object tombstone apply/send、library tombstone apply/send、conflict record 和 resurrection-blocked candidate；generated artifact tombstone 仍是 unsupported marker，不能进入 production deletion。domain 映射只落在 `.tombstones` 与 `.conflicts`，不触碰 audio、generated artifact payload、folder/studyItem metadata 文件或 UI projection owner。

NoCommit executor 只写临时 staging summary，记录 production commit、`applySyncManifest`、network send、receive JSON mutation、generated artifact deletion、audio deletion、physical delete、permanent delete、tombstone GC 和 legacy duplicate suppression 全部被抑制。真实 root-bound apply port 默认 disabled，`productionRootURL` 默认阻断；测试/内部 `testRootURL` 只写 `tombstone-conflict/` 下 marker/ledger JSON，执行 checkpoint -> atomic replace -> read-back verification -> rollback restore/remove，不删除业务文件。

双端 Commit executor 只允许 `.tombstoneMark` 和 `.conflictRecord` side effect。gate 要求 explicit token、owner approval、rollback plan 覆盖 tombstones/conflicts、NoCommit/dry-run/equivalence/execution-shadow/real-data-shadow evidence、root-bound non-dry-run apply port、atomic replace、rollback verification、soft marker store/conflict ledger support、tombstone newer-wins policy 与 rollback evidence。active-vs-tombstone 仍是 conservative conflict；`resurrectionBlocked` 只写 anti-resurrection ledger，阻止 generated artifact download 复活 tombstoned object。physical delete、permanent delete、tombstone GC、unsupported restore、ambiguous conflict policy 或 generated artifact tombstone apply 都必须 blocked。

iPhone/Mac 本轮只新增端侧 NoCommit executor、real apply port 和 commit executor；没有把 v8.11 接到默认 iPhone sync tick 或 Mac `/sync/inventory` response owner。v8.11 不新增 route、不扩大 `RequestVerifier`、不改 TLS/HMAC/nonce/body hash/Keychain、不切 retry drainer/Mac pending sync/audio upload/generated artifact download/folder metadata/UI/legacy retirement。read-side parallel projection 只做 diagnostics，`mutatedUI=false`、`syncOrUploadTriggered=false`。

## 2026-06-04 Canonical v8.10 library metadata cutover seam

v8.10 把 folder、study item、standalone note metadata 纳入 controlled cutover 合同，但架构 owner 仍被收窄到 metadata-only apply/send。共享 `CanonicalLibraryMetadataCutover.swift` 只接受 folder metadata apply/send、study item metadata apply/send 和 standalone note metadata apply/send candidate；conflict/tombstone action 只作为 blocker/unsupported-for-this-round diagnostics，不进入 production commit。

NoCommit executor 只写临时 staging summary，记录 would use existing metadata manifest bridge、parent/tag/filing/hash-prefix evidence 和 legacy fallback preserved；它不调用 `StudyLibraryStore.applySyncManifest`、不写 production root、不 suppress legacy。真实 root-bound apply port 默认 disabled，`productionRootURL` 默认阻断；只有测试/内部 `testRootURL` 会写临时 root，并执行 metadata bytes staging、atomic replace、hash read-back verification、checkpoint rollback restore/remove。

双端 library metadata Commit executor 只允许 metadata apply/send side effect，domain 限定为 folders、studyItems、standaloneNotes 或 apply diagnostics。可执行 canary 默认 `N=0`；`N=1` 必须显式内部配置或 staged canary policy、完整 evidence 和注入 executor。commit 成功后才精确 suppress 同 folder/studyItem/standalone note metadata 的 legacy duplicate action；gate blocked、resource move attempt、folder cycle、conflict、tombstone、failure、rollback 或 fallback 均保留 legacy metadata manifest path。

iPhone app seam 位于 legacy diff 后、final plan 确定前，默认不运行。Mac `/sync/inventory` seam 没有 peer snapshot，只记录 report/fallback diagnostics 并返回原 response。v8.10 不新增 route、不扩大 `RequestVerifier`、不改 TLS/HMAC/nonce/body hash、不移动资源文件、不切 UI owner、不迁移 audio/generated artifact/recordingMetadata/tombstone GC/conflict execution/retry/Mac pending sync/legacy retirement。UI parallel projection 只做 read-side diagnostics，`mutatedUI=false`。

## 2026-06-04 Canonical v8.9 generated artifacts cutover seam

v8.9 把 generated artifact 域纳入 controlled cutover 合同，但架构 owner 仍被收窄到 Mac authoritative transcript/note/summary 产物。共享 `CanonicalGeneratedArtifactCutover.swift` 只接受 `transcriptJSON`、`transcriptMarkdown`、`noteMarkdown`、`noteJSON`、`summaryJSON`，并复用 `CanonicalProjectionContract.generatedArtifactKinds`、`CanonicalSyncPlanner` 和 `CanonicalApplyPlan` 的现有 projection/planning/apply 语义。iPhone 已下载 artifact 仍只是 local availability evidence，不是 producer。

NoCommit executor 只写临时 staging summary，记录 would request existing `/sync/artifact-request`、would apply、hash/size evidence 和 legacy fallback preserved；它不下载、不写 production root、不 suppress legacy。真实 root-bound apply port 默认 disabled，`productionRootURL` 默认阻断；只有测试/内部 `testRootURL` 会写临时 root，并执行 payload staging、atomic replace、hash/size read-back verification、checkpoint rollback restore/remove。

双端 generated artifact Commit executor 只允许 canonical generated artifact apply/download apply candidate，side effect whitelist 只允许 generated artifact apply 与 redacted diagnostics。可执行 canary 默认 `N=0`；`N=1` 必须显式内部配置和注入 executor。commit 成功必须满足 precondition、postcondition、root-bound/hash/size verification 和 rollback checkpoint，成功后才精确 suppress 同 artifact 的 legacy duplicate action。gate blocked、peer unknown、producer ambiguity、tombstone、failure、rollback 或 fallback 均保留 legacy `/sync/artifact-request` path。

iPhone app seam 位于 legacy diff 后、final plan 确定前，默认不运行；Mac `/sync/inventory` seam 没有 peer snapshot，只记录 report/fallback diagnostics 并返回原 response。v8.9 不新增 artifact route、不扩大 `RequestVerifier`、不改 TLS/HMAC/nonce/body hash、不创建 generated artifact upload job、不自动下载 audio、不切 UI/retry/Mac pending sync/folder/studyItem/tombstone/delete/conflict/legacy retirement。UI parallel projection 只做 read-side diagnostics，`mutatedUI=false`。

## 2026-06-04 Canonical v8.7 recordingMetadata canary N=1

v8.7 在 v8.6 app seam 之后增加 `recordingMetadata` 单对象 canary。默认仍是 disabled / `N=0`；只有显式 `.canaryCommit`、`canaryMaxObjectsPerSyncRun == 1` 且 `allowsV87CanaryN1InternalExecution == true` 时，iPhone `LocalNetworkSyncEngine.performTick` 才会调用 `CanonicalRecordingMetadataCutoverRunner`。`N>1` 会以 `canaryBudgetAboveOneDenied` 阻断，`N=1` 缺内部开关会以 `missingInternalCanaryConfiguration` 阻断。

iPhone canary seam 位于 legacy diff 与 canonical/legacy plan 选择之间，复用同一批 local/peer canonical manifest、canonical apply plan、legacy action snapshot、owner-approved token 和 root-bound/read-only/rollback/equivalence evidence。候选选择器只接受 `recordingMetadataApply` / `recordingMetadataSend`，按 objectID、apply-before-send、actionID 稳定排序，每个 sync run 最多选择 1 个；view refresh、retry drainer、unsupported domain/action、evidence 不足、unresolved/tombstone conflict、缺 rollback checkpoint、非 root-bound apply port、send 缺 read-only probe 或已失败 action 都不会进入 commit。

成功路径要求 commit result 同时满足 committed、precondition verified 和 postcondition verified。只有这时才在最终 `LocalNetworkSyncDiffPlan` 上精确移除同 objectID、entityKind=`recording`、action reason=`recordingMetadataApply`/`recordingMetadataSend` 的 duplicate metadata action，并记录 `canonicalRecordingMetadataDuplicateLegacySuppressed`。失败路径不会 suppress；precondition/postcondition/transport/apply failure 会 rollback，rollback 成功后保留 legacy fallback，rollback 失败产生 fatal blocker。v8.7 observation report 显式记录 `runtimeSwitch=false`、`uiMutated=false`、`uploadJobCreated=false` 和 redacted summary。

Mac 侧本轮不新增 production route，也不改 `/sync/apply-metadata`、`RequestVerifier`、nonce/HMAC/TLS/body-hash 边界或 pending sync。Mac inventory seam 仍是 v8.6 report-only；即使看到 N=1 policy，也只记录 gate/evidence diagnostics，缺 peer snapshot 时继续 nonfatal blocked 并返回原 inventory response。

## 2026-06-04 Canonical v8.6 guarded commit app seam, canary N=0

v8.6 把 `recordingMetadata` guarded commit seam 接到 app 层诊断路径，但架构上仍是 report-only。共享层的 `CanonicalRecordingMetadataGuardedCommitSeam` 只接收 context/evidence/candidates 并返回 gate、evidence report、canary policy 和 diagnostics；它没有 executor 参数，不调用 `CanonicalRecordingMetadataCutoverRunner.run`，也不持有 production apply/transport port。

iPhone seam 位于 `LocalNetworkSyncEngine.performTick` 的 legacy diff 后、live read-only probe 与 canonical/legacy plan 选择前。显式 `.guardedExecuteCommit` 或 `.canaryCommit` 配置时，它复用 local/peer canonical manifest、canonical sync/apply plan、legacy recording metadata action snapshot、owner-approved token 和 cutover evidence，记录 `canonicalV86*` / `canonicalRecordingMetadata*` diagnostics，然后继续原 plan path。NoCommit seam 现在只响应 `.guardedExecuteNoCommit`。

Mac seam 位于 `/sync/inventory` response 构建完成后。因为 Mac inventory route 没有 peer snapshot，显式启用时 guarded gate 会记录 `insufficientPeerSnapshot` nonfatal blocker，并继续返回原 inventory response。双端 report 都固定表达 canary `N=0`、runtime switch false、commit not executed、legacy fallback preserved、duplicate suppression not applied。

v8.6 不改变 root-bound apply port、transport route、安全边界或 store owner。它不写 production root、不发送 `/sync/apply-metadata`、不调用 `StudyLibraryStore.applySyncManifest`、不 suppress duplicate legacy、不改变 UI、retry drainer、Mac pending sync、upload routes/security、audio/generated/folder/studyItem/tombstone/conflict 域。v8.7 之后，只有 iPhone `.canaryCommit` + 显式内部 N=1 走 canary runner；v8.6 guarded seam 自身仍不执行提交。

## 2026-06-04 Canonical v8.5 root-bound metadata apply port

v8.5 在 shared SyncCore 增加真实 root-bound `recordingMetadata` 写入核心：`CanonicalRootBoundMetadataWriteCore` 只接受绑定 root token 的 safe logical path token，执行 checkpoint -> atomic replace -> read-back verification -> redacted result，rollback 会用 checkpoint 原字节恢复或删除本轮新建文件。失败分类覆盖 root escape、production root disabled、checkpoint/atomic write/postcondition/rollback failure、unsupported store API、schema/decoding/permission/unknown。

双端 production apply port 的架构现在分为四类：默认 disabled、测试 fakeInMemory、显式 testRootBound、默认阻断的 productionRootDisabled。默认构造与 `makeDisabledPortSet()` 仍是 disabled/dry-run；只有测试/内部调用 `init(testRootURL:)` 才会写临时 root。`init(productionRootURL:)` 默认不写，必须另有显式 allow 才可能进入 productionRootBound，这条路径没有接入 app default path。

root-bound apply/send 仍只处理 `recordingMetadataApply` / `recordingMetadataSend` candidate。apply 写 metadata bytes；send 复用同一 root-bound metadata write 合同并标记 no-network summary，不发真实 `/sync/apply-metadata`。commit executor 只接受 metadata apply side effect，side-effect trace 只暴露 domain、object id、byte count、hash prefix、atomic/rollback 布尔摘要，不暴露完整 JSON、路径或 hash。

cutover gate 的 architecture evidence 扩展为必须证明：real root-bound apply port 可用、apply port mode 是 non-dry-run root-bound、root-bound write/atomic replace/rollback checkpoint/rollback verification 可用、production root 默认 disabled，并且 testRootBound 模式必须有 test root evidence。即便 evidence 通过，canary 默认仍 `N=0`；v8.6 app seam 只会记录 guarded report，不会调用 root-bound port 或 executor，legacy planner/inventory/routes/store/upload/UI/retry/Mac pending sync 仍是 production owner。

## 2026-06-04 Canonical v8.4 fake Commit hardening

v8.4 不改变 production architecture，只把 `recordingMetadata` Commit executor 的 fake/in-memory harness 压满。共享 failure injection enum 增加 duplicate/idempotent replay、unsupported/unexpected side effect 和 missing rollback checkpoint 等场景；双端 executor 对 apply-before/precondition/transport-before failure 走 rollback no-op，对 postcondition/partial mutation 走 fake rollback，对 missing checkpoint/rollback failure 标记 fatal blocker。

双端 `CanonicalProductionApplyPort` 的 `fakeInMemory` mode 仍是 actor-local fake store：记录 action、checkpoint、object 维度的内存状态，重复同 actionID 返回 idempotent result，rollback 只移除对应 fake checkpoint 的 action，并保留 unrelated object fake state。它不绑定真实 root，不读取/写入真实 store，不调用 `StudyLibraryStore.applySyncManifest`，也不发送真实 network；`sendMetadata` 仍只是既有 `/sync/apply-metadata` 的 fake route projection。

架构边界不变：默认 app path 仍不会执行 Commit。v8.6 的 `guardedExecuteCommit` / `canaryCommit` 只在显式配置下进入 diagnostics-only guarded report；v8.7 只给 iPhone `.canaryCommit` + 内部 N=1 打开一个 controlled canary 分支。legacy planner/inventory/apply/upload/UI/retry/Mac pending sync 仍是 production owner。v8.5 root-bound `recordingMetadata` apply port 也必须继续 default-off。

## 2026-06-04 Recording Metadata Commit Executor 架构补充

v8.3 在 controlled cutover 合同上新增双端 `recordingMetadata` Commit executor：iPhone 为 `IPhoneRecordingMetadataCutoverExecutor`，Mac 为 `MacRecordingMetadataCutoverExecutor`。executor 只接受 `recordingMetadataApply` / `recordingMetadataSend` candidate；默认构造仍绑定 disabled/dry-run production ports，因此真实 app 默认不会产生 production write/network/apply side effect。可执行路径必须由测试或内部配置显式注入 fake non-dry-run apply/transport port。

apply commit 的执行边界是 `CanonicalProductionApplyPort.applyMetadata`；send commit 的执行边界是 `.applyMetadata` route projection 到既有 `/sync/apply-metadata` 后调用 `sendMetadata`。这不是新 route，也不替换 `SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier`、TLS pinning、HMAC、nonce、body hash、Keychain、upload route 或 legacy `StudyLibraryStore.applySyncManifest` bridge。当前真实 store 缺少 single-object checkpoint/rollback API，真实 store commit 仍必须 blocked。

executor 的 safety chain 是 checkpoint -> precondition -> apply/send -> postcondition -> allowed side-effect check -> duplicate suppression。precondition 覆盖 action/domain、objectID、metadata hash 存在性、unresolved conflict、route/transport、bridge hint、modifiedAt 方向和 tombstone state；失败路径触发 rollback，rollback failure 是 fatal blocker。side-effect whitelist 只允许 recording metadata apply、`.applyMetadata` network request 与 diagnostics write；upload/generated/file/tombstone/conflict side effect 都视为 blocker。

runner 语义保持 single-domain canary：默认 `N=0` 不执行对象；v8.7 只允许显式内部 `N=1`，`N>1` 必须 blocked。commit 成功后只 suppress 同 action 的 duplicate legacy recording metadata；任何 gate/canary/precondition/postcondition/transport/apply/rollback failure 都保留 legacy fallback。新增 diagnostics 只写 redacted action/object/domain/result/reason/hash prefix/route summary，不写完整 metadata JSON、完整 hash、路径、secret、fingerprint、request/response body、transcript/note/summary 或 provider response。

## 2026-06-03 Recording Metadata Cutover 架构补充

`CanonicalRecordingMetadataCutover.swift` 是第一个 controlled real-root execution candidate 的共享合同层，但当前仍是 default-off、dependency-injected、test-only entry。它只接受 `recordingMetadata` domain 的 `recordingMetadataApply` / `recordingMetadataSend` candidate；其他 domain 或 action 会返回 unsupported/blocker，不会调用 executor。

cutover runner 的 gate 在执行前检查 explicit token、owner approval、rollback plan、real-data shadow copy、execution shadow、dry-run equivalence、无 blocking divergence、无 unresolved conflict、read-only transport probe、production port availability、legacy fallback、rollback rehearsal、production execution guard pass，并拒绝 view refresh 和 retry drainer trigger。gate 不通过时 canonical production commit 不执行，legacy fallback 继续可用。

canary mode 的默认 budget 为 0。v8.7 显式内部 N=1 时，selector 只选择稳定排序后的一个 eligible recording metadata candidate；`N>1` 不会扩大执行。commit 成功后才记录 duplicate legacy suppression。失败路径会先 rollback，rollback 成功后转 legacy fallback，rollback 失败则产生 fatal blocker。UI parallel projection 只生成 canonical/display hash prefix 等价诊断且 `mutatedUI=false`；retirement readiness 只是该单域的候选状态，不会自动禁用 legacy。

双端 production transport adapter 现在把 shared route `.applyMetadata` 映射到既有 `/sync/apply-metadata`，但没有新增真实 Mac route，也没有改 `RequestVerifier` 边界。`CanonicalKernelFacade` 对 metadata send action 调用 apply port 的 `sendMetadata` 合同；本轮测试用 fake executor/fake apply port 验证 mapping 和 guard，不触碰 `StudyLibraryStore.applySyncManifest`、`SecureMacUploadClient`、`SecureLocalHTTPSServer`、真实 store 或 upload runtime。

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
- 上传：`RecordingUploadCoordinator` 管理 job ledger、retry drainer、失败分类和状态；`RecordingUploadClient` 决定单请求上传或 resumable chunk 上传；`SecureMacUploadClient` 负责 HTTPS、证书 pinning、HMAC header。
- 连接状态：`SecureMacConnectionStore` 将 host/port/name 等写入 UserDefaults，将 device id、shared secret、fingerprint 写入 Keychain。
- 同步：`LocalNetworkSyncAppService` 由 `RokuricsApp` 在 app active 时启动，组合心跳、inventory diff、metadata/artifact 同步、缺失音频上传与到期 retry job drain。

### Mac 侧

- UI 层：`MacRootView` 使用 `NavigationSplitView` 组织 dashboard、iPhone connection、study library、AI chat、settings。
- HTTPS receiver：`SecureReceiverService` 持有 identity、paired devices、request verifier、file stores 和 `SecureLocalHTTPSServer`。
- 路由层：`SecureLocalHTTPSServer` 直接基于 Network.framework 处理 TLS listener、HTTP parsing、health/fingerprint/pair/upload/sync routes。
- 安全层：`MacIdentityManager` 生成/加载本机 signing key、app-local TLS private key JSON 和自签证书，并创建 `SecIdentity` 给 Network.framework；`RequestVerifier` 执行 path/content-type/body-size/header/HMAC/timestamp/nonce 校验。
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
- `LocalNetworkSyncInventory`：本地网络同步 inventory，包含 device、recordings、folders、studyItems、artifacts、可选 legacy manifest，以及可选 `canonicalManifest`。`canonicalManifest` 缺失时必须兼容旧客户端/旧服务端。
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
8. iPhone 根据 Mac 响应更新 metadata upload status 和 progress；retryable failure 写入 `nextRetryAfter`，到期后由 retry drainer 重新进入同一上传主路径。
9. 如果 Mac 已有同 recording 但 checksum/size 不同，Mac 拒绝覆盖，iPhone 将状态标记为 conflict/fatal，而不是继续覆盖旧音频。

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
4. `LocalNetworkSyncDiffPlanner` 先生成 legacy plan；当双端 inventory 都带有有效 `CanonicalManifest` 时，`CanonicalSyncPlanner` 接管 recording metadata diff、recording audio bootstrap candidate 和 Mac generated transcript/note/summary artifact transfer decision，`CanonicalLibrarySyncPlanner` 接管 folder/study item metadata/tombstone semantic planning，随后 `CanonicalApplyPlanner` 与 library apply actions 把 recording/folder/study item metadata apply/send、generated artifact apply、tombstone 和 conflict 统一桥接成 legacy 可执行 action；非 generated artifacts、完整 metadata manifest 执行、UI、retry 和物理存储仍沿用 legacy。
5. metadata 通过 `/sync/apply-metadata` 传 manifest；artifact 通过 `/sync/artifact-request` 取 base64 数据。
6. transcript/note/summary generated artifact 可自动下载，但执行仍桥接到既有 `/sync/artifact-request`/apply 通道并在写入前校验 checksum/size；audio 不自动下载，只通过上传队列补齐。
7. inventory 构建使用 checksum cache，文件 size/mtime 未变化时复用 audio checksum；hash 计算放到主 actor 之外执行。

### 当前本地网络同步边界

- iPhone 是当前主动执行同步的一侧：app active 后启动 heartbeat、foreground tick、periodic tick 和 retry drainer；Mac 手动点击同步只写入 pending sync request，等待 iPhone heartbeat 收到 `syncStartSignal` 后再排队 `manual-sync-requested` tick。
- Mac inventory 是 audio no-op 的关键事实源。Mac 必须在 `/sync/inventory` 中报告 `audioAvailable=true`，且提供与 iPhone 本地一致的 `audioChecksum` 和 `audioSize`，iPhone 才能判断“peer 已有同一音频”。
- metadata sync 和 audio upload 是不同层。`RecordingUploadStatus.uploaded`、metadata manifest 已应用、receive record 已存在，都不能单独证明 Mac audio 已完成。
- UI refresh 不能触发上传。录音列表、详情页、学习库或 Mac inbox refresh 只允许重读本地状态；是否上传必须由 sync/upload state machine 根据 trigger、local audio、peer audio、transfer job 和 ledger 决定。
- 当前最终 no-op 条件应是 peer audio available + same hash + same size。completed ledger 只能作为辅助证据，不能替代 peer inventory。
- peer audio unknown 在普通 sync 中会 deferred，不再当作“需要补传”直接上传；用户手动上传按钮会记录 manual force unknown，retry drainer 会记录 retry-drainer unknown。
- peer audio hash/size 不同现在是冲突，不覆盖 Mac 现有音频；需要用户或后续流程明确处理。

### Canonical Kernel Completion v1

当前 Rokurics 仍不是完整双端统一内核，iPhone `RecordingMetadata`、Mac audio inbox `receive.json`、Mac `StudyItemMetadata`、sync inventory/manifest、UI display state 多套模型继续并存。`RokuricsShared/SyncCore/CanonicalCore.swift` 提供 canonical 数据结构，`CanonicalProjectionContract.swift` 提供 generated artifact kinds、producer/capability 与 safe logical path token 合同，`CanonicalSyncPlanner.swift` 提供 recording/artifact sync decision，`CanonicalApplyPlan.swift` 提供 apply/conflict/tombstone action model，`CanonicalLibraryObject.swift` 与 `CanonicalLibrarySyncPlanner.swift` 提供 folder/study item/standalone note/tombstone semantic model 和 plan，`CanonicalTransferStateMachine.swift`、`CanonicalObjectProjection.swift`、`CanonicalInventoryBuilderContract.swift`、`CanonicalRetirementReadiness.swift` 提供只读状态投影、inventory coverage 和 readiness diagnostics。`IPhoneCanonicalRecordingAdapter` / `MacCanonicalRecordingAdapter` 与 `IPhoneCanonicalLibraryAdapter` / `MacCanonicalLibraryAdapter` 从已经加载或已经计算出的 legacy facts 只读生成 `CanonicalManifest`，`CanonicalShadowDiagnostics.swift` 继续生成 shadow report。

Canonical Kernel Completion v1 已接入真实 inventory/tick 路径，但范围被明确限制：

- iPhone sync tick 在旧 `LocalNetworkSyncInventory` 构建完成后，用同一批 `RecordingMetadata`、study manifest、inventory audio facts 和已下载 generated artifact facts 生成 canonical manifest、inventory coverage 与 `canonical-shadow.jsonl` report；iPhone generated facts 不作为 authoritative producer。
- Mac `/sync/inventory` 在旧 response 生成完成后，用同一批 inbox items、study manifest、recording entries、audio facts 和 generated artifact facts 生成 canonical manifest、inventory coverage 与 `canonical-shadow.jsonl` report；Mac generated transcript/note/summary facts 是 authoritative producer。
- 双端 `LocalNetworkSyncInventory` 新增 optional `canonicalManifest`，缺字段仍可解码；manifest 兼容扩展 library objects、folders、studyItems、standalone notes、library tombstones 和 capabilities，字段参与 inventory checksum，用于同版本双端的 canonical plan。
- iPhone `LocalNetworkSyncEngine.performTick` 保留 legacy planner 作为基础计划和 fallback；只有 local/peer 都有有效 canonical manifest、schema/hash/capability 通过校验时，才把 recording metadata diff、recording audio bootstrap candidate、generated artifact transfer decision、folder/study item metadata/tombstone semantic plan 和 recording/generated/library/tombstone/conflict apply semantics 替换为 canonical plan。
- canonical audio bootstrap 只产出已有上传主路径可消费的 upload candidate，最终仍调用 `RecordingUploadCoordinator.uploadAndWait`，由 `RecordingUploadClient` / `SecureMacUploadClient` 使用既有 HTTPS/HMAC/pinning/resumable routes 上传。
- canonical generated artifact download 只产出可桥接到旧 legacy artifact action 的 decision；实际下载仍使用 `/sync/artifact-request`，实际应用仍使用既有 artifact apply 逻辑，不新增 route，不创建 generated artifact upload job。
- canonical apply plan 与 library apply actions 定义 recording/folder/study item metadata apply/send、generated artifact download/apply、object/library tombstone apply/send、artifact tombstone unsupported/no-physical-delete 和 conflict record；实际 metadata 写入仍由双端 `StudyLibraryStore.applySyncManifest` 完成，实际 generated artifact 写入仍由旧 artifact request/apply 完成。
- canonical conflict model 对 metadata concurrent edit、audio content mismatch、generated artifact mismatch、active-vs-tombstone 采取保守记录策略，不覆盖对端音频或 artifact，不自动选择胜者。
- canonical tombstone model 只表示 soft delete、anti-resurrection、no physical delete、no permanent delete 和 no GC；对象 tombstone 会阻止 generated artifact download 复活已删除对象。
- canonical v1 接管 folder/study item metadata/tombstone 的语义规划和 metadata manifest 桥接，但不接管非 generated artifact、UI display state、retry drainer、Mac pending sync、Mac `applySyncManifest` 内部写入、`receive.json` 写入、legacy storage schema 或物理存储迁移。
- transfer state projection 只把 legacy transfer/upload strings 映射为 canonical phase；不修改 retry queue、upload ledger 或 pending sync。
- ObjectProjection 只读生成 display facts，可用于后续 UI 读取；当前不驱动 UI、sync、upload 或 artifact download。
- CanonicalInventoryBuilderContract 只从调用方已经提供的 facts 组装 manifest 与 coverage report；不做文件 IO、目录扫描或 hash 计算。
- CanonicalRetirementReadiness 只输出 readiness diagnostics；只要 transport、upload runtime、physical storage 或 UI 仍由 legacy 负责，就阻塞 retirement，不删除或禁用 legacy。
- shadow report 只写 hash prefix、计数、availability、byte size、逻辑文件名末段和 mismatch category；不写完整 hash、绝对路径、secret、完整 fingerprint、完整 transcript 或完整 provider response。
- shadow report 仍只用于观测；canonical planner diagnostics 可记录 plan used/fallback/audio bootstrap/no-op/deferred/conflict，但不得写入敏感内容。

### Canonical Runtime Kernel Offline Completion v1

`CanonicalFileRuntime.swift`、`CanonicalTransportRuntime.swift`、`CanonicalUploadRuntime.swift`、`CanonicalApplyRuntime.swift`、`CanonicalConflictResolver.swift`、`CanonicalRuntimeHarness.swift` 和 `CanonicalRuntimeReadiness.swift` 提供一套纯 Swift/Fundation 风格的离线 runtime kernel。它把 canonical plan/action 放进可执行的 in-memory harness 中验证，但不拥有真实生产链路。

离线 runtime kernel 的职责：

- File runtime 只接受 root token + logical path token，拒绝绝对路径、scheme URL、反斜杠和 `.`/`..` traversal；写入时校验预期 hash/size，支持 no-overwrite、same-content idempotency、metadata blob 和 tombstone marker，不执行物理删除。
- Transport runtime 是 in-memory route dispatcher，校验 source/destination 注册、route allowlist、capability、body hash、manifest hash/schema 和 idempotency key；不使用 Network.framework，不新增 HTTPS route。
- Upload runtime 支持 resumable session、offset/confirmedBytes、chunk hash、duplicate chunk idempotency、retry snapshot 和 finalize 后写入 in-memory file store；不绕过真实 `RecordingUploadCoordinator`。
- Apply runtime 在 in-memory store 中执行 canonical apply plan/library plan：metadata apply/send 写 metadata blob，generated artifact download/apply 校验 peer bytes 的 hash/size 后写本地 generated store，tombstone 只标记 soft tombstone，conflict/deferred/no-op 只记录。
- Conflict resolver 默认保持 unresolved/manual/keep-both/no-overwrite 策略，不自动覆盖音频、generated artifact 或 active-vs-tombstone 场景。
- Runtime harness 构造 iPhone/Mac 两个 in-memory node，离线跑 manifest/planner/apply/upload/readiness；用于测试 canonical kernel 端到端语义，不读取真实 Documents/Application Support，不触发 UI、Mac receiver、real upload client、retry drainer 或 pending sync。
- Runtime readiness 只说明离线 file/transport/upload/apply/conflict/harness 是否完成；只要 production owner 仍是 legacy，就把 production migration 标为 blocked。

### Canonical File Kernel Runtime v9.1

`CanonicalFileSnapshotRuntime.swift`、`CanonicalManifestRuntime.swift`、`CanonicalChecksumRuntime.swift`、`CanonicalAsyncDiagnosticsWriter.swift`、`CanonicalMainActorHotPathGuard.swift` 和 `CanonicalFileKernelRuntimeReadiness.v910(...)` 把 File 域从 contract/离线 harness 继续推进到 runtime owner 边界。该层不导入 UIKit/AppKit，不绑定 Rokurics 本地 HTTPS/TLS/HMAC；iPhone/Mac 只通过 `IPhoneCanonicalFileRuntimeAdapter`、`MacCanonicalFileRuntimeAdapter` 提供已经安全归一化的 logical artifact facts。

File snapshot 以 root token + safe logical scope 为入口，由 `CanonicalFileTreeSnapshotBuilder` actor 在 detached utility task 内构建。snapshot 只包含 stable file identity、logical token、size、mtime/contentVersion、kind、domain hint 和可选 hash proof；diagnostics 只输出 root token、计数、duration、hash prefix/cache key prefix 和 MainActor attempt count，不输出绝对路径或完整 hash。

Manifest runtime 是纯值层：`CanonicalManifestRuntimeBuilder` 从 File snapshot 组装 `CanonicalFileManifest`，不访问文件系统。content-stable cache key 使用 root token、logical token、size、mtime/contentVersion、schema、domain hint、hash prefix，不使用 `generatedAt`，因此同内容不同生成时间不会导致 manifest cache churn。

Checksum runtime 是 actor-backed cache wrapper。命中时跳过 hash provider；root token、logical token、size、mtime/contentVersion、schema、algorithm 或 domain hint 变化均 stale；corruption fail-closed 后重建，而不是阻断 legacy fallback。完整 hash 只留给 protocol/internal proof，diagnostics 只允许 prefix。

iPhone inventory 继续使用既有 background input path，把已构建 artifacts 适配为 File snapshot/manifest；不改变 sync plan、upload job、route 或 UI 行为。Mac `/sync/inventory` 只在 canonical mode `buildsCanonicalFacts` 时为当前 request 构建一次 File snapshot/manifest；`oldKernel` 和 blocked 不构建 canonical file snapshot。双端 `StudyLibraryStore` 的 v8.69 effective read cache 保持不变，只增加 File-domain cache key prefix/invalidation reason diagnostics。

### Canonical Production Ports & Dry-Run Migration Readiness v1

`CanonicalProductionPorts.swift` 把未来生产迁移需要的边界先声明为 shared contract：file、transport、upload、apply、clock、diagnostics 和 capability port，外加 production snapshot、runtime node state、legacy action snapshot、port readiness、suppressed trace 与 redacted diagnostics event。该合同只声明能力和审计字段，不实现真实 HTTPS route、真实 upload client、真实 store 或 UI，不替代 `RecordingUploadCoordinator`、`SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier` 或 `StudyLibraryStore.applySyncManifest`。

`IPhoneCanonicalProductionSnapshotAdapter` 与 `MacCanonicalProductionSnapshotAdapter` 是生产事实的只读 adapter。它们只消费调用方已经加载或已经计算出的 recording/library/tombstone/generated artifact/legacy action facts，调用 canonical inventory/projection/readiness builder 生成 `CanonicalProductionSnapshot`；不读取 Documents/Application Support、不扫描目录、不计算大文件 SHA256、不写 `receive.json`、不调用 `applySyncManifest`、不创建 upload job 或 apply job。

`IPhoneCanonicalDryRunPorts` 与 `MacCanonicalDryRunPorts` 是 suppressed dry-run port set。file port 只验证 root token 和 safe logical path token 并返回 would-write trace；transport port 只构造 signed/verified route projection；upload port 只构造 would-upload trace；apply port 只构造 would-apply trace。所有 dry-run trace 都必须保持 suppressed：不写真实文件、不发网络、不上传、不调用真实 apply、不改 UI、不改 retry queue、不改 Mac pending sync。

`CanonicalDryRunMigrationPlanner.swift` 比较 canonical dry-run action 与 legacy action snapshot，输出 dry-run readiness、legacy equivalence report 和 production migration gate。metadata churn 类 legacy-only action 可以归为 canonical 更保守且非阻塞；canonical 比 legacy 更激进、出现 conflict、缺 required port/capability、unsupported object、UI/retry/Mac pending sync/user data migration 未设计，都必须阻塞。当前 gate 只能给出 `eligibleForManualMigrationDesign`；`eligibleForRuntimeSwitch` 必须为 false，`retired` 必须为 false，legacy 仍是 production owner。

`safeLogicalPathToken` 只证明 logical path token 语法安全，不能单独证明文件属于生产 root；未来真实 file adapter 仍必须绑定 root token、store root 和 security-scoped access。`manifestHash` 只用于 manifest integrity/fingerprint，不能作为认证或授权，不能替代 TLS pinning、HMAC、nonce、body hash、Keychain 或 RequestVerifier。production/dry-run diagnostics 只允许写 event、domain、capability、count、bool、reason、hash prefix 和 logical token 摘要，不得写完整 transcript/note/summary/provider response、完整 hash、绝对路径、secret、完整 fingerprint 或本机隐私路径。

### Canonical Production Runtime API & Port Contract v1

`CanonicalKernelFacade.swift` 是 canonical kernel 对外的稳定外观 API。它把 snapshot/build manifest/planner/apply/library/transfer/object projection/readiness/dry-run/legacy compare/offline execute/production execute/rollback preview 统一成 shared SyncCore 调用面：`buildSnapshot`、`buildManifest`、`planSync`、`buildApplyPlan`、`buildLibraryPlan`、`buildTransferProjection`、`buildObjectProjection`、`buildRuntimeReadiness`、`buildProductionReadiness`、`dryRunMigration`、`compareLegacy`、`executeOffline`、`executeProduction` 和 `rollbackPreview`。它不导入 UIKit/AppKit/AVFoundation/Network.framework，也不直接引用真实 `RecordingUploadCoordinator`、`SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier`、`AudioFileStore`、`MacRecordingFileStore` 或 `StudyLibraryStore.applySyncManifest`。

Facade 执行模式是明确的 API 边界：`disabled` 默认拒绝执行，`dryRun` 只运行 suppressed dry-run，`offlineRuntime` 只使用离线 harness，`productionShadow` 只允许生产前 shadow/audit 语义，`productionExecute` 才允许请求真实 production port 方法。当前 app 没有任何 UI、sync tick、heartbeat、retry drainer 或 Mac pending sync trigger 调用 `executeProduction`。

`CanonicalProductionPorts.swift` 现在把 production port 从 dry-run projection 扩展为真实执行方法合同，同时保留所有 dry-run 方法。file port 需要表达 root-bound metadata/artifact read/write/hash/list/verify/rollback；transport port 需要表达 signed request build/send/receive/verify、manifest exchange、artifact request、apply metadata send 和 upload session route；upload port 需要表达 resumable start/resume/chunk/query/finalize/cancel、ledger read/write、failure classify、retry projection 和 rollback；apply port 需要表达 metadata/generated artifact/tombstone/conflict/precondition/postcondition/rollback；diagnostics、clock 和 capability port 负责 redacted production trace、monotonic time/timestamp window、capability/schema validation。协议默认实现继续让旧 dry-run port 编译，并把未实现的真实方法返回 suppressed/not implemented 风险，而不是静默执行。

`CanonicalProductionExecution.swift` 定义 production execution result、failure、redacted side effect、execution trace、execution token/policy/audit、rollback checkpoint/action/plan/result/audit 和 execution guard。`CanonicalProductionExecutionGuard` 在 `executeProduction` 调用端口前强制检查：mode 必须是 `productionExecute`，token 必须显式提供并带 owner approval，operation/domain 必须在 allowlist，rollback plan 必须覆盖 required domains，dry-run equivalence report 必须与 token 匹配且无 blocking divergence，unresolved conflicts 必须为空，required production port 必须是 non-dry-run，migration gate 不能阻塞。失败时 facade 返回 rejection result，side effects 为空。

生产执行结果只描述 side-effect contract，不携带敏感内容。`CanonicalProductionSideEffect` 与 `CanonicalProductionExecutionTrace` 只能记录 kind、domain、operation、redacted target、hash prefix/byte count/result/failure 分类等摘要；不得记录完整 transcript/note/summary/provider response、完整 hash、绝对路径、secret、完整 fingerprint、API key 或本机隐私路径。当前新增测试使用内存 fake production ports 验证合同和 guard，不代表真实生产 adapter 已实现。

### Canonical Production Adapter Skeletons & Migration Facade v1

双端 app target 现在各有四类 production adapter skeleton 和一个 migration facade。iPhone 文件为 `IPhoneCanonicalProductionFilePort.swift`、`IPhoneCanonicalProductionTransportPort.swift`、`IPhoneCanonicalProductionUploadPort.swift`、`IPhoneCanonicalProductionApplyPort.swift`、`CanonicalIPhoneMigrationFacade.swift`；Mac 文件为 `MacCanonicalProductionFilePort.swift`、`MacCanonicalProductionTransportPort.swift`、`MacCanonicalProductionUploadPort.swift`、`MacCanonicalProductionApplyPort.swift`、`CanonicalMacMigrationFacade.swift`。

这些 adapter skeleton 的架构位置是 canonical shared port contract 与真实 legacy runtime 之间的未来迁移边界。当前默认行为仍是 disabled/suppressed；只有测试显式传入 temp-root file port、fake loopback transport、fake upload ledger 和 fake apply store 时，才会在内存或临时目录中验证合同。它们不替换 `AudioFileStore`、`MacRecordingFileStore`、`SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier`、`RecordingUploadCoordinator`、`RecordingUploadClient` 或 `StudyLibraryStore.applySyncManifest`。

file adapter 只在 fake temp-root 模式验证 root-bound logical token、hash/size、rollback/tombstone contract 和 redacted resolution token；transport adapter 只映射既有 route 并默认抑制真实 network send；upload adapter 只验证内存 resumable session/ledger，不创建真实 upload job；apply adapter 只记录内存 metadata/generated/tombstone/conflict result，不写真实 store 或 `receive.json`。

`CanonicalIPhoneMigrationFacade` 与 `CanonicalMacMigrationFacade` 组合 snapshot adapter、production port set 和 `CanonicalKernelFacade`，提供 dry-run、legacy equivalence、migration gate、shadow preparation 和 guarded execution 入口。facade 默认 disabled，runtime switch false；当前没有接入 `LocalNetworkSyncEngine.performTick`、heartbeat、manual/periodic sync、retry drainer、Mac pending sync、UI、真实 HTTPS route 或真实 store。

### Canonical Shadow Migration Wiring

`CanonicalShadowMigrationConfiguration` 默认 `.disabled`。只有调用方显式传入 enabled configuration 时，iPhone `LocalNetworkSyncEngine.performTick` 会在 legacy `LocalNetworkSyncDiffPlanner.plan` 之后、`canonicalSyncPlanIfAvailable` 之前调用 shadow migration helper；Mac `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 会在本地 inventory 构建完成后调用 shadow migration helper。两个 helper 都只记录诊断，不把 shadow result 返回给 legacy 执行路径。

`IPhoneCanonicalShadowPortFactory` 与 `MacCanonicalShadowPortFactory` 只消费调用方已经持有的 `LocalNetworkSyncInventory.canonicalManifest`、可选 peer inventory 和 legacy diff action id。它们组装 `CanonicalProductionSnapshot`、suppressed dry-run port set、capability/readiness 摘要和安全诊断摘要；不得读取 store、扫描目录、计算额外文件 hash、发网络请求、写入 `receive.json`、创建 upload/apply job 或修改 UI。

Shadow mode 语义：

- `.disabled`：默认，不记录 migration 事件。
- `.diagnosticsOnly`：记录 started/suppressed/completed，不运行 dry-run。
- `.dryRunCompare` / `.shadowReadOnly`：只运行 `CanonicalDryRunMigrationPlanner` 和 suppressed dry-run ports，缺 local/peer snapshot 时记录 blocked 且非 fatal。
- `.shadowReadOnlyWithNetworkProbe`：仅允许额外的 read-only probe policy；默认 probe policy 关闭，mutating route 必须拒绝。
- `.blockedProductionExecute` 和任何 iPhone/Mac role 的 production execute 都必须阻断；真实 production execute 只保留 testHarness-only 测试路径。

### Canonical Execution Shadow Preparation v1

Execution shadow preparation 是 shadow migration 的下一层排练，不是 runtime cutover。`CanonicalExecutionShadow.swift` 在共享层组合 shadow file store、read-only transport projection、shadow upload receiver、in-memory apply store、rollback rehearsal 和 redacted event/report；`CanonicalKernelExecutionMode` 增加 `executionShadowDryRun`、`executionShadowWithShadowFileStore`、`executionShadowWithReadOnlyTransportProbe`。这些模式只允许 iPhone/Mac on-device role 做 shadow preparation，仍不允许进入 `productionExecute`。

双端 shadow port factory 在 execution shadow 模式下返回 shadow file/transport/upload/apply port set：iPhone 使用 `IPhoneCanonicalShadowFilePort.swift` 与 `IPhoneCanonicalShadowTransportPort.swift`，Mac 使用 `MacCanonicalShadowFilePort.swift` 与 `MacCanonicalShadowTransportPort.swift`。file port 必须绑定临时 shadow root，拒绝 production root、root 内逃逸和 hash/size mismatch；tombstone 只做 shadow marker，不做物理删除。upload port 只使用 shadow receiver 与 canonical resumable upload runtime；apply port 只写 in-memory shadow apply store；transport port 只构造 signed request projection 和 route classification，默认不发送网络。

iPhone `LocalNetworkSyncEngine.performTick` 的 execution shadow seam 仍位于 legacy diff 之后、canonical/legacy plan 选择之前；Mac `/sync/inventory` 的 seam 仍位于本地 inventory response 构建完成之后。runner 只记录 `canonicalExecutionShadow*` diagnostics，不把结果返回 legacy plan，不改变 pending upload/download/conflict 计数，不改变 Mac inventory response，不触发 retry drainer、Mac pending sync、真实 upload、真实 apply、真实 network send 或 UI 更新。

decision shadow green 只表示 dry-run/equivalence/gate 观测通过，不等于 execution shadow green；execution shadow green 只表示 shadow root/shadow receiver/in-memory apply/read-only projection 排练通过，不等于 production store、route、upload/apply 或 runtime owner 已迁移。真正 production cutover 仍需要单独审计、显式 owner approval、non-dry-run production ports、rollback plan、dry-run equivalence、execution shadow evidence 和真实设备验证。

Shadow migration diagnostics 写 `canonicalShadowMigrationStarted`、`canonicalShadowMigrationSuppressedSideEffects`、`canonicalShadowMigrationCompleted`、`canonicalShadowMigrationBlocked`、`canonicalShadowMigrationDivergenceDetected`、`canonicalShadowMigrationEquivalent`。事件只包含 trigger、nodeRole、mode、domain、gate/equivalence 状态、计数、reason 和 redacted summary；不得写绝对路径、完整 hash、secret、完整 fingerprint、API key、完整 transcript/note/summary/provider response。

### Canonical Recording Metadata Single-Domain Shadow Enablement v1

`CanonicalSingleDomainShadowConfiguration` 默认 `.disabled`，并且 `CanonicalShadowDomainEnablement` 必须显式包含 `.recordingMetadata` 才会运行。当前仅实现 recording metadata 单域；启用其他 domain 不会触发 metadata apply/send rehearsal。允许模式限定为 diagnostics-only、dry-run compare、execution shadow dry-run 和 execution shadow with shadow file store；production execute 或 blocked execution mode 只记录 blocked diagnostics。

`CanonicalRecordingMetadataExecutionShadowPlanner` 的输入来自调用方已经持有的 local/peer `CanonicalManifest`、`CanonicalSyncPlan`、`CanonicalApplyPlan` 和 `CanonicalLegacyActionSnapshot`。iPhone `LocalNetworkSyncEngine.performTick` 在 legacy diff 后复用同一批 local/peer inventory 与 canonical plan；Mac `/sync/inventory` 只有本地 inventory，缺 peer snapshot 时记录 `canonicalRecordingMetadataExecutionShadowBlocked` / `insufficientPeerSnapshot`，不改变 response shape。

`CanonicalRecordingMetadataShadowStore` 是 in-memory shadow store，只保存 objectID、hash prefix、modifiedAt、tombstone flag、rollback checkpoint id、pre/postcondition 和 apply/send/tombstone marker write 摘要。它不读取或写入真实 `metadata.json`，不调用 `StudyLibraryStore.applySyncManifest`，不发送 `/sync/apply-metadata` 或任何 upload/apply route，不触碰 `receive.json`、upload ledger、retry queue、Mac pending sync、UI 或生产文件路径。

单域 shadow 判定规则：metadata no-op 不写 shadow record；canonical download metadata 只 shadow apply；canonical upload metadata 只 shadow send projection；同 modifiedAt 不同 hash 是 conflict 且不 apply/send；newer tombstone 只写 marker；active-vs-tombstone conflict 只记录 conflict；legacy 会 upload/download 但 canonical 因 canonical metadataHash 相同 no-op 时是 non-blocking `canonicalMoreConservative`；canonical apply/send 而 legacy no-op/empty 时是 `canonicalMoreAggressive`，默认 blocking，除非 policy 显式允许。

诊断事件为 `canonicalRecordingMetadataExecutionShadowStarted`、`canonicalRecordingMetadataExecutionShadowCompleted`、`canonicalRecordingMetadataExecutionShadowBlocked`、`canonicalRecordingMetadataShadowApplyRehearsed`、`canonicalRecordingMetadataShadowSendRehearsed`、`canonicalRecordingMetadataShadowNoOp`、`canonicalRecordingMetadataShadowDivergenceDetected`、`canonicalRecordingMetadataShadowEquivalent`、`canonicalRecordingMetadataShadowProductionExecuteBlocked`。诊断只写 syncRunID、trigger、nodeRole、mode、domain、objectID、count、reason 和 hash prefix，不写完整 metadata、完整 hash、路径、secret、fingerprint 或 body。

### Canonical real-data shadow copy 与 read-only probe

2026-06-03 新增的 execution shadow evidence 层分为三部分：

1. `CanonicalRealDataShadowCopyRunner` 只接受 root-bound shadow target。它拒绝 production root、production root 子路径、source/target 同一文件、unsafe logical path token、source 越出显式 production root、超限 artifact 和 hash mismatch。成功时只返回 root kind/id、entry count、bytes、descriptor count、hash prefix/equality proof count 等 redacted summary，不返回绝对路径或完整 hash。
2. iPhone/Mac adapter 只消费调用方已经加载的 facts。iPhone 侧可复制 `RecordingMetadata`、inventory/study metadata 和显式 generated artifact；Mac 侧可复制 `RecordingReceiveRecord`、`MacRecordingInboxItem` descriptor、inventory/study metadata 和显式 generated artifact。audio 默认 descriptor-only，只写 object id、logical path token、size/hash prefix evidence，不复制真实音频字节。
3. `CanonicalShadowRootLifecycle` 默认立即清理 shadow root；显式 retain diagnostics 时只保留 bounded shadow root 并清理旧 sibling，且拒绝 production root。cleanup diagnostics 只包含 root kind/id、removed/retained count/bytes 和 failure 分类。

Read-only transport probe 使用 `CanonicalReadOnlyTransportProbePolicy` 独立表达 route allowlist/denylist。默认 disabled；显式启用时默认仍 suppressed network send。允许的 route 仅包括 health、fingerprint、sync status、sync inventory、device status；artifact request 必须显式 bounded allow。pair、upload metadata/audio/resumable start/status/chunk/finalize、sync apply/apply-metadata/manifest 等 mutating route 必须拒绝。probe 只证明 TLS/HMAC/body hash/timestamp/nonce/signature projection 保持；`manifestHash` 不能作为 auth 边界。

该层只把证据接入 execution shadow report/diagnostics，不影响 legacy diff、canonical/legacy plan 选择、Mac inventory response、upload coordinator、secure upload client、receiver route、request verifier、apply store、retry drainer、Mac pending sync 或 UI。

### Canonical v8 recording metadata no-commit app seam

`CanonicalCutoverAppSeamConfiguration` 是 app 层 cutover seam 的独立开关，默认 `.disabled`。NoCommit hook 当前唯一可执行 mode 是 `guardedExecuteNoCommit`；`guardedExecuteCommit`、`productionExecute`、`canaryCommit`、非 `recordingMetadata` domain、view refresh、retry drainer fresh metadata、缺 local/peer snapshot、证据不足、unsupported action、unstable metadata hash 和 unresolved conflict 都会被 `CanonicalRecordingMetadataNoCommitRunner.evaluateGate` 阻断。v8.6 guarded commit hook 使用同一 configuration，但只响应 `guardedExecuteCommit` / `canaryCommit` 并记录 report，不进入 NoCommit staging。

allowed 时，runner 只对 `recordingMetadataApply` / `recordingMetadataSend` candidate 调用 `CanonicalRecordingMetadataNoCommitExecutor.stageNoCommit`。iPhone/Mac executor 只在临时 staging root 下写 redacted payload summary：object/action id、direction、bridge hint、hash prefix、modifiedAt、tombstone 和 send route projection。结果显式标记 `calledApplySyncManifest=false`、`sentNetworkRequest=false`、`wroteProductionStore=false`、`suppressedLegacyDuplicate=false`。

v8.2 将 staging root lifecycle 从 executor 内部细节提升为共享合同：默认 root 是系统临时目录下的 NoCommit root，stage 后立即 cleanup；显式 diagnostics retain 必须有 `maxAge`、`maxCount`、`maxBytes` 边界，并会清理旧 sibling。`CanonicalNoCommitStagingRootLifecycle` 在写入前拒绝 production root 或 production root 子路径；cleanup 失败或 production-root refusal 只作为 NoCommit evidence/blocker 记录，不会转成真实 production write。

equivalence 比较 canonical direction、legacy direction、object id、metadata hash prefix、modifiedAt direction、tombstone state、send route `/sync/apply-metadata` 和可用的 payload size/hash evidence。canonical 更激进、证据不足、unsupported 或 divergent 均为 nonfatal blocker；legacy fallback 始终 preserved，`duplicateLegacySuppressedActionIDs` 始终为空。

`CanonicalNoCommitEvidenceReport` 汇总 candidate count、would apply/send、equivalent/divergent/insufficient/unsupported count、staging lifecycle、cleanup status、route projection、legacy action comparison、production commit suppressed 和 legacy duplicate suppressed。report 和 `canonicalV8NoCommit*` diagnostics 只包含 redacted summary、hash prefix、root kind/id 与计数，不包含 staging root 绝对路径或真实 metadata JSON。该 report 可作为 future guarded commit gate evidence 的输入，但当前不触发 `guardedExecuteCommit`。

`CanonicalMigrationStageConfiguration` 是只读 migration config descriptor，不是执行调度器。默认 stage 是 `.off`；`recordingMetadataNoCommit` 只声明 diagnostics + staging root write side effect、required evidence 和 recordingMetadata-only domain；`recordingMetadataGuardedCommit` 只描述 future production commit 所需 evidence/owner/rollback，不会创建 token、不调用 executor、不切 runtime switch。

### Canonical v8.6 guarded commit app seam

`CanonicalRecordingMetadataGuardedCommitSeam` 是 v8.6 的 app seam runner。它评估 owner-approved token、local/peer snapshot、recordingMetadata-only candidate、stable metadata hash、unresolved conflict、real-data shadow copy、execution shadow、dry-run equivalence、read-only transport probe、root-bound apply port readiness、rollback plan/readiness、legacy fallback、production execution guard 和 canary policy。`viewRefresh` 与 `retryDrainer` 仍被拒绝。

该 seam 的结果显式记录 `commitAttemptedCount=0`、`committedObjectCount=0`、`productionCommitCalled=false`、`realApplyPortCommitCalled=false`、`networkSendCalled=false`、`applySyncManifestCalled=false`、`metadataJSONWritten=false`、`duplicateLegacySuppressedActionIDs=[]`、`legacyPlanUnchanged=true`、`productionPlanUnchanged=true`、`runtimeSwitchEnabled=false`。即使 gate allowed，`canonicalRecordingMetadataGateAllowedButNoExecution` 与 `canonicalRecordingMetadataCommitSkippedBecauseCanaryBudgetZero` 也说明 `N=0` 没有执行对象。

iPhone hook 只把 report 写入 `ConnectionDiagnosticsStore`；Mac hook 只把 report 写入 connection diagnostics。两端都不把 report 返回给 plan executor、store、transport、upload、UI、retry drainer 或 Mac pending sync。

iPhone seam 在 `LocalNetworkSyncEngine.performTick` 的 legacy diff 后、canonical/legacy plan 选择前运行，复用同一批 local/peer inventory、canonical manifest、canonical sync/apply plan 和 legacy diff facts，只写 `ConnectionDiagnosticsStore`。Mac seam 在 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` inventory 构建后运行；由于 `/sync/inventory` 请求没有 peer canonical snapshot，启用时应记录 `insufficientPeerSnapshot`，并继续返回原 inventory response。该 seam 不调用旧 production cutover runner，不替换 legacy plan，不改 pending count、state store、upload ledger、retry、Mac pending sync、UI、route、security、真实 store 或 `receive.json`。

### Canonical v8.17 libraryMetadata read-side pilot completion

v8.17 在 `libraryMetadata` 唯一 active pilot 上增加 read-side parallel evidence 层。共享 `CanonicalLibraryMetadataReadProjection` 从 legacy manifest 和 canonical library objects 生成可比较 read snapshot：folder metadata、study item metadata、standalone note metadata、folder membership、filing/tags/color/trash state、business modified time 与 redacted logical resource token summary。projection 明确排除 standalone note 全文、真实资源路径、完整 hash、provider response 和本机隐私路径；发现 unsupported object 或 path leak risk 时只生成 blocker/diagnostic。

`CanonicalLibraryMetadataReadSideParallelDiff` 比较 legacy/canonical snapshot 并输出 divergence taxonomy、equivalence、blocker 和 bounded summary。`CanonicalLibraryMetadataReadSideCutoverEvaluator` 只评估 default-off read cutover candidate：`disabled` 不产生 diff；`parallelOnly` 只记录 diff；`canonicalReadCandidate` / `guardedCanonicalRead` 需要 v8.16 write-side staged canary evidence、zero divergence、fallback 可用、matrix 仍为 `libraryMetadata` sole active pilot，并且即使 ready 也返回 `readPathSwitched=false`、`uiMutated=false`、`syncOrUploadTriggered=false`。

双端 seam 均默认 `.disabled`。iPhone `IPhoneLibraryMetadataReadSideSeam` 在 sync tick 中复用已加载的 local inventory/canonical manifest facts，只写 diagnostics store；Mac `MacLibraryMetadataReadSideSeam` 在 `/sync/inventory` 构建过程中复用本地 inventory/canonical manifest facts，只写 connection diagnostics。两端 seam 不替换 legacy read model，不改变 inventory response、legacy/canonical plan、state store、upload ledger、retry queue、Mac pending sync、route/security、真实 store、`receive.json` 或 UI。

`CanonicalLibraryMetadataRetirementCandidateEvaluator` 在 v8.17 只生成 report-only readiness。它需要 write-side evidence、read-side cutover evidence、observation window、fallback 和 zero divergence；结果始终 `legacyDeleted=false`、`legacyDisabled=false`、`reportOnly=true`。legacy planner/store/route/read path 的删除或禁用必须后移到独立阶段。

### Canonical v8.1 Live Read-Only Transport Probe

v8.1 在 canonical shadow/cutover seam 附近增加默认关闭的 live read-only probe。共享 `CanonicalLiveReadOnlyTransportProbePolicy` 将执行拆成 `disabled`、`classifyOnly`、`buildSignedEnvelopeOnly`、`sendReadOnlyProbe` 和 `blockedMutatingRoute`；只有 `sendReadOnlyProbe` 且 explicit internal config enabled 时才允许发送网络请求，failure 一律 nonfatal。

iPhone sender 只复用现有 `SecureMacUploadClient` signed JSON request 与 pinned session；签名 payload、headers、TLS pinning、HMAC、timestamp、nonce、body SHA256 和 Keychain pairing snapshot 语义保持不变。diagnostics 只记录 mode、route、result、reason、syncRunID、trigger、body/hash prefix 等 redacted fields，不记录 secret、完整 fingerprint、完整 hash、request body 或 response body。

Mac receiver 不新增 route，不改变 route allowlist。probe marker 只作为 audit marker，不能绕过 `RequestVerifier`；marked mutating/unknown/default-disabled route 会 blocked。marked `/sync/inventory` 在 verifier accepted 后使用已有 inventory response shape 返回普通 inventory，并用 pre/post snapshot 比较 receive record count、upload session count、pending sync request count 和 study manifest checksum；snapshot 不可得时记录 unavailable，不假装 no mutation。

当前源码可证明 `/device/status`、`/sync/status` 和 upload/apply/pair/session routes 会写连接、sync、upload 或 store 状态，因此 live probe denylist 拒绝。`/sync/artifact-request` 默认 blocked，只有 explicit bounded artifact policy 才允许分类通过；v8.1 不让 audio 自动下载、不创建 upload job、不调用 `applySyncManifest`、不写 `receive.json`、不改变 pending sync、retry、UI、legacy plan、canonical production plan 或 runtime switch。

Canonical 语义：

- `objectID` 是同一录音跨端稳定 identity。
- `createdAt` 是录音创建时间，跨端同义，不等于 Mac `receivedAt`。
- `modifiedAt` 是 title / filing / tags / deletion 等业务 metadata 最后修改时间，用于业务 LWW；Mac 端 `receiveRecord.updatedAt`、inbox fallback 的即时 `updatedAt`、transcription/note/receive 处理状态、`receivedAt` 和 `observedAt` 都不能作为业务 LWW 时钟。只有已证明的 study item 业务编辑、metadata-only sync item、study-only item 或 tombstone 才能提供 Mac canonical `modifiedAt`。
- `metadataHash` 只 hash `CanonicalRecordingMetadata` 的规范化业务字段，不 hash 旧 `RecordingMetadata` 或 `StudyItemMetadata` 整体 JSON；合同版本为 `canonical-recording-business-metadata-v1`，字段限定为 `objectID`、title、filing、规范化 tags、delete/tombstone 状态和 delete 时间。
- `metadataHash` 必须排除 `createdAt`、`modifiedAt`、duration、upload progress、display state、ledger、receiveStatus、processing state、local path、diagnostic fields、`receivedAt`、`observedAt`、audio hash/size、transcript/note 内容和 provider response。`createdAt` 秒级/亚秒级差异不应导致 metadata hash mismatch。
- `audioAvailable` 只能由 canonical audio artifact 的 `availability == available`、`byteSize` 和 `contentHash` 同时证明。metadata uploaded、manifest applied、receive record existing、completed ledger、UI uploaded 都不能单独证明 audio uploaded。
- audio no-op 条件是 peer audio available + same `contentHash` + same `byteSize`；peer unknown 不等于 missing，普通 sync 下必须 deferred。
- 同一 `objectID` / `artifactID` 两端都有 artifact 但 hash 或 size 不一致时是 conflict，不能覆盖对端音频。
- generated artifact authoritative producer 当前限定为 Mac 侧 transcription/note generation 输出：`transcriptJSON`、`transcriptMarkdown`、`noteMarkdown`、`noteJSON`、`summaryJSON`。iPhone 本地已下载 artifact 可证明本地已有同内容，但不证明 iPhone 是 producer。
- generated artifact same no-op 条件是同 `objectID`/kind 的本地与 peer artifact 同 hash、同 size；peer authoritative 且本地缺失或 peer 更新时可生成 download；peer unknown/unproven 应 deferred；本地 authoritative newer 当前不创建 upload route。
- UI display state 只能由 `ObjectProjection` 读取 core facts 后生成，不能反向驱动 sync / upload；当前 UI 还没有切换到 canonical object projection。

Canonical fallback 语义：

- fallback 是强诊断，不是静默降级。任一端缺 canonical manifest、schema 不兼容、manifest hash 无效、capability 不满足或 planner 抛错时，本 tick 使用 legacy plan，并记录 `canonicalPlanFallback`。
- fallback 诊断必须包含 reason、legacy fallback used、trigger、nodeRole、recording count 和 canonical object count；reason 使用 `localCanonicalManifestMissing`、`peerCanonicalManifestMissing`、`canonicalSchemaUnsupported`、`canonicalManifestValidationFailed`、`canonicalCapabilityMissing`、`canonicalPlannerFailed` 等分类。
- shadow/planner 诊断必须能看到 metadata hash 收敛、createdAt 被 hash 排除、processing state 不参与 modifiedAt/hash、Mac 处理时钟被拒绝、业务 modifiedAt 被用于方向判断，以及 audio bootstrap/no-op/deferred/conflict。

下一阶段仍应保持分阶段：先用真实设备验证 Canonical Kernel Completion v1 的 metadata/no-op/audio bootstrap/generated artifact download/folder/study item metadata bridge 行为稳定；production ports/dry-run report 只能作为迁移设计输入。真正迁移需要单独审计、人工批准、root-bound production adapter、shadow migration、rollback 和真实设备验证。迁移完成前，不要把 UI、retry、Mac pending sync 或旧 `RecordingMetadata` vs `StudyItemMetadata` diff 继续作为补丁主战场，也不要把 dry-run 等价或 port declared 解读为 runtime switch 许可。

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
- Mac TLS private key 当前保存在 app-local security directory 的 `tls-private-key.json`，TLS certificate 保存为 `tls-certificate.der`；源码再通过 `SecIdentityCreate(nil, certificate, privateKey)` 创建 Network.framework 使用的 identity。旧文档曾写 Data Protection Keychain，与当前源码不符。
- Mac sandbox entitlements 包含 network client/server、user-selected executable/read-only 和 app-scope bookmarks。
- whisper.cpp/ffmpeg/model 访问依赖安全范围书签或 bundle helper。

## 当前架构风险与不确定点

- iPhone 与 Mac 有部分同名模型/store 源码但内容不同，例如 `StudyLibrarySyncModels.swift`、`ConnectionSyncStateStores.swift`、`RecordingTitleEditing.swift`。修改协议或数据结构时必须双端审查。
- Git-backed study sync 默认禁用，但代码和测试仍存在；不要误以为本地网络同步和 Git-backed sync 是同一套开关。
- Mac build phase 依赖仓库外本地 whisper.cpp 编译产物或 `WHISPER_CPP_ROOT`；新机器/CI 可复现性需要确认。
- `TranscriptionQueue` 目前只是占位状态对象，真实转写由 `TranscriptionCoordinator` 执行。
- retry drainer、Mac pending sync 超时/ack 以及 checksum cache 已有单元测试覆盖，但 Mac 点击同步到 iPhone 前台执行 tick 的完整真机链路仍需手动验证。
- UI 测试覆盖很轻，核心保障主要来自 Swift Testing 单元测试。
- `RokuricsVisualDiagnostics/` 和顶层图标源的维护策略需要人工确认。

## 2026-07-10 连接到内容完成的生产状态机

生产链路的完成关系现在是：

1. **连接**：TLS fingerprint pinning + 两阶段 pairing credential commit + HMAC/nonce request verification；heartbeat 成功独立建立 online evidence。
2. **同步控制面**：双方交换 inventory、manifest、object metadata、hash/size、tombstone、ledger/status facts；status delta 需要显式 ACK，Mac manual sync-start 需要匹配 runID ACK。
3. **metadata 应用**：双端等待全部必需 apply domain 完成；conflict、blocked、rollback failure、rejected/failed change 都使本轮失败。
4. **内容执行**：iPhone→Mac 通过现有 recording upload coordinator 或 artifact put；Mac→iPhone 仍由 iPhone 主动 artifact request/pull。recording audio 不自动从 Mac 下载到 iPhone。
5. **最终确认**：artifact 必须取得 server final apply/complete 证明；audio 必须由既有上传协议完成；所有 remaining transfer 为空后才能记录完整成功。

关键持久化身份：

- pairing：pending credential + confirmation token；提交后为 paired device credential。
- sync-start：`deviceID + syncRunID`，持久到 ACK/timeout。
- status exchange：`senderNodeID + sourceIncarnationID + sequence`。
- recording upload job：`recordingID + targetDeviceID`；target 改变会重建 job。
- artifact resume：`artifactID + checksum + size`，不能仅以 artifactID/offset 证明版本。

地址层优先使用稳定 `.local` hostname 和 Bonjour advertisement；数字 IPv4 是配对 payload 的 fallback，不再是唯一长期 endpoint。Release production owner 保持 old kernel；Debug canonical mode 必须有显式 stored configuration 和人工确认。

HTTPS listener 的候选端口初始由 `MacAppStorageProfile.receiverPort` 提供；该值优先读取当前 app profile 已持久化的动态端口。若绑定明确以 `EADDRINUSE` 失败，`SecureReceiverService` 释放失败 server、将候选端口加一、持久化并等待下一次用户点击；其他错误不移动端口。配对码和可复制 payload 只能在 listener ready 后发布，因此 payload 的 port 与真实 listener active port 相同。iPhone 不发现或猜测端口，而是读取 Mac 复制文本中的 `Port:` 并持久化到 paired connection snapshot。

## 2026-07-11 稳定业务等价、隔离执行与状态收敛架构

### V2 业务等价与业务时钟

`RokuricsShared/SyncCore/LocalNetworkBusinessSignatureV2.swift` 定义跨 iPhone/Mac 共用的中性 projection、规范化规则和 hash envelope。两端模型先映射为相同 projection，再以 sorted-key JSON 和 SHA256 生成带 `ln-business-v2:` 前缀的签名。文本做 Unicode NFC/trim，tag namespace/value 归一为小写，tag 去重排序；本机文件路径、duration/处理/上传/冲突状态、时间戳和派生 membership 不属于业务身份。custom properties 只有明确列入 `explicitBusinessCustomPropertyKeys` 的 key 才能进入签名和 merge；当前白名单为空。

同步因此维护三类互不替代的事实：

1. V2 business signature：判断跨设备业务内容是否等价。
2. 持久 `updatedAt`/canonical `modifiedAt`：决定相同对象的业务先后和 apply 方向。
3. receive、processing、upload、UI、retry 等 runtime state：只描述本机执行状态，不改变前两者。

merge 只覆盖 peer business fields，并保留本机路径、duration、processing 状态、note sections、source description、conflict state、本机 custom keys 和可重建 membership。tag 能匹配时保留本机 id/createdAt。canonical adapter 的业务时间来自持久对象或 deletion 事实，而不是接收/处理时刻；wire timestamp 在构造和解码时统一向下截断到整秒，使 ISO8601 round-trip 后 manifest hash 仍稳定。

### Action-scoped 执行与冲突隔离

planner 仍可从完整 inventory/manifest 形成全局差异，但执行前会按本轮 action ID 裁剪 manifest，并扩展必要的 item↔recording 关系。metadata apply/upload 只发送对应 object、tombstone、pending upload 与 recording facts；不存在所需 payload 时抛错。该边界防止一个小范围动作把无关对象或并发更新重新提交给 peer。

执行计划以冲突依赖图隔离对象：artifact conflict 会阻塞 owner recording，item conflict 会阻塞其 recording，recording conflict 会阻塞关联 item，folder conflict 会阻塞成员 item/recording。隔离后的无关 metadata、artifact、audio 动作可先完成；但原始 `conflictActions` 继续参与最终判定，所以本轮不会因安全动作成功而伪装成完整成功。

### Recording existence 与内容证明

`CanonicalRecordingExistenceTruth` 把 parent tombstone、peer knowledge 和 audio proof 分开建模。tombstone 优先级最高并阻止 resurrection；peer unknown 保持 deferred；metadata-only、receive/index 记录、study item 和 completed ledger 只证明对象或历史流程存在，不证明 peer 持有字节。只有同 recording 的 hash+byte-size 匹配、finalize proof 等内容级事实才能产生 `audioSameNoOp`；hash/size 不同为 conflict，本机有真实音频且 peer 无内容证明时形成 upload candidate。

### syncRunID 代际与 heartbeat 收敛

双端 connection sync state store 以当前 active runID 为写入门槛，并保留最多 32 个 superseded runID。新的 beginning phase 可以取代未完成旧轮；同轮倒退、旧轮迟到进度以及旧轮终态都被拒绝。iPhone heartbeat 携带当前 `LocalNetworkSyncRunStatus`，Mac 通过同一 run-aware store 消费进度/completed/failed；这条旁路用于修复终态 response 或 ACK 丢失后的状态收敛，不把 heartbeat presence 提升为同步成功。

### 诊断背压

`CanonicalAsyncDiagnosticsWriter` 在同一有序队列中支持 normal/critical priority。error-bearing 事件和 sync run/tick、upload/finalize、metadata apply 的终态被归类为 critical；队列饱和时 critical 可驱逐最早 normal，normal 不可驱逐 critical。序列化 tail task 保留接受顺序，所有事件仍先经过原有字段约束和敏感信息 redaction。

### Durable sync-start queue 与 ACK 边界

iPhone 的 coordinator consumer 与 app-service consumer 各自拥有独立磁盘队列，状态为 pending/in-flight/completed。enqueue 只有在原子写成功后才可对 Mac ACK；写失败同时回滚内存，heartbeat 也不能代替 ACK。重启时未完成 in-flight 被保守放回队首，completed/lifetime dedupe 防止同一信号被当前生命周期重复执行。这个队列解决“Mac 已删 pending，但 iPhone 尚未真正接管 run”的空窗。

### Metadata apply lease 与 terminal ownership

Mac 在 metadata apply 开始时取得 run-scoped lease，lease 存续期间 watchdog 不得把长 apply 判为 stalled；结束时刷新 activity timestamp 后再恢复 watchdog。同一 active run 的 terminal state first-write-wins；superseded run、非 active run 和 terminal 后的倒退更新都被拒绝。这样 inventory、apply、heartbeat 和超时监督共享同一个 run generation，而不是相互覆盖。

### Receiver-local marker 与真实对象身份

`syncedMetadataOnly` 不属于跨端业务模型，而是接收端对“仅收到 metadata”的本地收据。business merge 先比较业务字段，再在接收端保留/清理本机 marker。Pending recording upload 的 owner 是真实 StudyItem；builder 必须通过 recording relation 找回 itemID，不能因常见的一对一数据而假设 `itemID == recordingID`。

### Upload session 的内容合同

resumable session 绑定 checksum、byte size 和目标 peer。客户端发现内容合同变化时废弃旧 offset/session 并创建新 session；服务端不得用旧完整临时文件代替 final apply ACK。损坏 ledger 作为可诊断的派生状态处理，不能让仍存在的 recording 和文件永久失去上传机会。
