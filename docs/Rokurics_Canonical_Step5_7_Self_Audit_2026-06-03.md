# Rokurics Canonical Step 5-7 Self-Audit

审计日期：2026-06-03

## MODEL_CHECK_RESULT

无法从本地运行环境读取精确模型名称；本轮按 Codex 会话上下文执行。

## PATH_CHECK_RESULT

- `pwd`：`/Users/vita/Vitemis/Vela/Rokurics`
- `git rev-parse --show-toplevel`：`/Users/vita/Vitemis/Vela/Rokurics`
- 结论：当前工作目录与 Git root 匹配，可以在本仓库内新增本报告。

## READ_ONLY_SCOPE

本轮任务性质为只读自查。实际只新增本报告，未修改源码、测试、配置、Xcode project 或脚本；未 commit、未 push、未创建 PR；未启动 production cutover、真实迁移、真实上传或真实 apply。

## FILES_READ

已读取/核对：

- 常驻入口和项目文档：`AGENTS.md`、`docs/CURRENT_STATE.md`、`docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/DO_NOT_BREAK.md`、`docs/TESTING.md`、`docs/SYNC_STATE_AUDIT.md`。
- Claude 报告：`claude-report/Rokurics_接入双端的距离与不出bug_只读审计报告_2026-06-03-1158.md`。
- 最近 Codex 报告：读取了当前会话中上一轮 Step 7 最终报告；未发现单独落盘的最近两轮 Codex 最终报告文件。
- Shared canonical 源码：`CanonicalExecutionShadow.swift`、`CanonicalShadowMigration.swift`、`CanonicalRecordingMetadataExecutionShadow.swift`、`CanonicalKernelFacade.swift`、`CanonicalProductionExecution.swift`、`CanonicalProductionPorts.swift`、`CanonicalDryRunMigrationPlanner.swift`、`CanonicalApplyPlan.swift`、`CanonicalSyncPlanner.swift`、`CanonicalRealDataShadowCopy.swift`、`CanonicalReadOnlyTransportProbe.swift`、`CanonicalRecordingMetadataCutover.swift`、`CanonicalTransportRuntime.swift`。
- 双端 adapter/facade：`IPhoneCanonicalRealDataShadowCopyAdapter.swift`、`MacCanonicalRealDataShadowCopyAdapter.swift`、`CanonicalIPhoneMigrationFacade.swift`、`CanonicalMacMigrationFacade.swift`、`IPhoneCanonicalShadowPortFactory.swift`、`MacCanonicalShadowPortFactory.swift`、`IPhoneCanonicalProductionApplyPort.swift`、`MacCanonicalProductionApplyPort.swift`、`IPhoneCanonicalProductionTransportPort.swift`、`MacCanonicalProductionTransportPort.swift`。
- 现有 legacy/runtime 接缝：`Rokurics/StudyLibrarySyncCoordinator.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`、`Rokurics/StudyLibraryStore.swift`、`RokuricsMac/StudyLibraryStore.swift`。
- Step 5/6/7 相关测试：双端 `CanonicalRealDataShadowCopyTests`、`CanonicalReadOnlyTransportProbeTests`、`CanonicalExecutionShadowTests`、`CanonicalRecordingMetadataExecutionShadowTests`、`CanonicalRecordingMetadataCutoverTests`、`CanonicalRecordingMetadataProductionExecutionTests`、`CanonicalProductionExecutionGuardTests`。

## FILES_WRITTEN

- 新增：`docs/Rokurics_Canonical_Step5_7_Self_Audit_2026-06-03.md`

## WORKSPACE_STATUS

开始前 `git status --short` 已显示大量既有 dirty/untracked 内容，包括 `.DS_Store`、双端 sync 源码、6 份 docs、`RokuricsShared/SyncCore/`、双端 canonical adapter/test 文件和多份 `claude-report/`。本轮未回退、覆盖、清理这些既有改动；仅新增本报告。

源码与报告冲突说明：

- Claude 2026-06-03 11:58 报告认为 Step 5/6/7 尚未完成；当前源码和文档已有 Step 5 real-data shadow copy、Step 6 read-only transport probe、Step 7 recordingMetadata cutover candidate。按 AGENTS 要求，本报告以当前源码和 Xcode 配置为准。
- 任务提到 `CanonicalRollbackPlan.swift`；当前仓库不存在该文件，`CanonicalRollbackPlan`、checkpoint、action、audit、result 类型实际定义在 `RokuricsShared/SyncCore/CanonicalProductionExecution.swift`。

