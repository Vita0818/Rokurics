# Rokurics 新内核：接入现状 + 给 Codex 的 v8.0 工作方向 只读审计报告

- 审计时间：2026-06-03 17:05 (CST)
- 用途：① 判断新内核（Canonical）现在接入到什么地步；② 给出"还未接入部分"的工作方向，**作为可独立交接给 Codex 的文档**（下一次从 v8.0 开始；v7.6/v7.7 对话已丢失，本文不依赖那段上下文）。
- 审计方式：**只读**。重新读取当前源码；未修改任何代码/配置/脚本/测试；未运行构建或测试。唯一写入为本报告。
- 不含密钥/指纹/完整路径等敏感信息；定位以「文件:行号」给出。

> 当前未提交工作区状态：`SyncCore` 共 28 文件 / 约 17,308 行；最近 commit 仍是 `aae5d79 v7.6`，v7.7 及之后均为未提交改动。

---

## Part A — 现在接入到什么地步

### A.0 一句话

**运行时仍 100% 走旧内核；canonical 目前只作为"影子/观察者"接入，且全部默认关闭。** 影子链路本轮已推进到很深的程度（决策影子 → 执行影子 → 真实数据只读副本 → 只读传输探针 → 临时根清理），但**真正的"切换执行（cutover）"模块虽已写好且可提交到真实根，却没有接进 app**——只在测试/Facade 可达。所以新内核**尚未在任何一端承担一丝真实生产职责**。

### A.1 已接入 app（默认关闭，翻开关才跑）

iPhone `StudyLibrarySyncCoordinator`、Mac `SecureLocalHTTPSServer` 的同步路径里，`performTick`/inventory 阶段调用了影子接缝，**两个配置默认 `.disabled`**（`StudyLibrarySyncCoordinator.swift:1793-1794`）：

| 能力 | 位置 | 性质 |
| --- | --- | --- |
| 决策影子（canonical 决策 vs 旧 legacy 比对） | `:2189` `CanonicalShadowMigrationRunner().run` | 只比对，落诊断 |
| 执行影子（真跑文件执行进**隔离临时根**） | `IPhoneCanonicalShadowFilePort` + 工厂 | 真原子写/containment/回滚，但只进 temp 根 |
| **真实数据只读副本**（把真实录音/metadata/manifest 复制进影子根再执行） | `:2217 makeIPhoneRealDataShadowCopyIfEnabled` → `IPhoneCanonicalRealDataShadowCopyAdapter` | 读真实、写影子根；gated 到 `executionShadowWithShadowFileStore` |
| **只读传输探针**（route=syncInventory） | `:2245 makeIPhoneReadOnlyTransportProbeIfEnabled` | 评估请求只读性；`manifestHashUsedAsAuth:false`（守住安全边界） |
| **执行影子临时根清理** | `:2270 cleanupIPhoneExecutionShadowRootIfNeeded` | 上一轮我提的临时根堆积风险，本轮已修 |

安全闸门仍在且更全：`validatedShadowRootURL()` 拒绝生产根及其子目录（`CanonicalExecutionShadow.swift:35/53`）；影子传输 `sendRequest` 抛 `networkExecutionSuppressed`；影子 apply/upload 端口对真实变更 fail-closed。

### A.2 已写好但**未接入 app**（仅测试/Facade 可达）

- **录音 metadata 切换（cutover）**：`CanonicalRecordingMetadataCutover.swift` 定义了 `CanonicalCutoverMode`：`disabled / shadowOnly / guardedExecuteNoCommit / guardedExecuteCommit`（`:49-52`），含真实提交事件 `canonicalRecordingMetadataProductionCommit{Started,Completed,Failed}`（`:430-432`）与部分提交失败处理（`applyFailureAfterPartialCommit`）。
- 但它只经 `CanonicalIPhoneMigrationFacade/CanonicalMacMigrationFacade.runRecordingMetadataCutover(...)`（`CanonicalIPhoneMigrationFacade.swift:179`）暴露，而**这两个 Facade 在 app 同步/接收/入口里零调用**（grep 确认："NONE in app sync/receiver/app entry"）。
- 即：**"把某个域切到 canonical 真实执行"这一步，连 `guardedExecuteNoCommit`（执行但不提交）都还没接进 app**；`guardedExecuteCommit`（真提交真实根）更没有。

### A.3 仍是旧内核的部分

