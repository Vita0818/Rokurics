# Rokurics Canonical Migration Roadmap v8.4-v8.14

创建日期：2026-06-04

本文只定义路线和门禁，不启动迁移，不默认启用 cutover，不删除 legacy，不修改源码、测试或 Xcode project。所有阶段都必须继续以当前源码、Xcode 配置和最新只读审计为准；若旧报告与当前源码冲突，以当前源码为准。

## 2026-06-05 v8.13 路线冻结修订

根据《Rokurics 多域迁移盘点 · 未完域排期 · 注意事项》与用户决策，v8.13 不再推进 audio upload controlled cutover。v8.13 的主题改为 Migration Matrix Freeze & LibraryMetadata Pilot Selection：停止继续横向扩域，建立统一 domain x stage matrix，把 `libraryMetadata` 设为唯一 active pilot domain，其它 domain 只做 static-review-only/default-off audit。

本修订覆盖旧路线中“v8.13 audio upload controlled cutover + retry/pending integration”的计划。audio upload 仍是最高风险、最后处理；tombstone/delete 仍 blocked，直到 `libraryMetadata` pilot 证明 N0 gate -> N1 canary -> expanded canary -> domain write cutover -> read-side parallel -> read-side cutover -> retirement candidate 的完整 pipeline。

## 2026-06-05 v8.14 路线修订

根据用户明确任务，v8.14 主题从原路线中的“UI canonical projection cutover + legacy retirement gates”改为 `libraryMetadata` guarded commit seam, canary `N=0`。本阶段只把 N0 gate/evidence/readiness report 接到 iPhone tick 与 Mac inventory diagnostics seam，不执行 N1，不切 UI/read path，不触发 legacy retirement。

本修订覆盖旧路线中 v8.14 UI/read-side/retirement 的计划。UI canonical projection cutover、read-side cutover 和 legacy retirement gates 必须后移到 v8.14 之后的独立任务，并以 `libraryMetadata` N0 -> N1 -> expanded canary -> domain write cutover 的实际观察结果为前置条件。

## 2026-06-05 v8.15 路线修订

v8.15 主题为 `libraryMetadata` explicit internal canary N=1。它只允许 iPhone 在完整 evidence、owner-approved token、strict N=1 policy 和注入 executor 下提交 1 个 metadata-only candidate；Mac 真实 inventory 因缺 peer snapshot 仍 report/fallback。v8.15 不启用 N>1、allEligible、domain cutover、read-side cutover、runtime switch 或 legacy retirement。

## 2026-06-05 v8.16 路线修订

v8.16 主题为 `libraryMetadata` expanded canary stage：N3 -> N10 -> allEligible。它不是 domain cutover，也不是 read-side cutover；默认 disabled，必须显式 stage policy、previous-stage clean observation、完整 evidence、owner token 和注入 executor。allEligible 只表示本 run 中所有 eligible `libraryMetadata` metadata candidates，不是全域 runtime switch。

v8.16 的退出条件是 stage observation report 能证明 selected/executed/success/failure/rollback/fallback/suppression/skipped/read-side 计数清晰、首错停止、rollback/fatal blocker 可见、success-only per-candidate suppression 正确、Mac peer snapshot unavailable 仍 report-only。v8.17 才能考虑 `libraryMetadata` read-side parallel 扩展审计；UI/read path、legacy retirement 和其它 domain 仍后移。

## 2026-06-05 v8.17 路线修订

v8.17 主题为 `libraryMetadata` read-side end-to-end pilot completion：在 v8.16 staged canary evidence 之后补齐 read-side parallel diff、default-off canonical read candidate、legacy fallback policy、write-side evidence linkage 和 retirement readiness report-only。v8.17 不是 UI/read path cutover，也不是 legacy retirement；即使 candidate ready，也必须保持 `readPathSwitched=false`、`uiMutated=false`、`syncOrUploadTriggered=false`。

v8.17 的退出条件是 legacy/canonical library metadata read snapshot 可并行比较，standalone note content 与真实资源路径被排除，unsupported/path-leak/divergence 能阻断 candidate，write-side staged evidence 缺失会 blocked，retirement candidate 只输出 report-only。guarded read-side cutover 只能在后续独立阶段和单独审计后讨论；默认启用、UI switch、legacy 删除和其它 domain 迁移仍后移。

## 2026-06-05 v8.18 路线修订

v8.18 主题调整为 `libraryMetadata` production canary enablement N=1。它不是 read-side cutover，而是在 v8.17 read-side evidence 之后补齐 strict production canary wrapper、observation report、diagnostics 和双端 explicit bootstrap。默认仍 disabled；armed 只报告 no-execution；execute 只允许 explicit internal/debug configuration 下执行一个 metadata-only candidate。

v8.18 的退出条件是 production canary config 能固定 `libraryMetadata` + N=1，阻断 N>1/allEligible/runtime switch/release default/非 pilot domain，双端默认不注入 executor，显式 test-root 可注入 real apply port/executor，production root 必须 explicit allow，成功才 suppress matching legacy duplicate，失败 rollback/fallback 不 suppress，read path/UI/route/security/retry/Mac pending sync/legacy retirement 均不变。v8.19 之后才可重新讨论 N>1 或 read-side cutover，且必须独立审计。

## 2026-06-05 v8.19 路线修订

v8.19 主题为 `libraryMetadata` guarded read-side cutover seam。它不是默认 UI/read path 切换，而是在 v8.18 write-side canary evidence 之后新增 read source provider 和 read cutover gate：默认 `legacy`，parallel/candidate 模式只返回 legacy output；只有 explicit internal/test `guardedCanonicalRead` 且 gate 通过时，才可服务 canonical library metadata output。

v8.19 的退出条件是 gate 能阻断缺 write-side canary evidence、rollback fatal、read divergence、unsupported/pathLeakRisk、fallback missing、其它 active domain、default/release config、global UI cutover 和 runtime switch；canonical projection missing 或 read exception 必须 fallback legacy。retirement candidate 可记录 guarded read evidence，但仍 report-only，不删除 legacy、不禁用 legacy、不扩到 generatedArtifacts/tombstoneConflict/audioUpload/recordingMetadata。下一步应是 `libraryMetadata` observation/audit 与 retirement candidate 评估，不是跨域迁移。

## 2026-06-05 v8.20 路线修订

v8.20 主题为 `libraryMetadata` observation window 与 retirement candidate gate。它不是 legacy retirement，也不是默认 read/write cutover；只把 v8.18/v8.19 的 write/read evidence 汇总成 observation window、observation gate、rollback drill summary、E2E pilot report 和 report-only retirement candidate report。默认 disabled，必须 explicit internal/test configuration 才记录。

v8.20 的退出条件是 observation gate 能证明唯一 active pilot `libraryMetadata`、其它 domain static/default-off、write/read evidence、legacy fallback、zero divergence、zero rollback failure、zero unsupported/path leak、runtimeSwitch=false、default cutover=false、无 resource move/content write/tombstone delete/sync-upload/UI mutation。candidate ready 仍必须 `retirementExecutionPerformed=false`、`legacyDeleted=false`、`legacyDisabled=false`、`manualAuditRequired=true`。v8.21 才能在人工审计后决定是否延长 observation 或进入更严格的 manual retirement planning；不得自动扩域。

## 2026-06-05 v8.21 路线修订

v8.21 主题为 `generatedArtifacts` template alignment 与 next-pilot candidate。它只补齐 metadata-only read projection、read-side parallel diff、observation window、report-only retirement candidate gate 和 template report；`generatedArtifacts` 仍不是 active pilot，不执行 canary/cutover，不切 read path，不调用 `/sync/artifact-request`，不删除 legacy。只有在 `libraryMetadata` observation complete 或 retirement candidate ready 后，matrix 才允许 `generatedArtifacts.nextPilotCandidate`。

