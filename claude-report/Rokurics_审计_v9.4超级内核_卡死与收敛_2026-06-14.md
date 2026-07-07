# Rokurics 审计 · v9.4 四域超级内核 · 9000ms 卡死与状态不收敛

- 时间：2026-06-14 19:10 (CST)
- 方式：**只读**审计,对照你上传的《CANONICAL_LOCAL_KERNEL_FOUR_DOMAINS.md》四域规格。未改代码。
- 现象:两端全 `canonicalFullSync`,频繁 9000ms+ 卡死 + 若干 500ms 小卡顿;状态收敛仍未做好。
- 规模:SyncCore 已 **77,361 行 / 81 文件**。

---

## 0. 一句话
**Codex 又是"写了 v9.4 的类型,跳过了规格明令最先做的 v9.1 不卡顿"。** 规格路线图是 **v9.1(File Kernel 不卡顿)→ v9.2/9.3(连接/传输)→ v9.4(状态真相)**;Codex 把 v9.4 的类型写了一堆,但**你真正痛的两件——9000ms 卡死、状态收敛——恰恰都在它跳过/没接线的层里**。

---

## 重点 A · 为什么 9000ms 卡死(根因精确、可修)

### A1【主因·9000ms】同步诊断风暴
`ConnectionDiagnosticsStore` 是普通 `final class`(非 actor、非异步,`ConnectionSyncStateStores.swift:585`)。它的 `record()` **每被调一次**就(:640-649):
1. `loadEntries()` 读取并 JSON 解析**整个** jsonl;
2. 把全部条目(上限 200)**重新编码**;
3. `Data(...).write(to: logURL, options: .atomic)` **原子重写整个文件**。
全部**同步**,跑在调用方线程上。而调用方是 `@MainActor` 协调器,`diagnosticsStore.record(...)` 在其中有 **367 处**调用,一个同步 tick 会命中其中几十处;`canonicalFullSync` + 事件驱动(~5s)+ 心跳唤醒下,主线程被"读整文件→解析→编码→原子写"反复砸 → **秒级直至 9000ms 卡死**。

> 这正是规格 §9.2 / §10 / §12 三处**明令禁止**的:"no synchronous diagnostics/status JSONL write on MainActor hot path""async diagnostics writer""diagnosticsWriteDurationMs"。

### A2【讽刺点】v9.1 要求的异步写入器**写了,但没接**
`CanonicalAsyncDiagnosticsWriter.swift` **存在**(Codex 按 v9.1 建了),但:
- 协调器里出现 **0 次**;
- 全仓库除自身定义外**无人调用**(孤儿件)。
→ **该修卡顿的异步写入器被造出来当摆设,真正的热路径(367 处)还在用同步 `ConnectionDiagnosticsStore`。** 典型"造了新件、没迁热路径"。

### A3【次因·500ms】读缓存 key 含 `generatedAt`,必然抖动
`canonicalEffectiveCacheKey`(Mac `StudyLibraryStore.swift:609`)把 **`generatedAt=<时间戳>`** 放进了 key(:627)。每次快照重建 `generatedAt` 都是新 `Date()` → key 变 → **缓存必 miss → 每次都重建投影 + 重建整棵学习树**(尽管内容没变)。
→ 上一轮加的读缓存因此**形同虚设**;这正是规格 §9.2 点名的:"cache key is content-stable, not generatedAt-only"。这是 500ms 小卡顿的主要来源。

### A4【加重】v9.4 又往主线程加了活
状态真相运行时(`CanonicalStatusTruthRuntime` 等)被 `@MainActor` 的 `StudyLibraryStore`/协调器/`SecureLocalHTTPSServer` 引用——每 tick/每访问又叠加一层状态事实重算。**v9.1 没修,v9.4 还在加主线程负载,所以比以前更卡。**

---

## 重点 B · 为什么状态仍不收敛

### B1 EffectiveSyncStatus 类型建了,但 **UI 不读它**
v9.4 的状态真相类型齐全(8 个文件:`CanonicalStatusFact/Proof/EffectiveSyncStatusProjection/StatusFactStore/StatusReconciliation/StatusTruthRuntime/…`)。**但 UI 视图(RecordingLibraryView / MacStudyLibraryView / MacAudioInboxView / RecordingStatusView / RecordingStudyDetailPage)没有一个引用 `EffectiveSyncStatus`**——状态仍从 upload ledger / receive record / 本地文件存在 等多处各自拼。
→ 规格 §7.1 与 §15"完成"硬规则 **"UI state comes only from EffectiveSyncStatus"** 未达成。引擎在底层算了事实,UI 不消费 → **用户看不到任何收敛改善**。

