# Rokurics 新内核：是否具备"下一轮 shadow migration"接口基础 只读审计报告

- 审计时间：2026-06-02 17:49 (CST)
- 审计问题（按你的限定）：**只判断新内核是否已具备开始下一轮 shadow migration 的接口基础**；不评价旧内核是否臃肿。
- 审计方式：**只读**。重新读取当前源码；未修改任何代码/配置/脚本/测试；未运行构建或测试。唯一写入为本报告。
- 不含密钥/指纹/完整路径等敏感信息；定位以「文件:行号」给出。

---

## 0. 直接结论

**接口基础：基本具备（可以开始 shadow migration 这一阶段的工作）。但当前的 shadow 只能在测试 harness 里对"合成数据"跑，还不能在真机上对"你的真实库"跑——下一轮 shadow migration 的第一步，正是把适配器接到真实存储 + 加 app 接缝。**

换句话说：**"造好了什么"是真的**——可调用 Facade、生产端口协议、生产形态适配器（带 `isInsideRoot`、回滚检查点、真 resumable 校验）、默认关闭的执行护栏、回滚计划、影子准备入口、legacy 等价比对，全都在，且测试齐全。**"还差什么"也是确定的**——适配器只绑定测试根/内存、传输被抑制、生产执行被硬锁在 testHarness、且 app 路径里没有任何接缝。

所以对你的问题"新内核状态是否允许我开始从旧内核迁移"：**可以开始——但开始后的第一批任务不是'切流量'，而是'把这套接口接到真实数据与真实传输上、并在 app 里留一个默认关闭的影子钩子'。** 这与 Codex 自述"全部写好但默认关闭"一致；我补充的是：**"写好"= 接口与测试基底写好；尚未连到生产基底。**

---

## 1. 接口基础：已具备的部分（逐项核对，均属实）

| 能力 | 是否具备 | 证据 |
| --- | --- | --- |
| 可调用 Kernel Facade | ✅ | `CanonicalKernelFacade.swift`：`planSync/buildApplyPlan/buildLibraryPlan/compareLegacy/dryRunMigration/executeOffline/executeProduction/rollbackPreview` |
| 执行模式开关，默认关闭 | ✅ | `CanonicalKernelExecutionMode` 含 `disabled/dryRun/productionShadow/productionExecute/offlineRuntime`；Facade 与 MigrationFacade 默认 `.disabled`（`CanonicalIPhoneMigrationFacade.swift:16`） |
| 生产端口协议（边界 API） | ✅ | `CanonicalProductionPorts.swift`(1483 行) 7 端口；本轮新增 File/Transport/Upload/Apply/Snapshot 协议方法 |
| 生产形态适配器（可执行语义） | ✅（基底为测试） | File 端口真做 `write(to:.atomic)`+`isInsideRoot`+回滚检查点（`IPhoneCanonicalProductionFilePort.swift:179/211/242/305/436`）；Upload 端口真做 resumable offset/chunkHash/finalize 校验（`IPhoneCanonicalProductionUploadPort.swift:67-89`） |
| 执行护栏（默认拒绝） | ✅ | `executeProduction` 经 `CanonicalProductionExecutionGuard.evaluate`，拒绝原因含 `modeDisabled/missingApproval/missingRollbackPlan/dryRunNotEquivalent`（`CanonicalProductionExecution.swift:193-197`、`CanonicalKernelFacade.swift:368-404`） |
| 回滚计划 + 预览 | ✅ | 文件/metadata 检查点与回滚动作（`CanonicalIPhoneMigrationFacade.swift:156-178`）；File 端口写前存 `previousBytes`（`:242`） |
| 影子准备入口 | ✅ | `prepareShadowExecution(...)` 打包 dryRunPlan+migrationGate+equivalenceReport+productionInput（`:101-124`） |
| legacy 等价比对 | ✅ | `compareLegacy(...)` → `CanonicalLegacyEquivalenceReport`（按域给分歧等级） |
| 测试覆盖 | ✅ | 新增 `CanonicalKernelFacadeTests / CanonicalMigrationFacadeTests / CanonicalProductionAdapterTests / CanonicalProductionExecutionGuardTests / CanonicalRollbackPlanTests / CanonicalProductionPortContractTests` |

**评价**：作为"下一轮 shadow migration 要用的接口与护栏"，这套脚手架是齐的、而且设计得克制安全（默认关、要审批、要回滚、要 dry-run 等价才放行）。这一点 Codex 没夸大。

---

## 2. 但"开始真机 shadow"还缺的接缝（决定能否真正开跑）

### 2.1 适配器只绑定"测试根/内存"，没有连到真实存储

- 端口集工厂只有两种：`makeDisabledPortSet()` 与 `makeFakeInMemoryPortSet(rootURL: 测试根, transportResponder: 假响应, upload: fakeInMemory, apply: fakeInMemory)`（`CanonicalIPhoneMigrationFacade.swift:187-213`）。**没有**绑定 `AudioFileStore / MacRecordingFileStore / SecureMacUploadClient` 的"真实端口集"工厂。
- File 端口只有 `.testRoot` 模式（`IPhoneCanonicalProductionFilePort.swift:13`）+ 一个禁用 `init()`；**没有生产根模式**。即使"真写文件"，也只能写进测试根，无法指向真实 `Documents/Rokurics/Recordings`。
- Upload 端口是**内存账本**（`InMemoryCanonicalFileStore.hash`、`state.buffer.append`，`:76/83`），不是真网络上传。