## 2026-06-05 v8.22 路线修订

v8.22 主题为 `generatedArtifacts` active pilot guarded commit seam, canary `N=0`。`generatedArtifacts` 成为唯一 active pilot，`libraryMetadata` 不再 active，但其 observation/retirement-candidate evidence 仍是前置条件。本阶段只把 generated artifact gate/evidence/no-execution/N1 readiness report 接到 iPhone tick 与 Mac inventory diagnostics seam；candidate 即使 gate allowed 也必须因 canary budget 0 被 skipped。

v8.22 的退出条件是双端能记录 started/completed/blocked/gate/canary-zero/commit-skipped/download-skipped/apply-skipped/legacy-fallback-preserved/duplicate-suppression-not-applied diagnostics，且确认不调用 `/sync/artifact-request`、不下载、不 apply、不写 generated artifact、不 commit、不创建 upload job、不自动下载 audio、不新增 route、不切 runtime switch、不改 UI/read path/retry/Mac pending sync。N1 只能在后续独立人工审计、owner-approved token、canary budget 从 0 改 1 和新测试通过后讨论。

## 2026-06-05 v8.23 路线修订

v8.23 主题为 `generatedArtifacts` explicit internal canary `N=1`。本阶段只允许在 `generatedArtifacts` 唯一 active pilot、`libraryMetadata` observation/retirement prerequisite 已满足、owner-approved token、rollback/read-side/no-commit/dry-run/execution-shadow/real-data-shadow/root-bound evidence、local/peer snapshot 和 injected executor 同时存在时，由 iPhone seam 执行一个 `generatedArtifactDownloadApply` candidate。Mac inventory seam 仍 report-only。

v8.23 的退出条件是双端能验证 default-off、strict N=1 config、N>1/allEligible/runtime switch blocked、candidate 选择稳定且最多一个、summary/note JSON 优先于 transcript markdown、hash/byte/path/audio/producer/route/rollback blocker 可观测、成功才 exact legacy duplicate suppression、失败 rollback/fallback 不 suppression、fatal rollback blocker 和 redacted observation report。v8.23 不新增 route、不创建 generated artifact upload job、不自动下载 audio、不切 UI/read path/runtime switch、不迁移 retry drainer/Mac pending sync、不删除 legacy fallback。

## 2026-06-05 v8.24 路线修订

v8.24 主题为 `generatedArtifacts` staged canary expansion。它只在 v8.23 N=1 之后扩大同一 domain 的 canary 数量，不切 domain cutover/read path/UI/runtime switch。stage 顺序固定为 `N1 -> N3 -> N10 -> allEligible`；`N3` 需要 clean N1 evidence，`N10` 需要 clean N3 evidence，`allEligible` 需要 clean N10 evidence 与显式 `allowAllEligible=true`。

v8.24 的退出条件是双端能验证 default-off、explicit staged policy、v8.24 matrix 只允许 `generatedArtifacts` expanded canary、previous-stage failure/rollback/divergence/conflict/content/path/audio/hash/byte blocker、deterministic multi-candidate selection、顺序执行、首错 rollback 并停止、rollback fatal blocker、success-only per-candidate duplicate suppression、expanded read-side parallel diagnostics、Mac peer snapshot report-only 和 redacted observation report。v8.24 不新增 route、不创建 generated artifact upload job、不自动下载 audio、不绕过 `/sync/artifact-request`/checksum/size/security、不迁移 retry drainer/Mac pending sync、不删除 legacy fallback。下一步建议是 generatedArtifacts read-side guarded canonical seam/observation，而不是 audio migration。

## 2026-06-05 v8.25 路线修订

v8.25 主题为 `generatedArtifacts` read-side guarded seam、observation window 和 report-only retirement candidate gate。它不是默认 read path cutover，不改 UI，不删除 legacy；只在 v8.24 write-side staged canary evidence 之后补齐 metadata/availability read source provider、read cutover gate、write/read evidence linkage 和 observation summary。

v8.25 的退出条件是双端能验证默认 read source 仍为 legacy，parallel/candidate mode 只返回 legacy，explicit internal/test guarded read 在 gate 全部通过时可服务 canonical generated artifact metadata/availability output；gate 能阻断缺 write-side staged evidence、rollback failure、read divergence、unsupported artifact、contentLeakRisk、unsafePathToken、parent tombstone、audioConfusionRisk、fallback missing、其它 active domain、default/global UI cutover 和 runtimeSwitch。read-side seam 不调用 `/sync/artifact-request`、不下载/apply artifact、不写 generated artifact file、不创建 generated artifact upload job、不自动下载 audio、不触发 sync/upload、不改 inventory response、`receive.json`、retry drainer、Mac pending sync 或 route/security。retirement candidate 仍 report-only，`manualAuditRequired=true`，不得执行 legacy deletion/disable。

v8.25 之后应先审计 generatedArtifacts write/read evidence 和 observation window；下一步可以延长 generatedArtifacts observation，也可以开始 tombstoneConflict template alignment。不得直接跳 audio migration、legacy retirement 或默认 read/UI cutover。

## 2026-06-05 v8.26 路线修订

v8.26 主题为 `tombstoneConflict` template alignment 与 next-pilot candidate。它只补齐 metadata-only tombstone/conflict read projection、parallel diff、anti-resurrection gate、observation window、report-only retirement candidate gate、双端 default-off read-side seam 和 migration matrix 候选入口。`tombstoneConflict` 不是 active pilot，不进入 canary，不执行 domain/read-side cutover，不改 UI/read path/runtime switch，不删除 legacy。

v8.26 的退出条件是双端能验证 template audit ready、matrix 只标记 `nextPilotCandidate`、缺 generatedArtifacts evidence 时 candidate blocked、projection 排除完整 metadata/content/路径、anti-resurrection 阻断 stale live restore、physical/permanent delete/tombstone GC/auto conflict resolution 都是 fatal blocker、observation 默认 disabled、retirement candidate report-only、iPhone/Mac seam 默认 disabled 且 enabled 也无 store/UI/upload/inventory/receive/audio/delete/restore/tombstone-clear/conflict-resolve side effect。v8.26 之后应先审计 generatedArtifacts 与 tombstoneConflict evidence，不得直接推进 audio migration、legacy retirement 或默认 cutover。

## 2026-06-05 v8.27 路线修订

v8.27 主题为 `tombstoneConflict` active pilot guarded seam, canary `N=0`。`tombstoneConflict` 成为唯一 active pilot，`generatedArtifacts` 不再 active，但其模板/观察 evidence 仍是前置条件。本阶段只把 tombstone/conflict gate/evidence/no-execution/N1 readiness report 接到 iPhone tick 与 Mac inventory diagnostics seam；candidate 即使 gate allowed 也必须因 canary budget 0 被 skipped。

v8.27 的退出条件是双端能验证 started/completed/blocked/gate/canary-zero/commit-skipped/delete-skipped/restore-skipped/resolution-skipped/legacy-fallback-preserved/duplicate-suppression-not-applied diagnostics，且确认不写 tombstone marker、不 restore、不 clear tombstone、不 physical/permanent delete、不 tombstone GC、不 auto resolve conflict、不 suppress legacy、不创建 upload job、不发网络、不新增 route、不切 runtime switch、不改 UI/read path/retry/Mac pending sync/receive/audio inbox。N1 只能在后续独立人工审计、owner-approved token、canary budget 从 0 改 1 和新测试通过后讨论。

## 2026-06-05 v8.28 路线修订

