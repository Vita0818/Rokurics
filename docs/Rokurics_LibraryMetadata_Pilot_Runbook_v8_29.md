# Rokurics LibraryMetadata Pilot Runbook v8.29

日期：2026-06-06

## 目标

本 runbook 只用于 `libraryMetadata` real-device/debug internal N=1 pilot landing。它不授权 `generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata`、read-side cutover、legacy retirement、runtime switch 或 release/default enablement。

## Preflight

1. 确认当前 build 使用 debug/internal-only 配置；release/default app construction 必须保持 `CanonicalLibraryMetadataDebugPilotConfiguration.disabled`。
2. 确认 landing freeze 通过：唯一 active pilot 是 `libraryMetadata`，其它 domain staticOnly/defaultOff，runtimeSwitch=false，release/default cutover=false。
3. 准备 owner-approved `CanonicalCutoverToken`，并记录人工审批来源；不要把 token secret 或个人路径写入 diagnostics/docs。
4. 准备 rollback plan/checkpoint，覆盖本次唯一 candidate 的 domain/object。
5. 准备 evidence：NoCommit、real-data shadow copy、execution shadow、dry-run equivalence、metadata manifest route evidence、read-side parallel equivalent、legacy fallback、root-bound write、atomic replace、rollback verified/rehearsed。
6. 只在 debug/internal harness 中创建 root-bound apply port：
   - iPhone: `IPhoneLibraryMetadataRealApplyPort(testRootURL:)`
   - Mac: `MacLibraryMetadataRealApplyPort(testRootURL:)`
7. 对 candidate 设置 payload bytes 后再注入 executor。production root 默认必须 disabled；只有单独人工批准后才可使用 explicit production root，并且仍必须通过 freeze/evidence gate。

## Candidate Scope

允许：

- folder rename/color metadata
- study item tags/filing/folder membership metadata
- standalone note title/tags/filing metadata

必须阻断：

- resource move 或 folder hierarchy mutation
- standalone note content write
- generated artifact write/read cutover
- audio upload/download/recording metadata migration
- tombstone/delete/trash/permanent delete/tombstone GC
- parent missing、cycle、objectID instability、unresolved conflict、active-vs-tombstone conflict
- unsafe path、unsupported object/action、missing rollback checkpoint

## Execute N=1

1. 构造 `CanonicalLibraryMetadataDebugPilotConfiguration.executeTestRootN1(token:evidence:)`。
2. 注入 `IPhoneLibraryMetadataCutoverExecutor` 或 `MacLibraryMetadataCutoverExecutor`，其 apply port 必须是 test-root non-dry-run root-bound port。
3. 调用 `CanonicalLibraryMetadataDebugPilotBootstrap.evaluateOrRun(...)`，并传入 local/peer canonical snapshots、candidate list、trigger、nodeRole、syncRunID。
4. 检查 landing report：
   - `mode=executeN1Canary`
   - `rootMode=testRoot`
   - `candidate.selected=true`
   - `commitAttempted=true`
   - `commitSucceeded=true`
   - `readSideEquivalent=true`
   - `uiReadPathSwitched=false`
   - `legacyReadPathPreserved=true`
   - `otherDomainsStaticOnly=true`
   - `runtimeSwitchEnabled=false`
5. 成功后只允许 suppress exact matching libraryMetadata legacy duplicate。任何失败、rollback、unsafe/no eligible、diagnosticsOnly、armed 或 blocked report 都不得 suppress。

## Diagnostics

必须能看到以下事件中的相关子集：

- `canonicalLibraryMetadataLandingConfigEvaluated`
- `canonicalLibraryMetadataLandingDisabled`
- `canonicalLibraryMetadataLandingArmed`
- `canonicalLibraryMetadataLandingBlocked`
- `canonicalLibraryMetadataLandingN1Started`
- `canonicalLibraryMetadataLandingCandidateSelected`
- `canonicalLibraryMetadataLandingNoEligibleCandidate`
- `canonicalLibraryMetadataLandingCommitStarted`
- `canonicalLibraryMetadataLandingCommitCompleted`
- `canonicalLibraryMetadataLandingCommitFailed`
- `canonicalLibraryMetadataLandingRollbackStarted`
- `canonicalLibraryMetadataLandingRollbackCompleted`
- `canonicalLibraryMetadataLandingRollbackFailed`
- `canonicalLibraryMetadataLandingLegacyFallbackUsed`
- `canonicalLibraryMetadataLandingDuplicateSuppressed`
- `canonicalLibraryMetadataLandingReadSideEquivalent`
- `canonicalLibraryMetadataLandingReadSideDivergent`
- `canonicalLibraryMetadataLandingReportBuilt`
- `canonicalMigrationLandingFreezeViolation`

Diagnostics 必须 redacted：只记录 mode/rootMode/status/reason/count/object/action/hash prefix 等摘要，不记录完整 metadata JSON、standalone note content、transcript/note/summary、provider response、request/response body、完整 hash、绝对路径、secret、完整 fingerprint、证书私钥或个人隐私路径。

## Rollback and Fallback

- commit/postcondition failure 必须尝试 rollback。
- rollback 成功后 legacy fallback preserved，duplicate suppression count 必须为 0。
- rollback failure 是 fatal blocker；必须停止 pilot，不得扩大 candidate 或重试 unsafe candidate。
- Mac `/sync/inventory` 缺 peer snapshot 时只能 blocked/fallback/report-only，不得为了执行拉 peer snapshot 或调用 executor。

## Stop Conditions

出现以下任一情况，停止 pilot 并保持 disabled：

- freeze violation
- read-side divergent
- rollback failed 或 fatal blocker
- candidate unsafe/resource move/content/tombstone/audio/generated artifact 混入
- production root 未显式批准或 apply port dry-run/default-disabled
- missing owner token、rollback plan、evidence、executor、local/peer snapshot
- duplicate suppression 出现在非 success-only 情况
- UI/read path、sync owner、retry、Mac pending sync、route/security、upload ledger 或 inventory response 出现非预期变化

## Validation Commands

```sh
xcodebuild test -scheme Rokurics -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RokuricsTests/CanonicalLibraryMetadataLandingTests
xcodebuild test -scheme RokuricsMac -destination 'platform=macOS' -only-testing:RokuricsMacTests/CanonicalLibraryMetadataLandingTests
git diff --check
git status --short
```

通过本 runbook 只表示可以审计另一次 N=1。它不表示可以默认启用、扩大到 N>1/allEligible、切 read/UI、迁移其它 domain 或删除 legacy。
