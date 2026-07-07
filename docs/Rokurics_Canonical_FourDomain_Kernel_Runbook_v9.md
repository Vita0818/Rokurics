# Rokurics Canonical Four-Domain Kernel Runbook v9

最近更新：2026-06-16，v9.12 Post-v9.10 Audit Closure B / R6 Connection-Transfer Owner / R7 Final Gate。

## 目标

v9.12 在 v9.10 gate 之上收口 R6 与 R7：Connection/Transfer runtime owner 必须有真实 app path 引用，four-domain final gate/harness 必须逐项 fail closed。它不启用 release/default canonical，不删除或禁用 legacy，不新增 route，不改安全链路。

`READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL` 表示代码级证据包满足真机 app trial 前置条件，但 `realDeviceEvidencePresent=false` 仍是预期状态。它不是 paired-device 真机验证完成，也不是 canonical kernel production completion。

## Gate 四态

- `READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL`：R1-R7 code-level evidence、build/test summary、redacted evidence、cleanup audit 和 no-retirement lock 全部通过；允许进入人工 paired-device debug/internal trial 准备。
- `PARTIAL_WITH_BLOCKERS`：缺少非安全域证据，例如 R6 app runtime 引用、finalize proof -> StatusTruth、某个 four-domain domain 或 harness proof 缺失。
- `NOT_READY`：build/test summary 缺失或明确失败。
- `UNSAFE_TO_TRY_ON_DEVICE`：出现 release/default canonical、route/security bypass、RequestVerifier bypass、legacy fallback 缺失、upload route schema change、test-only upload port selected in production fullSync、peer proof 违规、existing different audio overwrite、UI refresh upload job、diagnostics leak、MainActor hot path violation、switch-back failure、Mac reverse connection、heartbeat heavy sync、mode boundary violation 或 legacy retirement。

## Required Green

1. v9.5 diagnostics hot path async ready。
2. v9.5 content-stable cache ready。
3. v9.5 status truth off-main ready。
4. v9.6 UI EffectiveStatus source ready。
5. v9.7 realtime exchange runtime ready。
6. R6 connection owner ready：app path 引用 `CanonicalConnectionRuntime`，heartbeat/liveness/syncRequested/status exchange carrier wired，Mac no reverse connection，heartbeat enqueue-only。
7. R6 transfer owner ready：`RecordingUploadCoordinator` 引用 `CanonicalTransferRuntime`，retry runtime wired，secure upload path retained，finalize proof feeds StatusTruth，retry drainer existing eligible only。
8. R7 four-domain harness passed：10+ deterministic scenarios、no-freeze assertions、proof assertions、mode sequence。
9. default/release oldKernel。
10. legacy fallback。
11. route/security unchanged。
12. RequestVerifier unchanged。
13. no heartbeat heavy sync。
14. no view refresh upload job。
15. retry storm guard。
16. diagnostics redacted。
17. switch-back proof。
18. no legacy retirement。
19. build/test summary present。

## Evidence Package

`CanonicalFourDomainEvidencePackage` 只保存 redacted summaries 和计数：

- mode transitions。
- cache hit/miss/rebuild。
- diagnostics write queue/drop/flush duration。
- mainActor violation counts。
- status fact/delta/ack/request counts。
- finalize proof count。
- metadataOnly rejected count。
- completed ledger rejected count。
- partial receive rejected count。
- peer proof unavailable count。
- route/security unchanged proof summary。
- switch-back proof summary。
- build/test summary。

不得写入 absolute path、full hash、secret、full fingerprint、request/response body、raw audio、full transcript/note/summary/provider response、full metadata JSON 或 full generated content。

## R6 Owner Mapping

- `oldKernel`：legacy connection/upload owner；canonical connection/transfer runtime disabled。
- `canonicalShadow`：carrier diagnostics/capability only；no transfer commit。
- `canonicalDecisionOnly`：connection unchanged；no transfer commit。
- `canonicalApplyNoAudio`：connection unchanged；canonical audio transfer blocked。
- `canonicalFullSync`：debug/internal + owner + manual + legacy fallback + route/security unchanged + R1-R6 green 时，Connection runtime over existing local HTTPS carrier，Transfer runtime over existing secure upload adapter。
- `blocked`：legacy fallback。

## fake/test-only Upload Port

The old in-memory upload ledger is now explicit `testOnly`. Tests and explicit migration harness port sets may construct it, but production fullSync upload path must not select it. If `productionUploadPortNotTestOnlyFake=false`, the gate returns unsafe and cannot READY.

## No-Retirement Lock

v9.10 必须保持：

- `legacyDeleted=false`
- `legacyDisabled=false`
- `retirementExecutionPerformed=false`
- `readyToRetireLegacyReportOnly=false`
- release/default oldKernel
- `canonicalFullSync` 只允许 debug/internal + owner + manual + all gates

本轮明确不执行 legacy retirement。

## Cleanup Gate

v9.12 gate/evidence/harness 不是 facade 替代品。没有真实 app runtime 引用的 v9 fake harness 类型必须被视为 test-only；真实 owner wiring 以 `StudyLibrarySyncCoordinator`、`RecordingUploadCoordinator`、`SecureReceiverService`、`SecureLocalHTTPSServer` 和 secure upload adapters 为准。不得留下“看起来完成”的无用 facade。

## 建议本地验证命令

```sh
xcodebuild -list -project Rokurics.xcodeproj
xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/RokuricsDerivedData-v912-iPhone test -only-testing:RokuricsTests/CanonicalTransferKernelRuntimeTests -only-testing:RokuricsTests/CanonicalFourDomainRuntimeHarnessTests -only-testing:RokuricsTests/CanonicalFourDomainRealDeviceTrialGateTests
xcodebuild -project Rokurics.xcodeproj -scheme RokuricsMac -configuration Debug -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/RokuricsDerivedData-v912-Mac test -only-testing:RokuricsMacTests/CanonicalTransferKernelRuntimeTests -only-testing:RokuricsMacTests/CanonicalFourDomainRuntimeHarnessTests -only-testing:RokuricsMacTests/CanonicalFourDomainRealDeviceTrialGateTests
rg "CanonicalConnectionRuntime|CanonicalConnectionEnvelope|CanonicalConnectionCarrier|CanonicalPeerLiveness" Rokurics RokuricsMac
rg "CanonicalTransferRuntime|CanonicalTransferSession|CanonicalTransferFinalizeProof|CanonicalTransferRetryRuntime" Rokurics RokuricsMac
rg "fakeLedger|fake ledger|simulated|testOnly" Rokurics RokuricsMac RokuricsShared
git diff --check
git status --short
```

这些命令只产生 local build/test evidence。缺 paired iPhone/Mac redacted jsonl 时，不得声明真机 no-freeze、状态收敛、文件不卡顿或 canonical kernel 完成。