真实文件落盘、真实 TLS+HMAC 传输、真实 resumable 上传、apply 写回、UI 读取——**运行时全部仍是 legacy**。canonical 的真实生产端口只在测试可达；真机上 canonical 不写真实数据、不发网络变更、不被 UI 读取。

### A.4 接入阶梯（打勾即现状）

1. ✅ 语义/决策内核为真相源（影子）
2. ✅ 生产适配器（真实执行逻辑）写好
3. ✅ 双端决策影子接缝（默认关）
4. ✅ 双端执行影子（隔离临时根，默认关）
5. ✅ 真实数据**只读副本** + 只读传输探针 + 临时根清理（默认关）
6. ⬜ **cutover 接入 app（先 guardedExecuteNoCommit）** ← 下一步
7. ⬜ guardedExecuteCommit（单域真实根提交）
8. ⬜ 逐域扩展 → UI 读 canonical → 退役 legacy

**结论：接入深度＝"影子全链路就绪（含真实数据只读副本），但尚未跨过'执行不提交'这道门"。** 对生产零风险（最危险的真实提交被刻意挡在 app 之外）。

---

## Part B — 给 Codex 的 v8.0 工作方向（未接入部分）

> 总原则（红线，全程不可破）：**默认关闭 · 一次只推一个域 · 影子先于执行 · 执行先"不提交"后"提交" · 每道门要回滚演练 · 绝不把影子/执行指向生产根 · `manifestHash` 永不当鉴权（TLS pinning + HMAC 必须保留）。**

### B1.（最高优先）把 cutover 接进 app，先只到 `guardedExecuteNoCommit`，且只做"录音 metadata"一个域

- 现状：cutover 模块与 runner 已写好，但只在 Facade/测试可达（A.2）。
- 要做：在 `StudyLibrarySyncCoordinator`（iPhone）与 `SecureLocalHTTPSServer`/`SecureReceiverService`（Mac）里，新增一个**默认关闭**的配置项（仿 `canonicalShadowMigrationConfiguration` 模式），在 tick/inventory 后调用 `CanonicalRecordingMetadataCutoverRunner`，模式锁死为 `guardedExecuteNoCommit`。
- 提供真实执行器 `CanonicalRecordingMetadataCutoverExecutor` 的生产实现：iPhone 绑 `AudioFileStore`、Mac 绑 `MacRecordingFileStore`，但在 NoCommit 模式下**只写入暂存/影子位置 + 与 legacy 逐字节比对**，**不替换真实文件**。
- 验收：真机开启后，诊断里 `…ProductionCommitStarted` 不应出现；只出现"执行成功但未提交 + 与 legacy 字节等价"。差异必须为 0。

### B2. 让"只读传输探针"真正上线（只读、不落库）

- 现状：`makeIPhoneReadOnlyTransportProbeIfEnabled` 调的是 `CanonicalReadOnlyTransportProbe().evaluate(...)`，是对"请求是否只读"的**分类评估**；影子传输 `realNetworkExecutionEnabled=false`，并不真发。
- 要做：实现一个**真实只读发送**路径，复用现有 `SecureMacUploadClient` 的 TLS pinning + HMAC，**只允许幂等只读路由**（`/sync/inventory`、`/fingerprint`、`/health`）。
- Mac 侧加断言/护栏：**影子探针请求绝不创建 receive 记录、不改任何状态**（可在 receiver 加一个"探针标记→只读"短路并计数）。
- 验收：探针往返成功；Mac 端 receive 计数/状态零变化。

### B3. 真实数据只读副本：补"源未被改动"的硬证明

- 现状：`IPhoneCanonicalRealDataShadowCopyAdapter` 读真实源、写影子根（A.1）。
- 要做：加测试断言**复制前后真实源文件的 mtime/size/hash 不变**（read-only 证明）；并确认 `executionShadowWithShadowFileStore` 下 copy→执行→比对→清理闭环在 Mac 端同构存在。
- 验收：源零改动；副本与源 hash 一致；清理后临时根被回收（沿用 `cleanup…`）。

### B4.（过门后）单域 `guardedExecuteCommit`：录音 metadata 先行

- 前置闸门（**全部满足**才允许把该域切到 commit，且仍默认关）：
  1. 决策影子分歧 = 0；
  2. 执行影子在**真实数据只读副本**上与 legacy **逐字节等价** = 0 diff；
  3. **故障注入回滚演练通过**：写中断 / 部分提交（`applyFailureAfterPartialCommit`）/ 磁盘满 / 权限失败 都能回滚到检查点；
  4. **重试幂等**证明（同一 cutover 重跑不产生双写/脏状态）；
  5. 崩溃安全：metadata 原子替换 + 与 receive.json 一致。
