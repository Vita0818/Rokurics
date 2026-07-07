# Rokurics LibraryMetadata Pilot Runbook v8.31

日期：2026-06-06

## Scope

v8.31 只允许 `libraryMetadata` 在 explicit debug/internal config 下执行一次 production-root N=1 pilot。它不是默认启用、不是 release 启用、不是 read path cutover、不是 UI cutover、不是 legacy retirement。

## Preconditions

- v8.30 `diagnosticsOnly` passed，且 safe diagnostics export 已 redacted。
- v8.30 `armN1Canary` passed。
- v8.30 explicit testRoot `executeN1Canary` passed。
- LandingFreeze green。
- read-side parallel evidence exists，且 divergence = 0。
- testRoot rollback evidence exists。
- owner 明确批准 production-root N=1 pilot。
- legacy fallback available。

如果任一前置条件缺失，停止，不启用 production-root N=1。

## Explicit Enablement

仅在 debug/internal harness 中构造：

- `mode = executeN1Canary`
- `rootMode = productionRootExplicit`
- `allowProductionRootWrites = true`
- `ownerApproved = true`
- `activePilot = libraryMetadata`
- `runtimeSwitch = false`
- `canaryMaxObjectsPerSyncRun = 1`
- injected productionRootBound apply port and executor

不得从 default app construction、release config、UI toggle、runtime switch、retry drainer、view refresh 或 Mac pending sync 自动启用。

## Verify Default And Release Disabled

- 默认 `CanonicalLibraryMetadataProductionCanaryConfiguration.disabled` 保持 disabled。
- 默认 iPhone/Mac bootstrap 不注入 apply port 或 executor。
- `allowProductionRootWrites=false` 必须 blocked。
- release/default config 不得有 production-root write。
- runtimeSwitch 必须 false。
- read path 必须 legacy。
- UI 必须 unchanged。

## Safe Candidate Selection

只选择一个 safe metadata-only candidate：

- folder rename/color metadata。
- study item tags/filing/folder membership metadata。
- standalone note title/tags/filing metadata。

禁止 candidate：

- delete/trash/tombstone/permanent delete/GC。
- standalone note content write。
- generated artifact/audio/upload mutation。
- resource move。
- unresolved conflict、parent missing、cycle、objectID instability。
- non-libraryMetadata domain。
- 多个 safe candidates。

## Expected Diagnostics

预期包含：

- `canonicalLibraryMetadataProductionRootGateEvaluated`
- `canonicalLibraryMetadataProductionRootGateAllowed`
- `canonicalLibraryMetadataProductionRootN1Started`
- `canonicalLibraryMetadataProductionRootCheckpointCreated`
- `canonicalLibraryMetadataProductionRootAtomicWriteStarted`
- `canonicalLibraryMetadataProductionRootAtomicWriteCompleted`
- `canonicalLibraryMetadataProductionRootPostconditionVerified`
- `canonicalLibraryMetadataProductionRootSafetyProofBuilt`
- `canonicalLibraryMetadataProductionRootDuplicateSuppressed`
- `canonicalLibraryMetadataProductionRootReadSideEquivalent`
- landing report diagnostics

blocked/failure 时预期包含 gate blocked、N1 failed、rollback/fallback 或 rollback failed diagnostics。

## Success Criteria

- gate allowed。
- exactly one safe candidate selected。
- rollback checkpoint created before write。
- root-bound atomic metadata write completed。
- postcondition verified。
- read-side parallel equivalent。
- exact matching legacy `libraryMetadata` duplicate suppressed once。
- legacy fallback remains available for future runs。
- safety proof redacted。
- read path legacy and UI unchanged。
- other domains staticOnly。

## Failure Criteria

- 任一 gate blocker。
- write/precondition/postcondition failure。
- read-side divergence。
- unsafe candidate。
- missing rollback evidence。
- missing legacy fallback。
- production root containment unverified。
- non-libraryMetadata active pilot。
- runtimeSwitch true。

失败必须 fallback legacy，且不得 suppress legacy duplicate。

## Rollback Criteria

必须 rollback：

- write failure after partial commit。
- postcondition mismatch。
- read-side divergence after write。
- any unexpected side effect。

rollback failure 是 fatal blocker；停止 pilot，不 suppress legacy，收集 redacted diagnostics 后人工审计。

## Emergency Disable

- 移除 explicit debug/internal config。
- 设置 `allowProductionRootWrites=false`。
- 移除 injected productionRootBound apply port/executor。
- 回到 `.disabled` 或 diagnostics-only。
- 保留 legacy fallback/read path/UI。

不得用删除 legacy、切 runtime switch、改 route 或清理真实资源文件作为 disable 手段。

## Collect For Claude

- redacted landing report。
- redacted production-root safety proof。
- read-side equivalence report。
- freeze guard report。
- blocker list、diagnostic kind、candidate kind、object kind、domain、hash prefix。

## Do Not Collect

- metadata JSON。
- standalone note content。
- transcript/note/summary content。
- provider response。
- secrets、tokens、shared secrets。
- complete fingerprints。
- complete hashes。
- request/response bodies。
- absolute local paths。

## Next Step

下一步是人工运行一次 production-root N=1 pilot 并交给 Claude 审计。不要自动扩大到 N>1、allEligible、read path cutover、UI cutover、legacy retirement 或其它 domain。
