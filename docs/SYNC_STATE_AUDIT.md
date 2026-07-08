# SYNC_STATE_AUDIT

## 2026-07-08 Rokurics v10.0 / Mac 本地录音对同步状态机影响审计

审计结论：当前保留的 v10.0 改动不改变同步状态机、上传状态机或 Mac receiver route。Mac 首页只新增本地录音入口；`MacRecordingManager` 只写 Mac 本机 inbox 和 transcript store，不创建 iPhone upload job，不修改 heartbeat、manual sync ack、retry drainer、inventory response、metadata/artifact apply、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain 或 pairing。

Mac 本地录音保存路径继续复用现有 inbox 语义：metadata 先写入 `MacRecordingFileStore.saveMetadata`，audio 经 `temporaryAudioUploadURL`、`checksumForTemporaryAudioUpload`、`saveAudio(temporaryFileURL:)` 落入受约束的 audio inbox。保存后的 receive record/transcription status 可被现有 Mac 学习库、转写、笔记和聊天链路读取，但它不是 peer audio proof，也不代表 iPhone 已同步。

iPhone 侧实时转写显示只属于录音界面 UI。共享模拟 session 不写 `RecordingMetadata`、不写 transcript artifact、不写 sync proof、不触发 upload/sync/apply/read runtime。此前 no-legacy fallback / canonical runtime 行为收窄已恢复到 v9.24，不属于当前同步状态机事实。

## 2026-06-18 Canonical v9.17 / Real Path State Fix 审计结论

审计结论：本轮只修 objectID/display cache/pending UI 三个真实路径断点。未新增 route，未修改 upload route schema，未绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash，未新增 Mac -> iPhone 反向连接，未新增 CanonicalFourDomain/Evidence/Gate/Scorecard/RuntimeHarness/Fake 脚手架，未做 legacy retirement。

ObjectID 状态机：录音音频的 UI key、upload decision key、transfer runtime key、iPhone finalize proof key、Mac finalize proof key、status exchange fact key 与 EffectiveStatus dictionary key 均以 `recordingAudio:<recordingID>` 为 canonical objectID。`IPhoneCanonicalTransferAdapter` 只在调用 existing secure upload route 时把 canonical objectID 转回裸 recordingID，避免改变 route contract。

Status truth -> upload UI：`StudyLibrarySyncCoordinator` 在 fact produce 与 status exchange/inventory delta consume 后桥接 truth projection 到 `StudyLibraryStore` 和 `RecordingUploadCoordinator`。桥接只复制 snapshot，不启动 upload，不从 View getter 触发 actor reconciliation。finalizeProof/peer hash-size proof 可显示 completed/peerVerified；metadataOnly、partialReceive、completed ledger only、peerUnknown 和 status ack alone 不显示 completed；existing different audio 仍 conflict/no-overwrite。

上传按钮 no-op：`RecordingUploadCoordinator` 对 decision early return 和 active upload skip 发布 canonical display state/progress diagnostic。blocked/failed/deferred/retry/finalizing/uploading 均可被 UI 观察；`view refresh` 和其他不能创建 upload job 的 trigger 仍不会创建 job。canonical transfer production port unavailable、finalize proof rejected、conflict 与 failed diagnostics 使用 canonical audio objectID。

Mac 手动同步：`SecureReceiverService.prepareManualStudyLibrarySync` 在 pending request 创建后立即发布 service revision；`MacIPhoneConnectionView` 消费返回状态 revision。生命周期仍由 `DeviceConnectionStatusStore` 管理：requested -> duplicate waiting -> heartbeat consumed -> inventory observed/in progress -> timeout/stale。Mac 继续只作为 HTTPS server 等待 iPhone heartbeat/inventory，不反连 iPhone。

证据边界：本轮仍是 local code/test evidence。`realDeviceEvidencePresent=false`；没有 paired iPhone/Mac redacted jsonl 时，不得声明真机状态收敛或 canonical full sync release readiness。

## 2026-06-17 Canonical v9.15 / R6-R7 Prove-or-Fix 审计结论

审计口径：本轮只以代码路径、grep 和 targeted tests 判断 R6/R7。旧 v9.10-v9.13 文档中的 READY、harness 或 fake/evidence scaffold 记录只能作为历史 code-level 说明；不得恢复已删除/未跟踪的 `CanonicalFourDomain*`、fake harness、Evidence package、CompletionGate/FinalScorecard/RealDeviceTrialGate 文件来证明 R7。

R6 Connection：真实 app path 已存在。iPhone `StudyLibrarySyncCoordinator`/heartbeat monitor 使用 `CanonicalConnectionRuntime` 生成/消费 heartbeat、syncRequested、status request 和 status exchange carrier；Mac `SecureReceiverService` 创建 runtime 并传给 `SecureLocalHTTPSServer`，server 只在既有 verified request/response path 内记录 inbound liveness 与 status/sync request。`canonicalDecisionOnly` 与 `canonicalApplyNoAudio` 现在映射 diagnostics-only connection carrier；`oldKernel` 仍 disabled；`canonicalFullSync` 才进入 connection owner with legacy fallback。heartbeat/status callback 只 enqueue existing work，不 inline inventory/apply/upload/file scan/hash/diagnostics sync write。Mac 仍不主动连接 iPhone。

R6 Transfer：真实 app path 已存在。`RecordingUploadCoordinator` 在 allowed `canonicalFullSync` 下进入 `CanonicalTransferRuntime`，然后通过 `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient`/`RecordingUploadClient` 复用 existing upload start/status/chunk/finalize routes。`RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、route path 和 upload schema 未改变。Mac finalize route 只在 response completed 且 checksum/byteSize 匹配后产生 receiver accepted `CanonicalTransferFinalizeProof`，再写入 `CanonicalStatusTruthRuntime`。partial receive、metadataOnly、completed ledger alone 和 receive record alone 仍不是 completed/peer proof；existing different audio 仍 conflict/no-overwrite。

R7 Final Gate：现有 `CanonicalRealDeviceTrialReadinessGate` 增加 v9.15 fail-closed gate，READY 值为 `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`。Gate 逐项检查 R1-R7、fake/testOnly production transfer port、finalize proof -> StatusTruth、route/security/RequestVerifier、Mac reverse topology、heartbeat inline heavy sync、view refresh upload job、retry drainer fresh job、soft peer-proof misuse、default/release oldKernel、legacy fallback、no legacy retirement、MainActor hot path 和 build/test summary。缺 R1-R7 或 build/test summary 返回 NOT_READY；fake/testOnly production transfer、route/security bypass、default/release canonical、missing legacy fallback、Mac reverse connection、heartbeat heavy sync、view refresh upload job、retry fresh job、soft peer-proof misuse、MainActor hot path 或 legacy retirement attempt 返回 UNSAFE。

验证状态：`git diff --check` 通过；no-new-scaffold grep 为空；macOS targeted tests 通过。iOS targeted tests 编译成功后未进入断言，失败于 simulator 启动基础设施：`Timed out trying to boot simulator after waiting 60.00s`。因此 v9.15 本轮最终状态为 `NOT_READY`，不得建议进入 `canonicalFullSync` 真机 trial。

证据边界：`realDeviceEvidencePresent=false`。`READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL` 即使在未来本地 targeted tests 全绿时，也只表示 paired-device DEBUG/internal app trial readiness；不是 release-ready，不是真机已通过，不是 legacy-retirement-ready。default/release 必须保持 `oldKernel`，legacy fallback 必须保留，本轮没有 route/security/schema/topology 变更，没有 legacy retirement。

## 2026-06-16 Canonical v9.13 / Post-audit Real Wiring 审计口径

v9.10 post-audit found R4/R6/R3 evidence incomplete. 旧 v9.10/v9.12 READY/closure 语句只代表本地 code-level gate 或 harness 结果，不代表 canonical 内核完成、可发布、真机已通过或可退休 legacy。

v9.13 closes code-level R4/R6/R3 only if tests/grep pass. UI final display state 必须追溯到 cached `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` snapshot；Connection/Transfer owner 必须是真实 app path 且只在允许的 `canonicalFullSync` commit；UI read、Store getter、View refresh 不得触发 status reconciliation、diagnostics sync write、manifest build、full hash、upload job 或 retry drain。

`realDeviceEvidencePresent=false`。没有 paired iPhone/Mac redacted jsonl 时，不得声明真机 no-freeze、状态收敛或 legacy retirement readiness。

## 2026-06-16 Canonical v9.12 / R6 Connection-Transfer Owner 与 R7 Final Gate 审计结论

审计结论：v9.12 不改变连接拓扑、heartbeat interval、route path、upload route schema、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、default/release oldKernel 或 legacy fallback。它只把 R6/R7 缺口从“报告说明”收口到 code-level gate/harness/tests：Connection/Transfer runtime owner 有真实 app path 引用，final gate 能逐项 fail closed。

Connection 状态机审计：`CanonicalConnectionRuntime` 由 iPhone `StudyLibrarySyncCoordinator` 与 Mac `SecureReceiverService`/`SecureLocalHTTPSServer` 使用。它记录 peer liveness、heartbeat envelope、status request、syncRequested envelope、status exchange carrier 与 capability summary。`syncRequested`/status request 只产生 enqueue action；不得 inline inventory、apply、upload、file tree scan、manifest build、full hash 或 diagnostics JSONL write。Mac 不主动连接 iPhone。

Transfer 状态机审计：`RecordingUploadCoordinator` 在 `canonicalFullSync` allowed 且 production port injection 允许 audio upload 时进入 `CanonicalTransferRuntime`。runtime owns session start、status refresh、chunk、confirmedBytes、resume、retry/backoff、finalize、finalize proof；真实上传仍走 `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient` -> Mac existing upload routes。chunk send failure 会先 status refresh，若 receiver confirmedBytes 前进则 resume，否则 fail closed。

Mac 接收审计：`SecureLocalHTTPSServer` existing upload handlers 仍先通过 verifier/security path，再交给 `MacRecordingFileStore`。finalize proof 只能在 response completed 且 checksum/byteSize 匹配后进入 StatusTruth；partial receive、completed ledger alone、metadataOnly 和 receive record alone 不 completed。existing different audio 仍 conflict/no-overwrite。

fake/test-only 审计：旧 in-memory upload ledger 已改为 `testOnly` port。它只可被 tests 或 explicit migration harness port set 构造；production fullSync upload path 不选择它。`fakeLedger` token 不再存在；若 evidence 发现 production fullSync selected test-only upload port，final gate unsafe，不得 READY。

Final gate 审计：`CanonicalFourDomainGateEvidence` 现在表达 Connection、Transfer、Sync、File 与 cross-domain 总表核心行。缺 connection runtime app reference、heartbeat/liveness/syncRequested、status exchange carrier、transfer runtime app reference、retry runtime、secure upload path、finalize proof -> StatusTruth、retry existing-only、UI EffectiveStatus、read cache、diagnostics async writer、file hot-path guard、kernel switch controls 或 no-retirement proof 均不得 READY。route/security/RequestVerifier bypass、Mac reverse connection、heartbeat heavy sync、view refresh upload job、retry storm、peer proof violation、MainActor hot path violation、diagnostics leak、test-only upload port selected、mode boundary violation 或 legacy retirement 进入 unsafe。

Harness 审计：deterministic two-node harness 仍不使用真实网络、不写 production root、不产生真机 evidence。它覆盖 metadataOnly + local audio transfer/finalize/proof/status exchange、peerUnknown deferred、completed ledger rejected、partial receive rejected、existing different audio no-overwrite、generated artifact status delta、cache hit、diagnostics storm async/backpressure、status exchange duplicate/stale/conflict 和完整 mode sequence。

证据状态：`realDeviceEvidencePresent=false` 仍是当前值。READY 只表示 code-level paired-device debug/internal trial readiness，不表示 real-device pass、production completion 或 legacy retirement。

## 2026-06-16 Canonical v9.11 / R4 UI EffectiveStatus 与 R3 No-Freeze 审计结论

审计结论：v9.11 不改变连接、上传、本地网络同步状态机、heartbeat、manual sync ack、retry drainer、inventory response、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、sync decision、apply runtime、read runtime、主开关 mode、default/release oldKernel 或 legacy fallback。它只把真实 UI/status model 的 final sync display 收口到 cached `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` snapshot，并补强 no-freeze/gate 反证。

Store snapshot 审计：iPhone/Mac `StudyLibraryStore`、iPhone `RecordingUploadCoordinator`、Mac `SecureReceiverService` 暴露只读 effective/display snapshot。getter 只读缓存字典；不得 await actor、merge facts、reconcile status、build manifest、full hash、读 ledger、写 diagnostics file、启动 sync/upload/retry drain 或访问 file/network IO。事实生产路径可以异步更新 snapshot，但 View read 不执行重活。

UI source 审计：iPhone recording library/detail/status action area 继续通过 `RecordingUploadCoordinator.displaySyncState(for:)` 取得状态；Mac study/audio inbox 的播放/转写可用性通过 `MacRecordingInboxItem.displayAudioAvailable` 取得。View 层不得直接从 upload ledger、receive record、metadataOnly、local file exists、partial receive、completed ledger 或 raw `hasAudio` 拼 completed/peerVerified/audioAvailable。

peer proof 审计：displayed complete/peerVerified/audioAvailable 只能来自 accepted finalizeProof、peerInventoryHashSizeMatch、same hash+same byteSize no-op proof，或 StatusTruth 验证的等价 proof chain。metadataOnly、metadataOnlyLedger、receiveRecordOnly、completed ledger alone、partialReceive、本地文件存在、expected manifest hash、peerUnknown、status ack alone 都不是 peer audio proof。existing different audio 仍为 conflict/no-overwrite，不覆盖、不强制上传。

no-freeze 审计：`CanonicalMainActorHotPathGuard` 覆盖 diagnosticsWrite、fileTreeSnapshot、manifestBuild、fullHash、readProjectionRebuild、statusTruthReconciliation、effectiveStatusProjection。UI read、Store getter、View refresh 的反证目标是 status reconciliation、diagnostics sync write、manifest build、full hash、upload job、retry drain 均为 0。R1 diagnostics async writer 与 R2 content-stable cache key 继续作为 gate evidence。

v9.10 gate 审计：trial gate/evidence/scorecard 现在要求 `uiEffectiveStatusBindingEvidence`、`viewLayerNoDirectPeerProofEvidence`、`noMainActorStatusReconciliationEvidence`、`noViewRefreshUploadJobEvidence`、`diagnosticsAsyncHotPathEvidence`、`contentStableCacheKeyEvidence`。缺 R4、缺 R3 no-freeze evidence、View 层直拼 completed 或 MainActor status reconciliation attempt 均不得 READY；安全违规进入 UNSAFE/NOT_READY。R1/R2/R5 green 但 R4 missing 仍不得 READY。

R6 审计：本轮未接管 CanonicalTransferRuntime owner 或 Connection Kernel owner，未把 `ownerApprovedCanonicalTransfer` 改 true，未重构 `SecureMacUploadClient`、upload route handler 或 heartbeat route，未新增 route 或协议空壳。R6 仍留给 v9.12。

## 2026-06-15 Canonical v9.10 / Four-Domain Real-Device Trial Gate 审计结论

审计结论：v9.10 不改变连接、上传、本地网络同步状态机、heartbeat、manual sync ack、retry drainer、inventory response、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、sync decision、apply runtime、upload runtime、read runtime、主开关 mode、default/release oldKernel 或 legacy fallback。它只新增 report-only trial gate、redacted evidence package、final scorecard、cleanup audit 和 no-retirement lock。

四域 gate 审计：`CanonicalFourDomainRealDeviceTrialGate.v910(...)` 只读取 v9.5-v9.9 evidence booleans、redacted evidence package、cleanup audit 与 no-retirement lock。READY 条件要求 diagnostics hot path async、content-stable cache、status truth off-main、UI EffectiveStatus source、realtime exchange、connection/transfer owner wiring、four-domain harness、default/release oldKernel、legacy fallback、route/security unchanged、RequestVerifier unchanged、Mac no reverse connection、heartbeat no heavy sync、view refresh no upload job、retry storm guard、diagnostics redacted、switch-back proof 和 build/test summary present。

状态机边界审计：heartbeat 仍只能携带 liveness/status/syncRequested/status envelope 并 enqueue existing work；不得 inline inventory/apply/upload/file scan/hash/diagnostics JSONL。UI refresh 仍不得创建 upload job；retry drainer 只能恢复 existing eligible job；Mac 仍不得主动连接 iPhone。

peer proof 审计：`metadataOnly`、completed ledger alone、receive record alone、partial receive、本地文件存在或 expected manifest hash 仍不是 peer audio proof。Evidence package 只统计 finalize proof count、metadataOnly/completed ledger/partial receive rejection count 和 peer proof unavailable count，不把 soft evidence 晋升为 completed/peerVerified/audioAvailable。

no-retirement 审计：v9.10 scorecard 必须输出 `legacyDeleted=false`、`legacyDisabled=false`、`retirementExecutionPerformed=false`、`readyToRetireLegacyReportOnly=false`。READY 不表示 legacy 可删除或禁用；legacy retirement 必须是未来独立项目，且需要真机证据和人工批准。

证据边界：本轮最多产生 local code/test/doc evidence。`realDeviceEvidencePresent=false` 是预期值；没有 paired iPhone/Mac redacted jsonl 时，不得声明 real-device validated、release/default canonical、canonical kernel complete 或 legacy retirement。

## 2026-06-13 Canonical v8.73 / Final App-State Readiness 审计结论

审计结论：v8.73 不改变同步状态机或传输拓扑，只在 v8.69-v8.72 代码级修复之上增加最终 readiness gate、双端 scorecard tests 和真机 runbook。连接方向仍是 iPhone client -> Mac HTTPS server；heartbeat 仍是 3 秒 liveness/status/hint carrier；真正同步仍走现有 scheduler/engine path，240 秒 periodic sync 保留为 fallback。

Claude 诊断项收敛审计：read cache 由双端 `StudyLibraryStore` effective projection cache 覆盖；Mac `/sync/inventory` 由 request-scoped off-main canonical snapshot 和 mode gating 覆盖；Mac manual sync 的 `syncRequested` 由 iPhone live heartbeat 解析并排队 immediate tick；新录音、metadata、generated artifact、tombstone/conflict、finalize、receive、transcription/note status 等本地事件由统一 event queue/status convergence path 覆盖。

final gate 审计：`CanonicalRealDeviceTrialReadinessGate.v873(...)` 只读取 evidence booleans 并输出 `CODE_COMPLETE_RESULT`。READY 条件要求 read cache、Mac inventory off-main、oldKernel canonical skip、`syncRequested` heartbeat、event-driven trigger、status convergence、storm protection、iOS/Mac build、targeted tests、default/release oldKernel、5 档主开关、`canonicalFullSync` gate、legacy fallback、route/security unchanged、switch-back proof driver、diagnostics redacted 和 runbook updated 同时满足。real-device evidence 只作为独立字段。

unsafe 审计：release/default canonical、legacy fallback missing、route/security/RequestVerifier bypass、unsafe production-root write、view refresh upload job、retry storm guard missing、metadataOnly/completed ledger/partial receive treated as audio proof、existing different audio overwrite risk、diagnostics leak、oldKernel switch-back failure、heartbeat heavy sync 或 Mac reverse connection 会返回 `UNSAFE_TO_TRY_ON_DEVICE`。

证据边界：本轮代码 gate 和 targeted tests 只能证明 code-level readiness。没有 paired iPhone/Mac redacted jsonl 时，real-device evidence 仍为 not run；不得把本地 build/test、simulator、fake clock、fixture root 或 realistic-root switch-back proof 当作 paired-device evidence。若 `CODE_COMPLETE_RESULT` 不是 `READY_FOR_REAL_DEVICE_APP_TRIAL`，不得上机切 `canonicalFullSync`。

## 2026-06-13 Canonical v8.72 / Event-Driven Sync Trigger and Status Convergence v1 审计结论

审计结论：v8.72 只改变重要本地事件如何进入 existing sync/status convergence scheduling。未改变连接拓扑、Mac server/client 方向、heartbeat 语义、240 秒 periodic fallback、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、sync decision、apply runtime、upload runtime、read runtime、主开关 mode、default/release oldKernel、legacy path 或 legacy fallback。

触发源审计：iPhone 新录音保存、recording title/filing metadata、upload status/finalize/retry、study library folder/item metadata、generated artifact availability、tombstone/conflict 和 app foreground pending changes 都 post `LocalNetworkSyncEventTrigger`。Mac receive/finalize、metadata-only apply observation、study library metadata、generated artifact、transcription/note status、tombstone/conflict、manual sync 和 foreground/server-start pending state 进入 Mac-local queue。

queue/debounce 审计：所有 iPhone 事件进入同一个 immediate queue，按 reason 聚合，短窗口 debounce，同类 duplicate coalesce，max frequency 限速，storm 超限记录 summary diagnostic。queue 只 schedule，不在事件 callback 内执行 heavy `performTick`。真正执行仍通过现有 scheduler/engine path；sync in-flight 时不重入，完成后若仍有 pending events，最多排一次 follow-up。

defer 审计：offline/disconnected/background/suspended 状态只记录 deferred reason 并等待下一次 online/foreground/startScheduler path flush，不忙等。240 秒 periodic sync 保留为最终 fallback；3 秒 heartbeat 仍不交换 inventory、不传文件，只能携带 `syncRequested` hint。

Mac 收敛审计：Mac 不主动连接 iPhone。Mac 事件需要 iPhone 拉取时，只设置 existing pending `syncRequested` hint 或更新 pending state；local-only 变化只刷新本地 projection/revision。`/sync/inventory`、receive.json、audio inbox semantics、route list、upload route 和 security verification 未改变。

status projection 审计：uploadStatus、receiveStatus、transcriptionStatus、noteStatus 变化后刷新本地 projection 并排队 status convergence。local UI status 不等于 peer proof；`metadataOnly`、completed ledger alone、partial receive 仍不是 audioAvailable/audio proof；finalize proof 才能推进 verified uploaded 状态。status refresh 不创建 upload job，不触发 transcription/note generation。

diagnostics 审计：新增/完善 `syncEventTriggerReceived`、`syncEventTriggerCoalesced`、`syncEventImmediateTickQueued/Started/Completed/Failed/Debounced/AlreadyRunning/DeferredOffline/DeferredBackground`、`syncEventFollowUpTickQueued`、`syncEventStormSuppressed`、`statusConvergenceRefreshRequested`、`statusConvergenceProjectionUpdated`、`statusConvergencePeerProofUnavailable`、`statusConvergenceFinalizeProofAccepted`、`statusConvergenceMetadataOnlyNotAudioAvailable`、`macSyncRequestedHintSetForEvent`、`macSyncRequestedHintConsumedAfterEvent`。metrics/count/duration 来自实际路径或 fake-clock tests，bounded/redacted。

证据状态：本轮是 local build/test evidence；没有 paired iPhone/Mac redacted jsonl 时，不得声明 real-device 状态收敛完成。下一轮 v8.73 建议增加真机观察 runbook 与 diagnostics gate。

## 2026-06-13 Canonical v8.71 / Live Heartbeat syncRequested 审计结论

审计结论：v8.71 只改变 `syncRequested` hint 在当前 live heartbeat path 的消费与排队。未改变连接拓扑、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、sync decision、apply runtime、upload runtime、read runtime、主开关 mode 语义、legacy fallback、240 秒 periodic sync 或 3 秒 heartbeat interval。

触发源审计：Mac 手动同步仍由 `SecureReceiverService.prepareManualStudyLibrarySync` 设置 pending，并显示“等待 iPhone 执行同步”。Mac 不主动连接 iPhone；pending 只通过现有 heartbeat/status response 的 `syncRequested`/start-signal hint 暴露给 iPhone。

iPhone heartbeat 审计：`StudyLibrarySyncCoordinator.performHeartbeat()` 现在从 `/device/status` response 解析 `syncRequested`。`syncRequested=false` 或旧 response 缺字段不排队；`syncRequested=true` 进入统一 helper。helper 不执行 heavy sync，只做 peer/online/background 判断、pending/running/debounce gate 和 async queue scheduling。

queue/debounce 审计：如果 sync tick 已运行，hint 只记录 pending/去重状态，不重入；如果已有 pending 或短 debounce 窗口内重复 hint，记录 deduped/debounced。排队 tick 尽快走现有 sync path，不等待 240 秒 timer，且仍遵守 oldKernel/canonicalShadow/canonicalDecisionOnly/canonicalApplyNoAudio/canonicalFullSync 的现有 kernel switch 和 gates。

Mac pending ack 审计：Mac `/device/status` 与 `/connection/heartbeat` 都可广告 pending `syncRequested`。当 iPhone 发起真正 `/sync/inventory` 并携带 matching `syncRunID` 时，Mac 记录 `manualSyncRequestedInventoryObserved`/`manualSyncRequestedConsumedByPeer` 并把 pending 状态推进到“iPhone 已开始同步”或清理对应 pending signal。未观察到 iPhone 请求时，pending 仍保持可观察。

diagnostics 审计：iPhone side 新增/完善 `heartbeatSyncRequestedHintReceived`、ignored/deferred、tick queued/already pending/already running/debounced、started/completed/failed。Mac side 新增/完善 pending set/advertised/consumed/inventory observed/cleared。metrics 中 count/duration/latency 来自真实路径或 fake-clock tests，bounded/redacted，不输出 request/response body、IP/host 之外的敏感内容、完整 hash/fingerprint、绝对路径、完整 metadata JSON、完整 transcript/note/summary/provider response、secret 或 raw audio。

剩余问题：v8.71 不做 new recording/status-change event-driven sync，不改变 240 秒周期，不声明状态最终收敛真机完成。v8.72 仍需处理更系统的 event-driven convergence。没有 paired-device redacted jsonl 时，不得声明真机状态收敛验证完成。

## 2026-06-12 Canonical v8.70 / Mac Server Inventory Off-Main + Kernel-Mode Build Gating 审计结论

审计结论：v8.70 只改变 Mac `/sync/inventory` 的 manifest/canonical facts 构建位置与 route-level mode gating。未改变连接、上传、本地网络同步状态机、heartbeat、manual sync ack、retry drainer、syncRequested、event-driven sync trigger、inventory response schema、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、sync decision、apply runtime、upload runtime、read runtime、主开关 mode 语义或 legacy fallback。

触发源审计：`SecureReceiverService` 解析 `CanonicalKernelSwitchResult.effectiveMode` 后传给 `SecureLocalHTTPSServer`。server 默认 mode 仍是 `oldKernel`，所以 release/default 和未注入 mode 的构造保持 legacy owner。该 mode 只用于 `/sync/inventory` canonical build/seam gating，不触发 heartbeat、syncRequested 或 event-driven sync。

oldKernel/blocked 审计：route 在 policy 层跳过 canonical recording/library/generated artifact/tombstoneConflict object 构建、canonical manifest 构建、canonical seam diagnostics、canonical apply/audio/read readiness。legacy inventory response 仍按 existing background manifest/facts input 构建，schema 和安全校验不变。diagnostics 只记录 skipped reason/count，不写敏感内容。

canonical modes 审计：`canonicalShadow`/`diagnosticsOnly` 允许 off-main shadow facts/no-commit diagnostics；`canonicalDecisionOnly` 只运行 decision 必需 seam；`canonicalApplyNoAudio` 运行 non-audio apply/existence 相关 seam 但跳过 audio upload commit/read seam；`canonicalFullSync` 构建 full canonical facts，但同一 request 只构建一次。

reuse/no-op 边界：`MacInventoryRequestBuildContext` 保存 request-scoped canonical snapshot。后续 seam 使用 shared snapshot，不得重复 adapter conversion、canonical manifest build、full scan/hash 或 Store/file 读取。snapshot 不跨 request 缓存可变 facts；checksum/runtime cache 仍按已有专门 cache 处理。

diagnostics 审计：新增/完善 `macInventoryRouteStarted/Completed`、`macInventoryManifestBuildStarted/Completed/OffMain`、`macInventoryCanonicalBuildSkippedBecauseOldKernel/Blocked`、`macInventoryCanonicalBuildStarted/Completed/OffMain/Reused`、`macInventoryCanonicalDuplicateBuildPrevented`、`macInventorySeamUsedSharedSnapshot`、`macInventoryMainActorManifestBuildAttempt`、`macInventoryMainActorCanonicalBuildAttempt`、`macInventoryMainActorHashAttempt`、`macInventoryMainActorScanAttempt`。metrics 覆盖 route/manifest/canonical durations、canonical object/artifact counts、skip/reuse/duplicate counts 和 MainActor attempt counts，均来自真实路径或 test fake clock。

剩余问题：v8.70 不处理 `syncRequested` 心跳接线、event-driven sync、legacy trigger/topology 或状态不收敛。v8.71/v8.72 仍需后续修复。没有真实 paired-device jsonl 时，不得声明 Mac 卡顿真机验证完成。

## 2026-06-12 Canonical v8.69 / Canonical Read Effective Projection Cache 审计结论

审计结论：v8.69 只改变 canonical read effective projection 的缓存策略。未改变连接、上传、本地网络同步状态机、heartbeat、manual sync ack、retry drainer、inventory response、`/sync/inventory`、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、sync decision、apply runtime、upload runtime、主开关 mode 语义或 legacy fallback。

cache key 审计：Store cache key 来自 read mode/source/fallback、canonicalReadServed、canonical snapshot source/generatedAt/object signatures、divergence summary、legacy backing revision；Mac 额外包含 hierarchy rule。相同 key 下 repeated access 只命中 cache，key 变化时一次性重建 projection。

iPhone read 审计：`effectiveStudyItems` / `effectiveStudyFolders` 在 canonical served 时返回 cached projection；folders 不再重复调用 item conversion。当前 iPhone 源码没有 `effectiveStudyTree` property，本轮不新增 tree read API。legacy/fallback/oldKernel 返回 legacy backing arrays。

Mac read 审计：`effectiveStudyItems` / `effectiveStudyFolders` / `effectiveStudyTree` 在 canonical served 时来自同一 cached projection；tree 不再通过属性链重复 conversion。default `tree()` 使用 cached effective tree；oldKernel/fallback/read failure 继续使用 stored legacy `studyTree`。

no-op 边界：read access 不触发 sync/upload/download/retry drainer，不创建 upload job，不做文件 IO/网络 IO，不改变 `/sync/inventory` response，不改变 `receive.json`、audio inbox、pending sync、transcription/note generation，不 mutate Store backing arrays；只更新 private cache/metrics diagnostics。

diagnostics 审计：新增 `canonicalReadEffectiveCacheHit/Miss/Invalidated/Rebuilt/TreeRebuilt/FallbackLegacy/RepeatedAccessAvoidedRebuild/RebuildDurationMs`，count/duration 来自真实路径，bounded/redacted，不输出完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response 或 raw audio bytes。

剩余问题：v8.69 不处理 Mac server inventory off-main、syncRequested heartbeat、legacy trigger/topology 或状态不收敛。v8.70/v8.71/v8.72 仍需后续修复。没有真实 paired-device jsonl 时，不得声明卡顿真机验证完成。

## 2026-06-12 Canonical v8.68 / T7 Single Kernel Switch UI + Final Code Completion Gate 审计结论

审计结论：v8.68 只收口设置 UI 与最终 code-completion/manual switch gate。连接、上传、本地网络同步状态机、heartbeat、manual sync ack、retry drainer、inventory response、`/sync/inventory`、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、read/apply/upload runtime 业务实现和 legacy fallback 均不改变。

触发源：只有 DEBUG/internal Settings 的 `Debug · 同步内核` 区 `内核模式` picker。用户可见 5 档为 `oldKernel`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`；默认/release/default 为 `oldKernel`。`canonicalFullSync` 选择会先进入确认弹窗，确认前不会持久化 fullSync confirmation。

