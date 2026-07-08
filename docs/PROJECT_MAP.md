# PROJECT_MAP

最近自查日期：2026-07-08

本文描述当前仓库结构。判断依据来自 Xcode project、scheme、Swift 源码、测试文件、脚本和现有 `docs/LongRecordingTestPlan.md`、`docs/SYNC_STATE_AUDIT.md`。

## 2026-07-08 新增/更新 v10.0 / Mac 首页与共享录音实时转写文件

- `RokuricsMac/MacHomeView.swift`：新增 Mac 首页，显示 Rokurics 标题、共享录音 orb，以及学习库、AI 对话、iPhone 连接三个入口。
- `RokuricsMac/MacRootView.swift`、`RokuricsMac/MacSidebarView.swift`：默认选择首页，并在侧边栏加入 `home` 项；不改变 Mac receiver、同步或连接拓扑。
- `RokuricsMac/MacRecordingManager.swift`：Mac 本地录音 owner。负责麦克风权限、`AVAudioRecorder` 录制、暂停/继续/停止、模拟实时转写、保存 inbox audio/metadata 和 transcript。
- `RokuricsMac/MacRecordingSessionView.swift`：Mac 录音 session wrapper，进入页面时启动录音，复用共享录音 surface，保存完成后返回首页。
- `RokuricsShared/SharedRecordingOrb.swift`：共享录音按钮、录音 phase 和时间格式；当前用于 Mac 首页录音入口。
- `RokuricsShared/SharedRecordingSessionSurface.swift`：双端共享录音界面，包含返回、计时、实时转写文本框、暂停/继续、停止和禁用上传按钮。
- `RokuricsShared/SharedLiveTranscriptionModels.swift`：模拟实时转写 snapshot、segment 和 session；provider id 为 `shared-live-simulated-asr`。
- `RokuricsShared/SharedRokuricsUI.swift`：补充共享录音 UI 所需颜色、glass surface/stroke/shadow helper。
- `Rokurics/RecordingManager.swift`、`Rokurics/RecordingSessionView.swift`：iPhone 录音页复用共享 session surface，并在录音期间显示同一个模拟实时转写 session；不持久化模拟 transcript，不改变上传/同步 schema。
- `RokuricsMac/MacRecordingFileStore.swift`：新增 `checksumForTemporaryAudioUpload(...)`，供 Mac 本地录音保存到既有 inbox audio path 前校验使用。
- `RokuricsMac/RokuricsMac.entitlements`、`Rokurics.xcodeproj/project.pbxproj`：开启 Mac audio input entitlement/resource access，并生成麦克风用途说明。

说明：v10.0 当前保留范围不包含 canonical runtime/fallback 行为改动、不包含设置页 Debug Sync Kernel 删除、不包含测试 source regression。那些文件已恢复到 v9.24。

## 2026-07-04 新增/更新 v9.24 / 双端英文显示文案文件

- `RokuricsShared/RokuricsCopy.swift`：新增双端共享展示文案 helper。中文首选语言返回中文，其他语言返回英文；同时提供展示 locale 和常用 count/open/choose/new 文案辅助。helper 为纯展示层，不改变 sync/upload/schema/route/security/raw value。
- `Rokurics/RokuricsTypography.swift`、`RokuricsMac/MacTypography.swift`、`RokuricsShared/SharedRokuricsUI.swift`：标题/返回按钮等共享视觉组件接入语言开关，非中文环境避免中英混排并控制长英文标题换行/缩放。
- `RokuricsShared/SharedStudyComponents.swift`、`RokuricsShared/SharedChatComponents.swift`、`Rokurics/RokuricsStudyDocumentViews.swift`、`RokuricsMac/MacDocumentDetailComponents.swift`：学习库、聊天、文档详情共享展示文案接入中英分支；旧 Markdown 中文解析键保持兼容。
- `Rokurics/` 下首页、录音、上传、学习库、聊天、设置、标题编辑、错误展示相关 Swift 文件：iPhone 可见文案改为系统语言分支，英文使用较短标签以减少移动端溢出。
- `RokuricsMac/` 下侧边栏、Dashboard、音频收件箱、学习库、连接、AI、设置、转写/whisper.cpp/笔记生成配置、receiver/status、标题编辑相关 Swift 文件：Mac 可见文案改为系统语言分支，设置页/表格/按钮使用 compact English。
- 本轮未新增 target、未改 Xcode target membership、未新增依赖、未改 route、未改上传/同步/安全协议。

## 2026-06-16 新增/更新 v9.12 / Post-v9.10 Audit Closure B 文件

