# SYNC_STATE_AUDIT

最近审计日期：2026-06-01

## 1. 当前真实状态总览

本轮修复后确认：源码继续使用统一的录音音频上传决策模型，核心入口是两端 `StudyLibrarySyncModels.swift` 中的 `RecordingAudioUploadDecisionEvaluator`。它能区分本地音频、对端音频、transfer job、upload ledger 和触发来源，并能把 view refresh 抑制为不创建上传任务。

Mac 侧“立即同步”仍不是直接拉起 iPhone 同步，而是写入 pending sync request，等待 iPhone 前台 heartbeat/probe 取到 `/connection/heartbeat` 响应中的 `syncStartSignal` 后再排队 tick。本轮已补 pending 去重、超时、iPhone ack、tick started/completed/failed 诊断，但 iPhone 不活跃、心跳没有运行、presence 不在线、用户断开连接、backoff/并发 gate 命中时，Mac 仍不能单方面完成同步。

上传链路保持 metadata/audio 主路径不变。状态收敛规则已调整：peer unknown 在普通 sync 中 deferred，显式用户上传才 manual force；peer hash/size 不同现在进入 conflict/fatal，不覆盖 Mac 既有音频；retryable failure 到期后由 retry drainer 重新进入 `RecordingUploadCoordinator.uploadAndWait` 主路径。

## 2. 审计范围与证据

只读检查过的关键源码：

- iPhone app 与连接：`Rokurics/RokuricsApp.swift`、`Rokurics/MacConnectionView.swift`。
- iPhone 录音 UI：`Rokurics/RecordingLibraryView.swift`、`Rokurics/RecordingStudyDetailPage.swift`、`Rokurics/StudyReadingPages.swift`。
- iPhone 学习库与录音 metadata：`Rokurics/StudyLibraryStore.swift`、`Rokurics/RecordingMetadata.swift`、`Rokurics/RecordingUploadStatus.swift`。
- iPhone 上传：`Rokurics/RecordingUploadCoordinator.swift`、`Rokurics/RecordingUploadClient.swift`、`Rokurics/SecureMacUploadClient.swift`。
- iPhone 同步：`Rokurics/StudyLibrarySyncCoordinator.swift`、`Rokurics/StudyLibrarySyncModels.swift`、`Rokurics/ConnectionSyncStateStores.swift`。
- Mac 连接和 UI：`RokuricsMac/MacIPhoneConnectionView.swift`、`RokuricsMac/AudioInboxStore.swift`、`RokuricsMac/MacRecordingInboxItem.swift`、`RokuricsMac/MacStudyLibraryView.swift`。
- Mac 接收和 inventory：`RokuricsMac/MacRecordingFileStore.swift`、`RokuricsMac/RecordingReceiveResult.swift`、`RokuricsMac/SecureReceiverService.swift`、`RokuricsMac/SecureLocalHTTPSServer.swift`、`RokuricsMac/RequestVerifier.swift`。
- Mac 同步模型：`RokuricsMac/StudyLibrarySyncModels.swift`、`RokuricsMac/ConnectionSyncStateStores.swift`。
- 测试：`RokuricsTests/RokuricsTests.swift`、`RokuricsMacTests/RokuricsMacTests.swift`、`RokuricsMacTests/StudyLibrarySyncTests.swift`、`RokuricsMacTests/StudyLibraryStoreTests.swift`。

## 3. 层次边界

连接层只负责配对、presence、heartbeat、pending sync hint 和 signed HTTPS 请求。它不应决定某条录音是否需要上传。

同步层负责 inventory、diff、metadata/artifact apply/download，以及把“对端缺少音频”的事实转成 upload candidate。它必须使用对端 inventory 的音频 hash/size 作为最终 no-op 依据。

上传层负责实际 metadata/audio 上传、resumable session、ledger、progress 和失败分类。它不能把 metadata 上传成功等同于 Mac 已有 audio。

UI 层只能展示状态和触发显式用户动作。列表、详情、文件夹、学习库 refresh 不能创建上传任务。

## 4. 当前同步状态模型表

