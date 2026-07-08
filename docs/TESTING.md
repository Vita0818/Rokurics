# TESTING

最近自查日期：2026-07-08

## 2026-07-08 Rokurics v10.0 / Mac 首页与共享录音实时转写验证

本轮验证重点：

- 工作区只保留 v10.0 A 范围：Mac 首页、Mac 本地录音、共享录音 surface、共享模拟实时转写、Mac 麦克风权限和 Mac inbox checksum helper。
- 已恢复 no-legacy fallback / canonical runtime / 设置页 Debug Sync Kernel 删除 / 测试 source regression 到 v9.24；后续验证不得再使用这些已撤回改动作为当前证据。
- Mac 首页默认入口应为 `MacHomeView`，侧边栏包含首页，点击录音 orb 进入 `MacRecordingSessionView`。
- Mac 录音保存应复用 `MacRecordingFileStore` 的 metadata-first inbox path，不新增 route 或反向连接。
- iPhone/Mac 录音界面应复用 `RokuricsSharedRecordingSessionSurface`，实时转写文本来自 `RokuricsSimulatedLiveTranscriptionSession`，不是实际 ASR provider。

建议验证命令：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v100-A-mac build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/RokuricsDerivedData-v100-A-ios build
git diff --check
git status --short
```

本轮实际验证结果：`git diff --check` 通过；Mac `RokuricsMac` Debug build 通过；iPhone `Rokurics` generic iOS Simulator Debug build 通过。两个 build 仍输出既有 Swift 6 actor isolation / deprecation warnings，未发现 v10 A 引入的编译错误。

验证结论必须区分：build 通过只能证明本地编译兼容；未进行真机 Mac 麦克风录音、未接入真实 OpenAI/FunASR streaming provider、未做 paired-device 同步验证时，不得声明真实 ASR 或真机同步链路通过。

## 2026-06-18 Canonical v9.17 / Real Path State Fix 验证

本轮验证重点：

- ObjectID：所有录音音频 upload/transfer/finalize proof/status fact/UI display cache 使用 `recordingAudio:<recordingID>`；裸 `recordingID` 只能作为 existing upload route 参数。
- Upload UI bridge：StatusTruth projection 通过 `StudyLibrarySyncCoordinator`/`StudyLibraryStore` 回灌 `RecordingUploadCoordinator.displaySyncStateByObjectID`；finalizeProof completed 可见，metadataOnly/partialReceive/completedLedgerOnly 不 completed。
- Upload button no-op：mac not paired、metadata/local audio missing、active upload、transfer/ledger in-flight、retry pending、trigger cannot create upload、peerUnknown deferred、production port unavailable、canonical blocked/conflict 都必须有 visible display/progress diagnostic，且不得绕过 canCreateUploadJob。
- Mac manual sync pending：点击立即同步后 `DeviceConnectionStatusStore`/`SecureReceiverService` 发布 pending；duplicate、heartbeat consumed、inventory observed、timeout/stale 可见；Mac 不新增反向连接。
- R1/R2/R4/R5：diagnostics hot path、content-stable cache、UI EffectiveStatus read 和 status exchange carrier 不回退。

目标验证命令：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v917-iPhone test -only-testing:RokuricsTests/CanonicalStatusTruthRuntimeTests -only-testing:RokuricsTests/RokuricsTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v917-Mac test -only-testing:RokuricsMacTests/RokuricsMacTests
rg "CanonicalObjectID\(.*metadata\.id|CanonicalObjectID\(.*recordingID|CanonicalObjectID\(.*job\.recordingID|CanonicalObjectID\(.*finalizeRequest\.recordingID" Rokurics RokuricsMac RokuricsShared
rg "recordingAudio:" Rokurics RokuricsMac RokuricsShared
rg "displaySyncStateByObjectID|canonicalDisplaySyncState|refreshDisplaySnapshot|effectiveSyncStatusByObjectID|produceCanonicalStatusFact|applyCanonicalStatusProjection|bridgeCanonicalStatusProjections" Rokurics/RecordingUploadCoordinator.swift Rokurics/StudyLibrarySyncCoordinator.swift Rokurics/StudyLibraryStore.swift
rg "prepareManualStudyLibrarySync|recordPendingSyncRequest|consumePendingSyncStartSignal|recordPendingSyncInventoryObserved|statusesByDeviceID|@Published|objectWillChange|presenceObservationRevision|manualSyncStatusRevision" RokuricsMac
rg "URLSession|NWConnection|connect\(" RokuricsMac
rg "loadEntries|write\(to:.*atomic" Rokurics/ConnectionSyncStateStores.swift
rg "generatedAt|Date\(" Rokurics/StudyLibraryStore.swift RokuricsMac/StudyLibraryStore.swift
git status --porcelain --untracked-files=all | rg "CanonicalFourDomain|Evidence|CompletionGate|FinalScorecard|RealDeviceTrialGate|RuntimeHarness|FakeConnection|FakeTransfer|FakeFile" || true
git diff --check
git status --short
```

说明：上述结果仍是 local code/test evidence。缺 paired-device redacted jsonl 时，`realDeviceEvidencePresent=false`。

## 2026-06-16 Canonical v9.13 / Post-audit Real Wiring 验证口径

v9.10 post-audit found R4/R6/R3 evidence incomplete. v9.10/v9.12 gate、harness、scorecard 与本地 targeted tests 不能单独解释为可发布、真机已通过、可退休 legacy 或 canonical 内核完成。

v9.13 closes code-level R4/R6/R3 only if tests/grep pass. 必须同时验证 UI final display 追溯到 cached `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` snapshot、R6 只有 allowed `canonicalFullSync` 能 commit transfer、fake/test-only port 不进入 production fullSync、R3 hot path 无 reconciliation/diagnostics sync write/manifest/hash/upload job/retry drain。

`realDeviceEvidencePresent=false`。没有 paired iPhone/Mac redacted jsonl 时，所有命令结果都只能作为 local code/test evidence。

## 2026-06-16 Canonical v9.12 / Post-v9.10 Audit Closure B 验证

本轮新增/更新验证重点：

- R6 Connection owner：真实 app path 引用 `CanonicalConnectionRuntime`，heartbeat/liveness/syncRequested/status exchange 走 existing `/device/status` 与 `/connection/heartbeat` carrier；Mac no reverse connection；heartbeat callback enqueue-only。
- R6 Transfer owner：`RecordingUploadCoordinator` 在 allowed `canonicalFullSync` 进入 `CanonicalTransferRuntime`；adapter 仍走 `IPhoneCanonicalSecureAudioUploadPort` / `SecureMacUploadClient` / existing upload routes；wrong offset 后 status refresh/resume；finalize proof 写入 StatusTruth。
- fake/test-only upload port：旧 in-memory ledger 改为 `testOnly` 命名；production fullSync selected test-only upload port 时 gate unsafe，不得 READY。
- R7 final gate：`CanonicalFourDomainGateEvidence`/trial gate 逐项检查 Connection、Transfer、Sync、File 与 cross-domain evidence；R4/R6/R7 缺失不得 READY；route/security/RequestVerifier/default canonical/diagnostics leak/MainActor hot path/proof violation/test-only upload port selected 均 unsafe。
- Harness：deterministic two-node harness 覆盖 metadataOnly -> upload/finalize/proof/status exchange/completed、peerUnknown deferred、completed ledger rejected、partial receive rejected、existing different audio no-overwrite、generated artifact status delta no provider rerun、cache hit skips hash、diagnostics storm async/backpressure、status exchange duplicate/stale/conflict、完整 mode sequence。

本轮目标验证命令：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v912-iPhone test -only-testing:RokuricsTests/CanonicalTransferKernelRuntimeTests -only-testing:RokuricsTests/CanonicalFourDomainRuntimeHarnessTests -only-testing:RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v912-Mac test -only-testing:RokuricsMacTests/CanonicalTransferKernelRuntimeTests -only-testing:RokuricsMacTests/CanonicalFourDomainRuntimeHarnessTests -only-testing:RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests
rg "CanonicalConnectionRuntime|CanonicalConnectionEnvelope|CanonicalConnectionCarrier|CanonicalPeerLiveness" Rokurics RokuricsMac
rg "CanonicalTransferRuntime|CanonicalTransferSession|CanonicalTransferFinalizeProof|CanonicalTransferRetryRuntime" Rokurics RokuricsMac
rg "fakeLedger|fake ledger|simulated|testOnly" Rokurics RokuricsMac RokuricsShared
rg "SecureMacUploadClient|RecordingUploadClient|RequestVerifier|upload-recording-audio-session" Rokurics RokuricsMac
rg "connect\\(|URLSession|NWConnection|startConnection" RokuricsMac
rg "EffectiveSyncStatus|CanonicalEffectiveSyncStatus|effectiveSyncStatus|displayState" Rokurics RokuricsMac
rg "uploadLedger\\.completed|receiveRecord|metadataOnly|localFileExists|audioAvailable|partialReceive|completedLedger" Rokurics/RecordingLibraryView.swift Rokurics/RecordingStatusView.swift Rokurics/RecordingStudyDetailPage.swift RokuricsMac/MacStudyLibraryView.swift RokuricsMac/MacAudioInboxView.swift RokuricsMac/MacReceiverStatusCard.swift
rg "loadEntries|write\\(to:.*atomic|generatedAt" Rokurics/ConnectionSyncStateStores.swift Rokurics/StudyLibraryStore.swift RokuricsMac/StudyLibraryStore.swift
git diff --check
git status --short
```

说明：这些命令仍是 local code/test evidence。缺 paired iPhone/Mac redacted jsonl 时，`realDeviceEvidencePresent=false`，不得声明真机已通过。

## 2026-06-16 Canonical v9.11 / R4 UI EffectiveStatus + R3 No-Freeze Proof 验证

本轮新增/更新验证重点：

- Store/snapshot：双端 `StudyLibraryStore`、iPhone `RecordingUploadCoordinator`、Mac `SecureReceiverService` 暴露只读 effective/display snapshot；getter 只读缓存，不触发 status reconciliation、upload job、retry drain、sync/network/file IO。
- UI/status model：metadataOnly、metadataOnlyLedger、receiveRecordOnly、completed ledger alone、partialReceive、local file exists only、peerUnknown、existingDifferentAudio 等状态通过 `CanonicalEffectiveSyncStatus` / `CanonicalDisplaySyncState` projection 显示，不能在 View 层拼 completed/peerVerified/audioAvailable。
- Proof rule：finalizeProof 与 peerInventoryHashSizeMatch 可显示 peerVerified/completed；metadataOnly 不显示 completed/audioAvailable；completed ledger alone 不显示 peerVerified；partialReceive 不显示 completed；existingDifferentAudio 显示 conflict/no-overwrite。
- View refresh：refresh/re-render 不创建 upload job、不触发 retry drain、不触发 fact reconciliation、不触发 diagnostics sync write。
- R3 no-freeze：`CanonicalMainActorHotPathGuard` 覆盖 diagnosticsWrite、fileTreeSnapshot、manifestBuild、fullHash、readProjectionRebuild、statusTruthReconciliation、effectiveStatusProjection。
- R1/R2 防回退：diagnostics record hot path 不回退到 loadEntries/atomic full rewrite/await file IO；canonical effective read cache key 不以 generatedAt/Date 为 identity 主因。
- Gate：缺 R4 不得 READY；View direct completed ledger proof violation 必须 unsafe/not-ready；MainActor status reconciliation attempt > 0 必须 unsafe/not-ready；R1/R2/R5 green 但 R4 missing 不得 READY。

本轮实际验证命令：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v911-iPhone test -only-testing:RokuricsTests/CanonicalEffectiveStatusUIProjectionTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v911-iPhone test -only-testing:RokuricsTests/CanonicalFileKernelRuntimeTests -only-testing:RokuricsTests/CanonicalReadRuntimeTests -only-testing:RokuricsTests/CanonicalStatusTruthRuntimeTests -only-testing:RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v911-Mac test -only-testing:RokuricsMacTests/CanonicalEffectiveStatusUIProjectionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v911-Mac test -only-testing:RokuricsMacTests/CanonicalFileKernelRuntimeTests -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests -only-testing:RokuricsMacTests/CanonicalStatusTruthRuntimeTests -only-testing:RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests
rg "EffectiveSyncStatus|CanonicalEffectiveSyncStatus|effectiveSyncStatus|CanonicalDisplaySyncState|displayState" Rokurics RokuricsMac
rg "uploadLedger\\.completed|receiveRecord|metadataOnly|localFileExists|audioAvailable|partialReceive|completedLedger" Rokurics/RecordingLibraryView.swift Rokurics/RecordingStatusView.swift Rokurics/RecordingStudyDetailPage.swift RokuricsMac/MacStudyLibraryView.swift RokuricsMac/MacAudioInboxView.swift RokuricsMac/MacReceiverStatusCard.swift
rg "loadEntries|write\\(to:.*atomic|Data\\(" Rokurics/ConnectionSyncStateStores.swift
rg "generatedAt|Date\\(" Rokurics/StudyLibraryStore.swift RokuricsMac/StudyLibraryStore.swift
rg "ownerApprovedCanonicalTransfer\\s*=\\s*true|CanonicalTransferRuntime" Rokurics RokuricsMac
git diff --check
git status --short
```

本轮实际结果：iPhone UI/status projection tests 通过；iPhone FileKernel/ReadRuntime/StatusTruth/Gate targeted tests 通过；Mac UI/status projection tests 通过；Mac FileKernel/ReadRuntime/StatusTruth/Gate targeted tests 通过。Mac `platform=macOS` 仍有 arm64/x86_64 多 destination warning，且 app test host 会按现有 scheme 启动 receiver 并打印既有 HTTPS 日志；这不是本轮新增 route。仍未运行完整全量 suite，未产生 paired iPhone/Mac redacted jsonl，不得声明真机 no-freeze、真机状态收敛、canonical kernel complete 或 R6 完成。

## 2026-06-15 Canonical v9.10 / Real-Device Trial Gate, Evidence Package, Cleanup, No-Retirement Lock 验证

本轮新增/更新验证重点：

- Gate：`CanonicalFourDomainRealDeviceTrialGate.v910(...)` 输出 `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_TRY_ON_DEVICE`。
- READY：v9.5-v9.9 code-level evidence 全绿、build/test summary present、redacted evidence package、cleanup audit clean、no-retirement lock closed；`realDeviceEvidencePresent=false` 仍可 READY。
- PARTIAL：缺一个非安全四域证据，例如 Connection/Transfer/Sync/File domain missing 或 v9.9 harness missing。
- NOT_READY：build/test summary missing 或 failed。
- UNSAFE：release/default canonical、route/security bypass、RequestVerifier bypass、missing legacy fallback、upload route schema change、metadataOnly/completed ledger/partial receive treated as peer proof、existing different audio overwrite、UI refresh upload job、diagnostics leak、MainActor hot path violation、oldKernel switch-back failure、Mac reverse connection、heartbeat heavy sync、retry storm guard missing 或 no-retirement lock broken。
- Evidence redaction：`CanonicalFourDomainEvidenceRedaction` 必须阻断 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio、full transcript/note/summary/provider response 和 full generated content。
- No-retirement lock：`legacyDeleted=false`、`legacyDisabled=false`、`retirementExecutionPerformed=false`、`readyToRetireLegacyReportOnly=false`；release/default oldKernel；`canonicalFullSync` 只允许 debug/internal + owner + manual + all gates。
- Cleanup：v9.10 新增类型是 report-only scorecard/evidence/gate，不是 runtime facade；没有 app runtime 引用的 v9 fake harness 类型必须是 test-only。

本轮目标验证命令：

```sh
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v910-iPhone test -only-testing:RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v910-Mac test -only-testing:RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests
rg "CanonicalFourDomain.*Facade|v9.*Facade|Facade.*v9" RokuricsShared/SyncCore Rokurics RokuricsMac
git diff --check
git status --short
```

本轮实际结果：`xcodebuild -list -project Rokurics.xcodeproj` 通过，schemes 包含 `Rokurics` 与 `RokuricsMac`。iPhone `RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests` 在 `iPhone 17, OS 26.5` simulator 上通过 6 个 Swift Testing 用例。Mac `RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests` 在 `platform=macOS`、`-parallel-testing-enabled NO` 下通过 6 个 Swift Testing 用例；macOS destination 仍有 arm64/x86_64 多匹配 warning，且 Mac test host 会按现有 scheme 启动 app/receiver 并打印既有日志。`rg "CanonicalFourDomain.*Facade|v9.*Facade|Facade.*v9" RokuricsShared/SyncCore Rokurics RokuricsMac` 无命中。`git diff --check` 通过。上述验证仍是 local build/test evidence；未产生 paired iPhone/Mac redacted jsonl，不得声明真机 no-freeze、状态收敛、文件不卡顿、canonical kernel 完成或 legacy retirement。

## 2026-06-15 Canonical v9.9 / Four-Domain Gate and Deterministic Harness 验证

本轮新增/更新验证重点：

- Gate：`CanonicalFourDomainCompletionGate.v990(...)` 检查 v9.5 diagnostics hot path async、content-stable cache key、status truth off-main projection；v9.6 UI effective status source cutover；v9.7 realtime exchange runtime；v9.8 connection/transfer owner wiring；default/release oldKernel、legacy fallback、route/security/upload schema、`RequestVerifier`、Mac no reverse connection、heartbeat no heavy sync、view refresh no upload job、retry storm guard、diagnostics redaction 和 oldKernel switch-back proof。
- Gate 四态：v9.5-v9.8 code-level evidence 全绿时 `READY`；缺一个非安全域时 `PARTIAL`；route/security/default canonical/peer proof/MainActor/no-freeze/reverse connection/heartbeat heavy sync/view refresh job/retry storm/diagnostics leak/switch-back failure 返回 `UNSAFE`。
- Harness：`CanonicalFourDomainRuntimeHarness` 使用 fake clock/fake sequence/fake carrier/fake transfer/fake file runtime，覆盖 10 个 required scenarios。Harness 不等于真机 evidence。
- No-freeze assertions：diagnosticsWrite/fileTree/manifest/hash/statusReconcile hot path attempt count 均为 0；cache hit skips hash；diagnostics writer async queue used；repeated UI read no rebuild。
- Proof assertions：every displayed completed state cites finalizeProof or peerInventoryHashSizeMatch；metadataOnly/completedLedger/partialReceive rejection diagnostics produced；status exchange ack alone cannot make completed。
- Safety boundary：不新增 route、不改 upload route schema、不绕过 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash、不让 Mac 主动连接 iPhone、不写 production root、不执行真实网络、不退休 legacy。

本轮实际验证命令：

```sh
pwd
git rev-parse --show-toplevel
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcrun simctl list devices available
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v990-iPhone test -only-testing:RokuricsTests/CanonicalFourDomainRuntimeHarnessTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v990-Mac test -only-testing:RokuricsMacTests/CanonicalFourDomainRuntimeHarnessTests
```

本轮实际结果：路径检查通过，`pwd` 与 Git root 均为 `/Users/vita/Vitemis/Vela/Rokurics`。`xcodebuild -list` 通过，schemes 包含 `Rokurics` 与 `RokuricsMac`。`xcrun simctl list devices available` 显示可用 `iPhone 17, OS 26.5`。iPhone targeted tests 通过 `CanonicalFourDomainRuntimeHarnessTests` 3 个 Swift Testing 用例；Mac targeted tests 在 `-parallel-testing-enabled NO` 下通过同名 3 个 Swift Testing 用例。Mac destination 仍有 arm64/x86_64 多匹配 warning，且 Mac test host 会按现有 scheme 启动 app/receiver 并打印既有日志；新增 fake harness 自身不调用真实网络、不新增 route、不写 production root。

收尾仍需运行：

```sh
rg "CanonicalFourDomain" RokuricsShared/SyncCore RokuricsTests RokuricsMacTests docs
git diff --check
git status --short
```

说明：这些命令只证明本地代码级 four-domain gate 与 fake deterministic harness。仍未运行完整全量 test suite，未产生 paired iPhone/Mac redacted jsonl，不得声明真机 no-freeze、状态收敛、文件不卡顿或 canonical kernel 完成。

## 2026-06-15 Canonical v9.8 / Connection and Transfer Runtime Owner Wiring 验证

本轮新增/更新验证重点：

- Switch mapping：`oldKernel` 下 connection/transfer owner disabled；shadow/diagnostics no transfer commit；decisionOnly no commit；applyNoAudio audio transfer blocked；blocked 回 legacy；fullSync 缺 owner/manual/debug/fallback/domain/runtime readiness 时 blocked。
- Connection owner：`CanonicalConnectionRuntime` owns peer liveness、heartbeat envelope、status request、syncRequested envelope；heartbeat callback 只 enqueue；Mac 不反连 iPhone；carrier 仍走 existing heartbeat/status path。
- Transfer owner：`CanonicalTransferRuntime` owns session start/status/chunk/finalize、confirmedBytes monotonic、resume/status refresh、retry/backoff、idempotency 和 finalize proof；production port 未启用时 fail closed，不把 fake ledger 当 READY。
- Adapter boundary：iPhone fullSync allowed 时 `RecordingUploadCoordinator` 进入 canonical transfer runtime，但真实上传仍走 `IPhoneCanonicalTransferAdapter` -> `IPhoneCanonicalSecureAudioUploadPort` -> `SecureMacUploadClient` -> existing Mac upload routes。
- Mac route/security：route list unchanged；`RequestVerifier` 仍在 heartbeat/status/upload route path；Mac finalize route 只在 verified completed + checksum/byteSize 匹配后把 receiver accepted proof 写入 status truth runtime。
- Proof boundary：finalize proof 可以推进 v9.4 truth engine；metadataOnly、completed ledger alone、receive record alone、partial receive 不 completed；existing different audio conflict/no-overwrite。
- Job boundary：view refresh no fresh job；retry drainer existing eligible only。
- App path evidence：`rg "CanonicalTransferRuntime"` 必须显示 `RecordingUploadCoordinator` 或真实 adapter 引用，而不只是 SyncCore/tests。

本轮实际验证命令：

```sh
pwd
git rev-parse --show-toplevel
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalTransferKernelRuntimeTests -only-testing:RokuricsTests/CanonicalStatusExchangeRuntimeTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalTransferKernelRuntimeTests -only-testing:RokuricsMacTests/CanonicalStatusExchangeRuntimeTests -quiet
```

本轮实际结果：路径检查通过，`pwd` 与 Git root 均为 `/Users/vita/Vitemis/Vela/Rokurics`。`xcodebuild -list` 通过，schemes 包含 `Rokurics` 和 `RokuricsMac`。iPhone targeted tests 通过 `CanonicalTransferKernelRuntimeTests` 与 `CanonicalStatusExchangeRuntimeTests`。Mac targeted tests 通过 `CanonicalTransferKernelRuntimeTests` 与 `CanonicalStatusExchangeRuntimeTests`；本机 macOS destination 仍有 arm64/x86_64 多匹配 warning，但默认 My Mac 运行成功。

本轮收尾仍需随最终报告记录：

```sh
rg "CanonicalTransferRuntime" Rokurics RokuricsMac RokuricsShared/SyncCore RokuricsTests RokuricsMacTests
git diff --check
git status --short
```

