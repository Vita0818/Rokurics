# DO_NOT_BREAK

## Git 禁区

- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不执行破坏性 Git 操作，不强制 push，不删除用户未提交文件。

## Rokurics v10.0 / Mac 首页与共享录音实时转写禁区

- v10.0 当前只保留 Mac 首页、本地录音、共享录音界面和模拟实时转写改动；不得把该范围扩大成 canonical runtime、fallback、旧内核删除、设置页开关删除或同步/上传/apply/read 行为变更。
- `MacRecordingManager` 保存音频必须继续走 `MacRecordingFileStore` 既有 metadata-first inbox path：`saveMetadata`、`temporaryAudioUploadURL`、`checksumForTemporaryAudioUpload`、`saveAudio(temporaryFileURL:)`。不得绕过 receive record、checksum/fileSize 更新或 inbox 根目录约束。
- Mac 本地录音只能作为 Mac 本机 inbox 来源。不得新增 Mac -> iPhone 反向连接、反向上传、反向同步、heartbeat carrier、upload route、artifact route 或 sync route。
- 实时转写当前必须标记为模拟 provider：`shared-live-simulated-asr` / `simulated-live-asr`。不得把模拟文本标成真实 OpenAI、FunASR、whisper.cpp 或用户音频的可信 ASR 输出。
- iPhone 录音页可以显示共享模拟实时转写文本，但不得新增 `RecordingMetadata` 字段、不得写 transcript artifact、不得创建 upload job、不得改变上传队列、学习库 schema、同步 proof 或 Mac 接收 route。
- 共享录音 UI 应继续复用 `RokuricsSharedRecordingSessionSurface`；Mac wrapper 只处理生命周期，iPhone wrapper 保留 iPhone 专属 filing/低电量 overlay。不要在 Mac 首页重写第二套录音 session 控制面板。
- 未来接入 OpenAI Realtime、FunASR streaming 或其他实时 ASR 时，必须单独设计 provider/settings/secret storage/redaction，不得把 API key、完整 provider response、raw audio、完整转写文本、完整 hash 或绝对路径写入文档/诊断。

## Canonical v9.12 / R6 Connection/Transfer Owner + R7 Final Gate 禁区

- v9.12 只做 post-v9.10 audit closure B：R6 Connection/Transfer owner wiring 复核与 R7 four-domain gate/harness 收口。不得执行 legacy retirement，不得启用 release/default canonical，不得新增 route，不得修改 `/device/status`、`/connection/heartbeat` 或 upload start/status/chunk/finalize route schema。
- Connection Kernel 在 `canonicalFullSync` allowed 时只能拥有 peer liveness、heartbeat envelope、syncRequested/status request、status exchange carrier、capability summary 与 diagnostics。不得 mark uploaded、mark audioAvailable、读写文件、创建 upload job、scan file tree、build manifest 或 inline sync/apply/upload。
- Mac 仍不得主动连接 iPhone。任何 Mac reverse connection、`URLSession`/`NWConnection` 主动拨号或 heartbeat heavy sync 都必须进入 unsafe gate，除非源码证明命中不是 Mac->iPhone 连接。
- Transfer Kernel 在 `canonicalFullSync` allowed 时只能通过 existing secure upload path 执行：`RecordingUploadCoordinator` -> `CanonicalTransferRuntime` -> `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient` -> existing Mac routes。不得新增 abort/proof/status route，不得绕过 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`。
- Production fullSync 不得选择 test-only in-memory upload port。旧 in-memory ledger 只能作为 tests/harness 显式 `testOnly` port；若 gate evidence 显示 test-only production upload port selected，必须 `UNSAFE_TO_TRY_ON_DEVICE`，不得 READY。
- Transfer wrong offset 必须 status refresh/resume 或 fail closed；duplicate chunk 只有同 offset/length/hash 可 idempotent；confirmedBytes 不得回退；partial receive 不得 completed；existing different audio 必须 conflict/no-overwrite。
- Finalize proof 只作为 StatusTruth input。Transfer runtime 不得直接设置 UI completed/uploaded verified；UI completed/peerVerified/audioAvailable 仍只能来自 `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState`。
- R7 gate 必须逐项表达 Connection、Transfer、Sync、File 与 cross-domain evidence。缺真实 app runtime 引用、缺 secure upload path、缺 finalize proof -> StatusTruth、缺 retry existing-only、缺 UI EffectiveStatus、缺 no-freeze/hot-path guard、缺 legacy fallback 或缺 mode boundary，均不得 READY。
- Harness 仍是假环境证据，不得当成 paired-device evidence。`realDeviceEvidencePresent=false` 必须保持，除非提供实际 paired-device redacted jsonl。
- 仍不得写 absolute path、full hash、secret、full fingerprint、request/response body、raw audio、full transcript/note/summary/provider response、full metadata JSON 或 full generated content 到 docs/evidence/diagnostics。

## Canonical v9.11 / UI EffectiveStatus snapshot + R3 No-Freeze 反证禁区

- v9.11 只能完成 R4 UI EffectiveStatus binding 与 R3 no-freeze proof。不得执行 R6：不得把 `ownerApprovedCanonicalTransfer` 改 true，不得接管 CanonicalTransferRuntime owner 或 Connection Kernel owner，不得重构 `SecureMacUploadClient` path、upload route handler、heartbeat route，不得新增 route、协议空壳或 Mac reverse connection。
- 不得新增视觉 UI。不得新增按钮、提示卡片、用户可见 technical diagnostics，不得改 layout、颜色、字体、间距、导航、View hierarchy 或用户操作流程。
- UI/status model 的 final sync status 必须读 `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` snapshot。View 层不得从 upload ledger、receive record、metadataOnly、local file exists、partial receive、completed ledger 或 raw `hasAudio` 多源拼 completed、peerVerified 或 audioAvailable。
- Store/coordinator/service getter 只能同步读取已缓存 snapshot。getter 不得 `await` actor 重算、merge facts、reconcile status、build manifest、full hash、read ledger、写 diagnostics file、启动 sync/upload/retry drain、访问 file IO 或 network IO。
- oldKernel、blocked、fallback 下可以保留旧行为等价显示，但必须在 Store/status model 层统一转换成 EffectiveSyncStatus-compatible display result；View 层不得绕过 projection 自己判断 completed/audioAvailable。
- displayed completed/peerVerified/audioAvailable 只能来自 accepted finalizeProof、peerInventoryHashSizeMatch、same hash+same byteSize no-op proof，或 StatusTruthEngine 已验证的等价 proof chain。
- `metadataOnly`、`metadataOnlyLedger`、`receiveRecordOnly`、completed ledger alone、partialReceive、local file exists only、expected manifest hash only、peerUnknown、status ack alone 不得显示 completed、peerVerified 或 audioAvailable。
- peerUnknown 必须显示 deferred/unknown/pending 类状态且不得创建 upload job；partialReceive 必须显示 partial/receiving/in progress 类状态且不得 completed；existing different audio 必须 conflict/blocked/no-overwrite 且不得覆盖或强制上传；metadataOnly 不得显示 audio available/completed。
- `CanonicalMainActorHotPathGuard` 必须继续覆盖 diagnosticsWrite、fileTreeSnapshot、manifestBuild、fullHash、readProjectionRebuild、statusTruthReconciliation、effectiveStatusProjection。UI read、Store getter、View refresh 不得触发 status reconciliation、diagnostics sync write、manifest build、full hash、upload job 或 retry drain。
- `ConnectionDiagnosticsStore.record(...)` 的 R1 修复不得回退：record hot path 不得调用 `loadEntries()`，不得 atomic rewrite 全文件，不得 await file IO。
- R2 修复不得回退：canonical effective read cache identity 不得包含 `generatedAt`、当前 `Date()` 或每次 snapshot 更新都会变化但内容不变的时间戳。`generatedAt` 可作为 legacy manifest 字段存在，但不得作为 cache key identity 主因。
- v9.10 final gate/scorecard/evidence package 必须继续要求 `uiEffectiveStatusBindingEvidence`、`viewLayerNoDirectPeerProofEvidence`、`noMainActorStatusReconciliationEvidence`、`noViewRefreshUploadJobEvidence`、`diagnosticsAsyncHotPathEvidence`、`contentStableCacheKeyEvidence`。缺 R4 或 R3 evidence 不得 READY；View 层直接把 completed ledger 显示 completed 必须 UNSAFE 或 NOT_READY。

## Canonical v9.10 / Real-Device Trial Gate, Evidence Package, Cleanup, No-Retirement Lock 禁区

- v9.10 只能建立 report-only trial gate、redacted evidence package、final scorecard、cleanup audit 和 no-retirement lock。不得扩展 runtime 行为，不得启用 release/default canonical，不得删除、禁用或退休 legacy。
- `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL` 只表示 code-level evidence 可以进入人工真机 app trial 准备；不得把它写成 real-device validated、canonical kernel complete、production complete 或 legacy retirement ready。
- default/release 必须继续 `oldKernel`；`canonicalFullSync` 只能 debug/internal + owner + manual + all gates。`legacyDeleted=false`、`legacyDisabled=false`、`retirementExecutionPerformed=false`、`readyToRetireLegacyReportOnly=false` 必须保持。
- 不得新增 route，不得修改 upload start/status/chunk/finalize schema，不得改 `SecureLocalHTTPSServer` route allowlist，不得在 evidence/gate/scorecard 里绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、pairing、Keychain 或安全范围书签。
- Missing legacy fallback 是 UNSAFE，不是普通 partial。route/security bypass、RequestVerifier bypass、upload route schema change、release/default canonical、Mac reverse connection、heartbeat heavy sync、view refresh upload job、retry storm guard missing、MainActor hot path violation、diagnostics leak、oldKernel switch-back failure 和 no-retirement lock broken 都必须 fail closed。
- `metadataOnly`、completed ledger alone、receive record alone、partial receive、本地文件存在或 expected manifest hash 不得成为 peer audio proof。Gate/evidence package 不得把这些 soft signals 计为 completed、peerVerified 或 audioAvailable。
- Evidence package 只能保留 redacted summaries 和计数，不得包含 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response 或 full generated content。
- Cleanup audit 不得留下“看起来完成”的无用 facade。没有真实 app runtime 引用的 v9 类型必须是 test-only/report-only 且有测试或文档说明；否则应删除或接线。
- 本轮新增类型不得调用真实 network/store/route/upload/apply，不得写 production root，不得触发 sync/upload/retry drainer，不得修改 UI/read path，不得改变 Mac pending sync 或 receiver topology。

## Canonical v9.9 / Four-Domain Gate and Deterministic Harness 禁区

- v9.9 只能建立 code-level four-domain gate 和 deterministic fake two-node harness。不得声称 canonical kernel 完成，不得把 fake harness、本地 build/test、simulator 或 fixture evidence 当作 paired-device real-device evidence；`realDeviceEvidencePresent` 必须保持 `false`。
- default/release 必须继续 `oldKernel`；legacy fallback、legacy upload/sync/read path、existing secure carrier 和 oldKernel switch-back path 必须保留。
- Portable canonical protocol/harness 不得写死 Rokurics local HTTPS/TLS/HMAC、pinning、nonce、body hash、URL route 或 `RequestVerifier` 细节。Rokurics 只能作为 adapter 实现这些协议。
- 不得新增 route，不得新增 status-exchange/upload/proof route，不得修改 upload start/status/chunk/finalize schema，不得改 `SecureLocalHTTPSServer` route allowlist。
- 不得绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、pairing、Keychain 或安全范围书签。Gate 发现 route/security/default canonical/RequestVerifier 变化必须 `UNSAFE`。
- Mac 仍不得主动连接 iPhone。Fake carrier 可以记录 reverse-connection attempt count，但真实代码不得新增 Mac client 或反向拨号。
- Heartbeat、status exchange、syncRequested callback 只能 enqueue existing sync/status work；不得 inline inventory、apply、upload、file tree scan、manifest build、full-file hash 或同步 diagnostics JSONL 写入。
- Fake transfer 不得调用真实网络、`SecureMacUploadClient`、`SecureLocalHTTPSServer` upload handler 或 production route。真实 Transfer runtime 仍必须复用 existing secure upload path。
- `metadataOnly`、completed ledger alone、receive record alone、partial receive、本地文件存在或 expected manifest hash 不得成为 peer audio proof。所有 displayed completed/peerVerified/audioAvailable 必须引用 accepted finalize proof、peer inventory/hash-size proof、same hash+same byteSize proof 或 valid dualAck proof chain。
- Status exchange ack alone 不得显示 completed，不得创建 upload job，不得作为 peer audio proof。
- View refresh 不得创建 upload job。Retry drainer 只能恢复 existing eligible job；storm guard 缺失、view refresh upload job 或 retry storm 必须 `UNSAFE`。
- MainActor hot path 不得执行 file tree scan、manifest build、full-file hash、status reconciliation 或 diagnostics JSONL 写入。Harness no-freeze counters 必须来自路径/计数，不得用真实重活冒充通过。
- Diagnostics 必须 bounded/redacted。不得写 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response；redaction violation 必须 blocked/rejected/UNSAFE。
- Harness 场景不得写 production root，不得迁移真实数据，不得触发 provider rerun、真实 upload、真实 sync、真实 file scan 或真实 diagnostics file write。

## Canonical v9.8 / Connection and Transfer Runtime Owner Wiring 禁区

- v9.8 只能在 `canonicalFullSync` 且 gates 全部允许时启用 Connection/Transfer runtime owner。不得声称 canonical kernel 完成；不得把 Connection/Transfer owner wiring 描述成 File no-freeze、Sync 全量状态收敛或 paired-device 真机验证完成。
- default/release 必须继续 `oldKernel`；legacy fallback、legacy connection/upload path、existing `RecordingUploadCoordinator` 和 secure upload route 必须保留。`oldKernel` 和 blocked 下 canonical connection/transfer owner 必须 disabled。
- `canonicalShadow` 与 diagnostics-only 只能 carrier diagnostics/no commit；`canonicalDecisionOnly` 不得 transfer commit；`canonicalApplyNoAudio` 必须阻断 canonical audio transfer；`canonicalFullSync` 缺 owner approval、manual confirmation、legacy fallback、route/security、domain readiness、connection runtime readiness 或 transfer runtime readiness 时必须 blocked/fallback。
- 不得新增 route，不得新增 abort route，不得修改 upload start/status/chunk/finalize route schema，不得改 `SecureLocalHTTPSServer` route allowlist。
- 不得绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、pairing、Keychain 或安全范围书签。Canonical protocol/runtime 不得写死 Rokurics local HTTPS/TLS/HMAC；Rokurics 只能通过 adapter 复用现有安全链路。
- Mac 仍不得主动连接 iPhone。Connection runtime 在 Mac 只能消费 incoming heartbeat/status request、记录 liveness、在既有 response path 暴露 pending hint；不得反向拨号或新建 client。
- Heartbeat callback 只能 enqueue existing sync/status work；不得 inline inventory、apply、upload、file tree scan、manifest build、full-file hash 或同步 diagnostics JSONL 写入。
- Transfer runtime 必须通过 existing `SecureMacUploadClient` / `IPhoneCanonicalSecureAudioUploadPort` / `SecureLocalHTTPSServer` upload route 执行真实 start/status/chunk/finalize。生产 port 未启用时必须 fail closed/block canonicalFullSync，不得用 fake ledger 假装 READY。
- `confirmedBytes` 必须单调；start 后必须允许 status refresh/resume；duplicate chunk 只有同 offset/length/hash 才可 idempotent；wrong offset 必须 status refresh/resume 或 fail safe；finalize 必须产生 receiver accepted proof。
- Finalize proof 只是 v9.4 Status Truth input。不得把 completed ledger alone、metadataOnly、receive record alone、partial receive、本地文件存在或 expected manifest hash 当 peer audio proof；不得让 Transfer runtime 直接设置 UI completed/uploaded verified。
- Mac finalize proof fact 只能在既有 finalize route verifier 已通过、route response completed、checksum 与 byteSize 均匹配后产生。partial receive 不 completed；existing different audio 必须 conflict/no-overwrite，不得覆盖。
- View refresh 不得创建 upload job。Retry drainer 只能恢复 existing eligible job；没有 eligible job 时不得创建 fresh canonical transfer job。
- Diagnostics 必须 bounded/redacted。不得写 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response；redaction violation 必须 blocked/rejected。

## Canonical v9.7 / Realtime Status Exchange Runtime Wiring 禁区

- v9.7 只能把 realtime status exchange 接到 existing heartbeat/status 或 inventory carrier。不得声称 canonical kernel 完成；不得把状态交换接线描述成 Connection/Transfer/Sync/File 四域完整 owner、真机收敛或 production cutover 完成。
- default/release 必须继续 `oldKernel`；legacy fallback、legacy sync/upload path、existing `RecordingUploadCoordinator` 和现有 UI/status fallback 必须保留。
- 不得新增 route，不得修改任何 upload route schema，不得在 upload start/status/chunk/finalize route 承载 `statusExchangeEnvelope`，不得改 `SecureLocalHTTPSServer` route allowlist。
- 不得绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、pairing、Keychain 或安全范围书签。Mac 仍不得主动连接 iPhone；Mac 只能在既有 request/response path 中返回 optional envelope 或设置 existing pending sync hint。
- Portable shared exchange runtime 不得写死 Rokurics local HTTPS/TLS/HMAC，不得 import URLSession 或 Network.framework。Rokurics 只能通过 iPhone/Mac adapter 把 optional envelope 放到 existing carrier payload。
- Optional decode 必须 old-peer safe。missing `statusExchangeEnvelope`、missing ack disposition、missing request kind 不得让 decode 失败；旧 peer payload 应按 nil/default 处理。
- Outgoing delta 必须来自 v9.4 fact store snapshot；incoming delta 必须经 `StatusTruthEngine`/`CanonicalStatusTruthRuntime` validate/merge。不得让低证明 fact 覆盖 accepted finalize proof、peer inventory/hash-size proof 或 same hash+byteSize proof。
- Ack 只表示 observed/incorporated/rejected，不得单独作为 peer audio proof，不得让 UI completed/peerVerified/audioAvailable。
- `runSyncSoon` request 只能 enqueue immediate sync/status refresh；不得在 heartbeat/status/inventory callback 内 inline heavy sync、inventory exchange、apply、upload、file scan 或 hash。
- `sendAudioProof` request 只能触发 lightweight proof request/diagnostic；不得创建 fresh upload job。view refresh 仍不得创建 upload job；retry drainer 仍只能恢复 existing eligible job。
- Sequence 必须 per sender monotonic；duplicate delta 必须 idempotent；stale/expired/wrong-destination envelope 必须 deterministic reject 并产生 rejected ack/diagnostic。
- Diagnostics 必须 bounded/redacted。不得写 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response；redaction violation 必须 blocked/rejected。
- MainActor hot path 不得做 file tree scan、manifest build、full-file hash 或同步 diagnostics JSONL 写入。Status exchange route/heartbeat handler 只能做 lightweight decode/merge/enqueue/diagnostic。

## Canonical v9.6 / Effective Status Binding Cutover 禁区

- v9.6 只允许替换已有 UI 状态字段的数据来源。不得新增按钮、提示卡片、用户可见 technical diagnostics，不得改 layout、颜色、字体、间距、导航或重写 View hierarchy。
- default/release 必须继续 `oldKernel`；legacy fallback、legacy upload path 和现有 route/security/topology 必须保留。不得新增 route，不得修改 upload route schema，不得绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、pairing、Keychain 或安全范围书签。Mac 仍不得主动连接 iPhone。
- UI/status model 在 canonicalFullSync gate allowed 时必须消费 `CanonicalEffectiveSyncStatus` 的 display projection；oldKernel、blocked 或 fallback 时必须经 `LegacySyncStatusToCanonicalEffectiveStatusAdapter` 得到 canonical-equivalent display model。
- UI 不得直接把 completed ledger、metadataOnly ledger、receive record、partial receive、本地文件存在或 expected manifest hash 显示为 completed、peerVerified 或 audioAvailable。旧 ledger 只能在 legacy adapter 内转成 canonical facts 后被 rules 拒绝或接受。
- 每个 displayed completed/peerVerified/audioAvailable 必须能追溯 accepted finalize proof、peer inventory/hash-size proof、same hash + same byteSize proof 或 valid dualAck proof chain。completed ledger alone 不得显示 peer verified；metadataOnly 与 partial receive 不得显示 completed。
- peerUnknown 必须显示 deferred/unknown，不得创建 upload job。view refresh/read/status display 不得创建 upload job；retry drainer 仍只能恢复 existing eligible job。
- conflict/no-overwrite 必须显示 blocker/failed/conflict 等现有状态，不得覆盖 peer audio，不得绕过 existing different audio conflict。
- Projection/adapter 不得做 file tree scan、manifest build、full-file hash、同步 diagnostics JSONL 写入或网络请求；不得把 display state 反向作为 business truth 写回 metadata。
- Diagnostics 和文档仍不得泄漏 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response。

## Canonical v9.5 / No-Freeze Hot Path Recovery 禁区

- v9.5 只修 no-freeze 热路径恢复。不得声称 canonical kernel 完成；不得把 diagnostics/read cache/status projection 修复描述成 Connection/Transfer/Sync/File 四域 owner、实时 status exchange 或 paired-device 真机验证全部完成。
- default/release 必须继续 `oldKernel`；legacy fallback、legacy UI status、legacy upload path 和现有 `RecordingUploadCoordinator` 入口必须保留。
- 不得新增 route，不得修改 upload route schema，不得改 `SecureLocalHTTPSServer` route allowlist、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、pairing、Keychain 或安全范围书签。Mac 仍不得主动连接 iPhone。
- `ConnectionDiagnosticsStore.record(...)` 必须保持 hot-path enqueue-only：不得调用 `loadEntries()`，不得 JSON decode 旧 JSONL，不能每个 event atomic rewrite 全文件，不能要求调用方 `await`，不能在 MainActor 执行文件写入。
- diagnostics IO 必须继续通过 `CanonicalAsyncDiagnosticsWriter` 或等价 actor/serial background owner。允许 facade 做 redaction、bounded in-memory recent entries 和 lightweight counters；真实 file IO、append、flush、prune/compaction 必须离开 MainActor hot path。
- diagnostics 写入前必须经过 redaction detector。不得写 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response 或 full local audio path。`diagnosticsWriteDurationMs` 必须来自真实 clock 或 fake clock。
- canonical effective read cache key 不得包含 `generatedAt`、当前 Date 或其他每次快照变化但内容不变的时间戳。key 必须来自 deterministic content signature，并覆盖 recordings、folders/items、artifact availability/hash prefix/byteSize、tombstone/conflict marker、upload/effective status stable fields、selected hierarchy rule、backing revision 和 fallback legacy state。
- repeated iPhone effective items/folders read 与 Mac `tree()` 不得反复 rebuild；read access 不得触发 sync、upload、retry drain、file IO、network IO 或 Store backing mutation。
- status truth projection 不得在 MainActor Store/coordinator/server hot path 反复跑 full reconciliation。MainActor 只能 enqueue fact 或读取 already-built projection snapshot；heartbeat callback 不得执行 reconciliation。
- `CanonicalStatusTruthRuntime` / fact store 的 projection cache 必须维持 deterministic version/content signature。按 objectID/domain 查询应是 map lookup 或 bounded lookup；expired/stale fact cleanup 必须后台执行并保持 redacted diagnostics。
- `metadataOnly`、completed ledger alone、partial receive、receive record only、local file exists 和 expected manifest hash 仍不得成为 peer audio proof。UI refresh 不得创建 upload job；retry drainer 仍只能恢复 existing eligible job。

## Canonical v9.4 / Sync State Truth Protocol 禁区

- v9.4 只实现 proof-driven status truth runtime/read path。不得声称 canonical kernel 完成；不得把只改 SyncCore model/projection/tests/docs 当作 Connection/Transfer/Sync/File 四域 owner 全部完成。
- default/release 必须继续 `oldKernel`；legacy fallback、legacy UI status、legacy upload path、`RecordingUploadCoordinator` 现有入口必须保留，直到后续明确 cutover。
- 不得新增 route，不得修改 upload route schema，不得改 `SecureLocalHTTPSServer` route allowlist、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、pairing、Keychain 或安全范围书签。Mac 仍不得主动连接 iPhone。
- Portable status truth protocol/runtime 不得写死 Rokurics local HTTPS/TLS/HMAC，不得 import URLSession 或 Network.framework；Rokurics 只能通过 adapter 提供 facts。
- completed/peerVerified 只能来自 accepted finalizeProof、peerInventory/hash-size match 或 dualAck + proof chain。metadataOnly、receiveRecordOnly、completed ledger alone、partial receive、local file exists、expected manifest hash 都不得成为 peer audio proof。
- local-only file exists 只能说明 localOnly，不得说明 peerVerified；same hash + same byteSize 才能 no-op；existing different audio 必须 conflict/no-overwrite，不得 overwrite peer audio。
- peerUnknown ordinary sync 必须 deferred。manual force 可以作为 causality/source 表达，但仍不得 bypass security、peer proof、existing-different-audio conflict 或 oldKernel/default gate。
- tombstone 必须阻止 generated artifact resurrection；unsupported schema 必须 blocked/fallback；stale fact 不得覆盖更新 proof。
- `CanonicalEffectiveSyncStatus.canCreateUploadJob` 是唯一 canonical status-based upload job creation permission。view refresh 必须 deny；retry drainer 不得创建 fresh job，只能由外层恢复 existing eligible job。
- Truth engine 不得直接 execute transfer、不得 mutate UI、不得启动 sync、不得做 file tree scan/manifest/full-file hash、不得在 MainActor hot path 写 diagnostics JSONL。
- status truth diagnostics 必须 bounded/redacted；不得写 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response。

## Canonical v9.3 / Transfer Kernel Runtime 禁区

- v9.3 只把 audio upload runtime / resumable upload executor 抽象为 Transfer Kernel runtime owner；不得声称 canonical kernel 完成，也不得把 Transfer proof 输出当作 v9.4 Sync Status Truth 已完成。
- default/release 必须继续 `oldKernel`；legacy fallback、legacy upload path、`RecordingUploadCoordinator` 入口必须保留至后续明确切换集成。
- 不得新增 route，不得新增 `/abort`，不得修改 start/status/chunk/finalize upload route schema，不得改 `SecureLocalHTTPSServer` allowlist、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、pairing、Keychain 或安全范围书签。Mac 仍不得主动连接 iPhone。
- Shared Transfer runtime/protocol 不得写死 Rokurics local HTTPS/TLS/HMAC，不得 import URLSession 或 Network.framework；Rokurics 只能通过 adapter 实现 carrier/security 细节。
- `confirmedBytes` 必须单调；next chunk offset 必须 deterministic；duplicate chunk 只有同 offset/length/hash 才能 idempotent；wrong offset 必须 status refresh/resume 或 fail-safe retry。
- partial receive、metadataOnly、completed ledger alone、receive record alone、local file exists、expected manifest hash 都不得成为 peer audio proof。Transfer finalize proof 只是 v9.4 status truth 的输入，Transfer runtime 不得直接设置 UI completed/uploaded verified。
- finalize 必须验证 byteSize 和可用 hash proof；existing different hash/size 必须 conflict/no-overwrite，不得 overwrite Mac 既有不同 audio。
- retry drainer 只能恢复 existing eligible job；view refresh 不得创建 upload job；peerUnknown、missing local audio、tombstone、conflict、security、malformed ledger 必须 blocked；stale interrupted session 在 status route 可用时必须先 status refresh；max attempt/backoff 必须防 retry storm。
- diagnostics 只允许 safe object/session id、state/reason、offset/byte count、hash prefix、duration/count 等摘要；不得写 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio bytes、full transcript/note/summary/provider response。

## Canonical v9.1 / File Kernel Runtime 禁区

- v9.1 只把 file tree、manifest、checksum、read projection cache diagnostics 和 diagnostics IO 推进到 File Kernel runtime owner 边界；不得声称 canonical kernel 完成，也不得把只改 SyncCore/read projection/scorecard 的工作当作四域完成。
- default/release 必须继续 `oldKernel`；legacy fallback 必须保留。`oldKernel` 与 blocked 下 Mac `/sync/inventory` 不得构建 canonical file snapshot/manifest。
- 不得新增 route，不得修改 route path、upload route schema、`SecureLocalHTTPSServer` allowlist、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、pairing、Keychain 或安全范围书签。Mac 仍不得主动连接 iPhone。
- Portable File runtime 不得写死 Rokurics local HTTPS/TLS/HMAC。Rokurics 只能通过 iPhone/Mac adapter 把已安全归一化的 logical artifact facts 输入 shared runtime。
- File snapshot 输入只能是 root token + safe logical scope/logical token；diagnostics 不得输出 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio、full transcript/note/summary/provider response。
- file tree snapshot、manifest build、full-file hash、diagnostics JSONL write 和 read projection rebuild 不得进入 MainActor hot path。MainActor attempt count 必须来自实际 detector/path，不得 hardcode zero telemetry。
- Manifest runtime 必须纯值构建，不做 file IO。cache key 必须 content-stable：root token、logical token、size、mtime/contentVersion、schema、domain hint/hash prefix；不得只依赖 `generatedAt`。
- Checksum cache 必须 actor-backed；lookup hit 必须跳过 hash provider；size/mtime/contentVersion/schema/algorithm/token/root/domain 变化必须 stale；cache corruption fail-closed 后重建，不得阻断 legacy fallback。
- iPhone repeated UI read 不得触发 file IO/network/sync/upload，不得新增 synthetic `effectiveStudyTree` API；Mac `effectiveStudyTree` 必须继续来自一次性 cached projection。
- v9.1 不得把 File Kernel local existence 当 peer audio proof。`metadataOnly`、completed ledger alone、partial receive、local file exists 仍不得成为 peer audio proof；retry drainer 仍只能恢复 existing eligible job，UI refresh 仍不得创建 upload job。

## Canonical v9.0 / Kernel Contract Freeze 禁区

- v9.0 只定义 canonical 四域 portable contract、状态模型、诊断 taxonomy、cross-domain invariants 和 readiness gate/report 类型。不得把本轮改动接入真实 app runtime，不得新增 route，不得修改 route path、upload route schema、`SecureLocalHTTPSServer` allowlist、`RecordingUploadCoordinator` 执行路径、`StudyLibraryStore` read path、Settings UI 或 `CanonicalKernelSwitch` runtime 行为。
- default/release 必须继续 `oldKernel`；legacy fallback 必须保留。`CanonicalKernelModeMirror` 只能映射现有主开关语义，不得替代 `CanonicalKernelSwitch` 或作为 runtime owner。
- Portable contract 不得绑定本项目的本地 carrier/security implementation；后续只能由 Rokurics adapter 实现。Connection contract 只能表达 carrier/liveness/status/syncRequested hint，不得 mark uploaded、scan file tree、write metadata 或 create upload job。
- Transfer contract 必须把 receiver finalize proof 作为 accepted proof。completed ledger alone、metadataOnly、receive record only、partial receive、local file exists、expected manifest hash 都不得成为 peer audio proof。
- Sync status truth 必须保留 hard proof rules：peerUnknown deferred；same hash + same byteSize 才是 audio no-op；finalize proof 或 peer hash-size proof 才能显示 peerVerified/completed；existing different audio 必须 conflict/no-overwrite；view refresh 不得创建 upload job；retry drainer 只能恢复 existing eligible job。
- Realtime status exchange contract 必须保持 transport-independent，只表达 envelope/delta/ack/request、sequence/logical clock/stale/expire/conflict policy；不得引用具体 app route、carrier class 或 security verifier。
- File contract 必须保持 root-bound relative addressing、atomic/rollback/postcondition 和 no-freeze guarantees。不得允许 MainActor hot path 执行 file tree scan、manifest build、full-file hash 或同步 diagnostics JSONL 写入。
- Diagnostics taxonomy 和 detector 不得允许绝对路径、完整 hash、secret、完整 fingerprint、完整 metadata JSON、request/response body、raw audio、完整 transcript/note/summary/provider response。
- `CanonicalKernelV9ContractReadinessGate.v900(...)` 只能接收 evidence bool 并返回 report；不得执行 sync/upload/read/file/network side effect。route/security bypass、default/release canonical、missing legacy fallback、peer proof violation、MainActor heavy work allowed 或 diagnostics leak 必须返回 `UNSAFE_TO_PROCEED`。
- v9.0 contract freeze 不等于 canonical kernel 完成。任何只修改 model/read projection/canary/evidence/scorecard 且未处理四域 runtime owner、状态真相、实时交换和文件不卡顿的任务，不得声明 canonical kernel 完成。

## Canonical v8.73 / Final App-State Readiness 禁区

- v8.73 只做 Claude 诊断问题最终收口、final app-state readiness gate、targeted 防回归测试和真机 runbook 更新。不得新增 canonical 业务域，不得重写传输层，不得新增 route，不得修改 route path 或 upload route。
- `CanonicalRealDeviceTrialReadinessGate.v873(...)` 是纯 scorecard。不得把 gate 接成 runtime trigger，不得在 gate 中执行 sync、inventory、apply、upload、read projection、文件 IO、网络 IO 或 Store mutation。
- default/release 必须保持 `oldKernel`；用户可见主开关仍是 5 档：`oldKernel`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`。`canonicalFullSync` 仍必须经过 owner approval、manual confirmation、legacy fallback、switch-back proof 和 route/security gate。
- heartbeat 仍不是同步。3 秒 heartbeat 只能做 liveness/status 和 `syncRequested` hint carrier；不得交换 inventory、不得传文件、不得把 heartbeat callback 变成 heavy sync。240 秒 periodic sync 必须保留为 fallback。
- Mac 仍是 HTTPS server，iPhone 仍是 client。Mac 不得主动连接 iPhone；Mac 侧 event trigger 只能设置 existing `syncRequested` hint/pending state 或刷新本地 projection。
- Path B transport 必须保留 legacy TLS/HMAC/pinning/nonce/body hash/upload route/`RequestVerifier`。不得绕过 RequestVerifier，不得改 pairing/certificate/Keychain，不得改安全范围书签。
- read cache 修复不得改变 read runtime 语义；read path 不得触发 sync/upload/retry，不得 mutate backing store。Mac inventory off-main/mode gating 不得改变 `/sync/inventory` response schema、receive.json、audio inbox、transcription/note generation 或 pending sync 语义。
- event-driven trigger 只能进入统一 queue/debounce/dedupe/storm guard；不得在事件 callback 内直接执行 heavy sync，不得创建 upload job。view refresh 不得创建 upload job；retry drainer 不得创建 unrelated fresh job。
- status convergence 不得把 local UI status 当 peer proof；`metadataOnly`、completed ledger alone、partial receive 不得当作 `audioAvailable` 或 uploaded proof；finalize proof 才能推进 uploaded verified。
- diagnostics、runbook、scorecard 和 final report 不得写 secrets、完整 fingerprint、完整 hash、绝对路径、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body、raw audio bytes、full local audio path、delete target path 或 private user content。
- `READY_FOR_REAL_DEVICE_APP_TRIAL` 只表示代码级可以上机试；不得把 simulator、本地 build/test、fake clock、fixture root、realistic-root switch-back proof 冒充 paired-device real-device evidence。没有 paired jsonl 时必须写 `not run; no real-device evidence produced.`