- `RokuricsShared/SyncCore/CanonicalFourDomainCompletionGate.swift`：扩展 R6/R7 逐行 evidence 与 blocker，覆盖 connection runtime app reference、heartbeat/liveness/syncRequested/status exchange、transfer runtime app reference、retry runtime、production upload port not test-only、secure upload path、finalize proof -> StatusTruth、sync/file/cross-domain mode boundary；fake/test-only production upload port selected 时 unsafe。
- `RokuricsShared/SyncCore/CanonicalFourDomainRealDeviceTrialGate.swift`：final trial gate 增加 R6/R7 blocker：connection/transfer runtime 引用缺失、secure upload path 缺失、finalize proof 未进 StatusTruth、retry existing-only 缺失、test-only upload port selected、mode boundary/legacy retirement violation。
- `RokuricsShared/SyncCore/CanonicalFourDomainRuntimeHarness.swift`、`CanonicalFourDomainFakeConnectionCarrier.swift`、`CanonicalFourDomainFakeFileRuntime.swift`：deterministic harness 补 diagnostics storm async/backpressure、status exchange duplicate/stale/conflict deterministic reject、完整 mode sequence `oldKernel -> canonicalShadow -> canonicalDecisionOnly -> canonicalApplyNoAudio -> canonicalFullSync -> oldKernel`。
- `RokuricsShared/SyncCore/CanonicalFourDomainEvidencePackage.swift`：evidence package 记录完整 mode transitions 与 diagnostics storm queue/drop summary。
- `RokuricsShared/SyncCore/CanonicalTransferRuntime.swift`：chunk send 失败后先走 existing status route refresh；若 receiver confirmedBytes 前进则从新 offset resume，否则 fail closed。
- `Rokurics/IPhoneCanonicalProductionUploadPort.swift`、`RokuricsMac/MacCanonicalProductionUploadPort.swift`：旧 in-memory ledger 改为显式 `testOnly` 命名；`fakeLedger` production-looking token 移除。真实 fullSync transfer 不选择该 port。
- `Rokurics/CanonicalIPhoneMigrationFacade.swift`、`RokuricsMac/CanonicalMacMigrationFacade.swift`：test harness port set 继续可显式构造 test-only in-memory upload port，但不属于 production injection policy。
- `RokuricsTests/CanonicalFourDomainRuntimeHarnessTests.swift`、`RokuricsMacTests/CanonicalFourDomainRuntimeHarnessTests.swift`：新增 harness 场景验收、R6 missing not READY、test-only production upload port unsafe。
- `RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests.swift`、`RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests.swift`：新增 R6 runtime evidence 缺失与 test-only production upload port unsafe 的 final gate tests。
- `RokuricsTests/CanonicalTransferKernelRuntimeTests.swift`：新增 wrong-offset/chunk failure 后 status refresh/resume 的 runtime targeted test。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/Rokurics_Canonical_FourDomain_Kernel_Runbook_v9.md`：记录 v9.12 R6/R7 closure、no route/security change、no legacy retirement 和 realDeviceEvidencePresent=false。

## 2026-06-16 新增/更新 v9.11 / R4 UI EffectiveStatus + R3 No-Freeze 反证文件

- `Rokurics/StudyLibraryStore.swift`：新增 `effectiveSyncStatusByObjectID` snapshot 与 `effectiveSyncStatus(for:)` / `canonicalDisplaySyncState(for:)` 只读 getter；`produceCanonicalStatusFact` 更新缓存 snapshot，getter 不触发 actor 重算、merge、reconcile、diagnostics file write、sync/upload/retry drain、file IO 或 network IO。
- `Rokurics/RecordingUploadCoordinator.swift`：新增 effective/display snapshot 字典；`displaySyncState(for:)` 改读缓存 snapshot，fallback 走 canonical-equivalent conservative display；`refreshDisplaySnapshot(for:)` 是显式刷新入口，不在 View getter 内读 ledger；上传行为、route、retry owner 不变。
- `RokuricsMac/StudyLibraryStore.swift`：新增同类只读 effective/display snapshot API，Mac Store getter 只读缓存。
- `RokuricsMac/SecureReceiverService.swift`：新增只读 `effectiveSyncStatusByObjectID` / display snapshot API，并只暴露已有 status truth projection；不改 `SecureLocalHTTPSServer` route/server 行为。
- `RokuricsMac/MacRecordingInboxItem.swift`：`canonicalDisplaySyncState` 从 computed 改为 stored snapshot；`displayAudioAvailable` 作为 Mac study/audio inbox 操作可用性的 canonical source。
- `RokuricsMac/MacStudyLibraryView.swift`、`RokuricsMac/MacAudioInboxView.swift`：现有播放/转写 enabled 状态改读 `displayAudioAvailable`；未新增按钮、颜色、字体、间距、导航或提示卡片。
- `RokuricsShared/SyncCore/CanonicalMainActorHotPathGuard.swift`：新增 `statusTruthReconciliation` 与 `effectiveStatusProjection` hot-path attempt counters，七类 no-freeze guard 全覆盖。
- `RokuricsShared/SyncCore/CanonicalFourDomainCompletionGate.swift`、`CanonicalFourDomainEvidencePackage.swift`、`CanonicalFourDomainRealDeviceTrialGate.swift`、`CanonicalFourDomainFinalScorecard.swift`：v9.10 gate/scorecard/evidence package 增加 v9.11 code-level evidence 字段；缺 R4 或缺 R3 no-freeze evidence 不得 READY，View direct proof 或 MainActor reconciliation attempt 进入 unsafe/not-ready。
- `RokuricsTests/CanonicalEffectiveStatusUIProjectionTests.swift`、`RokuricsMacTests/CanonicalEffectiveStatusUIProjectionTests.swift`：新增/更新 Store snapshot、UI display proof rule、View refresh no job/no recompute、Mac item stored snapshot 与 action availability tests。
- `RokuricsTests/CanonicalFileKernelRuntimeTests.swift`、`RokuricsMacTests/CanonicalFileKernelRuntimeTests.swift`：七类 hot-path guard coverage。
- `RokuricsTests/CanonicalStatusTruthRuntimeTests.swift`、`RokuricsMacTests/CanonicalStatusTruthRuntimeTests.swift`：Store/receiver/coordinator read-path source audit 更新为 snapshot API。
- `RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests.swift`、`RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests.swift`：新增缺 R4、View direct peer proof、MainActor status reconciliation attempt、R1/R2/R5 green but R4 missing 不得 READY 的 gate tests。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v9.11 范围、状态源矩阵、R3/R4 证据、测试与 R6 未执行边界。

## 2026-06-15 新增 v9.10 / Real-Device Trial Gate, Evidence Package, Cleanup, No-Retirement Lock 文件

- `RokuricsShared/SyncCore/CanonicalFourDomainRealDeviceTrialGate.swift`：新增 v9.10 四域 trial gate 四态：`READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_TRY_ON_DEVICE`。Gate 只读取 code-level evidence、evidence package、cleanup audit 与 no-retirement lock；build/test summary 缺失返回 NOT_READY，unsafe blocker 返回 UNSAFE。
- `RokuricsShared/SyncCore/CanonicalFourDomainEvidencePackage.swift`：新增 redacted evidence package，汇总 mode transitions、cache hit/miss/rebuild、diagnostics queue/drop/flush duration、MainActor violation counts、status fact/delta/ack/request counts、finalize proof/rejection counts、route/security proof、switch-back proof 和 build/test summary。
- `RokuricsShared/SyncCore/CanonicalFourDomainEvidenceRedaction.swift`：新增 v9.10 evidence redaction detector/proof，阻断 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio、full transcript/note/summary/provider response 和 full generated content。
- `RokuricsShared/SyncCore/CanonicalFourDomainFinalScorecard.swift`：新增 final scorecard，组合 v9.10 gate、evidence package、cleanup audit 和 no-retirement lock，输出 `noLegacyRetirementPerformed` 与 redacted diagnostics summary。
- `RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests.swift`：新增 iPhone targeted tests，覆盖 READY with `realDeviceEvidencePresent=false`、PARTIAL、NOT_READY、每类 unsafe blocker、redaction、cleanup audit 和 no-retirement lock。
- `RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests.swift`：新增 Mac targeted tests，覆盖同一 v9.10 shared contract。
- `docs/Rokurics_Canonical_FourDomain_Kernel_Runbook_v9.md`：新增 v9 四域 runbook，记录 v9.10 gate 四态、required green、evidence package、unsafe stop conditions、no-retirement lock 和本地验证命令。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：更新到 v9.10 状态。

## 2026-06-15 新增 v9.9 / Four-Domain Gate and Deterministic Harness 文件

- `RokuricsShared/SyncCore/CanonicalFourDomainCompletionGate.swift`：新增四域 code-level gate，检查 v9.5 diagnostics async、content-stable cache key、status truth off-main projection、v9.6 UI source cutover、v9.7 realtime exchange、v9.8 connection/transfer owner、default/release oldKernel、legacy fallback、route/security/upload schema、`RequestVerifier`、Mac no reverse connection、heartbeat no heavy sync、view refresh no upload job、retry storm guard、diagnostics redaction 和 oldKernel switch-back proof。输出 `READY` / `PARTIAL` / `UNSAFE`，并保留 `realDeviceEvidencePresent=false`。
- `RokuricsShared/SyncCore/CanonicalFourDomainRuntimeHarness.swift`：新增 deterministic fake two-node harness，串联 fake Connection/Transfer/Sync/File evidence，覆盖 10 个 v9.9 scenarios、no-freeze assertions、proof assertions 和 completion gate report。该 harness 不是真机 evidence。
- `RokuricsShared/SyncCore/CanonicalFourDomainFakeConnectionCarrier.swift`：新增 fake connection carrier，只记录内存 envelope、syncRequested enqueue、storm coalescing、Mac reverse connection attempt 和 heartbeat heavy sync attempt；不绑定 Rokurics HTTPS/TLS/HMAC。
- `RokuricsShared/SyncCore/CanonicalFourDomainFakeTransferPort.swift`：新增 fake transfer port，产生 in-memory finalize proof、partial receive 和 existing different audio conflict/no-overwrite result；不调用 `SecureMacUploadClient` 或真实 route。
- `RokuricsShared/SyncCore/CanonicalFourDomainFakeFileRuntime.swift`：新增 fake file runtime，维护 checksum/read cache、async diagnostics queue proof、hot-path attempt counters 和 cache-hit/repeated-read assertions；不扫描真实文件树、不写 production root。
- `RokuricsTests/CanonicalFourDomainRuntimeHarnessTests.swift`：新增 iPhone targeted tests，覆盖 harness 10 场景、no-freeze/proof assertions、Gate READY/PARTIAL/UNSAFE 和 `realDeviceEvidencePresent=false`。
- `RokuricsMacTests/CanonicalFourDomainRuntimeHarnessTests.swift`：新增 Mac targeted tests，覆盖同一 fake harness/gate contract。Mac app test host 会按现有 scheme 启动 app，但新增 harness 自身不使用真实网络、不新增 route、不写生产根。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.9 gate/harness 范围、fake evidence 边界、安全禁区和验证命令。

## 2026-06-15 新增/更新 v9.8 / Connection and Transfer Runtime Owner Wiring 文件

- `RokuricsShared/SyncCore/CanonicalConnectionRuntime.swift`：新增 portable actor runtime，负责 peer liveness、heartbeat envelope、canonical status request、syncRequested envelope 和 enqueue-only action mapping；不绑定 Rokurics HTTPS/TLS/HMAC。
- `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift`：新增 connection/transfer runtime readiness、configuration、blocker 和 mode mapping；`oldKernel` disabled，shadow/diagnostics carrier-only/no commit，applyNoAudio audio blocked，fullSync 需 owner/manual/fallback/readiness gates 后才启用 runtime owner。
- `RokuricsShared/SyncCore/CanonicalTransferRuntime.swift`：full transfer path 新增 start 后 status refresh/resume、monotonic confirmedBytes、chunk/finalize diagnostics 和 finalize proof handling。
- `RokuricsShared/SyncCore/CanonicalTransferRetryRuntime.swift`：继续作为 Transfer retry/backoff owner，限制 view refresh no job、retry drainer existing eligible only、stale interrupted session status refresh 和 fail-closed blockers。
- `RokuricsShared/SyncCore/CanonicalTransferDiagnostics.swift`：补充 transfer diagnostic summary，保持 safe ids、offset/count/hash prefix 等 redacted 输出。
- `Rokurics/IPhoneCanonicalTransferAdapter.swift`：新增 `IPhoneCanonicalTransferFileSource`，并把 `CanonicalTransferRuntimePort` 映射到 `IPhoneCanonicalSecureAudioUploadPort` / `SecureMacUploadClient` existing start/status/chunk/finalize secure path。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：iPhone app path 创建/刷新 `CanonicalConnectionRuntime`；heartbeat/device-status carrier 生成/消费 canonical connection envelope，callback 只 enqueue existing sync/status work。
- `Rokurics/RecordingUploadCoordinator.swift`：`canonicalFullSync` allowed 时进入 `CanonicalTransferRuntime`，仍通过 secure adapter 上传；finalize proof 写入 v9.4 status truth runtime；applyNoAudio/blocked/oldKernel 回 legacy 或阻断；retry drainer 只恢复 existing eligible job。
- `Rokurics/RecordingUploadClient.swift`、`Rokurics/SecureMacUploadClient.swift`：本轮审计为 existing resumable upload request/response、resume context 和 secure client route carrier；canonical transfer adapter 继续复用这些类型和现有 security path，不新增 upload route schema。
- `RokuricsMac/SecureReceiverService.swift`：Mac receiver 创建/刷新 `CanonicalConnectionRuntime`，传入 `SecureLocalHTTPSServer`，保持 Mac server-only topology。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：既有 heartbeat/status route 在 verifier 通过后记录 connection liveness/status request；既有 resumable finalize route 在 response verified completed 且 checksum/size 匹配后写入 receiver accepted finalize proof fact；未新增 route。
- `RokuricsMac/MacRecordingFileStore.swift`：本轮审计为 existing receive/session store 与 status truth fact helper；partial receive、completed ledger alone 和 existing different audio no-overwrite 规则继续由 store/route/runtime tests 覆盖。
- `RokuricsTests/CanonicalTransferKernelRuntimeTests.swift`、`RokuricsTests/CanonicalStatusExchangeRuntimeTests.swift`：新增/更新 iPhone targeted tests，覆盖 switch owner mapping、fullSync transfer runtime entry、connection liveness/enqueue-only、existing heartbeat carrier 和 oldKernel/applyNoAudio/blocked 边界。
- `RokuricsMacTests/CanonicalTransferKernelRuntimeTests.swift`：新增/更新 Mac targeted tests，覆盖 no new route、RequestVerifier still required、Mac no reverse connection、finalize proof fact、partial receive not proof 和 existing different audio conflict/no-overwrite。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.8 owner wiring、mode mapping、安全边界、测试命令和未完成 paired-device evidence。

## 2026-06-14 新增/更新 v9.7 / Realtime Status Exchange Runtime Wiring 文件

- `RokuricsShared/SyncCore/CanonicalRealtimeStatusExchangeProtocol.swift`：扩展 ack disposition 与 request kind，保持 transport-independent envelope/delta/ack/request contract；旧 payload missing kind/disposition decode 安全。
- `RokuricsShared/SyncCore/CanonicalStatusExchangeRuntime.swift`：新增 actor-backed portable runtime，负责从 `CanonicalStatusTruthRuntime` snapshot 生成 delta、维护 monotonic sequence、pending ack/request、duplicate/stale policy、incoming delta merge 和 request action mapping。
- `RokuricsShared/SyncCore/CanonicalStatusTruthRuntime.swift`：新增 `allFactsSnapshot()`，供 exchange runtime 读取 v9.4 fact store snapshot，不新增 persistent schema。
- `RokuricsShared/SyncCore/CanonicalKernelDiagnostics.swift`：补充 status request/carrier/full inventory/redaction blocked diagnostics kinds。
- `Rokurics/StudyLibrarySyncModels.swift`、`RokuricsMac/StudyLibrarySyncModels.swift`：`DeviceStatusRequest/Response`、`ConnectionHeartbeatRequest/Response`、`LocalNetworkSyncInventoryRequest/Response` 增加 optional `statusExchangeEnvelope`，missing field 兼容旧 peer。
- `Rokurics/SecureMacUploadClient.swift`：`fetchLocalNetworkSyncInventory` 增加 optional envelope overload，仍发 existing `/sync/inventory`，旧调用默认 nil。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：iPhone `StudyLibrarySyncCoordinator`、`LocalNetworkHeartbeatMonitor`、`LocalNetworkSyncEngine` 和 `LocalNetworkSyncAppService` 接入 shared exchange runtime；heartbeat/inventory 发送/消费 envelope，request action 只 enqueue existing sync event 或记录 lightweight proof diagnostics。
- `RokuricsMac/SecureReceiverService.swift`：Mac receiver 创建并持有 shared `CanonicalStatusExchangeRuntime`，继续保留 existing TLS/HMAC/RequestVerifier/server topology。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：existing `/device/status`、`/connection/heartbeat`、`/sync/inventory` 在 verifier 通过后消费 optional envelope，并在 response optional field 回传 delta/request/ack；未新增 route，upload routes 不承载 status exchange。
- `RokuricsMac/ConnectionSyncStateStores.swift`：新增 `recordStatusExchangeRunSyncSoonRequest(...)`，把 incoming `runSyncSoon` request 记录为 existing pending sync hint，Mac 不反连 iPhone。
- `RokuricsTests/CanonicalStatusExchangeRuntimeTests.swift`、`RokuricsMacTests/CanonicalStatusExchangeRuntimeTests.swift`：新增双端 v9.7 targeted tests，覆盖 old peer optional decode、delta flow、finalizeProof completed、metadataOnly not complete、request action-only、duplicate/stale/conflict policy、ack alone not proof、route/security/app-path 引用。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.7 runtime wiring、carrier、安全边界、测试命令和未完成真机 evidence。

## 2026-06-14 新增/更新 v9.6 / Effective Status Binding Cutover 文件

- `RokuricsShared/SyncCore/CanonicalEffectiveStatusUIProjection.swift`：新增 `CanonicalDisplaySyncState`、`CanonicalEffectiveStatusUIProjection` 和 `LegacySyncStatusToCanonicalEffectiveStatusAdapter`，把 canonical effective status/legacy status facts 转成 UI display model，并拒绝 metadataOnly、receiveRecordOnly、completed ledger alone、partial receive、local file exists 等 soft evidence 显示 completed/audio available。
- `Rokurics/RecordingUploadCoordinator.swift`：`displayStatus(for:)` 改由 `displaySyncState(for:)` 映射，canonicalFullSync allowed 时读 `CanonicalEffectiveSyncStatus` projection，oldKernel/blocked/fallback 时经 legacy adapter 得到等价 display model；保留 existing upload route/security/legacy upload path。
- `Rokurics/UploadableRecordingRow.swift`：`RecordingUploadActionAreaPresentation` 增加 `CanonicalDisplaySyncState` overload，复用原有状态文案和 progress/action-area presentation，不改视觉层级。
- `Rokurics/RecordingLibraryView.swift`、`Rokurics/RecordingStudyDetailPage.swift`：现有 recording card/detail action area 改用 `uploadCoordinator.displaySyncState(for:)` 作为状态字段来源；未新增按钮、颜色、字体、间距或导航。
- `Rokurics/StudyLibraryStore.swift`、`RokuricsMac/StudyLibraryStore.swift`、`RokuricsMac/SecureReceiverService.swift`：在已有 `canonicalEffectiveStatus(for:)` 旁新增 `canonicalDisplaySyncState(for:)` read helper，供 status/display projection 边界复用。
- `RokuricsMac/MacRecordingInboxItem.swift`、`RokuricsMac/MacStudyLibraryView.swift`：Mac inbox item 新增 canonical display state/audio availability text，detail “audio” 状态行改读该 display text；receive record only/metadataOnly/partial receive 不显示 audio available。
- `RokuricsTests/CanonicalEffectiveStatusUIProjectionTests.swift`、`RokuricsMacTests/CanonicalEffectiveStatusUIProjectionTests.swift`：新增双端 v9.6 targeted tests，覆盖 metadataOnly、receiveRecordOnly、completed ledger alone、partial receive、finalize proof、peer inventory/hash-size proof、peerUnknown、view refresh no upload job 和 legacy display fallback。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.6 cutover 范围、安全边界、文件地图和验证命令。

## 2026-06-14 新增/更新 v9.5 / No-Freeze Hot Path Recovery 文件

- `RokuricsShared/SyncCore/CanonicalAsyncDiagnosticsWriter.swift`：扩展为真实 app path 使用的 actor-backed diagnostics writer，支持 raw JSONL enqueue、bounded queue/backpressure、append-only flush、后台 compaction、`flushForTests()` / `drainForTests()` 和真实/fake clock `diagnosticsWriteDurationMs`。
- `Rokurics/ConnectionSyncStateStores.swift`：iPhone `ConnectionDiagnosticsStore.record(...)` 改为 redaction + enqueue + in-memory recent buffer/counter；record hot path 不再 `loadEntries()`、不再 JSON decode 全文件、不再 atomic rewrite 全文件、不要求调用方 await、不在 MainActor 写文件。
- `RokuricsMac/SecureReceiverService.swift`：Mac 侧同样接入 `CanonicalAsyncDiagnosticsWriter`，保留 existing receiver/service/security/topology 行为，提供 test flush/drain hook 和 redacted async diagnostics 写入。
- `Rokurics/StudyLibraryStore.swift`、`RokuricsMac/StudyLibraryStore.swift`：canonical effective read cache key 改为内容稳定 signature，排除 `generatedAt`，覆盖 recordings、folders/items、artifacts、tombstone/conflict、upload/effective status、backing revision、fallback state 和 Mac selected hierarchy rule。
- `RokuricsShared/SyncCore/CanonicalStatusTruthRuntime.swift`：新增 actor-backed effective status projection cache、projection snapshot/version/signature、projection metrics、duration diagnostics 和 MainActor reconciliation attempt counter。
- `RokuricsShared/SyncCore/CanonicalStatusFactStore.swift`：补充后台 stale/expired fact cleanup helper，保持 deterministic fact store owner 和 redacted diagnostics。
- `RokuricsShared/SyncCore/CanonicalStatusTruthDiagnostics.swift`、`RokuricsShared/SyncCore/CanonicalKernelDiagnostics.swift`：补充 `statusProjectionDurationMs`、`mainActorStatusReconciliationAttemptCount` 等 v9.5 no-freeze diagnostics cases。
- `Rokurics/StudyLibrarySyncCoordinator.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`、`RokuricsShared/SyncCore/CanonicalEffectiveSyncStatusProjection.swift`：本轮审计确认仍作为现有 sync/status/read path 边界；未新增 route、未改 upload schema、未把 UI refresh/retry drain 改成 job 创建路径。
- `RokuricsTests/CanonicalFileKernelRuntimeTests.swift`、`RokuricsMacTests/CanonicalFileKernelRuntimeTests.swift`：新增双端 diagnostics async enqueue/flush/redaction/backpressure tests，覆盖 MainActor 调用 record 后 flush 落盘。
- `RokuricsTests/CanonicalReadRuntimeTests.swift`、`RokuricsMacTests/CanonicalReadRuntimeTests.swift`：新增/更新 generatedAt-stable cache key 与 repeated read/tree 单次 rebuild coverage。
- `RokuricsTests/CanonicalStatusTruthRuntimeTests.swift`、`RokuricsMacTests/CanonicalStatusTruthRuntimeTests.swift`：新增双端 status truth projection cache/off-main guard coverage，验证 repeated effective status read 不重复 projection、MainActor reconciliation attempt 为 0，并保留 route/security text audit。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.5 scope、文件地图、安全边界和验证结果。

## 2026-06-14 新增/更新 v9.4 / Sync State Truth Protocol 文件

- `RokuricsShared/SyncCore/CanonicalSyncStatusTruthProtocol.swift`：扩展 v9 status fact/proof/effective status contract，新增 `CanonicalStatusFactID`、domain/phase、source/proof/causality/expiry、`CanonicalEffectiveSyncStatus` struct、blocker、hard rules 和 compatibility static statuses。
- `RokuricsShared/SyncCore/CanonicalStatusFactStore.swift`：新增 actor-backed in-memory fact store，支持 replacement、expiration/stale filtering、deterministic merge ordering 和 redacted merge/reject diagnostics；不新增 persistent disk schema。
- `RokuricsShared/SyncCore/CanonicalStatusReconciliation.swift`：新增 proof-driven hard-rule reconciliation runtime，统一 metadataOnly、receiveRecordOnly、completed ledger、partial receive、local file、peer inventory/hash-size、finalize proof、dual ack、conflict、tombstone、unsupported schema、view refresh 和 retry drainer gate。
- `RokuricsShared/SyncCore/CanonicalEffectiveSyncStatusProjection.swift`：新增 read projection helper，将 reconciliation phase/proof/source summary 转成 UI-safe `CanonicalEffectiveSyncStatus`，不触发 sync/upload/transfer/UI mutation。
- `RokuricsShared/SyncCore/CanonicalStatusTruthDiagnostics.swift`：新增 status truth diagnostics event/record/redaction，覆盖 statusFactProduced/Merged/Rejected、proof expired、effective projected、metadataOnly/completedLedger/partialReceive rejection、peer proof unavailable、finalize accepted、different audio conflict、upload job denied。
- `RokuricsShared/SyncCore/CanonicalStatusTruthRuntime.swift`：新增 actor runtime，封装 fact store、produce、facts lookup、reconcile、effective status 和 bounded diagnostics。
- `RokuricsShared/SyncCore/CanonicalStatusTruthReadiness.swift`：新增 `CanonicalStatusTruthReadiness.v940(...)` readiness gate，READY 需要 proof-driven status、hard rules、fact store、integration availability、upload job gate、redacted diagnostics、oldKernel/default/legacy fallback/no route/security change。
- `RokuricsShared/SyncCore/CanonicalKernelDiagnostics.swift`：补充 v9.4 convergence diagnostics cases。
- `Rokurics/RecordingUploadCoordinator.swift`、`Rokurics/StudyLibrarySyncCoordinator.swift`、`Rokurics/StudyLibraryStore.swift`：新增 iPhone read-only status truth runtime 注入与 helper，不改变 legacy UI/upload/read behavior。
- `RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`、`RokuricsMac/StudyLibraryStore.swift`、`RokuricsMac/MacRecordingFileStore.swift`：新增 Mac read-only status truth runtime 注入与 helper，不新增 route、不改 upload schema、不改变 receiver security/topology。
- `RokuricsTests/CanonicalStatusTruthRuntimeTests.swift`：新增 iPhone v9.4 targeted tests，覆盖 truth table、uploadNeeded/not completed、peerUnknown deferred、completed ledger rejected、same hash+size no-op、different hash conflict、UI refresh/retry drainer gate、fact store、redaction、readiness 和 adapter read path。
- `RokuricsMacTests/CanonicalStatusTruthRuntimeTests.swift`：新增 Mac v9.4 targeted tests，覆盖 partial receive、finalize proof completed、metadataOnly/receiveRecordOnly not audioAvailable、stale fact ordering、adapter read path 和 redaction。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.4 scope、truth table、安全边界、old UI coexistence、测试命令和 Mac runner blocker。

## 2026-06-14 新增/更新 v9.3 / Transfer Kernel Runtime 文件

- `RokuricsShared/SyncCore/CanonicalTransferSessionStateMachine.swift`：新增 Transfer runtime state machine，覆盖 idle/starting/started/chunking/interrupted/resuming/finalizing/finalized/failed/aborted/conflict/blocked，负责 confirmedBytes 单调、deterministic next offset、duplicate chunk idempotency、wrong offset refresh、partial receive not finalized、finalize hash/size proof 和 no-overwrite conflict。
- `RokuricsShared/SyncCore/CanonicalTransferProof.swift`：新增 finalize proof snapshot/redaction helper 与 `CanonicalTransferFinalizeProof.v930(...)` factory。diagnostics 只暴露 hash prefix；full hash 只作为 internal proof 字段保留给 runtime/status truth。
- `RokuricsShared/SyncCore/CanonicalTransferRuntime.swift`：新增 portable runtime owner、configuration/policy/result、byte source、`CanonicalTransferRuntimePort` 与 bridge。shared runtime 不引入 URLSession/Network.framework，不绑定 Rokurics route/security 实现，且返回 `uiCompletedStatusMutated=false`。
- `RokuricsShared/SyncCore/CanonicalTransferRetryRuntime.swift`：新增 retry/backoff owner，覆盖 view refresh no job、retry drainer existing eligible only、status refresh before resume、peerUnknown/missing local audio/tombstone/conflict/security/malformed ledger blocker、max attempt/backoff storm guard。
- `RokuricsShared/SyncCore/CanonicalTransferDiagnostics.swift`：新增 Transfer diagnostics kind/record/redaction helpers，禁止 absolute path、full hash、request/response body、raw audio 等敏感内容进入 diagnostics。
- `RokuricsShared/SyncCore/CanonicalTransferKernelReadiness.swift`：新增 `CanonicalTransferKernelReadiness.v930(...)` readiness gate，READY 需要 state machine、proof、adapter、retry/backoff、idempotency、no-route-change、security unchanged、redaction、oldKernel fallback 等 evidence。
- `RokuricsShared/SyncCore/CanonicalTransferProtocol.swift`：兼容扩展 transfer session states、finalize proof v9.3 字段、optional local abort boundary 和 partial receive/completed ledger proof rules。
- `Rokurics/IPhoneCanonicalTransferAdapter.swift`：新增 iPhone TransferPort adapter，薄包装 `IPhoneCanonicalSecureAudioUploadPort` / `RecordingSecureUploadTransport` / `SecureMacUploadClient`，继续使用 existing start/status/chunk/finalize secure upload path。
- `RokuricsMac/MacCanonicalTransferReceiveAdapter.swift`：新增 Mac receive adapter，薄包装 `MacAudioUploadCutoverExecutor` / `MacRecordingFileStore`，不新增 abort route，不直接处理 HTTP security。
- `RokuricsTests/CanonicalTransferKernelRuntimeTests.swift`、`RokuricsMacTests/CanonicalTransferKernelRuntimeTests.swift`：新增双端 v9.3 targeted tests，覆盖 state machine、retry/backoff、redaction、readiness、adapter source path、route/security unchanged、partial receive not proof、finalize proof output 和 no-overwrite。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.3 scope、文件地图、安全边界和验证命令。

## 2026-06-14 新增/更新 v9.0 / Kernel Contract Freeze 文件

- `RokuricsShared/SyncCore/CanonicalKernelProtocols.swift`：新增 portable 基础类型 `CanonicalNodeID`、`CanonicalNodeRole`、`CanonicalNodeIdentity`、`CanonicalLogicalTime`、`CanonicalSequence`、`CanonicalProtocolVersion`、`CanonicalObjectID`、`CanonicalDomain`、`CanonicalKernelModeMirror` 和 protocol boundary marker。`CanonicalKernelModeMirror` 只映射现有 `CanonicalKernelSwitchMode` 语义，不替代 `CanonicalKernelSwitch`。
- `RokuricsShared/SyncCore/CanonicalConnectionProtocol.swift`：定义 Connection contract、peer liveness、connection envelope/ack、heartbeat/status/syncRequested payload、carrier protocol 与 non-goals。Connection 只负责 carrier/liveness/status hint，不 mark uploaded、不 scan file tree、不 write metadata、不 create upload job。
- `RokuricsShared/SyncCore/CanonicalTransferProtocol.swift`：定义 transfer session/start/status/chunk/chunk ack/finalize/finalize proof/retry policy/retry record/transfer port。`CanonicalTransferFinalizeProof` 是 receiver accepted proof；completed ledger alone 不是 peer proof。
- `RokuricsShared/SyncCore/CanonicalSyncStatusTruthProtocol.swift`：定义 `CanonicalStatusFact`、`CanonicalStatusProof`、`CanonicalEffectiveSyncStatus`、`CanonicalStatusTruthEngine`、`CanonicalStatusReconciliation` 和 hard proof rules。
- `RokuricsShared/SyncCore/CanonicalRealtimeStatusExchangeProtocol.swift`：定义 transport-independent realtime status exchange envelope、delta、ack、request、sequence/logical-clock/stale/expire/conflict policy 类型；不接入任何本地 carrier runtime。
- `RokuricsShared/SyncCore/CanonicalFileProtocol.swift`：定义 file tree provider/snapshot、manifest builder、checksum cache key/record/lookup、root-bound writer、atomic write/rollback/postcondition、no-freeze budget 和 MainActor hot-path violation 类型。
- `RokuricsShared/SyncCore/CanonicalKernelDiagnostics.swift`：定义 v9.0 diagnostics taxonomy，覆盖 performance、convergence 与 forbidden redaction signals。
- `RokuricsShared/SyncCore/CanonicalKernelInvariants.swift`：定义 cross-domain invariants catalog，覆盖四域 owner、default/release oldKernel、legacy fallback、route/schema/security/no-proof/no-freeze/redaction 等强不变量。
- `RokuricsShared/SyncCore/CanonicalKernelV9Completion.swift`：定义 `CanonicalKernelV9ContractReadinessGate.v900(...)`、evidence bool、readiness report/blocker/status。gate 纯计算，无 runtime side effect。
- `RokuricsTests/CanonicalKernelV9ContractTests.swift`、`RokuricsMacTests/CanonicalKernelV9ContractTests.swift`：新增双端 contract tests，覆盖 Codable、hard proof rules、redaction detector、gate 四态和 transport-independent boundary。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`：记录 v9.0 contract-only 范围、文件地图、安全边界和验证命令。