说明：这些命令只证明本地代码级 owner wiring 与 targeted 防回归。仍未运行完整全量 test suite，未产生 paired iPhone/Mac redacted jsonl，不得声明真机传输/收敛验证完成或 canonical kernel 完成。

## 2026-06-14 Canonical v9.7 / Realtime Status Exchange Runtime Wiring 验证

本轮新增/更新验证重点：

- Runtime flow：`CanonicalStatusExchangeRuntime` 从 v9.4 fact store snapshot 生成 delta，incoming delta merge 回 `CanonicalStatusTruthRuntime`，sequence monotonic、duplicate idempotent、stale reject deterministic。
- Carrier wiring：iPhone `/device/status`、`/connection/heartbeat`、`/sync/inventory` request 可携带 optional envelope；Mac 对应 heartbeat/status response 和 inventory response 可返回 optional envelope；upload routes 不承载 status exchange。
- Old peer compatibility：missing optional envelope、missing ack disposition、missing request kind decode safe。
- Proof boundary：finalizeProof delta 可以推进 truth engine 到 completed；metadataOnly delta 不标记 audio complete；ack alone 不作为 peer proof；低证明 fact 不覆盖高证明 finalize proof。
- Request boundary：`runSyncSoon` 只返回 enqueue action；`sendAudioProof` 只返回 lightweight proof action，不创建 fresh upload job，不 inline heavy sync。
- Safety boundary：route list unchanged，`RequestVerifier` 仍在 Mac route path；default/release oldKernel、legacy fallback、TLS/HMAC/pinning/nonce/body hash、Mac no reverse connection 保持。
- App path evidence：`rg "CanonicalStatusExchangeRuntime|CanonicalStatusExchangeEnvelope"` 必须显示 `Rokurics/`、`RokuricsMac/` 和 `RokuricsShared/SyncCore/` 引用，而不只是 SyncCore/tests。

本轮实际验证命令：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v970-iPhone test -only-testing:RokuricsTests/CanonicalStatusExchangeRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -derivedDataPath /tmp/RokuricsDerivedData-v970-Mac test -only-testing:RokuricsMacTests/CanonicalStatusExchangeRuntimeTests
```

本轮实际结果：iPhone targeted tests 通过 7 个 Swift Testing 用例；Mac targeted tests 通过 5 个 Swift Testing 用例。第一次 iPhone 编译发现 `CanonicalStatusExchangeRuntime` duplicate check 误用 `String.map`，已改为显式 delta unwrap；第二次编译发现新增 heartbeat diagnostics 调用参数顺序不符合 `ConnectionDiagnosticsStore.record(...)`，已修正后重跑通过。Mac 本机 destination 出现 arm64/x86_64 多匹配 warning，但使用默认 arm64 My Mac 成功通过。

收尾仍需运行：

```sh
rg "CanonicalStatusExchangeRuntime|CanonicalStatusExchangeEnvelope" Rokurics RokuricsMac RokuricsShared/SyncCore RokuricsTests RokuricsMacTests
git diff --check
git status --short
```

说明：这些命令只证明本地代码级 realtime status exchange runtime wiring 与防回归。仍未运行完整全量 test suite，未产生 paired iPhone/Mac redacted jsonl，不得声明真机状态收敛完成或 canonical kernel 完成。

## 2026-06-14 Canonical v9.6 / Effective Status Binding Cutover 验证

本轮新增/更新验证重点：

- UI projection：`CanonicalEffectiveStatusUIProjection` 只有在 accepted finalize proof、peer inventory/hash-size proof、same hash+byteSize proof 或 valid dualAck proof chain 存在时才允许 `CanonicalDisplaySyncState` 显示 completed/peerVerified。
- Legacy fallback：`LegacySyncStatusToCanonicalEffectiveStatusAdapter` 把 oldKernel/blocked/fallback status 转成 canonical facts 后再投影；metadataOnly、receiveRecordOnly、completed ledger alone、partial receive 和 local file exists 不显示 completed/audio available。
- iPhone binding：`RecordingUploadCoordinator.displayStatus(for:)` 和 Library/Detail action area 读取 canonical display projection；view refresh 只读 display，不创建 upload job；旧按钮/文案/布局保持不变。
- Mac binding：Mac inbox/study detail 的 audio availability display 读取 `MacRecordingInboxItem.canonicalDisplaySyncState`；receive record only、metadataOnly、partial receive 不显示 audio available。
- Safety boundary：不新增 route、不改 upload route schema、不绕过 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash、不让 Mac 主动连接 iPhone、不把 display state 写回业务真相、不做视觉 UI 改动。

本轮目标验证命令：

```sh
rg "EffectiveSyncStatus|CanonicalDisplaySyncState" Rokurics RokuricsMac RokuricsShared/SyncCore RokuricsTests RokuricsMacTests
rg "uploadLedger\\.completed|metadataOnly|receiveRecord|localFileExists" Rokurics/RecordingLibraryView.swift Rokurics/RecordingStudyDetailPage.swift Rokurics/UploadableRecordingRow.swift RokuricsMac/MacRecordingInboxItem.swift RokuricsMac/MacStudyLibraryView.swift RokuricsMac/MacAudioInboxView.swift
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalEffectiveStatusUIProjectionTests -only-testing:RokuricsTests/CanonicalStatusTruthRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO test -only-testing:RokuricsMacTests/CanonicalEffectiveStatusUIProjectionTests -only-testing:RokuricsMacTests/CanonicalStatusTruthRuntimeTests
```

本轮实际结果：`rg "EffectiveSyncStatus|CanonicalDisplaySyncState"` 已确认真实 UI/status model 和双端测试引用 canonical projection；旧 soft evidence 字段在检查范围内未出现在 final display-complete 判断中，`receiveRecord` 只剩 Mac metadata loader 变量。`git diff --check` 通过。iPhone targeted tests 通过 `CanonicalEffectiveStatusUIProjectionTests` 与 `CanonicalStatusTruthRuntimeTests`；Mac targeted tests 在 `-parallel-testing-enabled NO` 下通过 `CanonicalEffectiveStatusUIProjectionTests` 与 `CanonicalStatusTruthRuntimeTests`，共 12 个 Swift Testing 用例。第一次 iPhone 测试曾因 Swift 编译器对 `normalized(value).map(CanonicalHash.init)` 触发诊断失败而中断，已改为显式 `guard` 后重跑通过。

说明：这些命令只证明本地代码级 UI status binding/projection 防回归。没有 paired iPhone/Mac redacted jsonl 时，不得声明真机状态收敛完成或 canonical kernel 完成。

## 2026-06-14 Canonical v9.5 / No-Freeze Hot Path Recovery 验证

本轮新增/更新验证重点：

- Diagnostics hot path：双端 `ConnectionDiagnosticsStore.record(...)` 从 MainActor 调用 1000 次时只做 redaction/enqueue/recent buffer，不读旧 JSONL、不 rewrite 全文件、不要求调用方 await；`flushForTests()` 后 JSONL 存在且内容 redacted。
- Async writer：`CanonicalAsyncDiagnosticsWriter` 被真实 iPhone/Mac app path 引用，支持 bounded queue/backpressure/drop policy、append flush、后台 compaction 和 `diagnosticsWriteDurationMs` clock evidence。
- Read cache key：iPhone/Mac canonical effective read cache key 排除 `generatedAt`，内容不变只更新时间戳时 key 相等；内容变化时 key 变化。Mac repeated `tree()` 与 iPhone repeated effective read 只 rebuild 一次。
- Status projection cache：`CanonicalStatusTruthRuntime` actor 维护 projection cache，重复 effective status read 不重复 reconciliation；MainActor reconciliation attempt count 在测试中保持 0。
- Safety boundary：不新增 route、不改 upload route schema、不绕过 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash、不改 UI 视觉、不改变 sync/apply/upload 语义、不让 Mac 主动连接 iPhone。

本轮实际验证命令：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalFileKernelRuntimeTests -only-testing:RokuricsTests/CanonicalReadRuntimeTests -only-testing:RokuricsTests/CanonicalStatusTruthRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO test -only-testing:RokuricsMacTests/CanonicalFileKernelRuntimeTests -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests -only-testing:RokuricsMacTests/CanonicalStatusTruthRuntimeTests
rg -n "CanonicalAsyncDiagnosticsWriter" Rokurics RokuricsMac RokuricsShared/SyncCore RokuricsTests RokuricsMacTests
rg -n "loadEntries\\(" Rokurics/ConnectionSyncStateStores.swift RokuricsMac/SecureReceiverService.swift
git diff --check
git status --short
```

本轮实际结果：iPhone 相关三组 targeted tests 通过；Mac 三组 targeted tests 在 `-parallel-testing-enabled NO` 下通过 27 个测试。最终 `rg`、`git diff --check` 与 `git status --short` 结果需随最终报告记录。上述验证仍是 local build/test evidence；未运行完整全量 test suite，未产生 paired iPhone/Mac redacted jsonl，不得声明真机 no-freeze 或 canonical kernel 完成。

## 2026-06-14 Canonical v9.4 / Sync State Truth Protocol 验证

本轮新增/更新验证重点：

- Fact model/runtime：`CanonicalStatusFactID`、fact/source/proof/causality/expiry、domain/phase、actor-backed in-memory fact store、replacement、expiration/stale filtering 和 deterministic merge ordering。
- Effective status：`CanonicalEffectiveSyncStatus` 输出 objectID/domain/phase/displayState/proof/sourceSummary/canDisplayAsComplete/canCreateUploadJob/canSuppressLegacyDuplicate/blocker。
- Truth table：metadataOnly、receiveRecordOnly、completed ledger alone、partial receive、local file exists、expected manifest hash 均不是 peer audio proof；same hash + same byteSize no-op；finalize proof、peer inventory/hash-size proof 或 dualAck proof chain 才能 peerVerified/completed；peerUnknown deferred；different hash conflict/no-overwrite；tombstone blocks resurrection；unsupported schema fallback；stale fact 不覆盖 fresh proof。
- Upload job gate：`canCreateUploadJob` 是唯一 canonical status-based job creation permission；view refresh denied；retry drainer 不创建 fresh job，只能恢复 existing eligible job。
- Adapter availability：iPhone `RecordingUploadCoordinator` / `StudyLibrarySyncCoordinator` / `StudyLibraryStore` 和 Mac `SecureReceiverService` / `SecureLocalHTTPSServer` / `StudyLibraryStore` / `MacRecordingFileStore` expose read-only `produceCanonicalStatusFact` / `canonicalEffectiveStatus`。
- Safety boundary：不新增 route，不改 upload route schema，不绕过 `RequestVerifier`/TLS/HMAC/pinning/nonce/body hash，不让 Mac 主动连接 iPhone，不直接 execute transfer，不直接 mutate UI，default/release 仍 oldKernel，legacy fallback 保留。
- Diagnostics：statusFactProduced/Merged/Rejected、statusProofExpired、effectiveStatusProjected、metadataOnlyRejectedAsAudioProof、completedLedgerRejectedAsPeerProof、partialReceiveRejectedAsCompleted、peerProofUnavailable、finalizeProofAccepted、existingDifferentAudioConflict、uploadJobCreationDeniedByStatusTruth 必须 redacted。
- Readiness：`CanonicalStatusTruthReadiness.v940(...)` READY 需要 proof-driven effective status、hard rules、fact store、integration availability、upload job gate、diagnostics redacted、oldKernel/default/legacy fallback、no route/security/schema change。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .codex-derived-data/ios-v940 -only-testing:RokuricsTests/CanonicalStatusTruthRuntimeTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS,arch=arm64' -derivedDataPath .codex-derived-data/mac-v940-retry -only-testing:RokuricsMacTests/CanonicalStatusTruthRuntimeTests
```

本轮实际结果：iPhone targeted tests 通过。Mac targeted tests 已编译通过，但两次执行均在本机 Xcode LaunchServices runner 启动阶段失败，未进入测试用例：`IDELaunchServicesLauncher - Failed to Launch (Failed to send resume to target process ... No such process)`。该失败作为本机 test runner blocker 记录，不作为 v9.4 truth table 断言失败。

说明：这些命令只证明本地代码级 status truth runtime/read path 和防回归。v9.4 仍不切 UI completed，不删除 legacy status path，不表示 full canonical kernel 完成；v9.5 仍需把 realtime status exchange ack/delta facts 接入 runtime。

## 2026-06-14 Canonical v9.3 / Transfer Kernel Runtime 验证

本轮新增/更新验证重点：

- State machine：`CanonicalTransferSessionStateMachine` 覆盖 required states、confirmedBytes 单调、deterministic next offset、duplicate chunk idempotency、wrong offset status refresh、resume、partial receive not finalized、finalize proof、hash/size mismatch conflict 和 no-overwrite。
- TransferPort boundary：`CanonicalTransferRuntimePort` 只表达 start/status/sendChunk/finalize/optional local abort；shared SyncCore 不出现 URLSession/Network.framework 或 Rokurics route/security 细节。
- Adapter：iPhone `IPhoneCanonicalTransferAdapter` 继续包装 existing `IPhoneCanonicalSecureAudioUploadPort` / `SecureMacUploadClient`；Mac `MacCanonicalTransferReceiveAdapter` 继续包装 existing `MacAudioUploadCutoverExecutor` / `MacRecordingFileStore`。
- Route/security：不新增 `/abort`，不改 start/status/chunk/finalize schema；`RequestVerifier` 仍覆盖现有 resumable audio routes；TLS/HMAC/pinning/nonce/body hash 未绕过。
- Retry/backoff：view refresh no job，retry drainer existing eligible only，peerUnknown/missing local audio/tombstone/conflict/security/malformed ledger blocked，interrupted session status refresh before resume，max attempt/backoff storm guard。
- Finalize proof：`CanonicalTransferFinalizeProof` 输出 receiver node、session id、object id、byteSize、hash prefix、internal proof、finalizedAt、verified；Transfer runtime 不设置 UI completed，v9.4 status truth 后续消费。
- Redaction：Transfer diagnostics 不得包含 absolute path、full hash、request/response body、raw audio bytes 等敏感内容。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTransferKernelRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTransferKernelRuntimeTests
```

说明：这些命令只证明本地代码级 Transfer runtime owner 与 adapter/route/security 防回归。没有 v9.4 Sync Status Truth 消费 finalize proof、也没有 paired iPhone/Mac redacted jsonl 前，不得声明 UI completed 真相完成、真机传输验证完成或 canonical kernel 完成。

## 2026-06-14 Canonical v9.1 / File Kernel Runtime 验证

本轮新增/更新验证重点：

- File snapshot：`CanonicalFileTreeSnapshotBuilder` actor 使用 root token + safe logical scope 构建 snapshot，输出 stable file identity、logical token、size、mtime/contentVersion、kind/domain hint、optional hash proof；绝对路径和 unsafe token 被拒绝。
- Manifest runtime：`CanonicalManifestRuntimeBuilder` 纯值构建，不做 file IO；cache key 由 root token、logical token、size、mtime/contentVersion、schema、domain hint/hash prefix 组成，`generatedAt` 变化不应改变 key。
- Checksum runtime：actor-backed cache；hit 跳过 hash provider；content facts/root/domain/schema/algorithm/token 变化 stale；corruption fail-closed 后重建；diagnostics 只允许 hash prefix。
- Diagnostics/runtime guard：`CanonicalAsyncDiagnosticsWriter` bounded enqueue + background flush，写入前 redaction；`diagnosticsWriteDurationMs` 来自 clock；`CanonicalMainActorHotPathGuard` 对 fileTreeSnapshot、manifestBuild、fullHash、diagnosticsWrite、readProjectionRebuild 记录实际 attempt。
- Read projection cache：iPhone/Mac 保留 v8.69 effective read cache；repeated UI read 不 rebuild、不触发 sync/upload；File-domain diagnostics 只记录 cache key prefix、invalidation/rebuild reason、duration/count。iPhone 不新增 synthetic `effectiveStudyTree`；Mac tree 继续一次性 cached projection。
- Mac inventory route：canonical mode `/sync/inventory` 每 request 构建一次 File snapshot/manifest 并复用 request context；`oldKernel`/blocked 跳过 canonical file snapshot；route schema/security/upload route/`RequestVerifier` 不变。
- Readiness：`CanonicalFileKernelRuntimeReadiness.v910(...)` 输出 no-freeze scorecard：fileTreeOffMainReady、manifestOffMainReady、checksumCacheReady、contentStableCacheKeyReady、asyncDiagnosticsReady、mainActorGuardReady、readProjectionCacheReady、macInventoryRouteReady、diagnosticsRedacted、routeSecurityUnchanged。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalFileKernelRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalFileKernelRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/StudyLibrarySyncTests
```

说明：这些命令只证明本地代码级 runtime owner、防回归和 route-level gating。没有 paired iPhone/Mac redacted jsonl 时，不得声明真机 no-freeze 或完整 canonical kernel 完成。

## 2026-06-14 Canonical v9.0 / Kernel Contract Freeze 验证

本轮新增/更新验证重点：

- Contract files：`RokuricsShared/SyncCore/CanonicalKernelProtocols.swift`、`CanonicalConnectionProtocol.swift`、`CanonicalTransferProtocol.swift`、`CanonicalSyncStatusTruthProtocol.swift`、`CanonicalRealtimeStatusExchangeProtocol.swift`、`CanonicalFileProtocol.swift`、`CanonicalKernelDiagnostics.swift`、`CanonicalKernelInvariants.swift`、`CanonicalKernelV9Completion.swift` 必须只定义 portable model/protocol/rule/report，不接 app runtime。
- Base types：`CanonicalNodeID`、`CanonicalNodeRole`、`CanonicalNodeIdentity`、`CanonicalLogicalTime`、`CanonicalSequence`、`CanonicalProtocolVersion`、`CanonicalObjectID`、`CanonicalDomain`、`CanonicalKernelModeMirror` 可 Codable roundtrip；mode mirror 只映射现有主开关语义。
- Proof hard rules：metadataOnly、receiveRecordOnly、completedLedgerOnly、partialReceive、localFileExists、expectedManifestHash 不是 peer audio proof；finalize proof/peer hash-size proof 可 verified；same hash + same byteSize 才 no-op；existing different audio conflict/no-overwrite；view refresh/retry drainer 不创建 fresh upload job。
- Diagnostics：performance/convergence taxonomy 完整；redaction detector 覆盖 absolute path、full hash、secret、full fingerprint、full metadata JSON、request/response body、raw audio、full transcript/note/summary/provider response。
- Gate：`CanonicalKernelV9ContractReadinessGate.v900(...)` 覆盖 `READY_FOR_V9_RUNTIME_IMPLEMENTATION`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_PROCEED`；unsafe 条件 fail closed。
- Boundary：contract tests 必须证明 transport-independent compile boundary，不新增 route、不改 upload route schema、不接 `RecordingUploadCoordinator`、不改 `StudyLibraryStore` read path、不改 Settings UI、不改 `CanonicalKernelSwitch` runtime behavior。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelV9ContractTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelV9ContractTests
```

说明：这些命令只产生 local build/test evidence。v9.0 READY 只表示 contract freeze 可进入后续 runtime adapter implementation，不表示 canonical kernel runtime 已完成，也不是 paired-device real-device evidence。

## 2026-06-13 Canonical v8.73 / Final App-State Readiness 验证

本轮新增/更新验证重点：

- Final gate：`CanonicalRealDeviceTrialReadinessGate.v873(...)` 输出 `READY_FOR_REAL_DEVICE_APP_TRIAL`、`PARTIAL_WITH_BLOCKERS`、`NOT_READY`、`UNSAFE_TO_TRY_ON_DEVICE` 四态；real-device evidence 通过 `realDeviceEvidencePresent` 单独记录。
- Claude report compliance：read cache、Mac inventory off-main/mode gating、oldKernel skip canonical build、`syncRequested` heartbeat hookup、event-driven trigger、status convergence、storm protection 和 runbook 均作为 gate 输入。
- Safety gates：default/release oldKernel、5 档主开关、`canonicalFullSync` owner/manual confirmation、legacy fallback、Path B legacy TLS/HMAC/upload route、route/security/`RequestVerifier` unchanged、switch-back proof driver 和 diagnostics redaction。
- Unsafe blockers：release/default canonical、route/security bypass、RequestVerifier bypass、Mac reverse connection、heartbeat heavy sync、view refresh upload job、retry storm、metadataOnly/completed ledger/partial receive audio proof、existing different audio overwrite 和 diagnostics leak 必须返回 `UNSAFE_TO_TRY_ON_DEVICE`。
- Real-device boundary：`READY_FOR_REAL_DEVICE_APP_TRIAL` 只表示代码级可上机按 runbook 试；没有 paired iPhone/Mac redacted jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/RokuricsTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalUploadStateTruthTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/StudyLibrarySyncTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/RokuricsMacTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/StudyLibraryStoreTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalUploadStateTruthTests
```

说明：仓库当前没有独立 `RokuricsTests/StudyLibrarySyncCoordinatorTests`、`RecordingUploadCoordinatorTests`、`StudyLibraryStoreTests`、`RokuricsMacTests/SecureReceiverServiceTests` 或 `SecureLocalHTTPSServerTests` 文件；对应 coverage 主要位于 `RokuricsTests/RokuricsTests.swift`、`RokuricsMacTests/RokuricsMacTests.swift`、`RokuricsMacTests/StudyLibrarySyncTests.swift`、`RokuricsMacTests/StudyLibraryStoreTests.swift` 和 canonical regression tests。所有命令仍只是 local build/test evidence。

## 2026-06-13 Canonical v8.72 / Event-Driven Sync Trigger and Status Convergence v1 验证

本轮新增/更新验证重点：