## Canonical v8.72 / Event-Driven Sync Trigger and Status Convergence v1 禁区

- v8.72 只处理 event-driven sync trigger/status convergence projection。不得重写 sync decision、apply runtime、upload runtime、read runtime、canonical domain、主开关 mode、legacy fallback 或默认/release `oldKernel`。
- 所有事件触发只能进入统一 queue/debounce/dedupe；不得在 callback 内直接执行 heavy `performTick`、inventory exchange、apply、upload、download、AI transcription 或 note generation。
- 3 秒 heartbeat 仍是探活/status/hint carrier；不得把 heartbeat 变成 inventory sync。240 秒 periodic sync 必须保留为 fallback，不得改成 3 秒或删除。
- 不得新增 route、改 route path、改 upload route、改 `/sync/inventory` schema、改 receive.json/audio inbox semantics、改 TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、pairing、certificate、Keychain 或安全范围书签。
- Mac 仍是 server，iPhone 仍是 client。Mac event trigger 不得主动连接 iPhone，只能设置既有 `syncRequested` hint/pending state 或刷新本地 projection。
- status convergence 不得把 local UI status 当 peer proof；`metadataOnly`、completed ledger alone、partial receive 不得当作 `audioAvailable` 或 uploaded proof；finalize proof 才能推进 uploaded verified。
- view refresh 不得创建 upload job；retry drainer 只能处理已有 eligible job，不得创建 unrelated fresh job；event trigger 本身不得创建 upload job，只能让后续 existing sync decision path 判断。
- queue 必须有 debounce、duplicate reason coalescing、max frequency、storm suppression、offline/background defer、sync in-flight gate 和 pending follow-up 限制，防止 sync/upload retry storm。
- diagnostics/metrics 必须 bounded/redacted，count/duration/latency 来自真实路径或 fake-clock tests；不得写 secrets、完整 fingerprint、完整 hash、绝对路径、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body、raw audio bytes、full local audio path 或 private user content。
- 没有 paired iPhone/Mac redacted jsonl 时，不得声明状态收敛真机验证完成。下一轮 v8.73 才做真机观察 runbook 与 diagnostics gate。

## Canonical v8.71 / Live Heartbeat Consumes syncRequested 禁区

- v8.71 只处理 Mac manual sync pending -> iPhone live heartbeat `syncRequested` hint -> queued immediate sync tick。不得改传输拓扑，不得让 Mac 主动连接 iPhone，不得把 heartbeat 本身变成 inventory exchange。
- 不得新增 route，不得改 route path，不得改 upload route，不得改 `/sync/inventory` schema，不得改 TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、pairing、certificate、Keychain 或安全范围书签。
- `heartbeatInterval` 继续是 3 秒探活/status；`syncInterval` 继续是 240 秒 periodic sync。不得把 240 秒周期改成秒级，也不得新增新录音/状态变化 event-driven sync trigger。
- live heartbeat 收到 `syncRequested=true` 只能 enqueue/schedule；不得在 heartbeat callback 内直接执行 heavy `performTick`、inventory exchange、apply、upload 或 read。
- queued tick 必须复用现有 sync/manual path，遵守 current kernel switch mode、sync decision、apply/read/upload gates 和安全传输。不得绕过 legacy fallback，不得删除 legacy，不得默认启用 canonical；default/release 必须 oldKernel。
- running/pending/duplicate hint 必须去重或 debounce，避免 reentry/sync storm；失败不得破坏 heartbeat loop。
- Mac pending 状态只能通过现有 heartbeat/status response 广告，并在 iPhone 发起真实 inventory/sync request 后标记 consumed/started/cleared 或保持可观察。不得新增反向拨号或隐式 upload job。
- diagnostics/metrics 必须 bounded/redacted，count/duration/latency 来自真实路径或 fake-clock tests；不得写 secrets、完整 fingerprint、完整 hash、绝对路径、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body、raw audio bytes、full local audio path 或 private user content。
- 本轮只解决“Mac 点同步拉不起 iPhone”的断线；新录音/状态变化触发真同步和更系统的 convergence 仍属 v8.72。没有 paired iPhone/Mac jsonl 时，不得声明状态收敛真机验证完成。

## Canonical v8.70 / Mac Server Inventory Off-Main + Kernel-Mode Build Gating 禁区

- v8.70 只处理 Mac `/sync/inventory` server inventory/manifest/canonical build off-main 与 route-level mode gating。不得改 `syncRequested`、heartbeat、sync interval、event-driven sync trigger、sync decision、read/apply/upload runtime 语义、upload job、route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、主开关 mode 语义、legacy path 或 legacy fallback。
- `/sync/inventory` response schema 与 route behavior 必须保持兼容；不得新增 route，不得改 `/sync/apply`、`/sync/apply-metadata`、`/sync/artifact-request` 或 audio start/status/chunk/finalize routes。
- default/release 必须继续 `oldKernel`。`oldKernel` 和 blocked 下不得构建 canonical recording/library/generated/tombstoneConflict objects，不得构建 canonical manifest，不得运行 canonical seams/readiness，不得把 skipped diagnostics 伪装成 canonical success。
- canonical modes 只能构建该 mode 必需 facts：shadow/diagnostics 只 diff/no-commit，decisionOnly 只 decision，applyNoAudio 不跑 audio commit/read，fullSync 可跑 full seams 但必须使用同一 request-scoped background snapshot。
- seam 不得在同一 request 内重复调用 adapter `makeObjects`、重复 build canonical manifest、重复全量 scan/hash 或重新读取 Store/files；只允许消费 shared snapshot，并在最后发布轻量 diagnostics。
- Mac server route 不得在 MainActor 上执行全量 manifest/canonical/hash/scan。MainActor 只允许 route verification、轻量引用读取、result publish 和 bounded diagnostics。
- manifest/canonical duration 和 count 必须来自真实路径或 test fake clock；MainActor attempt count、skip/reuse/duplicate-prevented count 必须来自实际 detector/path。不得写 hardcoded success 0。
- diagnostics 必须 bounded/redacted；不得写 secrets、完整 fingerprint、完整 hash、绝对路径、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body、raw audio bytes、full local audio path 或 private user content。
- 本轮不得声称状态收敛已修复；`syncRequested`、heartbeat、event-driven sync 和 legacy trigger/topology 仍属 v8.71/v8.72。没有 paired iPhone/Mac jsonl 时，不得声明 Mac 卡顿真机验证完成。

## Canonical v8.69 / Canonical Read Effective Projection Cache 禁区

- v8.69 只处理 canonical read effective projection cache。不得改 sync trigger、heartbeat、sync interval、sync decision、apply runtime、upload runtime、upload job 创建、transport route、upload route、receiver route/security、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain、pairing、主开关 mode 语义、业务域、legacy read path 或 legacy fallback。
- `oldKernel`、disabled、blocked、read failure、divergence 和 fallback legacy 必须继续读 legacy backing arrays；Mac 必须继续使用 stored legacy `studyTree`，不得走 canonical conversion。
- canonical served path 下 items/folders/tree 必须使用同一 cached projection。folders 不得再通过调用 item conversion 重算；Mac tree 不得通过属性链触发重复 items/folders conversion。
- cache invalidation 必须 deterministic：read runtime result/snapshot、read config/mode、legacy backing refresh、fallback state 和 Mac hierarchy rule 变化才重建；相同 key repeated access 不得重建 projection/tree。
- read path 不得触发 sync/upload/download/retry drainer，不得创建 upload job，不得做文件 IO/网络 IO，不得 mutate Store backing arrays；只允许更新 private cache/metrics diagnostics。
- Mac 不得改变 `/sync/inventory` response、`receive.json`、audio inbox、pending sync、transcription/note generation、route/security 或安全范围书签。
- diagnostics 必须 bounded/redacted；不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response、raw audio bytes 或用户内容。count/duration 必须来自真实路径或测试 fake clock，不得写死成功值。
- 没有 paired iPhone/Mac jsonl 时，不得声明卡顿真机验证完成。v8.70 才处理 Mac server inventory off-main，v8.71 才处理 `syncRequested` 心跳接线，v8.71/v8.72 仍需处理 legacy trigger/topology 状态不收敛。

## Canonical v8.68 / T7 Single Kernel Switch UI + Final Code Completion Gate 禁区

- v8.68 只处理 T7：单一主开关 UI、旧分散开关降权说明、final code-completion scorecard/manual switch gate、runbook/docs/tests。不得改 inventory MainActor、read runtime 接线、recording ReadSeam、apply runtime、upload runtime、audio commit executor、production-root write gate 语义、主开关底层 mode 语义、业务域、route、upload route、安全层、legacy path 或 legacy fallback。
- iPhone/Mac Settings 用户可见主开关必须只有 5 档：`oldKernel`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`。默认和 release/default 必须 `oldKernel`；release/default 不得启用 canonical 或 production-root write。
- `canonicalFullSync` 必须二次确认，且继续受 owner approval、manual confirmation、DEBUG/internal、readiness、legacy fallback、route/security unchanged、diagnostics redacted 和 switch-back proof gate 控制。缺任一 gate 必须 blocked，不得 partial silent enable。
- 切回 `oldKernel` 必须立即生效并清除 fullSync confirmation；`oldKernel` 下 sync/apply/existence/audio/read/libraryMetadata pilot 等 canonical owner 必须 disabled/nil。
- 旧分散开关、libraryMetadata pilot、productionRoot flag、read/apply/audio/existence override、UserDefaults debug key 和 test-only injection 只能作为高级限制/诊断，不能把 `oldKernel` 升级成 canonical，不能把 shadow/decision/applyNoAudio 升级出写入、上传、canonical read serving 或 canonical audio upload，不能单独打开 productionRoot write，不能绕过 owner/manual gate。
- Path B transport 必须保留 legacy TLS/HMAC/上传 route；不得新增 route，不得改 upload route，不得改 `RequestVerifier`、pinning、nonce、body hash、Keychain 或安全范围书签。
- diagnostics、scorecard、manual gate、runbook 和 JSONL 不得写 secrets、完整 hash、完整 fingerprint、绝对路径、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body、raw audio bytes、full local audio path 或 delete target path。
- `READY_FOR_REAL_DEVICE_CANONICAL_SWITCH` 只表示代码级可进入真机试运行；没有 paired iPhone/Mac redacted jsonl 时，必须报告 `realDeviceEvidencePresent=false`，不得把 simulator、local build/test、fixture root、fake clock 或 realistic-root proof 冒充真机 evidence。

## Canonical v8.67 / T6 Debug Switch-Back Proof Driver 禁区

- v8.67 只处理 T6：Debug 设置入口、薄 driver、safe temp clone、realistic-root harness 调用、redacted JSONL evidence 和 UI-safe summary。不得改 inventory MainActor、read runtime 接线、recording ReadSeam、apply runtime、upload runtime、audio commit executor、`canonicalFullSync` production-root gate、主开关 mode 语义、业务域、route、upload route、安全层、legacy path 或 legacy fallback。
- switch-back proof 不得在 production root、repo root、home、Desktop/Documents/Application Support 真实生产路径、app data production root、audio production root、study library production root、未标记非 temp root 或 symlink/path escape root 上运行。必须先 clone 到 system temp/test clone 或使用 deterministic fixture/test-harness marker，再通过 `CanonicalSwitchBackRootSafetyGuard`。
- driver 可以把当前 app data root 作为 source root 读取并复制到 temp clone，但不得在 source root 上执行 destructive/crash/switch-back proof，不得写业务域，不得 physical delete/permanent delete/tombstone GC，不得清空 trash，不得 restore/undelete，不得覆盖 existing different audio。
- driver 不得自动把真实 app 主开关切到 `canonicalFullSync`，不得触发 sync/upload，不得创建真实 upload job，不得发送真实网络请求，不得重启 Mac receiver，不得改变 `/sync/inventory`、receiver route/security、`receive.json`、audio inbox、pending sync、transcription 或 note generation。
- evidence JSONL 只能写到 temp proof-run root，不能写 source production root；字段只能包含 redacted diagnostic fields：timestamp、nodeRole、runID、status、rootKind、redactedRootToken、modeSequence summary、domain/crash counts、blocker enums、evidenceKind、realDeviceEvidencePresent 和 relative evidence path。不得写绝对路径、完整 hash、完整 metadata JSON、transcript/note/summary/provider response、request/response body、secret/API key、完整 fingerprint、delete target path、full local audio path 或 raw audio bytes。
- `evidenceKind=realisticRoot` 不能冒充 `realDevice`。没有 paired-device jsonl 时，必须保留 `realDeviceEvidencePresent=false`；simulator、local build/test、fixture root、fake clock 和 realistic-root proof 都不能作为真机验证完成依据。
- 失败或 blocker 必须 surfaced 到 UI-safe summary 和 JSONL event；不得吞错、不得把 production-root rejected 说成数据失败、不得把 evidence redaction violation 当成通过。

## Canonical v8.66 / T4-T5 Executor and Port Injection + Gated Production-Root Write 禁区

- v8.66 只处理 T4/T5：production ports/executors 按主开关 effective mode 注入，以及 `canonicalFullSync` production-root write gate。不得改 inventory MainActor、read runtime 接线、recording ReadSeam、sync decision 语义、主开关 mode 语义、业务域、route、upload route、安全层或 legacy fallback。
- `CanonicalKernelSwitchEffectiveConfiguration` 必须是 app path 唯一权限来源。libraryMetadata pilot、recording/generated/tombstone config、audioUpload runtime config、existence apply config、UserDefaults debug toggle 和 test-only injection 只能降权，不能绕过 `oldKernel`、decisionOnly、applyNoAudio、release/default 或 blocked gate。
- `oldKernel` 下 canonical production executors/ports 必须 nil/disabled/dry-run，legacy apply/upload owner 保留。release/default 必须继续 oldKernel，不得默认 canonical，不得 production-root write。
- diagnosticsOnly/canonicalShadow 只允许 diagnostics/shadow，不得 production write、audio upload 或 canonical read serving；canonicalDecisionOnly 不得 apply/upload/production-root write。
- `canonicalApplyNoAudio` 可注入 gated non-audio apply/existence availability，但必须阻止 canonical audio upload executor/job。metadata-only existence 不得变成 audioAvailable，不得写 audio bytes，不得创建 fake audio file。
- `canonicalFullSync` 只有 DEBUG/internal + ownerApproved + manualConfirmation + legacy fallback + legacy-readable/readiness + route/security + root safety 全部满足，才允许 RealApplyPort constructor 接收 `allowProductionRootWrites=true`。
- production root URL 必须来自现有 app data root / Store root / recording file store root；进入 writable port 前必须过 root safety guard。diagnostics 不得输出绝对路径、完整 hash、secret、完整 fingerprint、完整 metadata JSON、request/response body、raw audio bytes、完整 transcript/note/summary/provider response。
- audio executor 必须复用 existing secure upload path，不得绕过 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient`、TLS/HMAC/pinning/nonce/body hash 或 `RequestVerifier`。
- Mac 不得改变 `/sync/inventory`、`/sync/apply-metadata`、audio start/status/chunk/finalize route behavior、`receive.json` 语义、pending sync、transcription/note generation 或安全范围书签。
- 本地 build/test、simulator、fixture root 或 fake clock 不能当作 production-root write/audio upload 真机 evidence。下一轮 v8.67 才处理 T6：切回证明 driver。

## Canonical v8.65 / T2-T3 Master Switch Read + recordingMetadata ReadSeam Runtime Wiring 禁区