## 2026-06-13 新增/更新 v8.73 / Final App-State Readiness 文件

- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 `CanonicalRealDeviceTrialReadinessCodeCompleteResult`、`CanonicalRealDeviceTrialReadinessBlocker` 和 `CanonicalRealDeviceTrialReadinessGate.v873(...)`。该 gate 只汇总代码级 readiness，不接入运行时，不触发 sync/upload，不改 route/security；输出 `READY_FOR_REAL_DEVICE_APP_TRIAL`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_TRY_ON_DEVICE` 四态，并单独记录 `realDeviceEvidencePresent`。
- `RokuricsTests/CanonicalSyncKernelCompletionTests.swift`、`RokuricsMacTests/CanonicalSyncKernelCompletionTests.swift`：新增 v8.73 final app-state gate 回归测试，覆盖 READY with no real-device evidence、缺 convergence 修复时 PARTIAL、build/test 缺失时 NOT_READY，以及 route/security、heartbeat heavy sync、metadataOnly/audio truth、Mac reverse connection、retry storm 等 unsafe blocker。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`、`docs/LongRecordingTestPlan.md`：记录 v8.73 是 Claude 诊断问题最终收口轮，read cache/Mac inventory/`syncRequested`/event trigger/status convergence 已有代码级 gate，default/release oldKernel、Path B legacy transport、240 秒 fallback、heartbeat 非 sync、no route/security change 与 real-device evidence 边界保持。

## 2026-06-13 新增/更新 v8.72 / Event-Driven Sync Trigger and Status Convergence v1 文件

- `Rokurics/StudyLibrarySyncModels.swift`、`RokuricsMac/StudyLibrarySyncModels.swift`：新增 shared `SyncTriggerReason` 与 `LocalNetworkSyncEventTrigger` notification contract，覆盖 manual peer request、recording created/metadata、study library metadata、generated artifact availability、tombstone/conflict、upload finalized、Mac receive finalized、transcription/note status、status refresh、retry 和 app foreground pending changes。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：复用并扩展 v8.71 immediate sync queue，新增 unified event queue/debounce/dedupe/max-frequency/storm protection/offline-background defer/follow-up tick。queued tick 仍走现有 scheduler/engine path，不改 3 秒 heartbeat 或 240 秒 periodic fallback。
- `Rokurics/RecordingManager.swift`、`Rokurics/StudyLibraryStore.swift`：iPhone 新录音保存、rename、filing、delete/restore/tombstone、upload status/finalize/retry、folder/item metadata 与 generated artifact apply 变化后只 post event，不直接 sync、不创建 upload job。
- `RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/ConnectionSyncStateStores.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`：Mac 事件队列做 local refresh 并通过既有 `syncRequested` hint/pending state 等待 iPhone 拉取；server receive/finalize callback 带 event reason，heartbeat/status/inventory consumed diagnostics 保持现有 route/schema。
- `RokuricsMac/MacRecordingFileStore.swift`、`RokuricsMac/StudyLibraryStore.swift`：Mac transcription/note status、generated artifact availability、library metadata、tombstone/conflict 变化后 post status convergence/event trigger；不触发 AI rerun。
- `RokuricsTests/RokuricsTests.swift`、`RokuricsMacTests/RokuricsMacTests.swift` 及若干 Mac server construction tests：补 event reason parsing、status-only trigger no upload job、study folder metadata event、Mac receive/finalize reason 与 pending signal reason 回归。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/LongRecordingTestPlan.md`：记录 v8.72 event-driven trigger、status convergence、debounce/storm protection、Mac no-reverse-connect、no-route/no-security-change 与缺 real-device evidence。

## 2026-06-13 新增/更新 v8.71 / Live Heartbeat Consumes syncRequested 文件

- `Rokurics/StudyLibrarySyncModels.swift`、`RokuricsMac/StudyLibrarySyncModels.swift`：`DeviceStatusResponse` 增加兼容旧 response 的 `syncRequested` 与可选 `syncStartSignal` 解码；missing/malformed optional hint 安全落到 `false`，不改变 `ok` 或 summary 字段语义。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：live `/device/status` heartbeat 解析 `syncRequested` hint，并通过最小 helper 排队 immediate sync tick。helper 复用现有 sync/manual path，带 pending/running/debounce gate，不在 heartbeat callback 内直接执行 heavy sync，不改变 3 秒 heartbeat 或 240 秒 periodic sync。
- `RokuricsMac/SecureReceiverService.swift`：保留 `prepareManualStudyLibrarySync` pending 设置与“等待 iPhone 执行同步”状态，补充 redacted manual sync pending diagnostics。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：`/device/status` 与既有 `/connection/heartbeat` 一样可广告 pending `syncRequested`；`/sync/inventory` 观察到 iPhone 带 `syncRunID` 的同步请求后，把 Mac pending 状态推进为已开始/已消费的可观察状态。不新增 route，不改 route path/security。
- `RokuricsMac/ConnectionSyncStateStores.swift`：新增 pending manual sync 被 inventory 观察到时的状态记录 helper。
- `RokuricsTests/RokuricsTests.swift`、`RokuricsMacTests/RokuricsMacTests.swift`：新增/更新 heartbeat response decode、live heartbeat queue/debounce、scheduler pending gate、Mac manual pending inventory observed 等回归测试。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/LongRecordingTestPlan.md`：记录 v8.71 scope、no-route/no-security/no-240s-change 边界、diagnostics 和缺 real-device evidence。

## 2026-06-12 新增/更新 v8.70 / Mac Server Inventory Off-Main + Kernel-Mode Build Gating 文件

- `RokuricsMac/SecureLocalHTTPSServer.swift`：新增 Mac inventory kernel-mode build policy、request-scoped canonical snapshot/context 和 off-main canonical builder。`/sync/inventory` 的 legacy response schema/route/security 保持不变；`oldKernel`/blocked 跳过 canonical object/manifest/seam，canonical modes 只构建和运行必要 facts/seams，`canonicalFullSync` 每 request 只构建一次 canonical snapshot 并供 seams 复用。
- `RokuricsMac/SecureReceiverService.swift`：保存 `CanonicalKernelSwitchResult.effectiveMode`，并在启动 `SecureLocalHTTPSServer` 时传入 server；默认仍为 `oldKernel`，refresh path 不改变 heartbeat、syncRequested、upload route 或 connection security。
- `RokuricsMac/MacCanonicalRecordingAdapter.swift`：将纯值转换 adapter 标为 nonisolated，允许 Mac server canonical object conversion 在 background task 中执行，不改变 canonical object schema。
- `RokuricsMacTests/StudyLibrarySyncTests.swift`：新增/更新 Mac inventory route coverage，覆盖 oldKernel skip canonical build/schema unchanged、canonicalShadow off-main build/reuse、canonicalFullSync 每 request build once、manifest off-main diagnostics。
- `RokuricsMacTests/CanonicalKernelSwitchTests.swift`：新增 Mac inventory canonical build policy gating coverage，验证 oldKernel、shadow、decisionOnly、applyNoAudio、fullSync 的 facts/seam gating。
- `RokuricsMacTests/CanonicalShadowSeamTests.swift`、`RokuricsMacTests/CanonicalV8RecordingMetadataNoCommitTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataGuardedCommitSeamTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactGuardedCommitSeamTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataGuardedCommitSeamTests.swift`、`RokuricsMacTests/CanonicalTombstoneConflictGuardedCommitSeamTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataLandingTests.swift`：测试 server construction 显式传入对应 kernel mode，防止默认 oldKernel 误跑 canonical seam fixture。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v8.70 scope、off-main/gating/reuse diagnostics、验证命令、未触碰 syncRequested/heartbeat/event-driven sync 和仍缺 real-device evidence。