- Event contract：`SyncTriggerReason`/`LocalNetworkSyncEventTrigger` 可解析并覆盖 recordingCreated、recordingMetadataChanged、studyLibraryMetadataChanged、generatedArtifactAvailabilityChanged、tombstoneConflictChanged、audioUploadFinalized、macAudioReceiveFinalized、transcriptionStatusChanged、noteStatusChanged、syncStatusRefreshRequested、retryStateChanged、appForegroundedWithPendingChanges。
- iPhone triggers：新录音保存、rename/title/filing、upload status/finalize/retry、folder/item metadata、generated artifact availability、tombstone/conflict 和 foreground pending changes 只 queue immediate sync/status refresh，不直接 sync、不创建 upload job。
- Mac triggers：receive/finalize、metadata-only observation、library metadata、generated artifact、transcription/note status、tombstone/conflict、manual sync 和 foreground/server-start pending state 进入 Mac-local queue；Mac 只设置 existing `syncRequested` hint 或做 local refresh，不主动连接 iPhone。
- queue/storm：multiple quick events coalesce，sync running 时不重入，pending events after sync 最多触发 one follow-up，offline/background defer，不忙等；240 秒 periodic sync 保留。
- status convergence：upload/receive/transcription/note status projection refresh，不把 UI status 当 peer proof；metadataOnly、completed ledger alone、partial receive 不是 audio proof；finalize proof 才能推进 verified status。
- no route/security side effects：不新增 route，不改 upload route，不改 `/sync/inventory`、TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、pairing、Keychain 或 Mac server/client 拓扑。
- diagnostics：event trigger/status convergence/Mac hint diagnostics bounded/redacted。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/RokuricsTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/RokuricsMacTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
```

说明：仓库当前没有独立 `RokuricsTests/StudyLibrarySyncCoordinatorTests`、`RecordingUploadCoordinatorTests`、`RecordingMetadataTests`、`StudyLibraryStoreTests`、`RokuricsMacTests/SecureReceiverServiceTests`、`SecureLocalHTTPSServerTests` 或 `LongProcessingTests` 文件；对应 coverage 主要位于 `RokuricsTests/RokuricsTests.swift`、`RokuricsMacTests/RokuricsMacTests.swift`、`RokuricsMacTests/StudyLibraryStoreTests.swift`、`RokuricsMacTests/StudyLibrarySyncTests.swift` 与 canonical regression tests。所有命令只产生 local build/test evidence；没有 paired iPhone/Mac redacted jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。下一轮 v8.73 补真机观察 runbook + diagnostics gate。

## 2026-06-13 Canonical v8.71 / Live Heartbeat Consumes syncRequested 验证

本轮新增/更新验证重点：

- iPhone decode：`DeviceStatusResponse.syncRequested` 缺失时为 `false`，malformed optional hint 安全落到 `false`；`ok` 和 status summary 语义不变。
- live heartbeat：`StudyLibrarySyncCoordinator.performHeartbeat()` 在 `/device/status` 成功后解析 `syncRequested`/`syncStartSignal`，`false` 不排队，`true` 只 queue/schedule immediate sync tick。
- queue/debounce：queued tick 不等待 240 秒 timer，不在 heartbeat callback 内直接跑 heavy sync；running/pending/duplicate hint 有去重或 debounce diagnostics。
- kernel/gates：queued tick 复用现有 sync path，oldKernel 与 canonical modes 均遵守当前 kernel switch、decision、read、apply、upload 和 security gates。
- Mac pending：Mac manual sync response 继续广告 `syncRequested`；iPhone 发起 `/sync/inventory` 后 Mac pending 状态可被清理或推进到“iPhone 已开始同步”的可观察状态。
- no route/security side effects：不新增 route，不改 upload route，不改 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、pairing、Keychain 或 Mac server/client 拓扑。
- diagnostics：hint received/queued/started/completed/failed/deduped 与 Mac pending set/advertised/consumed/inventory observed/cleared 均 bounded/redacted。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/RokuricsTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/RokuricsMacTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
```

说明：仓库当前没有独立 `RokuricsTests/StudyLibrarySyncCoordinatorTests`、`RokuricsTests/LocalNetworkSyncHeartbeatTests`、`RokuricsMacTests/SecureReceiverServiceTests` 或 `RokuricsMacTests/SecureLocalHTTPSServerTests` 文件；对应 coverage 位于 `RokuricsTests/RokuricsTests.swift` 与 `RokuricsMacTests/RokuricsMacTests.swift`。所有命令只产生 local build/test evidence；没有 paired iPhone/Mac redacted jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。

## 2026-06-12 Canonical v8.70 / Mac Server Inventory Off-Main + Kernel-Mode Build Gating 验证

本轮新增/更新验证重点：

- Mac `/sync/inventory`：legacy response schema 和 route/security 不变，request verification、TLS/HMAC/pinning/nonce/body hash、`RequestVerifier` 不变。
- oldKernel/blocked：跳过 canonical recording adapter、library adapter、canonical manifest build 和 canonical seam diagnostics；default/release 仍 oldKernel。
- canonical modes：`canonicalShadow` off-main 构建 shadow facts；`canonicalDecisionOnly` 只构建/运行 decision 所需 facts；`canonicalApplyNoAudio` 不跑 audio commit facts；`canonicalFullSync` 每 request 只构建一次 canonical snapshot。
- reuse：多个 seam 使用同一 `MacInventoryRequestBuildContext` / canonical snapshot，duplicate canonical build 被阻止并记录 diagnostics。
- manifest：Mac inventory server path 使用 background manifest/facts input，不在 MainActor route path 同步重算 `StudyLibraryStore.makeSyncManifest(...)`。
- no side effects：不改变 receive.json、audio inbox、pending sync，不触发 transcription/note generation，不创建 upload job，不改 read/apply/upload/sync decision 语义。
- diagnostics：route/manifest/canonical started/completed/off-main/skipped/reused/duplicate/seam-shared metrics 来自真实路径或 test fake clock，bounded/redacted。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/StudyLibrarySyncTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
```

说明：仓库未发现 `RokuricsMacTests/SecureLocalHTTPSServerTests`。如果 full `StudyLibrarySyncTests` 受既有 apply/merge 测试交互影响失败，必须同时报告失败测试名，并用精确 selector 证明本轮新增 Mac inventory tests 与相关回归可独立通过。所有命令只产生 local build/test evidence；没有 paired iPhone/Mac redacted jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。

## 2026-06-12 Canonical v8.69 / Canonical Read Effective Projection Cache 验证

本轮新增/更新验证重点：

- iPhone cache：`effectiveStudyItems` / `effectiveStudyFolders` 在 canonical served path 下首次 projection 后 repeated access 不重算；folders 不再重复触发 item conversion。当前 iPhone 源码没有 `effectiveStudyTree` property，因此 tree 覆盖不适用 iPhone。
- Mac cache：`effectiveStudyItems` / `effectiveStudyFolders` / `effectiveStudyTree` 来自同一 cached projection；default `tree()` 读取 cached effective tree；oldKernel/fallback 继续 legacy stored `studyTree`。
- invalidation：read runtime result/snapshot、read config/mode、legacy backing refresh、fallback state 和 Mac hierarchy rule 变化会 invalidate/rebuild；相同 key 不 rebuild。
- no side effects：effective read access 不触发 sync/upload、不创建 upload job、不 mutate backing arrays；Mac 不改变 `/sync/inventory`、`receive.json`、audio inbox、pending sync、transcription/note。
- diagnostics：cache hit/miss/invalidated/rebuilt/tree rebuilt/fallback legacy/repeated access/duration metrics 来自真实路径，bounded/redacted。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/StudyLibraryStoreTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
```

说明：当前仓库没有单独 `RokuricsTests/StudyLibraryStoreTests.swift`；iPhone Store effective read cache coverage 位于 `RokuricsTests/CanonicalReadRuntimeTests.swift`。这些命令只产生 local build/test evidence。没有 paired iPhone/Mac redacted jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。不得把 simulator/local build/test 当作真机卡顿验证完成。

## 2026-06-12 Canonical v8.68 / T7 Single Kernel Switch UI + Final Code Completion Gate 验证

本轮新增/更新验证重点：

- Settings UI/model：iPhone/Mac DEBUG `Debug · 同步内核` 只有一个 `内核模式` 主选择器，用户可见 5 档为 `oldKernel`、`canonicalShadow`、`canonicalDecisionOnly`、`canonicalApplyNoAudio`、`canonicalFullSync`；default/release/default 为 `oldKernel`。
- confirmation：选择 `canonicalFullSync` 必须二次确认；切回 `oldKernel` 清除 confirmation；确认文案包含 backup/test-device、legacy fallback、switch-back proof 和 stop conditions。
- scattered switch suppression：libraryMetadata pilot、productionRoot flag、read/apply/audio/existence override 和 UserDefaults debug key 只能降级/阻断/诊断，不能越过主开关提权。
- final scorecard：`CanonicalSyncKernelCompletionScorecard.v868(...)` 覆盖 T1–T6、runtime mappings、oldKernel legacy mapping、Path B transport、route/security、diagnostics redaction、realDeviceEvidence=false 和四态 code-completion result。
- manual gate：`CanonicalSyncKernelManualSwitchGate` 只在 scorecard READY、backup acknowledgement、owner approval、manual confirmation、oldKernel baseline、switch-back proof、diagnostics export、legacy fallback、route/security unchanged、release/default oldKernel、no unsafe blocker 时允许 real-device trial。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSwitchBackTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSwitchBackTests
```

这些命令只产生 local build/test evidence。没有 paired iPhone/Mac redacted jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。`READY_FOR_REAL_DEVICE_CANONICAL_SWITCH` 只表示代码级可交给用户按 runbook 真机逐档推进，不代表真机验证完成。

## 2026-06-12 Canonical v8.67 / T6 Debug Switch-Back Proof Driver 验证

本轮新增/更新验证重点：

- Debug driver：双端 Settings 存在“运行新旧内核切回证明”按钮，按钮只在 DEBUG 出现，调用平台薄 wrapper，再调用 shared `CanonicalSwitchBackProofDebugRunner`。
- clone-before-proof：current app data root 只作为 source root；driver 必须创建 temp/test clone，clone root 经 `CanonicalSwitchBackRootSafetyGuard` 接受后才调用 `CanonicalSwitchBackRealisticRootHarness.runKernelSwitchBackProof()`。
- root safety：拒绝 `/`、home、repo root、Documents/Application Support production root 与子路径、Desktop production root、未标记非 temp root和 symlink/path escape root；temp clone / deterministic fixture / marked test clone 可接受。
- proof sequence：验证 oldKernel -> canonicalFullSync -> oldKernel -> canonicalFullSync 切回证明；existing sequence proof 仍覆盖 shadow/decision/applyNoAudio 中间阶段。
- JSONL evidence：写 temp proof-run root 下的 `Diagnostics/canonical-switch-back-proof.jsonl`，event family 为 `canonicalSwitchBackProof*`，字段 redacted，仅含 root token、counts、blocker enum、relative path 和 `evidenceKind=realisticRoot`。
- UI summary：显示 running/passed/failed/blocked、root safety、clone token、domain/crash summary、old/canonical/switch-back result、relative evidence path、blocker 和 warning；不显示绝对路径、完整 hash、metadata JSON 或用户内容。
- no side effects：不改主开关、不触发 sync/upload、不创建 upload job、不发送网络、不写业务域；Mac 不重启 receiver、不改 route/security、`receive.json`、audio inbox、pending sync、transcription/note。
- scorecard：driver proof passed 可满足 realistic-root switch-back prerequisite；missing/failed proof blocked；real-device evidence remains false。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSwitchBackTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLegacyCompatibilityTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSwitchBackTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLegacyCompatibilityTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
```

这些命令只产生 local build/test evidence。没有 paired iPhone/Mac jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。不得把 simulator、fixture root、temp realistic-root proof 或 build/test success 当作 paired-device real-device evidence。下一轮 v8.68 才处理 T7：单一主开关 UI 收口与最终 code-completion gate。

## 2026-06-12 Canonical v8.66 / T4-T5 Executor and Port Injection + Gated Production-Root Write 验证

本轮新增/更新验证重点：

- factory injection：iPhone/Mac production port factories 由 master switch effective config 决定 executor/port availability；`oldKernel`、diagnostics/shadow、decisionOnly、blocked 和 release/default 不构造 production-root writable ports。
- mode gates：`canonicalApplyNoAudio` 可注入 non-audio apply/existence availability，但 canonical audio upload executor blocked；`canonicalFullSync` 缺 owner approval、manual confirmation 或 root safety 时 production-root write blocked。
- fullSync allowed：DEBUG/internal + ownerApproved + manualConfirmation + readiness/fallback/legacy-readable/route-security/root safety 全部满足时，iPhone/Mac recording/library/generated/tombstone RealApplyPorts 可用 `allowProductionRootWrites=true` 构造，Mac existence/audio executor 可注入。
- bypass guard：libraryMetadata pilot、specialized config、UserDefaults debug toggle 和 test-only injection 不能绕过主开关；productionRoot flag 不能单独启用 production write。
- audio/existence invariants：metadataOnly 不是 audioAvailable，completed ledger alone 不是 proof；audio executor 继续复用 existing secure start/status/chunk/finalize path，不新增 route、不改 `RequestVerifier`。
- diagnostics：factory/gate diagnostics 只记录 redacted mode/root-safety/blocker summary，不含绝对路径、完整 hash、secret、fingerprint、metadata JSON、request/response body、raw audio bytes 或 provider/generated 内容。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalAudioUploadRuntimeTests
```

这些命令只产生 local build/test evidence；没有 paired iPhone/Mac jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。本轮不声明真机 production-root write 或 audio upload 验证完成。

## 2026-06-12 Canonical v8.65 / T2-T3 Master Switch Read + recordingMetadata ReadSeam Runtime Wiring 验证

本轮新增/更新验证重点：

- master switch read config：default/missing UserDefaults 与 `oldKernel` 清空 Store canonical read override；`canonicalShadow` compare only；`canonicalDecisionOnly` 与 `canonicalApplyNoAudio` 不 serve canonical read；`canonicalFullSync` + gate allowed 可让 iPhone/Mac Store 收到 guarded canonical read config。
- switch refresh：oldKernel -> canonicalFullSync -> oldKernel 会刷新 effective read output，且不会改变 Store legacy backing arrays。
- recordingMetadata ReadSeam：iPhone/Mac read runtime adapter 会调用平台 ReadSideSeam；divergence、read failure、unsupported/missing evidence fallback legacy。
- no side effects：read path 不触发 sync/upload、不创建 upload job、不 mutate Store；Mac read path 不改变 `/sync/inventory` response、`receive.json`、audio inbox、pending sync 或 transcription/note generation。
- bypass guard：libraryMetadata debug pilot、generatedArtifacts、tombstoneConflict、recordingMetadata、audioUpload、tests-only injection、UserDefaults debug switches 和旧 read override 只能进一步限制主开关，不能绕过 `CanonicalKernelSwitch`。
- diagnostics：新增/更新 tests 仍要求 diagnostics redacted，不含绝对路径、完整 hash、完整 metadata JSON、secret、fingerprint、request/response body、provider/generated/audio 内容。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataReadSideTests
```

这些命令只产生 local build/test evidence；没有 paired iPhone/Mac jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。本轮不验证 v8.66 的 T4/T5 production-root gated write。

## 2026-06-12 Canonical v8.64 / T1 Inventory MainActor Residual Closure 验证

本轮新增/更新验证重点：

- iPhone inventory：`LocalNetworkSyncInventoryBuilder` 不标注 `@MainActor`，且不再承载全量 metadata/jobs load、directory scan、metadataHash 或 SHA256；`buildRuntimeSnapshot(...)` 消费 background immutable input。
- sync manifest：`makeSyncManifest` 的 T1 主线程残留改为 `makeSyncManifestInBackground(...)` / background snapshot -> pure build；pure builder 不访问 Store、不做 IO、不做网络、不创建 upload job。
- Mac inventory：`/sync/inventory` facts 收集在 background input 完成，route schema、route behavior 和 `RequestVerifier` 不变。
- telemetry：`manifestBuildDurationMs`、cache skip/hash counters、MainActor manifest attempt 等字段来自真实 clock/cache/detector，不用 hardcoded 0 冒充成功；diagnostics redacted。
- regressions：legacy inventory output schema、canonical inventory snapshot schema、oldKernel behavior、checksum cache hit skip、same-run snapshot reuse、read/apply/upload mocks 未被调用、no upload job created。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/StudyLibrarySyncTests/localNetworkSyncInventoryBuildsMetadataJobsAndHashesOffMain
```

说明：当前仓库没有单独 `CanonicalChecksumCacheTests` 文件；checksum cache hit/skip coverage 位于 `CanonicalInventoryRuntimeTests`。这些命令只产生 local build/test evidence；没有 paired iPhone/Mac jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。

## 2026-06-12 Canonical v8.58 / RecordingMetadata RealApplyPort + ReadSideSeam 验证

本轮新增/更新验证重点：

- hard deliverables：四个文件必须存在并参与构建：`Rokurics/IPhoneRecordingMetadataRealApplyPort.swift`、`RokuricsMac/MacRecordingMetadataRealApplyPort.swift`、`Rokurics/IPhoneRecordingMetadataReadSideSeam.swift`、`RokuricsMac/MacRecordingMetadataReadSideSeam.swift`。
- real apply：iPhone/Mac recordingMetadata RealApplyPort root-bound、atomic、rollback checkpoint、postcondition verified、legacy-readable、canonical-readable；failure rollback/fallback，rollback failure fatal blocker；diagnostics redacted。
- write boundary：只写录音 title/name metadata、business modifiedAt fact 和 stable metadataHash；不写 audio bytes、不创建 upload job、不改 upload ledger、不写 standalone note 或 generated content；Mac 还要证明不写 `receive.json`、audio inbox、不触发 transcription/note generation。
- read seam：default/oldKernel legacy；canonicalShadow 和 canonicalDecisionOnly diff only；canonicalApplyNoAudio 可 diff 不默认 serve canonical；canonicalFullSync + gate allowed + clean diff 可 serve canonical recording metadata；divergence/read failure fallback legacy。
- main switch：`CanonicalKernelSwitch` 是唯一入口，release/default oldKernel，legacy fallback 保留，specialized recording config 不得绕过主开关。
- compatibility：legacy write -> canonical read、canonical write -> legacy read、switch oldKernel 后仍 legacy read same、oldKernel write 后 canonicalFullSync read same、crash/rollback/postcondition 中断保持 legacy-readable，无 migration required。
- diagnostics：targeted tests 必须检查 diagnostics redacted，不含完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint、request/response body、generated/provider/audio 内容。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsTests/CanonicalRecordingMetadataReadSideTests -only-testing:RokuricsTests/CanonicalRecordingMetadataRealApplyPortTests -only-testing:RokuricsTests/CanonicalKernelSwitchTests -only-testing:RokuricsTests/CanonicalLegacyCompatibilityTests -only-testing:RokuricsTests/CanonicalSyncRuntimeTests -only-testing:RokuricsTests/CanonicalApplyRuntimeTests -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataReadSideTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataRealApplyPortTests -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests -only-testing:RokuricsMacTests/CanonicalLegacyCompatibilityTests -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests -only-testing:RokuricsMacTests/CanonicalApplyRuntimeTests -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
```

说明：这些 tests 证明 dedicated recordingMetadata real apply/read seam、本地主开关 mapping、legacy compatibility 与 switch-back no-migration 行为。它们不产生 paired iPhone/Mac 真机 jsonl；没有 real-device run 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 `not run; no real-device evidence produced.`。

## 2026-06-11 Canonical v8.57 / P3-2 Realistic Library Root Switch-Back Proof 验证

本轮新增/更新验证重点：

- root safety：`CanonicalSwitchBackRootSafetyGuard` 拒绝 production-like root、home、repo root、Documents/App Support 生产路径和未标记非 temp root；temp realistic root 与 test clone 可运行。
- realistic fixture：`CanonicalRealisticLibraryRootFixture` 覆盖 study library metadata、recording metadata、generated artifact metadata/content fixture、tombstone/conflict/resurrection block、existence ledger、audio inbox、small audio fixture、upload ledger、retry、checksum cache、diagnostics、legacy store、canonical supplemental 和 schema marker。
- switch-back matrix：`CanonicalDomainSwitchBackMatrix` 覆盖五个业务域，证明 legacy/canonical/oldKernel/canonicalFullSync 双向读写兼容、无需 migration、无 canonical-only required field、无 legacy-incompatible disk format、fallback retained。
- crash/restart：`CanonicalCrashPoint` 覆盖 12 个 crash point，包含 audio session/chunk/finalize/retry/diagnostics；partial state 不得 completed/audioAvailable，不得 duplicate job storm。
- sequence/evidence：`CanonicalKernelSwitchSequenceProof` 覆盖 oldKernel -> canonicalShadow -> canonicalDecisionOnly -> canonicalApplyNoAudio -> canonicalFullSync -> oldKernel -> canonicalFullSync；`CanonicalSwitchBackEvidenceExporter` 区分 synthetic、realistic-root 与 real-device missing，并 redacts paths/hashes/content。
- scorecard：`CanonicalSyncKernelCompletionScorecard.v857(...)` 在 realistic-root proof 通过但无 paired-device evidence 时为 `codeCompleteNeedsDeviceEvidence`；release/default canonical、fallback missing 或 diagnostics leak 为 unsafe/blocker。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLegacyCompatibilityTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSwitchBackTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalCrashRecoveryTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLegacyCompatibilityTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSwitchBackTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalCrashRecoveryTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
```

说明：这些 tests 只产生 code-level / realistic-root proof。没有 paired iPhone/Mac jsonl 时，`REAL_DEVICE_EVIDENCE_RESULT` 必须是 not run，不能声称真机 validated、不能删除 legacy、不能 release/default canonical。

## 2026-06-11 Canonical v8.56 / P3-1 Unified Master Kernel Switch Consolidation 验证

本轮新增/更新验证重点：

- contract/mapping：`CanonicalKernelSwitch` 是唯一主入口；default/release `oldKernel`；`oldKernel` 关闭所有 canonical owners；`diagnosticsOnly`/`canonicalShadow` 不写不上传不 serve canonical read；`canonicalDecisionOnly` 不 apply/upload/read；`canonicalApplyNoAudio` 阻止 canonical audio upload；`canonicalFullSync` 映射全部 runtime 但必须 gate allowed。
- gate/blocker：`canonicalFullSync` 缺 debug/internal、manual confirmation、owner approval、legacy fallback、read/apply/audio/domain readiness、switch-back precondition、route/security unchanged、safe production root 或 diagnostics redaction 时必须 blocked。
- bypass audit：advanced overrides 只能降权，不能关闭 fallback/redaction、扩大 domain/scope、启用 runtimeSwitch、提升 read/apply/audio/sync 权限或写 unsafe production root；libraryMetadata debug pilot 不能 override `oldKernel`。
- Settings/injection：DEBUG-only `Debug · 同步内核` 持久化主模式；选择 fullSync 每次需要确认；切回 oldKernel 立即清 confirmation；Mac receiver app path 使用 master effective config；read/upload/apply/sync 都从 master result provider 或 effective config 获取。
- diagnostics：`canonicalKernelSwitch*` 事件只包含 mode、runtime modes、blocker enums、counts/summary，不含完整 path/hash/metadata/user content/security material。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
```

说明：本组测试只验证 P3-1 主开关收敛、mapping/gate/blocker/diagnostics 和 app-path bypass hardening。它不产生真实 iPhone/Mac switch-back evidence，不证明 v8.57 realistic-root switch-back，不允许 release/default canonical，不删除 legacy，不禁用 fallback。

## 2026-06-11 Canonical v8.55 / P2-5 audioUpload Domain Readiness 验证

本轮新增/更新验证重点：