mode 边界：`oldKernel` 全部回 legacy/nil；`canonicalShadow` 不写、不上传、不 serve canonical read；`canonicalDecisionOnly` 不 apply/upload/serve canonical read；`canonicalApplyNoAudio` 禁止 canonical audio upload；`canonicalFullSync` 仍只在 owner approval、manual confirmation、DEBUG/internal、readiness、legacy fallback、route/security unchanged、diagnostics redacted 和 switch-back proof gate 允许时映射 decision/read/apply/audio/existence。

旧开关审计：libraryMetadata debug pilot、productionRoot flag、read/apply/audio/existence override、UserDefaults debug key 和 test-only injection 只能降级、阻断或诊断，不能越过主开关提权。UI 文案将旧 pilot 标为高级限制/诊断；scorecard/tests 覆盖 no scattered switch bypass。

final gate 信号：`CanonicalSyncKernelCompletionScorecard.v868(...)` 输出 T1–T6、5 档 UI、fullSync confirmation、runtime mapping、oldKernel legacy mapping、legacy fallback、Path B transport、route/security、diagnostics redaction、switch-back proof driver、real-device evidence 和四态 `CanonicalSyncKernelCodeCompletionResult`。manual switch gate 输出 `allowedForRealDeviceTrial`、`blockedWithReasons`、`unsafeToTry`、`needsBuildValidation`、`needsSwitchBackProof`、`needsOwnerApproval`、`needsBackupAcknowledgement`。

证据状态：v8.68 代码 gate 可以给出 `READY_FOR_REAL_DEVICE_CANONICAL_SWITCH`，但该状态只表示可以拿 build 按 runbook 开始 paired-device trial。没有真实 iPhone/Mac paired jsonl 时，`realDeviceEvidencePresent=false`；不得把 simulator、本地 build/test、fixture root、fake clock 或 realistic-root proof 当作 paired-device evidence。

## 2026-06-12 Canonical v8.67 / T6 Debug Switch-Back Proof Driver 审计结论

审计结论：v8.67 只新增 Debug switch-back proof driver 调用路径和 redacted JSONL evidence writer。它不改变连接、上传、本地网络同步状态机、heartbeat、manual sync ack、retry drainer、inventory response、`/sync/inventory`、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、主开关 mode 语义、read/apply/upload runtime 或 legacy fallback。

driver 触发源：只有双端 Settings 的 `Debug · 同步内核` 区按钮“运行新旧内核切回证明”。按钮位于 `#if DEBUG`，运行时只读当前 app data root 作为 source root，并由 shared runner 创建 fresh system-temp clone。proof root 必须通过 `CanonicalSwitchBackRootSafetyGuard`；guard 拒绝 `/`、home、repo root、Documents/Application Support production root 与子路径、Desktop production root、未标记非 temp root 和 symlink-resolved dangerous root。

no-op 边界：driver 不自动切主开关，不触发 sync tick，不创建 upload job，不发送网络请求，不写业务域，不做 physical delete/permanent delete/tombstone GC，不覆盖 audio，不删除 legacy，不禁用 legacy fallback。Mac 侧不重启 `SecureLocalHTTPSServer`，不改变 `/sync/inventory` response、receiver route/security、`receive.json`、audio inbox、pending sync、transcription 或 note generation。

diagnostics/evidence 信号：新增 JSONL event family 为 `canonicalSwitchBackProofDriverStarted`、`canonicalSwitchBackProofDriverBlocked`、`canonicalSwitchBackProofDriverCompleted`、`canonicalSwitchBackProofRootRejected`、`canonicalSwitchBackProofCloneCreated`、`canonicalSwitchBackProofHarnessStarted`、`canonicalSwitchBackProofHarnessCompleted`、`canonicalSwitchBackProofEvidenceWritten`、`canonicalSwitchBackProofFailed` 和 `canonicalSwitchBackProofRealDeviceEvidenceMissing`。JSONL 只写 temp proof-run root，不写 source production root；字段只包含 timestamp、nodeRole、runID、status、rootKind、redactedRootToken、mode sequence summary、domain counts、crash point counts、blocker enums、evidenceKind、realDeviceEvidencePresent 和 relative evidence path。

证据状态：`evidenceKind=realisticRoot`，`realDeviceEvidencePresent=false`。没有 paired iPhone/Mac real-device jsonl 时，不得声明真机 switch-back proof 完成，也不得把 local build/test、simulator、fixture root、fake clock 或 realistic-root clone proof 当作 paired-device evidence。下一轮 v8.68 才做 T7：单一主开关 UI 收口和最终 code-completion gate。

## 2026-06-12 Canonical v8.66 / T4-T5 Executor and Port Injection + Gated Production-Root Write 审计结论

审计结论：v8.66 只改变 canonical production executor/port injection 与 production-root write gate。主开关 effective configuration 是 app path 唯一权限来源；libraryMetadata pilot、recording/generated/tombstone config、audioUpload runtime config、existence apply config、read/sync/apply runtime config、UserDefaults debug toggles 和 test-only injection 不能越过 master switch 提权。

iPhone 审计结论：`MacConnectionView`、`StudyLibrarySyncCoordinator`、`LocalNetworkSyncEngine` 在 construction/refresh path 调用 `IPhoneCanonicalProductionPortFactory`，按 mode 注入 recording/library/generated/tombstone cutover executor slots。`RecordingUploadCoordinator` 在构造 canonical audio executor 前额外检查 factory gate；`canonicalApplyNoAudio` 不创建 canonical upload job，`canonicalFullSync` allowed 才复用 existing secure upload path。

Mac 审计结论：`RokuricsMacApp`、`SecureReceiverService`、`SecureLocalHTTPSServer` 使用 `MacCanonicalProductionPortFactory` 注入 recording/library/generated/tombstone executor references、`canonicalRecordingExistenceApplyPort` 和 `MacAudioUploadCutoverExecutor` holder。`oldKernel` 下 existence port 为 nil；applyNoAudio/fullSync gate allowed 时 existence ledger 只写 metadata-only truth，不写 audio bytes、不创建 fake audio file。

production-root gate 审计结论：RealApplyPort production-root constructor 的 `allowProductionRootWrites=true` 只在 `canonicalFullSync` + DEBUG/internal + ownerApproved + manualConfirmation + legacy fallback + legacy-readable/readiness + route/security + root safety 全部满足时出现。否则 port nil/disabled/dry-run，diagnostics 记录 redacted blocker summary。release/default 仍 oldKernel/blocked。

route/security 审计结论：本轮未新增 route，未新增 upload route，未改 `/sync/inventory`、`/sync/apply-metadata`、audio start/status/chunk/finalize route behavior，未改 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain 或 `SecureMacUploadClient` 边界。metadataOnly、receiveRecordOnly 和 completed ledger alone 仍不是 audioAvailable/audio proof。

证据状态：新增/更新本地 tests 覆盖 factory/injection gates、specialized config bypass、route list 和 metadataOnly truth invariant。没有 paired iPhone/Mac 真机运行，没有 jsonl real-device evidence；不得声称真机 production-root write 或 audio upload 已验证。下一轮 v8.67 做 T6：切回证明 driver。

## 2026-06-12 Canonical v8.65 / T2-T3 Master Switch Read + recordingMetadata ReadSeam Runtime Wiring 审计结论

审计结论：v8.65 只改变 read runtime wiring。主开关 effective `readRuntimeConfiguration` 现在驱动 iPhone/Mac `StudyLibraryStore` read configuration，recordingMetadata ReadSideSeam 被 runtime adapter 真实调用。未改变 legacy diff/sync decision、canonical decision、apply plan、upload candidate、retry drainer、inventory response、route schema、upload route、`RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain 或 legacy fallback。

iPhone read 审计结论：`StudyLibrarySyncCoordinator` 与 `LocalNetworkSyncEngine` 在 master switch construction/refresh path 将 read config 传给 Store。`oldKernel`/disabled/blocked 清空 override 并回 legacy；`canonicalShadow` compare only；`canonicalDecisionOnly` 与 `canonicalApplyNoAudio` 不 serve canonical；`canonicalFullSync` gate allowed 时可传 guarded canonical read config。该路径不启动 sync、不创建 upload job、不写 Store backing data。

Mac read 审计结论：`RokuricsMacApp`、`SecureReceiverService` 和 `SecureLocalHTTPSServer` 在 service/server construction 与 refresh path 保留并传递 read config，server rebuild 不丢失 Store read config。不改变 `/sync/inventory` response、`receive.json`、audio inbox、pending sync、transcription/note generation、route/security 或 upload routes。

recordingMetadata ReadSeam 审计结论：`IPhoneCanonicalReadRuntimeAdapter` 调用 `IPhoneRecordingMetadataReadSideSeam`，`MacCanonicalReadRuntimeAdapter` 调用 `MacRecordingMetadataReadSideSeam`。ReadSideSeam 只产出 effective read projection；read failure、divergence、unsupported 或 missing evidence fallback legacy，diagnostics 保持 redacted。

specialized config 审计结论：libraryMetadata debug pilot、generatedArtifacts、tombstoneConflict、recordingMetadata、audioUpload、tests-only injection、UserDefaults debug switches 和旧 read override 只能进一步限制主开关，不能绕过 oldKernel/default、canonicalDecisionOnly、canonicalApplyNoAudio 或 canonicalFullSync gate。

证据状态：本轮补齐本地 build 与 targeted tests。没有 paired iPhone/Mac 真机运行，没有 jsonl real-device evidence；不得声称真机读切换验证完成。下一轮 v8.66 才处理 T4/T5：端口/执行器注入与 production-root gated write。

## 2026-06-12 Canonical v8.64 / T1 Inventory MainActor Residual Closure 审计结论

审计结论：v8.64 只收敛 inventory/runtime snapshot/sync manifest 构建路径的 MainActor 重活。未改变 legacy diff/sync decision、canonical decision、apply plan、upload candidate、retry drainer、read path、UI、route schema、upload route、`RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain 或 legacy fallback。

iPhone inventory 审计结论：`LocalNetworkSyncInventoryBuilder` 仍是非 `@MainActor` 轻量 struct，但全量 `loadAllMetadata`、`loadJobs`、study manifest facts、directory scan、metadataHash 与 SHA256 已通过 `LocalNetworkSyncInventoryBackgroundInput` 及 background builders 收集。`buildRuntimeSnapshot(...)` 不再直接调用 MainActor store 重活，也不在函数体内直接扫描目录或计算 metadata/artifact hash；checksum cache hit 继续跳过 SHA256。

sync manifest 审计结论：T1 路径中的 `makeSyncManifest` 主线程残留已改为 background snapshot -> pure build。`StudyLibraryStore.makeSyncManifestInBackground(...)` 只读取轻量 root 配置，实际 recordings load 和 `StudyLibrarySyncManifest` 构建在 background path 完成；legacy inventory build 也使用同一 immutable input。pure builder 不访问 Store、不做网络、不创建 upload job。

Mac inventory 审计结论：`SecureLocalHTTPSServer` 的 `/sync/inventory` response builder 现在消费 `MacLocalNetworkSyncInventoryBackgroundInput`，manifest facts、recording/folder/item metadata hashes、artifact scan/hash 均提前在 background path 生成；Mac T1 MainActor blocker 已清理。不改变 `/sync/inventory` schema，不改变 `RequestVerifier` 或 secure upload routes。

telemetry 审计结论：新增/保留的 diagnostics 覆盖 `inventoryBuildDurationMs`、`metadataLoadDurationMs`、`jobsLoadDurationMs`、`manifestBuildDurationMs`、`directoryScanDurationMs`、`hashDurationMs`、checksum cache hit/miss/stale、`hashComputedCount`、`hashSkippedByCacheHitCount`、MainActor metadata/jobs/manifest/hash/scan attempts、duplicate snapshot build 和 snapshot reuse。duration 来自真实 clock，count 来自 path/cache/detector；正常 0 不以 hardcoded success 代替。diagnostics 仍 redacted，不输出绝对路径、完整 hash、完整 metadata JSON、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response 或 raw audio bytes。

证据状态：本轮补齐本地 build 与 targeted tests。没有 paired iPhone/Mac 真机运行，没有 jsonl real-device evidence；不得声称真机卡顿验证完成。下一轮 v8.65 才处理 T2/T3：主开关驱动 read 与 recording ReadSeam 接入。

## 2026-06-12 Canonical v8.58 / recordingMetadata RealApplyPort + ReadSideSeam 审计结论

审计结论：v8.58 补齐 recordingMetadata 域四个承重文件：`IPhoneRecordingMetadataRealApplyPort.swift`、`MacRecordingMetadataRealApplyPort.swift`、`IPhoneRecordingMetadataReadSideSeam.swift`、`MacRecordingMetadataReadSideSeam.swift`。这些文件不能再由 NoCommit、Cutover、Shadow 或 Evidence 类型冒充。范围只限录音 title/name metadata、business modifiedAt、stable business metadataHash、root-bound metadata write/read、canonical-vs-legacy read comparison 和 legacy compatibility。

apply 审计结论：iPhone/Mac RealApplyPort 使用 root-bound metadata write，执行 atomic write、rollback checkpoint、postcondition verification 和 rollback verification。canonical 写入为 legacy-readable format，同时 canonical-readable；失败时 rollback/fallback，rollback failure 是 fatal blocker。iPhone 不写 audio/upload ledger/generated/standalone note；Mac 额外不写 `receive.json`、不写 audio inbox、不触发 transcription/note generation。

read 审计结论：iPhone/Mac ReadSideSeam 只在读侧做 gated projection 与 comparison。`oldKernel` 默认 legacy；`canonicalShadow` 与 `canonicalDecisionOnly` 只 diff；`canonicalApplyNoAudio` 可 diff 但不默认 serve canonical；`canonicalFullSync` 在 master gate allowed 且 diff clean 时可 serve canonical recording metadata projection。divergence、read failure、unsupported/missing evidence 或 release/default 均 fallback legacy。read 不触发 sync/upload/retry，不 mutate Store，不改 Mac inventory response、`receive.json` 或 audio inbox。

主开关审计结论：`CanonicalKernelSwitch` 仍是唯一入口，default/release 仍为 `oldKernel`；specialized recording metadata config 不得越过主开关。legacy fallback、legacy recording metadata path 和 switch-back no-migration 约束保留。连接安全未变：未新增 route，未改 TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain 或安全范围书签。

证据状态：本轮补齐本地 code/test/doc 证据，但未运行 paired iPhone/Mac 真机灰度，未产生 jsonl real-device evidence。缺真机证据时不得报告 real-device validated、release/default canonical 或 legacy retirement。

## 2026-06-11 Canonical v8.57 / P3-2 realistic switch-back audit

v8.57 把 switch-back audit 从 synthetic harness 推进到 realistic test-cloned root。当前新增证明只在 temp/test root 上运行，覆盖 oldKernel -> canonicalFullSync -> oldKernel -> canonicalFullSync 的 code-level reversibility；它不改变主开关 mode、sync/apply/read/upload ownership 语义，不新增 route，不改连接安全层。

审计结论：`CanonicalDomainSwitchBackMatrix` 覆盖五个业务域，`CanonicalKernelSwitchSequenceProof` 覆盖主开关顺序，`CanonicalCrashPoint` 覆盖 12 个 crash/restart 点，`CanonicalSwitchBackEvidenceExporter` 输出 redacted evidence 并把 real-device proof 标为 missing。legacy fallback、legacy-readable format、default/release oldKernel 和 canonicalFullSync debug/internal gate 均保留。

剩余证据：没有 paired iPhone/Mac real-device run；P4 仍需用真实设备证明 diagnostics、upload resume/finalize、read served/fallback、old->new->old->new 和 no-regression。缺真机 jsonl 时不得报告 real-device validated 或 legacy retirement。

最近审计日期：2026-06-12

## 2026-06-11 v8.56 / P3-1 Unified Master Kernel Switch Consolidation 审计结论

审计结论：`CanonicalKernelSwitch` 已存在并且是当前同步链路的主配置入口；v8.56 在不新增业务域、不改 route/security/upload/read 内容的前提下补齐 P3-1 contract/gate/report/diagnostics 与 advanced override 降权规则。主开关 mode 为 `oldKernel`、`diagnosticsOnly`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`、`blocked`。默认和 release/default 仍是 `oldKernel`。

mapping 审计结论：`oldKernel` 映射 sync/apply/existence/audio/read/libraryMetadata pilot 全 disabled；`diagnosticsOnly` 只启用 diagnostics mode；`canonicalShadow` 使用 noCommit/parallelCompare，不写、不上传、不 serve canonical read；`canonicalDecisionOnly` 只启用 sync primary decision；`canonicalApplyNoAudio` 启用 decision + non-audio apply/existence apply，audio/read disabled；`canonicalFullSync` 才启用 decision、non-audio apply、existence bridge、audio upload with legacy fallback 和 guarded read with legacy fallback。

gate/blocker 审计结论：`canonicalFullSync` 现在检查 debug/internal、manual confirmation、owner approval、legacy fallback、legacy read/write path、inventory/sync/apply/audio/read runtime readiness、recordingMetadata/libraryMetadata/generatedArtifacts/tombstoneConflict/audioUpload readiness、diagnostics redaction、route/security unchanged、safe production-root config、unresolved conflict、switch-back hard blocker 和 canonical-only disk-format blocker。任一 blocker 会把 effective mode 变成 `blocked`，不做 partial silent enable。

bypass 审计结论：advanced overrides 现在按能力等级校验，只允许降权或收窄；不能提升 sync/apply/existence/audio/read/libraryMetadata pilot 权限，不能关闭 fallback/redaction，不能启用 runtimeSwitch，不能扩大 enabled scopes/domains，不能让 libraryMetadata production-root pilot 越过 `oldKernel`。Mac app 启动路径改为向 `SecureReceiverService` 传 master effective libraryMetadata pilot config，避免旧 UserDefaults pilot 直接成为 receiver production owner。

diagnostics 审计结论：新增 `canonicalKernelSwitch*` diagnostic kind/report，只输出 mode、runtime mode、blocker enum、legacy fallback preserved 和 redacted summary。不得输出完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、transcript/note/summary/provider response、raw audio bytes 或 full local audio path。

证据状态：本轮新增/更新双端 `CanonicalKernelSwitchTests` 覆盖 mapping、fullSync gate、readiness/switch-back blocker、advanced override 降权和 libraryMetadata bypass blocker。没有 paired real-device evidence；v8.57/P3-2 仍需在 realistic library root 上验证 oldKernel -> canonicalFullSync -> oldKernel switch-back。

## 2026-06-11 v8.55 / P2-5 audioUpload Domain Readiness 审计结论

审计结论：`audioUpload` 的 canonical resumable commit executor、upload state truth/retry policy、read runtime audio status projection、legacy compatibility/switch-back proof 和 main switch plumbing 已存在；v8.55 补齐该域 contract/readStatus/ownership wrapper、runtime scope/diagnostics、kernel switch scope、scorecard 和双端 targeted tests。没有新增 route，没有改连接安全层，没有改 recordingMetadata/libraryMetadata/generatedArtifacts/tombstoneConflict。

proof/schema 审计结论：`CanonicalAudioUploadProofSchema.version` 是 `canonical-audio-upload-v1`。域字段是 recordingID/objectID、local audio existence/byteSize/hash prefix/safe token、peer existence/audio availability、proven peer byteSize/hash prefix、redacted session prefix、confirmedBytes、finalize proof、retry state 和 conflict state。完整路径、完整 hash、raw audio bytes、完整 metadata JSON、request/response body、secret、fingerprint、transcript/note/summary/provider 内容均被排除。

state/decision 审计结论：metadataOnly、receiveRecordOnly、studyItemOnly、completed ledger alone、expected manifest hash/size、partial receive 和 failed session 都不是 audio proof。peerUnknown deferred；same hash+same byteSize 才 no-op；different hash/size 或 existing different audio conflict/no-overwrite；uploadedVerified 只能来自 finalized proof 或 peer finalized same hash+byteSize。`CanonicalAudioUploadOwnershipPolicy` 在 peerUnknown/conflict/security failure 下不允许 fallback overwrite/bypass。

runtime/switch 审计结论：`CanonicalSyncRuntime` 默认 enabled scopes 包含 `audioUpload` 并输出 `canonicalAudioUploadDecision*` diagnostics。主开关下 `canonicalFullSync` 可启用 audioUpload decision scope 与 existing canonical upload runtime；`canonicalApplyNoAudio` 继续禁用 canonical audio owner；oldKernel/release/default 仍 legacy。read/status projection 增加 audioUpload readStatus，但 read/status 不创建 upload job、不 mutate Store。

security/redaction 审计结论：canonical commit 继续使用 `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` 和 Mac existing start/status/chunk/finalize handlers / `RequestVerifier`。TLS/HMAC/pinning/nonce/body hash 不变。新增 diagnostics 只允许 object/session prefix、state/reason、hash prefix、byte/offset/retry/count summary，不输出敏感内容。

证据状态：本轮 targeted tests 覆盖 contract/readStatus、peerUnknown no fallback overwrite、runtime scope/diagnostics、kernel switch mapping 和 scorecard report-only readiness。没有 paired real-device long-recording evidence；`realDeviceEvidencePresent=false`，manual switch trial 和 ready-to-retire 仍只能 report-only。

## 2026-06-11 v8.54 / P2-4 tombstoneConflict Domain Readiness 审计结论

审计结论：`tombstoneConflict` 的 canonical read projection、cutover executor、root-bound apply port、rollback/postcondition、anti-resurrection guard、legacy compatibility/switch-back proof 和 main switch plumbing 已存在；v8.54 补齐该域 contract 命名、hash schema、logical-time decision policy、runtime schema gate、domain diagnostics、scorecard 和双端 targeted tests。没有改 audio/upload/route/security/connection/generated artifact 内容/recordingMetadata/libraryMetadata 语义。

hash/schema 审计结论：`CanonicalTombstoneConflictHashSchema.version` 是 `canonical-tombstone-conflict-v1`。hash 输入是 stable tombstone/conflict business marker metadata：markerID、objectID、objectKind、markerKind、conflictKind、tombstoneState、displayState、businessModifiedAt、actorDeviceRole、parentObjectID 和 conflictResolutionState。delete target path、absolute/local/resource path、完整 metadata/content、standalone note 正文、generated artifact 内容、provider response、audio facts、upload/receive 状态、observedAt/receivedAt、UI-only state 和 diagnostics 均被排除。`CanonicalTombstoneConflictCandidate.markerHash` 已改为同一 schema 派生。

logical time / anti-resurrection 审计结论：canonical tombstoneConflict decision policy 使用 businessModifiedAt 或 logical event time。same hash 直接 no-op；local newer -> use local marker；peer newer -> apply peer marker；equal logical time + different hash -> deterministic conflict record/tie defer；missing logical time 或 schema mismatch -> fallback/block legacy。stale live resurrection 写 resurrection block record；restore、clear tombstone、physical delete、permanent delete 和 tombstone GC 都必须 blocked，不得把 absence/live record 当恢复证明。

decision/apply/read 审计结论：`CanonicalSyncRuntime` 在 enabled `tombstoneConflict` scope 下检查 local/peer tombstoneConflict schema，并输出 `canonicalTombstoneConflictDecision*` diagnostics。`CanonicalApplyRuntime` 仍通过既有 tombstone/conflict executor 写软 marker 或 conflict ledger，success-only duplicate suppression，不删除文件、不恢复对象、不自动 resolve conflict。`CanonicalReadRuntime` 增加 `canonicalTombstoneConflictRead*` diagnostics，read projection 只暴露 metadata 摘要并明确 read 不触发 delete/restore/GC。

redaction 审计结论：新增 diagnostics alias 只允许 mode/domain/objectID/marker kind/action/state/reason/count/hash prefix/logical time summary 等 redacted 信息。不得输出完整 metadata JSON、完整 hash、绝对路径、delete target path、fingerprint、request/response body、note/generated content、provider response、audio bytes、secret 或用户内容。

证据状态：本轮 targeted tests 覆盖 hash/path/UI/upload exclusion、candidate schema 统一、logical-time no-op/LWW/tie/missing fallback、unsafe delete/restore/GC blocker、anti-resurrection、runtime schema mismatch、read diagnostics 和 domain scorecard。没有 paired real-device evidence；`realDeviceEvidencePresent=false`，manual switch trial 和 ready-to-retire 仍只能 report-only。

## 2026-06-11 v8.53 / P2-3 generatedArtifacts Domain Readiness 审计结论

审计结论：`generatedArtifacts` 的 canonical planner、root-bound apply port、metadata-only read projection/source、legacy compatibility/switch-back proof 和 main switch plumbing 已存在；v8.53 补齐该域 contract 命名、hash schema、content-proof/modifiedAt decision policy、runtime schema gate、domain diagnostics、scorecard 和双端 targeted tests。没有改 audio/upload/route/security/connection/tombstone/recordingMetadata/libraryMetadata 语义。

hash/schema 审计结论：`CanonicalGeneratedArtifactHashSchema.version` 是 `canonical-generated-artifact-v1`。hash 输入是 stable generated artifact metadata：artifactID、recording objectID、kind、availability、contentHash algorithm/value、byteSize 和 businessModifiedAt。logical/local path、observedAt、producer node、provider request/response、transcript/note/summary 正文、diagnostics、audio bytes、upload/receive state、security material 和 tombstone 均被排除。

content proof / modifiedAt 审计结论：canonical generated artifact decision policy 先看 content proof。same contentHash + same byteSize 直接 no-op；缺 hash/size、availableWithoutHash、unknown/missing availability 或 unsupported kind/audio confusion 不可 apply。双方内容 proof 完整且内容不同后才使用 businessModifiedAt；local newer -> send local；peer newer -> apply peer；equal modifiedAt -> deterministic defer/conflict；missing modifiedAt 或 schema mismatch -> fallback/block legacy。

decision/apply/read 审计结论：`CanonicalSyncRuntime` 在 enabled `generatedArtifacts` scope 下检查 local/peer generated artifact schema，并输出 `canonicalGeneratedArtifactDecision*` diagnostics。`StudyLibrarySyncCoordinator` scoped primary plan 现在把 generated artifact download/no-op/defer/conflict 投影到 legacy-compatible diff actions，并把 artifact action 纳入 duplicate guard。`CanonicalApplyRuntime` 仍通过 root-bound generated artifact executor 写文件，`CanonicalReadRuntime` 增加 `canonicalGeneratedArtifactRead*` diagnostics 且 read projection metadata-only/content-excluded。

redaction 审计结论：新增 diagnostics alias 只允许 mode/domain/objectID/artifactID prefix/kind/action/state/reason/count/byteSize/hash prefix 等 redacted 信息。不得输出完整 transcript/note/summary/provider response、完整 artifact content、完整 hash、绝对路径、fingerprint、request/response body、audio bytes、secret 或用户内容。

证据状态：本轮 targeted tests 覆盖 hash/path/provider exclusion、content no-op、modifiedAt LWW/tie、missing content/modifiedAt blocker、schema mismatch、read diagnostics、duplicate guard 和 domain scorecard。没有 paired real-device evidence；`realDeviceEvidencePresent=false`，manual switch trial 和 ready-to-retire 仍只能 report-only。

## 2026-06-11 v8.52 / P2-2 libraryMetadata Domain Readiness 审计结论

审计结论：`libraryMetadata` canonical object、planner、apply runtime、read projection/source、Store effective read path、legacy compatibility/switch-back proof 和 main switch plumbing 已存在；v8.52 补齐该域 contract 命名、resource-token-free hash、modifiedAt decision policy、runtime schema gate、domain diagnostics、scorecard 和双端 targeted tests。没有改 audio/upload/route/security/connection/generated/tombstone/recordingMetadata 语义。

hash/schema 审计结论：`CanonicalLibraryMetadataHashSchema.version` 是 `canonical-library-metadata-v1`。hash 输入是 stable business library metadata：objectID/objectKind/title/itemKind/parent/filing/folder refs/tags/color/order/associatedRecordingID/deleted/businessModifiedAt。note full content、generated content、audio facts、local/resource path、logical resource tokens、upload/receive/sync state、diagnostics、provider response 和 security material 均被排除。旧 `CanonicalProjectionContract` study item payload 曾包含 `resourceTokens`，本轮改为 canonical business fields 后不再把资源路径变化当 metadata hash 变化。

modifiedAt/LWW 审计结论：canonical libraryMetadata decision policy 使用 businessModifiedAt。same hash 直接 no-op；local newer -> send local；peer newer -> apply peer；equal modifiedAt + different hash -> deterministic defer/conflict；missing modifiedAt 或 schema mismatch -> fallback/block legacy。该 policy 由 `CanonicalLibrarySyncPlanner` 调用，避免 planner 内 ad hoc 决策。

decision/apply/read 审计结论：`CanonicalSyncRuntime` 在 enabled `libraryMetadata` scope 下检查 local/peer library metadata schema，并输出 `canonicalLibraryMetadataDecision*` diagnostics。`CanonicalApplyRuntime` 的 libraryMetadata executor 仍是 root-bound metadata-only apply，不移动资源、不写 standalone note content、不碰 audio/upload/receive。`CanonicalReadRuntime` 增加 `canonicalLibraryMetadataRead*` diagnostics；iPhone/Mac Store effective folders/items 可在 guarded read served 时消费 canonical projection，默认和 fallback 仍读 legacy。

redaction 审计结论：新增 diagnostics alias 只允许 mode/domain/objectID/action/state/reason/count/hash prefix/modifiedAt summary 等 redacted 信息。不得输出完整 metadata JSON、完整 hash、绝对路径、fingerprint、request/response body、note full content、generated content、audio bytes 或 provider response。

证据状态：本轮 targeted tests 覆盖 hash exclusion、resource token/path no-hash-change、modifiedAt LWW/tie/schema mismatch、read diagnostics 和 domain scorecard。没有 paired real-device evidence；`realDeviceEvidencePresent=false`，manual switch trial 和 ready-to-retire 仍只能 report-only。

## 2026-06-11 v8.51 / P2-1 recordingMetadata Domain Readiness 审计结论

审计结论：`recordingMetadata` canonical adapter、execution shadow/cutover、root-bound metadata write、apply runtime、read runtime、legacy compatibility/switch-back proof 和 main switch plumbing 已存在；v8.51 只补该域 contract 命名、recordingMetadata 专属 diagnostics、Store effective read overlay、domain scorecard 视图和双端 targeted tests。没有改 audio/upload/route/security/connection/tombstone/generated/libraryMetadata 语义。

hash/schema 审计结论：`CanonicalRecordingMetadata.businessMetadataHashSchemaVersion` 是 `canonical-recording-business-metadata-v1`。hash 输入是 stable business metadata；createdAt、modifiedAt、duration 可作为 fact/decision/read projection 使用，但不进入 hash。upload progress、ledger、receive/observed/local path、audio hash/size、generated content、processing status 和 diagnostics 均被排除。iPhone adapter 与 Mac adapter 最终都落到同一 `CanonicalRecordingMetadata.metadataHash`。

modifiedAt/LWW 审计结论：canonical decision policy 使用 business modifiedAt。当前旧 iPhone model 没有独立 business modifiedAt，源码 adapter 的 createdAt/deletedAt fallback 是 documented compatibility fallback；runtime gate 仍可通过 `canonicalModifiedAtSemanticsAvailable=false` 阻断 primary。equal modifiedAt tie deterministic defer/conflict，不自动写。

decision/apply/read 审计结论：`CanonicalSyncRuntime` 可在 explicit debug/internal primary mode 下接管 recordingMetadata decision，并在 diagnostics/shadow/noCommit/blocked 时 fallback legacy。`CanonicalApplyRuntime` 的 recordingMetadata executor 通过 root-bound apply port 写 legacy-readable metadata，具备 atomic write、rollback checkpoint、postcondition 和 success-only duplicate suppression。`CanonicalReadRuntime` 可在 guarded canonicalFullSync 下 serve canonical recordingMetadata projection；iPhone/Mac Store effective read 已覆盖已有录音条目的 canonical title/tags/duration/deleted metadata，默认和 fallback 仍读 legacy。

redaction 审计结论：新增 diagnostics alias 包括 `canonicalRecordingMetadataDecision*` 与 `canonicalRecordingMetadataRead*`，只输出 mode/state/count/reason/hash prefix 等 redacted 信息。不得输出完整 metadata JSON、完整 hash、绝对路径、fingerprint、request/response body、audio bytes 或生成内容。

证据状态：本轮新增 iPhone/Mac targeted tests 覆盖 hash exclusion、business title hash change、upload/path/generated exclusion、modifiedAt LWW/tie/missing fallback、mode ownership、read diagnostics、Store effective projection、domain scorecard、legacy switch-back/crash readability。没有 paired real-device evidence；`realDeviceEvidencePresent=false`，`readyToRetireLegacy` 仅 report-only。

## 2026-06-11 v8.50 / P1-3 upload retry drain and state consistency 审计结论

v8.50 审计结论：当前源码已有 v8.48 metadata-only existence apply 与 v8.49 canonical audio upload commit executor，本轮没有重写两者，只补上传执行层状态真相、retry drainer policy、duplicate ownership guard 和 redacted diagnostics。`RecordingUploadCoordinator` 在 canonical executor 前会生成 `CanonicalUploadStateTruth` reconciliation/status projection diagnostics；真实上传仍进入既有 executor 和 legacy fallback 分支。

state truth 审计结论：audio truth source 必须同时看 local audio、canonical job store、legacy ledger、retry queue、peer inventory、peer metadata-only/receive-record-only/study-item-only、peer proven audio hash/byteSize、Mac partial/finalized receive、canonical existence ledger 与 tombstone/conflict。completed ledger alone、metadataOnly、receiveRecordOnly、studyItemOnly 和 expected manifest hash/size 都不是 audio proof；peerUnknown deferred；same hash+same byteSize 才 no-op；different hash/size conflict；finalize proof missing 时不得 mark uploaded。

retry drainer 审计结论：drainer 只能 resume existing eligible job，不能从 view refresh 或 unrelated fresh state 建 job。peerUnknown、missing local audio、tombstoned、different hash/size conflict、security failure、malformed ledger、backoff 未到、max retry 达到都必须 skip/fail closed，并输出对应 redacted diagnostics。stale interrupted session 需要先用 existing status route 刷新 confirmedBytes，再继续。

ownership 审计结论：`oldKernel` legacy-only；`diagnosticsOnly`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio` 不创建 canonical audio upload job；`canonicalFullSync` 只有 gate 允许时 canonical owner 可运行。canonical started/finalized proof accepted 后 suppress exact legacy fresh duplicate；canonical blocked before start 或 before peer data failure 可以 safe fallback；security failure/conflict 不允许 fallback 绕过安全或覆盖 existing different audio；legacy job running 时 canonical 不开 duplicate。