## 2026-06-12 新增/更新 v8.69 / Canonical Read Effective Projection Cache 文件

- `Rokurics/StudyLibraryStore.swift`：新增 canonical effective read cache、cache key、projection metrics 和 bounded redacted diagnostics。`effectiveStudyItems` / `effectiveStudyFolders` 在 canonical served 时返回缓存 projection；config/result/backing refresh/fallback 状态变化时重建一次。当前 iPhone 源码没有 `effectiveStudyTree` property，本轮不新增 iPhone tree API。
- `RokuricsMac/StudyLibraryStore.swift`：新增 canonical effective read cache，缓存 items、folders 和 `effectiveStudyTree`。`tree()` 的默认 selected-rule path 返回 cached effective tree；legacy/fallback/oldKernel 继续返回 stored `studyTree`。
- `RokuricsShared/SyncCore/CanonicalReadRuntime.swift`：新增 `canonicalReadEffectiveCacheHit`、`canonicalReadEffectiveCacheMiss`、`canonicalReadEffectiveCacheInvalidated`、`canonicalReadEffectiveCacheRebuilt`、`canonicalReadEffectiveTreeRebuilt`、`canonicalReadEffectiveFallbackLegacy`、`canonicalReadEffectiveRepeatedAccessAvoidedRebuild`、`canonicalReadEffectiveRebuildDurationMs` diagnostics kind。
- `RokuricsTests/CanonicalReadRuntimeTests.swift`、`RokuricsMacTests/CanonicalReadRuntimeTests.swift`：新增/更新 oldKernel legacy cached path、canonical first rebuild、repeated access no rebuild、config/result/refresh invalidation、fallback legacy、no sync/upload side effect 和 diagnostics redaction coverage。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v8.69 cache strategy、oldKernel legacy cached tree、无 sync/heartbeat/apply/upload/route/security 改动、v8.70/v8.71/v8.72 后续边界和缺 real-device evidence。

## 2026-06-12 新增/更新 v8.68 / T7 Single Kernel Switch UI + Final Code Completion Gate 文件

- `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift`：新增 T7 手动主开关 5 档 choices 与 manual-mode normalization；default/release 仍为 `oldKernel`，旧 `diagnosticsOnly` 仅保留为内部兼容安全 no-op，不进入用户可见主开关。
- `Rokurics/IPhoneSettingsView.swift`、`RokuricsMac/MacSettingsView.swift`：DEBUG `Debug · 同步内核` 区的 `内核模式` picker 只显示 `oldKernel`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`；`canonicalFullSync` 需要确认，切回 `oldKernel` 清 confirmation；旧 libraryMetadata pilot 标为高级限制/诊断。
- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 `CanonicalSyncKernelCodeCompletionResult` 四态与 `CanonicalSyncKernelCompletionScorecard.v868(...)`；manual switch gate 继续兼容旧字段，同时新增 `allowedForRealDeviceTrial`、`blockedWithReasons`、`unsafeToTry`、`needsBuildValidation`、`needsSwitchBackProof`、`needsOwnerApproval`、`needsBackupAcknowledgement`。
- `RokuricsTests/CanonicalKernelSwitchTests.swift`、`RokuricsMacTests/CanonicalKernelSwitchTests.swift`：新增 5 档 selector choices 与 fullSync confirmation 清理覆盖。
- `RokuricsTests/CanonicalSyncKernelCompletionTests.swift`、`RokuricsMacTests/CanonicalSyncKernelCompletionTests.swift`：新增 v8.68 READY/PARTIAL/NOT_READY/UNSAFE、realDeviceEvidence=false、manual switch gate owner/backup/switch-back/unsafe blocker 覆盖。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`、`docs/LongRecordingTestPlan.md`：记录 v8.68 T7、单一主开关、5 档、default/release oldKernel、fullSync gates、旧开关降权、Path B 保留 legacy transport 和 stop conditions。

## 2026-06-12 新增/更新 v8.67 / T6 Debug Switch-Back Proof Driver 文件

- `RokuricsShared/SyncCore/CanonicalSwitchBackProofDiagnostics.swift`：新增 DEBUG-only switch-back proof JSONL writer、event schema、UI-safe summary 和 shared runner。runner 调用 existing `CanonicalRealisticRootSwitchBackProofDriver`，只在 temp/test clone 上执行 proof，并把 JSONL evidence 写到 temp proof-run root 下的 `Diagnostics/canonical-switch-back-proof.jsonl`，UI 只显示 redacted temp relative path，`evidenceKind=realisticRoot` 且 `realDeviceEvidencePresent=false`。
- `RokuricsShared/SyncCore/CanonicalLegacyCompatibility.swift`：补强 `CanonicalSwitchBackRootSafetyGuard`，继续拒绝 `/`、home、repo root、Documents/Application Support production root 和未标记非 temp root，并新增 Documents/Application Support production 子路径与 Desktop production root 拒绝。
- `Rokurics/IPhoneCanonicalSwitchBackProofDriver.swift`：iPhone Debug 薄 wrapper，解析当前 `Documents/Rokurics` app data root 作为 source root，交给 shared runner clone 到 temp 后运行 proof。
- `RokuricsMac/MacCanonicalSwitchBackProofDriver.swift`：Mac Debug 薄 wrapper，解析当前 `MacAppStorageProfile.applicationSupportRootURL` 作为 source root，交给 shared runner clone 到 temp 后运行 proof。
- `Rokurics/IPhoneSettingsView.swift`：`Debug · 同步内核` 区新增“运行新旧内核切回证明”按钮、running/status 和 UI-safe summary；不切主开关、不触发 sync/upload。
- `RokuricsMac/MacSettingsView.swift`：同名 Debug 按钮与 summary；不重启 receiver、不改 `/sync/inventory`、route/security、`receive.json`、audio inbox、pending sync、transcription 或 note generation。
- `RokuricsTests/CanonicalSwitchBackTests.swift`、`RokuricsMacTests/CanonicalSwitchBackTests.swift`：新增 root guard 子路径/Desktop 拒绝、shared runner redacted JSONL、missing-source blocker、平台 driver 存在和 Settings 按钮文本覆盖。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`：记录 v8.67 T6 范围、realistic-root clone proof、redacted JSONL、非 real-device evidence 和 v8.68 T7 下一步。

## 2026-06-12 新增/更新 v8.66 / T4-T5 Executor and Port Injection + Gated Production-Root Write 文件

- `RokuricsShared/SyncCore/CanonicalProductionPortInjectionPolicy.swift`：新增共享 mode -> injection decision helper，只消费 `CanonicalKernelSwitchEffectiveConfiguration` 和传入 root URL；判断 non-audio executor、existence port、audio executor、production-root write 和 root safety。specialized configs 只能降权，不能提权。
- `Rokurics/IPhoneCanonicalProductionPortFactory.swift`、`RokuricsMac/MacCanonicalProductionPortFactory.swift`：新增平台工厂。`oldKernel`/diagnostics/shadow/decision/blocked 返回 nil/disabled；`canonicalApplyNoAudio` 注入 non-audio apply/existence availability 但 audio disabled；`canonicalFullSync` gate allowed 后才构造 production-root RealApplyPorts，Mac 额外注入 existence ledger 与 audio executor holder。
- `Rokurics/MacConnectionView.swift`、`Rokurics/StudyLibrarySyncCoordinator.swift`：iPhone app/coordinator/engine construction 与 refresh path 现在从 factory 输出更新 recording/library/generated/tombstone executor slots，不再直接把旧 libraryMetadata pilot executor 当 production owner。
- `Rokurics/RecordingUploadCoordinator.swift`：canonical audio upload 在既有 runtime mode check 之外增加 factory gate；只有 `canonicalFullSync` allowed 且 root safety 通过时才构造 `IPhoneAudioUploadCutoverExecutor`，仍复用 `SecureMacUploadClient` existing secure upload path。
- `RokuricsMac/RokuricsMacApp.swift`、`RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`：Mac app/service/server construction 按 factory 输出传入 recording/library/generated/tombstone executors、`canonicalRecordingExistenceApplyPort` 和 `MacAudioUploadCutoverExecutor` holder；server route/security behavior 未变。
- `RokuricsTests/CanonicalKernelSwitchTests.swift`、`RokuricsMacTests/CanonicalKernelSwitchTests.swift`：新增 factory/injection tests，覆盖 oldKernel nil、decision disabled、applyNoAudio audio blocked、fullSync owner/manual/root gate、release/default blocked、specialized config 不能绕过主开关、metadataOnly 非 audioAvailable 和 audio route list 不变。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/LongRecordingTestPlan.md`：记录 v8.66 T4/T5 范围、mode-gated injection、production-root gate、existence/audio 边界、无 route/security 修改、无 real-device evidence 和 v8.67 T6 下一步。

## 2026-06-12 新增/更新 v8.65 / T2-T3 Master Switch Read + recordingMetadata ReadSeam Runtime Wiring 文件

- `Rokurics/StudyLibrarySyncCoordinator.swift`：iPhone sync coordinator / local network sync engine 在解析 `CanonicalKernelSwitch` 后把 `effectiveConfiguration.readRuntimeConfiguration` 传入 `StudyLibraryStore`；`oldKernel`/disabled/blocked 清空 read override，`canonicalFullSync` gate allowed 时可传 guarded read config。不改变 sync decision、apply/upload runtime 或 upload job 创建。
- `Rokurics/StudyLibraryStore.swift`、`RokuricsMac/StudyLibraryStore.swift`：双端新增 `setCanonicalReadRuntimeConfiguration(...)`，区分 master-switch-managed disabled 与 test/direct override；refresh effective read projection 时以主开关 read config 为准，legacy backing arrays 不变，read 不 mutate store。
- `RokuricsMac/RokuricsMacApp.swift`、`RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`：Mac app/receiver/server construction 与 refresh path 传递 read runtime config，server rebuild 不丢失 Store read config；不改变 `/sync/inventory` response、`receive.json`、audio inbox、pending sync、route 或 security。
- `Rokurics/IPhoneCanonicalReadRuntimeAdapter.swift`、`RokuricsMac/MacCanonicalReadRuntimeAdapter.swift`：canonical read runtime adapter 通过 recordingMetadata ReadSideSeam 执行 read-side comparison/projection；divergence、read failure、unsupported 或 missing evidence fallback legacy。
- `Rokurics/IPhoneRecordingMetadataReadSideSeam.swift`、`RokuricsMac/MacRecordingMetadataReadSideSeam.swift`：继续作为 recordingMetadata domain read seam，现在被 runtime adapter 真实引用。
- `RokuricsTests/CanonicalReadRuntimeTests.swift`、`RokuricsMacTests/CanonicalReadRuntimeTests.swift`、`RokuricsTests/CanonicalKernelSwitchTests.swift`：新增/更新 master switch -> Store read config、mode switch refresh、recording ReadSeam invocation、fallback/no side effect、specialized read config cannot bypass master switch 的回归覆盖。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v8.65 T2/T3 范围、read config 接线、ReadSeam runtime 引用、specialized config 边界、验证命令和仍缺 real-device evidence。

## 2026-06-12 新增/更新 v8.64 / T1 Inventory MainActor Residual Closure 文件

- `Rokurics/StudyLibrarySyncCoordinator.swift`：iPhone inventory builder 改为 background input 驱动；metadata load、jobs load、directory scan、recording/folder/item metadataHash、artifact SHA256 与 sync manifest facts 收集转入 detached background path；`buildRuntimeSnapshot(...)` 只消费 immutable input，保留 legacy inventory schema、canonical snapshot schema、checksum cache key/schema 与 same-run snapshot reuse。
- `Rokurics/StudyLibraryStore.swift`：新增 `makeSyncManifestInBackground(deviceID:generatedAt:)`，将 recordings load 与 `StudyLibrarySyncManifest` 构建转成 background snapshot -> pure build；只保留轻量 root 配置读取在 MainActor。
- `RokuricsShared/SyncCore/CanonicalInventoryRuntime.swift`：runtime diagnostics/report 增加 `manifestBuildDurationMs`、`hashSkippedByCacheHitCount`、`mainActorManifestBuildAttemptCount`，并把 manifest build MainActor attempt 纳入 performance guard；telemetry 仍由真实 path/clock/cache merge 产生。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：Mac `/sync/inventory` facts 收集转入 background input，route 只消费 manifest facts、metadata hashes 和 artifacts；不改变 response schema、route behavior、`RequestVerifier` 或 TLS/HMAC/pinning/nonce/body hash。
- `RokuricsMac/StudyLibrarySyncModels.swift`、`RokuricsMac/StudyLibraryModels.swift`、`RokuricsMac/MacRecordingFileStore.swift`、`RokuricsMac/NoteStore.swift`、`RokuricsMac/MacRecordingInboxItem.swift`、`RokuricsMac/MacSecurityUtilities.swift`：补充纯值类型/纯 helper 的 `nonisolated` 标注，使 Mac inventory background facts path 在 Swift default MainActor isolation 下不回到主线程。
- `RokuricsTests/CanonicalInventoryRuntimeTests.swift`、`RokuricsMacTests/CanonicalInventoryRuntimeTests.swift`、`RokuricsMacTests/StudyLibrarySyncTests.swift`：新增/更新 cache-hit skip、manifest background equivalence、real telemetry、MainActor guard 和 Mac inventory diagnostic coverage。仓库未发现单独 `CanonicalChecksumCacheTests`；checksum cache coverage 位于 `CanonicalInventoryRuntimeTests`。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v8.64 T1 范围、MainActor 重活清理、Mac blocker 状态、真实 telemetry、验证命令和仍缺 real-device evidence。

## 2026-06-11 新增/更新 v8.57 / P3-2 Realistic Library Root Switch-Back Proof 文件