- contract/status：`canonical-audio-upload-v1` 只暴露 redacted audio upload domain fields；metadataOnly/receiveRecordOnly/studyItemOnly/completed ledger alone/expected manifest hash 都不是 audio proof；readStatus 覆盖 uploadNeeded、uploading、retryScheduled、uploadedVerified、conflict、deferredPeerUnknown 等状态。
- decision/runtime：oldKernel legacy；diagnosticsOnly/canonicalShadow compare only no job；canonicalDecisionOnly evaluates no network；canonicalApplyNoAudio blocks audio upload；canonicalFullSync gated decision+commit+read/status with fallback。audioUpload 进入 `CanonicalSyncRuntimeDecisionScope`。
- commit/security：canonical commit 继续复用 existing secure upload clients/routes；不新增 route，不改 `RequestVerifier`、TLS/HMAC/pinning/nonce/body hash；finalize proof 前不得 mark uploaded。
- ownership/retry：legacy running job prevents canonical duplicate；canonical exact successful job suppresses matching fresh legacy only after proof；retry drainer resumes existing eligible job only；view refresh/read/status never creates upload job；security/conflict no bypass fallback。
- compatibility/readiness：legacy fallback、switch-back proof、legacy-readable status 和 report-only `readyToRetireLegacyReportOnly` 必须保留；`realDeviceEvidencePresent=false` 直到 paired iPhone/Mac evidence 存在。
- diagnostics：`canonicalAudioUploadDecision*`、audio upload status projection 和 readiness scorecard diagnostics 必须 redacted，只输出 object/session prefix、state/reason、hash prefix、byte/offset/retry/count/duration summary。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadCommitExecutorTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalUploadStateTruthTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalUploadRetryDrainerTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalAudioUploadReceiveTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalUploadStateTruthTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
```

说明：如果 exact test 名称不同，应先用 Xcode/test inventory 映射到实际等价 tests 并在报告中说明。真实完成仍需要 paired iPhone/Mac long-recording evidence，证明 metadataOnly -> upload candidate、session start/chunk/resume/finalize、final proof accepted、same hash+size no-op、different hash/size conflict、old->new->old switch-back 和 redacted diagnostics。

## 2026-06-11 Canonical v8.54 / P2-4 tombstoneConflict Domain Readiness 验证

本轮新增/更新验证重点：

- contract/hash：`canonical-tombstone-conflict-v1` 只 hash tombstone/conflict marker 的 stable business facts；delete target path、local/resource path、UI-only state、upload/receive state、full content、generated content、provider response、audio facts 和 diagnostics 不改变 tombstoneConflict hash。
- candidate/runtime hash：`CanonicalTombstoneConflictCandidate.markerHash` 使用同一 v8.54 business schema；candidate marker payload 不得回退旧 v8-11 schema。
- logical time/LWW：same hash no-op；local newer use local marker；peer newer apply peer marker；equal logical time + different hash deterministic conflict/tie defer；missing logical time 或 schema mismatch fallback/block legacy。
- anti-resurrection/delete safety：stale live resurrection 写 resurrection block/conflict record；restore、clear tombstone、physical delete、permanent delete、tombstone GC、generated artifact/audio deletion blocked。
- decision/runtime：oldKernel legacy；diagnosticsOnly/canonicalShadow compare only；canonicalDecisionOnly no apply；canonicalApplyNoAudio 可 tombstone/conflict apply 但 no audio；canonicalFullSync gated decision/apply/read with fallback。tombstoneConflict schema mismatch 必须阻断 primary。
- apply/read：apply 必须 root-bound/atomic/rollback/postcondition and legacy-readable；只写 soft marker/conflict ledger。read projection metadata-only、redacted、no delete/restore/GC、no sync/upload/store mutation。
- compatibility：legacy fallback、legacy-readable tombstone/conflict path、switch-back proof 和 report-only readiness 必须保留；`readyToRetireLegacyReportOnly` 不执行 deletion/disable。
- diagnostics：`canonicalTombstoneConflictDecision*` 与 `canonicalTombstoneConflictRead*` 必须 redacted，只输出 mode/domain/objectID/marker/action/state/reason/count/hash prefix/logical time summary 等安全摘要。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTombstoneConflictTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTombstoneConflictCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTombstoneConflictReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
```

说明：这些 tests 证明 v8.54 contract、candidate hash schema、runtime scope/schema gate、read diagnostics、anti-resurrection/delete blocker 和 scorecard 行为。真实完成仍需要 paired iPhone/Mac device evidence，证明 tombstone marker propagation、conflict record write/read, anti-resurrection, guarded read served/fallback、old->new->old switch-back 和 redacted diagnostics。

## 2026-06-11 Canonical v8.53 / P2-3 generatedArtifacts Domain Readiness 验证

本轮新增/更新验证重点：

- contract/hash：`canonical-generated-artifact-v1` 只 hash artifactID、recording objectID、kind、availability、contentHash、byteSize、businessModifiedAt；logical/local path、observedAt、producer node、provider response、transcript/note/summary 正文、diagnostics、audio/upload/receive state 不改变 generated artifact hash。
- content proof：contentHash + byteSize 相同 no-op；hash-only/size-only/availableWithoutHash 不可 apply；missing content/hash/byteSize deferred；unsupported kind/audio confusion blocked。
- modifiedAt/LWW：双方内容 proof 完整且内容不同才使用 business modifiedAt；local newer send；peer newer apply；equal modifiedAt deterministic defer/conflict；missing modifiedAt 或 schema mismatch fallback/block legacy。
- decision/runtime：oldKernel legacy；diagnosticsOnly/canonicalShadow compare only；canonicalDecisionOnly no apply；canonicalApplyNoAudio 可 generated artifact apply 但 no audio；canonicalFullSync gated decision/apply/read with fallback。generatedArtifacts schema mismatch 必须阻断 primary。
- apply/read：apply 必须 root-bound/atomic/rollback/postcondition and legacy-readable；不得新增 route、不得触发 AI/转写/笔记生成、不得写 audio/upload/receive。read projection metadata-only、content excluded、no sync/upload/store mutation。
- compatibility：legacy fallback、legacy-readable generated artifact path、switch-back proof 和 report-only readiness 必须保留；`readyToRetireLegacyReportOnly` 不执行 deletion/disable。
- diagnostics：`canonicalGeneratedArtifactDecision*` 与 `canonicalGeneratedArtifactRead*` 必须 redacted，只输出 mode/domain/objectID/artifactID/action/state/reason/count/hash prefix/byteSize 等安全摘要。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactDomainTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactDomainTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
```

说明：这些 tests 证明 v8.53 contract、runtime scope/schema gate、read diagnostics、duplicate guard 和 scorecard 行为。真实完成仍需要 paired iPhone/Mac device evidence，证明 generated artifact availability、safe apply/read served/fallback、old->new->old switch-back 和 redacted diagnostics。

## 2026-06-11 Canonical v8.52 / P2-2 libraryMetadata Domain Readiness 验证

本轮新增/更新验证重点：

- contract/hash：`canonical-library-metadata-v1` 只 hash folder/study item/standalone-note shell 的稳定业务 metadata；title/name、parent/filing/folder refs、tags/color/order/deleted/businessModifiedAt 可改变 hash；resource path、logical resource tokens、note full content、generated content、audio facts、upload/receive/sync 状态和 diagnostics 不改变 libraryMetadata hash。
- modifiedAt/LWW：`CanonicalLibraryMetadataModifiedAtPolicy` 使用 businessModifiedAt；same hash no-op；local newer send；peer newer apply；equal modifiedAt 且 hash 不同 deterministic defer/conflict；missing modifiedAt 或 schema mismatch fallback/block legacy。
- decision/runtime：oldKernel legacy；diagnosticsOnly/canonicalShadow compare only；canonicalDecisionOnly no apply；canonicalApplyNoAudio 仅 metadata apply 且 audio disabled；canonicalFullSync gated decision/apply/read with fallback。libraryMetadata schema mismatch 必须阻断 primary。
- apply/read：metadata apply 必须 root-bound/atomic/rollback/postcondition and legacy-readable；不得 resource move、standalone note content write、audio/upload/receive write。read projection guarded、no sync/upload/store mutation，并通过 Store effective folders/items 被 UI 读取。
- compatibility：legacy fallback、legacy-readable disk format、switch-back proof 和 report-only readiness 必须保留；`readyToRetireLegacyReportOnly` 不执行 deletion/disable。
- diagnostics：`canonicalLibraryMetadataDecision*` 与 `canonicalLibraryMetadataRead*` 必须 redacted，只输出 mode/domain/objectID/action/state/reason/count/hash prefix 等安全摘要。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataReadCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibrarySyncPlannerTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
```

说明：这些 tests 证明 v8.52 contract、planner/runtime/read diagnostics 和 scorecard 行为。真实完成仍需要 paired iPhone/Mac device evidence，证明 libraryMetadata change、resource path change no-hash-change、decision used、metadata apply/read served/fallback、old->new->old switch-back 和 redacted diagnostics。

## 2026-06-11 Canonical v8.51 / P2-1 recordingMetadata Domain Readiness 验证

本轮新增/更新验证重点：

- contract/hash：`canonical-recording-business-metadata-v1` 只 hash stable business metadata；title/name 变化改 hash；upload progress、upload ledger、receive/observedAt、local/audio path、audio facts、processing status、diagnostics、generated transcript/note/summary content 不改 recordingMetadata hash。
- modifiedAt/LWW：使用 business modifiedAt；旧 iPhone missing business modifiedAt 必须 documented fallback 或 gate blocker；equal modifiedAt tie deterministic defer/conflict。
- decision/runtime：oldKernel legacy；diagnosticsOnly/canonicalShadow compare only；canonicalDecisionOnly no apply；canonicalApplyNoAudio decision+metadata apply and audio disabled；canonicalFullSync gated decision/apply/read with fallback。
- apply/read：metadata apply must be root-bound/atomic/rollback/postcondition and legacy-readable; read projection is guarded, no sync/upload/store mutation, and Store/UI effective model can consume canonical recordingMetadata when served.
- compatibility：legacy -> canonical -> legacy switch-back requires no migration; crash/restart around checkpoint/write/postcondition remains legacy-readable; readyToRetireLegacy remains report-only.
- diagnostics：recordingMetadata decision/read diagnostics are redacted and use hash prefixes only.

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalApplyRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
```

说明：新增 `CanonicalRecordingMetadataTests` 覆盖 P2-1 contract/read/switch-back scorecard。其它 runtime/cutover/read/apply tests 是 existing regression coverage。真实完成仍需要 paired iPhone/Mac device evidence，证明 metadata change、canonical hash equality/change、decision used、apply executed、read served/fallback、divergence count、old->new->old switch-back 和 redacted diagnostics。

## 2026-06-11 Canonical v8.50 / P1-3 upload retry drain/state consistency 验证

本轮新增/更新验证重点：

- state truth：metadataOnly / receiveRecordOnly / studyItemOnly / completed ledger alone / expected manifest hash+size 都不是 audio proof；peerUnknown deferred；missing local audio blocked；tombstoned blocked；same hash+same byteSize no-op；different hash/size conflict；finalized Mac proof accepted。
- retry drainer：只 resume existing eligible canonical/legacy job；不创建 unrelated fresh job；view refresh 不创建 job；peerUnknown/conflict/missing/tombstoned/security/malformed ledger fail closed；backoff/max retry 防 retry storm；stale session 先 status refresh。
- ownership：oldKernel legacy-only；diagnostics/shadow/decision/apply-no-audio 不建 canonical audio job；canonicalFullSync gate allowed 才 canonical owner；canonical start/finalize proof suppress exact legacy duplicate；security/conflict 不 fallback bypass/overwrite；legacy running suppress canonical duplicate。
- status projection/diagnostics：canonical state reconciliation 与 upload status projection 只进入 diagnostics/shadow，不切 UI/read path；diagnostics redacted。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalUploadStateTruthTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalUploadRetryDrainerTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalUploadOwnershipTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeCommitTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalUploadStateTruthTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalAudioUploadReceiveTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalExistenceApplyBridgeTests
```

说明：当前源码存在 iOS `CanonicalAudioUploadCommitExecutorTests`，同时保留等价 runtime commit 覆盖 `CanonicalAudioUploadRuntimeCommitTests` / Mac `CanonicalAudioUploadRuntimeCommitMacTests`。v8.50 tests 证明状态口径与 policy guard，不替代 paired-device retry/resume/finalize evidence。

## 2026-06-11 Canonical v8.49 / P1-2 audio upload commit executor 验证

本轮新增/更新验证重点：

- runtime config：default/release disabled；diagnosticsOnly/noCommit no job/network；canonicalUploadWithLegacyFallback 需要 DEBUG/internal owner approval；failure/blocker 保留 legacy fallback。
- candidate truth：peer metadataOnly/receiveRecordOnly/studyItemOnly without audio -> upload candidate；peer same hash+size -> no-op；peerUnknown -> deferred；different hash/size -> conflict；completed ledger alone 与 metadataOnly 不算 audio proof。
- resumable state：start/status/chunk/resume/finalize；confirmedBytes monotonic；duplicate chunk idempotent；wrong offset fail/resume；durable job store/retry resume；diagnostics redacted。
- transport/security：iPhone adapter 复用 `RecordingUploadClient` / `SecureMacUploadClient`；Mac receive 复用 `SecureLocalHTTPSServer` / `RequestVerifier` existing routes；不新增 route，不新增 abort route。
- finalize/postcondition：byteSize/hash proof 之后才 mark uploaded、清 retry、suppress duplicate legacy；existing different audio conflict/no-overwrite；大音频不 full-buffer。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadCommitExecutorTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeCommitTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingExistenceTruthTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalAudioUploadRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalAudioUploadReceiveTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalExistenceApplyBridgeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/LongProcessingTests
```

说明：这些 tests 证明 simulator/macOS unit coverage 和 existing route/runtime contracts。真实完成仍需 paired-device 新录音或长录音证据，覆盖 metadataOnly candidate、session start、chunk confirm、resume、finalize proof、Mac `audioAvailable` after finalize、same hash+size no-op 和 existing different audio conflict。

## 2026-06-11 Canonical v8.48 / P1-1 manifest.recordings apply 验证

本轮新增/更新验证重点：

- manifest schema：旧 manifest 缺 `recordings` decode 为 empty；新 manifest 带 recordings 可 decode；缺 audio facts 不等于 `audioAvailable`；malformed recording fact fail closed。
- Mac apply：server apply path 默认消费 `manifest.recordings`，写 canonical metadata-only existence ledger，不写 audio file、不写 `receive.json`、不 mark upload completed；重复 apply no-op；metadataHash 变化更新 record。
- Mac inventory：合并 metadata-only ledger，报告 recording exists 且 `audioAvailable=false`，没有真实 audio 时不报告 audio checksum/size/path。
- iPhone upload candidate：peer metadataOnly -> existing evaluator/upload coordinator path 的 candidate；receiveRecordOnly/studyItemOnly 不是 audio proof但可产生 upload candidate；same hash+size no-op；peerUnknown deferred；different hash/size conflict；local audio missing/view refresh 不创建 upload job。
- 边界：不新增 route、不改 upload route、不改 TLS/HMAC/pinning/nonce/body hash/`RequestVerifier`、不改 read path、不改主开关语义、不实现 canonical audio upload commit executor。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalManifestRecordingsApplyTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalExistenceApplyBridgeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalManifestRecordingsSchemaTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalAudioUploadCandidateTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingExistenceTruthTests
```

说明：这些 tests 只证明 P1-1 metadata-only apply / inventory / candidate handoff。它们不证明 canonical audio upload commit，也不替代 paired-device 新录音真机验证。真实完成仍需真机确认 iPhone 发送 `manifest.recordings`、Mac 写 metadata-only ledger、Mac inventory 暴露 `audioAvailable=false`、iPhone 产生 upload candidate、音频是否经 legacy uploader 实际到达。

## 2026-06-11 Canonical v8.46 sync kernel completion 验证

本轮新增/更新验证重点：

- iPhone inventory builder 在 background path 构建真实 local manifest/inventory facts，不发 fake mainActor `count=0` telemetry。
- 同一 iPhone `syncRunID` 内 duplicate runtime snapshot 复用并报告 duplicate build count。
- Mac `manifest.recordings` 只在显式 existence apply config + port 注入时写 canonical metadata-only ledger。
- 默认 Mac `StudyLibraryStore` 不写 canonical ledger，legacy apply 行为保持。
- Completion scorecard targeted tests 仍要求 real-device evidence 缺失时不能升级为真机完成。

本轮已运行并通过：

```sh
xcrun simctl list devices available
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild test -quiet -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests -resultBundlePath /private/tmp/Rokurics-v846-ios-inventory-all-1140.xcresult
xcodebuild test -quiet -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/StudyLibraryStoreTests -resultBundlePath /private/tmp/Rokurics-v846-mac-study-store-1158.xcresult
xcodebuild test -quiet -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests -resultBundlePath /private/tmp/Rokurics-v846-ios-completion-1200.xcresult
xcodebuild test -quiet -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests -resultBundlePath /private/tmp/Rokurics-v846-mac-completion-1201.xcresult
```

说明：一次并发 iOS/Mac test 尝试遇到 Xcode `build.db` lock，改为串行 rerun 后通过。当前仍未运行 paired iPhone/Mac real-device manual switch runbook；因此不能报告 real-device evidence 或 release/default canonical readiness。

## 2026-06-08 Canonical sync kernel finalization 验证

本轮新增/更新验证重点：

- iPhone/Mac `StudyLibraryStore` effective read path：default legacy、guarded fullsync canonical serve、divergence fallback、no sync/upload/store mutation。
- iPhone `RecordingUploadCoordinator` canonical audio owner：主开关允许时进入 real canonical executor，默认/手动按钮/view refresh/retry fresh job 保持 legacy/block。
- `CanonicalSwitchBackRealisticRootHarness`：test-cloned realistic root 下证明 legacy-readable switch-back、crash recovery、no physical delete、no legacy retirement。
- `CanonicalSyncKernelCompletionDomainReadiness`：12 域 completion matrix、`unsafe` status、realistic-root switch-back gate readiness。
- Runbook stop conditions 包含 `ExistingDifferentAudioBlocked` 和 security route failure。

本轮已运行并通过：

```sh
git diff --check
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
```

仍需运行/产生：paired iPhone/Mac real-device manual switch runbook evidence。unit tests、simulator tests、builds 和 test-cloned-root harness 不能替代真机 evidence。

## 2026-06-07 Canonical v8.45 completion gate / manual switch runbook 验证

本轮测试重点：

- `CanonicalSyncKernelCompletionScorecard` 任一 domain/code item 不完整必须阻断。
- 所有 code item 完成但无 paired-device logs 时必须为 `codeCompleteNeedsDeviceEvidence`。
- `CanonicalSyncKernelManualSwitchGate` 缺 backup acknowledgement、缺 switch-back proof 或 release/default canonical 时必须 blocked。
- Gate 通过只允许 manual trial，不允许 release default。
- `CanonicalSyncKernelEvidenceExporter` 必须 redacted，不能输出绝对路径、secret/token、完整 hash、request/response body 或用户内容。
- Runbook 必须明确 No legacy retirement、Do not delete legacy 和 `retirementExecutionPerformed=false`。
- Domain ready-to-retire report 必须 report-only，永不执行 legacy deletion/disable。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalSyncKernelCompletionTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalSyncKernelCompletionTests
```

说明：v8.45 tests 只证明 completion gate、manual switch gate、evidence redaction 和 runbook/report-only 合同。它不表示 paired-device canonicalFullSync 已完成，不表示 release default 可切 canonical，也不表示 legacy path 可删除。

## 2026-06-07 Canonical v8.44 legacy compatibility and switch-back proof 验证

本轮测试重点：

- `CanonicalLegacyCompatibilityMatrix.defaultV844()` 必须覆盖七个域，并证明 canonical write legacy-readable、legacy write canonical-readable、switch-back no migration、无 canonical-only required field、unknown fields backward compatible、rollback available、diagnostics redacted。
- 每个域必须覆盖 legacy writes -> canonical reads、canonical writes -> legacy reads、canonical writes -> switch old -> legacy modifies -> canonical reads again。
- partial canonical write failure 必须 rollback，随后 legacy read 仍看到旧数据。
- canonical diagnostics 不得改变数据格式 fingerprint。
- `oldKernel` 在 canonicalFullSync 写入后必须可读且 no crash。
- crash/restart 覆盖 before checkpoint、after checkpoint before write、after write before postcondition、after postcondition before duplicate suppression，并分别在 oldKernel 和 canonicalFullSync restart 下证明 no data loss、old kernel can read、incomplete state recovered or blocked、no physical delete。
- switch-back runtime harness 必须执行 canonical action set -> switch oldKernel -> legacy sync/read/modify -> compare -> switch canonicalFullSync -> compare again。
- 本轮仍不得声称 legacy deletion、release default cutover 或真实 paired-device full-sync 已完成。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalLegacyCompatibilityTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLegacyCompatibilityTests
```

建议回归补充：

```sh
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests -only-testing:RokuricsTests/CanonicalSyncRuntimeTests -only-testing:RokuricsTests/CanonicalApplyRuntimeTests -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeCommitTests -only-testing:RokuricsTests/CanonicalReadRuntimeTests -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests -only-testing:RokuricsMacTests/CanonicalApplyRuntimeTests -only-testing:RokuricsMacTests/CanonicalAudioUploadRuntimeCommitMacTests -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
```

说明：v8.44 tests 是格式/状态机兼容证明，不替代真实 iPhone/Mac paired-device full-sync 诊断。主开关切到 main/release 之前仍需要人工确认、真实设备证据和 no legacy deletion 审计。

## 2026-06-07 Canonical v8.43 unified kernel switch 验证

本轮测试重点：

- default `CanonicalKernelSwitchConfiguration` 必须解析为 `oldKernel`。
- `oldKernel` 必须映射所有 canonical owner config 为 disabled。
- `diagnosticsOnly` 不得产生 commit、upload job、network/send 或 canonical read serve。
- `canonicalFullSync` 必须 DEBUG/internal only，并要求 owner approval、manual confirmation、non-release/default。
- release/default 必须 block `canonicalFullSync`。
- 从 `canonicalFullSync` 切回 `oldKernel` 必须不需要 migration。
- mixed advanced override 与主开关冲突时必须 `blocked`。
- sync/apply/existence/audio/read legacy fallback 必须保留。
- shadow compare 必须在 shadow/full sync 语义下保留。
- Settings persistence 必须 normalize mode 并映射到主开关 result。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25' -only-testing:RokuricsTests/CanonicalKernelSwitchTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests
```

本轮已运行并通过：

- `xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25 -only-testing:RokuricsTests/CanonicalKernelSwitchTests`
- `xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination platform=macOS -only-testing:RokuricsMacTests/CanonicalKernelSwitchTests`

说明：v8.43 tests 证明主开关映射、reversibility gate、release/full-sync block、fallback retained、shadow compare retained 和 settings persistence 行为。它不表示 release 已切新内核，也不表示 legacy path 可删除。真实 full sync 前仍需要 paired-device diagnostics 和人工确认。

## 2026-06-07 Canonical v8.42 read runtime v1 验证

本轮测试重点：

- default `CanonicalReadRuntimeConfiguration` 必须 disabled，并返回 legacy read。
- `parallelCompare` 必须返回 legacy，同时构建 canonical diff/equivalence。
- `canonicalReadCandidate` 可以构建 canonical，但不得 serve canonical。
- `guardedCanonicalReadWithLegacyFallback` 必须在 evidence 齐全、debug/internal owner-approved、manual approval、release/default disabled、divergence=0 且 legacy fallback available 时才 serve canonical。
- divergence、unsupported object、path/content leak risk 或 gate blocker 必须 fallback legacy。
- read evaluation 不得触发 sync/upload，不得创建 upload job，不得 mutate store/write production data/move resource。
- read projections 与 diagnostics 必须 redacted，不输出 absolute path、full hash、secret、request/response body 或完整 content。
- iPhone adapter 默认 legacy；显式 guarded mode 可 serve canonical projection；失败时 fallback legacy，且不创建 upload job。
- Mac adapter 默认 legacy；显式 guarded mode 可 serve canonical projection；失败时 fallback legacy，且不改 inventory response、`receive.json`、audio inbox 或 transcription/note pipeline。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalReadRuntimeTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalReadRuntimeTests
```