真实证据仍缺失：本轮没有 paired iPhone/Mac 真机中断上传、app restart、resume from confirmedBytes、finalize proof、metadataOnly not audio、peerUnknown deferred、different hash/size conflict、view refresh no-job 的 evidence。当前结论只能是 code/test/doc 层状态一致性补强。

## 2026-06-11 v8.49 / P1-2 audio upload commit executor 审计结论

当前源码已具备 canonical audio upload commit executor 等价实现，并已接入 `RecordingUploadCoordinator` 的 explicit canonical owner 分支。本轮审计以源码为准：v8.48 文档中“本轮不实现 canonical audio upload commit executor”仅描述 P1-1 范围，不再代表当前 v8.49 状态。

owner/gate 审计结论：default/release 必须 disabled 并使用 legacy upload coordinator。`diagnosticsOnly`/`noCommit` 不建 job、不发网络；`testTransportUpload` 只能 fake/test transport；`canonicalUploadWithLegacyFallback` 只允许 DEBUG/internal、owner-approved、legacy fallback enabled、existing secure upload route available 的配置。任一 blocker 都 fallback legacy；但 conflict/security failure 不得 fallback 成覆盖 different audio 或绕过安全。

transport 审计结论：canonical commit 没有新增 route。iPhone 端复用 `RecordingUploadClient` / `SecureMacUploadClient` resumable start/status/chunk/finalize；Mac 端复用 `SecureLocalHTTPSServer` existing route handlers 和 `RequestVerifier`。TLS pinning、HMAC、nonce、body hash、route allowlist 和 body verification 没有被绕过或替换。abort 没有 network route。

state machine 审计结论：session/chunk/finalize 状态可序列化并支持 restart resume。confirmedBytes 单调；chunk offset deterministic；duplicate chunk 只有同 offset/length/hash 可 idempotent；wrong offset 必须走 server status/resume 或 fail safe。finalize 缺 chunk、byteSize mismatch、hash mismatch 都不得 mark uploaded。

candidate/postcondition 审计结论：metadataOnly、receiveRecordOnly、studyItemOnly without audio 只可作为 upload candidate，不可作为 `audioAvailable`；completed ledger alone 不是 no-op；peerUnknown deferred；same hash+same byteSize 才 no-op；different hash/size 和 existing different Mac audio 必须 conflict/no-overwrite。upload ledger completed、retry job cleanup 和 legacy duplicate suppression 必须等 finalize proof。

仍缺真实证据：本轮没有 paired iPhone/Mac real-device run。真实完成必须用新录音或长录音证明 metadataOnly candidate -> session start -> chunk confirm/resume -> finalize proof -> Mac audioAvailable after finalize -> same hash+size no-op -> existing different audio conflict。

## 2026-06-11 v8.48 / P1-1 manifest.recordings apply consumption 审计结论

v8.48 / P1-1 修复“新文件不传 / peer 永远 absent”的第一个执行层缺口：Mac server apply path 现在消费 incoming `manifest.recordings`，把每条合法 recording fact 落为 canonical metadata-only existence record。该路径不依赖打开 `canonicalFullSync`，但不改变主开关语义；主开关仍只决定 canonical owner，不新增 route、不改 read path、不删除 legacy fallback。

存储选择是 `canonical ledger`，不是 legacy `receive.json`。原因：`receive.json` 是 Mac read/UI/audio inbox 输入，写 metadata-only receive record 有把 metadataOnly 误读成 audio exists 的风险。Canonical ledger 只服务 sync inventory existence fact，postcondition 固定 `audioAvailable=false`，并证明没有 audio file created、没有 upload completed ledger written。旧 manifest 没有 `recordings` 时行为保持 empty/no-op。

Mac inventory 合并 ledger 后，peer 侧会看到 recording exists 且 `audioAvailable=false`。无真实 audio file 时不得输出 audio path、proven contentHash 或 byteSize；manifest 中的 expected hash/size 只能作为 declared metadata。existing same audio hash+size 是 no-op；existing different hash/size 是 conflict/blocker，不覆盖；completed ledger alone 不是 audio proof；peerUnknown 继续 deferred。

iPhone handoff 仍通过 existing evaluator / legacy upload coordinator：local audio exists + peer metadataOnly/receiveRecordOnly/studyItemOnly -> upload candidate；local audio missing -> no candidate；view refresh 不建 job；retry drainer 不建 unrelated fresh job。本轮不实现 canonical audio upload commit executor，也不声明 canonical upload commit complete。

仍缺真实证据：没有 paired-device 新录音 run。最终验收必须在真机确认 `manifest.recordings` sent、Mac apply consumed、metadata-only ledger written、Mac inventory `audioAvailable=false`、iPhone peer metadataOnly candidate generated through existing path，以及 audio 是否经 legacy uploader 到达。

## 2026-06-11 v8.46 sync kernel completion 审计结论

v8.46 补齐两个实际同步缺口并暴露一个剩余 blocker。默认/release 同步状态机仍为 `oldKernel`；主开关、legacy fallback、upload route/security、Mac receive finalization、read fallback 和 legacy-readable data format 均未改变。

iPhone inventory 审计结论：local canonical inventory input 已从 MainActor store load path 移到 detached background URL/file IO path，避免 inventory hash/scan 阶段调用 MainActor-isolated `AudioFileStore.loadAllMetadata` 与 `RecordingUploadJobStore.loadJobs`。报告字段现在记录真实 `mainActorHashAttemptCount`、`mainActorScanAttemptCount`、blocked count、`metadataLoadDurationMs`、scan/hash duration 和 duplicate reuse。不得再用 fake zero event 证明 off-main。

Duplicate build 审计结论：同一 `syncRunID`/node/source 的 iPhone runtime build 由 actor cache 复用，第二次构建应报告 reused/duplicate count，而不是重新扫描/hash。该复用只影响 inventory runtime 构建成本，不改变 legacy diff/apply/upload/read owner。

Mac `manifest.recordings` apply 审计结论：只有显式 configured store 会把 manifest recordings 交给 canonical existence apply bridge，写入 metadata-only ledger；默认 store no-op。该 ledger 只能作为 existence fact，不能写 audio、不能写 legacy `receive.json`、不能标记 upload completed，且无 finalize proof 时必须 `audioAvailable=false`。

剩余 blocker：Mac inventory 仍在 `@MainActor` 方法内构建。v8.46 已删除 fake zero telemetry，并把 mainActor scan/hash attempt 与 blocked count 报告为 1；这说明问题被真实暴露，但尚未架构性迁移到 off-main。manual switch runbook 必须把该 blocker 作为 stop/manual review 条件。

真实证据仍缺失：没有 paired iPhone/Mac real-device runbook evidence，没有长录音真实 upload resume/finalize evidence。当前只能报告 targeted tests/builds 通过，不能报告 production completion、release default canonical 或 legacy retirement。

## 2026-06-08 sync kernel finalization 审计结论

本轮源码盘点后补齐三个主要缺口：read runtime 不再只停留在 adapter，而是进入 iPhone/Mac Store/UI effective read path；audio upload 不再只有 noCommit/shadow/model，而是由 `RecordingUploadCoordinator` 在 `canonicalFullSync` 显式允许时调用真实 canonical resumable executor；switch-back proof 从 synthetic harness 扩展到 test-cloned realistic root harness。默认/release 仍必须是 `oldKernel`。

主开关仍是唯一 owner 入口。`oldKernel` 关闭 canonical owner；`canonicalShadow` 只 shadow/no write；`canonicalDecisionOnly` 不 apply/upload/read canonical；`canonicalApplyNoAudio` 不启用 canonical audio upload；`canonicalFullSync` 才能启用 non-audio apply + audio upload + guarded read，并且必须保留 legacy fallback、manual confirmation、owner approval 和 switch-back proof。invalid mixed config 仍应 blocked。

音频上传审计边界未变：不新增 upload route，不改 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`；start/status/chunk/finalize 继续走 existing secure route。peerUnknown deferred；metadataOnly/receiveRecordOnly/studyItemOnly 只能形成 upload candidate，不能当 audioAvailable；same hash + same byteSize 才 no-op；different hash/size 或 existing different Mac audio 必须 conflict/block；completed ledger alone 不能当 no-op proof；view refresh 不得创建 fresh job；retry drainer 不得创建 unrelated fresh job。

Read runtime 审计边界：read path 不触发 sync/upload，不 mutate store，不移动资源，不输出完整 path/hash/content/provider response。Divergence > 0 或 canonical exception 必须 fallback legacy，并记录 `canonicalReadRuntime*` diagnostics。Store backing data 仍 legacy-readable，canonical effective projection 只在 gated mode 作为 read output。

仍未完成的真实证据：本轮没有执行 paired real-device manual switch runbook；unit tests、builds、realistic test root 都不是 real-device evidence。最终状态最多可报告 code-complete candidate / ready for real-device trial，不能报告 production completion、release default canonical 或 legacy retirement。

## 2026-06-07 v8.45 completion gate / manual switch 审计结论

v8.45 不改变同步状态机 owner，只在 v8.37-v8.44 之上增加 completion/readiness/manual-trial gate。默认/release 仍必须解析为 `oldKernel`，legacy planner、legacy store、legacy route、legacy read/write path、legacy fallback、retry drainer、Mac pending sync、upload route/security、`receive.json` 和 audio inbox 均保留。

Completion scorecard 覆盖十一项：inventory runtime complete、diff/LWW runtime complete、existence truth complete、non-audio apply runtime complete、audio upload runtime complete、read runtime complete、master switch complete、legacy compatibility proof complete、switch-back proof complete、diagnostics redacted、real-device evidence required。代码路径完成但缺真机日志时状态是 `codeCompleteNeedsDeviceEvidence`，不能升级为真实完成。

Domain ready-to-retire matrix 覆盖 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload` 和 `recordingExistence/sync engine`。每个域必须报告 write executor ready、read cutover ready、canonical runtime owner ready、legacy fallback ready、switch-back proven、diagnostics clean、real-device evidence present、readyToRetireLegacy 和 `retirementExecutionPerformed=false`。该报告只用于人工审计，不能执行 deletion、disable 或 fallback removal。

Manual switch gate 是手动 trial 前的硬边界。它要求 scorecard code complete、v8.44 compatibility proof、switch-back proof、default oldKernel、release oldKernel、all diagnostics redacted、legacy fallback available、no unresolved blockers、owner approval 和 manual backup acknowledged。Gate 通过只允许 DEBUG/internal paired-device manual trial；`releaseDefaultAllowed=false` 必须保持。

Evidence package 只允许 redacted counts 和 proof summaries：mode transitions、object counts、cache counts、plan used/fallback counts、apply success/failure、upload success/failure、read divergence、switch-back proof 和 redaction proof。不得包含绝对路径、完整 hash、secret/token、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response、generated content 或 audio bytes。

Runbook `docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md` 是当前缺失真实证据的执行路线。审计必须抓取 `canonicalInventoryRuntime*`、`canonicalSyncRuntime*`、`canonicalExistence*`、`canonicalApplyRuntime*`、`canonicalAudioUploadRuntime*`、`canonicalReadRuntime*`、`canonicalKernelSwitch*`、`Divergent`、`FreezeViolation`、`RollbackFailed`、`ConflictBlocked`。任一 divergence/freeze/rollback/conflict/redaction/security/oldKernel switch-back failure 都必须 stop and switch back。

## 2026-06-07 v8.44 legacy compatibility / switch-back 审计结论

v8.44 在 v8.43 主开关之上补了 legacy compatibility proof。审计结论：`canonicalFullSync` 是行为 owner 选择，不是数据格式切换；切回 `oldKernel` 后，旧内核必须能继续读写 canonical 写过的数据，不需要 migration，不删除 legacy path，不做 physical delete。

`CanonicalLegacyCompatibilityMatrix` 覆盖七个域：`recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`recordingExistence`、`audioUpload`、`readRuntime`。每个域的 pass 条件固定为 canonical write legacy-readable、legacy write canonical-readable、switch-back no migration、no canonical-only required field、unknown fields ignored/backward compatible、rollback available、diagnostics redacted。任一不满足必须产生 `CanonicalLegacyCompatibilityBlocker`，并阻断主开关进入可推广状态。

Switch-back harness 的状态机为 canonical action set -> switch `oldKernel` -> legacy read/sync/modify -> compare -> switch `canonicalFullSync` -> compare。canonical 写入使用 legacy-v1 必需字段加可忽略 unknown 字段；legacy 修改可以丢弃 unknown 字段；canonical 再读必须接受 legacy-v1。diagnostics 写在独立 redacted channel，不改变数据格式 fingerprint。

Crash/restart safety 覆盖四个中断点：before checkpoint、after checkpoint before write、after write before postcondition、after postcondition before duplicate suppression。restart mode 覆盖 `oldKernel` 与 `canonicalFullSync`。要求 no data loss、oldKernel can read、canonicalFullSync can read、incomplete state rollback/recovered or blocked、duplicate suppression not applied after interrupted postcondition、physicalDeleteCount=0。

当前 blockers to main switch：v8.44 是本地内存 harness 和单元测试证明，不是 paired-device production full-sync 证据；真实上主开关仍需要 iPhone/Mac 双端 diagnostics、人工确认、release/default disabled 审计和 no legacy deletion 审计。

## 2026-06-07 v8.43 unified kernel switch 审计结论

v8.43 把 canonical runtime ownership 收敛为一个手动主开关。审计结论：该开关只改变行为 owner，不改变同步数据格式，不触发 migration，不删除 legacy path。默认/release 解析为 `oldKernel`，即 canonical sync/apply/existence/audio/read owner 全部 disabled。

模式与 owner 状态固定如下：

| Mode | Owner state | Audit expectation |
| --- | --- | --- |
| `oldKernel` | `oldKernel` | legacy owns decision/apply/upload/read; no canonical owner |
| `diagnosticsOnly` | `canonicalNoWrite` | diagnostics only; no commit/no network/no read serve |
| `canonicalShadow` | `shadow` | canonical builds plan/projection and parallel compare; legacy executes/reads |
| `canonicalDecisionOnly` | `canonicalNoWrite` | canonical may own v8.38 decision with legacy apply/read fallback |
| `canonicalApplyNoAudio` | `canonicalReadWrite` | canonical non-audio apply/existence only; audio/read remain legacy/fallback |
| `canonicalFullSync` | `canonicalReadWrite` | sync/apply/existence/audio/read guarded with fallback; DEBUG/internal confirmed only |
| `blocked` | `blocked` | invalid/release/irreversible/mixed config blocks all canonical configs |

Reversibility gate 是状态机切换的硬门：legacy read/write path available、canonical writes legacy-readable 或 dual-write-compatible、switch back 无 migration、无 canonical-only required field、无 physical move/delete、diagnostics redacted、shadow compare 可保留。任一不满足必须 `blocked`。

主开关适配的 effective configs 包含 inventory runtime、sync runtime、apply runtime、existence apply、audio upload runtime、read runtime、libraryMetadata debug pilot 和 migration matrix policy。advanced override 只能作为专项调试；若与主开关 mapping 不一致，必须 block，而不是产生半新半旧状态。

iPhone sync coordinator/engine 在 run/tick 边界刷新主开关；Mac receiver 在配置通知后刷新并重建 HTTPS server。切回 `oldKernel` 不需要转换任何本地文件，下一次 run/server rebuild 即回到 legacy owner。Settings section `Debug · 同步内核` 仅 DEBUG 可见；full sync 必须确认，Release 隐藏。

## 2026-06-07 v8.42 read runtime v1 审计结论

v8.42 补上 Store/UI 可读取 canonical projection 的 default-off read runtime，但不改变默认同步状态机 owner。iPhone/Mac 默认 read path、legacy Store/UI model、legacy diff/apply/upload owner、retry drainer、Mac pending sync、routes/security、`receive.json` 和 audio inbox 均保留。

read runtime modes 固定为 `disabled`、`parallelCompare`、`canonicalReadCandidate`、`guardedCanonicalReadWithLegacyFallback` 和 `blocked`。`disabled` 必须返回 legacy；`parallelCompare` 返回 legacy 并比较 canonical；`canonicalReadCandidate` 构建 canonical 但不 serve；guarded canonical read 必须 explicit debug/internal owner-approved 且带 legacy fallback；`blocked` 必须 fallback legacy。

统一 read snapshot 覆盖六个域：recording metadata、library metadata、generated artifact metadata/availability、tombstone/conflict display state、recording/audio existence and upload status、sync engine status summary。snapshot 只能暴露 redacted metadata/status summary，不得暴露 absolute path、full hash、secret、request/response body、audio bytes 或完整 transcript/note/summary/provider/generated content。

diff/gate 是 canonical serving 的边界。`CanonicalReadRuntimeDiff` 必须比较 missing object、metadata mismatch、title/tags/folder mismatch、artifact availability mismatch、tombstone/conflict mismatch、audio availability mismatch、upload status mismatch、unsupported object 和 path/content leak risk。divergence count 大于 0 时 guarded read 必须 blocked/fallback，除非 explicit test-only divergent mode。

Gate 必须同时满足 v8.37 inventory snapshot available、v8.38 plan authority evidence、v8.39 existence truth evidence、v8.40 apply runtime evidence for non-audio、v8.41 upload runtime evidence for audio status、divergence=0、legacy fallback available、other domains not conflicting、release/default disabled 和 manual owner approval。缺任一证据都不能 serve canonical。

iPhone adapter 只从 existing manifest/inventory/read inputs 生成 canonical-shaped snapshot，不调用 sync/apply/upload，不创建 upload job，不 drain retry，不移动资源，不写 production store。Mac adapter 同样只读 existing inputs，不改变 `/sync/inventory` response、`receive.json`、audio inbox、pending sync、transcription/note generation 或 upload ledger。

diagnostics 新增 `canonicalReadRuntimeModeEvaluated`、`canonicalReadRuntimeServedCanonical`、`canonicalReadRuntimeServedLegacyFallback`、`canonicalReadRuntimeDiffEquivalent`、`canonicalReadRuntimeDiffDivergent`、`canonicalReadRuntimeBlocked` 和 `canonicalReadRuntimeReportBuilt`。诊断必须 redacted，只能输出 mode/domain/objectID/count/hash prefix/safe summary；不得写完整 hash、绝对路径、secret、fingerprint、request/response body 或用户内容。

v8.42 的真实完成标准不是默认切 canonical read，而是能在 explicit debug/internal 配置下证明：gate evidence 齐全、diff equivalent、canonical served、fallback retained、no sync/upload/store side effects、diagnostics redacted。没有该证据时必须继续 legacy read。

## 2026-06-07 v8.41 audio upload runtime commit v1 审计结论

v8.41 补上 canonical audio upload 的写侧 runtime commit executor，但默认/release owner 仍是 legacy `RecordingUploadCoordinator`。canonical runtime 只有在 explicit debug/internal/test 配置下才可被选中；legacy fallback 必须保留，blocked/failure 时在安全场景回退 legacy。

runtime modes 固定为 `disabled`、`diagnosticsOnly`、`noCommit`、`testTransportUpload`、`canonicalUploadWithLegacyFallback` 和 `blocked`。`disabled` 使用 legacy；`diagnosticsOnly` 只评估 would-upload；`noCommit` 不建 job、不发网络；`testTransportUpload` 只用 fake/test transport；`canonicalUploadWithLegacyFallback` 必须 debug/internal owner-approved、非 release/default、secure port 非 dry-run、fallback 可用。

session state machine 覆盖 idle、starting、started、chunking、interrupted、resuming、finalizing、finalized、failed、aborted、conflict 和 blocked。start/status/chunk/finalize 必须走 existing secure upload route/client；v8.41 不新增 abort route。confirmedBytes 必须单调，offset 必须 deterministic，duplicate chunk 只有 offset/length/hash 相同才 idempotent，wrong offset 必须失败或 retry。finalize 必须校验 byteSize 和 hash；mismatch 进入 conflict/failure，不能记 audio uploaded。

候选决策继承 v8.39 existence truth：local audio + peer metadataOnly/receiveRecordOnly/studyItemOnly 可成为 upload candidate；peer same hash+size 才 no-op；peerUnknown 必须 deferred；peer different hash/size 必须 conflict；metadata uploaded、receive record、UI uploaded、completed ledger alone 都不是 audio proof。view refresh 必须 denied；retry drainer 只能 replay existing eligible retry，不能创建 fresh unrelated job。

retry/job persistence 只保存 objectID、sessionID、offset、chunkSize、content hash prefix、byteSize 和 state，不保存绝对路径或完整 hash。resume after restart 必须先通过 existing status route 刷新 stale session，再从 confirmed offset 继续。conflict/fatal blocker 不得无限循环。

iPhone adapter 必须复用 `RecordingUploadClient` / `SecureMacUploadClient` secure transport，不得自行构造未签名请求或绕过 pinning/HMAC/nonce/body hash。Mac 侧 `SecureLocalHTTPSServer` route allowlist 与 `RequestVerifier` 不变；`MacRecordingFileStore` 仍只在 verified finalize 后移动 part file 成 final audio；existing different audio 必须 conflict/no-overwrite。

upload ledger completed、iPhone uploaded state、Mac receive record audio availability 都只能在 finalize proof 之后成立。metadataOnly 不能产生 audioAvailable；completed ledger alone 不能成为 no-op；Mac existing different audio 不得覆盖；不得自动下载 audio、写 transcript/note/summary、物理删除 audio 或实现 tombstone GC。

diagnostics 必须 redacted：允许 mode/state/reason/objectID/sessionID prefix/count/byte size/hash prefix；不得输出 full hash、absolute path、secret、full fingerprint、request/response body、audio bytes、transcript/note/summary/provider output 或用户内容。真实审计仍需要 paired-device long-recording evidence；本地单元测试只能证明 guard、state machine、retry 和 route-bound adapter 行为。

## 2026-06-07 v8.40 apply runtime owner v1 审计结论

v8.40 首次允许 `CanonicalApplyPlan` 在显式配置下成为 non-audio apply runtime owner，但默认/release 仍是 legacy apply owner。legacy apply、legacy fallback、legacy upload runtime、retry drainer、Mac pending sync、route/security、UI 和 read path 均保留，`runtimeSwitch` 继续为 false。

运行模式为 `disabled`、`diagnosticsOnly`、`noCommit`、`testRootApply`、`productionRootApplyWithLegacyFallback` 和 `blocked`。`disabled` 走 legacy；`diagnosticsOnly` 只比较 canonical plan 与 legacy intent；`noCommit` 不提交；`testRootApply` 只允许 test root non-audio apply；`productionRootApplyWithLegacyFallback` 只允许 explicit debug/internal owner-approved 且 release/default 禁止。任一 gate blocker 都必须 legacy fallback。

Gate 必须同时确认 v8.38 plan authority 或 explicit noCommit、v8.37 inventory snapshot 有效、apply plan 有效、enabled domains 显式列出、executor 存在且非 dry-run-only、root-bound apply port 可用、rollback/postcondition 可用、legacy fallback 可用、diagnostics redacted、read path legacy、runtimeSwitch=false。unresolved conflict 只有 conflict-record action 启用时才可执行；audio action、resource move、standalone note content write、permanent delete/tombstone GC 和 unsupported domain 都必须 blocked。

Registry 范围固定为 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict` 和 `recordingExistence`。`audioUpload` 在 v8.40 是 unsupported domain，必须产生 `canonicalApplyRuntimeAudioActionBlocked` 或等价 blocker；不得迁移 audio upload runtime、resumable chunk upload、audio receive finalize 或 audio bytes 写入。