- `RokuricsShared/SyncCore/CanonicalLegacyCompatibility.swift`：扩展 `CanonicalCrashPoint` 至 12 个 crash/restart 点，新增 `CanonicalSwitchBackRootSafetyGuard`、`CanonicalRealisticLibraryRootFixture`、`CanonicalRealisticAppDataRootClone`、`CanonicalDomainSwitchBackMatrix`、`CanonicalKernelSwitchSequenceProof`、`CanonicalKernelSwitchBackProof`、`CanonicalSwitchBackEvidencePackage` 和 `CanonicalSwitchBackEvidenceExporter`；`CanonicalSwitchBackRealisticRootHarness` 改为写 realistic fixture 并输出 v8.57 redacted proof。
- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 `CanonicalSyncKernelCompletionScorecard.v857(...)`，将 P0-P3 code-level completion 与 realistic-root proof、default/release oldKernel、legacy fallback、diagnostics redaction 和 real-device evidence blocker 合并到 v8.57 scorecard。
- `RokuricsTests/CanonicalSwitchBackTests.swift`、`RokuricsMacTests/CanonicalSwitchBackTests.swift`：新增 root safety、realistic fixture/clone、五域 domain matrix、old->new->old->new sequence、evidence redaction 和 v8.57 scorecard tests。
- `RokuricsTests/CanonicalCrashRecoveryTests.swift`、`RokuricsMacTests/CanonicalCrashRecoveryTests.swift`：新增 12 个 crash point 与 audio partial/finalize/retry fail-closed tests。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`：记录 v8.57 realistic-root switch-back proof、root safety、domain/crash/evidence/scorecard 边界和仍缺 real-device evidence。

## 2026-06-11 新增/更新 v8.56 / P3-1 Unified Master Kernel Switch 文件

- `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift`：主开关 contract 增加 `CanonicalKernelSwitchGate`、`CanonicalKernelSwitchGateResult`、`CanonicalKernelSwitchGateState`、`CanonicalKernelSwitchEffectiveConfigurationBuilder`、`CanonicalKernelSwitchReport` 和 `CanonicalKernelSwitchDiagnosticKind`；`CanonicalKernelSwitchPolicy` 增加 inventory/sync/apply/audio/read/domain readiness、route/security、production-root、unresolved conflict、switch-back 和 canonical-only disk-format blockers；advanced overrides 改为只能降权，不能提升主开关权限。
- `RokuricsMac/RokuricsMacApp.swift`：Mac app 启动路径使用 `CanonicalKernelSwitch` effective libraryMetadata pilot config，旧 UserDefaults libraryMetadata debug pilot 不能直接成为 receiver production owner。
- `Rokurics/IPhoneSettingsView.swift`、`RokuricsMac/MacSettingsView.swift`：DEBUG 同步内核 fullSync 确认文案更新为 gate/legacy fallback/test-device 语义；旧 libraryMetadata 专项开关说明为高级限制入口，不能越过主开关。
- `RokuricsTests/CanonicalKernelSwitchTests.swift`、`RokuricsMacTests/CanonicalKernelSwitchTests.swift`：新增 P3-1 fullSync gate、readiness/switch-back blocker、advanced override 降权、unsafe same-mode override blocked、libraryMetadata production-root pilot cannot override oldKernel、diagnostics/report redaction 和 builder/gate contract tests。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`：记录 v8.56 主开关收敛、默认 oldKernel、fullSync gate、specialized config 降权、legacy fallback 和 v8.57 switch-back proof 前置条件。

## 2026-06-11 新增/更新 v8.55 / P2-5 audioUpload Domain Readiness 文件

- `RokuricsShared/SyncCore/CanonicalUploadStateTruth.swift`：新增 `CanonicalAudioUploadDomainFields`、`CanonicalAudioUploadProofSchema`、`CanonicalAudioUploadDecisionInput`、`CanonicalAudioUploadDecisionResult`、`CanonicalAudioUploadAvailability`、`CanonicalAudioUploadReadStatus` 和 `CanonicalAudioUploadOwnershipPolicy`；status projection 增加 readStatus；peerUnknown ownership 不允许 fallback overwrite。
- `RokuricsShared/SyncCore/CanonicalSyncRuntime.swift`：`CanonicalSyncRuntimeDecisionScope` 增加 `audioUpload`，默认 enabled scopes 与 diagnostics 增加 `canonicalAudioUploadDecision*`、metadataOnly/receiveRecordOnly/peerUnknown/no-op/conflict/security 等 audioUpload 域事件。
- `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift`：`canonicalFullSync` 的 sync policy 显式启用 audioUpload decision scope；`canonicalApplyNoAudio` 继续禁用 audio runtime；default/release 仍解析为 `oldKernel`。
- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 `CanonicalAudioUploadDomainReadinessScorecard.v855P2_5(...)`，记录 decision/commit/upload/retry/read/fallback/switch-back/diagnostics/tests/docs/device evidence，`readyToRetireLegacyReportOnly` 保持 report-only。
- `RokuricsTests/CanonicalUploadStateTruthTests.swift`、`RokuricsMacTests/CanonicalUploadStateTruthTests.swift`：新增 v8.55 contract/readStatus、redaction、metadataOnly upload-needed 和 peerUnknown no fallback overwrite coverage。
- `RokuricsTests/CanonicalSyncRuntimeTests.swift`、`RokuricsMacTests/CanonicalSyncRuntimeTests.swift`：新增 audioUpload scope primary decision diagnostics 与 duplicate guard coverage。
- `RokuricsTests/CanonicalKernelSwitchTests.swift`、`RokuricsMacTests/CanonicalKernelSwitchTests.swift`：新增 fullSync audioUpload scope enabled 与 applyNoAudio audio disabled coverage。
- `RokuricsTests/CanonicalSyncKernelCompletionTests.swift`、`RokuricsMacTests/CanonicalSyncKernelCompletionTests.swift`：新增 audioUpload v8.55 scorecard report-only/device-evidence blocker coverage。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/LongRecordingTestPlan.md`：记录 v8.55 contract、runtime/readiness、禁区、验证和剩余真机 evidence blocker。

## 2026-06-11 新增/更新 v8.54 / P2-4 tombstoneConflict Domain Readiness 文件

- `RokuricsShared/SyncCore/CanonicalTombstoneConflictCutover.swift`：新增 `CanonicalTombstoneConflictBusinessFields`、`CanonicalTombstoneConflictHashSchema`、`CanonicalTombstoneConflictModifiedAtPolicy` 和 decision input/result；candidate marker hash/payload 统一到 `canonical-tombstone-conflict-v1`，排除 delete/path/content/UI/upload/receive/audio/provider/diagnostics。
- `RokuricsShared/SyncCore/CanonicalSyncRuntime.swift`：`CanonicalSyncRuntimeDecisionScope` 增加 `tombstoneConflict`，authority gate 增加 tombstoneConflict schema 版本检查与 `canonicalTombstoneConflictDecision*` diagnostics。
- `RokuricsShared/SyncCore/CanonicalReadRuntime.swift`：read runtime 增加 `canonicalTombstoneConflictRead*` diagnostics alias，覆盖 canonical served、legacy fallback、equivalent/divergent diff、blocked 和 read did not trigger delete。
- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 `CanonicalTombstoneConflictDomainReadinessScorecard.v854P2_4(...)`，保持 real-device evidence、manual switch 和 legacy retirement report-only。
- `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift`：主开关 sync policy 显式启用 tombstoneConflict decision scope；apply policy 已保持 tombstoneConflict enabled；default/release 仍解析为 `oldKernel`。
- `RokuricsTests/CanonicalTombstoneConflictTests.swift`、`RokuricsMacTests/CanonicalTombstoneConflictTests.swift`：双端 hash/decision/runtime/read/scorecard targeted coverage。
- `RokuricsTests/CanonicalTombstoneConflictCutoverTests.swift`、`RokuricsMacTests/CanonicalTombstoneConflictCutoverTests.swift`、`RokuricsTests/CanonicalTombstoneConflictReadSideTests.swift`、`RokuricsMacTests/CanonicalTombstoneConflictReadSideTests.swift`：既有 cutover/read-side regression coverage，继续证明 root-bound apply、rollback/postcondition、no delete/restore/GC 和 read-side no-mutation。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v8.54 contract、runtime/readiness、禁区、验证和剩余真机 evidence blocker。

## 2026-06-11 新增/更新 v8.53 / P2-3 generatedArtifacts Domain Readiness 文件

- `RokuricsShared/SyncCore/CanonicalCore.swift`：新增 `CanonicalGeneratedArtifactBusinessFields`、`CanonicalGeneratedArtifactHashSchema`、`CanonicalGeneratedArtifactModifiedAtPolicy` 和 decision input/result；hash schema 为 `canonical-generated-artifact-v1`，排除 path、observedAt、provider response 和正文内容。
- `RokuricsShared/SyncCore/CanonicalSyncRuntime.swift`：`CanonicalSyncRuntimeDecisionScope` 增加 `generatedArtifacts`，authority gate 增加 generated artifact schema 版本检查与 `canonicalGeneratedArtifactDecision*` diagnostics。
- `RokuricsShared/SyncCore/CanonicalReadRuntime.swift`：read runtime 增加 `canonicalGeneratedArtifactRead*` diagnostics alias，覆盖 canonical served、legacy fallback、equivalent/divergent diff、blocked 和 `contentExcluded=true`。
- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 `CanonicalGeneratedArtifactDomainReadinessScorecard.v853P2_3(...)`，保持 real-device evidence 和 legacy retirement report-only。
- `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift`：主开关 sync policy 显式启用 generatedArtifacts decision scope；default/release 仍解析为 `oldKernel`。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：scoped primary decision plan 接入 generated artifact download/no-op/defer/conflict 投影与 duplicate guard identity；仍走既有 artifact download/apply/fallback 边界。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：report-only sync runtime gate context 增加 generated artifact schema 字段。
- `RokuricsTests/CanonicalGeneratedArtifactDomainTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactDomainTests.swift`：双端 hash/modifiedAt/content proof/blocker contract coverage。
- `RokuricsTests/CanonicalSyncRuntimeTests.swift`、`RokuricsMacTests/CanonicalSyncRuntimeTests.swift`、`RokuricsTests/CanonicalReadRuntimeTests.swift`、`RokuricsMacTests/CanonicalReadRuntimeTests.swift`、`RokuricsTests/CanonicalSyncKernelCompletionTests.swift`、`RokuricsMacTests/CanonicalSyncKernelCompletionTests.swift`：runtime schema gate、read diagnostics、duplicate guard 和 scorecard regression coverage。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v8.53 contract、runtime/readiness、禁区、验证和剩余真机 evidence blocker。

## 2026-06-11 新增/更新 v8.52 / P2-2 libraryMetadata Domain Readiness 文件

- `RokuricsShared/SyncCore/CanonicalLibraryObject.swift`：新增 `CanonicalLibraryMetadataBusinessFields`、`CanonicalLibraryMetadataHashSchema`、`CanonicalLibraryMetadataModifiedAtPolicy` 和 decision input/result；folder/study item metadataHash 改走 `canonical-library-metadata-v1`，排除 resource tokens/path/content。
- `RokuricsShared/SyncCore/CanonicalProjectionContract.swift`：folder/item metadata hash payload 改为同一 libraryMetadata business fields 输入；移除 study item `resourceTokens` 对 metadataHash 的影响。
- `RokuricsShared/SyncCore/CanonicalLibrarySyncPlanner.swift`：libraryMetadata metadata send/apply/no-op/fallback 决策改由 `CanonicalLibraryMetadataModifiedAtPolicy` 执行，保留既有 plan action 与 bridge hint 外部语义。
- `RokuricsShared/SyncCore/CanonicalSyncRuntime.swift`：authority gate 增加 libraryMetadata hash schema 版本检查与 `canonicalLibraryMetadataDecision*` diagnostics。
- `RokuricsShared/SyncCore/CanonicalReadRuntime.swift`：read runtime 增加 `canonicalLibraryMetadataRead*` diagnostics alias，覆盖 canonical served、legacy fallback、equivalent/divergent diff 和 blocked。
- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 `CanonicalLibraryMetadataDomainReadinessScorecard.v852P2_2(...)`，保持 real-device evidence 和 legacy retirement report-only。
- `RokuricsTests/CanonicalLibraryMetadataReadCutoverTests.swift`、`RokuricsMacTests/CanonicalLibrarySyncPlannerTests.swift`：双端 hash contract/resource-token exclusion 与 modifiedAt policy targeted coverage。
- `RokuricsTests/CanonicalSyncRuntimeTests.swift`、`RokuricsTests/CanonicalReadRuntimeTests.swift`、`RokuricsMacTests/CanonicalReadRuntimeTests.swift`、`RokuricsTests/CanonicalSyncKernelCompletionTests.swift`：runtime gate/read diagnostics/domain scorecard regression coverage。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`：记录 v8.52 contract、runtime/readiness、禁区、验证和剩余真机 evidence blocker。

## 2026-06-11 新增/更新 v8.46 Sync Kernel Completion 文件

- `RokuricsShared/SyncCore/CanonicalInventoryRuntime.swift`：runtime report/diagnostics 增加 `mainActorHashAttemptCount`、`mainActorScanAttemptCount`、`metadataLoadDurationMs`，区分真实 attempt 与 blocker，不再依赖 fake zero event。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：iPhone inventory input/manifest build 增加 detached background builder、URL/file IO input loader 与 same-syncRunID runtime build cache；同 tick duplicate snapshot 复用而非重扫。
- `RokuricsMac/StudyLibraryStore.swift`：`applySyncManifest` 增加显式配置的 `manifest.recordings` -> canonical metadata-only existence ledger apply；默认构造仍 disabled/no-op。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：移除 fake zero main-actor telemetry；当前 Mac inventory 仍 `@MainActor`，以真实 blocker count 报告剩余风险。
- `RokuricsTests/CanonicalInventoryRuntimeTests.swift`：新增 iPhone off-main telemetry 与 same-run snapshot reuse coverage。
- `RokuricsMacTests/StudyLibraryStoreTests.swift`：新增 Mac explicit manifest recordings ledger apply 与 default store no-ledger-write coverage。
- `Rokurics/RecordingMetadata.swift`、`Rokurics/StudyFilingModels.swift`、`Rokurics/StudyLibrarySyncModels.swift`、`Rokurics/SecureUploadUtilities.swift`、`Rokurics/RecordingUploadCoordinator.swift`、`Rokurics/RecordingUploadClient.swift`：补充非隔离值类型/纯函数标注，支持 iPhone background inventory builder 在 Swift default MainActor isolation 下编译。
- `docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`：记录 v8.46 code-completion 范围、验证结果和剩余 blocker。

## 2026-06-08 新增/更新 Sync Kernel Finalization 文件

- `Rokurics/StudyLibraryStore.swift`、`RokuricsMac/StudyLibraryStore.swift`：Store 增加 canonical read runtime state、effective read 输出和主开关通知刷新；backing arrays 仍为 legacy。
- `Rokurics/RecordingLibraryView.swift`、`Rokurics/RecordingStudyDetailPage.swift`、`Rokurics/RecordingSessionView.swift`、`Rokurics/IPhoneAIChatView.swift`、`RokuricsMac/MacStudyLibraryView.swift`、`RokuricsMac/MacAIChatView.swift`：主要 Store/UI read 边界改读 effective projection，默认仍 legacy。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：sync tick 把 local/peer inventory 和 upload candidates 提供给 Store canonical read projection；`LocalNetworkSyncAppService` 的 upload coordinator 接同一主开关 provider。
- `Rokurics/RecordingUploadCoordinator.swift`、`Rokurics/RokuricsHomeView.swift`：audio upload canonical runtime owner 接入主开关；真实执行复用 existing secure upload transport/routes，默认仍 legacy。
- `RokuricsShared/SyncCore/CanonicalLegacyCompatibility.swift`：新增 `CanonicalSwitchBackRealisticRootHarness`、`CanonicalKernelSwitchBackProof` 和 realistic test root switch-back result。
- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：新增 completion domain readiness、`unsafe` status 和 realistic-root gate readiness。
- `RokuricsShared/SyncCore/CanonicalAudioUploadRuntimeCommit.swift`：新增 `CanonicalAudioUploadCommitExecutor` alias 和 `CanonicalAudioUploadRuntimeOwner` wrapper。
- `RokuricsTests/CanonicalReadRuntimeTests.swift`、`RokuricsMacTests/CanonicalReadRuntimeTests.swift`：新增 Store effective read path tests。
- `RokuricsTests/CanonicalLegacyCompatibilityTests.swift`、`RokuricsMacTests/CanonicalLegacyCompatibilityTests.swift`：新增 realistic-root switch-back proof tests。
- `RokuricsTests/CanonicalSyncKernelCompletionTests.swift`、`RokuricsMacTests/CanonicalSyncKernelCompletionTests.swift`：新增 completion domain readiness、unsafe status 和 realistic-root gate tests。