说明：v8.42 测试通过只表示 read runtime provider、diff/gate/redaction、iPhone adapter 和 Mac adapter 的代码路径可验证。它不表示 default/release 已切 canonical read，不表示 legacy read path 可删除，也不表示真实 Store/UI 已完成生产切换。真实启用前仍需要 debug/internal owner approval、paired-device evidence 与 clean divergence report。

## 2026-06-07 Canonical v8.41 audio upload runtime commit v1 验证

本轮测试重点：

- default `CanonicalAudioUploadRuntimeConfiguration` 必须 disabled，并返回 legacy fallback。
- `diagnosticsOnly` 和 `noCommit` 只评估 would-upload，不创建 job、不发网络。
- `testTransportUpload` 可用 fake/test transport 验证 start/status/chunk/finalize。
- `canonicalUploadWithLegacyFallback` 必须 debug/internal owner-approved，release/default blocked，failure 在安全场景 fallback legacy。
- local audio + peer metadataOnly/receiveRecordOnly/studyItemOnly 是 upload candidate；peerUnknown deferred；same hash+size no-op；different hash/size conflict；completed ledger alone rejected。
- chunk offset deterministic，confirmedBytes monotonic，duplicate chunk idempotent，wrong offset fails/retries。
- finalize hash/byteSize mismatch 必须 failed/conflict，不能 mark uploaded 或 ledger completed。
- retry job persistence 可 resume offset，且不保存 absolute path/full hash。
- iPhone adapter 必须走 existing secure upload client path，不新增 route，不绕过 pinning/HMAC/nonce/body hash；viewRefresh 不创建 job；retryDrainer 只 replay existing retry。
- Mac route allowlist / `RequestVerifier` 不变；chunk/status/resume/finalize 语义不变；audio inbox/final file 只在 verified finalize 后写；existing different audio conflict/no overwrite。
- diagnostics 必须 redacted，不输出 full path/hash。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalAudioUploadRuntimeCommitTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalAudioUploadRuntimeCommitMacTests
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalAudioUploadCutoverPreparationTests -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/RokuricsTests
```

本轮已运行的核心新增测试通过：iPhone `CanonicalAudioUploadRuntimeCommitTests` 7 个用例通过，Mac `CanonicalAudioUploadRuntimeCommitMacTests` 3 个用例通过；v8.12 audio cutover preparation 与 v8.38 sync runtime selected regressions 通过。完整 `RokuricsTests/RokuricsTests` 在当前 dirty workspace 下仍有既有失败，包含一个可单独复现的 legacy resumable progress failure：`resumableNetworkFailurePreservesProgressInCoordinatorLedger()` 期望 `uploadProgressConfirmedBytes == 3`，实际为 `nil`。因此本轮不能声称 existing full upload/resumable suite 全绿。

说明：v8.41 单元测试通过只表示 canonical runtime executor、session state machine、fake/test transport adapter、retry persistence/redaction 和 Mac static route/postcondition guard 可验证。它不表示 default/release 已切 canonical，不表示 legacy fallback 可删除，也不表示真实长录音上传已完成。真实完成必须按 `docs/LongRecordingTestPlan.md` 运行 paired-device long-recording upload，确认 existing secure transport、resume/finalize、Mac hash/size/inbox postcondition 和 no-overwrite 行为。

## 2026-06-07 Canonical v8.40 apply runtime owner v1 验证

本轮测试重点：

- default `CanonicalApplyRuntimeConfiguration` 必须 disabled，并保留 legacy apply owner/fallback。
- `diagnosticsOnly` 和 `noCommit` 不执行 commit，不 suppress legacy。
- `testRootApply` 可以执行启用的 non-audio action；`productionRootApplyWithLegacyFallback` 在 release/default 必须 blocked。
- registry 必须覆盖 `recordingMetadata`、`libraryMetadata`、`generatedArtifacts`、`tombstoneConflict`、`recordingExistence`，缺 executor 或 dry-run-only executor 必须 blocked/fallback。
- `audioUpload` / audio artifact action 必须 blocked，不写 audio bytes，不创建 upload job。
- 每个 action 必须串行执行 precondition、rollback checkpoint、commit、postcondition 和 diagnostics；rollback failure 是 fatal。
- duplicate legacy suppression 只允许 canonical success + exact match；blocked/failure/noCommit/diagnostics 不 suppress。
- iPhone `performTick` 默认行为不变；显式 test/debug config 才可执行 non-audio apply；不改 retry drainer/UI/read path。
- Mac server default apply 不变；显式 config 下只能通过 v8.40 gate 进入 v8.39 existence metadata-only ledger bridge；route/security/receive.json/audio bytes 不变。
- diagnostics 必须 redacted，不输出完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint、request/response body、transcript/note/summary/provider output 或 standalone note content。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalApplyRuntimeTests -only-testing:RokuricsTests/CanonicalSyncRuntimeTests -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsTests/CanonicalLibraryMetadataCutoverTests -only-testing:RokuricsTests/CanonicalGeneratedArtifactCutoverTests -only-testing:RokuricsTests/CanonicalTombstoneConflictCutoverTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalApplyRuntimeTests -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests -only-testing:RokuricsMacTests/CanonicalExistenceApplyBridgeTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCutoverTests -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactCutoverTests -only-testing:RokuricsMacTests/CanonicalTombstoneConflictCutoverTests
```

说明：v8.40 测试通过只表示 non-audio apply runtime owner、gate、registry、rollback/postcondition、success-only duplicate suppression 和 diagnostics redaction 的代码路径可验证。它不表示 audio upload runtime 已迁移，不表示 read path/UI/route/security 可改变，也不表示 legacy 可删除。真实完成标准还需要 paired-device apply diagnostics，确认 explicit debug/internal apply 后 legacy fallback/suppression、Mac existence ledger、upload owner 和 route/security 边界都符合预期。

## 2026-06-07 Canonical v8.39 existence/apply bridge runtime v1 验证

本轮测试重点：

- `CanonicalRecordingExistenceTruth` 必须区分 absent、metadataOnly、receiveRecordOnly、studyItemOnly、metadataAndStudyItem、audioAvailable、audioHashSizeMatched、audioConflict、peerUnknown、tombstoned 和 unsupported。
- metadataOnly、receiveRecordOnly、studyItemOnly 和 completed ledger alone 都不得当 audioAvailable/audio uploaded/no-op。
- same hash + same byteSize 才是 audio no-op；different hash 或 size 必须 conflict；peerUnknown 必须 deferred；tombstoned parent 必须阻断 apply/upload。
- `manifest.recordings` 可生成 metadata-only existence apply candidate；Mac bridge 在 test root 下创建 placeholder/ledger，不写 audio file、不写 receive.json、不 mark upload completed。
- existing same placeholder no-op；existing different audio conflict；rollback 必须恢复 previous absence 或 previous record。
- Mac inventory 必须把 metadata-only existence 暴露为 peer recording exists，但 `audioAvailable=false`，无 proven audio 时不报告 hash/byteSize/path。
- iPhone local audio + peer metadataOnly 必须通过 existing evaluator 形成 upload candidate；same hash+size no-op；peerUnknown defer；different hash/size conflict；viewRefresh 和 retryDrainer 不创建 fresh unrelated job。
- 不新增 route、不改 upload route、不绕过 security、不切 read path、不删除 legacy。
- diagnostics 必须 redacted，不输出完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint 或 request/response body。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalRecordingExistenceTruthTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalExistenceApplyBridgeTests
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalSyncRuntimeTests -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests
```

说明：v8.39 测试通过只能证明 existence truth、metadata-only apply bridge、rollback/postcondition、inventory merge 和 upload-candidate diagnostics 的代码路径正确。它不表示真实新录音已经完成 iPhone->Mac 闭环；真实完成必须额外跑 paired-device 新录音验证，确认 Mac 消费 `manifest.recordings`、出现 metadata-only peer existence、iPhone 产生 peer metadataOnly upload candidate、existing secure upload coordinator 创建 audio job、Mac 最终收到音频。

## 2026-06-07 Canonical v8.38 sync decision runtime v1 验证

本轮测试重点：

- default `CanonicalSyncRuntimeConfiguration` 必须 disabled，默认/release 继续 legacy owner。
- `diagnosticsOnly` 不改变 owner；`canonicalPlanNoCommit` 只记录 would-use，不 suppress legacy。
- primary mode 必须要求 debug/internal + owner approval，release/default 必须 blocked。
- primary mode 缺 v8.37 snapshot、schema mismatch、unsupported object、fallbackRequired object、conflict、peer unknown audio 或 invalid manifest 时必须 fallback legacy。
- same canonical metadataHash + different legacy hash 必须是 canonical metadata no-op，且记录 legacy hash mismatch ignored。
- modifiedAt/LWW 必须 deterministic；equal modifiedAt tie 不得自动 overwrite。
- duplicate guard 只 suppress exact same object/action/scope，且只有 canonical actual primary owner 时生效。
- iPhone `performTick` default behavior unchanged；diagnosticsOnly 只比较；primary allowed 只接管 metadata scope，不新建 upload job，不切 read path。
- Mac inventory default response unchanged；missing peer snapshot blocks primary；diagnostics 只记录 blocked/fallback，不改 route/security/`receive.json`/audio inbox。
- diagnostics 必须 redacted，不输出完整 metadata JSON、完整 hash、绝对路径、secret、fingerprint 或 request/response body。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalSyncRuntimeTests
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/RokuricsTests/localNetworkSyncEngineDefaultRuntimeDoesNotUseCanonicalPrimary -only-testing:RokuricsTests/RokuricsTests/localNetworkSyncEnginePrimaryRuntimeUsesCanonicalMetadataNoOpWithoutAudioJob
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalSyncPlannerTests -only-testing:RokuricsTests/CanonicalLibrarySyncPlannerTests -only-testing:RokuricsTests/CanonicalApplyPlanTests -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests -only-testing:RokuricsTests/CanonicalAudioUploadCutoverPreparationTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalSyncRuntimeTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalSyncPlannerTests -only-testing:RokuricsMacTests/CanonicalLibrarySyncPlannerTests -only-testing:RokuricsMacTests/CanonicalApplyPlanTests -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests -only-testing:RokuricsMacTests/CanonicalAudioUploadCutoverPreparationTests
```

说明：v8.38 测试通过只表示 canonical plan 可作为 guarded decision candidate。它不表示 default/release canonical primary、production apply、production-root write、upload runtime cutover、read path cutover、route/security change、legacy fallback removal 或 v8.39 apply/existence bridge 已完成。真机完成标准还需要 paired-device diagnostics 证明 `canonicalSyncRuntimePlanUsed/Fallback/Blocked` 与 duplicate guard 行为。

## 2026-06-11 Canonical v8.47 P0-2 persistent checksum cache 验证

本组测试只验证 inventory/canonical snapshot 性能发动机：persistent checksum cache 真落盘、真命中、hit 跳过 hash provider、miss/stale 后台重算、cache corruption fail closed、bounded prune 和真实 telemetry。它不表示 sync decision、apply、upload、read path、主开关语义、route/security、legacy fallback 或 P1 domain 有任何改变。

重点覆盖：

- cache key 包含 safe logical token、byte size、mtime/contentVersion、hash algorithm、schema version、node role/platform role 和 namespace；logical token 变化 miss，size/mtime/contentVersion/algorithm/schema 变化 stale。
- cache record 内部保存 hash，diagnostics 只输出 hash prefix；不得输出完整 hash、绝对路径、secret、完整 fingerprint、完整 metadata JSON 或内容。
- 第一次构建 miss/hashComputed；第二次同数据 hit 且 fake hash provider count 不增加；重建 `CanonicalChecksumCacheStore` 且使用同一 cache root 后仍 hit，模拟 app restart。
- 修改 mtime 或 size 后 stale 并重新 hash；schema mismatch、corrupt root/record 或 partial temp file fail closed，系统继续运行。
- prune 按 oldest computedAt/LRU-like 顺序删除 cache record，且测试证明 non-cache 文件不被删除。
- telemetry duration 来自 fake clock/真实 measurement，count 来自 runtime counter/detector，不允许硬编码 fake count=0；mainActor attempt > 0 进入 performance report blocker/warning，但不改变 sync。
- iPhone `performTick` 每个 syncRunID 单 snapshot，canonical shadow/readiness/end-of-tick success 复用 snapshot/cache-backed facts；view refresh 不创建 upload job，retry drainer 与默认 sync plan 保持等价。
- Mac `/sync/inventory` response schema、`receive.json`、audio inbox 和 `RequestVerifier` 不变；cache-backed facts 可复用，但当前 Mac builder 仍 `@MainActor`，测试/报告必须如实记录。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests
```

当前仓库没有独立的 `CanonicalInventoryChecksumCacheTests` 或 `CanonicalInventoryTelemetryTests` test class 时，相关用例集中放在 `CanonicalInventoryRuntimeTests`。真机完成标准仍需要 paired-device before/after diagnostics：inventoryBuildDurationMs、cacheHit/Miss/Stale/Error、hashComputedCount、duplicateBuildCount、mainActor attempt counts、redacted diagnostics path 和 UI latency 体感记录；没有真机日志时必须报告 `not run; no real-device evidence produced.`

## 2026-06-07 Canonical v8.37 inventory runtime v1 验证

本轮测试重点：

- persistent checksum cache key 随 byte size、mtime、hash algorithm/schema/node role 变化而 stale。
- cache hit 必须避免重新 hash；cache miss/stale 必须后台 hash；cache corruption 必须 fail closed。
- hashUnavailable 不得作为 equality proof。
- snapshot/report/exporter 必须 redacted，不输出绝对路径、完整 hash、完整 metadata JSON、内容、secret、fingerprint 或 request/response body。
- iPhone `performTick` 每个 syncRunID 只构建一次 local runtime snapshot，末尾 success/shadow/readiness/diagnostics 复用同一份 snapshot/inventory。
- Mac `/sync/inventory` 和 inventory-backed artifact lookup/status 使用 cache-backed runtime；canonical shadow 不额外扫描 inbox。
- v8.46 后 iPhone background inventory 的 main-actor attempt/blocker count 必须为 0；当前 Mac inventory 若仍报告 blocker count，则代表未完成 off-main，而不是 passing signal。
- 外部 sync 行为必须 legacy-equivalent：不接管 diff/apply，不改 wire schema，不改 upload job creation/retry/Mac pending sync/route/security/read path。
- 真机完成标准需要 real-device diagnostics：cache hit/miss/stale、duplicate build count、mainActor blocker count，以及同步 UI latency 体感改善。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalInventoryRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalInventoryCoverageTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalInventoryRuntimeTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalInventoryCoverageTests
```

## 2026-06-07 LibraryMetadata real-device debug switch 验证

本轮测试重点：

- UserDefaults 缺省必须为 `off`，并映射到 `.disabled + nil executor`。
- `diagnosticsOnly` 只映射到 `.diagnosticsOnly(...)`，不注入 executor。
- `armTestRootN1` 与 `executeTestRootN1` 必须使用系统临时 test root，通过现有 bootstrap 注入 executor，且不得允许 production root write。
- `executeProductionRootN1` 必须要求 UI confirmation 与安全 production root；未确认或无 root 时必须 fail closed。
- 只有 `executeProductionRootN1` 可得到 `allowProductionRootWrites=true`。
- iPhone `MacConnectionView` 与 Mac `RokuricsMacApp.makeSecureReceiverService()` 的默认构造仍不注入 executor。
- Settings 中显示的 diagnostics 路径不得包含完整本机用户名路径。
- Mac certificate fingerprint 日志必须 prefix-only，不得输出完整 fingerprint。
- 测试/构建通过不等于真机验证；真实完成需要真机 `connection-diagnostics.jsonl` / `canonical-shadow.jsonl`。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataProductionRootPilotTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalMigrationMatrixTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataProductionRootPilotTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests
```

## 2026-06-06 v8.32 libraryMetadata N=1 evidence audit / N=3 readiness gate 验证

本轮测试重点：

- 缺少 v8.31 N=1 evidence 必须返回 `missingEvidence` 并阻断 N=3 readiness。
- valid redacted N=1 evidence 可以得到 `readyForN3AfterManualAudit`，但 gate 必须 `reportOnly=true` 且 `n3ExecutionAttempted=false`。
- invalid evidence、rollback failure、read-side divergence、unsafe side effect、other active domain、runtimeSwitch=true、release/default enabled、duplicate suppression without commit success 和 sensitive data leak 均 blocked。
- Post-run invariant 覆盖 exactly 0/1 executed candidate、metadata-only kind、no resource move/content write/generated artifact/audio/tombstone/delete、no read path/UI switch、legacy fallback available、other domains staticOnly。
- Mac route boundary / RequestVerifier violation 与 unexpected `receive.json` mutation 作为 evidence blocker 处理，不改 server route 或安全校验。
- Evidence exporter 必须 redacted；不输出完整 metadata JSON、note/transcript/summary/provider content、绝对路径、完整 hash、secret、fingerprint 或 request/response body。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataPilotEvidenceTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalMigrationMatrixTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataPilotEvidenceTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests
```

说明：v8.32 测试通过只表示 evidence audit/readiness gate 行为正确；不表示已完成真实 v8.31 N=1 pilot，不授权执行 N=3，不授权 default/release canary、read path cutover、UI change、legacy deletion/fallback disable 或其它 domain active pilot。

## 2026-06-06 v8.31 libraryMetadata production-root N=1 pilot 验证

本轮测试重点：

- `productionRootExplicit` 默认/release/allow=false blocked；runtimeSwitch、N>1、allEligible、non-libraryMetadata domain 均 blocked。
- explicit debug/internal + ownerApproved + LandingFreeze green + v8.30 evidence + read-side divergence zero + rollback evidence + productionRootBound executor 可构造 gate。
- iPhone/Mac 显式 productionRootURL 指向临时 root 时，可执行一个 safe folder metadata candidate，验证 root-bound bytes、atomic write、postcondition、read-side equivalence、success-only duplicate suppression 和 redacted safety proof。
- root containment、checkpoint、postcondition、rollback failure、unsafe candidate、resource move、content write/tombstone/delete 信号均 blocked 或 rollback/fallback。
- 默认 app/read/UI 不变；legacy fallback 保留；其它 domains staticOnly；RequestVerifier 和 `/sync/apply-metadata` route 边界不变。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataProductionRootPilotTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalMigrationMatrixTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataProductionRootPilotTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests
```

说明：v8.31 测试通过只表示可以进行一次人工 production-root N=1 pilot 和 Claude 审计；不表示可默认启用、扩大到 N>1/allEligible、切 read path、改变 UI、删除 legacy、移除 fallback 或启用其它 domain。

## 2026-06-06 v8.30 libraryMetadata diagnostics / arm / test-root drill 验证

本轮测试重点：

- `diagnosticsOnly` 默认不启用；显式配置时运行 LandingFreeze，但不选 candidate、不 commit、不 suppress legacy，并导出 redacted safe summary。
- `armN1Canary` 显式配置时只产生 N=1 readiness report；不需要 executor，不写 test root/production root，不 suppress legacy。
- `executeN1Canary` 默认 disabled；显式 internal/test + testRoot apply port 可提交一个 safe metadata-only candidate，并验证 rollback checkpoint/postcondition/read-side equivalence。
- `productionRootExplicit` 与 `allowProductionRootWrites=true` 在 v8.30 均 blocked；双端 bootstrap 不构造 production-root apply port/executor。
- LandingFreeze 覆盖非 `libraryMetadata` active pilot、runtimeSwitch、read path non-legacy、production injection/root write、fallback missing、N>1、allEligible、unsafe/resource/content/tombstone allowance。
- 默认 app/release 路径仍 disabled，read path legacy，UI unchanged，legacy fallback retained，其它 domains staticOnly。

目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataObservationTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalMigrationMatrixTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataLandingTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataObservationTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests
```

## 2026-06-06 v8.29 libraryMetadata real-device pilot landing 验证

本轮新增双端 `CanonicalLibraryMetadataLandingTests`，覆盖重点：

- debug/internal pilot config 默认 disabled，strict N=1 libraryMetadata-only，release/default/runtime switch 均关闭。
- `CanonicalMigrationLandingFreeze` 只允许 activePilot=`libraryMetadata`；generatedArtifacts/tombstoneConflict 等历史 active-pilot matrix 在 v8.29 landing 中会被 freeze blocker 拦截。
- diagnosticsOnly 和 armed N1 都不 commit、不 suppress duplicate，仍保留 legacy fallback/read path。
- iPhone 与 Mac 均用 real test-root apply port 执行一个 safe folder metadata candidate，验证 root-bound bytes、postcondition、landing diagnostics、read-side equivalence 和 success-only duplicate suppression。
- unsafe resource move、production-root default-disabled、read-side divergence、runtime switch、generatedArtifacts active pilot、Mac inventory peer snapshot missing 均 blocked/fallback/no suppression。
- Mac server inventory seam 只记录 landing blocked/fallback/report diagnostics，不改 response、route/security、`receive.json`、audio inbox 或 pending sync。

本轮实际验证命令：

```sh
xcodebuild test -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RokuricsTests/CanonicalLibraryMetadataLandingTests
xcodebuild test -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLibraryMetadataLandingTests
xcodebuild test -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RokuricsTests/CanonicalLibraryMetadataObservationTests -only-testing:RokuricsTests/CanonicalMigrationMatrixTests
xcodebuild test -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLibraryMetadataObservationTests -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests
xcodebuild -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
git diff --check
git status --short
```

结果：iPhone landing tests 10 个用例通过；Mac landing tests 6 个用例通过；双端 observation/migration matrix 回归通过；iPhone Debug build 与 Mac Debug build 通过。Mac 命令仍有既有 multiple destination warning、actor isolation warning、whisper helper embed script 提示，不影响本组通过结果。

## 2026-06-05 v8.28 tombstoneConflict canary N=1 验证

本轮新增双端 `CanonicalTombstoneConflictCanaryTests`，覆盖重点：

- default configuration 仍 disabled，默认 canary budget 为 0；显式 app seam N=1 才能形成 strict N1 config。
- N=1 要求 activePilot=`tombstoneConflict` 且无其它 active pilot；non-tombstoneConflict matrix、N>1、allEligible、runtimeSwitch 均 blocked。
- selector 稳定排序且最多选 1 个 executable candidate，优先 conflict record / resurrection block，再到 soft object/library tombstone marker；generated artifact tombstone marker 仅 report-only。
- safe soft marker / conflict record candidate 可通过 fake executor 或 test-root real apply port 执行一次；成功记录 postcondition/read-side diagnostics，并只在 canonical success 后 suppress matching tombstoneConflict duplicate。
- physical delete、permanent delete、tombstone GC、restore、clear tombstone、ambiguous conflict auto-resolution、stale live resurrection、generated artifact apply/download、audio/full-content action、unsafe path、missing rollback checkpoint 均在 commit 前 blocked。
- commit/postcondition failure 必须 rollback/fallback 且不 suppress；rollback failure 是 fatal blocker。
- iPhone default seam 不记录 N1 diagnostics、不创建 upload job、不调用 artifact/apply client；显式 N1 无 eligible candidate 时仅 diagnostics/fallback。
- Mac explicit N1 fake/test-root executor 覆盖 safe commit；缺 peer snapshot 时 blocked/fallback；不写 receive.json、不写 audio inbox、不触发 transcription/note generation、不改 route/security。