执行顺序固定为逐 action 串行：precondition -> rollback checkpoint -> domain commit -> postcondition -> diagnostics。首个失败停止后续 action；rollback failure 是 fatal blocker。只有 canonical action 成功且与 legacy action 精确匹配时才允许 duplicate legacy suppression；diagnosticsOnly/noCommit/blocked/failure/fallback 均不得 suppress legacy。

iPhone 侧在 `StudyLibrarySyncCoordinator.performTick` 中使用 v8.38 runtime result 构建 v8.40 apply context；默认 disabled，显式 debug/internal 才可执行 enabled non-audio actions。它不得创建 upload job，除既有 legacy upload path 外不得影响 audio 上传，不改 retry drainer，不改 UI/read path。

Mac 侧 `SecureReceiverService` / `SecureLocalHTTPSServer` 保持 route/schema/security 不变。v8.40 只在显式配置下用 shared gate/registry 约束 existing v8.39 recording existence metadata-only bridge；不得绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash，不得改 upload route，不得触发 transcription/note generation，不得写 audio bytes。

诊断必须 redacted，只能写 mode/domain/action/object/count/hash prefix/blocker 等摘要。不得输出完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint、request/response body、完整 transcript/note/summary/provider response 或 standalone note content。真机审计仍需要 paired-device apply diagnostics；本地测试通过不能替代真实设备证据。

## 2026-06-07 v8.39 existence/apply bridge runtime v1 审计结论

v8.39 不改变同步状态机 owner，也不迁移大文件上传 runtime。iPhone `performTick`、Mac apply route、legacy `StudyLibraryStore.applySyncManifest`、legacy upload coordinator/client、retry drainer、Mac pending sync、RequestVerifier、TLS/HMAC/pinning/nonce/body hash、upload routes、UI 和默认 read path 均保留。新增内容只补上 `manifest.recordings` 到 Mac metadata-only existence truth 的 apply bridge。

canonical existence truth 必须把同一 recording object 的学习库条目、recording metadata、receive record、audio availability 统一判断。metadataOnly、studyItemOnly、receiveRecordOnly 和 completed receive ledger 都不能作为 audio uploaded/no-op；只有 peer audio hash 与 byteSize 同时匹配才是 audio no-op；peerUnknown 不得当 missing，必须 deferred；different hash/size 必须 conflict；tombstoned parent 必须阻断 apply/upload candidate。

Mac apply bridge 消费 `manifest.recordings` 后，只能创建或更新 metadata-only existence record。由于 legacy inbox `receive.json` 是 Mac read path 输入，本轮使用单独 canonical ledger `sync/canonical-recording-existence/records/`。写入必须 root-bound、atomic、带 rollback checkpoint 和 postcondition；postcondition 必须证明 record exists、objectID/metadataHash 匹配、audioAvailable=false、没有 audio file created、没有 upload ledger completed。rollback 只能恢复 previous record 或移除本轮新增 placeholder；rollback failure 是 fatal。

Mac inventory 可以把 canonical ledger 合并为 peer recording exists，但不得谎报 audio。metadata-only record 必须 `audioAvailable=false`；hash、byteSize、audio path 只有真实音频事实证明时才出现；completed ledger 不能单独作为 audio proof；legacy inbox receive record 与 canonical ledger 同 object 时要归一，分歧必须产生 conflict/blocker diagnostics。

iPhone 侧只把 existence truth 接入现有上传候选判断和 diagnostics。local audio + peer metadataOnly/receiveRecordOnly/studyItemOnly 可以通过 existing evaluator 进入 legacy `RecordingUploadCoordinator` 上传候选；peer absent 先需要 metadata apply bridge；same hash+size no-op；peerUnknown deferred；different hash/size conflict。view refresh 不创建 upload job，retry drainer 不创建 fresh unrelated job，upload route/security 不变。

runtime 配置默认 `disabled`。`diagnosticsOnly` 只评估 would-apply，`noCommit` 只写 staging/test evidence，`testRootApply` 只允许 test root placeholder，`productionRootApply` 必须 explicit debug/internal owner-approved、root-bound、rollback、atomic、postcondition，且仍不得写 audio 或 mark audio available。release/default 不得启用 existence apply bridge；legacy fallback 必须一直可用。

v8.39 diagnostics 只能输出 objectID/action/state/reason/hash prefix/byte count 等 redacted 摘要。不得写完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint、request/response body 或用户内容。真实完成标准必须包含新录音 iPhone->Mac 真机 evidence：Mac 消费 manifest recording、出现 metadata-only peer existence、iPhone 产生 peer metadataOnly upload candidate、既有 coordinator 建 job、Mac 收到 audio。

## 2026-06-07 v8.38 sync decision runtime v1 审计结论

v8.38 只把 canonical diff/LWW 提升为受控 decision-runtime candidate，不改变默认同步状态机 owner。默认/release 仍使用 legacy diff owner；legacy planner、legacy fallback、legacy read path、legacy upload runtime、retry drainer、Mac pending sync、routes/security、`receive.json` 和 audio inbox 均保留。

新增 runtime mode/policy/result 与 authority gate。`disabled` 保持 legacy owner；`diagnosticsOnly` 只比较 canonical 与 legacy；`canonicalPlanNoCommit` 只记录 would-use canonical；`canonicalPlanPrimaryWithLegacyFallback` 仅在 explicit debug/internal、owner-approved、非 release/default、runtimeSwitch=false、readPathLegacy=true、legacy fallback available 且 gate 全部通过时，才能对启用的 metadata/library/recording existence scope 使用 canonical plan 作为 decision owner。`blocked` 或任何 gate blocker 都执行 legacy fallback。

Authority gate 必须检查 v8.37 snapshot、local/peer canonical manifest、manifest/hash schema、canonical modifiedAt 语义、unsupported object count、library fallbackRequired object count、conflict count、peerUnknown audio、legacy fallback、diagnostics redaction、其它 active migration domain 和 debug/internal owner approval。peer unknown audio 仍是 defer/blocker，不得当 missing；metadata uploaded 或 completed ledger 仍不能当 audio uploaded/no-op。

metadata truth 以 `canonical-recording-business-metadata-v1` 为准。iPhone/Mac adapter 必须喂入等价业务字段；hash 只覆盖 stable business metadata。canonical modifiedAt/LWW 只使用业务修改时间，不能使用 receivedAt、observedAt、upload progress、processing status 或 inbox observe time。canonical hash 相同即 metadata no-op；legacy hash 不同但 canonical hash 相同时，canonical primary mode 可以忽略 legacy mismatch 并记录 `canonicalSyncRuntimeLegacyHashMismatchIgnored`，不重复 metadata transfer。

iPhone `performTick` 在 legacy plan 之后构建 canonical plan 并评估 gate。primary allowed 时，只对 exact metadata/library/recording-existence scope 做 canonical owner 替换，并通过 duplicate guard 防止同 object/action/scope 的 legacy duplicate 再执行；diagnostics/noCommit/blocked/planning failure 都不 suppress legacy。大文件 audio upload runtime 仍由 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient` 与既有 evaluator 负责，本轮不新增 upload job。

Mac inventory/server 侧仅评估并记录 `canonicalSyncRuntimePlanEvaluated/Allowed/Fallback/Blocked` 等 redacted diagnostics。真实 `/sync/inventory` 缺 peer snapshot 时 primary blocked/fallback；不改变 response schema，不调用 apply，不写 `receive.json`，不写 audio inbox，不改 RequestVerifier/TLS/HMAC/nonce/body hash 或 upload/artifact routes。

v8.38 真实完成标准不是“canonical 默认接管”，而是 diagnostics 能按 syncRunID 证明：默认/release legacy owner；debug/internal allowed 时 `canonicalSyncRuntimePlanUsed` 只覆盖启用 metadata scope；blocked 时 `canonicalSyncRuntimePlanFallback`；无 duplicate execution；diagnostics 只含 count/object/action/scope/hash prefix，不含完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint 或 request/response body。

## 2026-06-11 v8.47 P0-2 persistent checksum cache 审计结论

v8.47 不改变同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory` response、legacy diff/apply、upload job creation、retry drainer、Mac pending sync、read path、UI、upload routes、RequestVerifier、TLS/HMAC/pinning/nonce/body hash 均保持原语义；本轮只让 inventory/canonical snapshot checksum cache 真实落盘、真实命中、真实减少 hash/scan 工作，并输出可真机对比的 telemetry。

持久化 cache 的 key 必须覆盖 safe logical token、byte size、mtime/contentVersion、hash algorithm、schema version、node role/platform role 和可选 namespace。record 内部可保存完整 hash 供 inventory 使用，但 diagnostics 只允许 hash prefix；record 还记录 byte size、mtime/contentVersion、computedAt、schemaVersion、source role 和 validation state。hit 必须跳过 hash provider，miss/stale 必须在后台 hash 并 atomic persist；logical token 变化为 miss，size/mtime/contentVersion/algorithm/schema 变化为 stale。

cache 维护必须 fail closed。schema mismatch、root corruption 或单 record decode failure 不能崩溃或改变 sync decision；系统应忽略损坏 cache、重新 hash 或返回 `hashUnavailable`。`hashUnavailable` 只表示无法证明内容相等，不得用于 equality proof、diff no-op 或 apply 判定。prune 只删除/重写 cache record，不能碰 audio inbox、receive.json、学习库内容、transcript/note/summary 或用户文件。

telemetry 必须来自真实路径。`inventoryBuildDurationMs`、metadata/jobs/file scan/hash/cache load/write/prune duration 用真实 clock 或 fake clock 测试钩子测量；cache hit/miss/stale/error、hash computed/failed/unavailable、duplicate snapshot、snapshot reuse、mainActor hash/scan/metadata/jobs attempts 和 redaction violation count 由 runtime counter/detector 产生。禁止硬编码 fake pass，例如 `MainActorHashBlocked count=0` 或 `MainActorScanBlocked count=0`。

iPhone 侧每个 `syncRunID` 应单 snapshot；end-of-tick success、canonical shadow/readiness 和 diagnostics 复用 snapshot 或 cache-backed facts，不触发二次 hash/scan。Mac 侧 `/sync/inventory` 使用 persistent checksum cache 复用 audio/artifact facts，response schema/security 不变；但源码审计显示 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 仍是 `@MainActor`，因此 Mac main-actor attempt 是真实剩余 blocker，不能在报告里抹平。

真实完成需要 paired-device before/after evidence：inventoryBuildDurationMs、cache hit/miss/stale/error、hashComputedCount、duplicateBuildCount、mainActor attempt counts、redacted diagnostics path 和 UI latency 体感记录。没有真机日志时结论只能是代码路径与单元测试覆盖，不能声明真机性能完成。

## 2026-06-07 v8.37 inventory runtime v1 审计结论

v8.37 不改变同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory` response、legacy diff/apply、upload job creation、retry drainer、Mac pending sync、read path、UI、upload routes、RequestVerifier、TLS/HMAC/pinning/nonce/body hash 均保持原语义；本轮只把 inventory/hash runtime 从主线程阻塞和重复构建中拆出来。

iPhone 每个 `syncRunID` 预期只构建一次 local runtime snapshot；同 tick 后续 success/diagnostics/shadow/readiness 使用同一份 legacy-compatible inventory 或同一组 file facts。Mac 每个 inventory request 使用一次 cache-backed snapshot；canonical shadow/readiness 不应重新扫描 inbox/receive/audio。v8.37 原始正常路径预期 duplicate build count 为 0；v8.46 后，同一 iPhone syncRunID 的重复请求应复用 snapshot 并可报告 duplicate/reuse count，而不是重新扫描/hash。

checksum cache 是持久化、fail-closed 的运行时缓存。key 必须包含 logical token、byte size、mtime、hash algorithm、schema version 和 node role；hit 不 hash，stale/miss 在后台 hash，cache corruption 重新 hash 或返回 hashUnavailable。hashUnavailable 只表示无法证明内容相等，不得用于 diff/apply equality proof。v8.47 进一步要求该 cache 真实落盘、跨 sync tick/app restart 命中，并用 fake hash provider count 证明 hit 不调用 hash。

诊断只能输出 redacted counts/durations/object counts：cache hit/miss/stale/error、hash computed、scan count、duplicate build、mainActor hash/scan blocker。不得写绝对路径、完整 hash、完整 fingerprint、secret、完整 metadata JSON、note/transcript/summary 内容或 request/response body。真机审计还需要 grep diagnostics 并观察 UI latency；没有真机日志时只能说明代码路径已接入。

## 2026-06-07 LibraryMetadata real-device debug switch 审计结论

本轮只把既有 libraryMetadata debug pilot 接到真机可操作的 Debug 设置和 app 构造点。iPhone `StudyLibrarySyncCoordinator` 与 Mac `SecureReceiverService` / `SecureLocalHTTPSServer` 的默认 owner 不变：默认仍 `.disabled`，executor 仍 nil，legacy diff/apply、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path、legacy store/write path 和 upload routes 保持原状。

Debug 设置可选择 `diagnosticsOnly`、`armTestRootN1`、`executeTestRootN1` 或 `executeProductionRootN1`。前两类 test-root 模式只在系统临时目录下构造 root-bound executor，不写 production root。production-root 模式必须 UI 二次确认并取得现有 app/store root；只有该模式会把 `allowProductionRootWrites=true` 传入既有 bootstrap。未确认或 root 不可用时 fail closed 到 disabled/nil。

本轮不新增 route，不绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash，不改 `receive.json`、audio inbox、transcription/note generation、upload route、retry drainer、Mac pending sync、StudyLibraryStore 或学习库 UI read path。`generatedArtifacts`、`tombstoneConflict`、`audioUpload` 和 `recordingMetadata` 仍 staticOnly/defaultOff。

诊断文件位置只在 UI/docs 中用相对路径或 `~` 展示；Mac certificate fingerprint 日志已改为 prefix-only。没有真机 jsonl 时，只能说明代码接线已完成，不能说明真机试点已验证。

## 2026-06-06 v8.32 libraryMetadata N=1 evidence audit / N=3 readiness gate 审计结论

v8.32 不改变同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory`、legacy diff/apply、retry drainer、Mac pending sync、upload ledger、默认 UI read path、legacy store/write path 和 upload routes 保持原状。本轮新增的是读取或引用 v8.31 N=1 redacted evidence 的审计模型、post-run invariant validator、safe exporter 和 N=3 readiness gate；它们不调用 executor、不触发 canary、不写 production root、不执行 N=3。

N=1 evidence bundle 必须证明：activePilot 仅为 `libraryMetadata`，executed candidate 数量为 0 或 1，candidate kind 为 safe metadata-only，productionRootSafetyProof valid，LandingFreeze green，other domains staticOnly，runtimeSwitch=false，release/default disabled，legacy fallback available，read-side parallel executed 且 divergence=0，rollback failure=0。duplicate suppression 只有在 commit success 后才允许；否则是 fatal blocker。

post-run invariant 继续阻断任何同步状态外溢：resource move、standalone note content write、generated artifact write、audio change、tombstone/delete、read path switch、UI mutation、RequestVerifier/route boundary violation、`receive.json` unexpected mutation、non-libraryMetadata active pilot、N>1、runtimeSwitch 或 release/default enablement。所有 violation 都必须 redacted 且 diagnosable。

N=3 readiness 只是人工审计前的报告状态。`readyForN3AfterManualAudit` 不会运行 N=3，不会开启 default/release，不会切 read path，不会删除 legacy，也不会让 `generatedArtifacts`、`tombstoneConflict`、`audioUpload` 或 `recordingMetadata` 变 active。若缺 v8.31 真实 N=1 evidence，结果必须是 `missingEvidence`，下一步是按 runbook 手动补跑 N=1。

## 2026-06-06 v8.31 libraryMetadata production-root N=1 pilot 审计结论

v8.31 不改变同步状态机 owner。iPhone 默认 `performTick`、Mac `/sync/inventory` response、legacy diff/apply、retry drainer、Mac pending sync、upload ledger、默认 UI read path 和 legacy store/write path 仍保持原状。新增的能力仅允许 `libraryMetadata` 在 explicit debug/internal config 下，对一个 safe metadata candidate 执行一次 production-root N=1 pilot。

production-root gate 必须同时满足：explicit internal/debug、`executeN1Canary`、`productionRootExplicit`、`allowProductionRootWrites=true`、owner-approved token、唯一 active pilot 为 `libraryMetadata`、无 runtime switch、LandingFreeze green、v8.30 diagnostics/arm/testRoot evidence、read-side divergence=0、rollback evidence、legacy fallback、productionRootBound apply-port evidence、checkpoint availability 和 postcondition verification capability。任一缺失必须 no write、legacy fallback preserved。

执行顺序固定为：选择恰好一个 safe metadata-only candidate，创建 rollback checkpoint，root-bound atomic metadata write，postcondition verification，read-side parallel comparison。成功后记录 redacted safety proof，并只 suppress exact matching legacy `libraryMetadata` duplicate；失败后 rollback/fallback，不 suppress legacy；rollback failure 是 fatal blocker。不会继续第二个 candidate，不会切 read path，不会改 UI，不会影响其它 domain。

安全边界保持不变：不新增 route，不绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash，不改变 upload routes，不让 audio 自动下载，不移动 audio/transcript/note/summary/resource 文件，不写 standalone note content，不执行 tombstone/delete/trash/permanent delete/GC，不删除或禁用 legacy。diagnostics 只允许记录 domain/mode/rootMode/nodeRole/syncRunID/candidate kind/result/reason/hash prefix；不得包含 root path、完整 metadata JSON、完整 hash、内容、secret、fingerprint 或 request/response body。

## 2026-06-06 v8.30 libraryMetadata diagnostics / arm / test-root drill 审计结论

v8.30 不改变同步状态机 owner。iPhone `performTick` 默认路径、Mac `/sync/inventory` response、legacy diff/apply、retry drainer、Mac pending sync、upload ledger、默认 UI read path 和 legacy store/write path 仍保持原状。新增的是 `libraryMetadata` debug pilot 的可验证 diagnostics/arm/testRoot execution drill。

`diagnosticsOnly` 在 seam 中运行 LandingFreeze，检查 activePilot 是否为 `libraryMetadata`、其它 domain 是否 staticOnly、runtimeSwitch 是否 false、read path 是否 legacy、默认 production executor/root write 是否关闭、release/default 是否 disabled。该阶段不选 candidate、不构造 write port、不 commit、不 suppress legacy；失败只作为 nonfatal redacted diagnostic。

`armN1Canary` 只做 readiness：最多一个 safe metadata-only candidate、rollback plan/checkpoint/readiness、read-side parallel evidence、legacy fallback availability。它不调用 executor，不写 test root，不写 production root，不 suppress legacy，不改变 read path。unsafe/no eligible/read-side divergence/fallback missing 只阻断后续执行建议。

`executeN1Canary` 只允许 explicit internal/test config + testRoot apply port。`productionRootExplicit` 和 `allowProductionRootWrites=true` 在 v8.30 均 blocked；双端 bootstrap 不会在 production-root mode 构造 apply port/executor。commit 成功后必须做 read-side parallel comparison；divergence > 0 是 blocker。duplicate suppression 仍只允许在 test harness/test-root success 后针对 matching legacy duplicate，默认 app production path 不 suppress。

safe diagnostic export 仅输出 mode/nodeRole/activePilot/freeze/candidate/canary/rollback/fallback/suppression/read-side/static/runtime/redacted 等摘要字段，不含完整 metadata JSON、note/transcript/summary/provider 内容、绝对路径、完整 hash、secret、fingerprint 或 request/response body。

## 2026-06-06 v8.29 libraryMetadata real-device pilot landing 审计结论

v8.29 不改变当前同步状态机 owner。iPhone `performTick` 默认路径、Mac `/sync/inventory` response、legacy diff、legacy `StudyLibraryStore.applySyncManifest`、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。新增内容是 default-disabled debug/internal landing config 与 executor 注入点。

landing freeze 要求本轮唯一 active pilot 为 `libraryMetadata`；`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata`、`uiProjection` 和 `legacyRetirement` 必须 static/default-off。runtimeSwitch、release/default cutover、read-side cutover 和 legacy retirement 均不得打开。历史 v8.22-v8.28 active-pilot helper 不构成本轮执行许可。

iPhone 显式 v8.29 config 在旧 libraryMetadata seam 前运行，并且只在 local/peer canonical snapshots、owner token、rollback/evidence、read-side equivalence、root-bound non-dry-run apply port 和 injected executor 都满足时才执行一个 metadata-only candidate。成功后只 suppress exact matching libraryMetadata legacy duplicate；失败、armed、diagnosticsOnly、blocked、unsafe、no eligible 或 rollback 都保留 legacy fallback。

Mac receiver 只增加 config/executor pass-through。真实 inventory context 没有 peer snapshot，因此只记录 `canonicalLibraryMetadataLandingConfigEvaluated`、blocked/fallback/report diagnostics，不拉取 peer、不调用 executor、不新增 route、不绕过 `RequestVerifier`、TLS/HMAC/nonce/body hash，不改 response、`receive.json`、audio inbox、transcription/note generation 或 pending sync。直接 internal/test harness 可用 `MacLibraryMetadataRealApplyPort(testRootURL:)` 验证 root-bound N=1。

read-side 仍是 parallel evidence：landing report 可记录 equivalent/divergent，但 `uiReadPathSwitched=false`、`legacyReadPathPreserved=true`。任何 read divergence 都必须阻断执行并保留 legacy。diagnostics 仅允许 redacted mode/rootMode/status/reason/count/hash prefix/object/action summary；不得写完整 metadata/content、完整 hash、绝对路径、secret、fingerprint 或 request/response body。

## 2026-06-05 v8.28 tombstoneConflict canary N=1 审计结论

v8.28 只把 `tombstoneConflict` active pilot 从 N=0 guarded evaluation 推进到显式 internal/test N=1 canary；当前同步状态机 owner 仍不变。iPhone `performTick`、Mac `/sync/inventory`、legacy diff、旧 metadata/artifact route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。

N=1 execution gate 必须同时满足：activePilot=`tombstoneConflict` 且无其它 active pilot、budget exactly 1、runtimeSwitch=false、allEligible=false、owner-approved token、rollback plan、NoCommit、dry-run equivalence、execution shadow、real-data shadow copy、read-side parallel equivalence、anti-resurrection evidence、failure injection coverage、non-dry-run root-bound apply port、legacy fallback 和 duplicate suppression policy。缺任一项必须 no commit，并继续 legacy fallback。

candidate selector 每 run 最多选 1 个 safe candidate，稳定优先 conflict record / resurrection block record，再到 object/library soft tombstone marker。generated artifact tombstone marker 只能 report-only；任何 generated artifact apply/download、audio action、full content mutation、unsafe path、missing rollback checkpoint、physical/permanent delete、tombstone GC、restore、clear tombstone、ambiguous conflict auto-resolution 或 stale live resurrection 都必须 blocked。成功只写 soft marker 或 conflict ledger record，不删除、不 restore、不清 tombstone、不写 audio/transcript/note/summary。

duplicate legacy suppression 只在 canonical commit 成功且 pre/postcondition verified 后应用，只针对 matching tombstoneConflict legacy duplicate。失败、rollback、rollback failure、unsafe/no eligible/report-only candidate 都不得 suppress。read-side 仍为 parallel diagnostics：记录 tombstone/conflict projection equivalence 或 divergence，但不切 read path、不改 UI、不触发 sync/upload。

Mac N=1 支持保持安全边界：不新增 route、不扩大 allowlist、不绕过 RequestVerifier/TLS/HMAC/nonce/body hash、不改 upload routes。真实 inventory context 缺 peer snapshot 时记录 blocked/fallback diagnostics，不改 response、`receive.json`、audio inbox、transcription/note generation 或 Mac pending sync。diagnostics 仅允许 redacted syncRunID、trigger、nodeRole、domain/object/action/blocker/status/hash prefix/count；不得写完整 metadata/content、完整 hash、绝对路径、secret、fingerprint 或 request/response body。

## 2026-06-05 v8.27 tombstoneConflict active pilot guarded seam N=0 审计结论

v8.27 只改变 canonical migration matrix 的 active pilot 归属和诊断 gate：`tombstoneConflict` 是唯一 active pilot，`generatedArtifacts` 不再 active，但其模板/观察 evidence 仍是前置条件。当前同步状态机 owner 不变；iPhone `performTick`、Mac `/sync/inventory`、legacy diff、旧 metadata/artifact route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。

guarded seam 只做 gate evaluation 和 no-execution report。iPhone seam 复用已加载的 local/peer inventory、canonical manifest、canonical apply/library plan、tombstoneConflict evidence 和 legacy action snapshot；Mac seam 只复用本地 inventory/canonical manifest，缺 peer snapshot 时阻断。两端都不扫描额外目录，不读取完整 metadata/content，不写 store，不改变 plan 或 response。

canary budget 固定为 0；任何 allowed 结果都必须转成 `allowedButCanaryBudgetZero` / commit skipped。v8.27 不执行 tombstone marker write、restore、tombstone clear、physical delete、permanent delete、tombstone GC、auto conflict resolution 或 legacy duplicate suppression；不创建 upload job、不触发网络、不改 UI/read path、不新增 route、不切 runtime switch、不改 retry drainer、Mac pending sync、`receive.json` 或 audio inbox。

gate blocker 必须覆盖 missing evidence、missing peer snapshot、缺 owner token、非 tombstoneConflict active pilot、N1/staged/allEligible/runtime switch/default enablement、unsupported action/domain、missing tombstone timestamp/policy/rollback evidence、generated artifact tombstone marker、ambiguous conflict policy、unsupported restore、stale live resurrection risk、physical/permanent delete 和 tombstone GC。diagnostics 只能写 redacted enum/status/reason/count/object/action summary/hash prefix；不得写完整 metadata/content、完整 hash、绝对路径、request/response body、secret、fingerprint 或用户内容。

## 2026-06-05 v8.26 tombstoneConflict template / next-pilot candidate 审计结论