v8.28 主题为 `tombstoneConflict` explicit internal canary `N=1`。它只允许在 `tombstoneConflict` 唯一 active pilot、owner-approved token、rollback plan、NoCommit/dry-run/execution-shadow/real-data-shadow/read-side parallel/anti-resurrection evidence、failure injection coverage、legacy fallback、duplicate suppression policy、non-dry-run root-bound apply port 和 injected executor 同时存在时，由 iPhone/test seam 或 shared runner 执行最多一个 safe tombstone/conflict candidate。默认仍 disabled；Mac inventory 真实 route 仍保持边界，不因 N1 配置新增 route 或绕过 peer snapshot 要求。

v8.28 的退出条件是双端能验证 strict N=1 config、N>1/allEligible/runtime switch/non-tombstoneConflict blocked、selector 稳定且最多一个、conflict/resurrection 优先于 marker、generated artifact marker report-only、physical/permanent delete/tombstone GC/restore/clear/auto-resolve/stale resurrection/generated-artifact apply/audio/full-content/unsafe-path/missing-rollback blocker 可观测、成功才 matching tombstoneConflict duplicate suppression、失败 rollback/fallback 不 suppression、rollback failure fatal blocker、read-side parallel diagnostics 不改 UI/read path、observation report redacted。v8.28 不改 retry drainer、Mac pending sync、upload routes、audioUpload、generatedArtifacts、recordingMetadata、libraryMetadata 或 legacy retirement。v8.29 只能在 N1 observation 人工审计后讨论是否扩大 tombstoneConflict canary。

## 1. 当前状态摘要

截至 2026-06-04，Canonical 新内核已经具备较完整的 shared SyncCore 合同、planner、apply plan、library object、object projection、transfer projection、runtime readiness、production port contract、dry-run migration planner、production execution guard、rollback contract、shadow diagnostics、real-data shadow copy、read-only transport probe、v8 NoCommit app seam，以及 `recordingMetadata` 单域 commit executor 合同。

当前真实 production owner 仍是 legacy runtime：

- iPhone `performTick` 的默认路径、Mac `/sync/inventory`、metadata manifest bridge、generated artifact request/apply、audio upload、retry drainer、Mac pending sync 和 UI 仍由 legacy 链路负责。v8.7 只在 iPhone explicit internal N=1 canary 配置下短暂执行一个 recording metadata candidate。
- `CanonicalKernelFacade` 默认 `disabled`；`productionExecute` 需要 explicit token、owner approval、rollback plan、dry-run equivalence、non-dry-run ports、无 unresolved conflict 和 migration gate 放行。
- `CanonicalProductionExecutionGuard` 仍阻断非 `testHarness` role 的 production execute。
- 双端 `IPhoneRecordingMetadataCutoverExecutor` / `MacRecordingMetadataCutoverExecutor` 已存在，v8.4 已通过 fake/in-memory apply port 加固 precondition、postcondition、transport/apply failure injection、rollback checkpoint、idempotency、duplicate replay 和 side-effect whitelist。
- 双端 production apply port 当前有 `disabled`、`fakeInMemory`、显式 `testRootBound` 和默认阻断的 `productionRootDisabled` 模式。v8.5 已补齐 root-bound `recordingMetadata` metadata bytes write core；`fakeInMemory` 仍只写 actor 内存，`testRootBound` 只写测试/内部 temp root，`productionRootURL` 默认不写，仍不存在接入 app default path 的真实 production store cutover。
- v8 NoCommit app seam 默认关闭，显式启用也只写临时 staging summary，并保持 `calledApplySyncManifest=false`、`sentNetworkRequest=false`、`wroteProductionStore=false`、`suppressedLegacyDuplicate=false`。v8.6 guarded commit app seam 已接入诊断路径，但 `N=0` 只记录 gate/evidence report，不调用 executor 或 production port。
- canary 默认 `N=0`。v8.7 只允许 explicit internal `N=1`；`N=1` 缺内部开关和 `N>1` 均 blocked。Commit 成功后才可 suppress 同 object/action 的 duplicate legacy recording metadata action；gate blocked、budget exhausted、precondition/postcondition/transport/apply/rollback failure 均必须 fallback/preserve legacy。
- UI 仍未切到 `CanonicalObjectProjection`；`CanonicalRetirementReadiness` 只输出 diagnostics/blocker，不删除、不禁用、不跳过 legacy。

资料时间差说明：