本轮目标验证命令：

```sh
git diff --check
git status --short
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictCanaryTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictGuardedCommitSeamTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTombstoneConflictCanaryTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTombstoneConflictGuardedCommitSeamTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTombstoneConflictReadSideTests
```

说明：v8.28 测试通过不表示可以默认启用、扩大到 N>1/allEligible、切 read/UI、迁移 generatedArtifacts/audioUpload/recordingMetadata/libraryMetadata、改变 retry drainer/Mac pending sync/upload routes 或删除 legacy。v8.29 只能在 v8.28 observation 人工审计后讨论。

## 2026-06-05 v8.27 tombstoneConflict active pilot guarded seam N=0 验证

本轮新增双端 `CanonicalTombstoneConflictGuardedCommitSeamTests`，覆盖重点：

- `CanonicalMigrationDomainMatrix.v827TombstoneConflictActivePilot(...)` 只把 `tombstoneConflict` 提升为唯一 active pilot，其它 domain 保持 static/default-off。
- 缺 generatedArtifacts/library template evidence 时 active pilot activation blocked。
- guarded seam 在证据齐全时只允许 N=0 gate evaluation，固定 `willExecuteNow=false`、commit skipped、legacy fallback preserved、duplicate suppression not applied。
- N1/staged/allEligible/runtime switch、缺 peer snapshot、缺 owner token、缺 evidence、unsupported action/domain 必须 blocked。
- physical delete、permanent delete、tombstone GC、restore、tombstone clear、stale live resurrection、ambiguous conflict policy 和 generated artifact tombstone marker apply 必须 blocked。
- iPhone tick seam 默认 disabled；显式 N=0 启用只记录 diagnostics，不调用 network client、不改 pending count、不创建 upload job、不改 UI/store/retry。
- Mac inventory seam 默认 disabled；显式启用也只记录 report-only diagnostics，不改 response、`receive.json`、audio inbox 或 Mac pending sync。

本轮实际验证命令：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictGuardedCommitSeamTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalMigrationMatrixTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalTombstoneConflictReadSideTests -only-testing:RokuricsTests/CanonicalTombstoneConflictCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalTombstoneConflictGuardedCommitSeamTests
```

结果：iOS build、macOS build、iPhone v8.27 seam tests、iPhone migration matrix tests、iPhone tombstone read-side/cutover tests 均通过。Mac v8.27 test bundle 编译完成，但两次运行均在 Xcode/LaunchServices runner 启动层失败，未进入测试断言；错误为 `IDELaunchServicesLauncher - Failed to Launch` / `No such process` 与 `childPID > 0` assertion。

## 2026-06-05 v8.26 tombstoneConflict template / read-side seam 验证

本轮新增双端 `CanonicalTombstoneConflictReadSideTests`，覆盖重点：

- `CanonicalTombstoneConflictTemplateReport.currentV826Audit()` 达到 `readyForNextPilotN0`。
- `CanonicalMigrationDomainMatrix.v826TombstoneConflictNextPilotCandidate(...)` 只把 `tombstoneConflict` 标为 `nextPilotCandidate`，不设为 active pilot，不打开 runtime switch，read path 仍 legacy。
- 缺 generatedArtifacts 模板/观察证据时，`tombstoneConflict.nextPilotCandidate` 保持 blocked。
- read projection 只输出 metadata-only 摘要，排除完整 metadata、完整 content、绝对路径和完整 hash，并对 path leak / full metadata / full content 记录 blocker。
- parallel diff 覆盖 equivalence、physical delete、permanent delete、tombstone GC、stale live resurrection 和 auto conflict resolution fatal blocker。
- anti-resurrection gate 对 stale live metadata resurrection 阻断；observation 默认 disabled；retirement candidate report-only blocked，固定不删除/禁用 legacy。
- iPhone/Mac read-side seam 默认 disabled；显式 enabled 也只记录 diagnostics，`storeMutated=false`、`uiMutated=false`、`uploadJobCreated=false`、`receiveJSONMutated=false`、`inventoryResponseMutated=false`、`audioInboxWritten=false`、`deleteAttempted=false`、`restoreAttempted=false`、`tombstoneCleared=false`、`conflictResolved=false`。

本轮实际验证命令：

```sh
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild test -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalTombstoneConflictReadSideTests
xcodebuild test -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalTombstoneConflictReadSideTests
git diff --check
git status --short
```

结果：iPhone `CanonicalTombstoneConflictReadSideTests` 6 个用例通过；Mac `CanonicalTombstoneConflictReadSideTests` 2 个用例通过。Mac 测试仍有既有多 destination warning、actor isolation warning 与 whisper helper build phase 提示，不影响通过结果。

## 2026-06-05 v8.25 generatedArtifacts read-side guarded seam / observation 验证

本轮新增双端 `CanonicalGeneratedArtifactReadCutoverTests`，覆盖重点：

- read source 默认 `legacy`；`parallelCompare` 返回 legacy output；`canonicalCandidate` 构建 canonical metadata/availability candidate 但不服务 UI。
- `guardedCanonicalRead` 在缺 explicit internal/test config、缺 write-side staged evidence、read divergence、unsupported artifact、contentLeakRisk、unsafePathToken、parent tombstone、audioConfusionRisk、fallback missing、其它 active domain、canonical projection missing 或 read exception 时 fallback legacy。
- gate 全部通过时可返回 canonical generated artifact metadata/availability output；output 排除 full transcript/note/summary、provider response、audio bytes 和 generated artifact upload state。
- iPhone/Mac read seam 默认 legacy；显式 guarded read 只返回 metadata/availability，不触发 sync/upload、不调用 `/sync/artifact-request`、不下载、不 apply、不写 generated artifact file、不改 UI/store/inventory/`receive.json`。
- observation window 记录 write-side staged canary evidence 与 read-side evidence；retirement candidate remains report-only，`retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。
- other domains 继续 staticOnly/defaultOff，runtimeSwitch=false，legacy fallback 保留。

本轮目标验证命令：

```sh
git diff --check
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactReadCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactCanaryStageTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactReadCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactCanaryStageTests
git status --short
```

说明：本组测试只验证 generatedArtifacts read-side guarded seam / observation 的 default legacy、explicit guarded canonical metadata/availability output、fallback、redacted diagnostics、no side effects 和 report-only retirement candidate。它不表示可以默认切 read path、改 UI、调用 `/sync/artifact-request`、下载/apply artifact、创建 upload job、自动下载 audio、改 route/security、迁移 retry drainer/Mac pending sync 或删除 legacy。

## 2026-06-05 v8.21 generatedArtifacts template / read-side seam 验证

本轮新增双端 `CanonicalGeneratedArtifactReadSideTests`，覆盖重点：

- read projection 只输出 metadata/availability 摘要，排除正文、完整 hash、真实路径和 audio bytes。
- unsafe logical path token、audio confusion、unsupported `summaryMarkdown` 会成为 read-side fatal blocker。
- legacy/canonical generated artifact read projection 等价时 divergence 为 0。
- observation window 默认 disabled；retirement candidate gate 默认 report-only blocked，固定不执行 retirement、不删除或禁用 legacy。
- template audit 达到 `readyForNextPilotN0` 时，matrix 仍要求 `libraryMetadata` observation complete 或 retirement candidate ready 才能把 `generatedArtifacts` 标记为 `nextPilotCandidate`。
- `nextPilotCandidate` 不成为 active pilot，不打开 runtime switch，不启用 audio/tombstone/legacy retirement。
- iPhone/Mac read-side seam 默认 disabled；显式 enabled 也只写 diagnostics，`storeMutated=false`、`uiMutated=false`、`artifactDownloaded=false`、`artifactApplied=false`、`uploadJobCreated=false`。

本轮实际验证命令：

```sh
git diff --check
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactReadSideTests
git status --short
```

结果：`git diff --check` 通过；iPhone `CanonicalGeneratedArtifactReadSideTests` 6 个用例通过；Mac `CanonicalGeneratedArtifactReadSideTests` 3 个用例通过。Mac 测试仍有既有多 destination warning 与 whisper helper build phase 提示，不影响通过结果。

## 2026-06-05 v8.20 libraryMetadata observation window / retirement candidate gate 验证

本轮新增双端 `CanonicalLibraryMetadataObservationTests` 与 `CanonicalLibraryMetadataRealCanaryTests`，覆盖重点：

- observation policy 默认 disabled，disabled window 不记录 event。
- explicit internal/test observation window 可记录 write-side canonical commit、read-side candidate、fallback、rollback、divergence、unsupported、unsafe side effect 等计数。
- observation gate 在 clean window 下进入 `completeReadyForRetirementCandidate`；divergence、rollback failure/fatal、unsupported、fallback missing、resource move/sync-upload 等会阻断。
- retirement candidate gate 只输出 report-only candidate；固定 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。
- v8.20 matrix report 只把 `libraryMetadata` 标为 observation complete / retirement candidate ready，`libraryMetadataPilotComplete=false`，其它 domain static-only。
- iPhone/Mac `observeReadSource(...)` hook 默认 disabled；显式 policy 只记录已有 read-source result，不触发 sync/upload、不移动资源、不写内容、不改 UI。
- diagnostics summary 不包含本机隐私路径。
- 新增 `CanonicalLibraryMetadataRealCanaryTests`，使用户指定的 real-canary 过滤器有实际测试用例。

本轮实际验证命令：

```sh
xcodebuild test -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RokuricsTests/CanonicalLibraryMetadataObservationTests
xcodebuild test -quiet -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RokuricsTests/CanonicalLibraryMetadataObservationTests
xcodebuild test -quiet -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RokuricsTests/CanonicalLibraryMetadataRealCanaryTests
xcodebuild test -quiet -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLibraryMetadataObservationTests
xcodebuild test -quiet -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLibraryMetadataRealCanaryTests
```

结果：`iPhone 16` destination 不存在，未进入编译/测试；改用本机可用 `iPhone 17` 后 iPhone observation tests 与 real-canary tests 均通过。Mac observation tests 与 real-canary tests 均通过。Mac 测试仍有既有多 destination、actor isolation warning 与 whisper helper embed 输出，不影响通过结果。

## 2026-06-05 v8.19 libraryMetadata guarded read-side cutover seam 验证

本轮新增双端 `CanonicalLibraryMetadataReadCutoverTests`，覆盖重点：

- read source 默认 `legacy`，`parallelCompare` 返回 legacy output 并记录 diff，`canonicalCandidate` 构建 canonical candidate 但不服务 UI。
- `guardedCanonicalRead` 在缺 explicit internal/test config、缺 write-side evidence、read divergence、unsupported object、pathLeakRisk、fallback missing 或其它 active domain 时 blocked/fallback legacy。
- gate 全部通过时可返回 canonical metadata-only output，并同时保留 legacy snapshot/equivalence summary。
- canonical projection missing 或 canonical read exception 时 fallback legacy。
- output 只覆盖 folder/study item/standalone note metadata；排除 audio state、generated artifact content 和 standalone note content。
- result 固定 `storeMutated=false`、`syncOrUploadTriggered=false`、`resourceMoved=false`、`contentWritten=false`、`uiMutated=false`。
- retirement candidate 可更新为 ready，但仍 `reportOnly=true`、`legacyDeleted=false`、`legacyDisabled=false`。
- diagnostics redacted，不写完整路径、完整 hash、完整 metadata JSON 或内容。

本轮实际验证命令：

```sh
git diff --check
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataReadCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataRealCanaryTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataProductionCanaryTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataReadCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataReadSideTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataRealCanaryTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataProductionCanaryTests
git status --short
```

结果：`git diff --check` 通过；iPhone Debug build 与 Mac Debug build 均通过；双端 `CanonicalLibraryMetadataReadCutoverTests`、`CanonicalLibraryMetadataReadSideTests`、`CanonicalLibraryMetadataProductionCanaryTests` 均通过。v8.19 执行时，请求中的双端 `CanonicalLibraryMetadataRealCanaryTests` 过滤条件返回 `TEST SUCCEEDED`，但当时源码中没有该测试类型，Xcode 输出未列出任何匹配测试用例；v8.20 已新增同名测试类型补齐该过滤器。

## 2026-06-05 v8.16 libraryMetadata expanded canary 验证

本轮新增双端 `CanonicalLibraryMetadataCanaryStageTests`，覆盖重点：

- stage policy 默认 disabled；`n3`、`n10`、`allEligible` 必须显式 stage policy 和 previous-stage clean evidence。
- N3 最多选择 3 个候选，N10 最多选择 10 个候选，allEligible 选择本 run 所有 eligible metadata candidate；选择顺序按 object kind、objectID、actionID 稳定。
- previous-stage failure、rollback failure、blocking divergence、unresolved conflict、postcondition failure、unsupported object、resource move、hierarchy cycle、objectID instability、read-side divergence、observation incomplete 都会阻断下一阶段。
- 多候选顺序执行，首个失败后 rollback 并停止；rollback 失败为 fatal blocker。
- duplicate legacy suppression 是 per-candidate success-only；mixed run 中成功 candidate 可 suppress，失败/未执行/跳过 candidate 保留 legacy fallback。
- read-side parallel 只记录 affected object diagnostics，observation report 固定 `runtimeSwitch=false`、`domain=libraryMetadata`、`uiMutated=false`、`resourceMoved=false`、`uploadJobCreated=false`。
- Mac fake peer + fake executor 覆盖共享 staged runner；真实 Mac inventory 缺 peer snapshot 时只能 report/fallback。

本轮实际验证命令：

```sh
git diff --check
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:RokuricsTests/CanonicalLibraryMetadataCanaryStageTests -only-testing:RokuricsTests/CanonicalLibraryMetadataCanaryTests -only-testing:RokuricsTests/CanonicalLibraryMetadataGuardedCommitSeamTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCanaryStageTests -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCanaryTests -only-testing:RokuricsMacTests/CanonicalLibraryMetadataGuardedCommitSeamTests
git status --short
```

结果：`git diff --check` 通过；iPhone Debug build 与 Mac Debug build 均通过；iPhone targeted tests 和 Mac targeted tests 均通过。iPhone targeted tests 曾因 stage gate 使用错误 evidence 字段失败一次，修正后同组测试通过。Mac build/test 仍有既有多 destination、actor isolation warning 与 whisper helper embed 输出，不影响通过结果。

说明：v8.16 测试不执行其它 domain，不新增 route，不切 UI/read path，不触发 retry drainer/Mac pending sync/upload runtime。

## 2026-06-05 v8.15 libraryMetadata canary N=1 验证

本轮新增双端 `CanonicalLibraryMetadataCanaryTests`，覆盖重点：

- `CanonicalLibraryMetadataCanaryConfiguration` 默认 disabled，显式 internal N=1 才满足 strict config。
- iPhone role N=1 canary 最多提交 1 个 safe metadata candidate，记录 configured/selected/commit/postcondition/read-side/observation diagnostics。
- N>1、allEligible、runtime switch 必须 blocked，不能提交或 suppress legacy。
- resource token/path 变化在 commit 前 blocked，legacy fallback preserved，不调用 executor。
- commit failure 会 rollback，保留 fallback，不 suppress duplicate legacy。
- Mac role 可在 fake peer + fake executor 下验证共享 N=1 runner；真实 Mac inventory 缺 peer snapshot 时记录 blocker/fallback。

本轮实际验证命令：

```sh
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RokuricsTests/CanonicalLibraryMetadataCanaryTests
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -only-testing:RokuricsTests/CanonicalLibraryMetadataCanaryTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCanaryTests
```

结果：`iPhone 16` destination 不存在，未进入编译/测试；改用本机可用 `iPhone 17` iOS 26.5 后 iPhone 新增测试 5/5 通过。Mac 新增测试 3/3 通过。Mac 测试期间仍有既有 actor isolation warning 和 whisper helper embed 输出，不影响通过结果。

## 2026-06-05 v8.14 libraryMetadata guarded commit seam N=0 验证

本轮新增双端 `CanonicalLibraryMetadataGuardedCommitSeamTests`，并扩展双端 `CanonicalMigrationMatrixTests` / `CanonicalLibraryMetadataCutoverTests`。覆盖重点：

- `CanonicalLibraryMetadataGuardedCommitSeam` 在 evidence/gate 允许时仍保持 canary budget `N=0`，不执行 commit。
- `CanonicalLibraryMetadataNoExecutionAssertion` 验证 production commit、real apply port、network send、`applySyncManifest`、metadata JSON write、duplicate suppression 和 runtime switch 均未发生。
- `CanonicalLibraryMetadataN1ReadinessReport` 只报告进入 N1 前的 blocker/status，不授权 N1。
- iPhone `performTick` 显式 v8.14 seam 只记录 diagnostics，不改变 legacy plan、不调用 apply/artifact client、不 suppress legacy duplicate。
- Mac `/sync/inventory` 显式 v8.14 seam 因 peer snapshot missing 记录 blocker，但 response 不变；default disabled 不发 v8.14 diagnostics。
- diagnostics summary redacted，不写完整 metadata JSON、完整 hash、request/response body、secret、fingerprint 或本机路径。

本轮实际验证命令：

```sh
xcodebuild -list -project Rokurics.xcodeproj
xcrun simctl list devices available
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination platform=macOS -only-testing:RokuricsMacTests/CanonicalLibraryMetadataGuardedCommitSeamTests
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25 -only-testing:RokuricsTests/CanonicalLibraryMetadataGuardedCommitSeamTests
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25 -only-testing:RokuricsTests/CanonicalMigrationMatrixTests -only-testing:RokuricsTests/CanonicalLibraryMetadataCutoverTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination platform=macOS -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCutoverTests
xcodebuild build -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25
xcodebuild build -project Rokurics.xcodeproj -scheme RokuricsMac -destination platform=macOS
git diff --check
git status --short
```

结果：上述 targeted tests 与双端 build 均通过。iPhone targeted seam test 曾有一次 destination 字符串解析失败，改用 simulator UUID 后通过；该失败不是源码或测试失败。Mac build/test 仍会出现既有 actor isolation/whisper helper 相关 warning，不影响本轮通过结果。

## 2026-06-05 v8.13 migration matrix 验证

本轮新增双端 `CanonicalMigrationMatrixTests`，覆盖：

- migration matrix 只允许一个 explicit active pilot，且只能是 `libraryMetadata`。
- `generatedArtifacts`、`tombstoneConflict`、`audioUpload` 在 v8.13 不能成为 active pilot。
- `runtimeSwitchEnabled=true`、release/default enabled cutover、read-side cutover 前 legacy retirement 均为 violation。
- `CanonicalLibraryMetadataPilotReport` 能识别现有 library metadata 机器件，也能在缺 read-side parallel readiness 时报告 blocker。
- 其它域保持 static-only/default-off/read-path-legacy。
- 默认 app seam config 仍 disabled，matrix 不改变 app behavior、不 suppress legacy duplicate。
- diagnostics summary 不写敏感路径。

本轮目标验证命令：

```sh
git diff --check
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalMigrationMatrixTests
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataCutoverTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCutoverTests
git status --short
```

说明：`CanonicalMigrationMatrixTests` 是 pure model/config guard 测试，不执行 canary、不调用 production port、不写真实 store、不发送网络、不改变 UI、retry drainer、Mac pending sync 或 upload routes。

## 环境要求

- macOS 与 Xcode：项目由 `Rokurics.xcodeproj` 管理，project `LastUpgradeCheck` 为 2640，target `CreatedOnToolsVersion` 为 26.4.1。
- iOS deployment target：26.4。
- macOS deployment target：26.4。
- Swift build setting：`SWIFT_VERSION = 5.0`。
- Mac app 需要 App Sandbox entitlements：`RokuricsMac/RokuricsMac.entitlements`。
- Mac 转写的 whisper.cpp helper：
  - 构建阶段执行 `Scripts/embed_whisper_helper.sh`。
  - 脚本优先读取 `WHISPER_CPP_ROOT`，否则回落到仓库外本地默认位置。
  - 需要已编译的 `whisper-cli` 和相关 dylib。
  - 文档不记录具体个人路径。
- iOS 测试需要可用 iOS Simulator；本轮确认可用 `iPhone 17 Pro` / iOS 26.5。

## 依赖安装方式

未发现 `Package.swift`、`Package.resolved`、CocoaPods、Carthage checkout、npm/yarn/pnpm 等依赖入口。当前项目主要依赖 Apple SDK/frameworks 和仓库外 whisper.cpp 编译产物。

需要后续确认：

- whisper.cpp 在新机器或 CI 上的安装/编译方式。
- 是否存在未提交或未纳入仓库的本地依赖准备步骤。

## 构建命令

本轮已用独立 DerivedData 路径实际运行 iPhone/Mac Debug build。

iPhone app build：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build
```

Mac app build：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build
```

注意：

- `RokuricsMac` build 会执行 `Embed whisper.cpp Helper`，缺少仓库外 whisper.cpp 产物或 `WHISPER_CPP_ROOT` 时可能失败。
- Mac Debug product name 在 scheme 中显示为 `RokuricsMac Local.app`。

## 单元测试命令

iPhone 单元/UI scheme 测试：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=<已安装模拟器名称>' test
```

Mac 单元/UI scheme 测试：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test
```

可按文件或测试名在 Xcode 中定向运行，或用 `-only-testing:` 缩小范围。本轮已验证：

```sh
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalCoreTests -only-testing:RokuricsTests/CanonicalShadowDiagnosticsTests -only-testing:RokuricsTests/CanonicalSyncPlannerTests -only-testing:RokuricsTests/CanonicalApplyPlanTests -only-testing:RokuricsTests/CanonicalLibraryObjectTests -only-testing:RokuricsTests/CanonicalLibrarySyncPlannerTests -only-testing:RokuricsTests/CanonicalTransferStateTests -only-testing:RokuricsTests/CanonicalObjectProjectionTests -only-testing:RokuricsTests/CanonicalInventoryCoverageTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalCoreTests -only-testing:RokuricsMacTests/CanonicalShadowDiagnosticsTests -only-testing:RokuricsMacTests/CanonicalSyncPlannerTests -only-testing:RokuricsMacTests/CanonicalApplyPlanTests -only-testing:RokuricsMacTests/CanonicalLibraryObjectTests -only-testing:RokuricsMacTests/CanonicalLibrarySyncPlannerTests -only-testing:RokuricsMacTests/CanonicalTransferStateTests -only-testing:RokuricsMacTests/CanonicalObjectProjectionTests -only-testing:RokuricsMacTests/CanonicalInventoryCoverageTests
```

2026-06-04 v8.11 本轮实际验证：

```sh
xcodebuild -quiet build -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25
xcodebuild -quiet build -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS'
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25 -only-testing:RokuricsTests/CanonicalTombstoneConflictCutoverTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalTombstoneConflictCutoverTests
xcodebuild -quiet test -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25 -only-testing:RokuricsTests/CanonicalApplyPlanTests
xcodebuild -quiet test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalApplyPlanTests
git diff --check
git status --short
```

2026-06-04 v8.12 audio upload preparation 本轮实际验证：

```sh
git diff --check
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalAudioUploadCutoverPreparationTests
xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalAudioUploadCutoverPreparationTests
xcodebuild build-for-testing -quiet -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild build-for-testing -quiet -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS,arch=arm64'
git status --short
```