v8.26 只补齐 `tombstoneConflict` 模板、metadata-only read projection、parallel diff、anti-resurrection gate、observation window 和 report-only retirement candidate gate；不改变当前同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory` response、legacy diff、旧 generated artifact request/apply route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。

`tombstoneConflict.nextPilotCandidate` 只是矩阵候选状态，不是 active pilot、不是 canary、不是 read-side cutover、不是 domain cutover。该候选要求 generatedArtifacts 模板/观察证据已就绪；即使候选 ready，也必须保持 `activePilot=false`、`staticOnly=true`、`runtimeSwitch=false`、`readPathLegacy=true`、legacy fallback available。不得把 v8.26 诊断解释为执行许可。

读侧 projection 只输出 tombstone/conflict metadata 摘要：object kind、tombstone state、deleted display state、timestamp summary、conflict status、anti-resurrection status、soft marker、hash prefix 和 redacted risk counts。不得读取或输出完整 metadata、完整 generated content、绝对路径、physical delete target path、完整 hash、request/response body、secret、fingerprint 或用户隐私路径。

双端 seam 默认 disabled。显式 enabled 时也只消费调用方已持有的 inventory/canonical manifest/apply plan/library plan facts，返回 diff 和 redacted diagnostics；不得执行 physical delete、permanent delete、tombstone GC、restore、tombstone clear、auto conflict resolution、upload job、sync job、store write、UI mutation、inventory response mutation、`receive.json` mutation、audio inbox write、transcription/note generation、retry drainer 或 Mac pending sync。

anti-resurrection gate 必须阻断 stale live metadata resurrection、absence-as-restore、缺 explicit restore signal、tombstoned parent 下 generated artifact/library metadata apply、physical/permanent delete、tombstone GC 和 auto conflict resolution。observation 默认 disabled/incomplete；retirement candidate gate 仍 report-only，固定不删除或禁用 legacy。

## 2026-06-05 v8.25 generatedArtifacts read-side guarded seam / observation 审计结论

v8.25 只补齐 `generatedArtifacts` read-side guarded seam 与 observation/report-only readiness，不改变当前同步状态机 owner。iPhone `performTick` 默认路径、Mac `/sync/inventory` response、legacy diff、旧 generated artifact request/apply route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。

read source 默认 `legacy`。`parallelCompare` 返回 legacy output 并记录 diff；`canonicalCandidate` 构建 canonical generated artifact metadata/availability candidate 但不服务 UI；`guardedCanonicalRead` 只有 explicit internal/test config、`generatedArtifacts` 唯一 active pilot、write-side staged canary clean evidence、zero divergence、zero unsupported/content/path/parent/audio blocker、fallback available、canonical projection complete、no artifact route change、no generated artifact upload job、runtimeSwitch=false 时才可返回 canonical metadata/availability output。任何 gate blocker、canonical projection missing 或 canonical read exception 都必须 fallback legacy。

双端 seam 只消费已加载的 legacy/canonical snapshot 或 inventory facts；不得调用 `/sync/artifact-request`，不得下载/apply artifact，不能写 generated artifact file，不能创建 generated artifact upload job，不能自动下载 audio，不能触发 sync/upload，不能修改 UI、store、`receive.json`、inventory response、transcription/note generation、retry drainer 或 Mac pending sync。read projection 和 diagnostics 只包含 hash prefix、byte size、logical token summary、availability、producer、parent state 和 redacted counts，不包含完整 transcript/note/summary、provider response、完整 hash、绝对路径、secret、fingerprint 或 request/response body。

observation window 现在把 write-side staged canary evidence 与 read-source evidence 串联：记录 write-side canonical commit、rollback、rollback failure、legacy fallback、duplicate suppression、read-side canonical served、legacy fallback、divergence、unsupported/contentLeakRisk/unsafePathToken/parentTombstone/audioConfusion、runtimeSwitch=false、activePilot=generatedArtifacts、otherDomainsStaticOnly。retirement candidate gate 仍 report-only；ready 只表示“候选可人工审计”，不执行 legacy deletion/disable，不改 runtime switch，不停止 legacy fallback 或 shadow comparison。下一步应审计 v8.25 evidence，可延长 generatedArtifacts observation 或转向 tombstoneConflict template alignment；不得直接迁移 audio。

## 2026-06-05 v8.24 generatedArtifacts staged canary expansion 审计结论

v8.24 只扩大 `generatedArtifacts` canary 的候选数量，不改变当前同步状态机 owner。iPhone `performTick` 默认路径、Mac `/sync/inventory`、legacy diff、旧 generated artifact request/apply route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。`N3/N10/allEligible` 只由 iPhone seam 在已有 local/peer canonical manifest、canonical apply plan 和 injected executor 基础上执行；Mac inventory seam 仍因缺 peer snapshot report-only blocked。

stage 顺序固定为 `N1 -> N3 -> N10 -> allEligible`。`N3` 需要 clean N1 evidence，`N10` 需要 clean N3 evidence，`allEligible` 需要 clean N10 evidence 与显式 `allowAllEligible=true`。previous-stage evidence 中 failure、rollback failure、blocking divergence、unresolved conflict、postcondition failure、unsupported artifact、content leak risk、unsafe path token、parent tombstone、audio confusion、hash unavailable、byte size unavailable、read-side divergence、缺 rollback/no-commit/dry-run/shadow/root-bound/read-only transport/legacy fallback 任一项都必须阻断下一 stage。

multi-candidate 执行必须顺序稳定。candidate 仍只能是 existing `/sync/artifact-request` bridge 的 `generatedArtifactDownloadApply`；不得把 generated artifact upload、audio upload、metadata/receiveRecord、unsupported kind 或 unsafe path 混入。每个成功 candidate 后记录 expanded read-side parallel diagnostics；首个失败必须 rollback、停止剩余 candidate、保留 legacy fallback。duplicate suppression 只对 committed 且 pre/postcondition verified 的 successful candidates 生效；失败 candidate、未执行 candidate、rollback/fatal rollback 或 Mac report-only 均不得 suppress。

v8.24 不新增 route，不绕过 `/sync/artifact-request`、checksum/size 校验、`RequestVerifier`、TLS pinning、HMAC、nonce、body hash、Keychain 或旧 artifact apply path；不创建 generated artifact upload job，不自动下载 audio，不切 UI/read path/runtime switch，不改 retry drainer、Mac pending sync、inventory response、pending count、upload ledger、`receive.json` 或 audio inbox。下一步应是 generatedArtifacts read-side guarded canonical seam/observation 的独立审计，不是 audio migration。

## 2026-06-05 v8.23 generatedArtifacts canary N=1 审计结论

v8.23 只在 `generatedArtifacts` 唯一 active pilot 内新增 explicit internal N=1 canary path。当前同步状态机 owner 仍不变：iPhone `performTick`、Mac `/sync/inventory`、legacy diff、旧 generated artifact request/apply route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。N=1 只由 iPhone seam 在已有 local/peer canonical manifest 和 apply plan 基础上选择一个 `generatedArtifactDownloadApply` candidate；Mac inventory seam 仍因缺 peer snapshot report-only blocked。

N=1 必须同时满足 owner-approved token、显式 internal config、budget exactly 1、no runtime switch、no allEligible/stage rollout、matrix activePilot=`generatedArtifacts`、`libraryMetadata` observation/retirement prerequisite、local/peer snapshot、injected executor、rollback/read-side/no-commit/dry-run/execution-shadow/real-data-shadow/root-bound evidence 和 `/sync/artifact-request` route evidence。缺任一条件必须 legacy fallback preserved，且不得执行 commit。

candidate blocker 现在必须细分 hash/byte size unavailable、unsafe logical path token、content leak risk、audio confusion risk、producer ambiguous、wrong route、generated artifact upload denied、rollback checkpoint missing、peer not authoritative、parent tombstone、conflict、runtime switch、N>1/allEligible、peer snapshot/executor missing 等；不得用泛化成功或静默 fallback 掩盖。成功后只 suppress exact matching legacy artifact action；失败、rollback、fatal rollback、no eligible 或 fallback 都不得 suppress。

v8.23 不新增 route，不绕过 `/sync/artifact-request`、checksum/size 校验、`RequestVerifier`、TLS pinning、HMAC、nonce、body hash、Keychain 或旧 artifact apply path；不创建 generated artifact upload job，不自动下载 audio，不切 UI/read path/runtime switch，不改 retry drainer、Mac pending sync、inventory response、pending count、upload ledger 或 `receive.json`。

## 2026-06-05 v8.22 generatedArtifacts active pilot guarded commit seam N=0 审计结论

v8.22 只改变 canonical migration matrix 的 active pilot 归属和诊断 gate：`generatedArtifacts` 是唯一 active pilot，`libraryMetadata` 不再 active，但其 observation complete 或 retirement candidate ready 仍是前置条件。当前同步状态机 owner 不变；iPhone `performTick`、Mac `/sync/inventory`、legacy diff、旧 generated artifact request/apply route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。

guarded commit seam 只做 gate evaluation 和 report。iPhone seam 复用已加载的 local/peer inventory、canonical manifest、canonical sync/apply/library plan、generated artifact read-side/template/observation/cutover evidence 和 legacy artifact action snapshot；Mac seam 复用本地 inventory/canonical manifest，缺 peer snapshot 时阻断。两端都不扫描额外目录，不读取 artifact 正文，不写 store，不改变 plan 或 response。

canary budget 固定为 0；任何 allowed 结果都必须转成 `allowedButCanaryBudgetZero` / commit skipped。v8.22 不调用 `/sync/artifact-request`、不下载 generated artifact、不 apply、不写 production root、不 commit、不创建 upload job、不自动下载 audio、不 suppress legacy duplicate、不改 read path/UI、不新增 route、不切 runtime switch、不改 retry drainer 或 Mac pending sync。旧 artifact request/apply path 只作为 legacy fallback 保留，不能被 v8.22 seam 触发。

gate blocker 必须覆盖 missing evidence、unsupported artifact kind、content leak、unsafe path、parent tombstone、audio confusion、missing peer snapshot、非 generated artifact domain、N1/staged/allEligible/runtime switch/default enablement、缺 owner token、缺 rollback/root-bound apply/legacy fallback/evidence。diagnostics 只能写 redacted status/reason/count/hash prefix/kind；不得写完整 transcript/note/summary/provider response、完整 hash、绝对路径、request/response body、secret、fingerprint 或用户内容。

## 2026-06-05 v8.21 generatedArtifacts template / next-pilot candidate 审计结论

v8.21 不改变当前同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory`、legacy diff、generated artifact request/apply route、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状；新增 generatedArtifacts read-side seam 默认 disabled。

read-side projection 只服务 generated artifact 的 metadata/availability 对照。它可以报告 transcript/note/summary JSON/Markdown 的 availability、byte size、hash prefix、producer 和 safe token summary；不得读取或输出正文、完整 hash、真实路径、audio bytes、provider response 或用户内容。audio 混入会成为 `audioConfusionRisk`，canonical 不支持的 `summaryMarkdown` 会成为 `unsupportedArtifactKind`。

双端 seam 只消费 sync/inventory 已经持有的 facts。iPhone 复用 local/peer `LocalNetworkSyncInventory` 与 canonical manifest；Mac 复用本机 inventory 与 canonical manifest。启用时只记录 redacted diagnostics，不下载 artifact、不 apply、不写 store、不写 `receive.json`、不创建 upload/apply job、不启动 transcription/note generation、不改 UI、不改 inventory response、不改 route/security、retry 或 pending sync。

matrix 中 `generatedArtifacts.nextPilotCandidate` 只是下一试点候选状态。它必须等到 `libraryMetadata` observation complete 或 retirement candidate ready 后才允许出现；不是 active pilot，不是 canary/cutover，不打开 runtime switch，不允许 duplicate suppression 或 legacy retirement。`libraryMetadata` 仍是唯一 active pilot，audio/tombstone/legacy retirement 保持 static/default-off。

## 2026-06-05 v8.20 libraryMetadata observation window / retirement candidate gate 审计结论

v8.20 只增加 observation window、observation gate、rollback drill summary、E2E pilot report 和 report-only retirement candidate gate，不改变当前同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory`、legacy diff、retry drainer、Mac pending sync、upload ledger、inventory response、默认 UI read path 和 legacy store/write path 仍保持原状。

observation policy 默认 disabled。显式 internal/test policy 下，window 只记录现有 write-side/read-side 结果中的计数：canonical commit attempt/success/failure、rollback success/failure/fatal、legacy fallback、duplicate suppression、canonical read candidate/read served、legacy read fallback、parallel divergence、unsupported/path leak 和 unsafe side effect。记录过程不调用 executor、不读取真实资源目录、不写 store、不发送网络、不创建 upload job、不移动资源、不写 standalone note content、不改 UI。

observation gate 要求：唯一 active pilot 为 `libraryMetadata`，其它 domain static/default-off；write/read evidence 足够；legacy fallback 可用；divergence、rollback failure/fatal、unsupported/path leak、resource move、content write、tombstone/delete、sync/upload、UI mutation 均为 0；runtimeSwitch=false；default/release cutover=false。任何 blocker 都只能使 retirement candidate blocked，不得 fallback 成 silent success。

retirement candidate gate 仍 report-only。candidate ready 不会删除 legacy planner/inventory/store/route/read implementation，不会禁用 fallback，不会切默认 canonical read/write，不会把 `libraryMetadataPilotComplete` 改成 true，也不会启用 generatedArtifacts、tombstoneConflict、audioUpload、recordingMetadata、uiProjection 或 legacyRetirement。下一步必须先人工审计 v8.20 observation report。

## 2026-06-05 v8.19 libraryMetadata guarded read-side cutover seam 审计结论

v8.19 只给 `libraryMetadata` pilot 增加 guarded read-source seam，不改变当前同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory`、legacy diff、retry drainer、Mac pending sync、upload ledger、inventory response 和默认 UI read path 仍保持 legacy；新增 read source 默认 mode 是 `legacy`。

read source mode 语义：`legacy` 直接返回 legacy output；`parallelCompare` 返回 legacy output 并记录 read diff；`canonicalCandidate` 构建 canonical output 但不服务 UI；`guardedCanonicalRead` 只有 explicit internal/test config + gate allowed 才返回 canonical metadata-only output。gate blocked、canonical projection missing、unsupported/path leak、divergence、fallback missing、write-side evidence 缺失或 canonical read exception 均显式 fallback legacy。

read cutover gate 要求 `libraryMetadata` 是唯一 active pilot，write-side canary evidence success、rollback fatal count 为 0、read-side divergence count 为 0、unsupported count 为 0、pathLeakRisk count 为 0、legacy fallback available、canonical projection complete、objectID stable、no resource move、no content write、no tombstone/delete candidate、no unresolved conflict、UI cutover not global、runtimeSwitch=false。其它 domain 仍 static/default-off；generatedArtifacts、tombstoneConflict、audioUpload、recordingMetadata 都没有 read cutover。

双端 seam 只消费已加载的 legacy/canonical manifest facts；不创建 upload job、不触发 sync/upload、不改 receive.json、不改 audio inbox、不启动 transcription/note generation、不写 standalone note content、不移动 audio/transcript/note/summary/resource 文件、不新增 route、不绕过 `RequestVerifier`、TLS/HMAC/nonce/body hash 或 Keychain。retirement candidate 更新仍 report-only，不删除或禁用 legacy。

## 2026-06-05 v8.18 libraryMetadata production canary N=1 审计结论

v8.18 只给 `libraryMetadata` pilot 增加显式 production canary wrapper 和 app bootstrap，不改变同步状态机 owner。iPhone `performTick`、Mac `/sync/inventory`、legacy diff、retry drainer、Mac pending sync、upload ledger、inventory response 和 UI 默认路径仍保持原状；本轮新增 bootstrap 没有被默认 app construction 自动调用。

执行 gate 仍是严格 N=1：domain 必须是唯一 active pilot `libraryMetadata`，`canaryMaxObjectsPerSyncRun == 1`，explicit internal/debug configuration、owner-approved token、rollback plan、NoCommit/dry-run/execution-shadow/real-data-shadow/read-side parallel evidence、non-dry-run root-bound apply port、legacy fallback、local/peer snapshot 和注入 executor 都必须存在。N>1、allEligible、runtime switch、release/default enablement、非 libraryMetadata active pilot、view refresh、retry drainer、缺 peer snapshot 或缺 read-side equivalence 都 blocked/fallback。

`.canaryN1Armed` 只能证明注入链路可配置，不能 commit；`.canaryN1Execute` 成功时也只执行一个 metadata-only folder/studyItem/standalone note candidate。成功后才 suppress matching legacy libraryMetadata duplicate；失败、rollback、unsafe/no eligible、gate blocked 或 fatal blocker 不 suppress，legacy fallback 保留。observation report 不驱动 plan、read model、UI、upload、retry 或 Mac pending sync。

production root guard 仍保持默认关闭。test-root 显式注入可构造 real apply port；production root 只有 explicit root mode 且 `allowProductionRootWrites=true` 才允许进入后续 gate，否则记录 `productionRootWritesDisabled`/real apply blocker。v8.18 不新增 route、不改 `RequestVerifier`、TLS/HMAC/nonce/body hash、Keychain、Mac receiver route、安全边界、standalone note content、resource move、audio upload、tombstone/delete/GC 或 legacy retirement。

## 2026-06-05 v8.16 libraryMetadata expanded canary 审计结论

v8.16 只扩展 `libraryMetadata` pilot 的 canary 深度，不改变同步状态机 owner。iPhone `performTick` 仍先生成 legacy diff；显式 expanded stage canary 在 legacy diff 后、最终 duplicate suppression 前执行。Mac `/sync/inventory` 仍缺 peer snapshot，真实 app seam 只记录 stage blocker/fallback/observation diagnostics 并返回原 response。

stage gate 要求顺序证据：N3 需要 clean N1 observation，N10 需要 clean N3 observation，allEligible 需要 clean N10 observation。每个 previous-stage evidence 必须包含完整 observation window、成功计数、无 failure/rollback failure/blocking divergence/unresolved conflict/postcondition failure/unsupported object/resource move/hierarchy cycle/objectID instability/read-side divergence，并继续要求 NoCommit、dry-run equivalence、execution shadow、real-data shadow copy、read-only transport probe、rollback plan、root-bound non-dry-run apply port、legacy fallback 和 owner-approved token。

candidate selector 仍只允许 metadata-only folder/studyItem/standalone note apply/send。多候选按 object kind、objectID、actionID 稳定排序，顺序执行；第一个失败 candidate 会 rollback 并停止后续候选。成功 candidate 的 duplicate legacy suppression 是 success-only 且 per-candidate；失败、未执行、跳过、no eligible、Mac peer snapshot unavailable 或 gate blocked 都保留 legacy fallback。

read-side parallel 仍只是 affected-object diagnostics，不驱动 UI/read path。v8.16 不新增 route、不发送 `/sync/apply-metadata` 以外的新路径、不改 `RequestVerifier`、TLS/HMAC/nonce/body hash、Keychain、Mac pending sync、retry drainer、upload runtime、standalone note content、resource file、physical/permanent delete、tombstone GC、audio/generated/recordingMetadata。allEligible 仍限本 run 的 `libraryMetadata` eligible candidates，不是全域 runtime switch。

## 2026-06-05 v8.15 libraryMetadata canary N=1 审计结论

v8.15 只给 `libraryMetadata` pilot 增加显式 internal N=1 canary，不改变同步状态机整体 owner。iPhone `performTick` 仍先生成 legacy diff；显式 N=1 canary 在 legacy diff 后、最终 duplicate suppression 前执行，且每个 sync run 最多提交 1 个 safe metadata candidate。Mac `/sync/inventory` 仍缺 peer snapshot，真实 app seam 只记录 peer-snapshot-unavailable blocker/fallback diagnostics 并返回原 response。

N=1 gate 要求：v8.13 matrix 仍只有 `libraryMetadata` active pilot；v8.14 N0/no-execution evidence 已存在；配置为 `.canaryCommit`、`canaryMaxObjectsPerSyncRun == 1`、`allowsInternalN1Execution == true`、`explicitInternalTestConfiguration == true`；owner-approved token、rollback plan、NoCommit/dry-run/execution-shadow/real-data-shadow/read-side parallel evidence、non-dry-run root-bound apply port 和 legacy fallback 均齐全。N>1、allEligible、runtime switch、非 libraryMetadata active pilot、缺 executor/evidence/peer snapshot 都 blocked/fallback。

candidate selector 只允许 folder/studyItem/standalone note metadata apply/send。folder rename/color metadata、studyItem tag/filing/folder membership metadata、standalone note title/tags/filing metadata 可作为 safe metadata-only candidate；resource token/path 变化、folder hierarchy mutation、standalone note content bytes、tombstone/delete、conflict、cycle、parent missing、objectID instability、view refresh 和 retry drainer 不提交。成功后才 suppress 同 object/action 的 duplicate legacy metadata action；失败、rollback、no eligible、Mac peer snapshot unavailable 或 gate blocked 不 suppress。

v8.15 不新增 route、不发送 `/sync/apply-metadata`、不调用 `StudyLibraryStore.applySyncManifest`、不改 `RequestVerifier`、TLS/HMAC/nonce/body hash、Keychain、Mac pending sync、retry drainer、upload runtime、UI/read-side owner、physical delete/permanent delete/tombstone GC 或资源文件位置。read-side parallel diagnostics 只记录 equivalence/divergence 与 `mutatedUI=false`，不驱动 UI。

## 2026-06-05 v8.14 libraryMetadata guarded commit seam N=0 审计结论

v8.14 不改变当前同步状态机的 owner。iPhone `performTick` 仍由 legacy/canonical planner 的既有选择逻辑输出最终 plan；Mac `/sync/inventory` 仍返回原 inventory response；metadata manifest bridge、generated artifact request/apply、audio upload、retry drainer、Mac pending sync 和 UI read path 仍按现有 legacy 链路运行。

新增的 `CanonicalLibraryMetadataGuardedCommitSeam` 只在显式 `.guardedExecuteCommit` 或 `.canaryCommit` 配置下评估 `libraryMetadata` N=0 gate。它会输出 evidence report、gate decision、no-execution assertion、N1 readiness report 和 redacted diagnostics，但不会调用 executor、不会调用 real apply port、不会发送 `/sync/apply-metadata`、不会调用 `applySyncManifest`、不会写 production root、不会 suppress duplicate legacy action。

iPhone seam 使用 legacy diff 后已经构造出的 local/peer canonical manifest、library plan、candidate 和 legacy action snapshot；评估后固定保留 legacy fallback，duplicate suppression report 固定为空。Mac seam 因 inventory route 缺 peer snapshot，会记录 missing peer snapshot blocker/readiness gap，并继续返回原 response。两端都不改 route/security、pending sync、upload/audio/generated artifact、tombstone/conflict、UI 或 read-side owner。

N=0 状态诊断必须同时表达 `canonicalLibraryMetadataV814CanaryBudgetZero`、`canonicalLibraryMetadataV814CommitNotExecuted`、`canonicalLibraryMetadataV814LegacyFallbackPreserved`、`canonicalLibraryMetadataV814DuplicateSuppressionNotApplied`，以及 `canonicalLibraryMetadataCanaryBudgetZero`、`canonicalLibraryMetadataGateAllowedButNoExecution`、`canonicalLibraryMetadataCommitSkippedBecauseCanaryBudgetZero`。这些诊断只能作为 v8.14 report-only evidence，不能作为 N1 执行许可。

## 2026-06-05 v8.13 migration matrix / pilot selection 审计结论

v8.13 不改变当前同步状态机。iPhone `performTick`、Mac `/sync/inventory`、metadata manifest bridge、generated artifact request/apply、audio upload、retry drainer、Mac pending sync 和 UI read path 仍由 legacy 链路负责。新增的 `CanonicalMigrationDomainMatrix`、`CanonicalMigrationGlobalConfigValidator`、`CanonicalLibraryMetadataPilotReport` 和 `CanonicalOtherDomainsStaticAuditReport` 都是 diagnostics/test-only 模型，不会触发 canary、production commit、网络发送、store 写入、legacy duplicate suppression 或 read-side cutover。

当前唯一 active pilot domain 是 `libraryMetadata`。其它 domain 的同步状态在 v8.13 固定为 static-review-only/default-off：`recordingMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload` 只能继续做代码完整性、静态审查、测试补齐和 blocker 报告。`audioUpload` 仍由现有 `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` 与 Mac resumable routes 负责，不由 canonical 自动创建 job、自动下载或 suppress legacy。

global guard 的 violation 规则用于防误配：多个 active canary domain、active domain 不是 `libraryMetadata`、`runtimeSwitchEnabled=true`、release/default cutover enabled、pilot 完成前启用 `generatedArtifacts` / `tombstoneConflict` / `audioUpload`、以及 read-side cutover 前 legacy retirement 都必须阻断。该 guard 不替代 `RequestVerifier`、TLS pinning、HMAC、nonce、body hash、Keychain 或 route allowlist。

`libraryMetadata` pilot 的下一步只能从 N0 gate 开始，后续顺序是 N1 canary、expanded canary、domain write cutover、read-side parallel、read-side cutover、retirement candidate。read-side parallel 仍只做投影与诊断，不能驱动 UI/sync/upload。legacy fallback 在整个 pilot 和观察期内保留；commit 成功前不得 suppress duplicate legacy action。

## 1. 当前真实状态总览

现有源码确认：录音音频上传决策模型继续收敛在两端 `StudyLibrarySyncModels.swift` 中的 `RecordingAudioUploadDecisionEvaluator`。它能区分本地音频、对端音频、transfer job、upload ledger 和触发来源，并能把 view refresh 抑制为不创建上传任务。Canonical Sync Truth v1 只在此 evaluator 之前生成 recording audio bootstrap candidate，不绕过 evaluator 或 upload coordinator。

Mac 侧“立即同步”仍不是直接拉起 iPhone 同步，而是写入 pending sync request，等待 iPhone 前台 heartbeat/probe 取到 `/connection/heartbeat` 响应中的 `syncStartSignal` 后再排队 tick。现有源码已有 pending 去重、超时、iPhone ack、tick started/completed/failed 诊断，但 iPhone 不活跃、心跳没有运行、presence 不在线、用户断开连接、backoff/并发 gate 命中时，Mac 仍不能单方面完成同步。

上传链路保持 metadata/audio 主路径不变。状态收敛规则已调整：peer unknown 在普通 sync 中 deferred，显式用户上传才 manual force；peer hash/size 不同现在进入 conflict/fatal，不覆盖 Mac 既有音频；retryable failure 到期后由 retry drainer 重新进入 `RecordingUploadCoordinator.uploadAndWait` 主路径。

本轮 Canonical Kernel Completion v1 补充在上述旧运行时上增加窄桥接：`RokuricsShared/SyncCore/CanonicalCore.swift`、`CanonicalProjectionContract.swift`、`CanonicalSyncPlanner.swift`、`CanonicalApplyPlan.swift`、`CanonicalLibraryObject.swift`、`CanonicalLibrarySyncPlanner.swift`、`CanonicalTransferStateMachine.swift`、`CanonicalObjectProjection.swift`、`CanonicalInventoryBuilderContract.swift`、`CanonicalRetirementReadiness.swift`、`CanonicalShadowDiagnostics.swift`、`IPhoneCanonicalRecordingAdapter`、`IPhoneCanonicalLibraryAdapter`、`MacCanonicalRecordingAdapter`、`MacCanonicalLibraryAdapter` 生成双端 `CanonicalManifest`、shadow report、planner diagnostics、apply diagnostics、inventory coverage、transfer projection、object projection 和 readiness diagnostics。v8.38 后，iPhone `performTick` 默认仍由 legacy plan 拥有决策；只有 explicit debug/internal `CanonicalSyncRuntimeConfiguration.canonicalPlanPrimaryWithLegacyFallback` 且 authority gate 全部通过时，canonical sync/apply/library plan 才可作为启用 metadata/library/recording-existence scope 的 decision owner。缺 canonical manifest、schema 不匹配、manifest invalid、conflict、unsupported、peer unknown 或任何 blocker 都使用 legacy fallback 并记录 runtime fallback/blocked diagnostics。

Rokurics 当前仍不是完整统一同步内核，iPhone recording model、Mac audio inbox model、Mac study item model、sync inventory/manifest、UI display state 仍并存。Canonical v8.38 只让 canonical metadataHash/modifiedAt/LWW 在受控 metadata scope 中成为可选 decision truth；执行仍桥接到 legacy `/sync/apply-metadata`、`StudyLibraryStore.applySyncManifest`、`/sync/artifact-request`/apply，且本轮不执行 production apply。它仍不接管 audio upload runtime、UI state、retry drainer、Mac pending sync、`applySyncManifest` 内部写入、`receive.json` 写入、wire protocol、route/security 或物理存储。下一阶段 v8.39 才应讨论 apply/existence bridge。

本轮 Canonical Production Runtime API & Port Contract v1 只新增 production-facing facade、真实 production port 方法合同、execution guard、rollback contract 和 redacted side-effect/result model。`CanonicalKernelFacade.executeProduction` 只有在显式 `productionExecute` mode、token owner approval、rollback plan、dry-run equivalence、non-dry-run ports、无 unresolved conflict 且 migration gate 放行时才会调用 port；当前没有任何 iPhone/Mac sync trigger、UI、heartbeat、retry drainer 或 Mac pending sync 调用它。测试中的 fake production ports 只验证合同，不代表真实 route/client/store 已迁移。

本轮 Canonical Production Adapter Skeletons & Migration Facade v1 新增双端 file/transport/upload/apply adapter skeleton 和 migration facade。它们默认 disabled，只在测试显式 fake/temp-root/in-memory port set 中验证 root-bound file token、existing-route transport projection、resumable upload ledger 和 in-memory apply result。没有修改 `performTick` 触发、retry drainer、Mac pending sync、UI、upload route、真实 network send、真实 upload job、真实 file/store 写入或 `applySyncManifest` / `receive.json` 写入。

本轮 Canonical v8.1 Read-Only Transport Probe Live Wiring 在 v8.0 no-commit seam 之后增加默认关闭的 live read-only probe。iPhone 侧只在 explicit internal config 下复用现有 signed request/TLS pinning/HMAC/timestamp/nonce/body hash 发送 marked read-only request；Mac 侧只在现有 route handling 中识别 marker 并记录 audit。它不新增 route、不扩大 mutating allowlist、不改变 legacy plan、canonical production plan、retry drainer、Mac pending sync、UI、upload/apply/store、`receive.json` 或 runtime switch。

本轮 Canonical v8.2 NoCommit Hardening & Migration Config Consolidation 只加固 NoCommit staging/evidence 层。NoCommit executor 默认写系统临时 staging root 并立即 cleanup，可显式 bounded retain diagnostics；生产 root 或其子路径会被拒绝。runner 新增 structured evidence report 和 migration stage summary diagnostics，但不调用 `guardedExecuteCommit`、`productionExecute`、`/sync/apply-metadata`、`applySyncManifest`、upload client、真实 store 或 duplicate suppression，也不改变 legacy plan、canonical current production plan、retry drainer、Mac pending sync、route/security 或 UI。

本轮 Canonical v8.3 Recording Metadata Commit Executor 只把 `recordingMetadata` 单域 Commit executor 做到可测试执行。iPhone/Mac 默认 executor 仍绑定 disabled/dry-run production ports，真实 app 默认以 internal fake apply-port requirement 阻断；只有测试或内部配置显式注入 fake non-dry-run apply/transport port 时，才会执行 `applyMetadata` 或通过既有 `/sync/apply-metadata` projection 执行 `sendMetadata`。真实同步状态没有切换：legacy planner、inventory、metadata manifest bridge、upload coordinator、retry drainer、Mac pending sync、UI、route/security 和真实 store 仍是 production owner。

v8.3 commit 成功后只 suppress 同 action 的 duplicate legacy recording metadata；canary 默认 `N=0`，gate blocked、budget exhausted、precondition/postcondition/transport/apply/rollback failure 都保留 legacy fallback。当前真实 `StudyLibraryStore` 缺少 single-object checkpoint/rollback API，所以真实 store commit 仍不可安全启用；本轮没有实现 audio/generated/folder/studyItem/UI、retry drainer、Mac pending sync、legacy retirement 或性能优化。