- v8.65 只处理 T2/T3：主开关驱动双端 Store read runtime configuration，以及 recordingMetadata ReadSideSeam 接入 runtime read adapter。不得改 inventory MainActor、sync decision、apply runtime、upload runtime、audio commit executor、production-root write gate、主开关 mode 语义、业务域、route、upload route、安全层或 UI 设计。
- `CanonicalKernelSwitchEffectiveConfiguration.readRuntimeConfiguration` 必须是 app path 的 read owner。specialized read config、debug pilot、tests-only injection 或旧 override key 只能进一步限制，不得把 `oldKernel`、`canonicalDecisionOnly`、`canonicalApplyNoAudio` 或未过 gate 的模式升级成 canonical serving read。
- `oldKernel`、disabled 和 blocked read configuration 必须清空 Store canonical read override 并回 legacy read。release/default 必须继续 oldKernel，不得默认 canonical。
- `canonicalShadow` 只能 parallel compare / non-serving read；`canonicalDecisionOnly` 不 serve canonical read；`canonicalApplyNoAudio` 不得越权 serve canonical read；`canonicalFullSync` 只有在 gate allowed 且 legacy fallback 可用时才可传 guarded canonical read config。
- recordingMetadata ReadSideSeam 必须保留 legacy fallback。divergence、read failure、unsupported input、missing evidence 或 diagnostics blocker 必须 fallback legacy，不得删除 legacy read path 或禁用 legacy fallback。
- read path 不得触发 sync/upload/download/retry drainer，不得创建 upload job，不得 mutate Store backing data，不得写 production root、audio bytes、standalone note、transcript/note/summary/generated artifact content。
- Mac read path 不得改变 `/sync/inventory` response、`receive.json`、audio inbox、pending sync、transcription/note generation、route/security、`RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain 或安全范围书签。
- diagnostics 必须 redacted；不得写绝对路径、完整 hash、完整 metadata JSON、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response 或 raw audio bytes。
- 本地 build/test、simulator、fixture root 或 fake clock 不能当作真机 read-switch evidence；没有 paired iPhone/Mac jsonl 时不得声明真机读切换验证完成。v8.66 才处理 T4/T5：端口/执行器注入与 production-root gated write。

## Canonical v8.64 / T1 Inventory MainActor Residual Closure 禁区

- v8.64 只处理 inventory/runtime snapshot/sync manifest 构建路径的 MainActor 重活残留。不得改 read runtime、recording ReadSeam、apply runtime、upload runtime、audio commit executor、`canonicalFullSync` production-root gate、主开关 mode 语义、业务域、route、upload route、安全层或 legacy fallback。
- `LocalNetworkSyncInventoryBuilder` 不得新增 `@MainActor`，也不得在 builder/runtime snapshot path 中新增全量 metadata load、jobs load、directory scan、metadataHash 或 SHA256 主线程重活。MainActor 只允许轻量配置读取、UI/final result publish 或通知。
- `buildRuntimeSnapshot(...)` 必须消费 background immutable input；不得直接调用 MainActor-isolated Store 重活、不得直接 scan artifact directory、不得直接计算 recording/folder/item metadataHash 或 cache-miss SHA256。
- `makeSyncManifest` 的 T1 路径必须保持 background snapshot -> pure build。pure builder 不得访问 MainActor Store、不得做文件 IO、不得做网络、不得创建 upload job；输出必须兼容既有 `StudyLibrarySyncManifest` wire shape。
- Mac `/sync/inventory` 必须保持 response schema 与 route behavior 不变；不得改 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain、安全范围书签或任何 upload start/status/chunk/finalize route。
- checksum cache key/schema 语义必须保持；cache hit 可以跳过 SHA256，cache miss/stale 才允许在 background path 计算。不得读取完整大音频进内存。
- telemetry duration 必须来自真实 clock 或测试 fake clock，count 必须来自真实 path/cache/detector。正常 0 可以，但不得写 hardcoded 0 作为成功证据；performance guard 必须把 MainActor manifest/hash/scan/metadata/jobs attempts 视为 blocker。
- diagnostics 必须 bounded/redacted；不得写绝对路径、完整 hash、完整 metadata JSON、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response 或 raw audio bytes。
- 本地 build/test、simulator 或 fixture root 不能当作真机卡顿 evidence；没有 paired iPhone/Mac jsonl 时不得写 real-device validated 或“卡顿真机验证完成”。

## Canonical v8.58 / recordingMetadata RealApplyPort + ReadSideSeam 禁区

- v8.58 只处理 `recordingMetadata`：录音 title/name metadata、business modifiedAt、stable business metadataHash、root-bound metadata write/read、canonical-vs-legacy read comparison 和 legacy compatibility。不得扩展到 audio bytes、audio upload、upload ledger、generated artifacts、libraryMetadata、tombstone/conflict、transcript/note/summary/provider content、connection/security 或新 route。
- 必须保留四个承重文件：`IPhoneRecordingMetadataRealApplyPort.swift`、`MacRecordingMetadataRealApplyPort.swift`、`IPhoneRecordingMetadataReadSideSeam.swift`、`MacRecordingMetadataReadSideSeam.swift`。不得用 NoCommit、Cutover、Shadow、Evidence 或 generic port 类型冒充这些文件的职责。
- recordingMetadata RealApplyPort 必须 root-bound、atomic、checkpoint rollback、postcondition verified、legacy-readable、canonical-readable；write/postcondition failure 必须 rollback/fallback，rollback failure 是 fatal blocker。
- recordingMetadata canonical write 不得写 audio bytes、不得创建 upload job、不得改 upload ledger、不得写 standalone note content、不得写 transcript/note/summary/generated artifact content、不得移动资源、不得 physical delete、不得 tombstone GC。
- Mac recordingMetadata RealApplyPort 不得写 `receive.json`，除非未来 legacy recording metadata 格式明确要求并有测试证明不会把 metadata 当 audio；不得写 audio inbox，不得触发 transcription/note generation，不得改 `SecureLocalHTTPSServer` route/security。
- ReadSideSeam 必须遵守主开关：`oldKernel` legacy read；`canonicalShadow`/`canonicalDecisionOnly` diff only；`canonicalApplyNoAudio` 可 diff 但不默认 serve canonical；`canonicalFullSync` 只能在 gate allowed 且 diff clean 时 serve canonical recording metadata。divergence/read failure 必须 fallback legacy。
- read 不得触发 sync/upload/download/retry drainer，不得 mutate Store，不得写 production data，不得改变 Mac inventory response、`receive.json`、audio inbox 或 UI 技术诊断。
- default/release 必须继续 `oldKernel`；specialized recording metadata config 不得越过 `CanonicalKernelSwitch`；legacy fallback 和 legacy recording metadata path 必须保留，switch-back 不得需要 migration。
- diagnostics 只允许 safe object ID、domain/action/state/reason、count、duration、hash prefix 或 redacted summary；不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response 或 raw audio bytes。
- 无 paired iPhone/Mac jsonl real-device evidence 时，只能报告 code/test/doc 层完成；不得报告 real-device validated、release/default canonical、legacy retirement 或删除 legacy fallback。

## Canonical v8.57 / P3-2 Realistic Library Root Switch-Back Proof 禁区

- v8.57 只允许 realistic test root / app-data-root clone proof；不得在 production root 上跑 destructive/crash harness，不得把 fixture 或 unit proof 冒充 real-device evidence。
- `CanonicalSwitchBackRootSafetyGuard` 必须拒绝 `/`、home、repo root、Documents/App Support 生产路径、Rokurics container production root 和未显式标记的非 temp/test clone root；diagnostics 只能写 redacted root token。
- 不得新增业务域、主开关模式、transport route、upload route、security bypass、read projection 内容或 upload executor；TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`、Keychain 和安全范围书签边界必须保持。
- oldKernel/default/release 必须继续为 legacy owner；`canonicalFullSync` 仍必须 DEBUG/internal + manual confirmation + owner approval + fallback + readiness gate。
- switch-back 证明必须覆盖 oldKernel -> canonicalFullSync -> oldKernel -> canonicalFullSync，无 migration、无 repair step、无 physical delete、无 permanent delete、无 tombstone GC、无 legacy deletion/disable。
- 五个业务域必须覆盖 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload`；不得用 support runtime 结果替代业务域证明。
- crash/restart proof 必须 fail closed：partial state 不得被当成 completed/audioAvailable，不得 duplicate job storm，不得 overwrite existing different audio，不得 legacy-incompatible corruption。
- evidence package 不得包含绝对路径、完整 hash、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body、secret、完整 fingerprint、delete target path 或 raw audio bytes。
- realistic-root proof 通过但缺 paired-device jsonl 时，只能报告 `codeCompleteNeedsDeviceEvidence` 或 manual-trial candidate，不得报告 real-device validated 或 legacy retirement。

最近自查日期：2026-06-12

本文记录维护本项目时不应破坏的工程约束。修改前先读 `AGENTS.md`、`CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md` 和本文。

## Canonical v8.56 / P3-1 Unified Master Kernel Switch 禁区

- 本轮只处理统一主开关：`CanonicalKernelSwitch`、effective configuration mapping、gate/blocker、Settings 入口、diagnostics 和 tests。不得新增业务域、route、upload route、canary/evidence/landing/retirement 类型，不得重写 TLS/HMAC/pinning/nonce/RequestVerifier，不得改各域 hash/LWW/read projection 内容。
- 默认和 release/default 必须解析为 `oldKernel`。`oldKernel` 必须关闭 sync decision、existence/apply bridge、non-audio apply、audio upload、read runtime、libraryMetadata pilot 和所有 canonical owner；不得因为旧 UserDefaults、domain-specific config、test fixture 或 runtimeSwitch 变成 canonical owner。
- `canonicalFullSync` 必须同时满足 DEBUG/internal、manual confirmation、owner approval、legacy fallback、legacy read/write/apply path、legacy upload fallback、inventory/sync/apply/audio/read runtime readiness、五域 readiness、diagnostics redaction、route/security unchanged、safe production-root config、无 unresolved conflict、无 switch-back hard blocker、无 canonical-only disk format blocker。缺任一项必须 blocked，不得 partial silent enable。
- `diagnosticsOnly` 与 `canonicalShadow` 不得写 production root、不得上传、不得 serve canonical read、不得 suppress legacy duplicate。`canonicalDecisionOnly` 不得 apply/upload/read canonical。`canonicalApplyNoAudio` 不得 canonical audio upload。`canonicalFullSync` 也不得绕过已有 runtime/domain/security gate。
- advanced overrides 和旧专项配置只能降权或限制，不能提升权限。它们不得从 `oldKernel`、`diagnosticsOnly`、`canonicalShadow`、`canonicalDecisionOnly` 或 `canonicalApplyNoAudio` 升级出 canonical apply/upload/read，也不得关闭 fallback/redaction、启用 runtimeSwitch、扩大 domain/scope、允许 production-root unsafe write 或绕过 master switch。
- 旧 `CanonicalLibraryMetadataDebugPilotConfiguration` 不得绕过主开关写 production root。真实 app path 必须使用 master effective config；测试可以直接注入 test-only 配置，但不得被描述为 app 默认或 release 行为。
- diagnostics 只允许 mode、nodeRole、syncRunID、runtime/domain enabled booleans、blocker enum、counts、hash prefix 和 redacted summary；不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response、raw audio bytes 或 full local audio path。
- v8.56 只说明切回 `oldKernel` 在行为/config 层立即生效；真实库 switch-back proof 是 v8.57/P3-2。不得把合成测试或 fixture 当作 real-device evidence，不得据此删除/禁用 legacy fallback。

## Canonical v8.55 / P2-5 audioUpload Domain Readiness 禁区

- 本轮只处理 `audioUpload`：audio existence/upload candidate/no-op/conflict、metadataOnly/receiveRecordOnly/studyItemOnly upload-needed、peerUnknown deferred、resumable session/chunk/confirmedBytes/finalize、retry state、ledger state、Mac receive audio availability 和 read/status projection。不得改 recordingMetadata、libraryMetadata、generatedArtifacts、tombstoneConflict、transcript/note/summary、standalone note、provider response、connection/security 或 UI design。
- audioUpload proof schema 必须保持 `canonical-audio-upload-v1`。域 diagnostics/read projection 只允许 safe object/session identifiers、state/reason、hash prefix、byte count、offset、confirmedBytes、retry count 和 duration/status summary。不得输出完整本地 audio path、绝对路径、raw audio bytes、完整 hash、完整 metadata JSON、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response。
- metadataOnly、receiveRecordOnly、studyItemOnly、metadata uploaded、UI uploaded、partial receive、failed session、completed ledger alone 和 expected manifest hash/byteSize 都不得当作 `audioAvailable`、uploaded 或 no-op proof。
- peerUnknown 必须 deferred；local audio missing 必须 blocked/no candidate；tombstoned parent 必须 blocked；same hash + same byteSize 才能 no-op；different hash/size 或 existing different Mac audio 必须 conflict/no-overwrite。
- uploaded/completed 只能在 Mac finalized proof 或 peer finalized same hash+byteSize proof 之后成立；finalize proof missing 时不得 mark uploaded、不得清 retry job、不得 suppress legacy completed state。
- `oldKernel` 和 release/default 必须 legacy owner；diagnosticsOnly/canonicalShadow 只比较不建 job；canonicalDecisionOnly 不发网络；canonicalApplyNoAudio 必须阻止 canonical audio upload；canonicalFullSync 只能 DEBUG/internal + owner approval/manual confirmation + gate allowed + fallback retained。
- canonical commit 必须复用 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier` 和现有 start/status/chunk/finalize routes。不得新增 route/upload route，不得改变 route contract，不得绕过 TLS/HMAC/pinning/nonce/body hash、Keychain 或安全范围书签。
- 大音频必须 bounded chunk streaming；不得一次性读完整 audio 进内存。confirmedBytes 必须单调，duplicate chunk 只能在同 offset/length/hash 时 idempotent，wrong offset 必须 status/resume 或 fail safe。
- retry drainer 只能 resume existing eligible canonical/legacy job；不得由 view refresh 或 read/status path 创建 fresh job；backoff/max retry/security failure/malformed ledger/conflict/peerUnknown 必须 fail closed 或 defer。
- read/status projection 必须 gated；read/status 不得触发 upload、retry drain、sync/download、Store mutation、文件移动或重 hash heavy work；projection failure、divergence、missing proof、release/default 必须 fallback legacy。
- duplicate suppression 只能在 canonical exact same scope/object/action 成功并通过 finalize/postcondition proof 后发生；diagnostics/noCommit/blocked/planning failure/security failure/conflict/fallback 不得 suppress legacy。
- Domain matrix / scorecard 中 `readyToRetireLegacyReportOnly` 只能 report-only；不得删除、禁用或跳过 legacy upload path/fallback。无 paired-device jsonl evidence 时 `realDeviceEvidencePresent=false`。

## Canonical v8.54 / P2-4 tombstoneConflict Domain Readiness 禁区

- 本轮只处理 `tombstoneConflict`：soft object/library tombstone marker、conflict record、resurrection block record、tombstoneState/displayState、conflictResolutionState 和 businessModifiedAt/logical event time。不得扩展到 audio upload/audio bytes、generated artifact 内容删除、recordingMetadata/libraryMetadata decision、connection/TLS/HMAC/pinning/nonce/RequestVerifier 或新 route。
- tombstoneConflict hash schema 必须保持 `canonical-tombstone-conflict-v1`，只包含 markerID、objectID、objectKind、markerKind、conflictKind、tombstoneState、displayState、businessModifiedAt、actorDeviceRole、parentObjectID、conflictResolutionState。不得把 physical/delete target path、absolute/local/resource path、完整 metadata/content、standalone note 正文、generated content、provider response、audio facts、upload/receive state、observedAt/receivedAt、UI-only state 或 diagnostics 纳入 hash。
- `CanonicalTombstoneConflictCandidate.markerHash` 必须派生自同一 business schema；不得恢复旧 v8-11 payload 或维护第二套 tombstone/conflict hash 口径。
- ModifiedAt/LWW 必须使用 businessModifiedAt 或 logical event time；不得用 receivedAt、observedAt、inventory scan time、upload/receive time 或 UI time。equal logical time 且 hash 不同必须 deterministic defer/conflict record，不得自动覆盖。
- restore、clear tombstone、physical delete、permanent delete、tombstone GC、generated artifact deletion 和 audio deletion 都不得由本域执行。stale live resurrection 必须写 resurrection block/conflict record 或 fallback/block，不得恢复对象或把旧 live metadata 当权威。
- `oldKernel` 和 release/default 必须 legacy owner；diagnosticsOnly/canonicalShadow 只比较不写不切 read；canonicalDecisionOnly 不写；canonicalApplyNoAudio 不碰 audio；canonicalFullSync 只能 DEBUG/internal + owner approval/manual confirmation + gate allowed + fallback retained。
- canonical tombstone/conflict apply 必须使用既有 root-bound tombstone/conflict executor，atomic write、checkpoint rollback、postcondition verified、legacy-readable；write/postcondition failure 必须 rollback，rollback failure 是 fatal blocker。不得新增 route、不得绕过 root-bound/rollback/postcondition，不得 auto-resolve conflict。
- canonical tombstoneConflict read 必须 gated；read 不得触发 sync/upload/download/retry drainer，不得 mutate Store，不得 delete/restore/GC，不得输出 delete target path、完整 hash、完整 content 或技术诊断到 UI。projection failure、divergence、unsupported marker、schema mismatch 或 release/default 必须 fallback legacy。
- duplicate legacy suppression 只能在 canonical 同一 scope/object/action 成功 commit 且 pre/postcondition verified 后发生；diagnostics/noCommit/blocked/planning failure/rollback/fatal rollback 不得 suppress legacy。
- diagnostics 只允许 syncRunID、nodeRole、objectID/markerID prefix、domain、markerKind/action/state/reason、hash prefix、logical time summary、count、durationMs。不得写完整 metadata JSON、完整 hash、绝对路径、delete target path、secret、完整 fingerprint、request/response body、完整 note/generated/provider response 或 raw audio bytes。
- Domain matrix / scorecard 中 `readyToRetireLegacyReportOnly` 只能 report-only；不得删除、禁用或跳过 legacy tombstone/conflict path。无 paired-device jsonl evidence 时 `realDeviceEvidencePresent=false`。

## Canonical v8.53 / P2-3 generatedArtifacts Domain Readiness 禁区

- 本轮只处理 `generatedArtifacts`：transcript/note/summary artifact 的 metadata、availability、kind/type、stable IDs、recording parent relation、contentHash、byteSize 和 business modifiedAt。不得扩展到 recordingMetadata、libraryMetadata、standalone note full content、provider response、AI call/transcription/generation、audio upload/audio bytes、upload ledger、tombstone/conflict、connection/TLS/HMAC/pinning/nonce/RequestVerifier 或新 route。
- generated artifact hash schema 必须保持 `canonical-generated-artifact-v1`，只包含 artifactID、objectID、kind、availability、contentHash algorithm/value、byteSize、businessModifiedAt。不得把 local/logical path、observedAt、producer node、provider request/response、正文内容、diagnostics、audio bytes、upload/receive state、security material 或 tombstone 纳入 hash。
- contentHash + byteSize 相同必须 no-op；hash-only、size-only、availableWithoutHash、unknown/missing availability 都不得作为 apply proof。缺 contentHash/byteSize、缺 business modifiedAt、unsupported kind、audio 混入、schema mismatch 或 parent/tombstone 风险必须 defer/block/fallback。
- ModifiedAt/LWW 只能在双方 generated artifact content proof 完整且内容不同的情况下使用；不得用 observedAt、download time、provider time、inventory scan time 或 receive/upload time。equal modifiedAt 且内容不同必须 deterministic defer/conflict，不得自动覆盖。
- `oldKernel` 和 release/default 必须 legacy owner；diagnosticsOnly/canonicalShadow 只比较不写不切 read；canonicalDecisionOnly 不写；canonicalApplyNoAudio 可 apply generated artifacts 但不得写 audio；canonicalFullSync 只能 DEBUG/internal + owner approval/manual confirmation + gate allowed + fallback retained。
- canonical generated artifact apply 必须使用既有 root-bound generated artifact apply port，atomic write/copy、checkpoint rollback、postcondition verified、legacy-readable；write/postcondition failure 必须 rollback，rollback failure 是 fatal blocker。不得新增 route、不得绕过 checksum/byteSize/root-bound 校验、不得创建 generated artifact upload job、不得触发 transcription/note/summary generation 或 AI provider call。
- canonical generated artifact read 必须 gated，且只读 metadata/availability/hash prefix/byteSize/kind。read 不得触发 sync/upload/download/retry drainer，不得 mutate Store，不得写文件，不得读取或输出正文。projection failure、divergence、unsupported artifact、content leak risk、unsafe path token、missing evidence、schema mismatch 或 release/default 必须 fallback legacy。
- duplicate legacy suppression 只能在 canonical 同一 scope/artifact/action 成功 commit 且 pre/postcondition verified 后发生；diagnostics/noCommit/blocked/planning failure/rollback/fatal rollback 不得 suppress legacy。
- diagnostics 只允许 syncRunID、nodeRole、objectID/artifactID prefix、domain、kind、action、state、reason、hash prefix、byteSize、count、durationMs。不得写完整 transcript/note/summary/provider response、完整 artifact content、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、raw audio bytes 或用户内容。
- Domain matrix / scorecard 中 `readyToRetireLegacyReportOnly` 只能 report-only；不得删除、禁用或跳过 legacy generated artifact path。无 paired-device jsonl evidence 时 `realDeviceEvidencePresent=false`。

## Canonical v8.52 / P2-2 libraryMetadata Domain Readiness 禁区

- 本轮只处理 `libraryMetadata`：folder/study item/standalone-note shell 的 title/name、parent/filing/folder references、tags、color/order、deleted metadata、businessModifiedAt 和 stable metadataHash。不得扩展到 note full content、generated artifact content、audio bytes、audio upload、upload ledger、receive session/chunk/finalize、recordingMetadata、tombstone/conflict/delete/GC、connection/TLS/HMAC/pinning/nonce/RequestVerifier 或新 route。
- libraryMetadata hash schema 必须保持 `canonical-library-metadata-v1`，只包含 stable business metadata。不得把 local path、resource path、logical resource tokens、note content、generated content、audio hash/byteSize、upload/receive/sync state、provider response、diagnostics 或 security material 纳入 hash。
- resource move/path/token 变化不得改变 libraryMetadata metadataHash；如要处理资源移动，必须由未来 resource/domain 明确设计，不得借 metadata hash 隐式触发。
- ModifiedAt/LWW 必须使用 businessModifiedAt；不得用 receivedAt、observedAt、upload time、diagnostic time 或 inventory scan time。equal modifiedAt 且 hash 不同必须 deterministic defer/conflict，不得自动覆盖。
- `oldKernel` 和 release/default 必须 legacy owner；diagnosticsOnly/canonicalShadow 只比较不写不切 read；canonicalDecisionOnly 不写；canonicalApplyNoAudio 不碰 audio；canonicalFullSync 只能 DEBUG/internal + owner approval/manual confirmation + gate allowed + fallback retained。
- canonical libraryMetadata apply 必须 root-bound、atomic、checkpoint rollback、postcondition verified；write/postcondition failure 必须 rollback，rollback failure 是 fatal blocker。不得移动 resource、不得写 standalone note content、不得写 generated content、不得写 audio/upload/receive/session state、不得 physical delete 或 tombstone GC。
- canonical libraryMetadata read 必须 gated；read 不得触发 sync/upload/download/retry drainer，不得 mutate Store，不得移动资源，不得输出完整 path/hash/content/provider response。projection failure、divergence、unsupported object、missing evidence、schema mismatch 或 release/default 必须 fallback legacy。
- duplicate legacy suppression 只能在 canonical 同一 scope/object/action 成功后发生；diagnostics/noCommit/blocked/planning failure 不得 suppress legacy。
- diagnostics 只允许 syncRunID、nodeRole、objectID、domain、action、state、reason、hash prefix、modifiedAt summary、count、durationMs。不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整 note/transcript/summary/provider response、generated content、raw audio bytes 或用户内容。
- Domain matrix / scorecard 中 `readyToRetireLegacyReportOnly` 只能 report-only；不得删除、禁用或跳过 legacy library metadata path。无 paired-device jsonl evidence 时 `realDeviceEvidencePresent=false`。

## Canonical v8.51 / P2-1 recordingMetadata Domain Readiness 禁区