- 2026-06-03 22:37 Claude 报告认为 Commit executor 仍待实现；2026-06-04 11:59 Claude 报告和当前源码显示双端 Commit executor 已补齐，但仍只可通过 fake/in-memory 端口执行，真实 root-bound apply port 尚未实现。
- 2026-06-04 本轮实现 v8.5 root-bound apply port 后，上述“真实 root-bound apply port 尚未实现”已过期；当前事实是 root-bound metadata write 合同和 temp/test root tests 已存在。v8.7 又补上 iPhone explicit internal N=1 canary 与成功后精确 duplicate suppression，但 app default path、N>1、Mac production commit、其他 domain、runtime switch 和真实 production root 写入仍未启用。
- 2026-06-04 本轮实现 v8.10 library metadata cutover seam 后，folder/studyItem/standalone note metadata 已具备 default-off NoCommit、root-bound temp/test apply port、双端 Commit executor、iPhone tick diagnostics/canary seam、Mac inventory report-only seam 和 success-only legacy duplicate suppression tests。当前仍不移动资源、不做 tombstone GC、不切 UI、不默认启用 canary、不改 route/security。
- 2026-06-04 本轮实现 v8.11 tombstone/conflict cutover contract 后，soft tombstone marker 与 conflict ledger 已具备 default-off NoCommit、root-bound temp/test apply port、双端 Commit executor、app seam policy config、canary stage gate、anti-resurrection ledger、read-side diagnostics-only projection 和 success-only legacy duplicate suppression tests。当前仍不做 physical/permanent delete、不做 tombstone GC、不删除 audio/transcript/note/summary、不切 UI、不默认启用 canary、不改 route/security、不迁移 audio upload/retry/Mac pending sync。
- 2026-06-04 本轮实现 v8.12 audio upload runtime shadow/canary preparation 后，audio upload 已具备 default-off/shadow-only domain model、evidence report、NoCommit runner、shadow receiver/resumable rehearsal wrapper、abort/rollback policy、read-side diagnostics projection、双端 no-commit executor、iPhone tick diagnostics seam 和 Mac inventory report-only seam。当前仍不创建真实 upload job、不调用 `RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient`、不写 Mac inbox/`receive.json`/upload ledger/retry、不同步 UI、不默认启用 canary、不改 route/security、不 suppress legacy。
- 2026-06-05 v8.13 已冻结横向扩域。当前事实是 `libraryMetadata` 为唯一 active pilot；`recordingMetadata`、`generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`uiProjection`、`legacyRetirement` 在本阶段只能 static-review-only 或 blocked-for-real-migration。没有 domain 默认启用 cutover，没有 runtime switch，没有 read-side cutover，没有 legacy retirement。
- 2026-06-05 v8.14 已将 `libraryMetadata` guarded commit seam 接入双端 diagnostics path，但固定 canary `N=0`。共享 seam 没有 executor 参数；iPhone tick 与 Mac inventory 只记录 gate/evidence/no-execution/N1-readiness diagnostics，不调用 real apply port、不发送 `/sync/apply-metadata`、不调用 `applySyncManifest`、不写 production root、不 suppress legacy、不改 plan/response/route/security/UI/retry/upload。
- 2026-06-05 v8.15 已新增 `libraryMetadata` explicit internal N=1 canary。iPhone 只在 strict N=1 + executor 注入下提交 1 个 safe metadata candidate；Mac 真实 inventory 缺 peer snapshot 仍只 report/fallback。
- 2026-06-05 v8.16 已新增 `libraryMetadata` expanded stage canary。N3/N10/allEligible 均默认 disabled，必须按顺序提供 previous-stage clean evidence；多候选顺序执行、首错停止、success-only per-candidate duplicate suppression，且仍不切 UI/read path、不改 route/security、不启用其它 domain。
- 2026-06-05 v8.17 已新增 `libraryMetadata` read-side parallel/candidate/report-only retirement evidence。双端 seam 默认 disabled，显式启用也只记录 diagnostics；read projection metadata-only 且排除 standalone note content/真实资源路径；candidate 需要 v8.16 write-side staged evidence 与 zero divergence，但仍不切 UI/read path、不触发 sync/upload、不删除 legacy、不扩域。
- 2026-06-05 v8.18 已新增 `libraryMetadata` production canary wrapper 和双端 explicit bootstrap。默认不注入 executor/apply port；显式 test-root 才注入 real apply port/executor；production root 需要 explicit allow；执行仍限 N=1，success-only suppression，failure rollback/fallback。
- 2026-06-05 v8.19 已新增 `libraryMetadata` guarded read source 与 read cutover gate。默认 read source 仍 legacy；explicit internal/test guarded read 可在 gate 通过时服务 canonical metadata-only output；fallback legacy、UI 默认行为、legacy read path、其它 domain static/default-off 和 retirement report-only 边界不变。
- 2026-06-05 v8.21 已新增 `generatedArtifacts` next-pilot template/read-side/observation/report-only readiness。该状态不是 active pilot，不执行 canary/cutover，不改旧 request/apply path。
- 2026-06-05 v8.22 已把 `generatedArtifacts` 设为唯一 active pilot，但只做 guarded commit seam N=0 gate evaluation。`libraryMetadata` 不再 active，只作为 observation/retirement-candidate prerequisite；不执行 candidate，不调用 `/sync/artifact-request`，不下载/apply/write/commit，不创建 upload job，不自动下载 audio，不新增 route，不改 UI/read path/retry/Mac pending sync。
- 2026-06-05 v8.23 已新增 `generatedArtifacts` explicit internal N=1 canary wrapper。只允许 iPhone 注入 executor 后执行一个 safe `generatedArtifactDownloadApply` candidate；Mac inventory report-only。
- 2026-06-05 v8.24 已新增 `generatedArtifacts` staged canary expansion。N3/N10/allEligible 均默认 disabled，必须按 N1->N3->N10->allEligible 顺序提供 clean previous-stage evidence；多候选顺序执行、首错停止、success-only per-candidate duplicate suppression，且仍不切 UI/read path、不新增 route、不改 retry/Mac pending sync、不启用 audio 或其它 domain。
- 2026-06-05 v8.26 已新增 `tombstoneConflict` template alignment 与 next-pilot candidate。该域只具备 metadata-only read projection、parallel diff、anti-resurrection gate、observation/report-only retirement 和双端 default-off diagnostics seam；仍不 active、不 canary、不 physical/permanent delete、不 tombstone GC、不 restore、不 auto resolve conflict、不切 read/UI/runtime。
- 2026-06-05 v8.27 已把 `tombstoneConflict` 设为唯一 active pilot，但只做 guarded commit seam N=0 gate evaluation。`generatedArtifacts` 不再 active，只作为模板/观察 prerequisite；不执行 candidate，不写 tombstone marker，不 restore/clear，不 physical/permanent delete，不 tombstone GC，不 auto resolve conflict，不创建 upload job，不发网络，不 suppress legacy，不改 UI/read path/retry/Mac pending sync。
- 2026-06-05 v8.28 已新增 `tombstoneConflict` explicit internal N=1 canary wrapper。默认 disabled；只允许一个 safe soft marker/conflict/resurrection block candidate；generated artifact tombstone marker report-only；成功才 suppress matching tombstoneConflict legacy duplicate，失败/rollback/no eligible/unsafe 不 suppress；不切 UI/read path、不改 retry/Mac pending sync/upload routes、不启用其它 domain。
- 本路线以 2026-06-05 当前源码和配置为准。

## 2. 总原则

迁移节奏必须是稳步推进、逐域迁移、默认关闭、可回滚、保留 legacy fallback。任何阶段都不得跳步 cutover。

硬性推进顺序：

```text
NoCommit -> fake Commit -> real port -> N=0 -> N=1 -> 扩大 canary -> domain cutover
```

全局原则：

- 一次只切一个 domain。
- 一次只切一个 direction：同一阶段内 apply 与 send 不混切；send 涉及 network 时必须有额外 route/probe/security evidence。
- 一次只切一个 executor：NoCommit、fake Commit、real apply port、network send、upload runtime、UI read cutover 不混在同一版落地。
- 默认 off：任何新 port、seam、canary、UI read、retirement gate 都必须默认关闭。
- Commit 成功后才 suppress legacy duplicate；失败、rollback、gate blocked、evidence 不足、canary budget 为 0 时一律不 suppress。
- Legacy fallback 保留到该 domain cutover 完成后的观察期结束；retirement readiness 通过也不等于自动删除 legacy。
- `recordingMetadata` 是第一个真实切换域；audio upload 是最高风险域，必须最后迁移。
- Generated artifacts 继续使用既有 `/sync/artifact-request`；metadata send/apply 继续使用既有 `/sync/apply-metadata`；不得新增 route。
- Canonical diagnostics、report、roadmap 只能写 redacted 摘要、hash prefix、计数、分类和 route name，不写完整内容或秘密。
- 每个阶段进入前必须完成 Claude/manual audit；每个阶段退出前必须重新做 Claude/manual audit。任何阶段都不能跳过 Claude/manual audit。

## 3. v8.4-v8.14 总表

| 版本 | 主题 | 默认状态 | 真实写入 | Network | Legacy suppression |
| --- | --- | --- | --- | --- | --- |
| v8.4 | Commit failure injection + fakeInMemory hardening | off/test-only | 否 | 否，只允许 fake projection | 否；只允许测试结果表达 |
| v8.5 | Real root-bound recordingMetadata apply port | off | 是，仅 recordingMetadata real port 显式 temp/test root | 否 | 否 |
| v8.6 | App seam guarded commit wiring, canary N=0 | off, N=0 | 否 | 否 | 否 |
| v8.7 | recordingMetadata canary N=1 | off, explicit internal N=1；N>1 blocked | 是，仅 iPhone 1 个 candidate | 仅 send direction 可走既有安全 route；Mac route/security 不变 | 是，仅同 object/action 成功后 |
| v8.8 | recordingMetadata domain cutover | off -> staged canary | 是，仅 recordingMetadata | 是，仅既有 `/sync/apply-metadata` | 是，仅 recordingMetadata duplicate |
| v8.9 | generated artifact domain migration | off -> staged canary | 是，generated artifact apply | 是，仅既有 `/sync/artifact-request` | 是，仅 generated artifact duplicate |
| v8.10 | folder/studyItem metadata domain migration | off -> staged canary | 是，仅 metadata manifest | 是，仅既有 metadata route | 是，仅 folder/studyItem metadata duplicate |
| v8.11 | tombstone/conflict domain migration | off -> staged canary | 是，仅 soft tombstone/conflict record | 仅既有 metadata route | 是，仅 soft tombstone/conflict duplicate |
| v8.12 | audio upload runtime shadow + canary preparation | off/shadow-only | 否 | 否，read-only evidence only | 否 |
| v8.13 | migration matrix freeze + `libraryMetadata` pilot selection | off / diagnostics-only | 否 | 否 | 否 |
| v8.14 | `libraryMetadata` guarded commit seam, canary N=0 | off / diagnostics-only / N=0 | 否 | 否 | 否 |
| v8.15 | `libraryMetadata` explicit internal canary N=1 | off / explicit N=1 only | 是，仅 iPhone 1 个 metadata candidate | 否；Mac route/security 不变 | 是，仅成功 candidate |
| v8.16 | `libraryMetadata` expanded canary N3/N10/allEligible | off / explicit staged policy only | 是，仅 iPhone staged metadata candidates | 否；不新增 route | 是，仅 per-candidate success-only |
| v8.17 | `libraryMetadata` read-side parallel + candidate report | off / diagnostics-only / candidate suppressed | 否 | 否 | 否 |
| v8.18 | `libraryMetadata` production canary N=1 bootstrap/wrapper | off / armed no-execution / explicit N=1 | 是，仅 explicit one metadata candidate | 否；不新增 route | 是，仅成功 candidate |
| v8.19 | `libraryMetadata` guarded read-side cutover seam | legacy / explicit internal guarded read | 否；read source only | 否 | 否；legacy fallback 保留 |
| v8.20 | `libraryMetadata` observation + retirement candidate report | off / report-only | 否 | 否 | 否 |
| v8.21 | `generatedArtifacts` next-pilot template | off / candidate-only / not active | 否 | 否 | 否 |
| v8.22 | `generatedArtifacts` active pilot guarded commit N=0 | off / diagnostics-only / N=0 | 否 | 否；不调用 artifact request | 否；legacy fallback 保留 |
| v8.23 | `generatedArtifacts` canary N=1 | off / explicit internal / one safe candidate | 是，仅 injected iPhone executor + root-bound rollback-covered candidate | 是，仅既有 `/sync/artifact-request` download/apply bridge；不新增 route | 是，仅 verified success exact legacy artifact duplicate |
| v8.24 | `generatedArtifacts` staged canary N3/N10/allEligible | off / explicit staged policy only | 是，仅 staged generated artifact download candidates | 是，仅既有 `/sync/artifact-request` download/apply bridge；不新增 route | 是，仅 per-candidate verified success exact legacy duplicate |
| v8.25 | `generatedArtifacts` read-side guarded seam + observation | legacy / explicit internal guarded read | 否；read source only | 否 | 否；legacy fallback 保留 |
| v8.26 | `tombstoneConflict` next-pilot template | off / candidate-only / not active | 否 | 否 | 否 |
| v8.27 | `tombstoneConflict` active pilot guarded commit N=0 | off / diagnostics-only / N=0 | 否 | 否 | 否；legacy fallback 保留 |
| v8.28 | `tombstoneConflict` canary N=1 | off / explicit internal / one safe candidate | 是，仅 injected executor + root-bound soft marker/conflict record | 否；不新增 route | 是，仅 verified success matching tombstoneConflict duplicate |

## 4. v8.4 - Commit failure injection + fakeInMemory hardening

| 项目 | 内容 |
| --- | --- |
| 目标 | 只在 fake/in-memory executor 中压测 `recordingMetadata` Commit executor。验证 precondition、postcondition、partial commit、rollback、duplicate suppression result、idempotency 和 failure injection。 |
| 允许范围 | 双端 `IPhoneRecordingMetadataCutoverExecutor` / `MacRecordingMetadataCutoverExecutor` 使用 fake non-dry-run apply/transport port；只处理 `recordingMetadataApply` / `recordingMetadataSend` candidate；只记录 redacted diagnostics。 |
| 明确禁止 | 不写真实根；不接 `performTick` 默认路径；不接真实 `StudyLibraryStore.applySyncManifest`；不发真实网络；不迁移 generated/folder/studyItem/audio/UI/retry/Mac pending sync；不删除 legacy。 |
| 进入条件 | v8.3 当前 fake executor 和 failure injection 枚举存在；NoCommit evidence、execution shadow、real-data shadow copy、read-only probe 仍可作为测试 evidence；Claude/manual audit 已确认 no real-root path。 |
| 退出条件 | 双端 fake tests 覆盖所有 failure injection：precondition mismatch、postcondition mismatch、transport failure before send、transport accepted then failure、apply failure before commit、partial commit、rollback failure、missing rollback checkpoint、unsupported/unexpected side effect、idempotent retry、duplicate object different action、failure replay not success、duplicate suppression allowed/skipped、unrelated fake object untouched。 |
| 必跑测试 | `RokuricsTests/CanonicalRecordingMetadataCommitExecutorTests.swift`、`RokuricsMacTests/CanonicalRecordingMetadataCommitExecutorTests.swift`、双端 `CanonicalRecordingMetadataCutoverTests`、双端 `CanonicalProductionExecutionGuardTests`、iPhone/Mac debug build，并运行 `git diff --check`。 |
| 是否允许真实写入 | 否。 |
| 是否允许 network | 否；只允许 fake transport route projection 到 `.applyMetadata` / `/sync/apply-metadata`。 |
| 是否允许 suppress legacy | 否。只允许 fake result 中表达“成功后可 suppress”的候选信号，不得影响 app legacy action。 |

## 5. v8.5 - Real root-bound recordingMetadata apply port

| 项目 | 内容 |
| --- | --- |
| 目标 | 实现真实 root-bound `recordingMetadata` apply port，但保持 default-off。只补齐真实 apply/write 的最小安全能力，不接默认 `performTick`。 |
| 允许范围 | 只限 `recordingMetadata` metadata bytes apply/send port 合同；port 必须绑定明确 root token/store root；支持 atomic replace、rollback checkpoint、postcondition verify、root containment check 和 redacted diagnostics。v8.5 实际落地为显式 `testRootBound` temp/test root 和默认阻断的 `productionRootDisabled`。 |
| 明确禁止 | 不接默认 app seam；不默认执行；不实现 network cutover；不迁移 audio/generated/folder/studyItem/tombstone/conflict/UI；不调用未审计的全量 manifest apply 作为 single-object rollback 替代；不绕过现有 path guard；不写 production root；不 suppress legacy。 |
| 进入条件 | v8.4 fake failure injection 全绿；明确真实 store checkpoint/rollback 设计；人工批准 root-bound scope；Claude/manual audit 确认 port 不会被默认构造或 UI/sync 自动启用。 |
| 退出条件 | port contract tests 证明 atomic replace 成功、rollback checkpoint 可恢复旧 metadata、postcondition mismatch 会 rollback、checkpoint failure 不写入、root escape 被拒、production root default-disabled、diagnostics 不泄漏完整 JSON/path/hash。 |
| 必跑测试 | 双端 `CanonicalRecordingMetadataRealApplyPortTests`、双端 recording metadata commit executor/cutover/guard 回归、iPhone/Mac build；文档检查 `git diff --check`。 |
| 是否允许真实写入 | 是，但仅显式测试/内部 temp/test root harness，对 `recordingMetadata` 单对象 root-bound metadata bytes；默认 app 与 production root 默认不允许。 |
| 是否允许 network | 否。 |
| 是否允许 suppress legacy | 否。真实 port 只证明 apply 能力，不 suppress legacy。 |

## 6. v8.6 - App seam guarded commit wiring, canary N=0

| 项目 | 内容 |
| --- | --- |
| 目标 | 把 `recordingMetadata` guarded commit 接到 app diagnostics seam，但 canary 固定 `N=0`。可以构造 gate、evidence report、readiness audit 和 diagnostics；不能执行任何对象。 |
| 允许范围 | iPhone tick seam 和 Mac inventory seam 可解析显式配置、token、owner approval、rollback plan、real-data shadow evidence、execution shadow evidence、dry-run equivalence、read-only probe evidence、production apply/transport readiness 和 legacy fallback evidence；runner 只能输出 canary zero / gate allowed but no execution / commit skipped。 |
| 明确禁止 | `N=0` 时不得调用 real apply port、不得调用 commit executor、不得发 network、不得调用 `applySyncManifest`、不得写 metadata JSON、不得 suppress legacy、不得改变 legacy plan/action count/pending count/UI、不得接 retry drainer 或 view refresh。 |
| 进入条件 | v8.5 real apply port default-off 且测试通过；manual/Claude audit 确认 app seam 默认 disabled；配置必须显式支持 canary budget 为 0。 |
| 退出条件 | iPhone tick seam 和 Mac inventory seam 在 `N=0` 下只记录 evidence/gate/canary budget diagnostics，legacy 继续执行，Mac 缺 peer snapshot nonfatal，且没有真实 write/network/apply/upload/duplicate suppression side effect。 |
| 必跑测试 | 双端 `CanonicalRecordingMetadataGuardedCommitSeamTests`、双端 `CanonicalV8RecordingMetadataNoCommitTests` mode-isolation 回归、iPhone/Mac build；手动核对 diagnostics redaction；`git diff --check`。 |
| 是否允许真实写入 | 否。 |
| 是否允许 network | 否。 |
| 是否允许 suppress legacy | 否。 |

## 7. v8.7 - recordingMetadata canary N=1

| 项目 | 内容 |
| --- | --- |
| 目标 | 在 iPhone sync tick 中只允许一个 recording metadata candidate 进入 guarded commit。失败必须 rollback/fallback；成功后只 suppress 同 object/action 的 duplicate legacy recording metadata action。 |
| 允许范围 | 单 domain：`recordingMetadata`；单 direction：一次 canary run 只允许 apply 或 send 其中之一；单 object/action；explicit token + owner approval + rollback plan + full evidence 必须齐全；必须 `.canaryCommit` + `N=1` + `allowsV87CanaryN1InternalExecution=true` + 注入 executor。 |
| 明确禁止 | 不扩大到 N>1；N=1 缺内部开关不得执行；不混切 apply/send；不触发 view refresh/retry drainer fresh job；不 suppress 非同 object/action legacy；不影响 audio/generated/folder/studyItem/UI/retry/Mac pending sync；不改 Mac `/sync/apply-metadata`、`RequestVerifier` 或安全 headers。 |
| 进入条件 | v8.6 `N=0` 真机 evidence 稳定；v8.5 real apply port rollback 演练通过；NoCommit 等价持续为 0；execution shadow 与 real-data shadow copy 通过；send direction 还必须先通过 read-only route/probe evidence。 |
| 退出条件 | N=1 成功路径：precondition/postcondition 全过、rollback checkpoint created、side-effect whitelist 通过、legacy duplicate suppression 仅限同 action；失败路径：rollback 成功、legacy fallback 执行、不 suppress；rollback failure 会产生 fatal blocker 并停止后续 commit。 |
| 必跑测试 | 双端 `CanonicalRecordingMetadataCanaryTests`、commit executor tests、cutover canary N=1 tests、real apply port tests、guarded seam tests、rollback tests、real device manual canary log review；send direction 额外跑 live read-only transport probe tests 和 Mac request verifier/security regression。 |
| 是否允许真实写入 | 是，仅 iPhone explicit internal N=1 的 1 个 recording metadata candidate；默认 app path 和 production root 仍不允许。 |
| 是否允许 network | 仅 send direction 允许既有 `/sync/apply-metadata`，且必须保留 `SecureMacUploadClient` / `RequestVerifier` / TLS pinning / HMAC / nonce / body hash。apply direction 不允许 network。 |
| 是否允许 suppress legacy | 是，但只在 canonical commit 成功后 suppress 同 object/action 的 duplicate legacy recording metadata action。 |

## 8. v8.8 - recordingMetadata domain cutover

| 项目 | 内容 |
| --- | --- |
| 目标 | 逐步扩大 N，完成 `recordingMetadata` 单域 cutover。Legacy fallback 保留到观察期结束。 |
| 允许范围 | 仍只限 `recordingMetadataApply` / `recordingMetadataSend`；逐步从 N=1 扩大到 bounded N，再到该 domain 的 guarded cutover；每次只切一个 direction，direction 观察稳定后再切另一个。 |
| 明确禁止 | 不影响 audio、generated artifacts、folder、studyItem、standalone note、UI、retry drainer、Mac pending sync；不把 metadata uploaded 当 audio uploaded；不删除 legacy planner/inventory/routes/stores。 |
| 进入条件 | v8.7 N=1 apply 和 send 各自通过真实设备观察；rollback/fallback 无未处理 blocker；diagnostics 能串联 syncRunID、token、rollback plan、commit result、legacy suppression。 |
| 退出条件 | `recordingMetadata` domain 在 bounded canary 扩大后无 blocking divergence、无 unresolved conflict、无 rollback fatal blocker；legacy fallback 可用；readiness 只对该域显示 candidate，不触发 legacy retirement。 |
| 必跑测试 | 双端 recording metadata commit/cutover/no-commit/production execution tests；sync planner/apply planner/library plan regression；Mac receiver security tests；真实设备 metadata apply/send 手动矩阵；`git diff --check`。 |
| 是否允许真实写入 | 是，仅 recording metadata。 |
| 是否允许 network | 是，仅既有 `/sync/apply-metadata`，不得新增 route 或扩大 allowlist。 |
| 是否允许 suppress legacy | 是，仅 canonical commit 成功后的同 object/action duplicate legacy recording metadata action。 |

## 9. v8.9 - generated artifact domain migration

| 项目 | 内容 |
| --- | --- |
| 目标 | 迁移 transcript/note/summary generated artifacts 的 download/apply。继续使用既有 `/sync/artifact-request`，不新增 route，不创建 generated artifact upload job，不自动下载 audio。 |
| 当前实现状态 | v8.9 已完成 default-off NoCommit staging、generated artifact root-bound temp/test apply port、双端 Commit executor、iPhone tick diagnostics/canary seam、Mac inventory report-only seam 和 success-only legacy duplicate suppression；默认 disabled、canary `N=0`，生产 root 默认阻断。 |
| 允许范围 | 仅 generated artifact kinds：transcript JSON/Markdown、note Markdown/JSON、summary JSON；peer authoritative producer 仍是 Mac generated output；iPhone downloaded artifact 只能证明本地 availability，不是 producer；apply 前后必须校验 checksum/size。 |
| 明确禁止 | 不迁移 audio；不创建 generated artifact upload job；不新增 artifact route；不把 generated artifact mismatch 自动覆盖；不写完整 transcript/note/summary/provider response 到 diagnostics/docs；不物理删除 artifact。 |
| 进入条件 | `recordingMetadata` domain cutover 稳定并保留 fallback；generated artifact shadow/download/apply equivalence 通过；artifact request bounded policy 与 checksum/size verification 通过审计。 |
| 退出条件 | generated artifact missing local / authoritative peer newer 可通过既有 `/sync/artifact-request` 下载并 apply；same hash+size no-op；peer unknown deferred；hash/size mismatch conflict；legacy fallback 可用。 |
| 必跑测试 | 双端 `CanonicalApplyPlanTests`、`CanonicalSyncPlannerTests`、generated artifact bridge tests、artifact request/apply checksum tests、Mac generated producer projection tests；真实设备 generated artifact download 手动验证。 |
| 是否允许真实写入 | 是，仅 generated artifact apply 的目标文件/metadata，且必须 checksum/size verify。 |
| 是否允许 network | 是，仅既有 `/sync/artifact-request`，bounded 且 signed；不允许 audio download。 |
| 是否允许 suppress legacy | 是，仅 generated artifact canonical apply/download 成功后的同 artifact duplicate legacy action。 |

## 10. v8.10 - folder/studyItem metadata domain migration

| 项目 | 内容 |
| --- | --- |
| 目标 | 迁移 folder/studyItem/standalone note metadata apply/send。保持 `folderID` / `itemID` 稳定；metadata manifest 兼容旧 schema。 |
| 当前实现状态 | v8.10 已完成 default-off NoCommit staging、library metadata root-bound temp/test apply port、双端 Commit executor、iPhone tick diagnostics/canary seam、Mac inventory report-only seam、canary stage gate、resource move/cycle/conflict blockers 和 success-only legacy duplicate suppression；默认 disabled、canary `N=0`，生产 root 默认阻断。 |
| 允许范围 | Folder rename/move/color/trash、study item metadata、standalone note metadata 只通过 metadata manifest apply/send 表达；资源路径、audio/transcript/note/summary 文件不移动。 |
| 明确禁止 | rename/move/color/trash 不移动真实资源；不改变 `folderID` / `itemID` 生成规则；不破坏旧 manifest decode；不迁移 UI read owner；不把 library move 当 physical file move；不做 permanent delete 或 tombstone GC；不迁移 audio/generated artifact/recordingMetadata。 |
| 进入条件 | v8.8 `recordingMetadata` 和 v8.9 generated artifact 稳定；folder/studyItem canonical library planner 与 legacy manifest bridge 等价；旧 schema 兼容测试通过。 |
| 退出条件 | folder/studyItem metadata no-op/apply/send/conflict/tombstone 语义稳定；manifest apply/send 成功后才 suppress duplicate；legacy fallback 在 fallbackRequiredObjectIDs、unsupported object、schema mismatch 时可用。 |
| 必跑测试 | 双端 `CanonicalLibraryObjectTests`、`CanonicalLibrarySyncPlannerTests`、`CanonicalApplyPlanTests`、`StudyLibraryStoreTests`、旧 manifest decode/compat tests；真实设备 folder rename/move/color/trash 手动验证。 |
| 是否允许真实写入 | 是，仅显式测试/内部 temp/test root 的 metadata bytes；业务默认路径仍不写 production root，不移动资源文件。 |
| 是否允许 network | 是，仅既有 metadata manifest route，如 `/sync/apply-metadata`。 |
| 是否允许 suppress legacy | 是，仅 folder/studyItem/standalone note metadata duplicate action 成功后。 |

## 11. v8.11 - tombstone/conflict domain migration

| 项目 | 内容 |
| --- | --- |
| 目标 | 迁移 soft tombstone 和 conflict record 的 production execution 语义。 |
| 当前实现状态 | 已完成 default-off NoCommit staging、root-bound temp/test soft tombstone marker 与 conflict ledger apply port、双端 Commit executor、app seam policy config、canary stage gate、anti-resurrection `resurrectionBlocked` ledger、read-side diagnostics-only projection 和 success-only legacy duplicate suppression；默认 disabled、canary `N=0`，生产 root 默认阻断。 |
| 允许范围 | Soft tombstone、anti-resurrection、active-vs-tombstone conservative conflict record、metadata tombstone apply/send、library tombstone apply/send、conflict diagnostics。 |
| 明确禁止 | 不 physical delete；不 permanent delete；不 tombstone GC；不删除 audio/transcript/note/summary；active-vs-tombstone 不自动选择胜者；tombstoned object 不得通过 generated artifact download 复活。 |
| 进入条件 | metadata、generated artifact、folder/studyItem domains 已稳定；conflict/tombstone apply plan 通过双端测试；manual audit 确认 no-physical-delete invariant 未被破坏。 |
| 退出条件 | soft tombstone 能阻止 resurrection；same tombstone no-op；active-vs-tombstone 进入 conflict record；conflict diagnostics redacted；legacy fallback 保留。 |
| 必跑测试 | 双端 `CanonicalTombstoneConflictCutoverTests`、双端 `CanonicalApplyPlanTests`；扩展阶段再补双端 `CanonicalLibrarySyncPlannerTests`、StudyLibrary trash/restore regression、Mac delete/restore safety tests。 |
| 是否允许真实写入 | 是，仅 soft tombstone metadata 与 conflict record。 |
| 是否允许 network | 当前实现不发 network；未来如启用 send 仅可走既有 metadata route，不新增 route。 |
| 是否允许 suppress legacy | 是，仅 canonical soft tombstone/conflict record 成功后的同 action duplicate。 |

## 12. v8.12 - audio upload runtime shadow + canary preparation

| 项目 | 内容 |
| --- | --- |
| 目标 | 为最高风险 audio upload runtime 做 shadow/canary 准备。此阶段不切 production audio upload。 |
| 当前实现状态 | v8.12 已完成 default-off/shadow-only audio upload preparation：shared domain/evidence/gate/NoCommit/shadow receiver/rollback/read-side projection、双端 no-commit executor、iPhone tick diagnostics seam、Mac inventory report-only seam 和双端准备测试。默认 disabled，canary N=0；N>0 production canary 在 v8.12 blocked。 |
| 允许范围 | Shadow-only upload runtime rehearsal、read-only evidence、upload decision evaluator parity、retry projection shadow、pending sync signal observation、large-file chunk/resume rehearsal、peer hash+size truth validation。 |
| 明确禁止 | 不自动下载 audio；peer unknown 不当 missing；different hash/size 必须 conflict；completed ledger/metadata uploaded/receive record/UI uploaded 不单独 no-op；view refresh/manual upload button/retry drainer fresh job 不创建 canonical upload job；不创建真实 upload job；不调用真实 upload routes；不写真实 upload ledger、Mac inbox、`receive.json`、retry queue、Mac pending sync 或 UI state；不 suppress legacy。 |
| 进入条件 | v8.11 前所有非 audio domains 稳定；legacy audio upload tests 全绿；manual audit 确认 audio state machine 禁区仍成立。 |
| 退出条件 | Shadow 能覆盖 same hash+size no-op、metadata-only upload candidate、peer missing、peer unknown deferred、different hash/size conflict、retry pending/backoff、resumable resume/finalize/hash mismatch、大文件不一次读内存。 |
| 必跑测试 | 两端 sync/audio decision tests、`CanonicalRuntimeKernelTests` upload runtime cases、`CanonicalExecutionShadowTests` upload rehearsal、`RecordingUploadCoordinator` / `RecordingUploadClient` / `SecureMacUploadClient` tests、Mac resumable upload route tests。 |
| 是否允许真实写入 | 否。 |
| 是否允许 network | 否；只允许 read-only/suppressed projection evidence。 |
| 是否允许 suppress legacy | 否。 |

## 13. v8.13 - migration matrix freeze + libraryMetadata pilot selection

| 项目 | 内容 |
| --- | --- |
| 目标 | 停止继续横向扩域，建立统一 domain x stage migration matrix，明确 `libraryMetadata` 是唯一 active pilot domain。 |
| 允许范围 | 新增/维护 diagnostics-only matrix、global config validator、`libraryMetadata` readiness gap audit、其它 domain static/default-off audit、双端 matrix tests 和文档。 |
| 明确禁止 | 不执行真实 canary；不 production commit；不切 UI；不切 read path；不删除 legacy；不改 retry drainer、Mac pending sync、upload route 或 audio upload runtime；不让 `generatedArtifacts`、`tombstoneConflict`、`audioUpload` 成为 active pilot。 |
| 进入条件 | 当前 5 个域 write 机器件均默认关闭，读路径仍 legacy；Claude/manual audit 已指出“广度已够、深度为零”；用户明确选择先打通 `libraryMetadata`。 |
| 退出条件 | matrix 只能允许一个 explicit active pilot；global guard 阻断多域 active、非 `libraryMetadata` active、runtime switch、default/release cutover、pilot 完成前 audio/tombstone/generated 真实迁移、read-side cutover 前 legacy retirement；libraryMetadata readiness 和其它域 static audit 有测试覆盖。 |
| 必跑测试 | 双端 `CanonicalMigrationMatrixTests`、双端 `CanonicalLibraryMetadataCutoverTests`、iPhone/Mac Debug build、`git diff --check`、`git status --short`。 |
| 是否允许真实写入 | 否。 |
| 是否允许 network | 否。 |
| 是否允许 suppress legacy | 否。 |

## 14. v8.14 - libraryMetadata guarded commit seam, canary N=0

| 项目 | 内容 |
| --- | --- |
| 目标 | 把 `libraryMetadata` pilot 的 N0 gate 接到双端 app diagnostics seam。只评估 guarded commit evidence、gate、no-execution assertion 和 N1 readiness report，不执行任何对象。 |
| 允许范围 | 共享 `CanonicalLibraryMetadataGuardedCommitSeam`、`CanonicalLibraryMetadataNoExecutionAssertion`、`CanonicalLibraryMetadataN1ReadinessReport`；iPhone `performTick` legacy diff 后 report-only seam；Mac `/sync/inventory` response 构建后 report-only seam；双端 seam/matrix/cutover tests 和文档。 |
| 明确禁止 | 不调用 commit executor；不调用 `CanonicalLibraryMetadataCutoverRunner`；不调用 real apply port；不发送 `/sync/apply-metadata`；不调用 `StudyLibraryStore.applySyncManifest`；不写 production root 或 metadata JSON；不 suppress legacy duplicate；不改 legacy/canonical plan、action count、pending count、Mac inventory response、route/security、retry drainer、upload job、UI、read path 或 legacy retirement。 |
| 进入条件 | v8.13 matrix 已确认 `libraryMetadata` 是唯一 active pilot；其它 domain static-only/blocked；libraryMetadata projection/planner/app seam/NoCommit/real apply/commit executor 机器件存在但默认关闭；manual/Claude audit 确认 N0 不执行。 |
| 退出条件 | 双端显式 v8.14 seam 在 canary `N=0` 下记录 started/completed/blocked/gate/canary-zero/commit-not-executed/fallback-preserved/duplicate-suppression-not-applied diagnostics；`CanonicalLibraryMetadataNoExecutionAssertion` 通过；N1 readiness 只报告 blocker/status；legacy plan/response/side effects unchanged。 |
| 必跑测试 | 双端 `CanonicalLibraryMetadataGuardedCommitSeamTests`、双端 `CanonicalMigrationMatrixTests`、双端 `CanonicalLibraryMetadataCutoverTests`、iPhone/Mac Debug build、`git diff --check`、`git status --short`。 |
| 是否允许真实写入 | 否。 |
| 是否允许 network | 否。 |
| 是否允许 suppress legacy | 否。 |

## 15. v8.18 - libraryMetadata production canary enablement N=1

| 项目 | 内容 |
| --- | --- |
| 目标 | 在 `libraryMetadata` 唯一 active pilot 上补齐 production canary wrapper、observation report、diagnostics 和双端 explicit bootstrap；仍只允许 N=1。 |
| 允许范围 | 共享 `CanonicalLibraryMetadataProductionCanaryConfiguration` / policy / injection result / observation report；iPhone/Mac explicit bootstrap 构造 test-root real apply port 和 cutover executor；双端 production canary tests 和文档。 |
| 明确禁止 | 不默认注入 executor；不启用 N>1/allEligible/runtime switch/release default；不切 read path/UI；不删除 legacy；不移动资源；不写 standalone note content；不改 route/security/retry/Mac pending sync/audio upload。 |
| 进入条件 | v8.17 read-side parallel evidence 存在；v8.13 matrix 仍只有 `libraryMetadata` active pilot；N1 canary runner、root-bound real apply port、rollback/fallback、success-only suppression 和 redacted diagnostics 均已测试。 |
| 退出条件 | 默认 disabled；armed no-execution；execute 需要 explicit internal/debug、owner token、rollback/read-side/write-side evidence、local/peer snapshot 和 injected executor；success-only duplicate suppression；failure rollback/fallback；production root 默认 blocked。 |
| 必跑测试 | 双端 `CanonicalLibraryMetadataProductionCanaryTests`、双端 `CanonicalLibraryMetadataCanaryTests`、双端 `CanonicalLibraryMetadataReadSideTests`、iPhone/Mac Debug build、`git diff --check`、`git status --short`。 |
| 是否允许真实写入 | 是，仅 explicit N=1 canary 的一个 metadata candidate，且必须 root-bound、rollback-covered；默认和 armed 不写。 |
| 是否允许 network | 否；不新增 route，不发送新 network path。 |
| 是否允许 suppress legacy | 是，仅 commit success 且 pre/postcondition verified 的 matching libraryMetadata duplicate。 |

## 16. 安全红线

以下红线适用于 v8.4-v8.18 每一阶段：

- 不把 `manifestHash` 当鉴权、授权、信任或 route allow 依据。
- 不绕过 TLS pinning、HMAC、nonce、timestamp、body hash、signature、content-type、Keychain 或 `RequestVerifier`。
- 不新增 route；`.applyMetadata` 只能映射既有 `/sync/apply-metadata`。
- 不自动下载 audio。
- 不把 metadata uploaded、manifest applied、receive record existing、UI uploaded 当成 audio uploaded。
- 不把 completed ledger 单独当 no-op；audio no-op 必须由 peer `audioAvailable=true` + same hash + same size 证明。
- 不把 peer unknown 当 missing；普通 sync 必须 deferred。
- 不覆盖 Mac existing different audio；hash/size 不同必须 conflict/fatal，并保持人工可见。
- 不物理删除 audio、transcript、note、summary；不 permanent delete；不 tombstone GC。
- 不为 generated artifact 创建 upload job；generated artifact download/apply 必须继续走既有 `/sync/artifact-request` 和 checksum/size 校验。
- 不让 view refresh、列表/详情 onAppear、学习库 refresh 或 Mac inbox refresh 创建 upload job。
- 不让 UI display state 反向驱动 sync、upload、retry 或 apply。
- 不把完整 metadata JSON、完整 transcript、完整 note、完整 summary、provider response、secret、shared secret、API key、TLS private key、完整 fingerprint、完整 hash、完整 request/response body 或本机隐私路径写入 diagnostics/docs。
- 不把 root token / logical path token 当成真实生产文件授权；真实 port 必须绑定 root、store root、containment check 和 rollback checkpoint。
- 不让 dry-run equivalent、port declared、readiness candidate、shadow green 或 NoCommit report 被解释为 runtime switch 许可。

## 17. 审计与回滚要求

每个版本必须有进入审计和退出审计：

- 进入审计：确认上一阶段 exit criteria 全部满足，确认当前阶段默认 off，确认 legacy fallback 可用，确认 rollback plan 覆盖 required domains。
- 退出审计：确认真实 side effects 与本阶段允许范围一致，确认 diagnostics redacted，确认 failure path rollback/fallback 可复现，确认未影响未迁移 domains。
- Claude/manual audit 均不可跳过；若审计发现 blocker，下一轮只能修 blocker，不扩 domain。
- 任何阶段出现 rollback fatal blocker、unexpected side effect、security boundary regression、route/security change、UI state 驱动业务状态、audio truth regression，都必须停止扩大 canary 并回退到 legacy fallback。

## 18. 必须明确的时间点

- v8.4 只是 fake/in-memory hardening。
- v8.5 才实现 real root-bound apply port。
- v8.7 才开始 N=1 canary。
- v8.14 只做 `libraryMetadata` guarded commit seam N=0；UI canonical projection cutover 和 legacy retirement gates 后移到 v8.14 之后的独立任务。
- v8.18 只做 `libraryMetadata` production canary N=1 wrapper/bootstrap；N>1、read-side cutover、UI switch 和 legacy retirement 仍后移。
- 任何阶段都不能跳过 Claude/manual audit。