本轮 Canonical v8.4 Commit Failure Injection & fakeInMemory Hardening 没有扩大 production 接入，只强化 fake/in-memory path。failure injection 覆盖 duplicate/idempotent replay、unsupported/unexpected side effect 和 missing rollback checkpoint；fake apply port 记录内存 checkpoint/action/object state，支持 clean commit、pre/postcondition mismatch、apply before/after partial failure、rollback success/failure、idempotent same action、unrelated object untouched 和 redacted side-effect trace。该能力不写真实 root、不调用 `applySyncManifest`、不发送真实 route、不创建 upload job、不改 legacy fallback；v8.5 才讨论 real root-bound recordingMetadata apply port。

本轮 Canonical v8.5 Real Root-Bound RecordingMetadata Apply Port 增加了真实 root-bound metadata write 能力，但仍没有扩大真实同步状态机接入。双端 apply port 只有在测试/内部显式 `testRootURL` 构造时才写 temp/test root；默认构造和 disabled port set 继续 dry-run/disabled，`productionRootURL` 默认 `productionRootDisabled`。root-bound core 只对 `recordingMetadata` metadata bytes 做 checkpoint、atomic replace、read-back verification 和 rollback restore，diagnostics/side-effect trace 只写 redacted hash prefix、byte count、checkpoint id 和 failure 分类。本轮没有接 iPhone tick、Mac inventory、UI、retry drainer、Mac pending sync、upload route、安全 route、`applySyncManifest`、`receive.json` 或 legacy duplicate suppression。

本轮 Canonical v8.6 App Seam Guarded Commit Wiring 只把 guarded commit report 接入 iPhone tick 和 Mac inventory 的诊断路径。显式 `guardedExecuteCommit` / `canaryCommit` 配置会评估 recordingMetadata gate、evidence report、root-bound apply readiness、transport readiness、rollback readiness 和 canary `N=0`，但 runner 没有 executor，不调用 production port，不写 production root，不发网络，不调用 `applySyncManifest`，不 suppress duplicate legacy，不改变 legacy/canonical plan、Mac inventory response、retry drainer、Mac pending sync、UI 或 upload/security route。NoCommit seam 只在 `.guardedExecuteNoCommit` 下运行，commit-mode canary 不再同时发出 NoCommit diagnostics。

本轮 Canonical v8.7 RecordingMetadata Canary N=1 在 iPhone tick 中增加 explicit internal canary 执行分支。默认仍 disabled/`N=0`；只有 `.canaryCommit`、`canaryMaxObjectsPerSyncRun == 1`、`allowsV87CanaryN1InternalExecution == true` 且存在注入 executor 时，才会在 legacy diff 后、canonical/legacy plan 选择前调用 `CanonicalRecordingMetadataCutoverRunner`。selector 每 run 只选择一个 `recordingMetadataApply` 或 `recordingMetadataSend` candidate；`N>1`、缺内部开关、view refresh、retry drainer、unsupported domain/action、证据不足、unresolved/tombstone conflict、缺 rollback checkpoint、非 root-bound apply port、send 缺 read-only probe、已失败 action 都 blocked。成功后仅在最终 diff plan 上 suppress 同 object/action 的 metadata action；失败、rollback 或 fallback 不 suppress。Mac 侧仍只做 v8.6 report，不新增 route，不改 `RequestVerifier`/TLS/HMAC/nonce/body-hash/pending sync。

本轮 Canonical v8.9 Generated Artifacts Domain Migration 在 generated artifact 域增加 default-off NoCommit、root-bound apply port、commit executor 和 app diagnostics seam。范围只限 transcript JSON/Markdown、note Markdown/JSON、summary JSON；Mac 仍是 authoritative producer，iPhone 已下载 artifact 只证明本地 availability。iPhone tick seam 默认 disabled/`N=0`，显式 NoCommit 只写 staging summary，显式 N=1 需要内部开关与注入 executor，commit 成功后才 suppress 同 artifact legacy `/sync/artifact-request` action。Mac `/sync/inventory` 因缺 peer snapshot 只 report/fallback。v8.9 不新增 route、不改 security、不卡 UI、不创建 generated artifact upload job、不自动下载 audio、不迁移 retry drainer/Mac pending sync/folder/studyItem/tombstone/delete/legacy retirement。

本轮 Canonical v8.10 Folder and StudyItem Metadata Domain Migration 在 folder/studyItem/standalone note metadata 域增加 default-off NoCommit、root-bound apply port、commit executor 和 app diagnostics seam。iPhone tick seam 默认 disabled/`N=0`，显式 NoCommit 只写 staging summary，显式 canary 需要内部 N=1 或 staged canary policy、完整 evidence、owner-approved token 与注入 executor；commit 成功后才 suppress 同 folder/studyItem metadata legacy action。Mac `/sync/inventory` 因缺 peer snapshot 只 report/fallback。v8.10 不移动资源文件、不新增 route、不改 security、不切 UI、不迁移 audio/generated artifact/recordingMetadata/tombstone GC/conflict execution/retry drainer/Mac pending sync/legacy retirement。

本轮 Canonical v8.11 Tombstone and Conflict Domain Migration 在 soft tombstone/conflict record 域增加 default-off NoCommit、root-bound tombstone/conflict marker/ledger apply port、commit executor、app seam configuration、canary stage gate 和 success-only legacy duplicate suppression model。iPhone/Mac 默认路径仍不执行 v8.11 commit；显式 NoCommit 只写 staging summary 并记录 production commit、`applySyncManifest`、network send、receive JSON mutation、generated artifact deletion、audio deletion、physical delete、permanent delete、tombstone GC 和 legacy suppression 全部被抑制。显式 commit 只允许 test-root marker/ledger JSON，side effect 仅 `.tombstoneMark`/`.conflictRecord`，成功后才可 suppress 同 object/domain/action/conflict kind 的 duplicate legacy action。`resurrectionBlocked` 是 anti-resurrection ledger action；physical/permanent delete、tombstone GC、unsupported restore、ambiguous conflict policy、真正 stale live resurrection risk 和 generated artifact tombstone apply 都 blocked。v8.11 不改 iPhone tick 默认 plan、Mac inventory response、route/security、audio upload、generated artifact download/apply、folder/studyItem metadata、UI、retry drainer 或 Mac pending sync。

本轮 Canonical v8.12 Audio Upload Runtime Shadow and Canary Preparation 只增加 default-off/shadow-only 的 audio upload cutover preparation。共享 `CanonicalAudioUploadCutover.swift` 把 local/peer/ledger/retry/trigger truth 建模为证据报告、candidate、gate、NoCommit、shadow receiver/rehearsal、abort/rollback policy 和 read-side projection；iPhone/Mac 新增纯 no-commit executor，并把 app seam 接到 iPhone tick 与 Mac inventory diagnostics 路径但默认 disabled。显式启用时也不创建真实 upload job、不调用 `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient`、不写 Mac inbox/`receive.json`、不改 upload ledger/retry drainer/Mac pending sync/UI、不 suppress legacy。completed ledger、metadata uploaded、receive record 和 UI uploaded 都被记录为不能单独 no-op；peer unknown deferred；peer missing/metadataOnly 只做 shadow/canary candidate；different hash/size conflict；canary N>0 在 v8.12 blocked。

## 2. 审计范围与证据

只读检查过的关键源码：

- iPhone app 与连接：`Rokurics/RokuricsApp.swift`、`Rokurics/MacConnectionView.swift`。
- iPhone 录音 UI：`Rokurics/RecordingLibraryView.swift`、`Rokurics/RecordingStudyDetailPage.swift`、`Rokurics/StudyReadingPages.swift`。
- iPhone 学习库与录音 metadata：`Rokurics/StudyLibraryStore.swift`、`Rokurics/RecordingMetadata.swift`、`Rokurics/RecordingUploadStatus.swift`。
- iPhone 上传：`Rokurics/RecordingUploadCoordinator.swift`、`Rokurics/RecordingUploadClient.swift`、`Rokurics/SecureMacUploadClient.swift`。
- iPhone 同步：`Rokurics/StudyLibrarySyncCoordinator.swift`、`Rokurics/StudyLibrarySyncModels.swift`、`Rokurics/ConnectionSyncStateStores.swift`。
- Canonical sync：`RokuricsShared/SyncCore/CanonicalCore.swift`、`RokuricsShared/SyncCore/CanonicalProjectionContract.swift`、`RokuricsShared/SyncCore/CanonicalSyncPlanner.swift`、`RokuricsShared/SyncCore/CanonicalApplyPlan.swift`、`RokuricsShared/SyncCore/CanonicalLibraryObject.swift`、`RokuricsShared/SyncCore/CanonicalLibrarySyncPlanner.swift`、`RokuricsShared/SyncCore/CanonicalTransferStateMachine.swift`、`RokuricsShared/SyncCore/CanonicalObjectProjection.swift`、`RokuricsShared/SyncCore/CanonicalInventoryBuilderContract.swift`、`RokuricsShared/SyncCore/CanonicalRetirementReadiness.swift`、`RokuricsShared/SyncCore/CanonicalShadowDiagnostics.swift`、`RokuricsShared/SyncCore/CanonicalProductionPorts.swift`、`RokuricsShared/SyncCore/CanonicalProductionExecution.swift`、`RokuricsShared/SyncCore/CanonicalKernelFacade.swift`、`Rokurics/IPhoneCanonicalRecordingAdapter.swift`、`Rokurics/IPhoneCanonicalLibraryAdapter.swift`、`RokuricsMac/MacCanonicalRecordingAdapter.swift`、`RokuricsMac/MacCanonicalLibraryAdapter.swift`。
- Canonical generated artifact cutover：`RokuricsShared/SyncCore/CanonicalGeneratedArtifactCutover.swift`、`Rokurics/IPhoneGeneratedArtifactNoCommitExecutor.swift`、`Rokurics/IPhoneGeneratedArtifactRealApplyPort.swift`、`Rokurics/IPhoneGeneratedArtifactCutoverExecutor.swift`、`RokuricsMac/MacGeneratedArtifactNoCommitExecutor.swift`、`RokuricsMac/MacGeneratedArtifactRealApplyPort.swift`、`RokuricsMac/MacGeneratedArtifactCutoverExecutor.swift`、`RokuricsTests/CanonicalGeneratedArtifactCutoverTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactCutoverTests.swift`。
- Canonical production adapter skeletons：`Rokurics/IPhoneCanonicalProductionFilePort.swift`、`Rokurics/IPhoneCanonicalProductionTransportPort.swift`、`Rokurics/IPhoneCanonicalProductionUploadPort.swift`、`Rokurics/IPhoneCanonicalProductionApplyPort.swift`、`Rokurics/CanonicalIPhoneMigrationFacade.swift`、`RokuricsMac/MacCanonicalProductionFilePort.swift`、`RokuricsMac/MacCanonicalProductionTransportPort.swift`、`RokuricsMac/MacCanonicalProductionUploadPort.swift`、`RokuricsMac/MacCanonicalProductionApplyPort.swift`、`RokuricsMac/CanonicalMacMigrationFacade.swift`。
- Canonical v8.3 recording metadata commit：`RokuricsShared/SyncCore/CanonicalRecordingMetadataCutover.swift`、`Rokurics/IPhoneRecordingMetadataCutoverExecutor.swift`、`RokuricsMac/MacRecordingMetadataCutoverExecutor.swift`、`RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataCommitExecutorTests.swift`。
- Mac 连接和 UI：`RokuricsMac/MacIPhoneConnectionView.swift`、`RokuricsMac/AudioInboxStore.swift`、`RokuricsMac/MacRecordingInboxItem.swift`、`RokuricsMac/MacStudyLibraryView.swift`。
- Mac 接收和 inventory：`RokuricsMac/MacRecordingFileStore.swift`、`RokuricsMac/RecordingReceiveResult.swift`、`RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`、`RokuricsMac/RequestVerifier.swift`。
- Mac 同步模型：`RokuricsMac/StudyLibrarySyncModels.swift`、`RokuricsMac/ConnectionSyncStateStores.swift`。
- 测试：`RokuricsTests/RokuricsTests.swift`、`RokuricsMacTests/RokuricsMacTests.swift`、`RokuricsMacTests/StudyLibrarySyncTests.swift`、`RokuricsMacTests/StudyLibraryStoreTests.swift`。

## 3. 层次边界

连接层只负责配对、presence、heartbeat、pending sync hint 和 signed HTTPS 请求。它不应决定某条录音是否需要上传。

同步层负责 inventory、diff、metadata/artifact apply/download，以及把“对端缺少音频”的事实转成 upload candidate。它必须使用对端 inventory 的音频 hash/size 作为最终 no-op 依据。

上传层负责实际 metadata/audio 上传、resumable session、ledger、progress 和失败分类。它不能把 metadata 上传成功等同于 Mac 已有 audio。

UI 层只能展示状态和触发显式用户动作。列表、详情、文件夹、学习库 refresh 不能创建上传任务。

## 4. 当前同步状态模型表

| 状态维度 | 当前模型/字段 | 主要来源 | 当前含义 | 风险 |
| --- | --- | --- | --- | --- |
| 本地音频 | `RecordingLocalAudioState` | iPhone inventory builder、upload coordinator | unknown/missing/unreadable/available/deleted | hash 已加 cache/off-main 计算，但大库 inventory 仍需观察 |
| 对端音频 | `RecordingPeerAudioState` | Mac `/sync/inventory` | unknown/missing/metadataOnly/available/different/deleted | unknown 普通 sync deferred；missing/metadataOnly 会补传；different 视为冲突 |
| 传输任务 | `RecordingTransferJobState` | `LocalNetworkSyncTransferJobStore` | queued/inFlight/finalizing/completed/failed/retryPending | retryPending 抑制普通新任务，retry drainer 到期后驱动上传 |
| 上传账本 | `RecordingUploadLedgerState` | `RecordingUploadJobStore` | none/queued/inFlight/finalizing/completed/failed/retryPending/fatalFailed | completed 不能单独作为 no-op，必须和 peer hash/size 匹配 |
| metadata 状态 | `RecordingUploadStatus`、`RecordingMetadataSyncState` | metadata JSON、sync manifest | localOnly/uploading/uploaded/failed 或 metadata-only/synced | metadata uploaded 不代表 audio uploaded |
| canonical manifest | `CanonicalManifest`、`CanonicalRecordingObject`、`CanonicalArtifact`、`CanonicalLibraryObject` | 双端 inventory adapter | recording metadata hash/modifiedAt、audio hash/size truth、generated artifact hash/size/logical token truth、folders/studyItems/standalone notes/tombstones/capabilities | optional；缺失/不兼容必须 fallback legacy |
| canonical apply plan | `CanonicalApplyPlan`、`CanonicalApplyAction` | iPhone canonical planner 后置桥接 | recording/folder/study item metadata apply/send、generated artifact request/apply、object/library tombstone apply/send、artifact tombstone unsupported、conflict record | 只表达语义；执行必须走 legacy route/store |
| canonical library plan | `CanonicalLibrarySyncPlanner`、`CanonicalLibrarySyncAction` | 双端 canonical manifest | folder/study item no-op/apply/send/conflict/tombstone、unsupported fallback | 只桥接 metadata manifest；不改 store schema |
| canonical conflict | `CanonicalConflictRecord` | canonical apply planner | metadata concurrent edit、audio mismatch、generated artifact mismatch、active-vs-tombstone | 只记录并桥接 conflict action，不覆盖文件、不自动解冲突 |
| canonical tombstone | `CanonicalTombstone` | canonical apply planner | soft delete、anti-resurrection、no physical delete、no permanent delete、no GC | 不物理删除 audio/transcript/note/summary，不做 tombstone GC |
| canonical transfer projection | `CanonicalTransferStateMachine` | legacy transfer/upload state strings | queued/in-flight/retry/failure/completed/generated artifact download 等只读 phase | 不修改 upload ledger、retry queue 或 pending sync |
| canonical object projection | `CanonicalObjectProjection` | canonical manifest + plan facts | recordings/generated artifacts/folders/studyItems 的 read-only display facts | 当前不驱动 UI/sync/upload |
| canonical inventory coverage | `CanonicalInventoryBuilderContract` | 调用方已提供 facts | recording/library/tombstone coverage 与 unsupported count | 不做 IO/扫描/hash |
| retirement readiness | `CanonicalRetirementReadiness` | canonical coverage、fallback、conflict、legacy owner 状态 | diagnostics-only gate | 不删除/禁用 legacy |
| canonical kernel facade | `CanonicalKernelFacade` | shared SyncCore API 调用方显式传入的 environment/input | snapshot/manifest/planner/readiness/dry-run/offline/production execute 的稳定外观 API | 默认 disabled；当前无 app trigger 调用 production execute |
| production execution guard | `CanonicalProductionExecutionGuard`、`CanonicalProductionExecutionToken`、`CanonicalProductionExecutionPolicy` | 显式 token、rollback plan、dry-run equivalence、migration gate、port readiness/conflict state | production execute 前置安全门 | 失败时必须 rejection 且 side effects 为空 |
| rollback contract | `CanonicalRollbackPlan`、`CanonicalRollbackCheckpoint`、`CanonicalRollbackAction`、`CanonicalRollbackAudit` | 生产迁移设计显式提供的 checkpoint/action | 描述 file/transport/upload/apply 等 domain 的 rollback 覆盖 | 只是合同；当前不执行真实 store rollback |
| production side effect trace | `CanonicalProductionExecutionResult`、`CanonicalProductionSideEffect`、`CanonicalProductionExecutionTrace` | facade 通过 fake/production port 返回的 redacted result | 记录 operation/domain/result/failure 分类与 redacted target | 不写完整路径、hash、secret、body 或内容 |
| production adapter skeletons | iPhone/Mac `CanonicalProductionFile/Transport/Upload/ApplyPort` | app target adapter skeleton | 默认 disabled，fake/temp-root/in-memory 只用于测试合同 | 不接入真实 route/client/store/apply，不改变 sync 状态机 |
| migration facade | `CanonicalIPhoneMigrationFacade`、`CanonicalMacMigrationFacade` | 双端 app target facade | 组合 snapshot adapter、port set 和 shared facade，默认拒绝 execution | runtime switch false；未接入 performTick/UI/retry/pending sync |
| execution shadow preparation | `CanonicalExecutionShadowPreparationRunner`、双端 shadow file/transport ports、shadow upload/apply ports | 显式 enabled shadow configuration、已加载 local/peer canonical snapshot 与 legacy diff facts | 在 shadow root/shadow receiver/in-memory apply store/read-only transport projection 中排练 file/upload/apply/rollback | 默认关闭；不写真实 store、不发真实网络、不上传、不调用真实 apply、不改变 legacy plan/response |
| v8.1 live read-only probe | `CanonicalLiveReadOnlyTransportProbePolicy`、iPhone live sender、Mac live probe audit | 显式 internal config、现有 signed HTTPS route、probe marker | 可分类、构造 signed envelope，或对 allowed read-only route 发送 marked probe 并记录 no-mutation audit | 默认关闭；只允许 read-only route；不新增 route、不写 receive/upload/apply/store/pending sync |
| v8.2 no-commit staging evidence | `CanonicalNoCommitStagingRootLifecycle`、`CanonicalNoCommitEvidenceReport`、`CanonicalMigrationStageConfiguration` | NoCommit executor staging result、runner diagnostics | 记录 staging root lifecycle/cleanup、equivalence evidence、config stage policy summary | 默认 NoCommit seam 仍关闭；allowed side effect 仅 staging root write/diagnostics，不执行 production commit |
| v8.5 root-bound metadata apply port | `CanonicalRootBoundMetadataWriteCore`、双端 `CanonicalProductionApplyPort(testRootURL:)` | 显式 temp/test root harness | 对 `recordingMetadata` metadata bytes 做 checkpoint、atomic replace、read-back verification、rollback restore 和 redacted trace | 默认 app path 不调用；production root 默认 disabled；不写 audio/generated/folder/studyItem/receive/upload/UI |
| v8.6 guarded commit app seam | `CanonicalRecordingMetadataGuardedCommitSeam`、guarded commit evidence report、canary policy | 显式 `.guardedExecuteCommit` / `.canaryCommit` app seam config | 记录 recordingMetadata gate、evidence/readiness、canary `N=0`、commit not executed、legacy preserved | 默认 disabled；无 executor；不调用 production port/network/applySyncManifest、不 suppress duplicate、不改 plan/response |
| v8.7 recordingMetadata canary N=1 | `CanonicalRecordingMetadataCanarySelector`、`CanonicalRecordingMetadataCutoverRunner`、iPhone injected executor | 显式 iPhone `.canaryCommit` + internal N=1 | 最多 1 个 recording metadata apply/send candidate；成功后 suppress 同 object/action metadata action | 默认 disabled；N>1 blocked；Mac report-only；不改 route/security/UI/retry/Mac pending sync/其他 domain |
| v8.10 library metadata cutover | `CanonicalLibraryMetadataCutoverRunner`、双端 library metadata NoCommit/real apply/commit executor、iPhone tick seam、Mac inventory seam | 显式 app seam config + complete evidence + injected executor | folder/studyItem/standalone note metadata apply/send；成功后 suppress 同 metadata duplicate | 默认 disabled；Mac report-only；不移动资源、不做 tombstone GC、不切 UI、不改 route/security/legacy fallback |
| v8.11 tombstone/conflict cutover | `CanonicalTombstoneConflictCutoverRunner`、双端 tombstone/conflict NoCommit/real apply/commit executor、root-bound marker/ledger core | 显式 app seam config + complete evidence + injected executor | object/library soft tombstone marker、conflict ledger、anti-resurrection record；成功后 suppress 同 tombstone/conflict duplicate | 默认 disabled；只写 test-root marker/ledger；不 physical/permanent delete、不 tombstone GC、不删 audio/transcript/note/summary、不改 route/security/UI/retry/pending sync |
| v8.12 audio upload shadow/canary preparation | `CanonicalAudioUploadCutoverRunner`、双端 audio upload NoCommit executor、shadow receiver/rehearsal wrapper、iPhone tick seam、Mac inventory seam | 显式 app seam config + descriptor/shadow evidence | audio upload evidence/candidate/gate diagnostics；same hash+size no-op proof；missing/metadataOnly shadow candidate；peer unknown deferred；conflict record projection | 默认 disabled/N=0；不创建 upload job、不调用 upload coordinator/client、不中断 legacy fallback、不写 inbox/receive.json/ledger/retry/UI、不改 route/security |
| v8.14 libraryMetadata guarded commit seam | `CanonicalLibraryMetadataGuardedCommitSeam`、`CanonicalLibraryMetadataNoExecutionAssertion`、`CanonicalLibraryMetadataN1ReadinessReport`、iPhone tick seam、Mac inventory seam | 显式 `.guardedExecuteCommit` / `.canaryCommit` app seam config + v8.13 matrix precondition | folder/studyItem/standalone note metadata gate/evidence/readiness diagnostics；canary budget zero；commit skipped；legacy fallback preserved | 默认 disabled/N=0；无 executor；不调用 real apply/applySyncManifest/network；不写 production root；不 suppress duplicate；不改 plan/response/route/security/UI/retry/upload |
| v8.15 libraryMetadata canary N=1 | `CanonicalLibraryMetadataN1CanaryRunner`、`CanonicalLibraryMetadataCanaryConfiguration`、candidate safety/observation report、iPhone N1 seam、Mac peer-missing diagnostics | 显式 iPhone `.canaryCommit` + strict internal N=1 + owner token + evidence + injected executor | 最多 1 个 metadata-only folder/studyItem/standalone note candidate；commit success 后 success-only duplicate suppression；read-side parallel diagnostics | 默认 disabled；N>1/allEligible/runtime switch blocked；Mac inventory peer snapshot unavailable report-only；不改 route/security/UI/retry/upload/read path |
| 展示状态 | `RecordingUploadDisplayState` | evaluator 或 UI presentation | hidden/waiting/preparing/uploading/finalizing/uploaded/failed/retryPending/manualRetryAvailable/conflict/fatalFailed | 展示状态不得反向触发上传 |
| 触发来源 | `RecordingAudioSyncTriggerSource` | sync trigger 字符串、手动按钮、retry drainer | manual/periodic/appActivation/viewRefresh/retryDrainer | manual/periodic/appActivation 可创建任务，view refresh 不可，retryDrainer 只处理到期重试 |

Canonical recording metadata hardening v1：

- `metadataHash` 合同为 `canonical-recording-business-metadata-v1`，只覆盖 `objectID`、title、filing、规范化 tags、delete/tombstone 状态和 delete 时间；`createdAt`、`modifiedAt`、duration、upload/receive/processing state、ledger、local path、diagnostics、`receivedAt`、`observedAt`、audio hash/size、transcript/note 内容和 provider response 不参与。
- `modifiedAt` 只表示业务 metadata LWW 时钟。Mac 端 `receiveRecord.updatedAt`、inbox fallback 即时 `updatedAt`、转写/笔记/receive 状态更新时间、`receivedAt`、`observedAt` 均不得作为 canonical `modifiedAt`。
- business edit、metadata-only sync item、study-only item 和 tombstone 是 Mac 使用 study item `updatedAt` / `trashedAt` 的允许来源；处理状态变化只进入 diagnostics，不驱动 metadata diff。

Canonical artifact transfer v1：

- generated artifact kinds 限定为 transcript JSON/Markdown、note Markdown/JSON、summary JSON；audio 仍按 recording audio bootstrap 处理，不走 artifact download。
- Mac generated artifacts 来自既有 legacy artifact inventory 已加载的 checksum、size、updatedAt 和 logicalPathToken，并标记 transcription/note generation authoritative producer；iPhone 已下载 generated artifacts 只证明本地可用，不是 authoritative producer。
- canonical generated artifact download 必须桥接到 legacy artifact action，实际请求仍为 `/sync/artifact-request`；缺少可执行 legacy artifact 时记录 fallback no-op，不新增 route。
- generated artifact 不创建 upload job，不触发 audio upload，不驱动 UI/retry/Mac pending/receive 写入；diagnostics 只写 kind、size、hash prefix、logical name 和 decision category。

Canonical apply/conflict/tombstone/library planning v1：

- `CanonicalApplyPlanner` 在 `CanonicalSyncPlanner` 之后运行，metadata upload/download decision 会变成 recording metadata send/apply；generated artifact download decision 会变成 legacy artifact request/apply；audio upload candidate 不在 apply plan 执行，仍留给现有 upload coordinator。
- `CanonicalLibrarySyncPlanner` 对 folder/study item/standalone note 生成 metadata no-op/apply/send/conflict/tombstone decision，并把可执行 action 转为 metadata manifest bridge action；view refresh 和 retry drainer 只记录 suppression/fallback，不创建新的 library transfer。
- `CanonicalLibraryMetadataCutoverRunner` 只允许 folder/studyItem/standalone note metadata apply/send canary；resource move attempt、folder hierarchy cycle、conflict record、library tombstone、object id instability、缺 rollback/root-bound evidence 都会阻断。NoCommit 不 suppress legacy，Commit 只有 success-only duplicate suppression。
- peer tombstone 更新时生成 object/library tombstone apply，本地 tombstone 更新时生成 object/library tombstone send；两者均桥接为 metadata manifest apply/send，只做 soft delete。active-vs-tombstone 进入 conflict record，不执行 apply/send。
- object tombstone 阻止 generated artifact download 复活删除对象；artifact tombstone 当前只生成 unsupported/no-physical-delete action，不物理删除 transcript/note/summary。
- conflict record 只保存 hash prefix、modifiedAt、object/artifact id、kind、policy/state；不写完整 hash、完整内容、绝对路径或 provider response。

Canonical v8.1 live read-only probe：

- route classification 默认 disabled；`classifyOnly` 不构造 envelope，`buildSignedEnvelopeOnly` 只构造 signed envelope 并 suppress network，`sendReadOnlyProbe` 只有 explicit internal config enabled 才发送，全部 failure nonfatal。
- 当前 allowed read-only classification 为 `GET /health`、`GET /fingerprint`、`POST /sync/inventory`；由于 `GET` routes 不走 signed body request，live sender 当前优先使用 signed `POST /sync/inventory`。`POST /sync/artifact-request` 默认 blocked，只有 bounded artifact flag 且 size within policy 时分类允许。
- 当前 denylist 包括 pair、upload secure test、metadata/audio/resumable upload session routes、device/sync status、sync apply/apply-metadata/manifest 和 unknown routes。`/device/status` 与 `/sync/status` 源码会更新连接/sync 状态，不能作为 live read-only route。
- Mac marked request 必须先过 `RequestVerifier`；probe marker 不改变 HMAC payload、headers、timestamp、nonce、body hash 或 nonce replay。`manifestHash` 只能作为 integrity/diagnostic，不是 auth。
- Mac no-mutation audit 对 receive records、upload sessions、pending sync requests 和 study manifest checksum 做 pre/post snapshot；snapshot unavailable 时只记录 `canonicalLiveReadOnlyProbeStateSnapshotUnavailable`，不得记录为 no mutation verified。
- probe diagnostics 只写 mode、route、result、reason、syncRunID、trigger、nodeRole、count/hash prefix 等 redacted summary；不写完整 hash、secret、完整 fingerprint、request/response body、metadata JSON、transcript、note、summary、provider response 或本机路径。

Canonical v8.2 NoCommit hardening：

- `canonicalV8NoCommitStagingRootCreated` / `canonicalV8NoCommitStagingRootCleaned` / `canonicalV8NoCommitStagingRootCleanupFailed`：只描述 NoCommit staging root lifecycle 和 cleanup 结果，不代表 production write。
- `canonicalV8NoCommitEvidenceReportBuilt`：runner 已生成 structured NoCommit evidence report；该 report 只可作为 future gate evidence，不自动启用 Commit。
- `canonicalV8NoCommitConfigStageResolved` / `canonicalV8NoCommitConfigBlocked`：migration stage descriptor 已解析；默认 `.off` 和非 recordingMetadata domain 必须保持 blocked，不驱动执行。
- `canonicalV8NoCommitCommitSuppressed` / `canonicalV8NoCommitLegacyDuplicatePreserved`：明确 NoCommit 不执行 production commit、不 suppress legacy duplicate；legacy fallback 继续 preserved。