## STEP5_REAL_DATA_SHADOW_COPY_STATUS

结论：Step 5 complete for the scoped evidence layer；不是生产迁移，也不是默认启用。

核对结果：

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| real-data shadow copy model 存在 | yes | `CanonicalRealDataShadowCopy.swift` |
| iPhone adapter 存在 | yes | `IPhoneCanonicalRealDataShadowCopyAdapter.swift` |
| Mac adapter 存在 | yes | `MacCanonicalRealDataShadowCopyAdapter.swift` |
| source 是 production data read-only reference | yes | adapter 只从调用方传入的 recording/receive/inventory/study/generated artifact facts 构造 copy source |
| target 是 isolated shadow root | yes | `CanonicalRealDataShadowCopyTarget` 使用 `.shadowCopy` root |
| shadow root 不得等于 production root | yes | `CanonicalShadowRootBinding.validatedShadowRootURL()` 拒绝 production root |
| shadow root 不得位于 production root 内 | yes | 同一 guard 拒绝 production root 子路径 |
| copy 后有 verification evidence | yes | `CanonicalRealDataShadowCopyVerification` / result summary |
| hashUnavailable 不当作 equality proof | yes | `hashUnavailable` 时 `equalityProof=false`，且 required hash 会失败 |
| audio 大文件默认 descriptor-only | yes | policy `copyAudioBytesByDefault=false`，双端 adapter 写 audio descriptor |
| generated artifacts 有 size-bound copy policy | yes | `maxGeneratedArtifactBytes` 和 source size guard |
| metadata copy 写 shadow root | yes | adapter target logical path 指向 shadow root 内 metadata/study/inventory |
| cleanup policy 存在 | yes | `cleanupImmediately`、`retainForDiagnostics`、`cleanupOnNextLaunch` |
| success/failure 尽力 cleanup | partial-by-design | lifecycle API 和测试覆盖 cleanup；runner 返回 result，不在所有 app path 自动删除真实临时 root |
| bounded retention 存在 | yes | `retainForDiagnostics(maxAge:maxBytes)` |
| diagnostics redacted | yes | summary 仅 root kind/id、counts、hash prefix、descriptor count |
| app path 启用时不改 legacy/current plan/UI/retry/pending sync | yes | evidence 只接入 shadow/report；legacy plan 仍先计算并执行 |

Blockers：无 Step 5 scoped blocker。

Safety concerns：只限显式启用 shadow copy；真实设备长期保留 diagnostics 时仍需关注临时 shadow root 生命周期。

Recommended next action：交给 Claude 做只读审计；后续真实设备只读样本验证应先跑 shadow copy evidence，不要直接 cutover。

## STEP6_READ_ONLY_TRANSPORT_PROBE_STATUS

结论：Step 6 complete for the scoped read-only probe contract；不是默认真实网络发送。

核对结果：

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| read-only transport probe contract 存在 | yes | `CanonicalReadOnlyTransportProbe.swift` |
| route classification 存在 | yes | read-only/mutating route status；execution shadow route policy 也将 `.applyMetadata` 归为 mutating |
| default disabled | yes | `CanonicalReadOnlyTransportProbePolicy(isEnabled=false)` |
| 只允许 read-only routes | yes | health/fingerprint/sync status/sync inventory/device status；artifact request 需显式 bounded allow |
| mutating routes 全拒绝 | yes | `isKnownMutatingRoute` |
| `/upload-*` route 拒绝 | yes | upload metadata/audio/resumable routes in denylist |
| `/sync/apply*` route 拒绝 | yes | `/sync/apply`、`/sync/apply-metadata`、`/sync/manifest` in denylist |
| `/pair` 拒绝 | yes | `/pair` in denylist |
| artifact request bounded 且 no apply | yes | `allowBoundedArtifactFetch` + max bytes；仍只 read-only probe |
| 表达 TLS/HMAC/timestamp/nonce/body hash 边界 | yes | request audit requires auth boundary preserved |
| manifestHash 不作 authentication | yes | `manifestHashUsedAsAuth` 直接 blocked |
| unit tests 不发真实网络 | yes | `allowNetworkSend=false` 默认，tests assert `networkSuppressed` |
| app path 不默认发送 probe | yes | shadow/probe config 默认 disabled |
| probe failure nonfatal | yes | probe result 进入 diagnostics/report，不驱动 production side effect |
| diagnostics redacted | yes | audit 记录 route/status/bools/failure，不写 body/secret |