- 本轮只处理 `recordingMetadata`：录音 title/name、business modifiedAt、stable business metadataHash、录音 filing/tags/deleted metadata，以及已有模型支持的 createdAt/duration read facts。不得扩展到 audio bytes、audio upload、upload ledger、receive session/chunk/finalize、transcript/note/summary/generated content、libraryMetadata、tombstone/conflict、delete/GC、connection/TLS/HMAC/pinning/nonce/RequestVerifier 或新 route。
- recordingMetadata hash schema 必须保持 `canonical-recording-business-metadata-v1`，只包含 stable business metadata。不得把 upload progress、upload ledger、receive status、receivedAt、observedAt、local path、audio path、audio hash/byteSize、processing status、diagnostics、provider response、transcript/note/summary/generated content 纳入 hash。
- ModifiedAt/LWW 必须使用业务 modifiedAt；不得用 receivedAt、observedAt 或 upload time。旧 iPhone model 缺独立 business modifiedAt 时，必须 documented fallback 或 block/fallback legacy；equal modifiedAt 且 hash 不同必须 deterministic defer/conflict，不得自动覆盖。
- `oldKernel` 和 release/default 必须 legacy owner；diagnosticsOnly/canonicalShadow 只比较不写不切 read；canonicalDecisionOnly 不写；canonicalApplyNoAudio 不碰 audio；canonicalFullSync 只能 DEBUG/internal + owner approval/manual confirmation + gate allowed + fallback retained。
- canonical apply 必须 root-bound、atomic、checkpoint rollback、postcondition verified；write/postcondition failure 必须 rollback，rollback failure 是 fatal blocker。不得写 audio bytes、不得创建 upload job、不得 mutate upload ledger/receive session、不得移动 resource、不得写 generated content、不得 physical delete 或 tombstone GC。
- canonical read 必须 gated；read 不得触发 sync/upload/download/retry drainer，不得 mutate Store，不得 heavy scan on MainActor，不得显示 technical diagnostics。projection failure、divergence、unsupported object、missing evidence 或 release/default 必须 fallback legacy。
- duplicate legacy suppression 只能在 canonical 同一 scope/object/action 成功后发生；diagnostics/noCommit/blocked/planning failure 不得 suppress legacy。
- diagnostics 只允许 syncRunID、nodeRole、objectID/recordingID、domain、action、state、reason、hash prefix、modifiedAt summary、count、durationMs。不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response、raw audio bytes 或用户内容。
- Domain matrix / scorecard 中 `readyToRetireLegacy` 只能 report-only；不得删除、禁用或跳过 legacy recording metadata path。无 paired-device jsonl evidence 时 `realDeviceEvidencePresent=false`。

## Canonical v8.50 / P1-3 upload retry drain/state consistency 禁区

- 不得把 v8.50 解释为新 upload executor、read cutover、UI cutover、sync decision rewrite、route migration 或 security rewrite；它只收齐 upload state truth、retry drain、duplicate ownership 和 diagnostics。
- `CanonicalUploadStateTruth` 必须拒绝 metadataOnly、receiveRecordOnly、studyItemOnly、metadata uploaded、UI uploaded、completed ledger alone 作为 `audioAvailable`、uploaded 或 no-op proof。
- upload completed verified 必须有 Mac finalized proof 或 peer inventory 已证明 finalized same hash+byteSize；expected manifest hash/byteSize 不是 peer proof。
- peerUnknown 必须 deferred；missing local audio 必须 absent/no candidate；tombstoned parent 必须 blocked；different hash/size 必须 conflict；existing different audio 不得覆盖。
- same hash + same byteSize 才能 no-op；hash-only 或 size-only 都不得 no-op。
- retry drainer 只能 resume existing eligible canonical/legacy job，不得创建 unrelated fresh job，不得由 view refresh 创建 job。
- retry drainer 必须尊重 persisted backoff、max retry、security failure、malformed ledger、missing file、tombstone/conflict stop condition，避免 retry storm。
- stale interrupted session 只有在 existing status route 支持并刷新 confirmedBytes 后才能继续；不得绕过 `RecordingUploadClient`、`SecureMacUploadClient` 或 existing upload clients。
- `oldKernel` 只能 legacy owner；diagnostics/shadow/decision/apply-no-audio modes 不得创建 canonical audio upload job；`canonicalFullSync` 仍须 gate allowed。
- canonical started/finalized proof accepted 后只能 suppress exact equivalent legacy fresh duplicate；proof missing 时不得 suppress legacy completed state。
- canonical security failure 不得 fallback 成绕过安全；canonical conflict 不得 fallback 成覆盖 existing different audio；legacy job running 时 canonical 不得开 duplicate。
- diagnostics 只能写 syncRunID、nodeRole、objectID/recordingID、sessionID prefix、offset/confirmedBytes/totalBytes/chunkSize、hash prefix、state、reason、retry count、durationMs；不得写绝对路径、完整 hash、完整 metadata JSON、secret、完整 fingerprint、request/response body、raw audio bytes、完整 transcript/note/summary/provider response。
- 没有 paired-device retry/resume/finalize evidence 时，不得声称 v8.50 真机完成。

## Canonical v8.49 / P1-2 audio upload commit 禁区

- canonical audio upload commit 必须默认/release disabled；真实 owner 只能在 explicit DEBUG/internal owner-approved policy 或 fake test transport 下启用。
- 必须保留 legacy `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` fallback；canonical failure 不得 silent partial success。
- 不得新增 upload route、不得新增 abort route、不得修改 existing upload route contract；只能使用现有 start/status/chunk/finalize。
- 不得绕过 TLS certificate pinning、HMAC、nonce、body hash、`RequestVerifier`、Keychain 或安全范围书签；不得把 manifestHash 当鉴权。
- 大音频必须 bounded chunk streaming；不得一次性把完整 audio 读入内存，不得在 diagnostics 写 raw audio bytes。
- finalize proof 是唯一上传完成边界：Mac finalize success、stored byteSize 匹配、expected hash 匹配后，才可 mark uploaded、清 retry、suppress exact duplicate legacy action。
- metadataOnly、receiveRecordOnly、studyItemOnly、UI uploaded、metadata uploaded、completed ledger alone 都不得当作 `audioAvailable`、audio uploaded 或 no-op proof。
- same hash + same byteSize 才是 audio no-op；peerUnknown 必须 deferred；different hash/size 必须 conflict；existing different Mac audio 不得覆盖。
- view refresh 不得创建 fresh upload job；retry drainer 只能 replay existing eligible retry，不得创建 unrelated fresh job。
- retry/session persistence 不得记录绝对路径、secret、完整 fingerprint、request/response body；diagnostics 只允许 redacted session/object/offset/count/hash prefix/state/reason。
- finalize 后 rollback 不是 delete；不得物理删除 audio/transcript/note/summary/resource，不得执行 permanent delete 或 tombstone GC。
- 没有 paired-device 新录音/长录音 evidence 时，不得声称 v8.49 真机完成或 release/default canonical enabled。

## Canonical v8.48 / P1-1 manifest.recordings apply 禁区

- Mac apply 必须消费 `manifest.recordings`，但只能写 canonical metadata-only existence ledger；不得写 audio bytes、不得创建 fake audio file、不得写 legacy `receive.json` 来切 read path。
- metadataOnly、receiveRecordOnly、studyItemOnly、metadata uploaded、UI uploaded 或 completed ledger alone 都不得当作 `audioAvailable`、audio uploaded 或 audio no-op proof。
- Mac inventory 可以报告 metadata-only recording exists，但必须 `audioAvailable=false`；无真实 audio file 时不得报告 audio path、proven audio hash 或 byteSize。
- same hash + same byteSize 才是 audio no-op；different hash/size 必须 conflict/blocker；existing different audio 不得覆盖。
- peerUnknown 必须 deferred；local audio missing + peer metadataOnly 不得创建 upload candidate；tombstoned parent 必须阻断 metadata apply/upload candidate。
- iPhone upload candidate 只能交给 existing upload evaluator / `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient`；本轮不得实现 canonical audio upload commit executor。
- view refresh 不得创建 fresh upload job；retry drainer 只能 replay existing eligible retry，不得创建 unrelated fresh job。
- 不得新增 route、修改 upload route、绕过 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、把 manifestHash 当鉴权、改变 read path、改变主开关语义、删除 legacy 或禁用 legacy fallback。
- diagnostics 必须 redacted，只能输出 syncRunID、nodeRole/objectID/action/state/reason/hash prefix/byte count/count；不得输出绝对路径、完整 hash、完整 metadata JSON、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response 或 audio bytes。
- 没有 paired-device 新录音证据时，不得声称 v8.48 真实端到端完成。

## Canonical v8.46 sync kernel completion 禁区

- 不得把 fake `count=0` diagnostics 当作 off-main 证据；inventory report 必须区分 mainActor attempt count 与 blocked count。
- iPhone inventory background builder 不得调用 MainActor-isolated store load API；新增字段只能记录真实 metadata load、scan/hash、cache/reuse 和 blocker 事实。
- Mac inventory 当前仍 `@MainActor`；在真正 off-main 前必须保留真实 blocker count，不得把 blocker 改回 0 或在文档中声称 Mac inventory 已 off-main 完成。
- `manifest.recordings` apply 只能在显式 non-disabled existence apply config 且注入 canonical recording existence apply port 时执行；默认 `StudyLibraryStore` 必须 no-op。
- Mac metadata-only apply 不得写 audio bytes、不得写 legacy `receive.json`、不得 mark upload completed、不得把 metadataOnly 当 audioAvailable；`audioAvailable=false` 是无音频证明时的固定边界。
- 不得新增或修改 upload route，不得绕过 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、Keychain 或安全范围书签。
- 不得删除 legacy planner/store/route/read/write/apply/upload/fallback，不得执行 legacy retirement，不得改变 default/release `oldKernel`。
- Unit/simulator/macOS tests 不得冒充 paired real-device evidence；没有真机 runbook evidence 时只能报告 code-complete candidate 或 remaining blocker。

## Canonical 2026-06-08 sync kernel finalization 禁区

- 允许范围仅限同步链路 code-complete 接线、read runtime owner、audio upload runtime owner、scorecard/gate/evidence/runbook/switch-back proof；不得迁移连接链路或横向新增其它业务域。
- 默认和 release 必须保持 `oldKernel`；不得默认启用 canonical，不得 release/default 访问 `canonicalFullSync`。
- 不得新增 upload route，不得修改现有 upload route，不得绕过 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`。
- 不得删除、禁用或跳过 legacy planner/store/route/read/write/apply/upload/fallback；切回 `oldKernel` 必须无需 migration。
- Read runtime 不得触发 sync/upload/download/retry drainer，不得 mutate store，不得移动资源，不得写 production data；divergence 或 exception 必须 fallback legacy。
- Audio runtime 不得 full-buffer 大音频；不得让 view refresh 创建 fresh upload job；retry drainer 不得创建 unrelated fresh job；peerUnknown 必须 deferred；metadataOnly/completed ledger alone 不得当 audio proof；existing different audio 不得覆盖。
- Diagnostics/evidence 不得输出绝对路径、完整 hash、secret/token、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response、generated content 或 audio bytes。
- Test fixture、unit test、synthetic harness、test-cloned realistic root proof 都不得冒充 real-device evidence。

## Canonical v8.45 completion gate / manual switch runbook 禁区

- 2026-06-07 v8.45 是 gate-only 旧状态；2026-06-08 起允许同步链路内的 read/audio owner 接线，但仍不得新增 route、改变 default/release、删除 legacy 或禁用 fallback。
- `CanonicalSyncKernelCompletionScorecard` 的 code-complete 不等于真机完成；缺 paired-device logs 时必须是 `codeCompleteNeedsDeviceEvidence`，不得报告 `readyForManualSwitchTrial`。
- Scorecard 任一 code item 或 domain readiness 不完整必须 `incomplete` 或 `blocked`，不得 silent pass。
- Domain ready-to-retire report 只能 report-only；必须保持 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`。不得删除、禁用、跳过或清理 legacy planner/store/route/read/write/fallback。
- `CanonicalSyncKernelEvidenceExporter` 不得输出绝对路径、完整 hash、secret、token、证书私钥、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response、generated content、audio bytes 或本机隐私路径。
- `CanonicalSyncKernelManualSwitchGate` 只能允许手动 trial；不得允许 release/default 切到 canonical。Gate 必须要求 scorecard code complete、compatibility proof、switch-back proof、default oldKernel、release oldKernel、diagnostics redacted、legacy fallback、无 unresolved blocker、owner approval 和 manual backup acknowledged。
- 缺 backup acknowledgement、缺 switch-back proof、release/default canonical、diagnostics not redacted、fallback unavailable 或 unresolved blocker 时必须 blocked。
- Runbook 中的 `canonicalFullSync` 只用于 DEBUG/internal/manual trial；不得解释为 release default、legacy retirement、schema migration、physical move/delete 或 no-fallback cutover。
- Required grep events `canonicalInventoryRuntime*`、`canonicalSyncRuntime*`、`canonicalExistence*`、`canonicalApplyRuntime*`、`canonicalAudioUploadRuntime*`、`canonicalReadRuntime*`、`canonicalKernelSwitch*`、`Divergent`、`FreezeViolation`、`RollbackFailed`、`ConflictBlocked`、`ExistingDifferentAudioBlocked` 必须 redacted 后进入 evidence package。

## Canonical v8.44 legacy compatibility / switch-back 禁区

- `CanonicalLegacyCompatibilityMatrix` 必须覆盖 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`recordingExistence`、`audioUpload`、`readRuntime` 七个域；新增域必须显式加入 matrix 和双端测试。
- 每个域必须证明 canonical write format legacy-readable、legacy write format canonical-readable、switch-back no migration、no canonical-only required field、unknown fields ignored/backward compatible、rollback available、diagnostics redacted。
- `canonicalFullSync` 写入后的数据必须能被 `oldKernel` legacy read/write path 读取和修改；切回旧内核不得要求 schema migration、数据转换、重写、删除、清理 staging root 或人工修复。
- canonical 写入只能使用 legacy-readable 或 dual-write-compatible 格式；不得把 canonical-only 字段设为旧内核读取必需字段。
- legacy 写入可以忽略或丢弃 unknown canonical 字段，但 canonical read 必须继续接受旧格式；不得把 unknown field 保留作为正确性前提。
- partial canonical write failure 必须 rollback 到 checkpoint 或阻断 incomplete state；rollback 不得物理删除非本轮新增数据，不得删除 audio/transcript/note/summary/resource。
- crash before checkpoint、after checkpoint before write、after write before postcondition、after postcondition before duplicate suppression 都必须 no data loss；oldKernel restart 必须可读；canonicalFullSync restart 必须可恢复或安全阻断。
- duplicate legacy suppression 只能在完整 postcondition 后执行；postcondition 后 crash 但 suppression 前 restart 时不得假装 suppression 已发生。
- compatibility diagnostics 必须 redacted，不得写完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整 transcript/note/summary/provider response、audio bytes 或用户内容。
- v8.44 是证明层，不是 legacy retirement。不得删除、禁用、跳过或清理 legacy planner、legacy store、legacy route、legacy read/write path、legacy fallback、retry drainer、Mac pending sync 或物理文件。

## Canonical v8.43 unified kernel switch 禁区

- `CanonicalKernelSwitchConfiguration` 必须是 canonical runtime behavior owner 的唯一主入口；新增细开关不得与主开关产生矛盾。
- 默认和 release 必须解析为 `oldKernel`；不得在 release/default 选择 `canonicalFullSync` 或任何 canonical owner。
- `oldKernel` 必须禁用 sync/apply/existence/audio/read/libraryMetadata 的 canonical ownership；legacy read/write/apply/upload path 必须保留。
- 主开关是行为 owner 开关，不是数据格式开关；不得通过它触发 schema migration、physical move/delete、legacy path deletion 或 legacy-readable format 破坏。
- canonical write 只能使用 legacy-readable disk format 或 dual-write-compatible format；不得写 canonical-only required field，除非有 legacy-compatible fallback。
- 切回 `oldKernel` 必须不需要数据转换、重写、迁移、删除或手动清理。
- `canonicalFullSync` 只能 DEBUG/internal + owner-approved + manual confirmation + non-release/default + fallback available + reversibility proof 全部通过。
- `diagnosticsOnly`、`canonicalShadow` 和 `canonicalDecisionOnly` 不得提交写入、不得创建 upload job、不得 serve canonical read。
- `canonicalApplyNoAudio` 不得启用 canonical audio upload 或 guarded read serving；audio upload/read fallback 必须保留。
- `blocked` 或 invalid mixed advanced override 必须把 canonical effective configs 置为 blocked，不得 fallback 到一个矛盾的半开配置。
- shadow comparison 必须可在 canonical owner active 时继续保留；不得以 full sync 为由关闭 shadow comparison。
- Settings 主开关必须 `DEBUG` only；Release UI 不显示。切 full sync 必须确认；切回旧内核必须立即清除确认。
- 既有 libraryMetadata debug pilot 只能作为高级专项开关；不得继续作为新旧内核主要入口。
- diagnostics 必须 redacted，不得写完整 hash、绝对路径、secret、完整 fingerprint、证书私钥、request/response body、完整 transcript/note/summary/provider response 或个人隐私路径。

## Canonical v8.42 read runtime v1 禁区

- v8.42 canonical read runtime 必须默认 disabled；release/default 不得启用 canonical read serving。
- `guardedCanonicalReadWithLegacyFallback` 只能用于 explicit debug/internal owner-approved 配置，并且必须保留 legacy fallback。
- `parallelCompare` 必须返回 legacy，只能比较 canonical；`canonicalReadCandidate` 可以构建 canonical，但不得 serve canonical。
- guarded read gate 必须检查 v8.37 snapshot、v8.38 plan authority、v8.39 existence truth、v8.40 non-audio apply evidence、v8.41 audio/upload-status evidence、divergence count 0、legacy fallback、其它 domain 不冲突、release/default disabled 和 manual owner approval。
- 任一 divergence、unsupported object、path/content leak risk、missing evidence 或 fallback unavailable 都必须 blocked/fallback，除非 explicit test-only divergent guarded read mode。
- read evaluation 不得触发 sync、apply、upload、download、retry draining、transcription、note generation 或 chat/provider request。
- read evaluation 不得 mutate store、write production data、move resources、write standalone note content、write audio bytes、write upload ledger completed、write retry job、write `receive.json` 或 mutate audio inbox。
- 不得删除 legacy read path、legacy Store/UI model、legacy planner/apply/upload fallback 或 route/security boundary。
- iPhone adapter 只能从 existing manifest/inventory/read inputs 构建 snapshot；不得创建 upload job，不得调用 `RecordingUploadCoordinator`、`RecordingUploadClient` 或 `SecureMacUploadClient`。
- Mac adapter 不得改变 `/sync/inventory` response schema，不得改 `receive.json`、audio inbox、pending sync、`SecureLocalHTTPSServer` route 或 `RequestVerifier` 行为。
- read projection 不得输出 absolute path、full hash、secret、full fingerprint、request/response body、full transcript/note/summary/provider response、audio bytes 或完整 generated content。
- diagnostics 必须 redacted，只能输出 mode/domain/objectID/count/hash prefix/safe summary；不得写本机隐私路径、完整 API 响应、证书私钥或用户内容。
- 没有 explicit debug/internal owner approval 和 clean equivalence evidence 时，不得声称 Store/UI 已可默认读取 canonical。

## Canonical v8.41 audio upload runtime commit v1 禁区

- v8.41 canonical audio upload runtime 必须默认 disabled；release/default 不得启用 canonical upload commit。
- `canonicalUploadWithLegacyFallback` 只能用于 explicit debug/internal owner-approved 配置，并且必须保留 legacy `RecordingUploadCoordinator` fallback。
- `diagnosticsOnly` 和 `noCommit` 不得创建 upload job、不得发网络、不得写 ledger completed、不得 suppress legacy。
- `testTransportUpload` 只能使用 fake/test transport；不得伪装成真实 secure upload evidence。
- 不得新增 upload route，不得修改 existing upload route contract；只能使用既有 resumable start/status/chunk/finalize 路径。
- 不得绕过 `RecordingUploadClient` / `SecureMacUploadClient`、TLS certificate pinning、HMAC、nonce、body hash、`RequestVerifier`、Keychain 或安全范围书签。
- 不得新增 abort route；abort 只能是 finalize 前的本地 session/job cleanup，不得物理删除 audio。
- 大音频必须按 chunk streaming；不得一次性把完整 audio 读入内存。
- confirmedBytes 必须单调；chunk offset 必须确定性；duplicate chunk 只能在 offset/length/hash 相同时 idempotent；wrong offset 必须失败或进入 retry。
- finalize 必须校验 byteSize 和 hash。hash/size mismatch 必须 conflict/failure，且不得 mark audio uploaded 或 upload ledger completed。
- Mac final audio 只能在 verified finalize 后出现；existing different audio 必须 conflict/no-overwrite。
- 不得自动下载 audio，不得写 transcript/note/summary/provider output，不得移动或物理删除 audio/transcript/note/summary/resource 文件，不得实现 permanent delete 或 tombstone GC。
- metadataOnly、studyItemOnly、receiveRecordOnly、metadata uploaded、UI uploaded 或 completed ledger alone 都不得作为 audio uploaded/no-op proof。
- audio no-op 只能由 peer audio same hash + same byteSize 证明；peerUnknown 必须 deferred；different hash/size 必须 conflict。
- view refresh 不得创建 fresh upload job；retry drainer 只能 replay existing eligible retry，不得创建 unrelated fresh job。
- retry/job persistence 不得保存绝对路径或完整 hash；diagnostics 不得输出完整 hash、绝对路径、secret、完整 fingerprint、request/response body、完整转写文本或用户内容。
- 没有 paired-device long-recording upload evidence 时，不得声称 v8.41 真实长录音上传已验证。

## Canonical v8.40 apply runtime owner v1 禁区

- v8.40 只能让 `CanonicalApplyPlan` 在 explicit config 下执行 non-audio domains；默认/release 必须继续 legacy apply owner。
- 不得删除 legacy apply、legacy planner、legacy fallback、legacy upload path、legacy read path 或 UI owner；`runtimeSwitch` 必须保持 false。
- `CanonicalApplyRuntimeConfiguration.disabled` 必须是默认。`productionRootApplyWithLegacyFallback` 只能在 debug/internal、owner-approved、非 release/default、legacy fallback available 且 gate 全部通过时使用。
- `diagnosticsOnly` 和 `noCommit` 不得提交、不写真实 store、不 suppress legacy duplicate。
- Gate 必须检查 v8.38 plan authority 或 noCommit、v8.37 inventory snapshot、valid apply plan、explicit enabled domains、executor、root-bound apply port、rollback、postcondition、legacy fallback、redacted diagnostics、legacy read path 和 `runtimeSwitch=false`。
- missing executor、dry-run-only executor、unsupported domain、domain not enabled、unresolved conflict without conflict-record action、resource move、standalone note content write、permanent delete/tombstone GC 都必须 blocked/fallback。
- `audioUpload` 在 v8.40 必须 blocked；不得迁移 audio upload runtime、resumable chunk upload、audio receive finalize、audio download 或 audio bytes 写入。
- 不得新增 route、修改 upload route、绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain、manifest/body hash 校验或安全范围书签；不得把 manifestHash 当鉴权。
- 不得把 metadataOnly、receiveRecordOnly、completed ledger、manifest apply 或 bridge success 当 audio uploaded/no-op。
- 执行必须串行；首个失败停止后续 action；rollback failure 是 fatal blocker；safe continue 必须等后续版本另有测试证明。
- duplicate legacy suppression 只能在 canonical action 成功且 exact match 后发生；diagnosticsOnly/noCommit/blocked/failure/fallback 均不得 suppress。
- Mac v8.40 existence path 只能通过既有 v8.39 canonical metadata-only ledger；不得借由 `receive.json` 切 read path，不得写 audio inbox，不得触发 transcription/note generation。
- diagnostics 必须 redacted；不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、证书私钥、request/response body、完整 transcript/note/summary/provider response、standalone note content 或本机隐私路径。
- 没有 paired-device real-device apply diagnostics 时，不得声称 v8.40 真实端到端 apply 已验证。

## Canonical v8.39 existence/apply bridge runtime v1 禁区

- v8.39 只能建立 recording existence truth 与 `manifest.recordings` metadata-only apply bridge；不得迁移大文件 upload runtime，不得切 UI/read path，不得删除 legacy。
- `CanonicalExistenceApplyRuntimeConfiguration.disabled` 必须是默认；release/default 不得启用 existence apply bridge。
- `productionRootApply` 只能在 explicit debug/internal、owner-approved、root-bound、atomic、rollback checkpoint、postcondition 全部满足时使用，且仍不得写 audio 或 mark audio available。
- 不得新增 route、修改 upload route、绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain、证书校验或安全范围书签。
- 不得自动下载 audio，不得写 audio bytes，不得创建 fake audio file，不得覆盖 Mac existing different audio，不得把 metadata uploaded/metadataOnly/study item/receive record/completed ledger 当 audio uploaded。
- audio no-op 只能由 same hash + same byteSize 证明；hashUnavailable、peerUnknown、completed ledger alone、metadata-only placeholder 都不得作为 no-op proof。
- peerUnknown 必须 deferred；absent peer 必须先要求 metadata apply bridge，不得直接当 audio no-op 或直接 suppress upload。
- different hash 或 different size 必须 conflict/blocker；tombstoned parent 必须阻断 metadata apply 与 upload candidate。
- Mac metadata-only existence 写入必须 root-bound、atomic、带 rollback checkpoint；rollback 只能恢复 previous record 或移除本轮新增 placeholder，不能删除其它文件。
- 若使用 canonical ledger，必须放在安全 app root 下，并只能作为 sync inventory existence fact；不得写 legacy `receive.json` 来切入 Mac read path。
- Mac inventory 可以报告 metadata-only recording exists，但必须 `audioAvailable=false`，无 proven audio 时不得报告 contentHash、byteSize 或 audio path。
- 不得物理删除文件，不得执行 tombstone/delete/trash/permanent delete/GC，不得移动 audio/transcript/note/summary/resource，不得写 standalone note content。
- iPhone 上传候选只能通过 existing `RecordingAudioUploadDecisionEvaluator` / `RecordingUploadCoordinator` path；view refresh 不得创建 job，retry drainer 不得创建 fresh unrelated job。
- diagnostics 必须 redacted，只能写 objectID/action/state/reason/hash prefix/byte count；不得写完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint、证书私钥、request/response body、完整转写文本或用户内容。

