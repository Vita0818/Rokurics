MODEL_CHECK_RESULT: Gemini 1.5 Pro (Antigravity)
PATH_CHECK_RESULT: 
- `pwd`: `/Users/vita/Vitemis/Vela/Rokurics`
- `git root`: `/Users/vita/Vitemis/Vela/Rokurics`
- 路径匹配预期，处于正确的 Git 根目录。

FINDINGS:
针对“真机实测连接后点击同步，进度反复在 12% 和 46% 之间跳跃，中间变回‘立即同步’，最后卡在 28%”的问题，代码审计发现由于 **iPhone 端局部流控拦截与 Mac 端状态机缺失超时/失败通知** 导致的状态断层。

详细原因如下：
1. **进度数值对应的状态**：
   - 12% = `.syncStartSignalSent`（Mac 侧写 pending request）
   - 28% = `.syncStartAcked`（iPhone 侧发送 `/sync/start` 被 Mac 接收）
   - 46% = `.inventoryExchanging`（iPhone 侧发送 `/sync/inventory`）
2. **跳跃与回退 (12% -> 46% -> 立即同步)**：
   Mac 侧点击“立即同步” (12%) 后，iPhone 的 Heartbeat 获取到 `syncRequested=true`，进入 `performLocalNetworkManualSync`，向 Mac 发送 `/sync/start` (Mac 达到 28%)，接着执行 `engine.performTick` 发送 `/sync/inventory` (Mac 达到 46%)。如果网络发生断联或其他报错导致 Tick 失败，iPhone 端会将自己的 state 设为 `.failed` 并回退到“立即同步”状态。
3. **最终卡死在 28% (.syncStartAcked) 的根本原因**：
   如果在某次触发时，iPhone 向 Mac 发送完了 `/sync/start`（此时 Mac 状态更新为 28%），但紧接着 iPhone 进入 `engine.performTick` 内部时，**命中了前置的流控阻断条件**（例如：`shouldDeferSyncBecauseUploadActive` 为 true，或 `isSyncing` 为 true，或命中 Backoff、状态掉线等）。
   此时，iPhone 端会直接 return `nil`，并将自身状态设为 `.failed`（变为“立即同步”）。
   **漏洞所在**：iPhone 在客户端本地决定 abort 本次执行时，**完全没有向 Mac 发送任何类似 `/sync/abort` 或是 failed 的网络信号**。Mac 侧在成功回复了 `/sync/start` ack 之后，处于痴痴等待后续 `/sync/inventory` 请求的状态。由于 Mac 并没有设计 Control Plane 中间状态的兜底超时机制，Mac 侧的 UI 就永远冻结在了 28%（`.syncStartAcked`）。

FILES_WRITTEN: 
- `gemini-report/07_03_26-13_15-sync_28_percent_stuck_audit.md`

PROJECT_AUDIT_SUMMARY:
- 主要模块：`StudyLibrarySyncCoordinator`（iPhone 端调度）, `LocalNetworkSyncEngine`（iPhone 端 tick 执行）, `SecureLocalHTTPSServer`（Mac 端接收处理）, `ConnectionSyncStateStores`（双端 UI 状态映射）。
- 关键链路：Heartbeat sync hint -> `/sync/start` (28%) -> `engine.performTick` 前置条件守卫校验 -> `/sync/inventory` (46%)。 缺陷发生在通过 28% 后但被前置守卫拦截，未闭环通知 Mac。

DOCS_CONTENT_SUMMARY:
- 查阅了 `docs/SYNC_STATE_AUDIT.md` 中关于 Mac 点击“立即同步”的 pending 及 heartbeat 链路文档。
- 确认现有文档中主要侧重了 pending 阶段的去重与超时，但并未涵盖进入 `.syncStartAcked` 握手之后的异常断流处理策略。

VALIDATION_RESULT:
- 实际运行命令：`pwd`, `git rev-parse --show-toplevel`, `git status --short`
- 结果：确认无误。未运行构建/测试。

UNCERTAINTIES:
- 当前 iPhone 在遇到前置守卫拦截时，除了 `shouldDeferSyncBecauseUploadActive`，是否还频繁触发了其他阻断（如 `isSyncing` 重入）？需要在实际报错设备的 diagnostics 日志中排查究竟是哪个判断条件拦截并返回了 `nil`，才导致了上述表现。

NEXT_RECOMMENDED_ACTION:
建议将此漏洞交由 Codex 进行修复。
修复方向建议：
1. **iPhone 侧**：在 `performLocalNetworkManualSync` 中，如果 `engine.performTick` 返回了 `nil` 且当前已经发过 `/sync/start` 信号，应向 Mac 发送一个明确的 `/sync/abort` 或失败通知。
2. **Mac 侧 (推荐)**：考虑到弱网或应用退入后台导致的直接断联，在 `SecureReceiverService` 或状态库里，应当为主控层状态（如 `.syncStartAcked`, `.inventoryExchanging`）增加一个全局的 Watchdog 定时器（例如 10~15 秒），如果长时间未收到下一步流转请求，自动将其回退至 `.idle` 以防 UI 卡死。