## 5. 关键状态定义

- `peer_metadata_only`：对端有录音 metadata，但没有可用 audio hash/size。当前决策允许上传音频。
- `peer_missing_audio`：对端 inventory 表示录音音频对象缺失。当前决策允许上传音频。
- `peer_audio_unknown_deferred`：普通 sync 不能确认对端音频状态时抑制上传，避免把未知误判为缺失。
- `manual_force_peer_unknown`：用户显式点击上传时，即使对端音频未知也可进入上传，但诊断必须标记为手动强制。
- `retry_drainer_peer_unknown`：retry drainer 恢复到期失败任务时可继续上传，避免 retry pending 永久等待。
- `peer_already_has_same_audio`：本地和对端音频 hash/size 均存在且一致。当前决策 no-op。
- `peer_audio_conflict`：本地和对端均有 audio 但 hash/size 不同。当前决策为 fail/conflict，不覆盖 Mac 既有音频。
- `completed_ledger_peer_matches`：本地 ledger 完成，同时对端 hash/size 一致。当前决策 suppress 并显示 uploaded。
- `ledger_retry_pending` / `transfer_retry_pending`：存在可重试失败但未到或未执行 retry。普通 trigger suppress；到期后由 retry drainer 处理。
- `view_refresh_only`：列表、详情、文件夹或学习库刷新。当前决策 suppress，不创建上传任务。
- `canonicalPlanUsed`：双端 `canonicalManifest` 存在且 schema/hash/capability 校验通过，本 tick 的 recording metadata/audio candidate 使用 canonical plan。
- `canonicalPlanFallback`：canonical manifest 缺失或校验失败，本 tick 使用 legacy plan。
- `canonical_audio_bootstrap_upload`：canonical 判断 peer object absent、peer audio missing、peer metadata-only 或 study-only/receive-only 事实需要补音频；该 action 仍必须走现有上传主路径。
- `canonical_audio_peer_unknown_deferred`：canonical 无法证明 peer 缺 audio，普通 sync 不上传。
- `canonical_generated_artifact_download`：canonical 判断 authoritative peer generated artifact 本地缺失或 peer 更新，需要通过 legacy artifact request/apply 下载。
- `canonical_generated_artifact_peer_same_noop`：本地与 peer generated artifact hash/size 相同，不重复下载；若 legacy 本来会下载，记录 canonical 抑制诊断。
- `canonical_generated_artifact_peer_unknown_deferred`：peer generated artifact 不可证明或状态未知，普通 sync deferred。
- `canonical_apply_metadata_apply_send`：canonical apply plan 决定 recording metadata apply/send，但执行仍是 `/sync/apply-metadata` 与 `StudyLibraryStore.applySyncManifest`。
- `canonical_generated_artifact_apply`：canonical apply plan 决定 generated artifact 下载并应用，但执行仍是 `/sync/artifact-request`、checksum/size 校验和旧 artifact apply。
- `canonical_folder_metadata_apply_send`：canonical library plan 决定 folder metadata apply/send，但执行仍是既有 metadata manifest bridge，不直接写 folder store。
- `canonical_study_item_metadata_apply_send`：canonical library plan 决定 study item/standalone note metadata apply/send，但执行仍是既有 metadata manifest bridge，不直接移动资源或改真实路径。
- `canonicalLibraryMetadataN1CanaryConfigured`：v8.15 显式 internal N=1 配置被识别；不是默认 runtime switch。
- `canonicalLibraryMetadataN1CandidateSelected` / `canonicalLibraryMetadataN1CandidateBlocked`：N=1 selector 选中一个 redacted metadata-only candidate，或记录 resource move、hierarchy mutation、tombstone/conflict 等 blocker。
- `canonicalLibraryMetadataN1CommitCompleted` / `canonicalLibraryMetadataN1CommitFailed`：单对象 library metadata canary commit lifecycle；只有 completed 且 postcondition verified 后才允许 duplicate suppression。
- `canonicalLibraryMetadataN1MacPeerSnapshotUnavailable`：Mac inventory seam 缺 peer snapshot，只能 report/fallback，response 不变。
- `canonicalLibraryMetadataN1ObservationRecorded`：记录 N=1 observation summary，必须保持 `mutatedUI=false`、`resourceMoved=false`、`contentBytesMutated=false`，除非 blocker 明确说明 canonical 未执行。
- `canonical_library_tombstone_apply_send`：folder/study item tombstone 只通过 metadata manifest soft-delete 同步，不物理删除文件、不做 permanent delete、不做 tombstone GC。
- `canonical_object_tombstone_apply_send`：object tombstone 只通过 metadata manifest soft-delete 同步，不物理删除文件。
- `canonical_active_vs_tombstone_conflict`：active 版本与 tombstone 版本竞争时只记录 conflict，不执行 apply/send。
- `canonical_tombstone_blocks_resurrection`：对象 tombstone 阻止 generated artifact download 复活已删除对象。
- `canonical_tombstone_conflict_commit_success`：v8.11 显式 commit 在 test-root marker/ledger 写入、pre/postcondition 和 rollback evidence 全部通过后完成；只允许 `.tombstoneMark`/`.conflictRecord` side effect。
- `canonical_tombstone_conflict_commit_blocked`：缺 evidence、缺 owner token、generated artifact tombstone apply、physical/permanent delete、tombstone GC、unsupported restore、ambiguous conflict policy 或 resurrection risk 未被 blocker action 吸收时必须 blocked 并 fallback。
- `canonical_tombstone_conflict_no_commit`：NoCommit 只写 staging summary；`applySyncManifestCalled=false`、network/receive JSON/generated artifact/audio deletion 均 suppressed，legacy duplicate preserved。
- `canonical_conflict_record_ledger`：conflict record 只写 redacted conflict kind/policy/hash prefix ledger；不自动选择胜者、不覆盖对端文件。
- `canonical_transfer_state_projected`：legacy transfer/upload 状态被映射为 canonical phase，只读，不修改 queue。
- `canonical_object_projection_built`：从 canonical facts 生成 read-only display projection，当前不驱动 UI/sync/upload。
- `canonical_retirement_readiness_blocked`：readiness gate 发现 transport/upload runtime/physical storage/UI 仍由 legacy 负责，只记录诊断，不禁用 legacy。
- `canonicalProductionPortsDeclared`：生产 port contract/capability 已声明，仍不是生产迁移。
- `canonicalProductionSnapshotBuilt`：只读 snapshot adapter 用调用方提供 facts 构造 production snapshot，不读取 store、不写入、不创建任务。
- `canonicalDryRunStarted` / `canonicalDryRunCompleted`：dry-run 评估开始/完成，只投影 would-write/would-upload/would-send/would-apply。
- `canonicalDryRunBlocked` / `canonicalDryRunDivergenceDetected`：缺 port/capability、unsupported object、conflict、canonical 更激进或 legacy equivalence 不满足时阻塞。
- `canonicalLegacyEquivalent` / `canonicalLegacyDivergent`：legacy action snapshot 与 canonical dry-run action 的审计结论；只用于报告，不切换 runtime。
- `canonicalProductionMigrationBlocked` / `canonicalEligibleForManualMigrationDesign`：migration gate 只能进入人工迁移设计，不得进入 runtime switch。
- `canonicalPortMissing` / `canonicalPortCapabilityMissing`：required production port 或 capability 缺失。
- `canonicalDryRunWouldWriteButSuppressed` / `canonicalDryRunWouldUploadButSuppressed` / `canonicalDryRunWouldSendNetworkButSuppressed`：dry-run port 发现未来迁移动作但已抑制真实写入、上传或网络发送。
- `canonicalFacadeDisabledRejected`：facade 处于 disabled/dry-run/offline/shadow 等非 production execute 模式时，production execution 必须拒绝。
- `canonicalProductionExecuteGuardRejected`：token、approval、rollback、dry-run equivalence、port、conflict 或 migration gate 任一条件失败，production execution 不调用真实 port。
- `canonicalProductionExecuteAllowed`：只有显式 token、rollback plan、dry-run equivalence、non-dry-run ports 和 migration gate 全部满足时，facade 才允许调用 production port。
- `canonicalRollbackPlanRequired`：生产执行必须携带覆盖 required domains 的 rollback plan；缺失或覆盖不足时拒绝。
- `canonicalProductionSideEffectRedacted`：production execution result 只能包含 redacted side-effect trace，不包含完整路径、hash、secret、body 或内容。
- `canonicalProductionAdapterDisabled`：iPhone/Mac production adapter skeleton 默认 disabled，未显式 fake/test harness 时不得写文件、发网络、上传或 apply。
- `canonicalProductionAdapterFakeOnly`：temp-root file、fake loopback transport、fake upload ledger 和 in-memory apply store 只用于测试，不代表真实 store/route/client 已迁移。
- `canonicalMigrationFacadeRuntimeSwitchFalse`：双端 migration facade 默认 runtime switch false，shadow preparation 和 dry-run report 不会接入 `performTick` 或 UI。
- `canonicalExecutionShadowStarted` / `canonicalExecutionShadowCompleted` / `canonicalExecutionShadowBlocked`：execution shadow preparation 的开始、完成或阻塞事件；默认 disabled 不应出现。
- `canonicalExecutionShadowFileWriteSuppressed` / `canonicalExecutionShadowFileWriteToShadowRoot`：file rehearsal 只能抑制生产写入或写 shadow root，不能写 production root。
- `canonicalExecutionShadowTransportProbeSuppressed` / `canonicalExecutionShadowTransportProbeCompleted`：transport rehearsal 默认 suppressed；read-only probe 只能记录允许 route 的 redacted projection。
- `canonicalExecutionShadowUploadRehearsed` / `canonicalExecutionShadowApplyRehearsed` / `canonicalExecutionShadowRollbackRehearsed`：upload/apply/rollback 只在 shadow receiver 或 in-memory store 中排练，不调用真实 client/store。
- `canonicalExecutionShadowDivergenceDetected` / `canonicalExecutionShadowEquivalent`：execution shadow 的等价或差异证据；不代表 runtime switch 或 legacy retired。
- `canonicalExecutionShadowProductionExecuteBlocked`：iPhone/Mac on-device role 请求 production execute 必须阻断，side effects 为空。
- `canonicalRootBoundMetadataTestRootApply`：仅测试/内部显式 test root 下的 `recordingMetadata` metadata bytes atomic apply；不是 app default path、runtime switch 或 legacy suppression。
- `canonicalRootBoundMetadataProductionRootDisabled`：即使提供 production root URL，默认也必须阻断写入；没有后续显式 canary/evidence/人工批准不得写 production root。
- `canonicalRootBoundMetadataRollbackVerified`：rollback checkpoint 恢复旧 metadata 或删除本轮新建文件后，read-back 与 checkpoint 原字节一致；验证失败必须作为 blocker。
- `canonicalRootBoundMetadataTraceRedacted`：root-bound write/rollback 结果只能记录 hash prefix、byte count、checkpoint id、atomic/rollback 布尔和 failure 分类，不记录完整 metadata JSON、完整 hash、绝对路径或内容。
- `canonicalV86GuardedCommitSeamStarted` / `canonicalV86GuardedCommitSeamCompleted` / `canonicalV86GuardedCommitSeamBlocked`：v8.6 guarded commit app seam 的开始、完成或 nonfatal blocker；只记录诊断，不驱动执行。
- `canonicalV86GuardedCommitGateEvaluated` / `canonicalV86GuardedCommitGateAllowed` / `canonicalV86GuardedCommitGateBlocked`：guarded commit gate 的 allow/block 结果；Mac inventory 缺 peer snapshot 必须 blocked 且 response 不变。
- `canonicalV86CanaryBudgetZero` / `canonicalRecordingMetadataCanaryBudgetZero`：canary budget 为 0；即使 gate allowed 也不得执行任何 object。
- `canonicalRecordingMetadataGateAllowedButNoExecution` / `canonicalRecordingMetadataCommitSkippedBecauseCanaryBudgetZero` / `canonicalV86CommitNotExecuted`：明确 app seam 没有调用 executor、production port、network 或 applySyncManifest。
- `canonicalRecordingMetadataCanaryN1Configured`：仅在 explicit internal N=1 配置被识别时出现；不是默认 runtime switch。
- `canonicalRecordingMetadataCanaryCandidateSelectionStarted` / `canonicalRecordingMetadataCanaryCandidateSelected` / `canonicalRecordingMetadataCanaryNoEligibleCandidate`：记录 N=1 selector 开始、被选中的单个 redacted object/action/hash prefix 或所有 blocker；不得包含完整 metadata/hash/path。
- `canonicalRecordingMetadataCanaryCommitStarted` / `canonicalRecordingMetadataCanaryCommitCompleted` / `canonicalRecordingMetadataCanaryCommitFailed`：记录单对象 canary commit lifecycle；失败后必须能继续看到 rollback/fallback 或 fatal blocker。
- `canonicalRecordingMetadataCanaryPostconditionVerified` / `canonicalRecordingMetadataCanaryPostconditionFailed`：记录 canary postcondition 结果；只有 verified 且 committed 时才允许 duplicate suppression。
- `canonicalRecordingMetadataCanaryLegacyFallbackUsed`：canonical canary 失败或 executor unavailable 后使用 legacy fallback；不得 suppress duplicate。
- `canonicalRecordingMetadataCanaryRollbackStarted` / `canonicalRecordingMetadataCanaryRollbackCompleted` / `canonicalRecordingMetadataCanaryRollbackFailed`：记录 canary rollback lifecycle；rollback failed 必须引出 fatal blocker。
- `canonicalRecordingMetadataCanaryFatalBlocker`：rollback failure 或 executor unavailable 等 fatal/blocking 状态；不得继续扩大 canary 或标记 retirement ready。
- `canonicalRecordingMetadataCanaryObservationReportBuilt`：iPhone app seam 记录 v8.7 observation summary，必须包含 runtimeSwitch=false、uiMutated=false、uploadJobCreated=false 和 sensitiveFieldsRedacted=true。
- `canonicalV86LegacyFallbackPreserved` / `canonicalV86DuplicateSuppressionNotApplied`：legacy plan 继续原样执行，duplicate legacy suppression candidate 只记录、不应用。

## 6. 触发图

| 触发源 | 当前代码路径 | 当前能否创建上传任务 | 正确预期 | 当前风险 |
| --- | --- | --- | --- | --- |
| iPhone 录音卡片上传按钮 | `RecordingLibraryView.uploadRecording` -> `RecordingUploadCoordinator.upload` | 能 | 用户显式点击；peer unknown 时作为 manual force 记录 | 仍需用户理解这是强制上传，不是同步自动收敛 |
| iPhone 详情页上传按钮 | `RecordingStudyDetailPage` -> `RecordingUploadCoordinator.upload` | 能 | 同上 | 同上 |
| iPhone 连接页立即同步 | `StudyLibrarySyncCoordinator.performManualSync` -> `/sync/start` -> `performTick("manual")` | 能 | 只按 inventory diff 补缺失音频 | 对端 inventory 不准确时会重传旧音频 |
| Mac 连接页立即同步 | `MacIPhoneConnectionView` -> `SecureReceiverService.prepareManualStudyLibrarySync` | 间接能 | Mac 写 pending signal，iPhone heartbeat 收到后再 tick | 已有 pending 去重和超时；iPhone 不在线或 heartbeat 未运行时仍等待/超时 |
| heartbeat/probe sync hint | iPhone `LocalNetworkHeartbeatMonitor` 收到 `syncStartSignal`/`syncRequested` | 能 | 使用同一个 `syncRunID` 排队 `manual-sync-requested` tick | 已记录 heartbeat consumed、ack、tick started/completed/failed，仍需真机端到端验证 |
| app active/foreground | `RokuricsApp` -> `LocalNetworkSyncAppService.activate` -> `foregroundTick` | 能 | 前台恢复时同步 metadata/artifact，并谨慎补音频 | debug 启动/前台切换可能触发旧录音重传 |
| periodic timer | `LocalNetworkSyncScheduler.startPeriodicTicks` -> `performTick("timer")` | 能 | 周期收敛缺失状态 | peer 缺失/过期时重复尝试 |
| upload ledger changed | `recordingUploadJobLedgerDidChange` -> `requestUploadLedgerTick` / retry drainer | 能 | 用于状态收敛和到期重试调度 | 未到 backoff 的任务必须继续等待 |
| folder/list/detail onAppear | `RecordingLibraryView`、`RecordingStudyDetailPage` local reload | 不能 | 只刷新本地 UI | 已有代码显式记录 view refresh suppress |
| StudyLibraryStore refresh | `studyLibraryStore.refresh()` | 不能 | 只重建本地学习库视图 | 禁止变成上传触发 |
| Mac AudioInbox refresh | `AudioInboxStore.refreshRecordingInbox` | 不能 | 只读取 Mac inbox 并更新 UI | 不能驱动 iPhone 上传 |
| Mac receive record update | `MacRecordingFileStore` 写 receive/audio 并发通知 | 不能 | 更新 Mac inventory 真相 | 若 inventory 未及时反映 audioAvailable，会导致 iPhone 继续补传 |
| transfer progress update | `LocalNetworkTransferProgress` 写入 study item | 不能 | 只显示进度 | 禁止由显示层重入上传 |
| UI display state change | `RecordingUploadDisplayState` / `UploadableRecordingRow` | 不能 | 仅展示 hidden/waiting/uploading/failed | display state 不得作为业务状态源 |

## 7. 上传决策真值表

| 本地音频 | 对端音频 | transfer job | ledger | 触发源 | 当前决策 | 应有含义 |
| --- | --- | --- | --- | --- | --- | --- |
| missing/unknown | 任意 | 任意 | 任意 | manual/periodic | fail `local_audio_missing` | 不上传，提示本地音频缺失 |
| available | available 且 hash/size 相同 | none | none | manual/periodic | no-op `peer_already_has_same_audio` | 不上传，Mac 已有同一音频 |
| available | available 且 hash/size 相同 | none | completed | manual/periodic | suppress `completed_ledger_peer_matches` | 不上传，账本和 Mac 均确认完成 |
| available | metadataOnly | none | none | manual/periodic | upload `peer_metadata_only` | 上传音频补齐 metadata-only |
| available | missing | none | none | manual/periodic | upload `peer_missing_audio` | 上传音频 |
| available | unknown | none | none | periodic/appActivation/manual sync | suppress `peer_audio_unknown_deferred` | 对端未知不等于缺失，等待下次明确 inventory |
| available | unknown | none | none | manual upload button | upload `manual_force_peer_unknown` | 用户显式强制上传，诊断不能伪装成同步收敛 |
| available | unknown | none | retryPending 到期 | retryDrainer | upload `retry_drainer_peer_unknown` | 到期失败任务走主上传路径恢复 |
| available | different | none | none | manual/periodic | fail `peer_audio_conflict` | 不覆盖 Mac 既有不同音频，展示冲突 |
| available | 任意非匹配 | queued/inFlight/finalizing | none | manual/periodic | suppress queued/inFlight | 不创建重复任务 |
| available | 任意非匹配 | none | retryPending 未到期 | manual/periodic | suppress retryPending | 等待 backoff，不创建重复任务 |
| available | metadataOnly/missing | none | none | folder/list/study refresh | suppress view refresh | 只刷新 UI，不上传 |

## 8. iPhone 端当前链路

`RokuricsApp` 在 `.task` 和 scene active 时调用 `LocalNetworkSyncAppService.activate()`。服务启动 heartbeat 和 scheduler，并在 peer online 时执行 foreground tick。scheduler 还会定时执行 `"timer"` tick。

`LocalNetworkSyncInventoryBuilder` 构造本地 inventory 时读取 `StudyLibraryStore.makeSyncManifest`、`AudioFileStore.loadAllMetadata(includeDeleted:)`、每条录音文件存在性、文件大小和 SHA256。inventory 中的 recording entry 会带 `audioAvailable`、`audioChecksum`、`audioSize`、`uploadLedgerState`、`uploadStatus`、`sourceDeviceID`、`audioLogicalPathToken`。音频 checksum 现在经过 `LocalNetworkChecksumCache`，文件 size/mtime 未变化时复用缓存，miss/invalidated 时在主 actor 外计算 hash。canonical manifest 构建只复用这些 facts 和已有 study manifest/generated artifact facts，再通过 `IPhoneCanonicalRecordingAdapter`、`IPhoneCanonicalLibraryAdapter` 与 `CanonicalInventoryBuilderContract` 生成 recording/library objects、tombstones 和 coverage。

`LocalNetworkSyncEngine.performTick` 拉取 Mac `/sync/inventory` 后先生成 legacy diff，再尝试 `CanonicalSyncPlanner`、`CanonicalApplyPlanner` 与 `CanonicalLibrarySyncPlanner`。canonical 可用时替换 recording metadata diff/apply/send、recording audio bootstrap candidate、generated artifact transfer/apply decision、folder/study item metadata apply/send、library/object tombstone apply/send 和 canonical conflict record；非 generated artifacts、完整 metadata manifest 执行、UI、retry 和物理存储沿用 legacy。canonical generated artifact download 会映射回 peer legacy artifact id 并继续走 artifact request/apply；recording/folder/study item metadata/tombstone apply/send 继续走 metadata manifest；transfer state projection、object projection、inventory coverage 和 readiness report 只写诊断。处理流程仍是先 metadata/artifact，再用 `uploadRecordingAudioActionsToRun` 通过统一 evaluator 过滤音频上传候选。最终上传仍调用 `RecordingUploadCoordinator.uploadAndWait`。`LocalNetworkSyncAppService` 还会在 scheduler gate 允许时 drain 到期 retry job，并用 `.retryDrainer` trigger 复用同一上传路径。

## 9. Mac 端当前链路

Mac 手动同步入口是 `MacIPhoneConnectionView` 的 `onSyncNow`，调用 `SecureReceiverService.prepareManualStudyLibrarySync(for:)`。当 git-backed sync 禁用时，它记录 `syncStartSignalSent` / `manualSyncPendingCreated` 并调用 `DeviceConnectionStatusStore.recordPendingSyncRequest`。这个动作不会直接连 iPhone；重复点击会复用未过期 pending request，超时后显示等待 iPhone 前台响应超时。

`ConnectionHeartbeatRouteHandler` 在 iPhone heartbeat 请求到达时消费 pending signal，响应 `syncRequested=true` 和 `syncStartSignal`。iPhone 收到后 ack，再排队 `manual-sync-requested` tick。Mac 侧记录 `manualSyncAckReceived`，inventory/apply-metadata 路径记录 `manualSyncTickStarted`、`manualSyncTickCompleted` 或 `manualSyncTickFailed`。

Mac `/sync/inventory` 由 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 生成。它读取 `StudyLibraryStore.makeSyncManifest`、`MacRecordingFileStore.loadInboxItems(includeDeleted:)`，并用 checksum cache 读取已有 audio 的 checksum/size，写入 `audioAvailable`、`audioChecksum`、`audioSize`、`sourceDeviceID`、`audioLogicalPathToken`，同时用这些既有 audio facts、legacy generated artifact facts 和 study manifest facts 通过 `MacCanonicalRecordingAdapter`、`MacCanonicalLibraryAdapter` 与 `CanonicalInventoryBuilderContract` 生成 optional `canonicalManifest` 和 coverage diagnostics。Mac 收到同 recording 但 hash/size 不同的 audio upload 时会拒绝覆盖并记录 conflict 诊断。

## 10. Mac 手动同步为何可能像 no-op

Mac 点击同步后只写 pending sync request；iPhone 必须同时满足这些条件才会执行：

- iPhone app active，`LocalNetworkSyncAppService` 已启动。
- paired snapshot 有效，用户连接意图不是 disconnected。
- heartbeat/probe 能成功到达 Mac `/connection/heartbeat`。
- Mac presence 在 iPhone 侧被标记 online。
- pending `syncStartSignal` 被 iPhone 收到并 ack。
- scheduler 没有被 already-in-flight、presence gate 或 backoff 拦住。

任一条件不满足，Mac 端 UI 会显示等待 iPhone 前台响应，超过 pending timeout 后进入超时状态；这仍不是 Mac 主动同步失败，而是 iPhone 未消费 pending signal。

## 11. 重复上传旧数据的主要原因

当前 evaluator 的最终 no-op 条件依赖 peer inventory 明确报告相同 hash/size。如果 Mac inventory 只报告 metadata 或 audio missing，手动/周期/前台 tick 会把录音看作需要补音频；如果是 peer unknown，普通 sync 现在 deferred，不再直接上传。

`RecordingUploadCoordinator.upload` 的默认 `peerAudioState` 是 `.unknown`。用户从列表/详情直接点上传时，如果没有先取得 Mac 端 audio truth，当前逻辑会允许上传并记录 `manual_force_peer_unknown`。这仍是显式用户动作，不应被解释成自动 sync no-op 判断。

## 12. 失败/未上传不重试的主要原因

## 2026-06-03 Recording Metadata Cutover 状态补充

本轮 Canonical Recording Metadata Controlled Cutover Candidate v1 新增 default-off 的 `recordingMetadata` 单域 cutover 合同和 executor 测试入口。它要求 shadow/equivalence/rollback/probe/guard/fallback evidence 齐全后，v8.7 才允许 iPhone explicit internal `N=1` 执行一个 recording metadata apply/send candidate；canary 默认 N=0，N>1 仍 blocked。

新增状态定义：

- `canonicalRecordingMetadataCutoverDisabled`：默认状态。无论 evidence 是否存在，都不执行 canonical production commit。
- `canonicalRecordingMetadataCutoverGateBlocked`：token、owner approval、rollback、real-data shadow copy、execution shadow、dry-run equivalence、blocking divergence、unresolved conflict、read-only probe、production port、legacy fallback、rollback rehearsal、production guard、view refresh 或 retry drainer 任一条件不满足。
- `canonicalRecordingMetadataCanaryNZero`：gate 可通过但 canary budget 为 0，不执行任何对象。
- `canonicalRecordingMetadataCanaryCommitSucceeded`：单个 candidate commit 成功且 pre/postcondition 成功，此时才允许 suppress 同 action legacy duplicate。
- `canonicalRecordingMetadataCanaryCommitFailed`：precondition/postcondition/transport/apply failure，必须 rollback；rollback 成功后保留 legacy fallback。
- `canonicalRecordingMetadataRollbackFatal`：rollback 失败，必须标记 fatal blocker，不得扩大 canary 或标记 retirement ready。
- `canonicalRecordingMetadataRollbackCheckpointMissing`：v8.4 fake Commit 发现 partial mutation 但缺 rollback checkpoint 时，必须标记 fatal blocker，不能当作 rollback success、canary pass 或 retirement evidence。
- `canonicalRecordingMetadataForbiddenSideEffectBlocked`：v8.4 fake Commit 发现 generated artifact/upload/file/UI/retry/Mac pending 等非 recording metadata side effect 时，必须失败并走 rollback/fallback，不得 suppress legacy duplicate。
- `canonicalUIProjectionParallelReadOnly`：只读投影用于比较 canonical/display hash prefix，不能改变 UI state、upload state 或 sync state。
- `canonicalRecordingMetadataRetirementCandidateOnly`：只表示该单域具备后续人工退役讨论资格，不自动删除或禁用 legacy。

新增诊断信号：

- `canonicalRecordingMetadataCutoverGateEvaluated` / `canonicalRecordingMetadataCutoverGateBlocked` / `canonicalRecordingMetadataCutoverGateAllowed`
- `canonicalRecordingMetadataCanaryStarted` / `canonicalRecordingMetadataCanaryCompleted` / `canonicalRecordingMetadataCanaryFailed`
- `canonicalRecordingMetadataProductionCommitStarted` / `canonicalRecordingMetadataProductionCommitCompleted` / `canonicalRecordingMetadataProductionCommitFailed`
- `canonicalRecordingMetadataRollbackStarted` / `canonicalRecordingMetadataRollbackCompleted` / `canonicalRecordingMetadataRollbackFailed`
- `canonicalRecordingMetadataLegacyFallbackUsed`
- `canonicalRecordingMetadataDuplicateLegacySuppressed`
- `canonicalUIProjectionParallelReadStarted` / `canonicalUIProjectionParallelReadEquivalent` / `canonicalUIProjectionParallelReadDivergent`
- `canonicalRecordingMetadataRetirementCandidate` / `canonicalRecordingMetadataRetirementBlocked`

边界不变：该层没有接入 `performTick`、retry drainer、Mac pending sync、UI、真实 route、真实 upload job、真实 store 或 `receive.json` 写入；失败会 rollback/fallback；只有 commit 成功后才 suppress duplicate legacy action。

源码存在 `RecordingUploadQueue`、`retryPolicy`、`nextRetryAfter`、`recoverStaleInProgressJobs`，也有失败后保存 `retryableFailed` 的逻辑。统一 evaluator 仍会把普通 trigger 下的 `ledger_retry_pending` 和 `transfer_retry_pending` 抑制为 waiting，避免无限新建任务。

现有源码已有 `RecordingUploadCoordinator.drainEligibleRetryJobs`，由 `LocalNetworkSyncAppService` 在 scheduler gate 允许时启动；未到 `nextRetryAfter` 的任务记录 backoff skip，到期任务以 `.retryDrainer` trigger 重新调用 `uploadAndWait`。fatal/conflict 与 retryable failure 分别映射到不同 display state。

## 13. UI 展示状态边界

`RecordingUploadStatus` 只有 `localOnly/uploading/uploaded/failed`，是 metadata 级状态。`RecordingUploadDisplayState` 是展示状态，用于 hidden/waiting/preparing/uploading/finalizing/uploaded/failed/retryPending/manualRetryAvailable/conflict/fatalFailed。