## 2026-06-07 新增/更新 v8.45 Completion Gate / Manual Switch 文件

- `RokuricsShared/SyncCore/CanonicalSyncKernelCompletion.swift`：v8.45 completion scorecard、domain ready-to-retire report、redacted evidence package/exporter 和 manual switch gate。2026-06-07 版本是共享纯模型/报告逻辑；2026-06-08 已扩展为同步链路 code-complete scorecard/gate，并由 Store read path、audio upload owner 和 realistic-root switch-back proof 接线，但仍不改默认主开关、不新增 route、不执行 legacy retirement。
- `RokuricsTests/CanonicalSyncKernelCompletionTests.swift`、`RokuricsMacTests/CanonicalSyncKernelCompletionTests.swift`：双端 v8.45 tests，覆盖 domain incomplete 阻断、code complete needs device evidence、manual switch gate backup/switch-back/release-default blocker、evidence redaction、runbook no legacy retirement 和 retirement report-only。
- `docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md`：v8.45 end-to-end manual switch runbook，阶段 0-18，覆盖 backup、oldKernel baseline、diagnosticsOnly、canonicalShadow、canonicalDecisionOnly、canonicalApplyNoAudio、canonicalFullSync、switch-back、paired devices、新录音、metadata-only existence、upload candidate、Mac receive audio、read projection、divergence monitor、stop/rollback 和 audit evidence package。
- `docs/CURRENT_STATE.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/PROJECT_MAP.md`：记录 v8.45 completion gate、scorecard、manual switch gate、runbook、redacted evidence 和 report-only legacy retirement boundary。

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
- `RokuricsShared/`：被 iPhone 与 Mac target 共同编译的共享 SwiftUI 组件和共享模型，当前包含学习库 UI、聊天模型、通用 sync core、Canonical Core、Projection Contract、Sync Planner、Apply Plan、Library Object/Planner、Transfer State Projection、Object Projection、Inventory Builder Contract、Retirement Readiness、离线 Runtime Kernel、Shadow Diagnostics、Real-Data Shadow/Probe、Recording Metadata Cutover 合同、v8 No-Commit app seam 合同、v8.3 recordingMetadata Commit executor 合同、v8.5 root-bound metadata write 合同、v8.6 guarded commit app seam report 合同、v8.7 recordingMetadata canary N=1 合同、v8.9 generated artifact cutover 合同、v8.10 library metadata cutover 合同、v8.11 tombstone/conflict cutover 合同、v8.12 audio upload shadow/canary preparation 合同、v8.13 migration matrix/global guard/libraryMetadata pilot audit 合同、v8.15 libraryMetadata N=1 canary 合同、v8.16 libraryMetadata expanded canary 合同、v8.17 libraryMetadata read-side pilot evidence 合同、v8.19 libraryMetadata guarded read source/gate 合同、v8.20 libraryMetadata observation/retirement report 合同、v8.21 generatedArtifacts read-side/template/next-pilot candidate 合同、v8.22-v8.25 generatedArtifacts active/staged/read-side 合同、v8.26 tombstoneConflict read-side/template/next-pilot candidate 合同、v8.41 audio upload runtime commit 合同、v8.42 canonical read runtime 合同、v8.43 unified kernel switch 合同和 v8.44 legacy compatibility/switch-back proof 合同。
- `RokuricsLiveActivities/`：WidgetKit Live Activity extension 代码。
- `RokuricsLiveActivitiesShared/`：Live Activity attributes，供 iPhone app 与 extension 共用。
- `RokuricsTests/`：iPhone app 单元测试，使用 Swift Testing。
- `RokuricsMacTests/`：Mac app 单元测试，使用 Swift Testing，覆盖接收、安全、转写、笔记、聊天、学习库和同步。
- `RokuricsUITests/`、`RokuricsMacUITests/`：XCTest UI 测试，目前是基础 launch / performance 模板级覆盖。
- `RokuricsVisualDiagnostics/`：视觉诊断截图与 DerivedData 记录，属于诊断资产，不是运行时代码。
- `Scripts/`：辅助脚本和生成图标资产。`embed_whisper_helper.sh` 由 Mac target 构建阶段调用；`export_finder_folder_icons.swift` 生成 Finder 风格文件夹图标。
- `docs/`：项目说明文档，包含常驻上下文、架构/测试/禁区说明、长录音验证计划和连接/上传/同步状态审计。
- `Rokurics.xcodeproj/`：Xcode project。使用 file system synchronized groups；共享 scheme 为 `Rokurics` 与 `RokuricsMac`。

## 2026-06-07 新增/更新 v8.44 Legacy Compatibility 文件

- `RokuricsShared/SyncCore/CanonicalLegacyCompatibility.swift`：v8.44 legacy compatibility matrix、domain/result/blocker 类型，以及纯内存 switch-back/crash harness。覆盖七个域的 legacy-readable/canonical-readable、switch-back no migration、unknown fields、rollback、redacted diagnostics、no physical delete 合同。
- `RokuricsTests/CanonicalLegacyCompatibilityTests.swift`、`RokuricsMacTests/CanonicalLegacyCompatibilityTests.swift`：双端 v8.44 tests，覆盖 compatibility matrix、legacy->canonical/canonical->legacy roundtrip、canonical write -> oldKernel -> legacy modify -> canonical read、partial write rollback、diagnostics 不改格式、oldKernel after canonicalFullSync no crash、crash/restart safety 和 switch-back harness state compare。
- `docs/CURRENT_STATE.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/PROJECT_MAP.md`：记录 v8.44 switch-back contract、compatibility matrix、已证明域、blockers 和 no legacy deletion。

## 2026-06-07 新增/更新 v8.43 Kernel Switch 与 v8.42 Read Runtime 文件

- `RokuricsShared/SyncCore/CanonicalKernelSwitch.swift`：v8.43 unified manual kernel switch。定义主开关 mode/policy/result/blocker、owner state、effective config adapter、migration matrix policy summary、reversibility gate/proof、settings persistence key 和 diagnostics summary。默认 `oldKernel`，release/default 不选 full sync；invalid mixed advanced override 进入 blocked。
- `Rokurics/IPhoneSettingsView.swift`、`RokuricsMac/MacSettingsView.swift`：DEBUG 设置新增 `Debug · 同步内核` 主入口；`canonicalFullSync` 二次确认；切回旧内核立即清 confirmation；既有 `Debug · 学习库迁移试点` 标注为高级专项开关。
- `Rokurics/MacConnectionView.swift`、`Rokurics/StudyLibrarySyncCoordinator.swift`：iPhone sync coordinator/engine 从主开关解析 sync/apply effective config，并在手动 run / engine tick 边界刷新；`LocalNetworkSyncAppService` 的常驻 scheduler engine 使用同一 provider。
- `RokuricsMac/RokuricsMacApp.swift`、`RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`：Mac receiver/server 从主开关注入 sync/apply/existence config；receiver 观察主开关通知并在 server 已启动时重建 server。
- `Rokurics/IPhoneCanonicalReadRuntimeAdapter.swift`、`RokuricsMac/MacCanonicalReadRuntimeAdapter.swift`：read adapter 新增 `fromCanonicalKernelSwitch(...)` factory，read runtime config 来源可统一为主开关。
- `RokuricsTests/CanonicalKernelSwitchTests.swift`、`RokuricsMacTests/CanonicalKernelSwitchTests.swift`：双端 v8.43 tests，覆盖 default oldKernel、owner disabled、diagnostics no side effects、full sync DEBUG/release gate、reversibility、invalid mixed config blocked、fallback retained、shadow compare retained 和 settings persistence。
- `docs/CURRENT_STATE.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/PROJECT_MAP.md`：记录 v8.43 主开关、映射表、可逆性、设置入口、禁区和验证。

- `RokuricsShared/SyncCore/CanonicalReadRuntime.swift`：v8.42 unified canonical read runtime。定义 read runtime config/mode/policy/result、six-domain `CanonicalReadSnapshot` projections、legacy-vs-canonical diff/equivalence/divergence、gate、redacted diagnostics 和 default-off provider。默认 disabled 返回 legacy；guarded canonical read 只允许 explicit debug/internal owner-approved 且 evidence/divergence gate 通过。
- `Rokurics/IPhoneCanonicalReadRuntimeAdapter.swift`：iPhone Store/UI read adapter。围绕 existing manifest/inventory read boundary 构建 sanitized canonical read candidate；默认 legacy；显式 guarded mode 可 serve canonical projection；不触发 sync/upload、不创建 upload job、不写 store、不移动资源。
- `RokuricsMac/MacCanonicalReadRuntimeAdapter.swift`：Mac Store/UI read adapter。围绕 existing manifest/inventory read boundary 构建 sanitized canonical read candidate；默认 legacy；显式 guarded mode 可 serve canonical projection；不改变 `/sync/inventory` response、`receive.json`、audio inbox、pending sync 或 transcription/note generation。
- `RokuricsTests/CanonicalReadRuntimeTests.swift`：iPhone/shared v8.42 tests，覆盖 default legacy、parallel legacy、candidate no-serve、guarded serve with evidence、divergence/unsupported fallback、no side effects、redaction 和 iPhone adapter default/guarded/fallback。
- `RokuricsMacTests/CanonicalReadRuntimeTests.swift`：Mac/shared v8.42 tests，覆盖 default/parallel/candidate/guarded modes、divergence/unsupported/leak-risk fallback、redaction、Mac adapter no receive/inbox mutation 和 no upload job。
- `docs/CURRENT_STATE.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`、`docs/PROJECT_MAP.md`：记录 v8.42 read runtime 的 default-off、gate、fallback、no side effects、redaction 和 validation 边界。

## 2026-06-04 新增/更新 Cutover 文件