结果说明：

- `git diff --check` 通过。
- iPhone `CanonicalAudioUploadCutoverPreparationTests` 的 test command 已完成 Swift 编译/打包，但 Simulator `iPhone 17` 启动失败，错误为 `Unable to boot the Simulator` / `launchd_sim` bind session failure，因此测试未实际执行。
- Mac `CanonicalAudioUploadCutoverPreparationTests` 的 test command 已完成编译/签名，但 Xcode 在启动测试宿主时触发 `IDELaunchServicesLauncher` assertion，测试未实际执行。
- 双端 `build-for-testing -quiet` 均通过，证明新增 v8.12 shared/app/test 文件可编译。

## 集成测试命令

没有发现独立集成测试 runner。当前集成性质覆盖分布在：

- `RokuricsTests/RokuricsTests.swift`：上传队列、resumable upload、本地网络同步、heartbeat、sync manifest。
- `RokuricsMacTests/RokuricsMacTests.swift`：HTTPS receiver、pairing、HMAC、resumable route、delete/restore。
- `RokuricsMacTests/StudyLibrarySyncTests.swift`：Git-backed sync 和本地网络同步 endpoint。

建议使用上面的 scheme test 命令，或在 Xcode 中定向运行相关 test file。

## UI 测试命令

UI tests 包含在两个 app scheme 的 TestAction 中：

- `RokuricsUITests`
- `RokuricsMacUITests`

命令同上 `xcodebuild ... test`。当前 UI 测试主要是 launch/performance 模板，真实业务 flow 仍需要手动验证。

## 静态检查 / lint / format

未发现 SwiftLint、SwiftFormat、format/lint 脚本或 package manifest。

基础文档/空白检查：

```sh
git diff --check
```

Swift 编译级静态检查建议使用对应 `xcodebuild ... build` 或 `xcodebuild ... test`。

## 手动验证矩阵

### iPhone 录音

- 首次麦克风授权。
- 开始、暂停、恢复、停止录音。
- 低电量/后台 audio mode 下计时和状态。
- 保存时选择 filing：type/subject/chapter/topic。
- 录音列表、学习库、废纸篓、恢复、永久删除。

### iPhone 到 Mac 配对和上传

- Mac 启动 HTTPS receiver，复制 pairing info。
- iPhone 粘贴 pairing info，确认 host/port/code/fingerprint 解析。
- `/health` 指纹 pinning 成功和失败。
- pairing code 过期、错误 code、重新配对。
- 小文件单请求上传。
- 大文件 resumable 上传、断点重试、冲突处理。
- 上传成功后 iPhone metadata 变为 uploaded，Mac Audio Inbox 出现 recording。

### Mac 转写和笔记

- Mock transcription。
- whisper.cpp bundled helper。
- 外部 debug fallback。
- m4a 转 WAV。
- 35-45 分钟触发 chunked transcription。
- 2-3 小时长录音按 `docs/LongRecordingTestPlan.md` 验证。
- note generation mock/OpenAI-compatible/Anthropic。
- 长 transcript 分段生成 sections 后合并 final note。

### 学习库和同步

- iPhone/Mac 两端相同 filing 层级浏览。
- metadata-only sync 不删除真实 audio。
- transcript/note/summary generated artifact 自动下载，且必须通过既有 `/sync/artifact-request`/apply 通道完成。
- audio 不自动下载，只通过上传队列补齐。
- folder rename/move/color/trash 不改变 itemID 和资源路径。
- 冲突场景保留可诊断状态。

### 同步状态回归计划

修改同步/上传状态机时，至少覆盖以下自动测试：

- Canonical Core shadow output：`RokuricsTests/CanonicalCoreTests.swift` 与 `RokuricsMacTests/CanonicalCoreTests.swift` 覆盖双端 adapter 输出 `CanonicalManifest`、metadataHash 业务字段合同、createdAt/duration/processing/audio facts 不参与 hash、Mac inbox fallback `updatedAt` 不进入 canonical `modifiedAt`、业务 study item edit 使用业务时钟、audio hash/size no-op/conflict、receive/upload display state 不反向证明 audio、generated artifact path token sanitization、Mac authoritative producer 与 iPhone non-authoritative downloaded artifact 投影。
- Canonical Shadow Diagnostics：`RokuricsTests/CanonicalShadowDiagnosticsTests.swift` 与 `RokuricsMacTests/CanonicalShadowDiagnosticsTests.swift` 覆盖 report 不修改 legacy input、hash prefix redaction、logical name sanitization、metadata converged/diverged、createdAt ignored、processing state ignored、Mac processing clock rejected、study-only、receive-only、same audio、unknown audio、conflict category 和 generated artifact category/redaction。
- Canonical Sync Planner：`RokuricsTests/CanonicalSyncPlannerTests.swift` 与 `RokuricsMacTests/CanonicalSyncPlannerTests.swift` 覆盖 optional `canonicalManifest` 解码兼容、metadata hash/modifiedAt 方向、business modifiedAt diagnostics、createdAt ignored diagnostics、同时间戳 conflict、audio same no-op、peer object absent/metadata-only/missing/study-only bootstrap、peer unknown deferred、generated artifact download/no-op/defer/conflict、view refresh/retry drainer suppress、schema/hash/capability fallback。
- Canonical Apply Plan：`RokuricsTests/CanonicalApplyPlanTests.swift` 与 `RokuricsMacTests/CanonicalApplyPlanTests.swift` 覆盖 metadata apply/send bridge hint、generated artifact legacy request/apply bridge、conflict record redaction、object tombstone apply/send、active-vs-tombstone conflict、same tombstone no action、artifact tombstone no-physical-delete policy、tombstoned object anti-resurrection、audio conflict no apply/download、dedupe。
- Canonical Library Objects：`RokuricsTests/CanonicalLibraryObjectTests.swift` 与 `RokuricsMacTests/CanonicalLibraryObjectTests.swift` 覆盖 folders、study items、standalone notes、library tombstones、old manifest decode、metadata hash 稳定性和 path/content redaction。
- Canonical Library Sync Planner：`RokuricsTests/CanonicalLibrarySyncPlannerTests.swift` 与 `RokuricsMacTests/CanonicalLibrarySyncPlannerTests.swift` 覆盖 folder/study item no-op/apply/send/conflict/tombstone、view refresh/retry drainer suppress 和 unsupported fallback。
- Canonical Transfer/Object Projection：`RokuricsTests/CanonicalTransferStateTests.swift`、`RokuricsMacTests/CanonicalTransferStateTests.swift`、`RokuricsTests/CanonicalObjectProjectionTests.swift`、`RokuricsMacTests/CanonicalObjectProjectionTests.swift` 覆盖 legacy state 到 canonical phase 的只读映射，以及 ObjectProjection 不驱动 UI/sync/upload。
- Canonical Inventory Coverage/Readiness：`RokuricsTests/CanonicalInventoryCoverageTests.swift` 与 `RokuricsMacTests/CanonicalInventoryCoverageTests.swift` 覆盖 manifest builder coverage、unsupported object 统计和 retirement readiness diagnostics-only gate。
- Canonical Production Ports：`RokuricsTests/CanonicalProductionPortsTests.swift` 与 `RokuricsMacTests/CanonicalProductionPortsTests.swift` 覆盖 production port contract、required capability、unsafe logical token 拒绝、suppressed file/transport/upload/apply trace，以及 dry-run 不写入、不上传、不发网络、不调用真实 apply。
- Canonical Production Snapshot：`RokuricsTests/CanonicalProductionSnapshotTests.swift` 与 `RokuricsMacTests/CanonicalProductionSnapshotTests.swift` 覆盖 snapshot adapter 只用显式 legacy facts、生成 runtime node state/readiness/projection、hash prefix diagnostics redaction，不读取真实 store、不写 `receive.json`、不调用 `applySyncManifest`。
- Canonical Dry-Run Migration / Legacy Equivalence / Gate：`RokuricsTests/CanonicalDryRunMigrationTests.swift`、`CanonicalLegacyEquivalenceTests.swift`、`CanonicalMigrationGateTests.swift` 与对应 Mac 测试覆盖 metadata churn conservative/no-op、canonical aggressive blocker、conflict blocker、missing port blocker、unsupported object blocker、redacted divergence、manual migration design eligible、runtime switch false、legacy retired false。
- Canonical Kernel Facade：`RokuricsTests/CanonicalKernelFacadeTests.swift` 与 `RokuricsMacTests/CanonicalKernelFacadeTests.swift` 覆盖默认 disabled 拒绝、dry-run facade 输出、offline runtime harness、缺 token production rejection，以及 fake production port allowed 时只产生 redacted side-effect trace。
- Canonical Production Port Contract：`RokuricsTests/CanonicalProductionPortContractTests.swift` 与 `RokuricsMacTests/CanonicalProductionPortContractTests.swift` 覆盖 file/transport/upload/apply 的真实执行方法合同、legacy dry-run ports 继续编译且 suppressed、以及没有真实 route/upload/apply 行为被接入。
- Canonical Production Execution Guard：`RokuricsTests/CanonicalProductionExecutionGuardTests.swift` 与 `RokuricsMacTests/CanonicalProductionExecutionGuardTests.swift` 覆盖缺 rollback plan、缺 dry-run equivalence、dry-run-only port、unresolved conflict、blocked migration gate 等 rejection reason。
- Canonical Rollback Plan：`RokuricsTests/CanonicalRollbackPlanTests.swift` 与 `RokuricsMacTests/CanonicalRollbackPlanTests.swift` 覆盖 rollback plan required domain 覆盖、rollback audit 缺口、rollback result 只报告合同结果。
- Canonical Production Execution Result：`RokuricsTests/CanonicalProductionExecutionResultTests.swift` 与 `RokuricsMacTests/CanonicalProductionExecutionResultTests.swift` 覆盖 side-effect trace redaction、disabled/dry-run 无 side effect、route/upload route 不变、generated artifact 不创建 upload job、app source 未把 facade 接入 `performTick`。
- Canonical Execution Shadow：`RokuricsTests/CanonicalExecutionShadowTests.swift` 与 `RokuricsMacTests/CanonicalExecutionShadowTests.swift` 覆盖 execution shadow dry-run、shadow root 写入边界、production root 拒绝、hash/escape 拒绝、read-only transport projection、mutating route 拒绝、upload resume/no-op/conflict/finalize mismatch、apply rehearsal 不调用真实 apply、rollback rehearsal、iPhone/Mac production execute blocked。`CanonicalShadowSeamTests.swift` 双端覆盖 iPhone tick/Mac inventory seam 记录 execution shadow diagnostics 且不改变 legacy plan 或 response shape。
- Canonical Recording Metadata Single-Domain Shadow：`RokuricsTests/CanonicalRecordingMetadataExecutionShadowTests.swift` 与 `RokuricsMacTests/CanonicalRecordingMetadataExecutionShadowTests.swift` 覆盖默认 disabled、非 recordingMetadata domain 不执行、metadata no-op/canonicalMoreConservative、apply/send/tombstone marker、same modifiedAt conflict、active-vs-tombstone conflict、canonicalMoreAggressive 默认 blocked 与 policy allow、missing peer snapshot、diagnosticsOnly no real writes、bounded diagnostics/hash prefix。`CanonicalShadowSeamTests.swift` 双端覆盖单域 shadow seam 默认不改变 client side effects 或 Mac inventory response。
- Canonical v8.2 NoCommit staging/evidence：`RokuricsTests/CanonicalNoCommitStagingRootTests.swift` 与 `RokuricsMacTests/CanonicalNoCommitStagingRootTests.swift` 覆盖 staging root 默认 cleanup、production root/child refusal、bounded retain by count/bytes、evidence report redaction、migration stage default off/NoCommit no production commit/future guarded commit descriptor，以及 staging failure cleanup。`CanonicalV8RecordingMetadataNoCommitTests.swift` 双端覆盖 NoCommit runner 不提交、不 suppress legacy、默认 cleanup、显式 retain diagnostics、iPhone tick/Mac inventory seam 仍不改 legacy plan/response。
- Canonical v8.4 Recording Metadata Commit fake/in-memory hardening：`RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests.swift` 与 `RokuricsMacTests/CanonicalRecordingMetadataCommitExecutorTests.swift` 覆盖默认 executor 阻断真实 production commit、内部 fake apply/send commit、既有 `/sync/apply-metadata` route projection、canary N=0/N=1、pre/postcondition failure、transport before/accepted-after failure、apply before/after partial failure、rollback success/failure、missing rollback checkpoint fatal blocker、idempotent retry、same object different action 不跳过、failure replay 不伪装成功、成功后 duplicate suppression、失败 fallback、不支持 non-recordingMetadata action、unexpected/unsupported side-effect 阻断、unrelated object untouched、fake tombstone/conflict/audio/generated/folder/studyItem untouched proxy checks 和 side-effect trace redaction。
- Canonical v8.5 Real Root-Bound Recording Metadata Apply Port：`RokuricsTests/CanonicalRecordingMetadataRealApplyPortTests.swift` 与 `RokuricsMacTests/CanonicalRecordingMetadataRealApplyPortTests.swift` 覆盖 root-bound target unsafe path 拒绝、失败分类、默认 disabled、production root default-disabled、temp test root atomic metadata write、redacted trace、rollback restore、postcondition mismatch rollback、checkpoint failure、root escape、audio/ledger/generated untouched、test-root real port commit executor 和 gate evidence blockers。
- Canonical v8.6 Guarded Commit App Seam：`RokuricsTests/CanonicalRecordingMetadataGuardedCommitSeamTests.swift` 与 `RokuricsMacTests/CanonicalRecordingMetadataGuardedCommitSeamTests.swift` 覆盖 default-off、证据齐全但 canary `N=0` 不执行、显式内部 N=1 只放过 gate 但仍不执行、N>1 blocked、unsafe mode/trigger/evidence blocker、diagnostics redaction、iPhone tick plan/client side effects unchanged、Mac inventory missing peer snapshot nonfatal 和 response unchanged。
- Canonical v8.7 Recording Metadata Canary N=1：`RokuricsTests/CanonicalRecordingMetadataCanaryTests.swift` 与 `RokuricsMacTests/CanonicalRecordingMetadataCanaryTests.swift` 覆盖 selector 稳定排序、apply-before-send、unsupported trigger/root-bound blocker、prior failed candidate exclusion、observation report redaction/runtimeSwitch false/UI false/uploadJob false；双端 `CanonicalRecordingMetadataCutoverTests` 覆盖 N=1 缺内部开关 blocked、N>1 blocked、N=1 success/failure/rollback/fallback/duplicate suppression。
- Canonical v8.15 LibraryMetadata Canary N=1：`RokuricsTests/CanonicalLibraryMetadataCanaryTests.swift` 与 `RokuricsMacTests/CanonicalLibraryMetadataCanaryTests.swift` 覆盖 strict N=1 config、single safe candidate commit、N>1/allEligible/runtime switch blocker、resource move blocker、failure rollback/fallback/no suppression、Mac fake peer commit 和 Mac inventory peer snapshot unavailable blocker。
- Canonical v8.11 Tombstone and Conflict Domain Migration：`RokuricsTests/CanonicalTombstoneConflictCutoverTests.swift` 与 `RokuricsMacTests/CanonicalTombstoneConflictCutoverTests.swift` 覆盖 default-off、candidate generation、NoCommit staging、test-root marker/ledger commit/rollback、production root disabled、canary stage policy、physical/permanent delete/tombstone GC/conflict ambiguity/generated artifact tombstone blockers、anti-resurrection `resurrectionBlocked` ledger、success-only legacy duplicate suppression、failure rollback/fallback、read-side diagnostics-only、receive JSON/audio/generated artifact deletion suppression 和 route/security/no-physical-delete 边界。
- view refresh 不创建 upload job：列表、详情、文件夹、学习库 refresh 都必须命中 `uploadDecisionSuppressedViewRefreshOnly`。
- peer 已有同 audio no-op：manual sync、Mac pending sync hint、foreground tick、periodic tick 在 peer hash/size 相同场景不调用 upload coordinator。
- peer metadata-only 补传：Mac inventory 有 metadata 但无 audio 时只上传一次；下一次 inventory 报告同 hash/size 后 no-op。
- metadata uploaded 但 peer missing：本地 metadata `uploaded` 不能阻止 audio 补传。
- completed ledger 但 peer missing：ledger completed 不能单独 no-op，必须继续补 peer 缺失 audio。
- completed ledger 且 peer same：应 suppress 并显示 uploaded。
- transfer/ledger in-flight 去重：同 syncRunID、同 recordingID、同 artifactID 不重复创建任务。
- retryable failure：失败后写入 `nextRetryAfter`，未到期不新建任务，到期后 retry drainer 复用上传主路径并恢复上传。
- peer unknown：普通 sync deferred；用户手动上传记录 manual force；retry drainer 记录 retry-drainer。
- peer conflict：Mac 已有同 recording 但 checksum/size 不同时不能覆盖，必须展示/记录冲突。
- Mac 手动同步链：pending sync request 只能被 heartbeat 消费一次；重复点击去重；超时给明确状态；iPhone 必须 ack 同一个 `syncRunID` 并排队 tick。
- Mac inventory：已有 audio 时必须报告 `audioAvailable`、`audioChecksum`、`audioSize`、`sourceDeviceID`、`audioLogicalPathToken`。
- Generated artifact transfer：Mac generated transcript/note/summary projection 必须标记 authoritative producer；iPhone 已下载 generated artifact 只能作为本地 availability，不得作为 producer；canonical download 必须桥接到 legacy artifact request/apply，不得新增 route 或 generated upload job。
- checksum cache：iPhone/Mac inventory 构建时文件 size/mtime 不变应命中缓存，变化时 invalidated，并记录 off-main hash 诊断。

手动验证建议：

- iPhone 前台时，Mac 点立即同步，确认 Mac pending -> iPhone heartbeat -> ack -> tick -> completed/failed 全链路诊断。
- iPhone 后台或未启动时，Mac 点立即同步，确认 UI 明确显示等待 iPhone，而不是伪装成完成。
- debug 启动 iPhone 后，Mac 已有同 hash/size 的旧录音不再重复上传。
- 网络中断后失败上传显示可重试，到 backoff 后可恢复。
- 100MB+ 或长录音场景下打开列表、连接页和触发 sync 不应出现明显主线程卡顿。

### AI Chat

- 新建/切换/删除会话。
- 从学习库 folder/item 导入上下文。
- note summary 优先，transcript preview fallback。
- 大上下文截断。
- 附件保存和不支持附件时本地保留提示。
- provider 配置缺失、超时、空响应。

## 常见失败原因

- Mac build 找不到仓库外 whisper.cpp 编译产物；需要设置 `WHISPER_CPP_ROOT` 或准备本机 helper/dylib。
- iOS test 未指定存在的 simulator 名称。
- Mac sandbox 缺少安全范围书签，导致 whisper-cli/model/ffmpeg 访问失败。
- TLS identity 未生成、app-local TLS private key/certificate 不可读，或 `SecIdentityCreate` 失败，导致 HTTPS listener 启动失败。
- iPhone 保存的 certificate fingerprint 与 Mac 当前 TLS certificate 不一致，导致 pinning failure。
- HMAC 请求 timestamp 超过窗口、nonce 重放、body hash 不匹配、content type 不匹配、路径不在 allowlist。
- 长录音转写 provider timeout 或模型路径/权限错误。
- LLM provider base URL、model name、API key、max_tokens 配置错误。

## 2026-06-03 Recording Metadata Cutover 验证

本轮新增以下测试文件：

- `RokuricsTests/CanonicalRecordingMetadataCutoverTests.swift`
- `RokuricsTests/CanonicalRecordingMetadataCanaryTests.swift`
- `RokuricsTests/CanonicalRecordingMetadataProductionExecutionTests.swift`
- `RokuricsMacTests/CanonicalRecordingMetadataCutoverTests.swift`
- `RokuricsMacTests/CanonicalRecordingMetadataCanaryTests.swift`
- `RokuricsMacTests/CanonicalRecordingMetadataProductionExecutionTests.swift`

本轮实际运行：

```sh
xcrun simctl boot <iPhone-17-iOS-26.5-UDID>
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'id=<iPhone-17-iOS-26.5-UDID>' -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsTests/CanonicalRecordingMetadataCanaryTests -only-testing:RokuricsTests/CanonicalRecordingMetadataProductionExecutionTests test
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCanaryTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataProductionExecutionTests test
```

覆盖点：默认 disabled、unsupported domain、缺 token/evidence/rollback、view refresh/retry drainer denied、unresolved conflict denied、canary N=0、canary N=1、commit 成功后 duplicate legacy suppression、commit failure rollback/fallback、rollback fatal blocker、UI parallel projection `mutatedUI=false`、retirement readiness candidate/blocker、send action 使用既有 `/sync/apply-metadata` route projection、non-recordingMetadata action 不写 generated artifact、不创建 upload side effect。

## 本轮是否实际运行命令

2026-05-26 文档自查实际运行：

- `pwd`
- `git rev-parse --show-toplevel`
- `git status --short`
- `xcodebuild -list -project Rokurics.xcodeproj`
- 多个只读 `find`、`rg`、`sed`、`wc`、`diff -q`
- 写入文档后运行的验证命令见最终报告。

2026-06-01 Canonical Core / Shadow Mode / Sync Truth v1 本轮实际/预期验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalCoreTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalShadowDiagnosticsTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalSyncPlannerTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalCoreTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalShadowDiagnosticsTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalSyncPlannerTests`
- 文档和空白检查：`git diff --check` 与 `git status --short`。

实际运行结果以最终报告为准；全量 Swift Testing 在并发环境下可能出现既有非确定性失败，需用失败项隔离重跑确认。

2026-06-02 Canonical Artifact Transfer v1 本轮实际/预期验证：

- `xcodebuild -list -project Rokurics.xcodeproj`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -destination generic/platform=iOS build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -destination platform=macOS build`
- `xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalCoreTests -only-testing:RokuricsTests/CanonicalSyncPlannerTests -only-testing:RokuricsTests/CanonicalShadowDiagnosticsTests`
- `xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination platform=macOS -only-testing:RokuricsMacTests/CanonicalCoreTests -only-testing:RokuricsMacTests/CanonicalSyncPlannerTests -only-testing:RokuricsMacTests/CanonicalShadowDiagnosticsTests`
- 文档和空白检查：`git diff --check` 与 `git status --short`。