| 状态维度 | 当前模型/字段 | 主要来源 | 当前含义 | 风险 |
| --- | --- | --- | --- | --- |
| 本地音频 | `RecordingLocalAudioState` | iPhone inventory builder、upload coordinator | unknown/missing/unreadable/available/deleted | hash 已加 cache/off-main 计算，但大库 inventory 仍需观察 |
| 对端音频 | `RecordingPeerAudioState` | Mac `/sync/inventory` | unknown/missing/metadataOnly/available/different/deleted | unknown 普通 sync deferred；missing/metadataOnly 会补传；different 视为冲突 |
| 传输任务 | `RecordingTransferJobState` | `LocalNetworkSyncTransferJobStore` | queued/inFlight/finalizing/completed/failed/retryPending | retryPending 抑制普通新任务，retry drainer 到期后驱动上传 |
| 上传账本 | `RecordingUploadLedgerState` | `RecordingUploadJobStore` | none/queued/inFlight/finalizing/completed/failed/retryPending/fatalFailed | completed 不能单独作为 no-op，必须和 peer hash/size 匹配 |
| metadata 状态 | `RecordingUploadStatus`、`RecordingMetadataSyncState` | metadata JSON、sync manifest | localOnly/uploading/uploaded/failed 或 metadata-only/synced | metadata uploaded 不代表 audio uploaded |
| 展示状态 | `RecordingUploadDisplayState` | evaluator 或 UI presentation | hidden/waiting/preparing/uploading/finalizing/uploaded/failed/retryPending/manualRetryAvailable/conflict/fatalFailed | 展示状态不得反向触发上传 |
| 触发来源 | `RecordingAudioSyncTriggerSource` | sync trigger 字符串、手动按钮、retry drainer | manual/periodic/appActivation/viewRefresh/retryDrainer | manual/periodic/appActivation 可创建任务，view refresh 不可，retryDrainer 只处理到期重试 |

## 5. 关键状态定义

- `peer_metadata_only`：对端有录音 metadata，但没有可用 audio hash/size。当前决策允许上传音频。
- `peer_missing_audio`：对端 inventory 表示录音音频对象缺失。当前决策允许上传音频。
- `peer_audio_unknown_deferred`：普通 sync 不能确认对端音频状态时抑制上传，避免把未知误判为缺失。
- `manual_force_peer_unknown`：用户显式点击上传时，即使对端音频未知也可进入上传，但诊断必须标记为手动强制。
- `retry_drainer_peer_unknown`：retry drainer 恢复到期失败任务时可继续上传，避免 retry pending 永久等待。
- `peer_already_has_same_audio`：本地和对端音频 hash/size 均存在且一致。当前决策 no-op。
- `peer_audio_conflict`：本地和对端均有 audio 但 hash/size 不同。当前决策为 fail/conflict，不覆盖 Mac 既有音频。
- `completed_ledger_peer_matches`：本地 ledger 完成，同时对端 hash/size 一致。当前决策 suppress 并显示 uploaded。
- `ledger_retry_pending` / `transfer_retry_pending`：存在可重试失败但未到或未执行 retry。普通 trigger suppress；到期后由 retry drainer 处理。
- `view_refresh_only`：列表、详情、文件夹或学习库刷新。当前决策 suppress，不创建上传任务。

## 6. 触发图