`UploadableRecordingRow` 只根据 metadata 和 status 生成 action area presentation。它不能代表 Mac 已有 audio，也不能触发 upload。未来不要把“显示等待上传”或“显示上传失败”做成 view lifecycle 的副作用。

## 14. Metadata 与 Audio 的边界

metadata sync/upload 完成只表示 Mac 可以看到录音条目。audio 是否完成必须看 Mac inventory 的 `audioAvailable=true`，并且 `audioChecksum` 和 `audioSize` 与 iPhone 本地音频一致。

`RecordingUploadStatus.uploaded` 不能单独作为停止上传的证据。正确 no-op 条件是：本地 audio available，peer audio available，hash/size 均存在且一致；ledger completed 只能作为辅助证据。

## 15. Diff 与 no-op 规则

legacy 路径中，`LocalNetworkSyncDiffPlanner` 会把 core diff 中的 recording audio object 转成 `uploadRecordingAudioActions` 或 `noOps`，并通过 evaluator 抑制 peer available 的上传。canonical 可用时，`CanonicalSyncPlanner` 对 recording metadata 使用 canonical `metadataHash`/`modifiedAt`，对 audio 使用 canonical artifact availability/hash/size，并把 action 桥接回同一个 sync/upload pipeline；对 generated transcript/note/summary artifact 使用 canonical producer/hash/size/logicalPathToken 决策，再桥接回旧 artifact request/apply pipeline。`CanonicalLibrarySyncPlanner` 对 folder/study item/standalone note 使用 canonical metadata hash 与 businessModifiedAt 决定 no-op/apply/send/conflict/tombstone，再桥接回 metadata manifest pipeline。

audio download 当前禁用。对端有 audio 而本地缺 audio 时，规划应保持 no-op 或 metadata/artifact 处理，不应自动下载 audio。

最终 no-op 规则必须落在 inventory truth 上：peer audio available + same hash + same size。canonical v1 中该 truth 来自 peer `CanonicalArtifact.availability == available`、`contentHash` 与 `byteSize`；legacy fallback 中来自 peer inventory `audioAvailable/audioChecksum/audioSize`。completed ledger、metadata uploaded、receive completed、UI uploaded 都不能单独替代这个判断。

generated artifact no-op 规则必须落在同一 `objectID`/kind 的 canonical artifact truth 上：本地与 peer 均 available 且 `contentHash`、`byteSize` 相同。peer authoritative newer 可下载；peer unknown/unproven deferred；本地 authoritative newer 当前不上传，只记录 unsupported/local producer no route 类诊断。

## 16. 诊断信号

当前代码已经记录以下有价值的阶段：

- `localAudioStateResolved`
- `peerAudioStateResolved`
- `uploadStateEvaluated`
- `uploadDecisionComputed`
- `uploadDecisionNoOpPeerAlreadyHasSameAudio`
- `uploadDecisionSuppressedCompletedAndPeerMatches`
- `uploadDecisionUploadBecausePeerMetadataOnly`
- `uploadDecisionUploadBecausePeerMissingAudio`
- `peerAudioUnknownDeferred`
- `manualForcePeerUnknownUpload`
- `retryJobEligible`
- `retryJobStarted`
- `retryJobCompleted`
- `retryJobSkippedBackoff`
- `retryDrainerStarted`
- `retryDrainerScheduled`
- `audioConflictDetected`
- `uploadSuppressedConflict`
- `retryPendingDisplayState`
- `uploadDecisionSuppressedQueued`
- `uploadDecisionSuppressedInFlight`
- `uploadDecisionSuppressedViewRefreshOnly`
- `syncPeerAudioAvailable`
- `syncPeerAudioHashMatched`
- `syncPeerAudioMissing`
- `macInventoryReportsAudioAvailable`
- `macInventoryChecksumRecomputed`
- `checksumCacheHit`
- `checksumCacheMiss`
- `checksumCacheInvalidated`
- `checksumComputedOffMainActor`
- `inventoryBuildStarted`
- `inventoryBuildCompleted`
- `inventoryBuildDurationMs`
- `pendingSyncRequestCreated`
- `manualSyncPendingCreated`
- `syncStartSignalReceived`
- `syncStartAckSent`
- `manualSyncAckReceived`
- `manualSyncTickStarted`
- `manualSyncTickCompleted`
- `manualSyncTickFailed`
- `syncRequestedTickQueued`
- `canonicalShadowBuildStarted`
- `canonicalShadowReportWritten`
- `canonicalShadowReportWriteFailed`
- `canonicalShadowBuildCompleted`
- `canonicalShadowBuildDurationMs`
- `canonicalShadowLegacyMismatchDetected`
- `canonicalShadowStudyItemOnlyWithoutReceiveRecord`
- `canonicalShadowMetadataHashConverged`
- `canonicalShadowMetadataHashDiverged`
- `canonicalShadowCreatedAtIgnoredForMetadataHash`
- `canonicalShadowModifiedAtIgnoredProcessingState`
- `canonicalShadowMacUpdatedAtRejectedAsProcessingClock`
- `canonicalShadowBusinessModifiedAtUsed`
- `canonicalShadowAudioConflictDetected`
- `canonicalInventoryCoverageReportWritten`
- `canonicalFolderProjected`
- `canonicalStudyItemProjected`
- `canonicalLibraryTombstoneProjected`
- `canonicalLibraryObjectUnsupported`
- `canonicalPlanUsed`
- `canonicalPlanFallback`
- `canonicalMetadataHashConverged`
- `canonicalCreatedAtIgnoredForMetadataHash`
- `canonicalModifiedAtIgnoredProcessingState`
- `canonicalBusinessModifiedAtUsed`
- `legacyWouldUploadMetadataButCanonicalNoOp`
- `legacyMetadataHashMismatchButCanonicalHashMatch`
- `canonicalAudioBootstrapUpload`
- `canonicalAudioPeerSameNoOp`
- `canonicalAudioPeerUnknownDeferred`
- `canonicalAudioConflict`
- `canonicalGeneratedArtifactDownload`
- `canonicalGeneratedArtifactAuthoritativePeerNewer`
- `canonicalGeneratedArtifactPeerSameNoOp`
- `canonicalGeneratedArtifactPeerUnknownDeferred`
- `canonicalGeneratedArtifactUnsupportedUpload`
- `canonicalGeneratedArtifactLocalProducerNoRoute`
- `canonicalGeneratedArtifactConflict`
- `canonicalApplyPlanUsed`
- `canonicalRecordingMetadataApplyPlanned`
- `canonicalRecordingMetadataSendPlanned`
- `canonicalFolderMetadataApplyPlanned`
- `canonicalFolderMetadataSendPlanned`
- `canonicalStudyItemMetadataApplyPlanned`
- `canonicalStudyItemMetadataSendPlanned`
- `canonicalLibraryTombstoneApplyPlanned`
- `canonicalLibraryTombstoneSendPlanned`
- `canonicalRecordingMetadataAppliedFromCanonical`
- `canonicalRecordingMetadataSentFromCanonical`
- `canonicalFolderMetadataAppliedFromCanonical`
- `canonicalFolderMetadataSentFromCanonical`
- `canonicalStudyItemMetadataAppliedFromCanonical`
- `canonicalStudyItemMetadataSentFromCanonical`
- `canonicalLibraryTombstoneAppliedFromCanonical`
- `canonicalLibraryTombstoneSentFromCanonical`
- `canonicalGeneratedArtifactApplyPlanned`
- `canonicalGeneratedArtifactHashVerifiedBeforeApply`
- `canonicalGeneratedArtifactHashMismatchAfterDownload`
- `canonicalObjectTombstoneApplyPlanned`
- `canonicalObjectTombstoneSendPlanned`
- `canonicalObjectTombstoneAppliedFromCanonical`
- `canonicalObjectTombstoneSentFromCanonical`
- `canonicalArtifactTombstoneUnsupported`
- `canonicalConflictRecordCreated`
- `canonicalTombstoneRecordCreated`
- `canonicalApplyUnsupportedDeferred`
- `legacyWouldDownloadArtifactButCanonicalNoOp`
- `legacyArtifactMismatchButCanonicalResolved`
- `canonicalLibraryObjectsProjected`
- `canonicalLibraryActionBridged`
- `canonicalFolderMetadataHashConverged`
- `canonicalFolderPlanned`
- `canonicalStudyItemMetadataHashConverged`
- `canonicalStudyItemPlanned`
- `canonicalLibraryObjectPlanned`
- `canonicalLibraryConflictRecorded`
- `canonicalDomainFallback`
- `canonicalLegacyFullManifestFallback`
- `canonicalArtifactPlanFallback`
- `canonicalTransferStateProjected`
- `canonicalObjectProjectionBuilt`
- `canonicalRetirementReadinessReportWritten`

`canonicalPlanFallback` reason 必须能区分 `localCanonicalManifestMissing`、`peerCanonicalManifestMissing`、`canonicalSchemaUnsupported`、`canonicalManifestValidationFailed`、`canonicalCapabilityMissing` 和 `canonicalPlannerFailed`；result 同时记录 legacy fallback used、trigger、nodeRole、recording count 与 canonical object count。

下一步排查真实设备时应按 syncRunID 串联 Mac 点击、heartbeat、iPhone tick、inventory、canonical plan/fallback、canonical apply plan、canonical library plan、generated artifact bridge decision、metadata manifest apply/send、upload coordinator、transfer/object projection、readiness report 和 canonical shadow report。shadow report/projection/readiness 只能作为观察证据；是否实际接管 recording metadata/audio candidate/generated artifact/folder/study item/apply/tombstone/conflict decision 以 `canonicalPlanUsed` / `canonicalApplyPlanUsed` / `canonicalLibraryObjectsProjected` / `canonicalPlanFallback` 和 generated artifact/library action diagnostics 为准。`CanonicalKernelFacade.executeProduction` 当前不在任何 syncRunID 触发链上；若未来出现 production execution trace，必须同时能追到 explicit token、rollback plan、dry-run equivalence、guard audit 和 migration gate evidence。

## 17. 可能导致卡顿的源码位置

以下路径仍可能在主线程或 UI 相关 actor 上执行大量 IO/JSON/扫描；audio hash 已加缓存和 off-main 计算，但还不能等同于全量 inventory 增量化：

- `LocalNetworkSyncInventoryBuilder.build` 读取所有 metadata，并为 cache miss/invalidated 的本地音频计算 SHA256。
- `LocalNetworkSyncEngine.performTick` 标记为主 actor 相关路径，inventory、diff、diagnostics、progress 更新集中执行。
- `uploadMissingRecordingAudioIfNeeded` 先 `recordingManager.reloadRecordings()`，再读取本地 inventory checksum 或计算 SHA256，并每 200ms 刷新 transfer progress。
- `StudyLibraryStore.refresh()` 和 `makeSyncManifest()` 会读取/修复学习库 metadata。
- `ConnectionDiagnosticsStore.record` 写诊断 JSONL，频繁阶段记录可能放大 IO。
- Canonical shadow report、inventory coverage、transfer projection、object projection 和 readiness report 当前都复用旧 inventory/study manifest 已加载数据；不新增 audio hash/目录扫描，但真实大库仍需观察 report 编码和诊断写入开销。
- Mac `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 读取整个 inbox，并为 checksum cache miss/invalidated 的 audio 计算 hash。
- `AudioInboxStore.refreshRecordingInbox` 在通知后读取 inbox、trash，并为每条记录写多条诊断。
- `MacRecordingFileStore.loadInboxItems` 遍历日期目录、录音目录、receive.json 和 audio 文件属性。

后续优化重点应放在增量 inventory、目录扫描批处理、诊断写入节流，以及真机长录音场景下的 UI latency 观测。

## 18. 已落实与剩余计划

已落实：

1. “是否需要上传音频”继续收敛在统一 evaluator，并新增 peer unknown deferred、manual force、retry drainer 和 conflict/fatal 分支。
2. Mac 手动同步增加 pending 去重、timeout、ack、tick started/completed/failed 诊断。
3. retry queue 到期后由明确 drainer 重新走上传主路径，未到 backoff 不重复创建任务。
4. inventory 使用 checksum cache，文件 mtime/size 不变时复用 hash。
5. view refresh 继续只做本地 refresh，不进入上传 state machine 的 job creation 分支。
6. Canonical Shadow Mode 已接入 iPhone sync tick 与 Mac `/sync/inventory`，生成 report 和 diagnostics。
7. Canonical Kernel Completion v1 已接管 recording metadata diff、recording audio bootstrap candidate、Mac generated transcript/note/summary transfer decision、recording/folder/study item metadata apply/send、generated artifact request/apply、object/library tombstone apply/send、canonical conflict record、transfer/object projection、inventory coverage 和 readiness diagnostics；legacy fallback、旧上传主路径、旧 metadata/artifact request/apply、旧安全/路由机制、UI、retry、Mac pending sync、`receive.json` 写入和物理存储保留。
8. Canonical Runtime Kernel Offline Completion v1 已补齐离线 file/transport/upload/apply/conflict/harness/readiness 执行语义：root-bound path、hash/size/no-overwrite/tombstone、route/capability/body hash/idempotency、resumable chunk/finalize/retry snapshot、generated artifact apply 和 unresolved conflict 都有双端 target 测试覆盖；该能力仍不接入生产 tick、真实 route、真实 upload client、真实 store、UI、retry drainer 或 Mac pending sync。
9. Canonical Shadow Migration Wiring v1 已新增默认关闭的 migration shadow 状态机。iPhone 触发点是 `performTick` 中 legacy diff 之后、canonical/legacy plan 选择之前；Mac 触发点是 `/sync/inventory` 本地 inventory 构建完成之后、响应返回之前。启用后只记录 migration gate/equivalence/suppressed side-effect 事件，不修改 legacy plan、state store transfer counts、Mac pending sync、retry queue、upload ledger、inventory response 或 UI。
10. Canonical Execution Shadow Preparation v1 已新增默认关闭的执行级 shadow 排练。启用后可在 shadow root、shadow receiver、in-memory apply store 和 read-only transport projection 中验证 file/upload/apply/rollback 行为，但不写真实 store、不发送真实网络、不创建真实 upload job、不调用真实 apply、不改变 legacy plan、Mac inventory response、retry、pending sync 或 UI。
11. Canonical Recording Metadata Single-Domain Shadow Enablement v1 已新增默认关闭的 `recordingMetadata` 单域 shadow。iPhone 在 legacy diff 后复用已有 local/peer canonical manifest、canonical sync/apply plan 和 legacy action snapshot，记录 metadata no-op/apply/send/tombstone/conflict/equivalence/blocker 诊断；Mac `/sync/inventory` 因缺 peer snapshot 只记录 `insufficientPeerSnapshot` blocked 且继续返回 inventory。该 shadow 不改变 transfer counts、state store、upload ledger、retry queue、pending sync、inventory response、真实 metadata store、route 或 UI。
12. Canonical Real-Data Execution Shadow & Read-Only Transport Probe v1 已新增默认关闭的真实数据 shadow copy/probe 证据层。iPhone tick seam 与 Mac inventory seam 只在显式 execution shadow mode/policy 下创建临时 shadow root、复制已加载 metadata/receive/inventory/study/generated artifact evidence、写 audio descriptor-only evidence、记录 cleanup/probe summary；默认不复制 audio bytes、不发真实网络、不调用 upload/apply/store、不改变 canonical/legacy plan、Mac inventory response、state store、retry queue、pending sync 或 UI。
13. Canonical v8.0/v8.2 Recording Metadata NoCommit App Seam 已新增默认关闭的 app seam 和 staging/evidence hardening。iPhone tick seam 位于 legacy diff 后、canonical/legacy plan 选择前；Mac inventory seam 位于 inventory 构建后、response 返回前。显式启用时只允许 `guardedExecuteNoCommit`，只 staging recording metadata apply/send summary、默认 cleanup staging root、记录 `canonicalV8*` / `canonicalV8NoCommit*` diagnostics、equivalence/blocker 和 evidence report，不替换 legacy plan、不 suppress duplicate legacy、不调用 `/sync/apply-metadata`、不调用 `applySyncManifest`、不发真实网络、不写 production store、不改 transfer counts、retry、Mac pending sync、inventory response 或 UI。
14. Canonical v8.6 Recording Metadata Guarded Commit App Seam 已新增默认关闭的 diagnostics-only guarded commit wiring。iPhone tick seam 复用 local/peer canonical manifest、apply plan 和 legacy recording metadata action snapshot；Mac inventory seam 因缺 peer snapshot 只记录 nonfatal blocker。显式 `guardedExecuteCommit` / `canaryCommit` 在 `N=0` 下只评估 evidence/readiness、记录 commit not executed、legacy fallback preserved 和 duplicate suppression not applied；不执行 real commit、不写 production root、不发网络、不调用 `applySyncManifest`、不 suppress duplicate、不改 plan/response、retry、Mac pending sync、UI 或安全 route。
15. Canonical v8.7 Recording Metadata Canary N=1 已新增默认关闭的 explicit internal iPhone canary。只有 `.canaryCommit` + `N=1` + `allowsV87CanaryN1InternalExecution` + 注入 executor 才会选择并执行一个 recording metadata candidate；成功后只 suppress 同 object/action 的最终 metadata action，失败/rollback/fallback 不 suppress。`N>1` blocked，Mac 仍 report-only，安全 route、retry、pending sync、UI 和其他 domain 不变。
16. Canonical v8.17 LibraryMetadata Read-Side Pilot Completion 已新增默认关闭的 read-side parallel evidence seam。iPhone 触发点仍在 sync tick 已加载 inventory/canonical facts 后；Mac 触发点仍在 `/sync/inventory` 本地 inventory 构建后、response 返回前。显式启用时只比较 legacy/canonical library metadata read snapshot、记录 divergence/candidate/fallback/retirement report；默认 off 且启用后仍不切 read path、不改 UI、不触发 sync/upload、不 suppress legacy、不改 route/security/retry/Mac pending sync、不改变 inventory response。

剩余计划：

1. 在真实 iPhone + Mac 上验证 Mac 点击立即同步 -> heartbeat -> ack -> iPhone tick -> Mac completed/failed 的完整 UI 和诊断链路，并同时检查两端 canonical plan/fallback、generated artifact bridge action、folder/study item metadata bridge、inventory coverage、object projection、readiness report 和 shadow report。
2. 继续把学习库 manifest、目录扫描、JSON 诊断写入做增量化或节流。
3. 为 peer same audio、peer metadata-only、retry drainer、Mac pending timeout、canonical shadow mismatch、folder/study item metadata bridge 和 readiness gate 增加更接近真实设备的端到端用例。

## 19. 测试计划

自动测试应覆盖：

- view refresh 不创建 upload job。
- app activation 在 peer same hash/size 时 no-op。
- manual sync 在 peer same hash/size 时 no-op。
- peer metadata-only 只上传一次，下一次 inventory same hash/size 后 no-op。
- ledger completed 但 peer missing 时仍允许补传。
- ledger completed 且 peer same hash/size 时 suppress。
- retryable failure 到期后 drain retry queue 并恢复上传。
- retryPending 未到期时不创建重复任务。
- Mac pending sync request 只被 heartbeat 消费一次。
- Mac pending sync request 重复点击去重，并在超时后给出明确状态。
- Mac inventory 必须报告 audioAvailable/hash/size/sourceDeviceID/logicalPathToken。
- checksum cache 在文件 size/mtime 不变时命中，变化时 invalidated。
- peer unknown 普通 sync deferred，手动上传 force，retry drainer 可恢复。
- peer audio hash/size 不同进入 conflict，不覆盖 Mac 旧音频。
- Canonical shadow report 只能用已经加载的 legacy facts 构建；hash 只能写 prefix；study-only、receive-only、metadata diverged、same audio、unknown audio、conflict、generated artifact peer same/unknown/conflict 等 category 必须可测试；report 不能改变 legacy inventory response。
- Canonical planner：metadata same hash 必须抑制 legacy metadata mismatch；modifiedAt newer 决定 upload/download；同 modifiedAt 不同 hash 进入 conflict；peer object absent、metadata-only、missing 和 study-only/receive-only 可 bootstrap audio；generated artifact missing local/authoritative peer newer 可 download、same hash/size no-op、peer unknown deferred、不创建 upload job；peer unknown、view refresh、retry drainer fresh job 必须 deferred/suppressed；schema/hash/capability 不兼容必须 fallback legacy。
- Canonical apply planner：metadata direction 必须变成 apply/send action；generated artifact download 必须带 legacy artifact request/apply bridge hint；same generated artifact no-op 不创建 upload job；active-vs-tombstone 必须 conflict 且不 apply/send；object tombstone 只能 soft delete；artifact tombstone 只能 unsupported/no-physical-delete；tombstoned object 必须阻止 generated artifact resurrection；conflict/diagnostics 不写完整 hash、路径或内容；dedupe 不重复同一 action。
- Canonical runtime kernel：file runtime 必须拒绝 unsafe path/root 并校验 hash/size；transport runtime 必须校验 route/capability/body hash/manifest hash/idempotency；upload runtime 必须支持 offset resume、duplicate chunk idempotency、retry snapshot 和 finalize checksum；apply runtime 必须只写 in-memory metadata/generated/tombstone record；conflict resolver 必须保持 unresolved/no-overwrite；runtime readiness 必须在 production owner 仍为 legacy 时阻塞 migration。
- Canonical shadow migration wiring：默认 disabled 不应产生 `canonicalShadowMigration*` 事件；diagnostics-only 只记录 started/suppressed/completed；dry-run compare/read-only 缺 peer snapshot 应记录 blocked 且不影响 tick/inventory response；network probe 默认 off，开启后只接受 health/fingerprint/sync inventory/artifact request/device status 等 read-only probe，upload/apply/mutating route 必须拒绝；iPhone/Mac role 的 production execute 必须返回 `blockedProductionExecute`。
- Canonical execution shadow preparation：默认 disabled 不应产生 `canonicalExecutionShadow*` 事件；execution shadow dry-run 缺 peer snapshot 应 blocked 且非 fatal；shadow file port 必须拒绝 production root/root escape/hash mismatch 并只写 shadow root；shadow transport port 默认不发送网络且拒绝 mutating route；upload rehearsal 必须覆盖 resume/no-op/conflict/finalize mismatch 且不调用真实 upload client；apply rehearsal 必须只写 in-memory shadow store、不调用 `applySyncManifest`、不物理删除 tombstone；iPhone/Mac role production execute 必须继续 blocked。
- Canonical recording metadata single-domain shadow：默认 disabled 不应产生 `canonicalRecordingMetadata*` 事件；非 `recordingMetadata` domain enablement 不应执行；metadata same canonical hash + legacy metadata move 应是 non-blocking `canonicalMoreConservative` no-op；peer newer 应 shadow apply，local newer 应 shadow send，same modifiedAt different hash 应 conflict only；newer tombstone 应 marker only；active-vs-tombstone 应 conflict only；canonical more aggressive 默认 blocked，policy 允许时才 rehearsal；Mac inventory 缺 peer snapshot 应 blocked 且不改 response；diagnostics 必须 bounded 且只写 hash prefix。
- Canonical real-data execution shadow/read-only probe：默认 disabled 不应产生 copy/probe side effect；shadow copy target 必须拒绝 production root、production 子路径、unsafe logical path、source/target equality、hash mismatch 和超限 artifact；audio 默认只写 descriptor evidence，不复制真实音频字节；cleanup 只能删除/保留 shadow root 且拒绝 production root；read-only probe 默认 network suppressed，mutating upload/apply/pair route 必须拒绝，artifact request 只有显式 bounded allow 时可通过，`manifestHash` 不能替代 TLS/HMAC/nonce/body hash/signature。
- Canonical v8 recording metadata no-commit seam：默认 disabled 不应产生 `canonicalV8*` 事件；非 `recordingMetadata` domain、commit/production/canary mode、view refresh、retry drainer、缺 snapshot 或证据不足必须 blocked；allowed candidate 只能写 staging summary，默认 cleanup staging root，可显式 bounded retain diagnostics，并验证 no production commit/no duplicate suppression/no network/no `applySyncManifest`/no production store；iPhone enabled seam 不改变 legacy plan/action count/client side effect，Mac enabled inventory seam 记录 `insufficientPeerSnapshot` 且 response shape 不变。v8.2 evidence report/config stage summary 只能用于诊断和 future gate evidence，不能启用 Commit。
- Canonical v8.6 recording metadata guarded commit seam：默认 disabled 不应产生 `canonicalV86*` 事件；显式 commit/canary mode 必须仍是 canary `N=0` report；gate allowed 也必须记录 no execution；Mac 缺 peer snapshot 必须 nonfatal blocked 且 response shape 不变；验证 no production commit/no real apply port/no network/no `applySyncManifest`/no metadata JSON write/no duplicate suppression/no runtime switch/no plan mutation。
- Canonical v8.7 recording metadata canary N=1：默认 disabled 或 N=0 不应执行；N=1 缺内部开关必须 blocked；N>1 必须 blocked；selector 必须稳定选择一个 eligible recordingMetadata apply/send candidate 并排除 unsupported trigger/evidence/conflict/root-bound/probe/failed action；成功后只 suppress 同 object/action metadata action；失败必须 rollback/fallback 且不 suppress；observation report 必须 redacted 且 runtimeSwitch/UI/uploadJob 均为 false；Mac inventory 仍 report-only。
- Canonical v8.17 libraryMetadata read-side pilot：默认 disabled 不应产生 read-side diff side effect；parallelOnly 只能输出 legacy/canonical read snapshot diff，不切 read path；canonicalReadCandidate/guardedCanonicalRead 必须要求 `libraryMetadata` sole active pilot、v8.16 write-side staged canary evidence、zero divergence、fallback 可用和 no unsupported/path-leak blocker；ready 也必须保持 `readPathSwitched=false`、`uiMutated=false`、`syncOrUploadTriggered=false`；retirement candidate 只能 report-only，legacyDeleted/legacyDisabled 必须为 false。

手动测试应覆盖：

- Mac 点击立即同步时 iPhone 前台、后台、未启动三种状态。
- debug 启动 iPhone 后不应重传 Mac 已有同 hash/size 的旧录音。
- 网络中断后失败上传在 backoff 到期后可重试。
- 大录音 inventory/hash 不应明显卡住列表或连接页。

## 20. 不得突破的边界

- 不让 view lifecycle、folder/list/study refresh、AudioInbox refresh 创建上传任务。
- 不把 metadata uploaded 当成 audio uploaded。
- 不把 completed ledger 单独当成 no-op。
- 不把 peer unknown 当成普通 sync 下的缺失音频。
- 不覆盖 Mac 已有但 hash/size 不同的音频。
- 不把 UI display state 当成业务状态源。
- 不在主线程做全量大文件 hash、全量 inventory、全量 JSON 反复读写；hash miss 也应记录 off-main 计算。
- 不恢复 audio auto-download。
- 不为 generated artifact 新增 route、绕过 legacy artifact request/apply 或创建 upload job。
- 不让 canonical apply plan 绕过 `/sync/apply-metadata`、`StudyLibraryStore.applySyncManifest`、`/sync/artifact-request`、checksum/size 校验或 `RecordingUploadCoordinator`。
- 不让 canonical shadow migration result 驱动 upload/download/apply、改变 legacy plan、改变 state store control plane、改变 Mac inventory response、触发 retry drainer、触发 Mac pending sync 或修改 UI。
- 不让 canonical execution shadow result 驱动 production store 写入、真实 network send、真实 upload/apply、legacy plan 替换、Mac inventory response 改写、retry drainer、Mac pending sync、runtime switch 或 UI。
- 不让 recording metadata single-domain shadow result 驱动真实 metadata JSON 写入、`/sync/apply-metadata`、`applySyncManifest`、upload/apply route、upload ledger、retry queue、Mac pending sync、receive.json、legacy plan 替换、pending count 改写、runtime switch 或 UI。
- 不让 real-data shadow copy/probe result 驱动真实 production store 写入、audio upload/download、真实 network send、真实 apply、legacy plan 替换、Mac inventory response 改写、state store transfer counts、retry drainer、Mac pending sync、runtime switch 或 UI。
- 不让 v8 no-commit seam 驱动 production commit、legacy replacement、duplicate suppression、真实 network send、真实 apply/store/upload、legacy plan 替换、pending count 改写、Mac inventory response 改写、retry drainer、Mac pending sync、runtime switch 或 UI。
- 不让 v8.6 guarded commit seam 驱动 production commit、real root-bound apply、network send、`applySyncManifest`、metadata JSON write、legacy duplicate suppression、legacy/canonical plan 替换、pending count 改写、Mac inventory response 改写、retry drainer、Mac pending sync、runtime switch、UI 或 upload/security route 改动。
- 不让 v8.7 canary 扩大到 N>1、默认启用、无内部开关执行、无 root-bound/read-only/rollback/equivalence evidence 执行、跨 domain 执行、Mac production commit、UI/runtime switch、retry drainer、Mac pending sync 或 route/security 改动。duplicate suppression 只允许 canonical commit success 后的同 object/action metadata action。
- 不让 v8.17 read-side candidate 变成默认 read cutover、UI owner switch、legacy route/store/planner deletion、legacy read fallback disable、sync/upload trigger、resource move、standalone note content write、route/security change、retry drainer 或 Mac pending sync 改动。read-side divergence report 只能是 evidence，不得驱动生产读路径。
- 不把 canonical tombstone 变成 audio/transcript/note/summary 物理删除、permanent delete 或 tombstone GC。
- 不绕过 TLS pinning、HMAC、nonce、Keychain、安全范围书签。
- 不在文档或诊断中写入完整密钥、完整 fingerprint、完整 API 响应、完整转写文本或本机隐私路径。