- `RokuricsShared/SyncCore/CanonicalLibraryMetadataLanding.swift`：v8.29 libraryMetadata real-device pilot landing wrapper。定义 landing freeze、debug/internal-only N=1 pilot configuration/policy/bootstrap、landing report、recommendation 和 diagnostics 汇总；复用现有 production canary/N1 runner/root-bound apply port，默认 disabled，不启用 release/default/runtime switch。
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataProductionCanary.swift`：v8.29 扩展 production canary injection result，向 landing wrapper 暴露已计算的 N=1 selection 与 candidate safety reports，便于 armed/no-eligible/unsafe candidate 报告在不执行时仍可诊断。
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataCutover.swift`：v8.29 新增 `canonicalLibraryMetadataLanding*` 与 `canonicalMigrationLandingFreezeViolation` diagnostic kind。原 v8.10-v8.20 libraryMetadata cutover/read/observation 合同不变。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：新增 default-disabled `CanonicalLibraryMetadataDebugPilotConfiguration` 与 executor 注入参数；显式配置时走 v8.29 landing bootstrap，默认 app construction 不注入 executor/apply port、不改 UI/read/legacy sync。
- `RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`：新增 default-disabled v8.29 debug pilot config/executor pass-through。Mac inventory context 缺 peer snapshot 时只记录 landing blocked/fallback/report diagnostics，不改 route/security/response。
- `RokuricsTests/CanonicalLibraryMetadataLandingTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataLandingTests.swift`：双端 v8.29 tests，覆盖 default-off config、landing freeze、diagnosticsOnly、armed no-commit、test-root real apply port N=1、production-root default block、read-side divergence、unsafe/resource-move blocker、server peer-snapshot block 和其它 domain static-only。
- `docs/Rokurics_LibraryMetadata_Pilot_Runbook_v8_29.md`：v8.29 manual/internal pilot runbook，记录 preflight、arming/execution、diagnostics、rollback/fallback 和 stop conditions。
- `RokuricsShared/SyncCore/CanonicalTombstoneConflictReadProjection.swift`：v8.26 tombstoneConflict metadata-only read projection、read-side diff、default-off diagnostics config、anti-resurrection template gate、observation window/gate、report-only retirement candidate gate 和 template readiness audit。只记录 tombstone/conflict metadata 摘要、hash prefix 和 redacted risk counts，不包含完整 metadata、完整内容、完整 hash、绝对路径或 delete target path。
- `Rokurics/IPhoneTombstoneConflictReadSideSeam.swift`：iPhone v8.26 default-off tombstoneConflict read-side seam。复用 local/peer `LocalNetworkSyncInventory`、canonical manifest、apply plan 和 library plan facts，输出 diagnostics-only diff result，不删除、不 restore、不清 tombstone、不 resolve conflict、不写 store、不触发 upload/sync/UI。
- `RokuricsMac/MacTombstoneConflictReadSideSeam.swift`：Mac v8.26 default-off tombstoneConflict read-side seam。复用本机/peer inventory 与 canonical facts，输出 diagnostics-only diff result，不改变 `/sync/inventory` response、`receive.json`、audio inbox、route/security 或 Mac pending sync。
- `RokuricsTests/CanonicalTombstoneConflictReadSideTests.swift`、`RokuricsMacTests/CanonicalTombstoneConflictReadSideTests.swift`：双端 v8.26 tests，覆盖 template readiness、matrix next-pilot gate、projection redaction、fatal delete/GC/resurrection/auto-resolution blocker、anti-resurrection、observation/retirement report-only 和 seam no-mutation。
- `RokuricsShared/SyncCore/CanonicalGeneratedArtifactReadProjection.swift`：v8.21 generatedArtifacts metadata-only read projection、read-side diff、default-off diagnostics config、observation window/gate、report-only retirement candidate gate 和 template readiness audit。只记录 availability/hash prefix/byte size/producer/kind 等摘要，不包含正文、完整 hash、真实路径或 audio bytes。
- `Rokurics/IPhoneGeneratedArtifactReadSideSeam.swift`：iPhone v8.21 default-off generatedArtifacts read-side seam。复用 local/peer `LocalNetworkSyncInventory` 与 canonical manifest facts，输出 diagnostics-only diff result，不下载、不 apply、不写 store、不触发 upload/sync/UI。
- `RokuricsMac/MacGeneratedArtifactReadSideSeam.swift`：Mac v8.21 default-off generatedArtifacts read-side seam。复用本机 inventory 与 canonical manifest facts，输出 diagnostics-only diff result，不改变 `/sync/inventory` response 或 route/security。
- `RokuricsTests/CanonicalGeneratedArtifactReadSideTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactReadSideTests.swift`：双端 v8.21 tests，覆盖 content exclusion、unsafe/audio/unsupported blocker、observation/retirement report-only、matrix next-pilot gate 和 seam no-mutation。
- `RokuricsShared/SyncCore/CanonicalGeneratedArtifactGuardedCommit.swift`：v8.22 generatedArtifacts active-pilot guarded commit seam N=0 合同，包含 gate/result/evidence/no-execution/N1-readiness/diagnostics。只评估五类 generated artifact candidate，canary budget 固定 0，不调用 `/sync/artifact-request`、不下载、不 apply、不写、不 commit、不 suppress legacy。
- `RokuricsTests/CanonicalGeneratedArtifactGuardedCommitSeamTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactGuardedCommitSeamTests.swift`：双端 v8.22 tests，覆盖唯一 active pilot matrix、N=0 no-execution、unsupported/content/path/audio/parent-tombstone blocker、iPhone tick diagnostics-only 和 Mac inventory report-only。
- `RokuricsShared/SyncCore/CanonicalGeneratedArtifactCutover.swift` 同文件还包含 v8.23/v8.24 generatedArtifacts canary：`CanonicalGeneratedArtifactN1CanaryRunner`、`CanonicalGeneratedArtifactCanaryStageRunner`、stage policy/evidence/gate/report、N3/N10/allEligible 顺序 gate、多候选首错 rollback 停止、success-only duplicate suppression 和 expanded read-side parallel diagnostics。默认 disabled，只限 `generatedArtifacts`，不切 UI/read path/runtime switch。
- `RokuricsTests/CanonicalGeneratedArtifactCanaryTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactCanaryTests.swift`：双端 v8.23 tests，覆盖 strict N=1 config、single candidate selection、hash/byte/path/route/audio/producer blocker、success-only suppression、rollback/fallback/fatal blocker、iPhone executor injection 和 Mac report-only。
- `RokuricsTests/CanonicalGeneratedArtifactCanaryStageTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactCanaryStageTests.swift`：双端 v8.24 tests，覆盖 staged policy default-off、N1->N3->N10->allEligible 顺序、clean previous-stage evidence、allEligible 显式许可、多候选顺序执行、首错停止、rollback fatal、Mac peer snapshot blocker 和 redacted observation。
- `RokuricsShared/SyncCore/CanonicalRecordingMetadataCutover.swift`：recording metadata 单域 cutover config/gate/result/diagnostics/canary/rollback/fallback/UI parallel projection/retirement readiness 合同。默认 disabled，只支持 `recordingMetadataApply` / `recordingMetadataSend` candidate；v8.7 新增 N=1 selector、N>1 blocker、observation report 和 internal execution flag。
- `RokuricsShared/SyncCore/CanonicalRootBoundMetadataWrite.swift`：v8.5 real root-bound `recordingMetadata` metadata bytes write core，提供 apply port mode、target/root token 校验、atomic replace、rollback checkpoint/restore、postcondition verification、失败分类和 redacted write/rollback result。默认不接 app path。
- `RokuricsShared/SyncCore/CanonicalRecordingMetadataCutover.swift` 同文件还包含 v8 no-commit app seam：`CanonicalCutoverAppSeamConfiguration`、`CanonicalRecordingMetadataNoCommitRunner`、no-commit candidate/equivalence/result/diagnostics。默认 disabled，只允许 `guardedExecuteNoCommit`，不做 production commit 或 duplicate suppression。
- `RokuricsShared/SyncCore/CanonicalRecordingMetadataCutover.swift` 同文件还包含 v8.6 guarded commit app seam：`CanonicalRecordingMetadataGuardedCommitSeam`、guarded context/gate/evidence report/canary policy/readiness/diagnostics。默认 disabled；`N=0` 只记录 report，不执行 commit、不调用 port、不 suppress legacy；v8.7 只允许 iPhone explicit internal N=1 走 runner。
- `Rokurics/IPhoneRecordingMetadataNoCommitExecutor.swift`、`RokuricsMac/MacRecordingMetadataNoCommitExecutor.swift`：双端 no-commit staging executor，只写临时 staging root summary，显式不调用 network/apply/store/upload。
- `Rokurics/IPhoneRecordingMetadataCutoverExecutor.swift`、`RokuricsMac/MacRecordingMetadataCutoverExecutor.swift`：双端 v8.3 recordingMetadata Commit executor。默认 disabled/dry-run port set 会阻断真实 production commit；只有测试或内部显式注入 fake non-dry-run apply/transport port 时，才执行 apply/send、pre/postcondition、rollback 和 side-effect whitelist。
- `Rokurics/IPhoneCanonicalProductionApplyPort.swift`、`RokuricsMac/MacCanonicalProductionApplyPort.swift`：双端 production apply port。默认 disabled，`fakeInMemory` 只写 actor 内存，v8.5 新增显式 `testRootURL` temp/test root-bound metadata write 与默认阻断的 `productionRootURL` 构造。
- `RokuricsTests/CanonicalRecordingMetadataCutoverTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataCutoverTests.swift`：双端 cutover gate、canary、rollback、fallback、duplicate suppression、UI projection 和 retirement readiness 单元测试。
- `RokuricsTests/CanonicalRecordingMetadataCanaryTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataCanaryTests.swift`：双端 v8.7 canary selector/observation 测试，覆盖稳定排序、apply-before-send、unsupported trigger/root-bound blocker、failed candidate 排除和 redacted observation report。
- `RokuricsTests/CanonicalRecordingMetadataProductionExecutionTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataProductionExecutionTests.swift`：双端 migration facade 默认 disabled、fake guarded commit、`/sync/apply-metadata` route projection、kernel send/apply 分流和 non-recordingMetadata blocked 测试。
- `RokuricsTests/CanonicalV8RecordingMetadataNoCommitTests.swift`、`RokuricsMacTests/CanonicalV8RecordingMetadataNoCommitTests.swift`：双端 v8 no-commit gate、staging、equivalence、diagnostics、iPhone tick seam 和 Mac inventory seam 测试。
- `RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataCommitExecutorTests.swift`：双端 v8.3 Commit executor 默认阻断、fake apply/send、canary N=0、rollback/fallback、failure injection、idempotency、duplicate suppression 和 unexpected side-effect blocker 测试。
- `RokuricsTests/CanonicalRecordingMetadataRealApplyPortTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataRealApplyPortTests.swift`：双端 v8.5 real root-bound metadata apply port 测试，覆盖 temp/test root atomic write、rollback、postcondition/checkpoint failure、root escape、redaction、default disabled、production root default-disabled 和 boundary untouched。
- `RokuricsTests/CanonicalRecordingMetadataGuardedCommitSeamTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataGuardedCommitSeamTests.swift`：双端 v8.6/v8.7 guarded commit app seam 测试，覆盖 default-off、evidence complete + canary `N=0` no execution、explicit internal N=1 gate-only/no execution、N>1 blocked、unsafe mode/trigger/evidence blocker、redaction、iPhone tick plan/client unchanged、Mac inventory missing peer snapshot nonfatal/response unchanged。
- `RokuricsShared/SyncCore/CanonicalGeneratedArtifactCutover.swift`：v8.9 generated artifact cutover 合同，覆盖五类 Mac authoritative generated artifact candidate、NoCommit evidence、canary gate、root-bound generated artifact write/rollback、commit/fallback、legacy duplicate suppression 和 read-side diagnostics。默认 disabled，生产 root 默认阻断。
- `Rokurics/IPhoneGeneratedArtifactNoCommitExecutor.swift`、`RokuricsMac/MacGeneratedArtifactNoCommitExecutor.swift`：双端 generated artifact NoCommit executor，只写临时 staging summary，不执行下载、apply、upload 或 duplicate suppression。
- `Rokurics/IPhoneGeneratedArtifactRealApplyPort.swift`、`RokuricsMac/MacGeneratedArtifactRealApplyPort.swift`：双端 generated artifact real apply port。默认 disabled，`testRootURL` 只写临时 root，`productionRootURL` 默认 `productionRootDisabled`。
- `Rokurics/IPhoneGeneratedArtifactCutoverExecutor.swift`、`RokuricsMac/MacGeneratedArtifactCutoverExecutor.swift`：双端 generated artifact Commit executor，默认 disabled port 阻断；测试/内部注入 root-bound port 后才可执行 hash/size verified apply 与 rollback。
- `RokuricsTests/CanonicalGeneratedArtifactCutoverTests.swift`、`RokuricsMacTests/CanonicalGeneratedArtifactCutoverTests.swift`：双端 v8.9 tests，覆盖 default-off/N=0、五类 kind 限定、NoCommit staging-only、root-bound apply/rollback、production root default-disabled、success-only legacy duplicate suppression、fallback/rollback 和 UI read-side diagnostics。
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataCutover.swift`：v8.10 folder/studyItem/standalone note metadata cutover 合同，覆盖 metadata-only candidate、NoCommit evidence、canary stage gate、root-bound metadata write/rollback、commit/fallback、resource move/cycle/conflict blockers、success-only legacy duplicate suppression 和 read-side diagnostics。默认 disabled，生产 root 默认阻断。
- `Rokurics/IPhoneLibraryMetadataNoCommitExecutor.swift`、`RokuricsMac/MacLibraryMetadataNoCommitExecutor.swift`：双端 library metadata NoCommit executor，只写临时 staging summary，不执行 resource move、apply、network 或 duplicate suppression。
- `Rokurics/IPhoneLibraryMetadataRealApplyPort.swift`、`RokuricsMac/MacLibraryMetadataRealApplyPort.swift`：双端 library metadata real apply port。默认 disabled，`testRootURL` 只写临时 root，`productionRootURL` 默认 `productionRootDisabled`。
- `Rokurics/IPhoneLibraryMetadataCutoverExecutor.swift`、`RokuricsMac/MacLibraryMetadataCutoverExecutor.swift`：双端 library metadata Commit executor，默认 disabled port 阻断；测试/内部注入 root-bound port 后才可执行 metadata hash verified apply/send 与 rollback。
- `RokuricsTests/CanonicalLibraryMetadataCutoverTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataCutoverTests.swift`：双端 v8.10 tests，覆盖 default-off/N=0、candidate generation、NoCommit staging-only、root-bound apply/rollback、production root default-disabled、canary stage blocker、resource move/cycle/conflict blocker、success-only duplicate suppression、fallback/rollback 和 UI read-side diagnostics。
- `RokuricsShared/SyncCore/CanonicalAudioUploadCutover.swift`：v8.12 audio upload shadow/canary preparation 合同，覆盖 local/peer/ledger/retry/trigger truth、candidate/evidence/gate、canary stage N=0、NoCommit result、shadow receiver/rehearsal、abort/rollback policy、read-side projection 和 diagnostics。默认 disabled，不调用 production upload runtime。
- `RokuricsShared/SyncCore/CanonicalAudioUploadRuntimeCommit.swift`：v8.41 canonical audio upload runtime commit executor。定义 default-disabled runtime config/mode/policy/result、resumable session/chunk/offset/finalize/abort/retry/job store/resume token、streaming byte source、candidate truth integration、retry replay 和 redacted diagnostics；commit modes 只允许 existing secure upload start/status/chunk/finalize port，不新增 route。
- `Rokurics/IPhoneCanonicalAudioUploadRuntimeAdapter.swift`：iPhone v8.41 canonical secure upload adapter。包装 existing `RecordingUploadClient` / `SecureMacUploadClient` resumable API，复用 TLS/HMAC/pinning/nonce/body hash；只读取 bounded audio chunks，不一次性读完整文件；abort 不新增网络 route。
- `Rokurics/IPhoneCanonicalProductionUploadPort.swift`、`RokuricsMac/MacCanonicalProductionUploadPort.swift`：双端 fake/test upload port 增强 duplicate chunk idempotency 和 wrong-offset failure，用于 canonical runtime tests，不改变 production route。
- `Rokurics/IPhoneAudioUploadNoCommitExecutor.swift`、`RokuricsMac/MacAudioUploadNoCommitExecutor.swift`：双端 audio upload NoCommit executor，只返回 suppressed summary，不创建 upload job、不调用 `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient`、不写 inbox/`receive.json`/ledger/retry。
- `RokuricsTests/CanonicalAudioUploadCutoverPreparationTests.swift`、`RokuricsMacTests/CanonicalAudioUploadCutoverPreparationTests.swift`：双端 v8.12 tests，覆盖 default-off/N=0、peer hash+size no-op、ledger/metadata/receive/UI 非 no-op proof、peer unknown/view refresh/retry/manual 抑制、NoCommit side-effect 全 false、canary N>0 blocked、shadow receiver rehearsal、abort/rollback 和 read-side diagnostics。
- `RokuricsTests/CanonicalAudioUploadRuntimeCommitTests.swift`、`RokuricsMacTests/CanonicalAudioUploadRuntimeCommitTests.swift`：双端 v8.41 runtime commit tests，覆盖 default disabled legacy fallback、metadataOnly candidate、peerUnknown deferred、same hash+size no-op、different conflict、completed ledger rejected、duplicate chunk idempotency、wrong offset failure、finalize hash mismatch、retry resume offset、route allowlist/static Mac postcondition 和 diagnostics redaction。
- `RokuricsShared/SyncCore/CanonicalMigrationMatrix.swift`：v8.13 migration matrix freeze 合同，定义 domain × stage 状态、全局 config guard、libraryMetadata pilot readiness audit、generatedArtifacts v8.21/v8.22/v8.24 matrix helper 和其他域 static-only audit。默认只做诊断/测试，不接 app seam，不开启 release/default cutover、read-side cutover、UI row、upload route 或 legacy retirement。
- `RokuricsShared/SyncCore/CanonicalNoCommitV82.swift`：v8.13 扩展 `CanonicalMigrationStage` 阶段枚举，加入 `notStarted`、`projected`、`planned`、`noCommit`、`realApplyPort`、`commitExecutor`、`appSeamDefaultOff`、`canaryN0`、`canaryN1`、`expandedCanary`、`domainCutover`、`readSideParallel`、`readSideCutover`、`retirementCandidate`、`retired`，供矩阵和 guard 表达迁移顺序。
- `RokuricsTests/CanonicalMigrationMatrixTests.swift`、`RokuricsMacTests/CanonicalMigrationMatrixTests.swift`：双端 v8.13 tests，覆盖 sole active pilot=`libraryMetadata`、其他域 static-only、runtime switch/default cutover/legacy retirement blocker、libraryMetadata readiness、diagnostics redaction 和 app seam default-off。
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataCutover.swift` 同文件还包含 v8.15 N=1 canary：`CanonicalLibraryMetadataCanaryConfiguration` / `Mode`、扩展 canary policy、candidate safety report、observation report、`CanonicalLibraryMetadataN1CanaryRunner` 和 `canonicalLibraryMetadataN1*` diagnostics。默认 disabled，严格 libraryMetadata-only/N=1。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：v8.15 iPhone N=1 seam 接在 legacy diff 后、legacy suppression 前；只有显式 strict N=1 config + 注入 executor 时执行一个 candidate，成功后才返回 cutover result 供 success-only suppression。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：v8.15 Mac inventory seam 因缺 peer snapshot 只记录 N1 peer unavailable/fallback/observation diagnostics，继续返回原 response。
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataCutover.swift` 同文件还包含 v8.16 expanded canary：stage evidence/report、`CanonicalLibraryMetadataCanaryStageRunner`、stage observation report、N3/N10/allEligible gate、首错停止、per-candidate success-only duplicate suppression 和 expanded read-side diagnostics。默认 disabled，只限 `libraryMetadata`。
- `Rokurics/StudyLibrarySyncCoordinator.swift`：v8.16 iPhone expanded stage seam 接在 legacy diff 后、final suppression 前；只有显式 `.canaryCommit` + stagePolicy N3/N10/allEligible + 完整 evidence + 注入 executor 时执行 staged candidates。
- `RokuricsMac/SecureLocalHTTPSServer.swift`：v8.16 Mac inventory seam 因缺 peer snapshot 只记录 stage evaluated/blocked/fallback/observation diagnostics，继续返回原 response。
- `RokuricsTests/CanonicalLibraryMetadataCanaryStageTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataCanaryStageTests.swift`：双端 v8.16 tests，覆盖 default-off、previous-stage evidence、N3/N10/allEligible、确定性选择、首错停止、rollback fatal、per-candidate suppression、Mac peer snapshot blocker 和 redacted observation。
- `RokuricsTests/CanonicalLibraryMetadataCanaryTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataCanaryTests.swift`：双端 v8.15 tests，覆盖 strict N=1 config、single safe commit、N>1/allEligible/runtime switch blocker、resource move blocker、failure rollback/fallback、success-only suppression、Mac fake peer 和 Mac peer-snapshot unavailable。
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataReadProjection.swift`：v8.17 libraryMetadata read-side pilot evidence 合同，包含 metadata-only read projection、parallel diff、default-off read cutover candidate、write-side evidence linkage、legacy fallback policy 和 report-only retirement candidate。排除 standalone note content、真实资源路径和完整 hash。
- `Rokurics/StudyLibrarySyncCoordinator.swift`、`Rokurics/IPhoneLibraryMetadataReadSideSeam.swift`：v8.17 iPhone read-side seam 默认 disabled；显式启用时只记录 legacy/canonical read diff/candidate diagnostics，不改变 plan、read path、UI、sync/upload 或 legacy fallback。
- `RokuricsMac/SecureLocalHTTPSServer.swift`、`RokuricsMac/MacLibraryMetadataReadSideSeam.swift`：v8.17 Mac inventory read-side seam 默认 disabled；显式启用时只记录本地 inventory/canonical read diff/candidate diagnostics，继续返回原 inventory response。
- `RokuricsTests/CanonicalLibraryMetadataReadSideTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataReadSideTests.swift`：双端 v8.17 tests，覆盖 metadata-only projection、content/path redaction、deterministic diff、unsupported/path-leak blocker、write-side evidence linkage、default-off seam、no read path/UI/sync/upload mutation 和 retirement report-only。
- `RokuricsShared/SyncCore/CanonicalLibraryMetadataReadProjection.swift` 同文件还包含 v8.19 guarded read source/gate：`CanonicalLibraryMetadataReadSourceProvider` 默认返回 legacy；explicit internal/test guarded read 且 gate 通过时可返回 canonical metadata-only output；gate/fallback/diagnostics 均不触发 UI、sync/upload、resource move、content write 或 legacy retirement。
- `Rokurics/IPhoneLibraryMetadataReadSideSeam.swift`、`RokuricsMac/MacLibraryMetadataReadSideSeam.swift`：v8.19 新增可选 `readSource(...)` wrapper，默认 unused/legacy，只供 internal/test config 验证 guarded canonical read output。
- `RokuricsTests/CanonicalLibraryMetadataReadCutoverTests.swift`、`RokuricsMacTests/CanonicalLibraryMetadataReadCutoverTests.swift`：双端 v8.19 tests，覆盖 read source mode、gate blockers、canonical served、legacy fallback、metadata-only output、diagnostics redaction、no side effects 和 retirement report-only。

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
  - `IPhoneCanonicalRecordingAdapter.swift`
  - `IPhoneCanonicalLibraryAdapter.swift`
  - `RokuricsShared/SyncCore/CanonicalCore.swift`
  - `RokuricsShared/SyncCore/CanonicalLibraryObject.swift`
  - `RokuricsShared/SyncCore/CanonicalProjectionContract.swift`
  - `RokuricsShared/SyncCore/CanonicalSyncPlanner.swift`
  - `RokuricsShared/SyncCore/CanonicalLibrarySyncPlanner.swift`
  - `RokuricsShared/SyncCore/CanonicalApplyPlan.swift`
  - `RokuricsShared/SyncCore/CanonicalTransferStateMachine.swift`
  - `RokuricsShared/SyncCore/CanonicalObjectProjection.swift`
  - `RokuricsShared/SyncCore/CanonicalInventoryBuilderContract.swift`
  - `RokuricsShared/SyncCore/CanonicalRetirementReadiness.swift`
  - `RokuricsShared/SyncCore/CanonicalFileRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalFileSnapshotRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalManifestRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalChecksumRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalAsyncDiagnosticsWriter.swift`
  - `RokuricsShared/SyncCore/CanonicalMainActorHotPathGuard.swift`
  - `RokuricsShared/SyncCore/CanonicalTransportRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalUploadRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalApplyRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalConflictResolver.swift`
  - `RokuricsShared/SyncCore/CanonicalRuntimeHarness.swift`
  - `RokuricsShared/SyncCore/CanonicalRuntimeReadiness.swift`
  - `RokuricsShared/SyncCore/CanonicalShadowDiagnostics.swift`
  - `RokuricsShared/SyncCore/CanonicalExecutionShadow.swift`
  - `RokuricsShared/SyncCore/CanonicalRootBoundMetadataWrite.swift`
  - `RokuricsShared/SyncCore/CanonicalMigrationMatrix.swift`
  - `RokuricsShared/SyncCore/CanonicalRealDataShadowCopy.swift`
  - `RokuricsShared/SyncCore/CanonicalReadOnlyTransportProbe.swift`
  - `IPhoneRecordingMetadataNoCommitExecutor.swift`
  - `IPhoneRecordingMetadataCutoverExecutor.swift`
  - `IPhoneCanonicalProductionApplyPort.swift`
  - `IPhoneCanonicalFileRuntimeAdapter.swift`
  - `IPhoneCanonicalRealDataShadowCopyAdapter.swift`
  - `IPhoneCanonicalShadowFilePort.swift`
  - `IPhoneCanonicalShadowTransportPort.swift`
  - `IPhoneCanonicalShadowPortFactory.swift`
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
  - `MacCanonicalRecordingAdapter.swift`
  - `MacCanonicalLibraryAdapter.swift`
  - `RokuricsShared/SyncCore/CanonicalCore.swift`
  - `RokuricsShared/SyncCore/CanonicalLibraryObject.swift`
  - `RokuricsShared/SyncCore/CanonicalProjectionContract.swift`
  - `RokuricsShared/SyncCore/CanonicalSyncPlanner.swift`
  - `RokuricsShared/SyncCore/CanonicalLibrarySyncPlanner.swift`
  - `RokuricsShared/SyncCore/CanonicalApplyPlan.swift`
  - `RokuricsShared/SyncCore/CanonicalTransferStateMachine.swift`
  - `RokuricsShared/SyncCore/CanonicalObjectProjection.swift`
  - `RokuricsShared/SyncCore/CanonicalInventoryBuilderContract.swift`
  - `RokuricsShared/SyncCore/CanonicalRetirementReadiness.swift`
  - `RokuricsShared/SyncCore/CanonicalFileRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalFileSnapshotRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalManifestRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalChecksumRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalAsyncDiagnosticsWriter.swift`
  - `RokuricsShared/SyncCore/CanonicalMainActorHotPathGuard.swift`
  - `RokuricsShared/SyncCore/CanonicalTransportRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalUploadRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalApplyRuntime.swift`
  - `RokuricsShared/SyncCore/CanonicalConflictResolver.swift`
  - `RokuricsShared/SyncCore/CanonicalRuntimeHarness.swift`
  - `RokuricsShared/SyncCore/CanonicalRuntimeReadiness.swift`
  - `RokuricsShared/SyncCore/CanonicalShadowDiagnostics.swift`
  - `RokuricsShared/SyncCore/CanonicalExecutionShadow.swift`
  - `RokuricsShared/SyncCore/CanonicalMigrationMatrix.swift`
  - `RokuricsShared/SyncCore/CanonicalRealDataShadowCopy.swift`
  - `RokuricsShared/SyncCore/CanonicalReadOnlyTransportProbe.swift`
  - `MacRecordingMetadataNoCommitExecutor.swift`
  - `MacRecordingMetadataCutoverExecutor.swift`
  - `MacCanonicalFileRuntimeAdapter.swift`
  - `MacCanonicalRealDataShadowCopyAdapter.swift`
  - `MacCanonicalShadowFilePort.swift`
  - `MacCanonicalShadowTransportPort.swift`
  - `MacCanonicalShadowPortFactory.swift`
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
- `RokuricsTests/CanonicalCoreTests.swift`
  - iPhone adapter 到 `CanonicalManifest` 的只读投影、metadataHash 业务字段合同、createdAt/duration/processing/audio facts 排除、restore stale deletedAt、audio no-op/conflict 语义、generated artifact path token sanitization 和 iPhone downloaded artifact non-authoritative 投影。