## Canonical v8.38 sync decision runtime v1 禁区

- v8.38 只能把 canonical planner 作为 guarded decision-runtime candidate。默认/release 必须继续 legacy owner；不得默认启用 canonical primary。
- `CanonicalSyncRuntimeConfiguration.disabled` 必须是默认；`runtimeSwitchEnabled` 必须保持 false；read path 必须保持 legacy。
- `canonicalPlanPrimaryWithLegacyFallback` 只能在 explicit debug/internal、owner-approved、非 release/default、legacy fallback available、diagnostics redacted 且 authority gate 全部通过时使用。
- release/default primary、missing v8.37 snapshot、invalid local/peer manifest、metadataHash schema mismatch、canonical modifiedAt unavailable、unsupported object、library fallbackRequired object、unresolved conflict、peer unknown audio、diagnostics not redacted、其它 active migration domain 都必须 blocked/fallback。
- peer unknown 不得当 missing；metadata uploaded、manifest applied、completed ledger、receive record existing 或 UI uploaded 不得当 audio uploaded/no-op。
- canonical metadataHash 必须只覆盖 stable business metadata；不得把 receivedAt、observedAt、upload progress、processing status、local path、audio hash/size、generated content、provider response 或 diagnostics 纳入 recording metadata hash。
- canonical modifiedAt/LWW 必须使用业务修改时间。旧 iPhone model 缺 business modifiedAt 时必须记录 warning/blocker，除 explicit internal documented fallback 外不得 primary。
- primary scope 只限 metadata/library/recording existence decision；不得接管大文件 audio upload runtime，不得创建新的 upload job，不得让 audio 自动下载。
- 不得执行 production apply，不得调用新的 apply bridge，不得写 production root，不得写 standalone note content，不得移动资源，不得物理删除文件，不得执行 tombstone/delete/trash/permanent delete/tombstone GC。
- 不得新增 route、修改 upload route、绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain 或安全范围书签。
- 不得改变 `/sync/inventory` response schema、Mac `receive.json`、audio inbox、pending sync、transcription/note generation、retry drainer、UI 或默认 read path。
- duplicate suppression 只能在 canonical plan 实际成为 primary owner 时，对 exact same object/action/scope 的 legacy duplicate 生效；diagnosticsOnly、NoCommit、blocked、planning failure 或 fallback 时不得 suppress legacy。
- diagnostics 必须 redacted，只能写 syncRunID、mode、count、object/action/scope/hash prefix 和 blocker summary；不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、证书私钥、request/response body、完整转写文本或用户内容。
- v8.38 不得删除 legacy planner/fallback；v8.39 apply/existence bridge 前不得把 runtime diagnostics 解释成 production apply 许可。

## Canonical v8.47 P0-2 persistent checksum cache 禁区

- v8.47 只能改 inventory/canonical snapshot checksum cache、telemetry 和 diagnostics；不得改变 sync decision、apply、upload、read path、主开关语义、legacy fallback 或任何 P1 domain。
- 不得修改 `/sync/inventory` route、wire schema、route allowlist、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier`，不得把 manifestHash 当鉴权。
- cache key 必须至少包含 safe logical/object-local token、byte size、mtime/contentVersion、hash algorithm、schema version、node role/platform role 和可选 namespace；logical token 变化必须 miss，size/mtime/contentVersion/algorithm/schema 变化必须 stale。
- cache record 可以内部保存完整 hash，但 diagnostics/docs/logs 只能输出 hash prefix；不得输出绝对路径、secret、完整 fingerprint、完整 metadata JSON、完整 transcript/note/summary/provider response 或用户内容。
- cache hit 必须真的跳过 hash provider；cache miss/stale 必须在 MainActor 外后台 hash；不得在 MainActor 做大文件 hash 或全量目录 scan，不得用 `semaphore.wait()` 伪异步等待 hash。
- cache read/write 必须 off-main；cache write 必须 atomic；cache file 不得放在用户可见学习库内容目录；prune 只能删除/重写 cache record，绝不能删除用户数据。
- cache corruption、schema mismatch 或单 record decode failure 必须 fail closed，重新 hash 或返回 `hashUnavailable`；`hashUnavailable` 不得作为 equality proof 或 no-op/diff/apply 依据。
- telemetry duration 必须来自真实 clock measurement 或测试 fake clock；count 必须来自真实路径/检测器。正常路径为 0 可以记录，但不得写硬编码 fake success 事件如 `MainActorHashBlocked count=0`。
- diagnostics 必须包含 syncRunID/nodeRole 且 bounded/redacted；mainActor hash/scan/metadata/jobs attempts 必须如实检测。当前 Mac inventory 仍 `@MainActor` 时，不得把 blocker 抹成 0。
- performance regression guard 只能输出 diagnostics/warning/blocker summary，不得改变业务 sync 语义。
- 真正完成必须有真机 before/after diagnostics 和 UI latency 体感记录；没有真机 evidence 不得声称 P0-2 fully validated。

## Canonical v8.37 inventory runtime v1 禁区

- v8.37 只能稳定 inventory/hash runtime。不得接管 diff、apply、read path、UI、upload job creation、retry drainer、Mac pending sync、upload routes 或任何 security route。
- 默认/release 必须继续 legacy owner；不得删除 legacy inventory builder、legacy fallback、legacy planner/store/route/read/write。
- 不得改变 `/sync/inventory` route、allowlist、request/response schema、TLS/HMAC/pinning/nonce/body hash、RequestVerifier 或 manifestHash 的安全边界。
- 不得在 MainActor 上做大文件 SHA256，不得使用 `semaphore.wait()` 伪异步等待 hash，不得让目录扫描或 hash 卡住 UI。
- checksum cache key 必须至少包含 logical token、byte size、mtime/content version、hash algorithm、schema version 和 node role/platform；size/mtime/algorithm/schema 变化必须 stale。
- cache hit 不得重新 hash；cache miss/stale 必须后台 hash；cache corruption 必须 fail closed 为重新 hash 或 hashUnavailable，不得崩溃。
- hashUnavailable 不得作为 equality proof，不得驱动 diff/apply/no-op 判定。
- 每个 iPhone syncRunID/tick 只能构建一次 local runtime snapshot；Mac 每个 inventory request 不得因为 shadow/report 再扫描 inbox/audio。
- diagnostics/report 必须 redacted；不得写绝对路径、完整 hash、完整 fingerprint、secret、完整 metadata JSON、note/transcript/summary 内容、request/response body 或 full audio path。
- 不得改变 Mac `receive.json`、audio inbox、pending sync、transcription/note generation；不得让 audio 自动下载、移动资源、物理删除文件、执行 tombstone/delete 或写 standalone note content。

## LibraryMetadata real-device debug switch 禁区

- Debug 设置开关只允许服务 `libraryMetadata` 真机预检；不得新增 migration domain、migration stage、public pilot/canary/evidence/landing 类型或新内核抽象。
- 默认、Release/default、普通 app 构造必须继续 `.disabled`，executor 必须 nil。不得默认启用 pilot，不得在 release/default 启用 pilot。
- `diagnosticsOnly` 是第一步，只能运行诊断和 LandingFreeze；不得提交、不得 suppress legacy、不得切 read path。
- `armTestRootN1` 与 `executeTestRootN1` 只能使用系统临时目录 test root；不得写 production root，不得传 `allowProductionRootWrites=true`。
- `executeProductionRootN1` 必须经 UI 二次确认，并且必须安全取得现有 app/store root；无法取得时必须 fail closed。只有该模式允许 `allowProductionRootWrites=true`。
- 不得改 StudyLibraryStore 或学习库 UI 默认读路径；不得删除 legacy read/write/store/planner/route/fallback；不得禁用 legacy fallback。
- 不得改 upload routes、retry drainer、Mac pending sync、RequestVerifier、TLS/HMAC/pinning/nonce/body hash、Keychain 或安全范围书签。
- 不得移动真实 audio/transcript/note/summary/resource 文件，不得写 standalone note content，不得执行 tombstone/delete/trash/permanent delete/tombstone GC。
- `generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 必须继续 staticOnly/defaultOff。
- Settings、diagnostics、logs 和 docs 不得输出完整 certificate fingerprint、secret、完整 hash、完整 metadata JSON、完整 transcript/note/summary/provider response、request/response body 或绝对本机路径。Mac fingerprint 日志只能输出短 prefix。
- 代码接线不等于真机验证；没有真机 `connection-diagnostics.jsonl` / `canonical-shadow.jsonl` 时不得声称 pilot 已验证。

## Canonical v8.32 libraryMetadata N=1 evidence audit / N=3 readiness gate 禁区

- v8.32 只能审计既有 v8.31 N=1 evidence、构造 redacted evidence bundle、验证 post-run invariant、导出安全摘要并计算 report-only N=3 readiness。不得执行新的 production-root write，不得执行 N=3/allEligible，不得启用 default/release。
- 缺少真实 v8.31 N=1 evidence 时必须报告 `missingEvidence` 并阻断 N=3；不得伪造成功，不得用测试 fixture 冒充真实 pilot evidence。
- Evidence bundle/export 只能包含 mode/rootMode/activePilot、candidate count/kind、commit/rollback/fallback/duplicate/read-side counts、LandingFreeze、productionRootSafetyProof、otherDomainsStaticOnly、runtimeSwitch、release/default disabled、redacted source ID 和 blocker。不得包含完整 metadata JSON、standalone note content、transcript/note/summary/provider response、绝对路径、完整 hash、secret、API key、完整 fingerprint、request/response body。
- Post-run invariant 必须阻断 executed candidate > 1、non-libraryMetadata active pilot、unsafe candidate kind、resource move、content write、generated artifact write、audio change、tombstone/delete、read path switch、UI mutation、rollback failure、read-side divergence、duplicate suppression without commit success、other domains 非 staticOnly、runtimeSwitch=true、release/default enabled。
- Mac evidence 若报告 RequestVerifier/route boundary violation 或 `receive.json` unexpected mutation，必须 blocked；不得通过 v8.32 修改 route、安全校验、upload route、inventory response、audio inbox 或 pending sync。
- `readyForN3AfterManualAudit` 只是报告状态。它不得执行 N=3，不得打开 runtime switch，不得删除 legacy planner/inventory/store/route/read/write/fallback，不得禁用 fallback，不得移动资源文件，不得写 standalone note content，不得执行 tombstone/delete。
- `generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 必须继续 staticOnly/defaultOff，不能成为 active pilot。

## Canonical v8.31 libraryMetadata production-root N=1 pilot 禁区

- v8.31 只允许 `libraryMetadata` 在 explicit debug/internal `executeN1Canary` + `productionRootExplicit` + `allowProductionRootWrites=true` 下执行一次 production-root N=1 pilot。默认、release、普通 app construction 不得启用。
- production-root gate 必须要求 ownerApproved、LandingFreeze green、v8.30 diagnosticsOnly evidence、armN1 evidence、testRoot execute success evidence、read-side divergence=0、rollback evidence、legacy fallback、productionRootBound apply-port evidence、checkpoint availability 和 postcondition verification capability。
- 候选必须恰好一个 safe metadata-only candidate。允许范围仅为 folder rename/color metadata、study item tags/filing/folder membership metadata、standalone note title/tags/filing metadata。
- N>1、allEligible、non-libraryMetadata domain、多个 active pilot、runtimeSwitch、release/default enablement、unsafe candidate、resource move、content write、standalone note content、tombstone/delete/trash/permanent delete/GC 都必须 blocked。
- 执行必须按 checkpoint -> atomic metadata write -> postcondition verification -> read-side parallel comparison。precondition/write/postcondition failure 必须 no write 或 rollback/fallback；rollback failure 是 fatal blocker。
- duplicate suppression 只能在 production-root N=1 成功且 pre/postcondition verified 后，对 exact matching legacy `libraryMetadata` duplicate 生效。失败、blocked、unsafe、no eligible、read-side divergent 或 rollback failure 不得 suppress。
- 不得切 read path，不得改 UI，不得删除 legacy planner/inventory/store/route/read/write/fallback，不得禁用 legacy fallback，不得实现 legacy retirement。
- 不得新增 route、改 upload route、绕过 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash、Keychain/安全范围书签，不得让 audio 自动下载或让 ObjectProjection 反向驱动 sync/upload。
- 不得移动真实 audio/transcript/note/summary/resource 文件，不得写 standalone note content，不得执行 physical/permanent delete 或 tombstone GC。
- `generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 必须继续 staticOnly/defaultOff，不得成为 active pilot。
- diagnostics 和 safety proof 必须 redacted；不得写 actual root path、完整 metadata JSON、完整 transcript/note/summary/provider response、完整 hash、secret、完整 fingerprint、证书私钥、request/response body 或个人隐私路径。

## Canonical v8.30 libraryMetadata diagnostics / arm / test-root drill 禁区

- v8.30 只允许 `libraryMetadata` 的 `diagnosticsOnly`、`armN1Canary` 和显式 testRoot `executeN1Canary`。不得新增或启用 `generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 的 active pilot、canary、read cutover 或 runtime switch。
- 默认、release、app 入口、UI 路径必须保持 disabled。不得默认注入真实 executor，不得默认构造 apply port，不得默认启用 canary，不得切 read path，不得改变 UI。
- `diagnosticsOnly` 只能运行 LandingFreeze 和安全摘要；不得选择 candidate、不得构造 write port、不得 commit、不得 suppress legacy、不得修改 read path。failure 只能作为 nonfatal diagnostic。
- `armN1Canary` 只能形成 N=1 readiness report：safe candidate availability、rollback readiness、read-side parallel evidence、legacy fallback availability。不得 commit、不得写 test root、不得写 production root、不得 suppress legacy。
- `executeN1Canary` 只能在 explicit internal/test config + testRoot/tempRoot apply port 下运行，candidate count 必须 <= 1。`productionRootExplicit` 和 `allowProductionRootWrites=true` 在 v8.30 必须 blocked。
- 允许 candidate 仅限 folder rename/color metadata、study item tags/filing/folder membership metadata、standalone note title/tags/filing metadata。不得移动资源、写 standalone note content、写 generated artifact、改 audio、处理 unresolved conflict/hierarchy cycle/parent missing/objectID instability 或 tombstone/delete/trash/permanent delete/GC。
- LandingFreeze 必须阻断多个 active pilot、非 `libraryMetadata` active pilot、其它 domain 非 static、runtimeSwitch、release/default enablement、read path 非 legacy、默认 production executor/root write、fallback missing、N>1、allEligible、unsafe candidate、resource move/content write/tombstone delete allowance。
- safe diagnostics 只能输出 mode、nodeRole、activePilot、freeze status、candidate kind、canary/rollback/fallback bool、suppression/read-side counts 等摘要。不得写完整 metadata JSON、完整 transcript/note/summary/provider response、standalone note content、绝对路径、完整 hash、secret、API key、完整 fingerprint 或 request/response body。
- v8.31 只能在 testRoot drill 通过且 owner 明确批准后，讨论 production-root N=1。不得自动继续扩大到 N>1、allEligible、其它域、read path cutover 或 legacy retirement。

## Canonical v8.29 libraryMetadata real-device pilot landing 禁区

- v8.29 只能服务 `libraryMetadata` real-device/debug internal N=1 pilot landing。不得把 `generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 或其它 domain 加入本轮 active pilot、canary、read-side cutover、domain cutover 或 runtime switch。
- `CanonicalMigrationLandingFreeze` 必须保持严格：唯一 active pilot 为 `libraryMetadata`；其它 domain staticOnly/defaultOff；release/default cutover=false；runtimeSwitch=false；legacy read path=true；非 library production injection 不得出现。
- `CanonicalLibraryMetadataDebugPilotConfiguration.disabled` 必须是默认。不得加 UI toggle，不得从 release/default app construction 自动启用，不得自动创建 real apply port/executor。
- 执行只允许 explicit internal/debug config、owner-approved token、rollback plan、read-side parallel equivalence、NoCommit/dry-run/execution-shadow/real-data-shadow evidence、root-bound non-dry-run apply port evidence、local/peer snapshot 和 injected executor 全部满足。
- candidate 每 run 最多一个，且必须 metadata-only：folder rename/color、study item tags/filing/folder membership、standalone note title/tags/filing。不得写 standalone note content、generated artifact、audio、upload job、full metadata blob 或用户内容。
- 必须阻断 resource move、folder hierarchy mutation、tombstone/delete/trash/permanent delete/tombstone GC、parent missing、cycle、objectID instability、unresolved conflict、active-vs-tombstone conflict、unsafe path、unsupported object/action 和 retry of failed unsafe candidate。
- commit 必须 root-bound、precondition verified、postcondition verified，并保留 rollback checkpoint。失败必须 rollback/fallback；rollback failure 是 fatal blocker。
- duplicate legacy suppression 只能在 canonical libraryMetadata commit success 且 pre/postcondition verified 后，对 exact matching libraryMetadata legacy duplicate 生效。diagnosticsOnly、armed、blocked、no eligible、unsafe、failure、rollback 或 Mac peer-snapshot-missing report-only 均不得 suppress。
- iPhone v8.29 seam 不得 double-execute 旧 v8.15/v8.16 libraryMetadata seam。Mac `/sync/inventory` 不得为了 landing 拉 peer snapshot、发网络、改 response、调用 executor 或绕过 route/security。
- 默认 read/UI 仍必须是 legacy。read-side parallel 只能作为 landing evidence/report；不得切 `StudyLibraryStore` read owner、UI source、legacy route/store/planner，或自动进入 read-side cutover/retirement。
- diagnostics 只能写 redacted enum/status/reason/count/object/action/hash prefix/rootMode/mode；不得写完整 metadata JSON、standalone note content、transcript/note/summary/provider response、request/response body、完整 hash、绝对路径、secret、完整 fingerprint、证书私钥或个人隐私路径。

## Canonical v8.28 tombstoneConflict canary N=1 禁区

- v8.28 只允许唯一 active pilot `tombstoneConflict` 的显式 internal/test N=1 canary；默认必须 disabled，默认 budget 必须为 0，release/default 配置不得启用。
- N=1 gate 必须要求 budget exactly 1、`explicitInternalTestConfiguration=true`、`allowsInternalN1Execution=true`、owner-approved token、rollback plan、NoCommit/dry-run/execution-shadow/real-data-shadow/read-side parallel/anti-resurrection evidence、legacy fallback、duplicate suppression policy 和 non-dry-run root-bound apply-port evidence。
- N>1、allEligible、runtime switch、non-tombstoneConflict domain、多个 active pilot、缺 local/peer snapshot、缺 executor 或缺 evidence 必须 blocked/fallback，不得 commit。
- 允许 candidate 仅限 soft object/library tombstone marker apply/send、conflict record commit、resurrection block record；generated artifact tombstone marker 只能 unsupported/report-only，不得执行 apply/download。
- 必须阻断 physical delete、permanent delete、tombstone GC、restore object、clear tombstone、ambiguous conflict auto-resolution、stale live metadata resurrection、generated artifact apply/download on tombstoned parent、audio-related action、full content mutation、unsafe path token、missing rollback checkpoint、unsupported object/action。
- 成功只可写 root-bound soft marker 或 conflict ledger record，并验证 postcondition；rollback 只能恢复本 candidate 的 marker/record 前状态，不得删除 audio/transcript/note/summary，不得 restore unrelated object 或 resolve unrelated conflict。
- duplicate legacy suppression 只能在 canonical tombstoneConflict commit success 且 pre/postcondition verified 后，对 matching tombstoneConflict legacy duplicate 生效；失败、rollback、fatal rollback、skipped、unsafe、report-only 或 unselected candidate 不得 suppress。
- iPhone 默认构造不得注入执行器；显式 test/future production 注入也必须走 gate。Mac `/sync/inventory` 不得新增 route、扩大 allowlist、绕过 RequestVerifier/TLS/HMAC/nonce/body hash，不得改 response、`receive.json`、audio inbox、pending sync、upload routes 或 transcription/note generation。
- v8.28 不得切 UI/read path，不得触发 sync/upload，不得改 retry drainer、Mac pending sync、upload ledger、audioUpload、generatedArtifacts、recordingMetadata、libraryMetadata 或 legacy retirement；其它 domain 必须保持 staticOnly/defaultOff，runtimeSwitch=false。
- diagnostics/docs 只能写 redacted enum/status/reason/count/object/action/hash prefix；不得写完整 metadata JSON、transcript、note、summary、provider response、request/response body、完整 hash、绝对路径、secret、完整 fingerprint、证书私钥或用户内容。

## Canonical v8.27 tombstoneConflict active pilot guarded seam N=0 禁区

- v8.27 只允许 `tombstoneConflict` 作为唯一 active pilot 做 guarded commit gate evaluation；canary budget 必须固定为 0，任何 candidate 都不得执行。
- `generatedArtifacts` 不得继续作为 active pilot，但其模板/观察 evidence 必须继续作为 `tombstoneConflict` active pilot 的前置证据。其它 domain 必须保持 static/default-off。
- iPhone/Mac v8.27 seam 默认必须 disabled。显式 `.guardedExecuteCommit` / `.canaryCommit` 也只能记录 redacted diagnostics、gate result、no-execution assertion 和 N1 readiness report；不得持有或调用 executor。
- v8.27 不得写 tombstone marker、不得 restore、不得 clear tombstone、不得 physical delete、不得 permanent delete、不得 tombstone GC、不得 auto resolve conflict、不得 suppress legacy duplicate、不得删除或禁用 legacy。
- 不得调用新 route、不得绕过 metadata/artifact 旧 route、不得创建 upload job、不得触发 network send、不得调用 `applySyncManifest`、不得写 production root/store/`receive.json`/audio inbox、不得修改 UI/read path、inventory response、retry drainer、Mac pending sync、upload ledger 或 runtime switch。
- gate 必须阻断 unsupported action/domain、missing tombstone timestamp、missing tombstone policy/rollback evidence、generated artifact tombstone marker apply、ambiguous conflict policy、unsupported restore、stale live resurrection risk、physical/permanent delete、tombstone GC、N1/staged/allEligible/runtime switch/default enablement、缺 owner token、缺 local/peer snapshot 和缺 rollback/root-bound/legacy fallback/evidence。
- diagnostics 只能写 redacted enum/status/reason/count/object kind/action kind/hash prefix；不得写完整 metadata/content、完整 hash、绝对路径、request/response body、secret、完整 fingerprint、证书私钥、完整 API response、完整转写文本或用户内容。

## Canonical v8.26 tombstoneConflict template / next-pilot candidate 禁区

- v8.26 只允许 `tombstoneConflict` 模板审计、metadata-only read projection、parallel diff、anti-resurrection gate、observation window 和 report-only retirement candidate gate；不得执行真实 canary、domain cutover、read-side cutover、legacy retirement、audio migration 或其它域迁移。
- `tombstoneConflict.nextPilotCandidate` 不是 active pilot。不得把它计入 active canary/cutover，不得打开 runtime switch，不得修改默认 read path、UI、legacy fallback、retry drainer、Mac pending sync、upload route、inventory response 或 `receive.json`。
- read projection 只能包含 object id/kind、tombstone state、deleted display state、timestamp summary、conflict kind/status、active-vs-tombstone state、anti-resurrection status、soft marker presence、hash prefix 和 redacted counts；不得包含完整 metadata、完整 generated content、完整 hash、绝对路径、physical delete target path、request/response body、secret、fingerprint、证书私钥或用户内容。
- iPhone/Mac tombstoneConflict read-side seam 默认必须 disabled。显式启用时也只能消费调用方已持有的 inventory/canonical/apply/library facts 并记录 redacted diagnostics；不得写 store、改 UI、改 inventory response、改 `receive.json`、写 audio inbox、创建 upload/apply job、触发 sync/upload、启动 transcription/note generation、修改 retry drainer 或 Mac pending sync。
- 不得执行 physical delete、permanent delete、tombstone GC、restore、tombstone clear、legacy deletion、legacy disable、auto conflict resolution 或 stale live metadata resurrection。任何这类信号必须成为 blocker/diagnostic，而不是 fallback success。
- anti-resurrection gate 必须要求 stale live metadata 不能恢复 tombstone、absence of tombstone 不能被解释为 restore、restore 需要 explicit signal、tombstoned parent 下 generated artifact/library metadata apply 被阻断、newer tombstone policy 显式、active-vs-tombstone conflict 保守处理。
- observation policy 默认 disabled/incomplete；retirement candidate gate 只能 report-only，必须保持 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。
- diagnostics 只能写 redacted enum/status/reason/count/object kind/hash prefix；不得写完整 metadata/content、完整路径、完整 hash、secret、完整 fingerprint、证书私钥、完整 API response、完整转写文本或个人隐私路径。

## Canonical v8.25 generatedArtifacts read-side guarded seam 禁区