Blockers：无 Step 6 scoped blocker。

Safety concerns：未来若允许 `allowNetworkSend=true`，必须仍只限 read-only route，并继续复用 TLS/HMAC/nonce/body hash 边界；当前未做真实网络发送验证。

Recommended next action：交给 Claude 只读审计；真实设备阶段先只跑 suppressed 或明确 read-only network probe，不碰 upload/apply/pair。

## STEP7_RECORDING_METADATA_CUTOVER_STATUS

结论：Step 7 recordingMetadata slice complete for a default-off, single-domain candidate；eligible for Claude audit；eligible for later real canary design only after explicit owner approval and real-device evidence；NOT eligible for full cutover。

核对结果：

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| single-domain cutover configuration 存在 | yes | `CanonicalSingleDomainCutoverConfiguration` |
| 默认 disabled | yes | mode 默认 `.disabled`，facade 参数默认 `.disabled` |
| 只允许 `domain = recordingMetadata` | yes | gate 非 recordingMetadata 加 `.unsupportedDomain` |
| 非 recordingMetadata blocked | yes | tests cover recordingAudio/generatedArtifact unsupported |
| production gate 存在 | yes | `CanonicalRecordingMetadataCutoverRunner.evaluateGate` |
| explicit token required | yes | missing token -> `.missingToken` |
| owner approval required | yes | token ownerApproved false -> `.missingOwnerApproval` |
| rollback plan required | yes | rollback missing/coverage missing -> `.missingRollback` |
| dry-run equivalence required | yes | evidence false -> `.missingDryRunEquivalence` |
| execution shadow evidence required | yes | evidence false -> `.missingExecutionShadowEvidence` |
| real-data shadow copy evidence required | yes | evidence false -> `.missingRealDataShadowCopyEvidence` |
| no unresolved conflict required | yes | evidence/candidate conflict -> `.unresolvedConflict` |
| migration/production guard pass required | yes | evidence `productionExecutionGuardPassed` required |
| non-dry-run production port required | yes | evidence `productionPortAvailable` required |
| viewRefresh rejected | yes | trigger `.viewRefresh` -> `.viewRefreshTriggerDenied` |
| retryDrainer fresh metadata rejected | yes | trigger `.retryDrainer` -> `.retryDrainerFreshMetadataDenied` |
| canary policy exists | yes | `CanonicalCutoverPolicy.canaryMaxObjectsPerSyncRun` |
| canary default N is 0 | yes | default policy `canaryMaxObjectsPerSyncRun=0` |
| canary N=1 supported | yes | tests cover `.canary(maxObjects: 1)` |
| canary failure stops later objects | yes | runner breaks after first failure |
| rollback checkpoint exists | yes | candidate `rollbackCheckpointID` / effective checkpoint |
| rollback success/failure tested | yes |双端 cutover tests cover success and fatal rollback failure |
| canonical success suppresses only duplicate legacy recording metadata action | yes | suppression only appended after committed + pre/post condition |
| audio/generated/folder/studyItem legacy actions not suppressed by this runner | yes | only recording metadata candidate kinds allowed |
| precommit failure fallback legacy | yes | commit failure -> rollback -> legacy fallback if available |
| postcondition failure rollback/fallback | yes | failure kind maps to rollback path |
| UI ObjectProjection parallel diagnostics only | yes | UI projection has `mutatedUI=false` |
| retirement candidate only recordingMetadata report | yes | readiness is candidate/blocker report only |
| runtime switch global false | yes | dry-run migration readiness remains `eligibleForRuntimeSwitch=false`; facades default disabled |
| not default production execute | yes | global production guard still blocks non-testHarness production execute |

Blockers：无 Step 7 recordingMetadata scoped blocker。

Safety concerns：当前执行仍依赖注入 executor/fake port tests；没有真实设备 canary、没有默认 production executor 接入、没有 UI 切换、没有 legacy retirement。

Recommended next action：先交 Claude 只读审计；通过后才设计真实设备 recordingMetadata canary，仍不要扩域。

## SAFETY_BOUNDARY_CHECK