| 触发源 | 当前代码路径 | 当前能否创建上传任务 | 正确预期 | 当前风险 |
| --- | --- | --- | --- | --- |
| iPhone 录音卡片上传按钮 | `RecordingLibraryView.uploadRecording` -> `RecordingUploadCoordinator.upload` | 能 | 用户显式点击；peer unknown 时作为 manual force 记录 | 仍需用户理解这是强制上传，不是同步自动收敛 |
| iPhone 详情页上传按钮 | `RecordingStudyDetailPage` -> `RecordingUploadCoordinator.upload` | 能 | 同上 | 同上 |
| iPhone 连接页立即同步 | `StudyLibrarySyncCoordinator.performManualSync` -> `/sync/start` -> `performTick("manual")` | 能 | 只按 inventory diff 补缺失音频 | 对端 inventory 不准确时会重传旧音频 |
| Mac 连接页立即同步 | `MacIPhoneConnectionView` -> `SecureReceiverService.prepareManualStudyLibrarySync` | 间接能 | Mac 写 pending signal，iPhone heartbeat 收到后再 tick | 已有 pending 去重和超时；iPhone 不在线或 heartbeat 未运行时仍等待/超时 |
| heartbeat/probe sync hint | iPhone `LocalNetworkHeartbeatMonitor` 收到 `syncStartSignal`/`syncRequested` | 能 | 使用同一个 `syncRunID` 排队 `manual-sync-requested` tick | 已记录 heartbeat consumed、ack、tick started/completed/failed，仍需真机端到端验证 |
| app active/foreground | `RokuricsApp` -> `LocalNetworkSyncAppService.activate` -> `foregroundTick` | 能 | 前台恢复时同步 metadata/artifact，并谨慎补音频 | debug 启动/前台切换可能触发旧录音重传 |
| periodic timer | `LocalNetworkSyncScheduler.startPeriodicTicks` -> `performTick("timer")` | 能 | 周期收敛缺失状态 | peer 缺失/过期时重复尝试 |
| upload ledger changed | `recordingUploadJobLedgerDidChange` -> `requestUploadLedgerTick` / retry drainer | 能 | 用于状态收敛和到期重试调度 | 未到 backoff 的任务必须继续等待 |
| folder/list/detail onAppear | `RecordingLibraryView`、`RecordingStudyDetailPage` local reload | 不能 | 只刷新本地 UI | 已有代码显式记录 view refresh suppress |
| StudyLibraryStore refresh | `studyLibraryStore.refresh()` | 不能 | 只重建本地学习库视图 | 禁止变成上传触发 |
| Mac AudioInbox refresh | `AudioInboxStore.refreshRecordingInbox` | 不能 | 只读取 Mac inbox 并更新 UI | 不能驱动 iPhone 上传 |
| Mac receive record update | `MacRecordingFileStore` 写 receive/audio 并发通知 | 不能 | 更新 Mac inventory 真相 | 若 inventory 未及时反映 audioAvailable，会导致 iPhone 继续补传 |
| transfer progress update | `LocalNetworkTransferProgress` 写入 study item | 不能 | 只显示进度 | 禁止由显示层重入上传 |
| UI display state change | `RecordingUploadDisplayState` / `UploadableRecordingRow` | 不能 | 仅展示 hidden/waiting/uploading/failed | display state 不得作为业务状态源 |

## 7. 上传决策真值表

| 本地音频 | 对端音频 | transfer job | ledger | 触发源 | 当前决策 | 应有含义 |
| --- | --- | --- | --- | --- | --- | --- |
| missing/unknown | 任意 | 任意 | 任意 | manual/periodic | fail `local_audio_missing` | 不上传，提示本地音频缺失 |
| available | available 且 hash/size 相同 | none | none | manual/periodic | no-op `peer_already_has_same_audio` | 不上传，Mac 已有同一音频 |
| available | available 且 hash/size 相同 | none | completed | manual/periodic | suppress `completed_ledger_peer_matches` | 不上传，账本和 Mac 均确认完成 |
| available | metadataOnly | none | none | manual/periodic | upload `peer_metadata_only` | 上传音频补齐 metadata-only |
| available | missing | none | none | manual/periodic | upload `peer_missing_audio` | 上传音频 |
| available | unknown | none | none | periodic/appActivation/manual sync | suppress `peer_audio_unknown_deferred` | 对端未知不等于缺失，等待下次明确 inventory |
| available | unknown | none | none | manual upload button | upload `manual_force_peer_unknown` | 用户显式强制上传，诊断不能伪装成同步收敛 |
| available | unknown | none | retryPending 到期 | retryDrainer | upload `retry_drainer_peer_unknown` | 到期失败任务走主上传路径恢复 |
| available | different | none | none | manual/periodic | fail `peer_audio_conflict` | 不覆盖 Mac 既有不同音频，展示冲突 |
| available | 任意非匹配 | queued/inFlight/finalizing | none | manual/periodic | suppress queued/inFlight | 不创建重复任务 |
| available | 任意非匹配 | none | retryPending 未到期 | manual/periodic | suppress retryPending | 等待 backoff，不创建重复任务 |
| available | metadataOnly/missing | none | none | folder/list/study refresh | suppress view refresh | 只刷新 UI，不上传 |

## 8. iPhone 端当前链路

`RokuricsApp` 在 `.task` 和 scene active 时调用 `LocalNetworkSyncAppService.activate()`。服务启动 heartbeat 和 scheduler，并在 peer online 时执行 foreground tick。scheduler 还会定时执行 `"timer"` tick。