- v8.25 只允许 `generatedArtifacts` 的 read-side metadata/availability projection、parallel diagnostics、default-off guarded canonical read candidate、observation window 和 report-only retirement candidate gate；不得默认切 read path，不得改 UI 默认行为，不得执行 legacy retirement。
- `CanonicalGeneratedArtifactReadSourceConfiguration` 默认必须保持 `legacy`。`parallelCompare` 和 `canonicalCandidate` 只能返回 legacy output；`guardedCanonicalRead` 必须要求 explicit internal/test configuration 和 read cutover gate 全部通过。
- read projection 只能包含 object/artifact id、kind、availability、byte size、hash prefix、producer/capability summary、logical token summary、local downloaded state、peer authoritative state、updatedAt summary 和 parent active/tombstoned summary；不得包含 full transcript/note/summary content、provider response、完整 hash、绝对路径、request/response body、audio bytes 或 generated artifact upload state。
- read cutover gate 必须要求 `generatedArtifacts` 为唯一 active pilot、其它 domain static/default-off、write-side staged canary evidence clean、rollback fatal count 为 0、read-side divergence count 为 0、unsupported/contentLeakRisk/unsafePathToken/parentTombstone/audioConfusion count 为 0、legacy fallback available、canonical projection complete、无 artifact route change、无 generated artifact upload job、explicit internal/test config、UI cutover 非 global、runtimeSwitch=false。
- gate blocked、canonical projection missing、unsupported artifact、divergence、contentLeakRisk、unsafePathToken、parent tombstone、audio confusion、fallback missing 或 canonical read exception 必须显式 fallback legacy，并记录 redacted reason；不得 silent fallback。
- iPhone/Mac generated artifact read seam 只能消费调用方已持有的 inventory/canonical snapshot facts；不得扫描真实资源目录、读取全文、下载 artifact、apply artifact、写 generated artifact 文件、写 store、写 `receive.json`、创建 upload/apply job、触发 sync/upload、启动 transcription/note generation、修改 UI、修改 inventory response、audio inbox、retry drainer 或 Mac pending sync。
- observation window 只能记录 redacted counts 和 blocker categories；retirement candidate gate 只能 report-only，必须保持 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。candidate ready 不得自动删除 legacy、禁用 fallback、打开 runtime switch 或停止 shadow comparison。
- v8.25 diagnostics 只能写 domain、stage/mode、syncRunID、nodeRole、artifact kind、object/artifact counts、divergence counts、byte size、hash prefix、logical token summary 和 reason；不得写完整 transcript/note/summary/provider response、完整 hash、绝对路径、secret、完整 fingerprint、request/response body 或用户内容。
- `audioUpload`、`tombstoneConflict`、`recordingMetadata`、`libraryMetadata` 不得成为 active pilot；不得新增 route、扩大 route allowlist、绕过 `/sync/artifact-request`、`RequestVerifier`、TLS/HMAC/pinning/nonce/body hash 或 Keychain；不得让 audio 自动下载。

## Canonical v8.24 generatedArtifacts staged canary expansion 禁区

- v8.24 只允许 `generatedArtifacts` 唯一 active pilot 的 staged canary expansion；默认必须 disabled，必须显式 `.canaryCommit`、`stagePolicy.allowCandidateExecution=true`、`explicitInternalTestConfiguration=true`、owner-approved token、clean previous-stage evidence、local/peer snapshot、executor 和 v8.24 matrix 才能执行。
- stage 顺序必须是 `N1 -> N3 -> N10 -> allEligible`。`N3` 不得缺 clean N1 evidence，`N10` 不得缺 clean N3 evidence，`allEligible` 不得缺 clean N10 evidence 或 `allowAllEligible=true`；不得跳 stage，不得把 N1 readiness 或 N1 success 自动解释成 allEligible/cutover。
- previous-stage failure、rollback failure、blocking divergence、unresolved conflict、postcondition failure、unsupported artifact、content leak risk、unsafe path token、parent tombstone、audio confusion、hash unavailable、byte size unavailable、read-side divergence、缺 rollback/no-commit/dry-run/shadow/root-bound/read-only transport/legacy fallback 任一项都必须阻断下一 stage。
- candidate 仍只能是 existing `/sync/artifact-request` bridge 的 `generatedArtifactDownloadApply`。不得新增 route，不得创建 generated artifact upload job，不得绕过 checksum/size/root-bound/rollback checkpoint 校验，不得混入 audio upload、metadata、receiveRecord 或 unsupported kind。
- 多 candidate 必须稳定排序、顺序执行；首个 commit/postcondition 失败必须 rollback、停止剩余 candidate、保留 legacy fallback。rollback failure 是 fatal blocker。
- duplicate suppression 只能应用于已成功 commit 且 pre/postcondition verified 的 candidate。失败 candidate、未执行 candidate、rollback、fatal rollback、no eligible、fallback 或 Mac report-only 都不得 suppress legacy。
- Mac `/sync/inventory` v8.24 seam 仍 report-only。不得为了执行 expanded canary 在 Mac inventory route 里拉 peer snapshot、发网络、改 response shape、触发 pending sync 或调用 executor。
- v8.24 不得切 UI/read path/runtime switch，不得改 retry drainer、Mac pending sync、upload ledger、inventory response、`receive.json`、audio inbox、legacy planner/store/route 或安全边界。下一步不得直接跳到 audio migration。

## Canonical v8.23 generatedArtifacts canary N=1 禁区

- v8.23 只允许 `generatedArtifacts` 唯一 active pilot 的 explicit internal N=1 canary；默认必须 disabled，budget 必须正好为 1，缺 `explicitInternalTestConfiguration`、`allowsInternalN1Execution`、owner-approved token、rollback/read-side/evidence、local/peer snapshot、executor 或 matrix 前置条件时必须 blocked。
- N>1、allEligible、staged rollout、runtime switch、release/default enablement 都必须 blocked；不得把 v8.22 N1 readiness、read-side equivalent、dry-run equivalent、shadow green 或 matrix active pilot 解读为自动执行许可。
- candidate 只能是 existing `/sync/artifact-request` bridge 的 `generatedArtifactDownloadApply`，最多执行一个；不得为 generated artifact 创建 upload job，不得新增 route，不得绕过 checksum/size/root-bound/rollback checkpoint 校验。
- candidate safety 必须阻断 audio 混入、unsupported kind/action、missing hash、missing byte size、unsafe logical path token、content leak risk、producer ambiguous、peer not authoritative、wrong route、parent tombstone、unresolved conflict、rollback checkpoint missing 和 failed action retry。
- 成功后只能 suppress exact matching legacy artifact action；commit failed、postcondition failed、rollback、fatal rollback、no eligible、fallback 或 Mac report-only 都不得 suppress legacy。
- Mac `/sync/inventory` v8.23 seam 仍 report-only。不得为了执行 N=1 在 Mac inventory route 里拉 peer snapshot、发网络、改 response shape、触发 pending sync 或调用 executor。
- v8.23 diagnostics/observation 只能写 redacted enum/count/status/reason/object id/artifact id/kind/hash prefix/byte size/route status/fallback/suppression bool；不得写完整 artifact content、完整 hash、绝对路径、transcript/note/summary/provider response、完整 request/response body、secret、fingerprint、证书私钥或用户内容。
- v8.23 不得切 UI/read path/runtime switch，不得改 retry drainer、Mac pending sync、upload ledger、inventory response、`receive.json`、audio inbox、legacy planner/store/route 或安全边界。

## Canonical v8.22 generatedArtifacts active pilot guarded commit N=0 禁区

- v8.22 只允许 `generatedArtifacts` 作为唯一 active pilot 进入 guarded commit gate evaluation；canary budget 必须固定为 0，任何 candidate 都不得执行。
- `libraryMetadata` 在 v8.22 不得继续作为 active pilot，但其 observation complete 或 retirement candidate ready 必须继续作为 `generatedArtifacts` active pilot 的前置证据。其它 domain 必须保持 static/default-off。
- iPhone/Mac v8.22 seam 默认必须 disabled。显式 `.guardedExecuteCommit` / `.canaryCommit` 也只能记录 redacted diagnostics、gate result、no-execution assertion 和 N1 readiness report；不得持有或调用 executor。
- v8.22 不得调用 `/sync/artifact-request`、不得下载 generated artifact、不得 apply、不得写 production root、不得写 store、不得 commit、不得创建 upload job、不得自动下载 audio、不得新增 route、不得切 runtime switch、不得修改 UI/read path、retry drainer、Mac pending sync、inventory response、`receive.json` 或 audio inbox。
- 旧 generated artifact request/apply path 和 legacy fallback 必须保留；v8.22 seam 不得触发 legacy duplicate suppression，不得绕过旧 checksum/size 校验，也不得删除或禁用 legacy planner/store/route/read path。
- gate 必须阻断 unsupported kind、content leak、unsafe path token、parent tombstone、audio confusion、missing local/peer manifest、missing peer snapshot、缺 owner token、缺 rollback/root-bound/legacy fallback/evidence、N1/staged/allEligible/runtime switch/default/release enablement。
- v8.22 diagnostics 只能写 redacted enum/count/status/reason/hash prefix/artifact kind/logical id；不得写完整 artifact content、完整 hash、完整路径、transcript/note/summary/provider response、request/response body、secret、fingerprint、证书私钥或用户内容。

## Canonical v8.21 generatedArtifacts next-pilot template 禁区

- v8.21 只允许 `generatedArtifacts` 模板审计、metadata-only read projection、default-off read-side seam、observation window 和 report-only retirement candidate gate；不得执行真实 canary、read-side cutover、domain cutover、legacy retirement、audio/tombstone/recordingMetadata migration。
- `CanonicalGeneratedArtifactReadProjection` 只能包含 object/artifact id、kind、availability、byte size、hash prefix、producer summary、safe logical token summary 和 availability flags；不得包含 transcript/note/summary 正文、provider response、audio bytes、完整 hash、完整路径、绝对路径、request/response body、secret、fingerprint 或用户内容。
- iPhone/Mac generated artifact read-side seam 默认必须 disabled。显式启用时也只能消费调用方已持有的 inventory/canonical manifest facts；不得读取真实资源目录、下载 artifact、apply artifact、写 store、写 `receive.json`、改 UI、创建 upload/apply job、启动 transcription/note generation、修改 inventory response、audio inbox、retry drainer 或 Mac pending sync。
- `summaryMarkdown` 等 canonical generated artifact 不支持的 legacy kind 必须阻断；audio 混入 generatedArtifacts projection 必须作为 `audioConfusionRisk`；metadataJSON/receiveJSON 属于已知非生成物，不得误当本域 candidate。
- observation policy 默认 disabled；observation gate 默认 incomplete/disabled。retirement candidate report 必须保持 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。
- `generatedArtifacts` 只能在 `libraryMetadata` observation complete 或 retirement candidate ready 后标为 `nextPilotCandidate`；该状态不得计入 active pilot、canary、cutover 或 runtime switch。`libraryMetadata` 仍是唯一 active pilot；`audioUpload`、`tombstoneConflict`、`legacyRetirement` 在本轮不得变 active。
- v8.21 diagnostics 只能写 redacted enum/count/status/reason/hash prefix；不得写完整 artifact content、完整 hash、完整路径、provider response、TLS/HMAC/nonce/body、secret、fingerprint、证书私钥或用户内容。

## Canonical v8.20 libraryMetadata observation / retirement candidate gate 禁区

- v8.20 只允许 `libraryMetadata` observation window、observation gate、rollback drill summary、E2E pilot report 和 report-only retirement candidate gate；不得执行 legacy retirement、不得删除或禁用 legacy、不得把 candidate ready 解释为 retired。
- observation policy 默认必须 disabled；只有 explicit internal/test configuration 才能记录 observation event 或 read-source hook 输出。
- observation gate 必须要求唯一 active pilot `libraryMetadata`、其它 domain static/default-off、write/read evidence、legacy fallback、zero divergence、zero rollback failure/fatal、zero unsupported/path leak、runtimeSwitch=false、default/release cutover=false、无 resource move、无 content write、无 tombstone/delete、无 sync/upload、无 UI mutation。
- `CanonicalMigrationDomainMatrix.v820LibraryMetadataObservationReport(...)` 只能表达 report 状态；`libraryMetadataPilotComplete` 必须保持 false，其它 domain 必须保持 static-only/default-off。
- `CanonicalLibraryMetadataRetirementCandidateReport` 必须保持 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`reportOnly=true`，并要求人工审计。不得自动打开 runtime switch、默认 canonical read/write、legacy suppression 或其它 domain migration。
- iPhone/Mac `observeReadSource(...)` hook 只能消费已生成的 read-source result；不得读取真实资源目录、扫描 store、写 store、触发 sync/upload、创建 upload/apply job、移动资源、写 standalone note content、修改 UI、修改 inventory response、`receive.json`、audio inbox、retry drainer 或 Mac pending sync。
- v8.20 diagnostics 只能写 redacted enum/count/status/reason/hash prefix；不得写完整 metadata JSON、完整 hash、完整 transcript/note/summary/provider response、request/response body、绝对路径、secret、fingerprint、证书私钥或用户内容。

## Canonical v8.19 libraryMetadata guarded read-side cutover seam 禁区

- v8.19 只允许 `libraryMetadata` guarded read-source seam；不得默认切 read path，不得全局 UI 切 canonical，不得启用 generatedArtifacts/tombstoneConflict/audioUpload/recordingMetadata read cutover，不得执行 legacy retirement。
- `CanonicalLibraryMetadataReadSourceConfiguration` 默认必须保持 `legacy`。`parallelCompare` 与 `canonicalCandidate` 只能返回 legacy output；`guardedCanonicalRead` 必须要求 explicit internal/test configuration。
- read cutover gate 必须同时要求：唯一 active pilot 为 `libraryMetadata`、其它 domain static/default-off、write-side canary success evidence、rollback fatal count 为 0、read-side divergence count 为 0、unsupported count 为 0、pathLeakRisk count 为 0、legacy fallback available、canonical projection complete、objectID stable、no resource move、no content write、no tombstone/delete candidate、no unresolved conflict、UI cutover not global、runtimeSwitch=false。
- gate blocked、canonical projection missing、unsupported object、divergence、path leak risk、canonical read exception 或 fallback missing 时必须显式 fallback legacy，并记录可诊断 reason；不得 silent fallback，也不得把 fallback 记作 production failure，除非后续配置明确要求 strict fatal。
- read source 只能服务 folder metadata、study item metadata 和 standalone note metadata；不得包含 audio state、generated artifact content、standalone note content、transcript/note/summary/provider response、真实资源路径、完整 hash、secret、完整 fingerprint 或本机隐私路径。
- iPhone/Mac read seam 只能消费调用方已持有的 legacy/canonical manifest facts；不得扫描真实资源目录、移动资源、写 store、写 `receive.json`、创建 upload/apply job、触发 sync/upload、启动 transcription/note generation、修改 audio inbox、retry drainer 或 Mac pending sync。
- 默认 UI 和 `StudyLibraryStore` legacy read implementation 必须保留。不得删除 legacy read path、legacy store、legacy route、legacy planner/inventory 或 upload coordinator/client。
- guarded read served canonical 也必须保留 legacy snapshot/equivalence summary；若后续 divergence 出现，必须阻断未来阶段并按策略 fallback。
- `CanonicalLibraryMetadataRetirementCandidateEvaluator` 在 v8.19 仍只能 report-only；candidate ready 不得自动删除、禁用 legacy 或打开 runtime switch。
- v8.19 diagnostics 只能写 domain、stage/mode、syncRunID、nodeRole、object counts、divergence counts、reason、hash prefix 或 redacted summary；不得写完整 metadata JSON、完整 note/transcript/summary/provider response、完整 hash、绝对路径、secret、fingerprint、request/response body 或用户内容。

## Canonical v8.18 libraryMetadata production canary N=1 禁区

- v8.18 只允许唯一 active pilot `libraryMetadata` 的 explicit internal/debug N=1 production canary wrapper；不得启用其它 domain、N>1、allEligible、domain cutover、read-side cutover、runtime switch、release/default cutover 或 legacy retirement。
- `CanonicalLibraryMetadataProductionCanaryConfiguration` 默认必须保持 `.disabled`；不得从 app 启动、UI、heartbeat、manual/periodic sync、retry drainer、Mac pending sync 或 receiver 默认路径自动启用。
- `.canaryN1Armed` 只能记录 armed/no-execution；不得 commit、不得调用 executor、不得 suppress legacy duplicate、不得写 production root。
- `.canaryN1Execute` 必须同时满足 explicit internal/debug configuration、owner-approved token、rollback plan、NoCommit/dry-run/execution-shadow/real-data-shadow/read-side parallel evidence、non-dry-run root-bound apply port、legacy fallback、local/peer snapshot、injected executor 和 v8.13 matrix sole active pilot；缺任一条件必须 blocked/fallback。
- production root 默认必须 disabled。只有 `.productionRootExplicit` 且 `allowProductionRootWrites=true` 才能进入后续 gate；否则必须记录 blocker 并保持 no execution。test-root 注入不得被解释为 production root approval。
- duplicate legacy suppression 只能在 canonical libraryMetadata commit success 且 pre/postcondition verified 后，对 matching folder/studyItem/standalone note metadata action 生效；失败、rollback、fatal blocker、unsafe/no eligible、gate blocked 或 read-side divergence 不得 suppress。
- observation report 只能写 redacted status/count/blocker/recommendation；必须保持 `uiMutated=false`、`resourceMoved=false`、`uploadJobCreated=false`。不得驱动 read path、UI、sync/upload、legacy/canonical plan、inventory response、state store、upload ledger、retry queue、Mac pending sync、route/security、真实 store 或 `receive.json`。
- v8.18 不得移动资源文件、写 standalone note content、自动下载 audio、新增 route、绕过 `/sync/apply-metadata`、绕过 `StudyLibraryStore.applySyncManifest`、改 `RequestVerifier`/TLS/HMAC/nonce/body hash/Keychain、做 physical/permanent delete、tombstone GC 或删除/禁用 legacy。

## Canonical v8.16 libraryMetadata expanded canary 禁区

- v8.16 只允许唯一 active pilot `libraryMetadata` 从 N1 扩到 `n3`、`n10`、`allEligible` staged canary；不得启用其它 domain、domain cutover、read-side cutover、runtime switch、release/default cutover 或 legacy retirement。
- 默认必须 disabled。只有显式 `.canaryCommit`、stagePolicy 请求 `n3`/`n10`/`allEligible`、`allowCandidateExecution=true`、owner-approved token、完整 evidence、previous-stage clean observation、rollback plan 和注入 executor 同时存在时，iPhone seam 才可尝试 expanded candidate。
- 不得跳 stage：N3 必须有 N1 clean evidence，N10 必须有 N3 clean evidence，allEligible 必须有 N10 clean evidence；previous-stage failure、rollback failure、blocking divergence、unresolved conflict、postcondition failure、resource move、hierarchy cycle、objectID instability、unsupported object、read-side divergence 或 observation window incomplete 都必须 blocked/fallback。
- candidate 仍只能是 folder/studyItem/standalone note metadata apply/send。resource token/path 变化、folder hierarchy mutation、standalone note content bytes、tombstone/delete/conflict、cycle、parent missing、objectID instability、unsupported action、view refresh 和 retry drainer 不得提交。
- 多 candidate 必须稳定排序并顺序执行；首个失败后必须 rollback 并停止后续 candidate。rollback 失败必须 fatal block；失败、未执行、跳过 candidate 必须保留 legacy fallback。
- duplicate legacy suppression 必须 per-candidate success-only。整轮因后续 candidate 失败而失败时，前面已经 commit 且 pre/postcondition verified 的 candidate 仍可 suppress；失败、未执行、跳过或不匹配 legacy action 不得 suppress。
- Mac `/sync/inventory` 缺 peer snapshot，真实 app seam 只能记录 v8.16 stage blocked/fallback/observation diagnostics，不能提交、不能 suppress legacy、不能改 response body/schema、route/security 或 pending sync。
- read-side parallel 仍只对 affected object 记录 diagnostics，不得切 UI/read path，不得创建 upload job、移动资源文件、写 standalone note content、处理 tombstone/delete/GC，或影响 audio/generated/recordingMetadata。
- v8.16 diagnostics 只能写 redacted syncRunID、domain、object id/kind、action、hash prefix、blocker、stage、计数和 recommendation；不得写完整 metadata JSON、完整 hash、payload、绝对路径、secret、fingerprint、证书私钥或用户内容。

## Canonical v8.15 libraryMetadata canary N=1 禁区

- v8.15 只允许 `libraryMetadata` N=1 canary；不得启用其它 domain、expanded canary、allEligible、domain cutover、read-side cutover、runtime switch 或 legacy retirement。
- 默认必须 disabled。只有显式 `.canaryCommit`、`canaryMaxObjectsPerSyncRun == 1`、`allowsInternalN1Execution == true`、`explicitInternalTestConfiguration == true`、owner-approved token、完整 evidence、rollback plan 和注入 executor 同时存在时，iPhone seam 才可尝试一个 candidate。
- N>1、allEligible、runtime switch、release/default enabled、非 `libraryMetadata` active pilot、多个 active pilot、缺 v8.13/v8.14 evidence、缺 owner approval、缺 rollback、缺 root-bound non-dry-run apply port、缺 read-side parallel evidence 都必须 blocked/fallback。
- candidate 只能是 folder/studyItem/standalone note metadata apply/send。resource token/path 变化、folder hierarchy mutation、standalone note content bytes、tombstone/delete、conflict、cycle、parent missing、objectID instability、unsupported action、view refresh 和 retry drainer 都不得提交。
- duplicate legacy suppression 只能在 canonical commit 成功且 pre/postcondition verified 后发生；失败、rollback、gate blocked、no eligible candidate、Mac peer snapshot unavailable 或 fallback 时不得 suppress legacy。
- Mac `/sync/inventory` 缺 peer snapshot，真实 app seam 只能记录 v8.15 peer-snapshot blocker/fallback diagnostics，不能提交、不能 suppress legacy、不能改 response body/schema。
- 不得新增或修改 `/sync/apply-metadata`、upload/artifact route、`RequestVerifier`、TLS/HMAC/nonce/body-hash/Keychain、Mac pending sync、retry drainer、upload queue、UI owner/read path、physical delete/permanent delete/tombstone GC 或文件资源移动。
- v8.15 diagnostics 只能写 redacted syncRunID、domain、object id/kind、action、hash prefix、blocker、observation/status；不得写完整 metadata JSON、完整 hash、完整 request/response body、绝对路径、secret、fingerprint、证书私钥或用户内容。

## Canonical v8.14 libraryMetadata guarded commit seam 禁区

- v8.14 只允许 `libraryMetadata` guarded commit seam 做 N=0 report-only 评估；不得把它解释为 N1 canary、production execute、domain cutover、read-side cutover 或 legacy retirement。
- `CanonicalLibraryMetadataGuardedCommitSeam` 不得持有或调用 commit executor；不得调用 `CanonicalLibraryMetadataCutoverRunner`、real apply port、production apply/transport port 或任何真实 store/network adapter。
- iPhone seam 不得改变 `LocalNetworkSyncDiffPlan`、canonical/legacy plan、action count、pending count、retry drainer、upload job、UI owner 或其它 domain 执行路径。
- Mac inventory seam 不得改变 `/sync/inventory` route、response body/schema、`RequestVerifier`、TLS/HMAC/nonce/body-hash、route allowlist、pending sync、receive JSON、audio inbox 或 resumable upload routes。
- N=0 下必须保持 `commitAttemptedCount=0`、`committedObjectCount=0`、`productionCommitCalled=false`、`realApplyPortCommitCalled=false`、`networkSendCalled=false`、`applySyncManifestCalled=false`、`metadataJSONWritten=false`、`duplicateLegacySuppressedActionIDs=[]`、`legacyFallbackPreserved=true`、`runtimeSwitchEnabled=false`。
- 不得发送 `/sync/apply-metadata`，不得调用 `StudyLibraryStore.applySyncManifest`，不得写 production root 或 metadata JSON，不能移动 audio/transcript/note/summary/resource 文件，不能创建 upload job，不能 suppress legacy duplicate。
- `CanonicalLibraryMetadataNoExecutionAssertion` 失败必须视为 v8.14 blocker，不能被 diagnostics 或 readiness 结果覆盖。
- `CanonicalLibraryMetadataN1ReadinessReport` 只能报告后续 N1 blocker/status；不得因为 readiness 为 candidate 或 ready-after-enablement 就自动启用 N1、改 canary budget、打开 runtime switch 或允许 duplicate suppression。
- 必须保留 v8.14 diagnostics：`canonicalLibraryMetadataV814SeamStarted`、`canonicalLibraryMetadataV814SeamCompleted`、`canonicalLibraryMetadataV814SeamBlocked`、`canonicalLibraryMetadataV814GateEvaluated`、`canonicalLibraryMetadataV814GateAllowedBudgetZero`、`canonicalLibraryMetadataV814GateBlocked`、`canonicalLibraryMetadataV814CanaryBudgetZero`、`canonicalLibraryMetadataV814CommitNotExecuted`、`canonicalLibraryMetadataV814LegacyFallbackPreserved`、`canonicalLibraryMetadataV814DuplicateSuppressionNotApplied`，以及 N=0 状态事件 `canonicalLibraryMetadataCanaryBudgetZero`、`canonicalLibraryMetadataGateAllowedButNoExecution`、`canonicalLibraryMetadataCommitSkippedBecauseCanaryBudgetZero`。
- v8.14 diagnostics/readiness/evidence 只能写 redacted domain/object/action/gate/readiness 摘要；不得写完整 metadata JSON、完整 hash、完整 request/response body、secret、fingerprint、证书私钥、用户内容或本机隐私路径。

## Canonical v8.13 migration matrix 禁区