- Legacy planner/inventory/store/route 保留；iPhone `performTick` 仍先生成 legacy plan，canonical 可用时才桥接，失败回 legacy。
- `/sync/apply-metadata` 仍通过 `SecureLocalHTTPSServer` route 和 `RequestVerifier.verify`，再调用 `StudyLibraryStore.applySyncManifest`。
- upload audio 仍走 `RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient` 主路径。
- production transport adapter 默认 network suppressed；fake responder 仅测试显式构造。
- production apply adapter 默认 disabled/fake-in-memory；不调用真实 `applySyncManifest`。
- `.applyMetadata` 是 canonical route projection 到既有 `/sync/apply-metadata`，不是新增真实 Mac HTTP route。
- production execution guard 仍要求 testHarness role；iPhone/Mac role 进入 `productionExecute` 仍 blocked。
- Diagnostics/report 不写完整 transcript/note/summary/provider response、secret、full fingerprint、API key、request/response body 或完整 hash。

## BEHAVIOR_CHANGE_CHECK

| 问题 | yes/no | 证据/说明 |
| --- | --- | --- |
| 是否删除 legacy planner | no | `LocalNetworkSyncDiffPlanner.plan` 仍生成 legacy plan |
| 是否删除 legacy inventory | no | `LocalNetworkSyncInventory` 和 legacy manifest 仍存在 |
| 是否停止 legacy plan 每 tick 计算 | no | iPhone tick 先生成 `legacyPlan`，再 canonical/fallback |
| 是否改 UI | no | 本轮只新增报告；cutover UI projection `mutatedUI=false` |
| 是否改 retry drainer | no | gate 明确拒绝 retryDrainer fresh metadata |
| 是否改 Mac pending sync | no | 未改 Mac pending sync path |
| 是否改 upload route | no | upload route list和 handlers 未改 |
| 是否新增 route | no real route / yes canonical enum | 新增 `.applyMetadata` canonical projection，映射既有 `/sync/apply-metadata`；未新增 Mac HTTP route |
| 是否绕过 RequestVerifier | no | `/sync/apply-metadata` 仍先 verify |
| 是否绕过 SecureMacUploadClient | no | cutover tests/fake executor 不替代真实 client |
| 是否绕过 RecordingUploadCoordinator | no | audio upload 仍走 existing coordinator |
| 是否让 audio 自动下载 | no | audio default descriptor-only，canonical audio仍 upload candidate |
| 是否把 metadata uploaded 当 audio uploaded | no | docs/source 保持 audio truth = peer hash + size |
| 是否把 completed ledger 单独当 no-op | no | no-op 仍需 peer audio available/hash/size |
| 是否把 peer unknown 当 missing | no | planner/evaluator deferred |
| 是否覆盖 Mac existing different audio | no | conflict/fatal preserved |
| 是否写 production root | no by default | shadow copy/root guard拒 production root；cutover默认 disabled |
| 是否物理删除 audio/transcript/note/summary | no | tombstone仍 soft/no-physical-delete |
| 是否实现 permanent delete / tombstone GC | no | 未切 tombstone GC |
| 是否写 full metadata JSON/transcript/note/summary/provider response 到 diagnostics/docs | no | 本报告不含完整内容 |
| 是否写 absolute path/secret/full fingerprint/API key 到 diagnostics/docs | no, except required path check | 仅保留任务要求的仓库 path check；未写 secret/fingerprint/API key |
| 是否默认启用 shadow | no | shadow configs default `.disabled` |
| 是否默认启用 cutover | no | cutover config default `.disabled` |
| 是否允许 non-recordingMetadata cutover | no | gate unsupported |
| 是否 runtime switch 仍 false | yes | dry-run migration readiness 不允许 runtime switch |
| 是否 legacy fallback 仍保留 | yes | gate failure/failure path保留 fallback |

## TEST_VALIDATION_RESULT

本轮实际运行：

- `pwd`：通过。
- `git rev-parse --show-toplevel`：通过。
- `git status --short`：已读取，显示大量既有 dirty/untracked；本轮只新增报告。
- `xcrun simctl list devices available`：通过，确认 iPhone 17 / iOS 26.5 可用。
- `xcrun simctl boot <iPhone-17-iOS-26.5-UDID>`：通过。
- `git diff --check`：通过。
- iPhone targeted tests：通过。
  - `CanonicalRealDataShadowCopyTests`
  - `CanonicalReadOnlyTransportProbeTests`
  - `CanonicalExecutionShadowTests`
  - `CanonicalRecordingMetadataCutoverTests`
  - `CanonicalRecordingMetadataProductionExecutionTests`
  - `CanonicalRecordingMetadataExecutionShadowTests`
  - `CanonicalProductionExecutionGuardTests`