`LocalNetworkSyncInventoryBuilder` 构造本地 inventory 时读取 `StudyLibraryStore.makeSyncManifest`、`AudioFileStore.loadAllMetadata(includeDeleted:)`、每条录音文件存在性、文件大小和 SHA256。inventory 中的 recording entry 会带 `audioAvailable`、`audioChecksum`、`audioSize`、`uploadLedgerState`、`uploadStatus`、`sourceDeviceID`、`audioLogicalPathToken`。音频 checksum 现在经过 `LocalNetworkChecksumCache`，文件 size/mtime 未变化时复用缓存，miss/invalidated 时在主 actor 外计算 hash。

`LocalNetworkSyncEngine.performTick` 拉取 Mac `/sync/inventory` 后生成 diff，先处理 metadata/artifact，再用 `uploadRecordingAudioActionsToRun` 通过统一 evaluator 过滤音频上传候选。最终上传仍调用 `RecordingUploadCoordinator.uploadAndWait`。`LocalNetworkSyncAppService` 还会在 scheduler gate 允许时 drain 到期 retry job，并用 `.retryDrainer` trigger 复用同一上传路径。

## 9. Mac 端当前链路

Mac 手动同步入口是 `MacIPhoneConnectionView` 的 `onSyncNow`，调用 `SecureReceiverService.prepareManualStudyLibrarySync(for:)`。当 git-backed sync 禁用时，它记录 `syncStartSignalSent` / `manualSyncPendingCreated` 并调用 `DeviceConnectionStatusStore.recordPendingSyncRequest`。这个动作不会直接连 iPhone；重复点击会复用未过期 pending request，超时后显示等待 iPhone 前台响应超时。

`ConnectionHeartbeatRouteHandler` 在 iPhone heartbeat 请求到达时消费 pending signal，响应 `syncRequested=true` 和 `syncStartSignal`。iPhone 收到后 ack，再排队 `manual-sync-requested` tick。Mac 侧记录 `manualSyncAckReceived`，inventory/apply-metadata 路径记录 `manualSyncTickStarted`、`manualSyncTickCompleted` 或 `manualSyncTickFailed`。

