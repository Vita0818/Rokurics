# Rokurics 任务卡 · 先做卡顿 + UI 收敛(对称)

- 时间：2026-06-18 (CST) · 只读审计基础上给 Codex 的执行卡。验收均为编译/真机级。
- 总约束(放每条 prompt 最前)：**只做运行时/接线,不加任何新类型(禁止 FourDomain/evidence/gate/scorecard/fake);不改 oldKernel 默认;不绕 TLS/HMAC/RequestVerifier;Path B 不重写传输协议本身。**

---

## 任务卡 1 · 灭卡顿:把 Mac 服务端残留的主线程重活搬走(最高优先)

**现状(已只读确认):**
- `RokuricsMac/SecureLocalHTTPSServer.swift` 整体 `@MainActor`(:52)。
- ✅ 已 detached:canonical inventory 构建走 `Task.detached`(:4428 / :4514 / :4561)——这块别动。
- ❌ 仍在主线程同步:
  - legacy `studyLibraryStore.makeSyncManifest(deviceID:)` **同步**调用于 `:3188 / :3236 / :3420`(加载全部录音元数据 + 逐条哈希);
  - 同步 `write(to:options:.atomic)` 于 `:3826`(接收 artifact 落盘)、`:7855 / :7865`(ledger record 写)。

**做什么:**
1. 把 `:3188 / :3236 / :3420` 的 `makeSyncManifest` 改为后台构建(仿同文件 `:6480` 已有的 `await Task.detached(priority:.utility){…}`,或仿 iPhone 的 `makeSyncManifestInBackground`)。主线程不得做全量元数据加载/哈希。
2. 把 `:3826 / :7855 / :7865` 的同步 atomic 文件写移到**后台串行 actor**(写盘不在 `@MainActor` 上同步阻塞);保持原子性与回滚语义不变。
3. 全面排查 `SecureLocalHTTPSServer` 内**所有**"加载全部元数据 / 哈希 / 目录扫描 / 整文件写"——一律不得在 `@MainActor` 同步执行;耗时处加 `manifestBuildDurationMs / mainActorLongTaskDurationMs` 诊断。

**验收(真机):** 两端 fullSync,连续狂操作 → `connection-diagnostics` 里 `mainActorLongTaskDurationMs` 有界、**无 9000ms**;`manifestBuildDurationMs` 大头不在主线程阶段。
**不准:** 不加新类型;不改 detached 已做好的 inventory 路径;不改安全/默认。

---

## 任务卡 2 · UI 状态收敛:让双端对称交换 + UI 单一来源

**现状(已只读确认):**
- iPhone 发/收 delta 对称(`statusDeltaSent=3 / Received=3`);Mac 服务端 `produceCanonicalStatusFactsFromInventory`(:2598)会从 inventory 产 facts。
- ❌ 但 Mac 服务端(`SecureLocalHTTPSServer` / `SecureReceiverService`)**未见对称的 `CanonicalStatusExchangeEnvelope` 消费 + 回发 delta/ack**——状态交换偏 iPhone 单边驱动,Mac 不对称参与 → 两端难以秒级一致。
- ✅ Mac UI 已读 `canonicalDisplaySyncState`(MacStudyLibraryView/AudioInbox/ReceiverStatusCard);iPhone 显示已走 canonical(RecordingLibraryView 残留 4 处 `uploadStatus` 是上传逻辑,非显示)。

**做什么:**
1. **Mac 服务端对称化**:在心跳 / `/sync/inventory` 响应里,Mac 也要**消费**对端 `CanonicalStatusExchangeEnvelope`(delta/ack/request)并**回发**自己的 status facts/acks——不只是在 inventory 里产 facts。让两端都既发又收。
2. **UI 单一来源复核**:双端 UI 的同步状态显示只来自 `EffectiveSyncStatus / canonicalDisplaySyncState`;iPhone 复核 RecordingLibraryView 的显示徽标确实走 canonical(残留 uploadStatus 仅用于上传逻辑不用于显示)。
3. **执行规格 §7.3 硬规则**:`metadataOnly≠completed`、`partialReceive≠completed`、本地文件存在≠peer 有、**无 peer proof 不得显示 completed**。

**验收(真机):** 一端改状态/传文件 → 另一端**几秒内**显示同一状态;两端诊断里 `statusDeltaSent↔Received`、`statusAckSent↔Received` **成对出现(Mac 侧也要有 Received/produced)**;无 peer proof 的项不显示"完成"。
**不准:** 不加新类型/route;不绕 proof;不在 `@MainActor` 重算 effectiveStatus(只读已缓存结果)。

---

## 顺序与节奏
1. **先做任务卡 1(灭卡顿)** —— 独立、低风险、立刻可感;做完你真机确认不卡,再做卡 2。
2. 每张卡:Codex 交"改了哪些文件:行号 + 编译零 error",你真机出 jsonl 证据,我只读核验是否真到位(防夸大/防偷加类型)。
3. 这两张做完 = 你最痛的两点(卡顿 + UI 收敛)落地;之后才谈 R6(Connection/Transfer 真接管)/执行接管等更大改动。