- Mac targeted tests：通过。
  - `CanonicalRealDataShadowCopyTests`
  - `CanonicalReadOnlyTransportProbeTests`
  - `CanonicalExecutionShadowTests`
  - `CanonicalRecordingMetadataCutoverTests`
  - `CanonicalRecordingMetadataProductionExecutionTests`
  - `CanonicalRecordingMetadataExecutionShadowTests`
  - `CanonicalProductionExecutionGuardTests`

验证自查：

1. Step 5 tests exist：yes。
2. Step 6 tests exist：yes。
3. Step 7 tests exist：yes。
4. iPhone targeted tests run：yes，本轮通过。
5. Mac targeted tests run：yes，本轮通过。
6. build run：本轮 targeted tests 触发构建；最近上一轮也已运行 iPhone generic build 和 Mac build 并通过。未在本轮另行跑全量 build-only 命令。
7. `git diff --check` pass：yes。
8. failed not rerun：no，本轮无失败未重跑。
9. full tests not run：yes，未运行全量测试套件。
10. real device validation not run：yes，未做真机验证。

## BLOCKERS

Scoped Step 5/6/7 自查无 blocker。

Full cutover blockers 仍存在：

- 未做真实设备端到端验证。
- 未做真实 recordingMetadata canary。
- 未接入默认 production executor。
- 未切 UI 到 canonical projection。
- 未迁移 full physical storage。
- 未退休 legacy planner/inventory/routes/stores/retry/Mac pending sync。
- 未做全量测试套件。

## UNCERTAINTIES

- `CanonicalRollbackPlan.swift` 文件不存在；rollback 合同定义在 `CanonicalProductionExecution.swift`。这是任务清单与当前源码结构的冲突。
- Claude 2026-06-03 11:58 报告状态已落后于当前源码；需让 Claude 针对当前 worktree 重新只读审计。
- 最近两轮 Codex 最终报告未发现独立本地文件；本报告使用当前会话可见的上一轮最终报告和当前源码/测试为证据。
- 工作区有大量既有 dirty/untracked 文件；`git status` 不能仅凭状态区分本轮之前的全部来源。本轮只新增本报告。
- 本轮未运行全量测试、未做真机验证、未启动真实 network probe 或 production cutover。

## CLAUDE_AUDIT_RECOMMENDATION

建议交给 Claude 做只读审计。审计范围应聚焦：

- Step 5 shadow root/source/cleanup/hashUnavailable/audio descriptor-only 是否存在未覆盖路径。
- Step 6 read-only probe route policy 是否有遗漏 mutating route。
- Step 7 recordingMetadata gate/canary/rollback/fallback/duplicate suppression 是否能被误用为 full cutover。
- 是否存在任何 app path 默认启用 shadow/cutover 或 production execute 的入口。

不要直接 cutover，不要删 legacy。

## NEXT_CODEX_RECOMMENDATION

下一步应该是审计，而不是继续扩域。

如果 Claude 找到 blocker，下一轮 Codex 只修 blocker，不扩展 domain。若 Claude 审计通过，再做真实设备 read-only evidence 和 recordingMetadata canary 设计；canary 仍需 explicit token、owner approval、rollback plan、dry-run equivalence、execution shadow、real-data shadow copy、read-only probe 和 legacy fallback。

## FINAL_JUDGMENT

1. 第 5 步是否完成：yes，完成 scoped real-data shadow copy evidence layer。
2. 第 6 步是否完成：yes，完成 scoped read-only transport probe contract。
3. 第 7 步 recordingMetadata 最小切片是否完成：yes，完成 default-off single-domain candidate。
4. 是否可以交给 Claude 审计：yes，建议只读审计。
5. 是否可以开始真实设备验证：yes，但仅限只读 shadow/probe evidence，不启用 cutover。
6. 是否可以做 recordingMetadata canary：not yet automatically；Claude 审计和真实设备 evidence 通过后，可以设计显式批准的 canary。
7. 是否可以全量 cutover：no。
8. 是否可以删除 legacy：no。
9. 下一步应该是：审计；若有 blocker 则只修 blocker，不继续扩域。