→ 含义：今天就算把模式打开，shadow 也是在**对合成/测试数据**做对照，不是对你真实学习库做对照。

### 2.2 传输被显式抑制，生产执行被硬锁在测试 harness

- Transport 生产端口："production send suppressed"、"fake signer; no URLSession"（`IPhoneCanonicalProductionTransportPort.swift:24/36`）——**不真正发网络**。
- `executeWithGuard` 仅在 `allowTestHarnessProductionExecution && token.nodeRole == .testHarness` 时才走真执行，**否则强制改用 `.disabled` Facade 并拒绝**（`CanonicalIPhoneMigrationFacade.swift:130-138`）。即真机 iPhone/Mac 角色根本进不了执行分支。

→ 含义：同步本质是跨设备，而跨设备的真实/影子发送当前不可用；on-device 执行被结构性锁死在测试角色。

### 2.3 app 路径里没有任何接缝

- 在 `StudyLibrarySyncCoordinator / SecureLocalHTTPSServer / SecureReceiverService / RokuricsApp` 内**搜不到**对 Facade/MigrationFacade 的调用。
- 即运行中的 app 既不会（哪怕默认关闭地）构造影子输入，也没有"影子并行 + 比对落诊断"的钩子。

→ 含义：下一轮要先在 app 里加一个默认关闭的影子调用点，shadow 才"在产品里发生"。

---

## 3. 判定：是否允许开始 shadow migration

**允许开始这个阶段——因为接口/护栏/回滚/比对的"骨架"齐了。** 但要清楚 shadow migration 的**第一批任务恰好是补 2.1–2.3**，而不是直接观察影子结果：

下一轮 shadow migration 的最小起步清单（建议顺序）：

1. **真实端口集工厂**：新增把 File 端口指向真实录音根（FilePort 增加"生产根模式"）、Upload 端口接 `SecureMacUploadClient`/真实 resumable、Apply 端口接真实写回的 `make...ProductionPortSet(realStores...)`。
2. **传输影子化**：让 Transport 端口至少能"按真实 TLS+HMAC 规则构造并（影子地）发送/比对"，解除 send 抑制（鉴权红线：`manifestHash` 不当鉴权，TLS pinning+HMAC 必须用现成的）。
3. **解锁 on-device 影子角色**：把 `executeWithGuard` 的 testHarness 硬锁，放宽为"默认关闭、可灰度开启的 `productionShadow` 角色"（仍走护栏：审批+回滚+dry-run 等价）。
4. **app 接缝**：在 `performTick`（及 Mac receiver）里加默认关闭的影子调用——构造快照→Facade 影子执行→`compareLegacy` 落 `canonical-shadow.jsonl` 与 divergence 诊断。
5. **验收口径**：影子分歧（`CanonicalLegacyEquivalenceReport` 的 `canonicalOnly/legacyOnly/conflict/unsupported`）趋零、回滚演练通过、护栏 reject 清零，再谈切主。

完成 1–4 才算"真机 shadow 真正开跑"；第 5 步是从 shadow 走向 cutover 的闸门。

---

## 4. 一句话回答你的问题

- **接口基础是否具备？** 具备（Facade + 生产端口 + 生产形态适配器 + 默认关闭护栏 + 回滚 + 影子准备 + 等价比对 + 测试，齐全且设计安全）。
- **是否可以开始从旧内核迁移（进入 shadow 阶段）？** 可以开始——但"开始"等于先做第 3 节的 1–4 项接线；**当前 shadow 只能在测试 harness 对合成数据跑，尚不能在真机对真实库跑**。
- 与 Codex 自述一致："全部写好但默认关闭"成立；需补一句：**写好的是接口与测试基底，真实存储/真实传输/app 接缝尚未连接。**

---

## 5. 本轮只读核对的关键位置

- Facade/模式/护栏：`RokuricsShared/SyncCore/CanonicalKernelFacade.swift:11/23/314/356/368-404`；`CanonicalProductionExecution.swift:193-197`。
- 迁移 Facade/端口工厂/锁：`Rokurics/CanonicalIPhoneMigrationFacade.swift:16/54/101-124/130-138/187-213`（Mac 端 `CanonicalMacMigrationFacade.swift` 同构）。
- 适配器真实性与边界：`IPhoneCanonicalProductionFilePort.swift:13/179/211/242/305/436`（真写+containment+回滚，仅测试根）；`IPhoneCanonicalProductionUploadPort.swift:67-89`（内存 resumable）；`IPhoneCanonicalProductionTransportPort.swift:24/36`（发送抑制）。
- 无 app 接缝：`StudyLibrarySyncCoordinator / SecureLocalHTTPSServer / SecureReceiverService / RokuricsApp` 内无 Facade 调用（grep 确认）。

## 6. 不确定项 / 说明

- 未运行构建/测试；结论基于静态阅读 + 端口工厂/护栏/锁的交叉印证。
- 评价基调：本轮接口与安全护栏设计到位、可作为 shadow migration 的起点；"尚不能真机开跑"特指**真实存储绑定、真实/影子传输、on-device 解锁、app 接缝**四项接线未做，非设计错误。
- `git status` 中 `.swift` 改动均为你/Codex 在途工作；本轮我仅 Read/grep，未改动任何源码；唯一新增为本报告。