- `RokuricsTests/CanonicalShadowDiagnosticsTests.swift`
  - iPhone shadow report 的 legacy input 不变性、hash prefix redaction、metadata converged/diverged、createdAt ignored、processing ignored、same/unknown/conflict audio category 和 generated artifact shadow category/redaction。
- `RokuricsTests/CanonicalSyncPlannerTests.swift`
  - iPhone inventory optional `canonicalManifest` 兼容、canonical metadata plan、business modifiedAt diagnostics、createdAt ignored diagnostics、audio bootstrap/no-op/defer/conflict、generated artifact download/no-op/defer、view refresh/retry drainer 抑制和 legacy fallback。
- `RokuricsTests/CanonicalApplyPlanTests.swift`
  - iPhone target 下验证 shared canonical apply plan：recording metadata apply/send、generated artifact request/apply bridge hint、conflict redaction、object/artifact tombstone soft-delete/no-physical-delete policy、anti-resurrection、audio conflict no apply、dedupe。
- `RokuricsTests/CanonicalLibraryObjectTests.swift`
  - iPhone library adapter 与 shared library object model：folders、study items、standalone notes、tombstones、metadata hash、old manifest decode 和 path/content redaction。
- `RokuricsTests/CanonicalLibrarySyncPlannerTests.swift`
  - shared library planner：folder/study item no-op/apply/send/conflict/tombstone、view refresh/retry drainer suppression 和 unsupported fallback。
- `RokuricsTests/CanonicalTransferStateTests.swift`
  - legacy transfer/upload 状态到 canonical transfer phase 的只读投影；不修改 queue。
- `RokuricsTests/CanonicalObjectProjectionTests.swift`
  - read-only ObjectProjection：recording/generated artifact/folder/study item display facts、deleted/conflict state 和 audio truth 边界。
- `RokuricsTests/CanonicalInventoryCoverageTests.swift`
  - inventory builder coverage 与 retirement readiness gate；确认 readiness 只诊断不删除/禁用 legacy。
- `RokuricsTests/CanonicalRuntimeKernelTests.swift`
  - iPhone target 下验证离线 canonical runtime：root-bound file store、hash/size/no-overwrite/tombstone、transport route/capability/body hash/idempotency、resumable upload、apply executor、conflict resolver、two-node in-memory harness 和 runtime readiness gate。
- `RokuricsTests/CanonicalExecutionShadowTests.swift`
  - iPhone target 下验证 execution shadow preparation：shadow root 写入边界、production root 拒绝、read-only transport projection、upload/apply/rollback rehearsal、production execute blocked 和 redacted diagnostics。
- `RokuricsTests/CanonicalRealDataShadowCopyTests.swift`
  - iPhone target 下验证 real-data shadow copy：只写 shadow root、metadata/descriptor evidence、production root/unsafe path/source equality/hash/size guard、cleanup/refuse production root 和 diagnostics redaction。
- `RokuricsTests/CanonicalReadOnlyTransportProbeTests.swift`
  - iPhone target 下验证 read-only probe：默认 disabled、network suppressed、mutating route rejected、manifestHash non-auth 和 signed shadow request projection。
- `RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests.swift`
  - iPhone target 下验证 v8.3 recordingMetadata Commit executor 默认阻断真实 commit、fake apply/send、既有 `/sync/apply-metadata` route projection、rollback/fallback、failure injection、idempotency、duplicate suppression 和 unexpected side-effect blocker。
- `RokuricsMacTests/`
  - `CanonicalCoreTests.swift`：Mac adapter join receive/study/artifact facts、`receivedAt`/processing `updatedAt` 不影响 metadataHash/modifiedAt、inbox fallback `updatedAt` 被拒绝、业务 study item edit 使用业务时钟、receive record 不能单独证明 audio、Mac generated artifact authoritative producer 投影。
  - `CanonicalShadowDiagnosticsTests.swift`：Mac shadow report 的 study-only、receive-only、Mac processing clock rejected、peer audio conflict 和 inventory response 不变性。
  - `CanonicalSyncPlannerTests.swift`：Mac inventory optional `canonicalManifest` 兼容、canonical metadata plan、business modifiedAt diagnostics、createdAt ignored diagnostics、audio bootstrap/no-op/defer/conflict、generated artifact download/no-op 和 legacy fallback。
  - `CanonicalApplyPlanTests.swift`：Mac target 下验证 shared canonical apply/conflict/tombstone 模型与 iPhone target 同等语义；不触发 Mac route、文件写入或物理删除。
  - `CanonicalLibraryObjectTests.swift`：Mac library adapter 到 canonical folders/study items/standalone notes/tombstones 的只读投影和 redaction。
  - `CanonicalLibrarySyncPlannerTests.swift`：Mac target 下验证 shared library planner 与 metadata manifest bridge 语义。
  - `CanonicalTransferStateTests.swift`：Mac target 下验证 transfer state projection 不改 retry/upload queue。
  - `CanonicalObjectProjectionTests.swift`：Mac target 下验证 ObjectProjection 只读显示状态，不驱动 UI/sync/upload。
  - `CanonicalInventoryCoverageTests.swift`：Mac target 下验证 inventory coverage/readiness diagnostics。
  - `CanonicalRuntimeKernelTests.swift`：Mac target 下验证同一套离线 canonical runtime kernel，不触发真实 Network.framework route、Mac receiver、真实文件 store、UI 或生产 tick。
  - `CanonicalExecutionShadowTests.swift`：Mac target 下验证 execution shadow file/transport/upload/apply/rollback rehearsal 不触发真实 receiver、`receive.json`、Network.framework route、真实 store 或 production execute。
  - `CanonicalRealDataShadowCopyTests.swift`：Mac target 下验证 receive/inbox/generated artifact evidence 只写 shadow root、audio descriptor-only、production root guard 和 cleanup guard。
  - `CanonicalReadOnlyTransportProbeTests.swift`：Mac target 下验证 read-only probe 默认 disabled、artifact request bounded allow、mutating upload route rejected、auth boundary preserved 和 network suppressed。
  - `CanonicalRecordingMetadataCommitExecutorTests.swift`：Mac target 下验证 v8.3 recordingMetadata Commit executor 与 iPhone target 同等语义；不触发真实 receiver、`applySyncManifest`、Network.framework route、真实 store 或 production execute。
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