2026-06-02 Canonical Apply / Conflict / Tombstone v1 本轮实际/预期验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalCoreTests -only-testing:RokuricsTests/CanonicalShadowDiagnosticsTests -only-testing:RokuricsTests/CanonicalSyncPlannerTests -only-testing:RokuricsTests/CanonicalApplyPlanTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalCoreTests -only-testing:RokuricsMacTests/CanonicalShadowDiagnosticsTests -only-testing:RokuricsMacTests/CanonicalSyncPlannerTests -only-testing:RokuricsMacTests/CanonicalApplyPlanTests`
- 文档和空白检查：`git diff --check` 与 `git status --short`。

2026-06-02 Canonical Kernel Completion v1 本轮实际/预期验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalCoreTests -only-testing:RokuricsTests/CanonicalShadowDiagnosticsTests -only-testing:RokuricsTests/CanonicalSyncPlannerTests -only-testing:RokuricsTests/CanonicalApplyPlanTests -only-testing:RokuricsTests/CanonicalLibraryObjectTests -only-testing:RokuricsTests/CanonicalLibrarySyncPlannerTests -only-testing:RokuricsTests/CanonicalTransferStateTests -only-testing:RokuricsTests/CanonicalObjectProjectionTests -only-testing:RokuricsTests/CanonicalInventoryCoverageTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalCoreTests -only-testing:RokuricsMacTests/CanonicalShadowDiagnosticsTests -only-testing:RokuricsMacTests/CanonicalSyncPlannerTests -only-testing:RokuricsMacTests/CanonicalApplyPlanTests -only-testing:RokuricsMacTests/CanonicalLibraryObjectTests -only-testing:RokuricsMacTests/CanonicalLibrarySyncPlannerTests -only-testing:RokuricsMacTests/CanonicalTransferStateTests -only-testing:RokuricsMacTests/CanonicalObjectProjectionTests -only-testing:RokuricsMacTests/CanonicalInventoryCoverageTests`
- 文档和空白检查：`git diff --check` 与 `git status --short`。

2026-06-02 Canonical Runtime Kernel Offline Completion v1 本轮实际验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRuntimeKernelTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRuntimeKernelTests`
- 本组测试只验证离线/in-memory runtime kernel，不等同于真实设备同步、真实 HTTPS route、真实 upload client、真实 file store、UI 或 pending sync 验证。

2026-06-02 Canonical Production Ports & Dry-Run Migration Readiness v1 本轮实际验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test -only-testing:RokuricsTests/CanonicalProductionPortsTests -only-testing:RokuricsTests/CanonicalProductionSnapshotTests -only-testing:RokuricsTests/CanonicalDryRunMigrationTests -only-testing:RokuricsTests/CanonicalLegacyEquivalenceTests -only-testing:RokuricsTests/CanonicalMigrationGateTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalProductionPortsTests -only-testing:RokuricsMacTests/CanonicalProductionSnapshotTests -only-testing:RokuricsMacTests/CanonicalDryRunMigrationTests -only-testing:RokuricsMacTests/CanonicalLegacyEquivalenceTests -only-testing:RokuricsMacTests/CanonicalMigrationGateTests`

2026-06-02 Canonical Production Runtime API & Port Contract v1 本轮实际验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test -only-testing:RokuricsTests/CanonicalKernelFacadeTests -only-testing:RokuricsTests/CanonicalProductionPortContractTests -only-testing:RokuricsTests/CanonicalProductionExecutionGuardTests -only-testing:RokuricsTests/CanonicalRollbackPlanTests -only-testing:RokuricsTests/CanonicalProductionExecutionResultTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalKernelFacadeTests -only-testing:RokuricsMacTests/CanonicalProductionPortContractTests -only-testing:RokuricsMacTests/CanonicalProductionExecutionGuardTests -only-testing:RokuricsMacTests/CanonicalRollbackPlanTests -only-testing:RokuricsMacTests/CanonicalProductionExecutionResultTests`
- 本组测试只验证 facade/port/guard/rollback/result 合同和 fake production port 行为；不等同于真实 `performTick`、真实 HTTPS route、真实 upload client、真实 file store、UI、retry drainer 或 pending sync 验证。
- `git diff --check`
- 本组测试只验证 production port contract、read-only snapshot adapter、suppressed dry-run ports、legacy equivalence report 和 migration gate；不等同于真实生产迁移、真实 HTTPS route、真实 upload client、真实 file store、UI、retry drainer 或 Mac pending sync 验证。

2026-06-02 Canonical Production Adapter Skeletons & Migration Facade v1 本轮实际验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test -only-testing:RokuricsTests/CanonicalProductionAdapterTests -only-testing:RokuricsTests/CanonicalMigrationFacadeTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalProductionAdapterTests -only-testing:RokuricsMacTests/CanonicalMigrationFacadeTests`
- 本组测试只验证双端 production file/transport/upload/apply adapter skeleton 的 disabled/fake behavior，以及双端 migration facade 的 disabled/test-harness guard；不等同于真实 `performTick`、真实 HTTPS route、真实 upload client、真实 file store、真实 `applySyncManifest`、UI、retry drainer 或 Mac pending sync 验证。
- 文档和空白检查：`git diff --check` 与 `git status --short`。

2026-06-02 Canonical Shadow Migration Wiring v1 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test -only-testing:RokuricsTests/CanonicalShadowMigrationTests -only-testing:RokuricsTests/CanonicalShadowSeamTests -only-testing:RokuricsTests/CanonicalMigrationFacadeTests -only-testing:RokuricsTests/CanonicalProductionExecutionResultTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalShadowMigrationTests -only-testing:RokuricsMacTests/CanonicalShadowSeamTests -only-testing:RokuricsMacTests/CanonicalMigrationFacadeTests -only-testing:RokuricsMacTests/CanonicalProductionExecutionResultTests`
- `git diff --check`
- `git status --short`
- 本组测试只验证 default-off shadow migration config、suppressed dry-run/read-only port factory、iPhone tick/Mac inventory 诊断 seam、network probe policy、redaction/bounding 和 non-testHarness productionExecute 阻断；不等同于真实 runtime cutover、真实 network probe、真实 upload/apply/store 写入、UI、retry drainer 或 Mac pending sync 验证。

2026-06-02 Canonical Execution Shadow Preparation v1 本轮实际验证：

- `xcodebuild -list -project Rokurics.xcodeproj`
- `xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RokuricsTests/CanonicalExecutionShadowTests -only-testing:RokuricsTests/CanonicalShadowSeamTests/performTickExecutionShadowRecordsReportWithoutChangingLegacyPlan`
- `xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalExecutionShadowTests -only-testing:RokuricsMacTests/CanonicalShadowSeamTests/macInventoryExecutionShadowRecordsReportAndStillReturnsSameResponseShape`
- `xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RokuricsTests/CanonicalShadowSeamTests`
- `xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalShadowSeamTests`
- `git diff --check`
- `git status --short`
- 本组测试只验证 execution shadow preparation 的 shadow file/upload/apply/rollback/read-only transport projection、双端 seam diagnostics 和 production execute blocked；不等同于真实 production cutover、真实 network send、真实 upload/apply/store 写入、UI、retry drainer 或 Mac pending sync 验证。前两条 method-level seam filter 未覆盖完整 seam class，因此本轮另行运行了双端 `CanonicalShadowSeamTests` class。

2026-06-02 Canonical Recording Metadata Single-Domain Shadow Enablement v1 验证边界：

- iPhone 目标命令：`xcodebuild test -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RokuricsTests/CanonicalRecordingMetadataExecutionShadowTests`。
- Mac 目标命令：`xcodebuild test -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalRecordingMetadataExecutionShadowTests`。
- 本组测试只验证 `recordingMetadata` 单域 shadow 的 in-memory apply/send/tombstone marker、pre/postcondition、rollback checkpoint 摘要、方向等价/分歧和 bounded diagnostics；不等同于真实 metadata JSON 写入、真实 `/sync/apply-metadata`、真实 `applySyncManifest`、真实 upload/apply route、UI、retry drainer、Mac pending sync 或 production cutover。
- 若 macOS 26.5/Xcode 对 debug dylib 签名策略报 `RokuricsMac.debug.dylib` launch-time dyld failure，或 `IDELaunchServicesLauncher` 在禁用 debug dylib 后断言，应先确认 Mac target build 是否通过，再单独处理本机签名/LaunchServices 问题。

2026-06-03 Canonical Real-Data Execution Shadow & Read-Only Transport Probe v1 本轮实际验证：

- `xcodebuild -list -project Rokurics.xcodeproj`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test -only-testing:RokuricsTests/CanonicalRealDataShadowCopyTests -only-testing:RokuricsTests/CanonicalReadOnlyTransportProbeTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRealDataShadowCopyTests -only-testing:RokuricsMacTests/CanonicalReadOnlyTransportProbeTests`
- `git diff --check`
- `git status --short`

本组测试只验证 default-off real-data shadow copy/probe contract、shadow root guard/cleanup、descriptor-only audio evidence、generated artifact size/hash guard、read-only route allowlist、mutating route denylist、manifestHash non-auth 和 network suppressed projection；不等同于真实 production cutover、真实 network send、真实 upload/apply/store 写入、真实 audio copy、UI、retry drainer、Mac pending sync 或 legacy retirement 验证。

2026-06-03 Canonical v8.2 Recording Metadata NoCommit Hardening 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalNoCommitStagingRootTests -only-testing:RokuricsTests/CanonicalV8RecordingMetadataNoCommitTests -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsTests/CanonicalRecordingMetadataProductionExecutionTests -only-testing:RokuricsTests/CanonicalRealDataShadowCopyTests -only-testing:RokuricsTests/CanonicalReadOnlyTransportProbeTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalNoCommitStagingRootTests -only-testing:RokuricsMacTests/CanonicalV8RecordingMetadataNoCommitTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataProductionExecutionTests -only-testing:RokuricsMacTests/CanonicalRealDataShadowCopyTests -only-testing:RokuricsMacTests/CanonicalReadOnlyTransportProbeTests`
- `git diff --check`
- `git status --short`

本组测试只验证 v8 app seam default-off、mode/domain/trigger/snapshot/evidence gate、NoCommit staging root lifecycle/cleanup/retention、production root refusal、evidence report、migration config stage descriptor、apply/send equivalence、canonical more aggressive/insufficient evidence blocker、redacted diagnostics、iPhone tick diagnostics-only seam 和 Mac inventory missing-peer-snapshot seam；不等同于 production cutover、canary、legacy replacement、真实 network send、真实 upload/apply/store 写入、UI、retry drainer、Mac pending sync 或 legacy retirement 验证。

2026-06-04 Canonical v8.3 Recording Metadata Commit Executor 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsTests/CanonicalV8RecordingMetadataNoCommitTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCommitExecutorTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsMacTests/CanonicalV8RecordingMetadataNoCommitTests`
- `git diff --check`
- `git status --short`

本组测试只验证 `recordingMetadata` single-domain Commit executor 的 fake/internal-port apply/send、pre/postcondition、rollback、canary、legacy fallback、duplicate suppression 和 diagnostics。默认 executor 仍阻断真实 production commit；本组不等同于真实 `StudyLibraryStore.applySyncManifest` cutover、真实网络发送、真实 store rollback、audio/generated/folder/studyItem/UI 迁移、retry drainer/Mac pending sync 迁移、legacy retirement 或性能优化验证。

2026-06-04 Canonical v8.4 Commit Failure Injection & fakeInMemory Hardening 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalProductionExecutionGuardTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCommitExecutorTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalProductionExecutionGuardTests`

本组测试只验证 v8.4 fake/in-memory Commit hardening。它不实现 real root-bound apply port、不写 production root、不接 default app path、不默认启用 Commit、不改变真实 route/security/upload/UI/retry/Mac pending sync，也不代表 v8.5 real apply port readiness。

2026-06-04 Canonical v8.5 Real Root-Bound RecordingMetadata Apply Port 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataRealApplyPortTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataRealApplyPortTests`
- 双端 `CanonicalRecordingMetadataCommitExecutorTests`、`CanonicalRecordingMetadataCutoverTests`、`CanonicalProductionExecutionGuardTests` 可作为回归补充。
- `git diff --check`
- `git status --short`

本组测试只验证 default-off 的 root-bound `recordingMetadata` metadata bytes 写入合同、atomic replace、rollback checkpoint/restore、postcondition verification 和 redacted side-effect trace。它只写 temp/test root，不写 production root，不接 app default path，不执行 canary，不调用真实 `/sync/apply-metadata`、`applySyncManifest`、upload client、route/security、UI、retry drainer、Mac pending sync 或 legacy retirement。

2026-06-04 Canonical v8.6 App Seam Guarded Commit Wiring, Canary N=0 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataGuardedCommitSeamTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataGuardedCommitSeamTests`
- 双端 `CanonicalV8RecordingMetadataNoCommitTests` 可作为 mode isolation 回归，确认 NoCommit seam 只响应 `.guardedExecuteNoCommit`。
- `git diff --check`
- `git status --short`

本组测试只验证 default-off 的 v8.6 app seam guarded report、canary `N=0`、gate/evidence/readiness diagnostics、legacy fallback preserved 和 duplicate suppression not applied。它不执行 real commit、不写 production root、不调用真实 root-bound apply port、不发送 `/sync/apply-metadata`、不调用 `applySyncManifest`、不写 metadata JSON、不改 route/security/upload/UI/retry drainer/Mac pending sync/audio/generated/folder/studyItem，也不代表 v8.7 `N=1` canary 可直接启用。

2026-06-04 Canonical v8.7 Recording Metadata Canary N=1 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalRecordingMetadataCanaryTests -only-testing:RokuricsTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests -only-testing:RokuricsTests/CanonicalRecordingMetadataRealApplyPortTests -only-testing:RokuricsTests/CanonicalRecordingMetadataGuardedCommitSeamTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCanaryTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCutoverTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataCommitExecutorTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataRealApplyPortTests -only-testing:RokuricsMacTests/CanonicalRecordingMetadataGuardedCommitSeamTests`
- send direction 若做真机观察，应补跑 live read-only transport probe tests 与 Mac receiver/security regression。
- `git diff --check`
- `git status --short`

本组测试只验证 explicit internal N=1 canary 的 selector、gate、root-bound/read-only/rollback evidence、single-object commit、failure rollback/fallback、duplicate suppression 和 observation report。它不表示可以扩大到 N>1、默认启用 canary、改 Mac route/security、迁移其他 domain、切 UI/runtime switch 或 retired legacy。

2026-06-04 Canonical v8.9 Generated Artifacts Domain Migration 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS Simulator' build-for-testing`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build-for-testing`
- `git diff --check`
- `git status --short`

本组测试只验证 generated artifact cutover 的 default-off/N=0、五类 artifact kind 限定、NoCommit staging-only、root-bound temp/test apply + rollback、production root default-disabled、N=1 explicit internal gate、success-only legacy duplicate suppression、failure rollback/fallback、Mac inventory report-only seam 和 UI read-side diagnostics。它不表示可以新增 artifact route、迁移 audio、创建 generated artifact upload job、自动下载 audio、修改 route/security、切 UI、迁移 retry drainer/Mac pending sync/folder/studyItem/tombstone/delete，或 retired legacy。

2026-06-04 Canonical v8.10 Folder and StudyItem Metadata Domain Migration 本轮应验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataCutoverTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCutoverTests`
- 双端 `CanonicalLibraryObjectTests`、`CanonicalLibrarySyncPlannerTests`、`CanonicalApplyPlanTests`、`CanonicalGeneratedArtifactCutoverTests`、`CanonicalRecordingMetadataCutoverTests` 可作为回归补充。
- `git diff --check`
- `git status --short`

本组测试只验证 folder/studyItem/standalone note metadata cutover 的 default-off/N=0、candidate generation、NoCommit staging-only、root-bound temp/test metadata apply/send + rollback、production root default-disabled、canary stage blocker、resource move/cycle/conflict blocker、success-only legacy duplicate suppression、failure rollback/fallback、Mac inventory report-only seam 和 UI read-side diagnostics。它不表示可以移动 audio/transcript/note/summary/resource 文件、做 permanent delete/tombstone GC、修改 route/security、迁移 audio/generated artifact/recordingMetadata/UI/retry drainer/Mac pending sync，或 retired legacy。

2026-06-04 Canonical v8.11 Tombstone and Conflict Domain Migration 本轮应/实际验证：

- `xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalTombstoneConflictCutoverTests`
- `xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25 -only-testing:RokuricsTests/CanonicalTombstoneConflictCutoverTests`
- `xcodebuild -quiet build -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25`
- `xcodebuild -quiet build -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS'`
- `xcodebuild -quiet test -project Rokurics.xcodeproj -scheme Rokurics -destination id=AECD0F26-B201-4FE6-ACB8-4BA3A4528E25 -only-testing:RokuricsTests/CanonicalApplyPlanTests`
- `xcodebuild -quiet test -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalApplyPlanTests`
- `git diff --check`
- `git status --short`

本组测试只验证 tombstone/conflict cutover 的 default-off、candidate generation、NoCommit staging-only、root-bound temp/test soft tombstone marker 与 conflict ledger 写入/rollback、production root default-disabled、canary stage blocker、success-only legacy duplicate suppression、failure rollback/fallback、anti-resurrection conflict ledger、read-side diagnostics-only、receive JSON/generated artifact/audio deletion suppression 和 route/security/no-physical-delete 边界。它不表示可以做 permanent delete、physical delete、tombstone GC、删除 audio/transcript/note/summary、切 UI、迁移 audio upload/retry drainer/Mac pending sync、改 route/security、自动下载 generated artifact 或 retired legacy。

2026-06-03 Canonical v8.1 Read-Only Transport Probe Live Wiring 本轮应验证：

- `git diff --check`
- `git status --short`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLiveReadOnlyTransportProbeTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalReadOnlyTransportProbeTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalV8RecordingMetadataNoCommitTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLiveReadOnlyTransportProbeTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalReadOnlyTransportProbeTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalV8RecordingMetadataNoCommitTests`
- security regression if practical: `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/RokuricsMacTests`

本组测试只验证 live probe default-off、route classification denylist/allowlist、build signed envelope without send、explicit internal send gate、existing signing shape、performTick diagnostics-only seam、Mac RequestVerifier boundary、marked inventory no-mutation audit、state snapshot unavailable handling 和 redacted diagnostics；不等同于 production cutover、upload migration、metadata apply migration、UI migration、retry/Mac pending sync migration、runtime switch 或 legacy retirement。

2026-06-05 Canonical v8.17 LibraryMetadata Read-Side End-to-End Pilot Completion 本轮实际验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalLibraryMetadataReadSideTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalObjectProjectionTests -only-testing:RokuricsTests/CanonicalLibraryMetadataCanaryStageTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalLibraryMetadataReadSideTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalObjectProjectionTests -only-testing:RokuricsMacTests/CanonicalLibraryMetadataCanaryStageTests`
- `git diff --check`
- `git status --short`

本组测试只验证 `libraryMetadata` read-side projection/diff/candidate/fallback/retirement report 的 default-off、metadata-only、content/path redaction、unsupported/path-leak blocker、write-side staged evidence linkage、iPhone tick seam default-off/diagnostics-only 和 Mac inventory seam report-only。它不表示可以默认启用 read cutover、切 UI/read path、删除/禁用 legacy、移动资源、写 standalone note content、触发 sync/upload、迁移 retry drainer/Mac pending sync、修改 route/security 或扩到其它 domain。

2026-06-05 Canonical v8.18 LibraryMetadata Production Canary Enablement N=1 本轮实际验证：

- `swiftc -parse RokuricsShared/SyncCore/CanonicalLibraryMetadataProductionCanary.swift`
- `swiftc -parse Rokurics/IPhoneLibraryMetadataProductionCanaryBootstrap.swift`
- `swiftc -parse RokuricsMac/MacLibraryMetadataProductionCanaryBootstrap.swift`
- `xcodebuild test -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:RokuricsTests/CanonicalLibraryMetadataProductionCanaryTests`
- `xcodebuild test -project Rokurics.xcodeproj -scheme RokuricsMac -only-testing:RokuricsMacTests/CanonicalLibraryMetadataProductionCanaryTests`
- `git diff --check`
- `git status --short`

本组测试只验证 `libraryMetadata` production canary wrapper/config/bootstrap 的 default-off、strict N=1、armed no-execution、explicit test-root executor injection、production-root disabled guard、success-only legacy suppression、failure rollback/fallback、unsafe candidate skip、read-side evidence blocker 和 Mac peer snapshot blocker。它不表示可以默认启用 canary、扩大到 N>1/allEligible、切 UI/read path、删除 legacy、移动资源、写 standalone note content、触发 sync/upload、迁移 retry drainer/Mac pending sync、修改 route/security 或扩到其它 domain。

2026-06-05 Canonical v8.24 GeneratedArtifacts Staged Canary Expansion 本轮实际验证：

- `git diff --check`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactCanaryStageTests -only-testing:RokuricsTests/CanonicalGeneratedArtifactCanaryTests -only-testing:RokuricsTests/CanonicalGeneratedArtifactGuardedCommitSeamTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactCanaryStageTests -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactCanaryTests -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactGuardedCommitSeamTests`
- `git status --short`

本组测试只验证 `generatedArtifacts` staged canary expansion 的 default-off、explicit internal stage policy、`N1 -> N3 -> N10 -> allEligible` 顺序、clean previous-stage evidence gate、allEligible 显式许可、多 candidate deterministic selection、首错 rollback 并停止、rollback fatal blocker、success-only duplicate suppression、expanded read-side parallel diagnostics、iPhone executor path、Mac peer snapshot report-only 和 v8.24 matrix guard。它不表示可以默认启用 canary、切 domain cutover、切 UI/read path/runtime switch、创建 generated artifact upload job、自动下载 audio、新增 route、绕过 `/sync/artifact-request`/checksum/size/security、迁移 retry drainer/Mac pending sync、修改 inventory response、删除 legacy fallback 或扩到其它 domain。

2026-06-05 Canonical v8.23 GeneratedArtifacts Canary N=1 本轮实际验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactCanaryTests`（本机无 iPhone 16 simulator，Xcode 返回 destination not found）
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactCanaryTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactCanaryTests`
- `git diff --check`
- `git status --short`

本组测试只验证 `generatedArtifacts` explicit internal N=1 canary wrapper/config/selector/observation/diagnostics、single candidate priority、hash/byte/path/producer/route/audio blocker、success-only exact legacy suppression、failure rollback/fallback、fatal rollback blocker、iPhone executor injection 和 Mac peer snapshot report-only。它不表示可以默认启用 canary、扩大到 N>1/allEligible/stage、创建 generated artifact upload job、自动下载 audio、新增 route、绕过 `/sync/artifact-request`/checksum/size/security、切 UI/read path/runtime switch、迁移 retry drainer/Mac pending sync、修改 inventory response 或删除 legacy fallback。

2026-06-05 Canonical v8.22 GeneratedArtifacts Active Pilot Guarded Commit Seam N=0 本轮实际验证：

- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'generic/platform=iOS' build`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' build`
- `xcrun simctl list devices available`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactGuardedCommitSeamTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:RokuricsTests/CanonicalGeneratedArtifactReadSideTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:RokuricsTests/CanonicalMigrationMatrixTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactGuardedCommitSeamTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalGeneratedArtifactReadSideTests`
- `xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' test -only-testing:RokuricsMacTests/CanonicalMigrationMatrixTests`
- `git diff --check`
- `git status --short`

本组测试只验证 `generatedArtifacts` 作为唯一 active pilot 的 v8.22 N=0 gate evaluation、default-off seam、canary budget zero、no-execution assertion、unsupported/content/path/parent-tombstone/audio blocker、iPhone tick diagnostics-only、Mac inventory report-only 和 matrix guard。它不表示可以执行 N=1、调用 `/sync/artifact-request`、下载/apply/write/commit generated artifact、创建 upload job、自动下载 audio、新增 route、切 runtime switch、修改 UI/read path、迁移 retry drainer/Mac pending sync、suppress legacy 或删除 legacy fallback。