- v8.13 已冻结横向扩域；不得继续把新 domain 推到真实 migration/canary/cutover。
- `libraryMetadata` 是唯一 active pilot domain；除 `libraryMetadata` 外，`recordingMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`uiProjection` 和 `legacyRetirement` 只能保持 static-review-only 或 blocked-for-real-migration。
- 不允许多个 active pilot；active pilot 必须显式配置；非 `libraryMetadata` active pilot 必须被 `CanonicalMigrationGlobalConfigValidator` 视为 violation。
- 不允许任何 release/default enabled cutover；不允许 `runtimeSwitchEnabled=true`；所有 app seam 默认必须继续 disabled，executor 默认 nil。
- pilot 完成前不得启用 `generatedArtifacts`、`tombstoneConflict` 或 `audioUpload` 的真实 canary/cutover；`audioUpload` 仍是最高风险、最后处理。
- 不允许跳 stage：canary 需要 previous stage evidence；read-side cutover 需要 write-side cutover success；retired 需要 read-side cutover、observation window 和 fallback readiness。
- pilot 路线固定为 N0 gate -> N1 canary -> expanded canary -> domain write cutover -> read-side parallel -> read-side cutover -> retirement candidate；每一步都必须另有审计和显式任务。
- 不得把 `CanonicalMigrationDomainMatrix`、`CanonicalLibraryMetadataPilotReport` 或其它 static audit report 当作 runtime switch、canary 执行、read-side cutover 或 legacy retirement 许可。
- v8.13 不切 UI、不切 read path、不 suppress legacy duplicate、不删除 legacy planner/inventory/store/route，不改 retry drainer/Mac pending sync/upload route，不让 audio 自动下载，不物理删除 audio/transcript/note/summary，不实现 permanent delete 或 tombstone GC。
- matrix/readiness/static audit diagnostics 只能写 enum、布尔值、计数、stage/domain 名称和 hash prefix；不得写 secrets、完整 fingerprint、完整 hash、完整 metadata JSON、完整 transcript/note/summary/provider response、完整 request/response body 或本机隐私路径。

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
  - Canonical v8.10 library metadata cutover 只允许 metadata-only apply/send；不得把 folder/studyItem/standalone note metadata 修改解释成真实 audio/transcript/note/summary/resource 文件移动。
  - Canonical v8.10 不允许 permanent delete、tombstone GC、UI owner cutover、recordingMetadata/generated artifact/audio side effect；失败、rollback、gate blocked 或 fallback 时不得 suppress legacy duplicate。
  - Canonical v8.15 N=1 canary 仍只允许一个 metadata-only folder/studyItem/standalone note candidate；resource token 变化、folder hierarchy mutation、standalone note content bytes 或任何 delete/tombstone/conflict 都必须 blocked。
  - Canonical v8.15 duplicate suppression 必须 success-only；Mac inventory 缺 peer snapshot 时只能 report/fallback。
  - Canonical v8.11 tombstone/conflict cutover 只允许 soft tombstone marker 与 conflict ledger record；不得把 tombstone marker 解释成 physical delete、permanent delete、tombstone GC、restore cutover 或 UI 删除切换。
  - Canonical v8.11 不得删除 audio、transcript、note、summary、receive JSON 或 generated artifact payload；active-vs-tombstone 必须保守记录 conflict，不能自动选择胜者或复活 tombstoned object。
- Sync manifest：
  - `StudyLibrarySyncManifest.checksum` 计算字段不能随意增删 payload；如改 schema 必须保持旧 manifest 解码兼容。
  - `pendingUploads` 不应携带 shared secret、绝对路径或完整文件内容。
- Local network inventory：
  - 双端 `LocalNetworkSyncInventory.canonicalManifest` 是 optional。旧 payload 缺字段必须继续解码；canonical 缺失或不兼容时必须回退 legacy planner。
  - `canonicalManifest` 不得携带绝对路径、secret、完整 fingerprint、API key、完整 transcript、完整 provider response 或本机隐私路径。
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
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataCutover.swift`
- `Rokurics/IPhoneLibraryMetadataCutoverExecutor.swift`
- `RokuricsMac/MacLibraryMetadataCutoverExecutor.swift`
- `RokuricsShared/SyncCore/CanonicalTombstoneConflictCutover.swift`
- `Rokurics/IPhoneTombstoneConflictCutoverExecutor.swift`
- `RokuricsMac/MacTombstoneConflictCutoverExecutor.swift`

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
- 不为 canonical v8.10 新增 metadata route；folder/studyItem/standalone note metadata 必须继续使用既有 metadata manifest bridge / `/sync/apply-metadata` 边界。
- 不为 canonical v8.11 新增 tombstone/conflict route；soft tombstone 与 conflict record 必须继续受既有 metadata/apply 边界、root-bound marker/ledger gate 和 redacted diagnostics 约束。
- 不把 `CanonicalTombstoneConflictCutoverRunner`、双端 tombstone/conflict real apply port 或 app seam configuration 接入默认 runtime，除非另有独立任务、审计、测试和人工批准。
- 不把 canonical v8.12 audio upload preparation 解释成 production upload runtime cutover；`CanonicalAudioUploadCutoverRunner`、双端 audio upload NoCommit executor、shadow receiver/rehearsal 或 app seam 默认都必须保持 disabled/shadow-only，不得替换 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient` 或 Mac resumable upload routes。
- 不让学习库移动/重命名真实移动 transcript/note/audio 资源，除非实现完整迁移和回滚。
- 不把 mock provider 当成真实生产 provider 结果写死。
- 不把 `TranscriptionQueue` 当成真实任务引擎；真实转写当前在 `TranscriptionCoordinator`。

## 同步/上传状态机禁区

- 不在 view lifecycle、folder/list/detail onAppear、study library refresh、Mac Audio Inbox refresh 中创建 recording audio upload job。
- 不把 metadata uploaded、manifest applied、receive record existing 或 UI “已上传”显示状态当成 audio uploaded。
- 不把 completed upload ledger 单独当成 no-op；只有 peer inventory 明确报告同 recording 的 `audioAvailable=true` 且 hash/size 与本地一致，才可视为 audio no-op。
- 不把 canonical v8.12 evidence report、NoCommit result、shadow rehearsal success、canary stage、completed ledger、metadata uploaded、receive record 或 UI uploaded 当成真实 audio upload 成功。
- 不把 peer audio unknown 当成普通 sync 下的可补传事实；普通 sync 应 deferred，只有显式用户手动上传或 retry drainer 可以带明确 reason 继续。
- 不覆盖 Mac 已有但 hash/size 不同的 recording audio；该场景必须保留 conflict/fatal 诊断和人工可见状态。
- 不让 UI display state 反向驱动上传、重试或 sync tick。展示状态只能来自业务状态，不能成为业务状态源。
- 不在主线程/主 actor 路径做全量大文件 SHA256、全量 inventory、全量 inbox 扫描或高频 JSON 诊断写入；如必须读取，应使用 checksum cache、增量状态或后台执行。
- 不让 retry pending 永久只显示等待；`nextRetryAfter` 到期后必须由 retry drainer/queue drain 去重后重新进入上传主路径。
- 不把 Mac 手动同步实现成直接假定 iPhone 已同步。Mac 只能发 pending signal；必须保留 pending created、heartbeat consumed、iPhone acked、tick started/completed/failed/timeout 的状态回执。

## Canonical migration 禁区

- Canonical Kernel Completion v1 可以接管 recording metadata diff、recording audio bootstrap candidate、Mac generated transcript/note/summary artifact transfer decision、folder/study item metadata/tombstone semantic planning、transfer state projection、object projection、inventory coverage 和 readiness diagnostics；不得顺手接管非 generated artifacts、UI state、retry drainer、Mac pending sync、`receive.json` 写入、`applySyncManifest` 内部写入、wire protocol 或物理存储迁移。
- Canonical Runtime Kernel Offline Completion v1 只能提供纯离线 in-memory file/transport/upload/apply/conflict/harness/readiness 验证；不得把 `CanonicalRuntimeHarness`、`InMemoryCanonicalTransportRuntime`、`CanonicalResumableUploadRuntime` 或 `CanonicalApplyExecutor` 接入生产 `LocalNetworkSyncEngine.performTick`、Mac HTTPS server route、真实 store、UI、retry drainer 或 Mac pending sync，除非后续任务明确要求迁移并补齐生产验证。
- Canonical Production Ports & Dry-Run Migration Readiness v1 只能声明生产 port contract、构造只读 production snapshot、运行 suppressed dry-run ports、输出 legacy equivalence report 和 migration gate；不得把 port declared、dry-run equivalent 或 manual migration design eligible 解读为生产 runtime switch。
- Canonical Production Runtime API & Port Contract v1 只能声明稳定 facade API、真实 production port 方法合同、execution guard、rollback contract 和 redacted side-effect/result model；不得把 `CanonicalKernelFacade` 或 `executeProduction` 解读为真实 production adapter 已完成。
- Canonical Production Adapter Skeletons & Migration Facade v1 只能提供双端 production file/transport/upload/apply adapter skeleton 和 migration facade；不得把 fake/temp-root/in-memory 测试路径解读为真实生产迁移、runtime switch 或 legacy replacement。
- iPhone/Mac production adapter skeleton 默认必须保持 disabled；file temp-root、transport fake responder、upload fake ledger、apply fake store 只能由测试 harness 显式构造，不能从 app UI、sync tick、heartbeat、retry drainer 或 Mac pending sync 自动启用。
- 不得用 production adapter skeleton 替换真实 `AudioFileStore`、`MacRecordingFileStore`、`SecureMacUploadClient`、`SecureLocalHTTPSServer`、`RequestVerifier`、`RecordingUploadCoordinator`、`RecordingUploadClient` 或 `StudyLibraryStore.applySyncManifest`，除非后续任务明确要求生产迁移并补齐审计、shadow、rollback 和真实设备验证。
- production transport adapter 只能映射既有 route，不得新增真实 network route、扩大 route allowlist、改变 upload route、绕过 signed request/HMAC/TLS pinning/nonce/body hash 或直接调用 Network.framework 发送真实请求。
- production file adapter 的 temp-root fake mode 不得写入真实 iPhone Documents、Mac Application Support、真实 study store、真实 audio inbox 或真实 generated artifact 目录；不得做物理删除、permanent delete 或 tombstone GC。
- production upload adapter 的 fake ledger 不得创建真实 upload job，不得调用 `RecordingUploadCoordinator`、`RecordingUploadClient` 或 `SecureMacUploadClient`，不得让 audio 自动下载。
- production apply adapter 的 fake store 不得调用真实 `applySyncManifest`，不得写 `receive.json`、study metadata、transcript/note/summary 文件或 generated artifact 目标路径。
- `CanonicalIPhoneMigrationFacade` / `CanonicalMacMigrationFacade` 默认必须保持 disabled 且 runtime switch false；`executeWithGuard` 不得在缺少 test harness config、testHarness token 和 fake/in-memory ports 时执行 side effect。
- `CanonicalShadowMigrationConfiguration` 默认必须保持 disabled。不得在 app 启动、UI、heartbeat、manual sync、periodic sync、retry drainer 或 Mac receiver 默认构造中静默开启 shadow migration。
- `IPhoneCanonicalShadowPortFactory` / `MacCanonicalShadowPortFactory` 只能消费调用方已经持有的 inventory/legacy facts；不得读取真实 store、扫描目录、计算额外大文件 SHA256、写文件、发送网络请求、创建 upload/apply job 或修改 UI。
- Canonical Execution Shadow Preparation v1 只能在显式 shadow mode 下运行 file/upload/apply/rollback/read-only transport projection 排练；不得把 execution shadow mode 设为默认，不得从 UI、heartbeat、manual/periodic sync、retry drainer 或 Mac receiver 默认路径静默启用。
- Execution shadow file rehearsal 只能写经过验证的 shadow root；shadow root 不得等于 production root，也不得位于 production root 内。`IPhoneCanonicalShadowFilePort` / `MacCanonicalShadowFilePort` 不得写真实 iPhone Documents、Mac Application Support、audio inbox、study store、generated artifact 目录或任何生产 `receive.json`。
- Execution shadow upload rehearsal 只能使用 shadow receiver/canonical upload runtime；不得创建真实 upload job，不得调用 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient` 或 Mac resumable upload session，不得改变 upload ledger、retry queue、inbox 或 `receive.json`。
- Execution shadow apply rehearsal 只能写 in-memory shadow apply store；不得调用真实 `StudyLibraryStore.applySyncManifest`，不得写 study metadata、folder/item store、generated artifact 文件、transcript/note/summary 目标路径或 `receive.json`。
- Execution shadow transport rehearsal 默认必须 suppressed；即使 read-only probe 显式开启，也只能构造/记录 redacted projection 或发送到明确允许的 read-only route。upload/apply/mutating route、route allowlist 扩大、真实 upload route 修改和绕过 signed request/HMAC/TLS pinning/nonce/body hash 均禁止。
- Execution shadow diagnostics 只能写 mode、role、domain、side-effect class、suppression status、count、reason、hash prefix 等摘要；不得写完整路径、完整 hash、secret、完整 fingerprint、API key、完整请求/响应 body、transcript/note/summary/provider response 或本机隐私路径。
- decision shadow/equivalence green 不等于 execution shadow 可通过；execution shadow equivalent 也不等于 runtime switch、legacy retired 或 production execute 可放行。
- iPhone `LocalNetworkSyncEngine.performTick` 的 shadow migration seam 只能在 legacy diff 后记录诊断；不得把 shadow dry-run result 替换 legacy plan、不得改变 pending upload/download/conflict 计数、不得调用 upload/download/apply。
- Mac `/sync/inventory` 的 shadow migration seam 只能在本地 inventory response 构建完成后记录诊断；不得改变 response body、不得因为缺 peer snapshot 拒绝请求、不得触发 artifact request/upload/apply。
- `CanonicalSingleDomainShadowConfiguration` 默认必须保持 disabled；不得在 app 启动、UI、heartbeat、manual/periodic sync、retry drainer、Mac receiver 或 Mac pending sync 默认路径静默启用 `recordingMetadata` 单域 shadow。
- `recordingMetadata` 单域 shadow 只能使用已经加载的 local/peer canonical manifest、canonical sync/apply plan 和 legacy diff facts；不得额外读取真实 metadata JSON、扫描目录、计算额外文件 hash 或读取/写入 production store。
- `CanonicalRecordingMetadataShadowStore` 只能写 in-memory shadow record/write summary。不得写 iPhone `Metadata/`、Mac inbox `metadata.json`、study store、upload ledger、retry queue、`receive.json`、artifact 文件或任何 production root。
- 单域 shadow apply/send/tombstone marker 不得调用 `/sync/apply-metadata`、`StudyLibraryStore.applySyncManifest`、`SecureMacUploadClient`、`RecordingUploadCoordinator`、`RecordingUploadClient`、Mac upload session 或任何真实 HTTPS mutating route。
- canonical 更激进 recording metadata apply/send 默认必须 blocking；same modifiedAt different hash、active-vs-tombstone conflict 和 unresolved conflict 不得 shadow apply/send。newer tombstone 只能写 shadow marker，不能物理删除 audio/transcript/note/summary 或 permanent delete。
- `canonicalRecordingMetadataShadow*` diagnostics 只能写 syncRunID、trigger、nodeRole、mode、domain、objectID、action/result/failure、count、reason 和 hash prefix；不得写完整 metadata JSON、完整 hash、路径、secret、完整 fingerprint、API key、完整 request/response body、完整 transcript/note/summary/provider response 或本机隐私路径。
- Shadow network probe policy 默认必须 disabled。即使显式启用，也只能接受 health/fingerprint/sync inventory read-only/artifact request read-only/device status read-only；upload metadata/audio/resumable chunk/finalize、apply metadata/manifest 和 mutating route 必须拒绝。
- Real-data shadow copy policy 默认必须 disabled。即使显式启用，也只能写入临时 shadow root；不得写 production root、production root 子路径、真实 iPhone Documents、真实 Mac Application Support store、`receive.json`、upload ledger、state store 或 study store。
- Real-data shadow copy audio 默认必须 descriptor-only。不得默认复制真实音频字节；只有后续任务明确批准 bounded audio-byte copy 时，才允许在 shadow root 内复制，并必须保留 size/hash 校验和 cleanup policy。
- Shadow root cleanup 只能删除/保留当前 shadow root 或 bounded retained sibling；必须拒绝 production root 和 production root 子路径。cleanup diagnostics 不得写绝对路径、完整 hash、secret、fingerprint 或内容。
- Read-only transport probe 默认必须 disabled 且默认 network suppressed。显式启用也只允许 health、fingerprint、sync status、sync inventory、device status；artifact request 需要显式 bounded allow。pair、upload、resumable upload、sync apply/apply-metadata/manifest 等 mutating route 必须拒绝。
- `manifestHash` 只能是 manifest integrity evidence，不能作为 auth、authorization、trust 或 route allow 的依据；不得替代 TLS pinning、HMAC、nonce、timestamp、body hash、signature、content-type、Keychain 或 `RequestVerifier`。
- iPhone/Mac role 不得进入 `productionExecute`。非 testHarness token 即使 ownerApproved/rollback/dry-run 等条件满足，也必须返回 `blockedProductionExecute`，且 side effects 为空。
- `CanonicalKernelFacade` 默认必须保持 `disabled`；未显式进入 `productionExecute` 模式时不得产生真实 file write、network send、upload、apply、ledger mutation、rollback mutation 或 diagnostics 之外的 side effect。
- 不得把 `CanonicalKernelFacade.executeProduction` 接入 `LocalNetworkSyncEngine.performTick`、heartbeat、periodic sync、manual sync、retry drainer、Mac pending sync、view lifecycle、UI button、真实 HTTPS route、真实 upload client、真实 store 或 `StudyLibraryStore.applySyncManifest`，除非后续任务明确要求生产迁移并补齐审计、人工批准、production adapter、shadow/rollback 和真实设备验证。
- production execution guard 不得被绕过或弱化。必须同时满足 explicit token、owner approval、operation/domain allowlist、rollback plan、dry-run equivalence、无 blocking divergence、无 unresolved conflict、required non-dry-run ports、migration gate 未阻塞，才能调用真实 production port 方法。

## Recording Metadata Cutover 禁区

