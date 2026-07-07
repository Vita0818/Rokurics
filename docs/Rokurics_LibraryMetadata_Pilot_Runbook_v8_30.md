# Rokurics LibraryMetadata Pilot Runbook v8.30

适用范围：只用于 debug/internal 验证 `libraryMetadata`。不得用于 release/default 配置，不得扩展到 `generatedArtifacts`、`tombstoneConflict`、`audioUpload` 或 `recordingMetadata`。

## Phase 1: diagnosticsOnly

配置方式：

- 使用 `CanonicalLibraryMetadataDebugPilotConfiguration.diagnosticsOnly(...)`。
- evidence 可使用内部测试 evidence；不注入 executor，不传 testRoot/prodRoot apply port。
- app 默认构造仍保持 `.disabled`；只在 debug/internal seam 或测试 harness 中显式传入。

预期结果：

- LandingFreeze 为 green/allowed。
- activePilot 为 `libraryMetadata`，其它 domains 为 staticOnly。
- runtimeSwitch 为 false，release/default 为 disabled。
- read path 为 legacy，UI 不变。
- candidate selected 为 false。
- canary attempted 为 false。
- production executor 未注入，production root write 未启用。
- diagnostics redacted 为 true。

## Phase 2: armN1Canary

配置方式：

- 使用 `CanonicalLibraryMetadataDebugPilotConfiguration.armTestRootN1(token:evidence:)`。
- token 必须 owner-approved，evidence 必须包含 rollback plan、read-side parallel equivalence、legacy fallback 和 safe candidate readiness。
- 不注入 executor，不构造 write port。

预期结果：

- LandingFreeze 为 green/allowed。
- selected candidate count <= 1。
- readiness report 显示 safe candidate availability。
- rollback readiness 为 ready。
- read-side evidence 为 equivalent。
- legacy fallback availability 为 true。
- commitAttempted 为 false。
- duplicate suppression count 为 0。

## Phase 3: executeN1Canary With testRoot

配置方式：

- 使用 `CanonicalLibraryMetadataDebugPilotConfiguration.executeTestRootN1(token:evidence:)`。
- 通过 iPhone/Mac test-root real apply port 注入 executor。
- 只允许 testRoot 或 tempRoot；`productionRootExplicit` 必须 blocked。
- `allowProductionRootWrites=true` 必须 blocked in v8.30。

预期结果：

- 仅一个 safe metadata-only candidate 被提交到 test root。
- rollback checkpoint 存在。
- precondition/postcondition verified。
- commit success 后运行 read-side parallel comparison。
- read-side divergence count 必须为 0；若 > 0，标记 blocker。
- legacy fallback preserved。
- duplicate suppression 只允许在 test harness/test-root success 后针对 matching libraryMetadata duplicate；默认 app production path 不 suppress。
- production root write attempted 为 false。
- UI/read path 不切换。

## Immediate Disable

- 将 debug pilot config 改回 `CanonicalLibraryMetadataDebugPilotConfiguration.disabled`。
- 移除测试 harness 中的 testRoot executor 注入。
- 确认 release/default app construction 仍没有 pilot config、executor 或 apply port 注入。
- 不需要删除 legacy、retry、upload、Mac pending sync 或 route。

## Failure Interpretation

- LandingFreeze violation：停止本轮，修正配置；不得通过 runtime switch、release/default 或其它 domain active pilot 继续。
- no eligible / unsafe candidate：保留 legacy fallback，不 commit。
- read-side divergence：阻断 execute 后续建议，不切 read path。
- rollback failure：fatal blocker；不得 suppress legacy。
- productionRootExplicit 或 allowProductionRootWrites=true：v8.30 预期 blocked，不应绕过。

## Safe Diagnostic Collection

使用 `CanonicalLibraryMetadataPilotDiagnosticExporter` 收集摘要。允许字段包括 mode、nodeRole、activePilot、freezeStatus、candidate selected/kind、canary/rollback/fallback bool、duplicate suppression count、read-side equivalence/divergence count、otherDomainsStatic、runtimeSwitchFalse、diagnosticsRedacted。

禁止收集或粘贴：

- 完整 metadata JSON。
- standalone note content。
- transcript、note、summary 或 provider response。
- 绝对路径。
- 完整 hash。
- secrets、API key、shared secret。
- 完整 certificate fingerprint。
- request/response body。

## Forbidden Actions

- 不新增其它 domain 阶段。
- 不默认启用 canary。
- 不在 release/default 启用。
- 不使用 production root。
- 不设置 `allowProductionRootWrites=true`。
- 不允许 N > 1。
- 不允许 allEligible。
- 不切 read path。
- 不改 UI。
- 不删除 legacy。
- 不禁用 legacy fallback。
- 不移动资源文件。
- 不写 standalone note content。
- 不执行 tombstone/delete/trash/permanent delete/GC。
- 不改 upload route。
- 不绕过 RequestVerifier、TLS、HMAC、pinning、nonce 或 body hash。

## Next Step

v8.31 只能在 Phase 3 testRoot drill 通过、诊断摘要安全且 owner 明确批准后，讨论 production-root N=1。不得自动继续到 N>1、allEligible、read-side cutover、legacy retirement 或其它 domain。