Mac `/sync/inventory` 由 `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 生成。它读取 `StudyLibraryStore.makeSyncManifest`、`MacRecordingFileStore.loadInboxItems(includeDeleted:)`，并用 checksum cache 读取已有 audio 的 checksum/size，写入 `audioAvailable`、`audioChecksum`、`audioSize`、`sourceDeviceID`、`audioLogicalPathToken`。Mac 收到同 recording 但 hash/size 不同的 audio upload 时会拒绝覆盖并记录 conflict 诊断。

## 10. Mac 手动同步为何可能像 no-op

Mac 点击同步后只写 pending sync request；iPhone 必须同时满足这些条件才会执行：

- iPhone app active，`LocalNetworkSyncAppService` 已启动。
- paired snapshot 有效，用户连接意图不是 disconnected。
- heartbeat/probe 能成功到达 Mac `/connection/heartbeat`。
- Mac presence 在 iPhone 侧被标记 online。
- pending `syncStartSignal` 被 iPhone 收到并 ack。
- scheduler 没有被 already-in-flight、presence gate 或 backoff 拦住。

任一条件不满足，Mac 端 UI 会显示等待 iPhone 前台响应，超过 pending timeout 后进入超时状态；这仍不是 Mac 主动同步失败，而是 iPhone 未消费 pending signal。

## 11. 重复上传旧数据的主要原因

当前 evaluator 的最终 no-op 条件依赖 peer inventory 明确报告相同 hash/size。如果 Mac inventory 只报告 metadata 或 audio missing，手动/周期/前台 tick 会把录音看作需要补音频；如果是 peer unknown，普通 sync 现在 deferred，不再直接上传。

`RecordingUploadCoordinator.upload` 的默认 `peerAudioState` 是 `.unknown`。用户从列表/详情直接点上传时，如果没有先取得 Mac 端 audio truth，当前逻辑会允许上传并记录 `manual_force_peer_unknown`。这仍是显式用户动作，不应被解释成自动 sync no-op 判断。

## 12. 失败/未上传不重试的主要原因

源码存在 `RecordingUploadQueue`、`retryPolicy`、`nextRetryAfter`、`recoverStaleInProgressJobs`，也有失败后保存 `retryableFailed` 的逻辑。统一 evaluator 仍会把普通 trigger 下的 `ledger_retry_pending` 和 `transfer_retry_pending` 抑制为 waiting，避免无限新建任务。

本轮已增加 `RecordingUploadCoordinator.drainEligibleRetryJobs`，由 `LocalNetworkSyncAppService` 在 scheduler gate 允许时启动；未到 `nextRetryAfter` 的任务记录 backoff skip，到期任务以 `.retryDrainer` trigger 重新调用 `uploadAndWait`。fatal/conflict 与 retryable failure 分别映射到不同 display state。

## 13. UI 展示状态边界

`RecordingUploadStatus` 只有 `localOnly/uploading/uploaded/failed`，是 metadata 级状态。`RecordingUploadDisplayState` 是展示状态，用于 hidden/waiting/preparing/uploading/finalizing/uploaded/failed/retryPending/manualRetryAvailable/conflict/fatalFailed。

`UploadableRecordingRow` 只根据 metadata 和 status 生成 action area presentation。它不能代表 Mac 已有 audio，也不能触发 upload。未来不要把“显示等待上传”或“显示上传失败”做成 view lifecycle 的副作用。

## 14. Metadata 与 Audio 的边界

metadata sync/upload 完成只表示 Mac 可以看到录音条目。audio 是否完成必须看 Mac inventory 的 `audioAvailable=true`，并且 `audioChecksum` 和 `audioSize` 与 iPhone 本地音频一致。

`RecordingUploadStatus.uploaded` 不能单独作为停止上传的证据。正确 no-op 条件是：本地 audio available，peer audio available，hash/size 均存在且一致；ledger completed 只能作为辅助证据。

## 15. Diff 与 no-op 规则

`LocalNetworkSyncDiffPlanner` 会把 core diff 中的 recording audio object 转成 `uploadRecordingAudioActions` 或 `noOps`，并通过 evaluator 抑制 peer available 的上传。

audio download 当前禁用。对端有 audio 而本地缺 audio 时，规划应保持 no-op 或 metadata/artifact 处理，不应自动下载 audio。

最终 no-op 规则必须落在 inventory truth 上：peer audio available + same hash + same size。completed ledger、metadata uploaded、receive completed、UI uploaded 都不能单独替代这个判断。

## 16. 诊断信号

当前代码已经记录以下有价值的阶段：

- `localAudioStateResolved`
- `peerAudioStateResolved`
- `uploadStateEvaluated`
- `uploadDecisionComputed`
- `uploadDecisionNoOpPeerAlreadyHasSameAudio`
- `uploadDecisionSuppressedCompletedAndPeerMatches`
- `uploadDecisionUploadBecausePeerMetadataOnly`
- `uploadDecisionUploadBecausePeerMissingAudio`
- `peerAudioUnknownDeferred`
- `manualForcePeerUnknownUpload`
- `retryJobEligible`
- `retryJobStarted`
- `retryJobCompleted`
- `retryJobSkippedBackoff`
- `retryDrainerStarted`
- `retryDrainerScheduled`
- `audioConflictDetected`
- `uploadSuppressedConflict`
- `retryPendingDisplayState`
- `uploadDecisionSuppressedQueued`
- `uploadDecisionSuppressedInFlight`
- `uploadDecisionSuppressedViewRefreshOnly`
- `syncPeerAudioAvailable`
- `syncPeerAudioHashMatched`
- `syncPeerAudioMissing`
- `macInventoryReportsAudioAvailable`
- `macInventoryChecksumRecomputed`
- `checksumCacheHit`
- `checksumCacheMiss`
- `checksumCacheInvalidated`
- `checksumComputedOffMainActor`
- `inventoryBuildStarted`
- `inventoryBuildCompleted`
- `inventoryBuildDurationMs`
- `pendingSyncRequestCreated`
- `manualSyncPendingCreated`
- `syncStartSignalReceived`
- `syncStartAckSent`
- `manualSyncAckReceived`
- `manualSyncTickStarted`
- `manualSyncTickCompleted`
- `manualSyncTickFailed`
- `syncRequestedTickQueued`

下一步排查真实设备时应按 syncRunID 串联 Mac 点击、heartbeat、iPhone tick、inventory、decision、upload coordinator。

## 17. 可能导致卡顿的源码位置

以下路径仍可能在主线程或 UI 相关 actor 上执行大量 IO/JSON/扫描；audio hash 已加缓存和 off-main 计算，但还不能等同于全量 inventory 增量化：

- `LocalNetworkSyncInventoryBuilder.build` 读取所有 metadata，并为 cache miss/invalidated 的本地音频计算 SHA256。
- `LocalNetworkSyncEngine.performTick` 标记为主 actor 相关路径，inventory、diff、diagnostics、progress 更新集中执行。
- `uploadMissingRecordingAudioIfNeeded` 先 `recordingManager.reloadRecordings()`，再读取本地 inventory checksum 或计算 SHA256，并每 200ms 刷新 transfer progress。
- `StudyLibraryStore.refresh()` 和 `makeSyncManifest()` 会读取/修复学习库 metadata。
- `ConnectionDiagnosticsStore.record` 写诊断 JSONL，频繁阶段记录可能放大 IO。
- Mac `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` 读取整个 inbox，并为 checksum cache miss/invalidated 的 audio 计算 hash。
- `AudioInboxStore.refreshRecordingInbox` 在通知后读取 inbox、trash，并为每条记录写多条诊断。
- `MacRecordingFileStore.loadInboxItems` 遍历日期目录、录音目录、receive.json 和 audio 文件属性。

后续优化重点应放在增量 inventory、目录扫描批处理、诊断写入节流，以及真机长录音场景下的 UI latency 观测。

## 18. 本轮已落实与剩余计划

已落实：

1. “是否需要上传音频”继续收敛在统一 evaluator，并新增 peer unknown deferred、manual force、retry drainer 和 conflict/fatal 分支。
2. Mac 手动同步增加 pending 去重、timeout、ack、tick started/completed/failed 诊断。
3. retry queue 到期后由明确 drainer 重新走上传主路径，未到 backoff 不重复创建任务。
4. inventory 使用 checksum cache，文件 mtime/size 不变时复用 hash。
5. view refresh 继续只做本地 refresh，不进入上传 state machine 的 job creation 分支。

剩余计划：

1. 在真实 iPhone + Mac 上验证 Mac 点击立即同步 -> heartbeat -> ack -> iPhone tick -> Mac completed/failed 的完整 UI 和诊断链路。
2. 继续把学习库 manifest、目录扫描、JSON 诊断写入做增量化或节流。
3. 为 peer same audio、peer metadata-only、retry drainer 和 Mac pending timeout 增加更接近真实设备的端到端用例。

## 19. 测试计划

自动测试应覆盖：

- view refresh 不创建 upload job。
- app activation 在 peer same hash/size 时 no-op。
- manual sync 在 peer same hash/size 时 no-op。
- peer metadata-only 只上传一次，下一次 inventory same hash/size 后 no-op。
- ledger completed 但 peer missing 时仍允许补传。
- ledger completed 且 peer same hash/size 时 suppress。
- retryable failure 到期后 drain retry queue 并恢复上传。
- retryPending 未到期时不创建重复任务。
- Mac pending sync request 只被 heartbeat 消费一次。
- Mac pending sync request 重复点击去重，并在超时后给出明确状态。
- Mac inventory 必须报告 audioAvailable/hash/size/sourceDeviceID/logicalPathToken。
- checksum cache 在文件 size/mtime 不变时命中，变化时 invalidated。
- peer unknown 普通 sync deferred，手动上传 force，retry drainer 可恢复。
- peer audio hash/size 不同进入 conflict，不覆盖 Mac 旧音频。

手动测试应覆盖：

- Mac 点击立即同步时 iPhone 前台、后台、未启动三种状态。
- debug 启动 iPhone 后不应重传 Mac 已有同 hash/size 的旧录音。
- 网络中断后失败上传在 backoff 到期后可重试。
- 大录音 inventory/hash 不应明显卡住列表或连接页。

## 20. 不得突破的边界

- 不让 view lifecycle、folder/list/study refresh、AudioInbox refresh 创建上传任务。
- 不把 metadata uploaded 当成 audio uploaded。
- 不把 completed ledger 单独当成 no-op。
- 不把 peer unknown 当成普通 sync 下的缺失音频。
- 不覆盖 Mac 已有但 hash/size 不同的音频。
- 不把 UI display state 当成业务状态源。
- 不在主线程做全量大文件 hash、全量 inventory、全量 JSON 反复读写；hash miss 也应记录 off-main 计算。
- 不恢复 audio auto-download。
- 不绕过 TLS pinning、HMAC、nonce、Keychain、安全范围书签。
- 不在文档或诊断中写入完整密钥、完整 fingerprint、完整 API 响应、完整转写文本或本机隐私路径。