### B2 Connection / Transfer 仍是 legacy 外围
`CanonicalConnectionProtocol / CanonicalTransferProtocol / CanonicalTransferRuntime` 等**协议+配置类型**建了,但:
- `CanonicalTransferRuntime` 默认 `ownerApprovedCanonicalTransfer=false`、`legacyFallbackEnabled=true`(:34-36)——**默认不接管**;
- 双端 app 各仅 **1 处**引用 → 基本未集成。
→ 真正能让状态**实时交换**的层(v9.5 Realtime Status Exchange)几乎没起步;连接/传输仍 legacy。状态事实没有 canonical 实时通道在两端之间流动,自然不收敛。

### B3 收敛的本质仍卡在 v9.5 没做
规格说得很直白(§55):收敛依赖"何时、由谁、通过哪个通道、带什么 proof、把哪个状态告诉谁"。这是 **v9.5 Realtime Status Exchange** 的活。v9.4 只把"状态真相"的**本地类型**写了,**跨端交换协议(delta/ack/request/sequence)没有运行**,所以两端各自有"真相"却互不传递 → 仍不收敛。

---

## 对照规格 §15「完成」逐条打分

| 完成条件 | 现状 |
| --- | --- |
| Connection Kernel 拥有 peer liveness + 状态交换载体 | ❌ 仍 legacy(协议类型在,未接管) |
| Transfer Kernel 拥有可续传状态机 + finalize proof | 🟡 类型/runtime 配置在,默认不接管 |
| Sync Kernel 拥有状态真相 + **状态交换** + diff/apply/read + 事件触发 | 🟡 真相类型在、事件触发在;**实时交换未运行** |
| File Kernel 拥有 no-freeze runtime | ❌ **同步诊断写未消除、缓存 key 抖动**(核心未达成) |
| 一个开关控四域 | 🟡 开关在,四域未全接管 |
| oldKernel 可即时切回 | ✅ 保留 |
| **UI 只从 EffectiveSyncStatus 取状态** | ❌ UI 未读 |
| **无 MainActor 重活(文件/同步/状态)** | ❌ 诊断风暴 + 缓存重建 + 状态重算全在主线程 |
| 无路由/安全绕过 | ✅(沿用 legacy 安全) |
| 无 peer proof 不显示完成 | 🟡 引擎有 proof 概念,但 UI 未用 |
| 诊断能解释延迟与不收敛 | 🟡 计数类型多,但**诊断写入本身就是卡顿源**,且热路径未用异步写 |

→ **11 条里 ❌4 / 🟡5 / ✅2。按规格自身定义,远未"完成";而且最硬的两条(File no-freeze、UI 只读 EffectiveSyncStatus)正是你两个症状的对应项。**

---

## 方向(必须回到规格的顺序:先 v9.1)
不是再写更多 v9.4/9.5 类型,而是**把 v9.1 真正落到热路径**:
1. **灭 9000ms**:让 `ConnectionDiagnosticsStore.record()` 不再在主线程同步整文件重写——改成**追加写 + 后台串行队列/actor**,并把现有 367 处热路径真正接到 `CanonicalAsyncDiagnosticsWriter`(它已存在,只是没接)。这是最高优先、最直接的灭卡。
2. **灭 500ms**:把读缓存 key 改成**内容稳定**(对象集合的稳定指纹),去掉 `generatedAt`,让缓存真正命中、不再每次重建树。
3. **降主线程负载**:状态真相重算移出 `@MainActor`(后台算、UI 只读结果)。
4. **再谈收敛**:把 **UI 改成只读 `CanonicalEffectiveSyncStatus`**(B1),并推进 **v9.5 实时状态交换**(B3)让两端真正交换 proof——这才是收敛的正解。
5. 顺序别再颠倒:**v9.1 不卡顿 → v9.5 交换 → UI 接 EffectiveSyncStatus**,而不是继续堆类型。

---

## 附 · 只读核对位置
- 9000ms 主因:`Rokurics/ConnectionSyncStateStores.swift:585`(final class)、`:601-649`(record 同步 loadEntries+整文件 atomic 重写);协调器 `diagnosticsStore: ConnectionDiagnosticsStore`(:64)、367 处 record;`CanonicalAsyncDiagnosticsWriter` 协调器引用 0 次、全仓库无调用(孤儿)。
- 500ms:`RokuricsMac/StudyLibraryStore.swift:609/627`(cacheKey 含 generatedAt)。
- v9.4 类型:`RokuricsShared/SyncCore/CanonicalStatusFactStore / CanonicalStatusReconciliation / CanonicalEffectiveSyncStatusProjection / CanonicalStatusTruthRuntime / CanonicalSyncStatusTruthProtocol / CanonicalRealtimeStatusExchangeProtocol.swift`。
- UI 未读:RecordingLibraryView / MacStudyLibraryView / MacAudioInboxView / RecordingStatusView / RecordingStudyDetailPage 均无 `EffectiveSyncStatus` 引用。
- Connection/Transfer 未接管:`CanonicalTransferRuntime.swift:34-36`(默认 ownerApproved=false/legacy=true);双端各 1 处引用。