- `CanonicalSingleDomainCutoverConfiguration` 默认必须保持 disabled；不得从 UI、app 启动、heartbeat、manual/periodic sync、retry drainer、Mac pending sync 或 Mac receiver 默认路径启用。
- single-domain cutover 只允许 `recordingMetadata`，且只允许 `recordingMetadataApply` / `recordingMetadataSend` candidate。non-recordingMetadata domain/action 必须 blocked，不得切 audio、generated artifact、folder/studyItem、standalone note、tombstone GC、retry drainer、Mac pending sync、full UI 或 physical storage。
- v8.3 Commit executor 仍不得接入默认 iPhone tick、Mac `/sync/inventory`、UI、heartbeat、manual/periodic sync、retry drainer 或 Mac pending sync。`IPhoneRecordingMetadataCutoverExecutor` / `MacRecordingMetadataCutoverExecutor` 默认必须继续使用 disabled/dry-run port set，并在没有内部 fake non-dry-run apply port 时阻断。
- v8.3 可执行路径只能由测试或内部显式配置注入 fake non-dry-run apply/transport port。不得把 fake port、in-memory port 或 failure injection 解释为真实 production adapter、runtime switch、legacy replacement 或真实设备 canary。
- v8.4 fake/in-memory Commit hardening 仍不得实现真实 root-bound apply port、写 production root、接默认 app path、默认启用 Commit、执行真实 `/sync/apply-metadata`、调用真实 `applySyncManifest`、创建 upload job 或 suppress app legacy duplicate。duplicate suppression 只能出现在 fake canonical success 的测试结果中。
- v8.4 failure injection / fake apply port 只能影响 `recordingMetadataApply` / `recordingMetadataSend` fake candidate。precondition/apply-before/transport-before failure 不得留下 fake mutation；postcondition/partial mutation 必须 rollback；missing rollback checkpoint 或 rollback failure 必须 fatal blocker；forbidden side effect 必须失败并尝试 rollback。
- v8.5 real root-bound apply port 必须继续 default-off。`IPhoneCanonicalProductionApplyPort()`、`MacCanonicalProductionApplyPort()` 和双端 `makeDisabledPortSet()` 必须保持 disabled/dry-run；不得从 app 默认 path、UI、heartbeat、manual/periodic sync、retry drainer、Mac pending sync 或 Mac receiver 默认构造中启用 testRootBound/productionRootBound。
- v8.5 `testRootBound` 只能写测试/内部显式传入的 temp/test root。测试不得写 iPhone Documents、Mac Application Support、真实 audio inbox、真实 study store、真实 `receive.json`、真实 upload ledger、真实 generated artifact 目录或 production root。
- v8.5 `productionRootURL` 构造默认必须是 `productionRootDisabled`。不得把提供 production root URL 解释为授权写入；除后续任务明确批准并补齐 canary/evidence/真实设备验证外，production root write 必须保持阻断。
- Root-bound metadata write 只能处理 `recordingMetadata` single-object metadata bytes；不得借此写 audio、generated artifact、folder/studyItem、standalone note、tombstone GC、conflict record、upload ledger、retry queue、Mac pending sync 或 UI state。
- Root-bound metadata target 必须绑定 root token、safe logical path token 和 root containment check；必须拒绝绝对路径、`file://`/scheme URL、`.`/`..` traversal、root token mismatch 和 root escape。`safeLogicalPathToken` 仍只是 token 语法检查，不是生产授权。
- Root-bound metadata write 必须保持 checkpoint -> atomic replace -> read-back postcondition verification -> rollback restore 合同。checkpoint failure 不得写文件；postcondition mismatch/partial write 必须 rollback；rollback failure 必须作为 blocker 记录，不能继续扩大 canary。
- Root-bound side-effect trace 只能输出 redacted object id、domain、byte count、hash prefix、checkpoint id、atomic/rollback 布尔和 failure 分类；不得输出完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、API key、完整 request/response body、transcript/note/summary/provider response 或本机隐私路径。
- v8.5 gate evidence 不得被弱化：real root-bound port、non-dry-run root-bound mode、root-bound write、atomic replace、rollback checkpoint、rollback verification、production root default-disabled 和 test root evidence 缺任一项时不得放行 recordingMetadata canary commit。
- v8.6 guarded commit app seam 必须继续 default-off。`N=0` 时 `guardedExecuteCommit` / `canaryCommit` 只能在显式 configuration 下记录 diagnostics/evidence report；不得从 UI、app 启动、heartbeat、manual/periodic sync、retry drainer、Mac pending sync 或 Mac receiver 默认构造中启用。
- v8.6 canary budget `N=0` 不得执行。不得把 gate allowed、evidence complete、root-bound readiness complete 或 owner-approved token 解读为可执行 commit；`canonicalRecordingMetadataGateAllowedButNoExecution` 和 `canonicalRecordingMetadataCommitSkippedBecauseCanaryBudgetZero` 必须仍表示 no execution。
- v8.6 runner 不得接收或调用 commit executor，不得调用 `CanonicalRecordingMetadataCutoverRunner.run`，不得调用 production apply/transport port，不得写 production root，不得发送 `/sync/apply-metadata`，不得调用 `StudyLibraryStore.applySyncManifest`，不得写 metadata JSON，不能创建 upload job。
- v8.6 app seam 不得 suppress duplicate legacy action，不得替换 legacy plan 或 canonical production plan，不得改变 pending upload/download/conflict counts，不得改变 Mac inventory response、retry drainer、Mac pending sync、UI、route/security、audio/generated/folder/studyItem/tombstone/conflict 域。
- v8.6 diagnostics/evidence report 只能输出 mode、trigger、nodeRole、domain、candidate count、gate blockers、canary budget、commit attempted count、duplicate suppression candidate count、hash prefix 和 redacted readiness summary；不得输出完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint、request/response body、transcript/note/summary/provider response 或本机隐私路径。
- v8.7 recordingMetadata canary 必须继续 default-off，且只能通过 iPhone `.canaryCommit` + `canaryMaxObjectsPerSyncRun == 1` + `allowsV87CanaryN1InternalExecution == true` + 注入 executor 进入执行分支。`N=1` 缺内部开关必须 blocked；`N>1` 必须 `canaryBudgetAboveOneDenied`，不得静默扩大。
- v8.7 canary selector 每个 sync run 最多选择 1 个 `recordingMetadataApply` 或 `recordingMetadataSend` candidate；必须按 objectID、apply-before-send、actionID 稳定排序，并拒绝 view refresh、retry drainer、非 recordingMetadata domain/action、evidence 不足、unresolved/tombstone conflict、缺 rollback checkpoint、非 root-bound apply port、send 缺 read-only probe 和已失败 action。
- v8.7 iPhone canary 成功后只能在最终 diff plan 中删除同 objectID、entityKind=`recording`、reason=`recordingMetadataApply` 或 `recordingMetadataSend` 的一个 metadata action。不得 suppress 非同 object/action、audio、generated artifact、folder、studyItem、tombstone、conflict、UI、retry 或 Mac pending sync action。
- v8.7 Mac 侧不得新增 production commit route、不得改 `/sync/apply-metadata`、不得改 `RequestVerifier`、TLS pinning、HMAC、nonce、timestamp、body hash、content-type 或 route allowlist；Mac inventory seam 即使看到 N=1 policy 也仍是 report-only。
- v8.9 generated artifact cutover 必须继续 default-off，且只允许五类 generated artifact：`transcriptJSON`、`transcriptMarkdown`、`noteMarkdown`、`noteJSON`、`summaryJSON`。不得把 audio、recording metadata、folder、studyItem、standalone note、tombstone/delete、conflict、retry drainer、Mac pending sync、UI 或 legacy retirement 纳入 v8.9 执行范围。
- v8.9 app seam 的 canary 默认必须是 `N=0`；`N=1` 必须有显式内部配置、注入 executor、root-bound/hash/size/rollback/fallback evidence。`N>1` 不得执行，缺 executor、缺 peer snapshot、peer unknown、非 Mac authoritative producer、ambiguous producer、parent tombstone、hash/size 缺失或 mismatch 必须 blocked/fallback。
- v8.9 NoCommit executor 只能写临时 staging summary 并 bounded cleanup；不得下载 artifact、写 production root、调用 `/sync/artifact-request`、调用 legacy apply/store、创建 upload job、修改 UI 或 suppress legacy duplicate。
- v8.9 real generated artifact apply port 默认必须 disabled。`testRootURL` 只能用于测试/内部临时 root；`productionRootURL` 默认必须 `productionRootDisabled`。不得写真实 iPhone Documents、Mac Application Support、真实 generated artifact 目录、study store、`receive.json`、upload ledger、retry queue、Mac pending sync 或 production root，除非后续任务明确批准并补齐真实设备审计。
- v8.9 commit 成功前必须完成 precondition、postcondition、payload bytes、hash/size、root containment、atomic write、checkpoint 和 rollback verification。postcondition/hash/size mismatch、partial write、rollback failure 或 forbidden side effect 不得 suppress legacy；rollback failure 必须成为 blocker。
- v8.9 duplicate legacy suppression 只能在 canonical generated artifact commit 成功后精确删除同 objectID/artifactID/kind/hash/size 的 legacy artifact action。不得 suppress audio upload/download、metadata manifest、folder/studyItem、tombstone/conflict、UI、retry 或 Mac pending sync action。
- v8.9 只能继续使用既有 `/sync/artifact-request` route summary/legacy bridge；不得新增 artifact route、扩大 `RequestVerifier` route allowlist、改变 TLS pinning/HMAC/nonce/timestamp/body hash/content-type/Keychain、创建 generated artifact upload job、自动下载 audio 或绕过 artifact checksum/size verification。
- v8.9 Mac `/sync/inventory` seam 没有 peer snapshot时必须 report/fallback 并返回原 inventory response；不得为通过 gate 在 inventory route 发网络、拉 peer manifest、触发 artifact request/upload/apply、修改 pending sync 或改变 response shape。
- v8.9 diagnostics 只能写 syncRunID、trigger、nodeRole、domain、kind、object/artifact id、byte size、hash prefix、route summary、gate/fallback/rollback 分类和 count；不得写完整 transcript/note/summary/provider response、完整 hash、绝对路径、secret、fingerprint、完整 request/response body 或本机隐私路径。
- v8.9 UI parallel/read-side projection 只能 diagnostics-only，必须保持 `mutatedUI=false`；不得让 generated artifact projection 驱动当前 UI、sync、upload queue、retry state 或 legacy retirement。
- v8.11 NoCommit 只能写临时 staging summary，必须保持 `applySyncManifestCalled=false`、network send suppressed、receive JSON mutation suppressed、generated artifact deletion suppressed、audio deletion suppressed 和 legacy duplicate preserved。
- v8.11 real apply port 默认必须 disabled；`productionRootURL` 默认 `productionRootDisabled`。只有显式 test-root harness 可以写 `tombstone-conflict/` marker/ledger JSON。
- v8.11 commit side-effect whitelist 仅允许 `.tombstoneMark` 与 `.conflictRecord`。任何 file payload delete、metadata apply、generated artifact apply、network request、upload side effect 都必须 blocked/rollback。
- v8.11 `resurrectionBlocked` 只能作为 anti-resurrection ledger 记录；不得触发 generated artifact download、restore、UI resurrection、retry 或 upload。
- v8.11 commit 成功且 postcondition 通过后才可 suppress 同 object/domain/action/conflict kind 的 duplicate legacy action；gate blocked、fallback、rollback 或 failure 不得 suppress。
- v8.11 diagnostics 只写 redacted domain、object/artifact id、tombstone state、conflict kind/policy、hash prefix 和 reason；不得写完整 hash、完整 content、绝对路径、secret、fingerprint、request/response body 或用户正文。
- recording metadata cutover 必须同时具备 explicit token、owner approval、rollback plan、real-data shadow copy evidence、execution shadow evidence、dry-run equivalence、无 blocking divergence、无 unresolved conflict、read-only transport probe、production port availability、legacy fallback availability、rollback rehearsal 和 production execution guard pass；缺任一条件不得执行 canonical production commit。
- canary mode 默认 `canaryMaxObjectsPerSyncRun = 0`，不得静默扩大；v8.7 只允许显式内部 N=1，任何 N>1 都不得执行。
- duplicate legacy action 只能在 canonical commit precondition/postcondition 均成功后 suppress。commit 失败、partial commit、rollback 或 fallback 路径不得 suppress legacy duplicate。
- rollback 失败必须成为 fatal blocker，不能继续扩大 canary、继续切换或标记 retirement ready。
- v8.3 executor precondition/postcondition 不得被弱化。action/domain、objectID、canonical/local/peer metadata hash、unresolved conflict、send route/transport、bridge hint、modifiedAt 方向和 tombstone state 必须继续检查；检查失败必须 fallback/rollback，不得继续 suppress legacy duplicate。
- v8.3 side-effect whitelist 只能允许 recording metadata apply、`.applyMetadata` network route projection 和 diagnostics write。upload、generated artifact、file write、physical tombstone、conflict write、audio/generator/folder/studyItem/UI side effect 必须 blocked。
- legacy fallback 必须保留；gate blocked 或 canonical precommit/canary failure 时不得删除、禁用或停止 legacy planner/store/route/upload/apply path。
- UI parallel projection 只能 diagnostics-only，必须保持 `mutatedUI=false`；不得让 canonical projection 直接驱动当前 UI、sync、upload queue 或 retry state。
- recording metadata retirement readiness 只能是 candidate/blocker report，不得自动删除 legacy planner、legacy inventory、legacy route、legacy store、upload coordinator/client、Mac pending sync 或 retry drainer。
- `.applyMetadata` 只能映射到既有 `/sync/apply-metadata` route path；不得新增真实 route、扩大 Mac route allowlist、修改 upload routes、绕过 `RequestVerifier`、TLS pinning、HMAC、nonce、body hash、signature 或 Keychain。
- 当前真实 `StudyLibraryStore` 缺少 single-object checkpoint/rollback API；不得把 v8.3 executor 直接接到真实 `StudyLibraryStore.applySyncManifest`、iPhone `AudioFileStore.updateMetadata` 或 Mac inbox/study store。真实 store commit 必须先补齐可审计 checkpoint/rollback 设计和测试。
- rollback plan 不得只是文档描述；`CanonicalRollbackPlan` 必须覆盖 required domains，并用 checkpoint/action/audit 表达可验证 rollback contract。没有 rollback plan 或覆盖不足时 production execution 必须拒绝。
- dry-run equivalence report 仍是生产前置 gate，不是可选诊断。token 缺失、token 不匹配、dry-run 未运行、dry-run divergent、canonical 更激进、缺 port/capability、unsupported object、conflict 或 migration gate blocked 时，production execution 必须返回 rejection 且 side effects 为空。
- real production port methods 必须继续是端口合同，不得在默认 protocol extension 或 dry-run port 中偷偷调用真实文件系统、Network.framework、upload coordinator、secure upload client、Mac HTTPS server、request verifier 或 store 写入。
- production side-effect trace 和 execution result 只能写 redacted target、operation/domain、hash prefix、byte count、result/failure 分类和 rollback/audit id；不得写完整 transcript/note/summary/provider response、完整 hash、绝对路径、secret、完整 fingerprint、API key、完整请求/响应 body 或本机隐私路径。
- `IPhoneCanonicalProductionSnapshotAdapter` / `MacCanonicalProductionSnapshotAdapter` 只能消费调用方显式传入的 legacy facts；不得读取真实 store、扫描目录、计算大文件 hash、写 `receive.json`、调用 `applySyncManifest`、创建 upload/apply job 或修改 UI。
- `IPhoneCanonicalDryRunPorts` / `MacCanonicalDryRunPorts` 必须保持 dry-run suppressed：不得写真实文件、发送真实网络请求、上传 audio、调用真实 apply、修改 retry queue、修改 Mac pending sync 或触发 UI 状态变更。
- `safeLogicalPathToken` 只是 logical path token 的语法安全合同，不等同于生产 root-bound 文件访问授权；真实生产 adapter 必须继续绑定 root token、store root 和安全范围文件访问。
- `manifestHash` 只能作为 manifest integrity/fingerprint，不能替代 TLS pinning、HMAC、nonce、body hash、content-type、RequestVerifier、Keychain 或授权判断。
- dry-run legacy equivalence report 只能作为 audit 证据；metadata churn suppression 可视为 canonical 更保守但非阻塞，canonical 更激进 upload/apply、conflict、缺 port/capability、unsupported object、UI/retry/Mac pending sync/user data migration 未设计必须阻塞。
- production migration gate 当前不得输出 runtime switch 或 legacy retired。真正迁移必须另有审计、人工批准、root-bound production adapter 实现、shadow migration、rollback 方案和真实设备验证。

## Canonical v8.0 No-Commit App Seam 禁区

- `CanonicalCutoverAppSeamConfiguration` 默认必须保持 disabled；不得从 app 启动、UI、heartbeat、manual/periodic sync、retry drainer、Mac pending sync 或 Mac receiver 默认路径启用。
- v8 app seam 当前只允许 `domain == .recordingMetadata` 且 `mode == .guardedExecuteNoCommit`。`guardedExecuteCommit`、`productionExecute`、`canaryCommit`、非 recordingMetadata domain/action、view refresh、retry drainer fresh metadata、缺 local/peer snapshot、证据不足、unsupported action、unstable hash 和 unresolved conflict 必须 blocked。
- no-commit executor 只能写临时 staging root 下的 redacted summary；不得写 iPhone `Metadata/`、Mac inbox、study store、upload ledger、sync state、retry queue、`receive.json`、artifact 文件或任何 production root。
- v8.2 NoCommit executor 默认必须在 stage 后立即 cleanup staging root；显式 retain diagnostics 必须 bounded by maxAge/maxCount/maxBytes，且不得把 retained staging root 当成生产数据源。
- NoCommit staging root lifecycle 必须拒绝 production root 或 production root 子路径。cleanup 失败只能记录 redacted blocker/evidence，不得为了清理而删除 production root、越权遍历 store、写 fallback production 文件或吞掉 blocker。
- NoCommit evidence report 只能作为 future gate evidence；不得因为 report complete 就自动启用 `guardedExecuteCommit`、`productionExecute`、canary、runtime switch、legacy retirement 或 duplicate suppression。
- `CanonicalMigrationStageConfiguration` 默认必须保持 `.off`。stage/config summary 只是只读描述；`recordingMetadataNoCommit` 只允许 diagnostics/staging root write side effect，不允许 production commit side effect。`recordingMetadataGuardedCommit` 只能描述 future requirements，不得执行。
- no-commit runner 不得调用 `CanonicalRecordingMetadataCutoverRunner.run` 的 production commit/canary path，不得调用 `/sync/apply-metadata`、`StudyLibraryStore.applySyncManifest`、`SecureMacUploadClient`、`RecordingUploadCoordinator`、`RecordingUploadClient`、Mac upload session 或任何真实 mutating route。
- v8 seam 不得 suppress legacy duplicate。`duplicateLegacySuppressedActionIDs` 必须保持空；legacy fallback 必须 preserved；production commit 必须只记录 suppressed/no-commit diagnostic，不能执行真实 commit。
- v8 diagnostics 只能写 syncRunID、trigger、nodeRole、domain、mode、objectID、count、result/reason、hash prefix、route path 和 bounded summary；不得写完整 metadata JSON、完整 hash、绝对路径、secret、完整 fingerprint、API key、完整 request/response body、完整 transcript/note/summary/provider response 或本机隐私路径。
- Mac `/sync/inventory` seam 没有 peer canonical snapshot，启用时应记录 `insufficientPeerSnapshot` 并继续返回原 inventory response；不得为通过 gate 而在 inventory route 里发网络、拉 peer manifest、改 response shape 或触发 Mac pending sync。
- Canonical file runtime 必须继续使用 root token + logical path token；不得接受绝对路径、`file://`/scheme URL、反斜杠 traversal、`.`/`..` traversal 或未绑定 root。tombstone 只能标记，不得物理删除 audio/transcript/note/summary 或 metadata 文件。
- Canonical transport runtime 不得替代 TLS pinning、HMAC、nonce、body hash、content-type、RequestVerifier 或现有 HTTPS route；离线 idempotency/route/capability 校验只能作为 kernel 语义测试。
- Canonical upload runtime 不得绕过 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient` 或 Mac resumable upload session；离线 finalize 写入只能发生在 in-memory file store。
- Canonical runtime readiness 只能输出诊断 gate；不得因为 offline runtime complete 就删除、禁用、跳过或清理 legacy planner、legacy inventory、legacy route、legacy store、retry drainer、Mac pending sync 或物理文件。
- Canonical Apply / Conflict / Tombstone / Library Planning v1 只能把 recording/folder/study item metadata apply/send、generated artifact download/apply、object/library tombstone apply/send、artifact tombstone unsupported policy 和 conflict record 表达成 shared apply/library model；不得删除或替换 legacy planner、legacy inventory、legacy routes、legacy apply/store。
- canonical apply bridge 必须继续通过既有 `/sync/apply-metadata`、`StudyLibraryStore.applySyncManifest`、`/sync/artifact-request` 和 artifact checksum/size 校验执行。folder/study item action 只能桥接为既有 metadata manifest apply/send/tombstone；不得新增 artifact route、不得绕过 signed request/HMAC/TLS pinning/nonce/body hash、不得绕过 `RecordingUploadCoordinator`。
- canonical tombstone 只能是 soft-delete / anti-resurrection / no-physical-delete / no-permanent-delete / no-GC policy。不得把 tombstone action 实现成 audio/transcript/note/summary 文件物理删除、permanent delete 或 tombstone GC。
- active-vs-tombstone 必须进入 conflict record，不能同时执行 metadata apply/send；tombstoned object 不得通过 generated artifact download 复活。
- canonical conflict record 和 apply diagnostics 只能写 object/artifact id、kind、reason、hash prefix、size 和 action/result/failure 分类。不得写完整 transcript、note、summary、provider response、完整 hash、绝对路径、secret、完整 fingerprint 或本机隐私路径。
- canonical production/dry-run diagnostics 只能写 event、domain、capability、count、bool、reason、hash prefix、logical token 和 suppressed action 摘要。不得写完整 transcript、note、summary、provider response、完整 hash、绝对路径、secret、完整 fingerprint、API key 或本机隐私路径。
- canonical library object diagnostics 只能写 object id、object kind、metadata hash prefix、modifiedAt/action/result/failure 分类。不得写完整资源内容、完整 transcript/note/summary、绝对路径、secret、完整 fingerprint、完整 hash 或 provider response。
- `CanonicalLibraryObject` / `CanonicalFolderObject` / `CanonicalStudyItemObject` / `CanonicalStandaloneNoteObject` 只能表示稳定 id、业务 metadata、层级/父子关系、logical resource token、soft-delete/tombstone 和 redacted hash；不得把真实资源路径、文件内容、provider response 或用户隐私路径放入 manifest。
- Legacy planner/inventory/两端 `StudyLibrarySyncModels.swift` 必须保留。canonical manifest 缺失、schema 不兼容、manifest hash 无效或 capability 不满足时，必须使用 legacy fallback 并记录 `canonicalPlanFallback`。
- `canonicalPlanFallback` 不得静默记录成泛化错误；至少要区分 local/peer manifest missing、schema unsupported、manifest validation failed、capability missing 和 planner failed，并附带 legacy fallback used、trigger、nodeRole、recording count、canonical object count。
- Shadow report 只能观察；不得驱动 UI state、retry drainer、Mac pending sync、`receive.json` 写入或 wire protocol。
- Shadow JSONL 不得写完整 hash、绝对路径、secret、完整 fingerprint、API key、完整 transcript、完整 provider response 或本机隐私路径；只能写 hash prefix、计数、availability、byte size、逻辑文件名末段和 mismatch category。
- `CanonicalRecordingMetadata.metadataHash` 只能覆盖 canonical business metadata equality：`objectID`、title、filing、规范化 tags、delete/tombstone 状态和 delete 时间。不得把 `createdAt`、`modifiedAt`、duration、upload/receive/processing state、ledger、local path、diagnostics、`receivedAt`、`observedAt`、audio hash/size、transcript/note 内容或 provider response 加回 metadata hash。
- `createdAt` 是对象事实而不是 metadata equality/LWW 输入；秒级与亚秒级精度差异不得制造 metadata hash mismatch。
- Mac canonical `modifiedAt` 只能来自已证明的业务 metadata 时钟。不得把 `RecordingReceiveRecord.updatedAt`、inbox fallback 即时 `updatedAt`、receive/transcription/note 状态更新时间、`receivedAt` 或 `observedAt` 当作业务 LWW 时钟。
- shadow/planner diagnostics 必须持续覆盖 `canonicalMetadataHashConverged`、`canonicalCreatedAtIgnoredForMetadataHash`、`canonicalModifiedAtIgnoredProcessingState`、`canonicalMacUpdatedAtRejectedAsProcessingClock`、`canonicalBusinessModifiedAtUsed`、audio bootstrap/no-op/deferred/conflict 等事件。
- generated artifact canonical projection 只能复用旧 inventory 已经加载/计算出的 artifact facts；不得新增 artifact route、不得绕过 `/sync/artifact-request`/apply、不得为 generated artifact 创建 upload job、不得把 iPhone 已下载 artifact 当成 authoritative producer。
- generated artifact diagnostics 只能记录 kind、availability、byte size、hash prefix、逻辑文件名末段和 decision category；不得写完整 transcript、note、summary、provider response、完整 hash 或绝对路径。
- `CanonicalTransferStateMachine` 只能做状态投影，不能修改 upload ledger、retry queue、transfer job、pending sync 或 display state。
- `CanonicalObjectProjection` 只能做 read-only display projection，不能写 UI model、sync state、upload state、artifact apply state 或 storage。
- `CanonicalInventoryBuilderContract` 只能使用调用方已提供的 facts；不得自己读取文件、遍历目录、计算大文件 SHA256、发网络请求或创建 upload/apply job。
- `CanonicalRetirementReadiness` 只能输出诊断 gate。不得因为 readiness 通过或失败就删除、禁用、跳过或清理 legacy planner、legacy inventory、legacy route、legacy store、retry drainer、Mac pending sync、物理文件或 tombstone。
- 不先修 UI、retry drainer 或 Mac pending sync 来掩盖 canonical 语义未统一的问题。
- 不继续在旧 `RecordingMetadata` vs `StudyItemMetadata` JSON diff 上补丁式扩大 recording metadata 逻辑；canonical v1 已用 `CanonicalManifest`、`CanonicalRecordingObject.metadataHash` 和 `CanonicalTimestamp.modifiedAt` 承接该语义。
- 不让 `CanonicalManifest` 携带绝对路径、secret、完整 fingerprint、API key、完整 transcript、完整 provider response 或本机隐私路径。
- 不把旧 `uploadStatus`、`receiveStatus`、completed ledger、manifest applied、UI uploaded 映射成 canonical audio available。audio available 只能由 audio artifact 的 availability + content hash + byte size 证明。
- 不把 peer unknown 当成 missing；不把 hash/size 不一致当成可覆盖场景。
- 不为 canonical audio bootstrap 新增上传 client、HTTPS route、绕过 `RecordingUploadCoordinator` 的路径或自动 audio download。canonical bootstrap 只能进入现有 upload coordinator/client 主路径。
- 不让 view refresh、列表/详情 onAppear、学习库 refresh 或 Mac inbox refresh 创建 canonical audio upload；retry drainer 只能处理已有到期 retry，不能因为 canonical peer unknown 创建新任务。
- 不让 v8.12 audio upload seam 写 Mac inbox、`receive.json`、upload ledger、retry queue、transfer job、Mac pending sync、UI state 或 duplicate legacy suppression；v8.12 canary N>0 必须 blocked，直到后续 v8.13 独立任务、审计和真实设备验证。
- 不让 `ObjectProjection` 反向写入 sync/upload 状态。它只能从 canonical facts 生成 UI display state。
- 不在 adapter 或 shadow report 构建中新增大文件扫描、计算全量 SHA256、创建 upload job、修改 `receive.json`、调用 `applySyncManifest` 或改变 `StudyLibraryStore` / `AudioInboxStore` 行为。只能复用旧 inventory 已经加载或已经计算出的事实。

## Canonical v8.1 Live Read-Only Probe 禁区

- `CanonicalLiveReadOnlyTransportProbePolicy` 默认必须保持 disabled；不得从 app 启动、UI、heartbeat、manual/periodic sync、retry drainer、Mac pending sync 或 receiver 默认路径启用。
- `sendReadOnlyProbe` 必须同时满足 explicit internal config enabled 和 route read-only classification；`classifyOnly` 不得构造 envelope，`buildSignedEnvelopeOnly` 不得发送网络。
- probe 不得新增真实 network route，不得扩大 mutating route allowlist，不得把 `/device/status`、`/sync/status`、upload、apply、pair、session、manifest 或 unknown route 当成 live read-only route。
- probe marker 不得绕过 `RequestVerifier`，不得改变 TLS pinning、HMAC、timestamp、nonce、body hash、content-type、Keychain pairing snapshot 或 nonce replay 语义。
- `manifestHash` 只能用于 integrity/diagnostics，不能替代 TLS pinning、HMAC、nonce、body hash、signature、RequestVerifier 或授权判断。
- Mac marked read-only probe 不得写 `receive.json`、创建 upload session、调用 `applySyncManifest`、修改 `StudyLibraryStore`、修改 pending sync、触发 transcription/note generation、创建 upload job、自动下载 audio 或改变 inventory response 业务字段。
- iPhone live probe failure 必须 nonfatal，只能写 redacted diagnostics/evidence；不得改变 tick return value、legacy plan、canonical current production plan、upload ledger、retry queue、pending count、UI 或 runtime switch。
- diagnostics 只能写 syncRunID、trigger、nodeRole、mode、route、result/reason、status/count 和 hash prefix；不得写 secret、完整 fingerprint、完整 hash、完整 request/response body、完整 metadata JSON、完整 transcript、完整 note、完整 summary、provider response、绝对路径或本机隐私路径。
- no-mutation audit 如果 snapshot 不可取得，必须记录 unavailable，不得伪造 `canonicalLiveReadOnlyProbeNoMutationVerified`。

## Canonical v8.17 LibraryMetadata Read-Side Pilot 禁区

- `CanonicalLibraryMetadataReadSideCutoverConfiguration` 默认必须保持 `.disabled`；不得从 app 启动、UI、heartbeat、manual/periodic sync、retry drainer、Mac pending sync 或 receiver 默认路径启用 canonical read。
- read-side projection 只能读取调用方已加载的 legacy/canonical library metadata facts；不得扫描真实资源目录、移动资源、读取 standalone note 全文、读取 transcript/note/summary/provider response、计算大文件 hash、写 store 或发网络。
- read snapshot 只能包含 folder/study item/standalone note metadata、folder membership、filing/tags/color/trash state、business modified time 和 redacted logical resource token summary；不得包含完整 note 内容、完整资源路径、绝对路径、完整 hash、secret、fingerprint、request/response body 或本机隐私路径。
- `parallelOnly` 只能输出 diff/equivalence/blocker diagnostics；不得替换 legacy read model、UI model、sync plan、upload plan、retry state、Mac pending sync state、inventory response 或 canonical production plan。
- `canonicalReadCandidate` / `guardedCanonicalRead` 必须要求 `libraryMetadata` 为唯一 active pilot、v8.16 write-side staged canary clean evidence、zero read divergence、legacy fallback available、无 unsupported object、无 path leak risk、无 blocking divergence；缺任一条件必须 blocked。
- 即使 candidate ready，v8.17 也必须保持 `readPathSwitched=false`、`uiMutated=false`、`syncOrUploadTriggered=false`，并记录 guarded read suppressed / legacy fallback available diagnostics；不得实际切换 UI/read path。
- retirement readiness 只能是 report-only；不得删除、禁用、跳过、清理或停止 legacy planner、legacy store、legacy route、legacy read fallback、retry drainer、Mac pending sync 或任何物理文件。
- write-side evidence linkage 只能引用 staged canary status、stage、rollback/fallback/suppression/resource-move/read-divergence 计数和 bool；不得把证据缺失解释为通过，也不得因为 evidence complete 自动执行 read cutover。
- v8.17 不得启用其它 domain。`recordingMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`uiProjection`、`legacyRetirement` 仍必须 static/default-off/blocked，直到 `libraryMetadata` pilot 的 read-side evidence 经独立阶段批准。
- v8.17 diagnostics 只能写 syncRunID、trigger、nodeRole、domain、mode、candidate state、failure/blocker kind、divergence kind、object id、计数、hash/resource token prefix 或 bounded summary；不得写完整 metadata JSON、完整 hash、完整路径、secret、完整 fingerprint、完整 request/response body、完整 transcript/note/summary/provider response 或用户正文。

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