- 要做：把该域 executor 的 NoCommit 升为 Commit（真实根原子替换 + 回滚检查点），仍受 `CanonicalProductionExecutionGuard`（approval + rollback + dryRun 等价 + 执行影子等价）把关；保留 `…ProductionCommitFailed` 落诊断与自动回滚。
- 验收：观察期内该域 canonical 提交与 legacy 行为一致、无回滚触发、无数据异常。

### B5. 逐域扩展（严格按危险度，一次一个）

顺序建议：录音 metadata → 生成产物（转写/笔记，相对可重生）→ 文件夹/学习项 metadata → tombstone/删除 → **录音音频上传**（最重、放最后）。每个域都走 B1→B4 同一阶梯。

### B6. UI 读 canonical 投影（倒数第二步）

- 用 `CanonicalObjectProjection` 驱动 UI 显示，先**并行展示 legacy vs canonical**，差异为 0 再切主读。
- 注意 `CanonicalRetirementReadiness` 里 `uiStillReadsLegacyStatus` 阻断项需在此清除。

### B7. 退役 legacy（最后）

- 当 `CanonicalRetirementReadiness` 各域达到可退役、且观察期通过，逐域删除 legacy 执行分支（保留影子比对一段时间作回归闸门）。

---

## Part C — 给 Codex 的"开工自检清单"（v8.0 第一条 PR 之前）

1. 读这几个文件建立现状：`RokuricsShared/SyncCore/CanonicalShadowMigration.swift`、`CanonicalExecutionShadow.swift`、`CanonicalRecordingMetadataCutover.swift`、`CanonicalRealDataShadowCopy.swift`、`CanonicalReadOnlyTransportProbe.swift`；接缝在 `Rokurics/StudyLibrarySyncCoordinator.swift:2107-2300` 与 `RokuricsMac/SecureLocalHTTPSServer.swift:3185+`。
2. 确认两个 shadow 配置默认 `.disabled`，且你新增的 cutover 配置也默认 `.disabled`。
3. 任何"执行/提交"路径都要先过 `CanonicalProductionExecutionGuard` 与 `validatedShadowRootURL()` 这类 fail-closed 守卫。
4. 每个 PR 只动一个域 / 一个阶梯档位；附：单测 + 真机影子诊断截图（分歧/等价/回滚）。
5. 不改 `manifestHash` 的用途（完整性，非鉴权）；不绕 TLS pinning / HMAC / nonce。

---

## Part D — 当前风险评估（回应"不出 bug"）

- **生产风险：实质为零。** 真实提交被挡在 app 之外（cutover 未接入）；影子全默认关；执行影子只进临时根并拒绝生产根；传输发送被抑制；临时根有清理。
- 唯一要 Codex 在 B 阶段持续守住的，是**每跨一道门都先回滚演练 + 字节等价**，并保持"一次一个域"。

---

## E. 本轮只读核对的关键位置

- 接缝与默认关：`Rokurics/StudyLibrarySyncCoordinator.swift:1776-1809/2107-2300`；`RokuricsMac/SecureLocalHTTPSServer.swift:957/3185+`。
- 执行影子/真实数据副本/探针/清理：`:2189/2217/2245/2270`；`Rokurics/IPhoneCanonicalShadowFilePort.swift`、`IPhoneCanonicalShadowTransportPort.swift`、`IPhoneCanonicalRealDataShadowCopyAdapter.swift`。
- 安全闸门：`RokuricsShared/SyncCore/CanonicalExecutionShadow.swift:35/53`（拒生产根）、读只路由分类（`:276-395`）。
- cutover（已写未接入）：`CanonicalRecordingMetadataCutover.swift:49-52/430-432`；`CanonicalIPhoneMigrationFacade.swift:179`（仅 Facade/测试可达，app 零调用）。

## F. 不确定项 / 说明

- 未运行构建/测试；结论基于静态阅读 + 端口/护栏/默认配置/调用点交叉印证。
- 评价基调：v7.7 把"影子→执行影子→真实数据只读副本→只读探针"打通且默认关、并修了临时根清理，是高质量的稳步推进；"尚未接入"特指 **cutover 未进 app、真实提交未发生**，并非设计有误。
- `git status` 中 `.swift` 改动均为你/Codex 在途工作；本轮我仅 Read/grep，未改动任何源码；唯一新增为本报告。
