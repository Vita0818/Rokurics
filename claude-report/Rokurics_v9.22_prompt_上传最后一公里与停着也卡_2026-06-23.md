# v9.22 · 上传最后一公里(H)+ 停着也卡(G)—— 运行时修复,不 git commit

> 接 v9.20(A 渲染门)+ v9.21(E 首连后台 / F Mac 服务端及时响应)。**E/F 已生效**:trace 证明上传失败点已从"开头 apply-metadata 连接丢失"推进到"最后一步 finalize",小文件已能完整上传成功。本版只补最后两处缺口。完成后【不要 git commit、不要回退现有改动】。

**全局硬约束(任何任务都不得违反):**
- 【冻结·逐字不改 isolation/async/时序/逻辑】`MacSecurityUtilities.swift`、`RequestVerifier.swift`、`PairedDeviceStore.swift`、`SelfSignedCertificateBuilder`、TLS 身份/证书、HMAC/nonce、配对(`beginPairing`)。
- 【不动视觉/动画】`RokuricsHomeView` 的发光球 / `TimelineView` / `Material`,不加 `.drawingGroup()`。
- 不新增 scaffolding/类型/protocol/route;只做运行时修复。双端共享逻辑放 `RokuricsShared`。
- 不破坏同步语义/数据正确性/安全链路。**不得让 `UploadFlightRecorder` 退回"读整文件+重写"。**

---

## 任务 H · 修大文件上传"最后一公里"(finalize 被并发同步撞掉)

**诊断(trace 实证,upload-trace.jsonl 2026-06-22):**
- 大文件:`metadata ✅ → session ✅ → 全部 chunk ✅`(11:31:28–11:32:03 十几块全 success),**只在 `/upload-recording-audio-session/finalize` 失败**:`secureRequestFailed … "cancelled"`(11:32:04),同一刻 `/sync/apply-metadata` → `"The network connection was lost."`(11:32:05)。
- **撞车证据:** chunk 还在传的 11:31:54 iPhone 并发发 `/sync/inventory`;最后一块刚完成的 11:32:03 又并发发 `/sync/apply-metadata`。即**上传进行中,周期同步(inventory/apply-metadata)无避让地并发开火。**
- `StudyLibrarySyncCoordinator` 里**没有任何"上传进行中暂停同步"的护栏**;iPhone 用 `URLSessionConfiguration.ephemeral`(`SecureMacUploadClient.swift:1568`)各开连接,但都打向**同一个 `@MainActor` 的 `SecureLocalHTTPSServer`(:52)**。大文件传 35s,必然撞上周期同步 → Mac 单线程服务端被同步占住 → 连接被拆 → finalize `cancelled`、同步 `connection lost`。
- 小文件 1–2s 传完,窗口太短不撞,所以**已能成功**——印证根因就是"并发撞车",不是上传链路本身。

**做(双管齐下,优先 H1):**
- **H1【iPhone·上传与同步互斥】** 有"活跃上传"(尤其大文件 resumable session 进行中)时,**暂停周期同步对 Mac 的请求**(`/sync/inventory`、`/sync/apply-metadata`、心跳触发的同步),上传结束(成功/失败终态)后再恢复。用一个轻量的"上传进行中"标志(`uploadCoordinator` 已有 ledger/active job 状态,直接读,不新增类型),在 `StudyLibrarySyncCoordinator` 的同步触发点前 `guard !uploadActive`。**心跳本身可保留(它轻),但心跳里"触发整库同步/inventory/apply-metadata"这步要避让。**
- **H2【Mac·finalize 尽快回包,证明事实后置】** `handleResumableAudioFinalizeRequest`(`SecureLocalHTTPSServer.swift:5241`)当前顺序是 `await resumableAudioFinalizeResponse → await produceMacTransferFinalizeProofFactIfPresent → sendRouteResponse`。**把 `sendRouteResponse` 提到 `produceMacTransferFinalizeProofFactIfPresent` 之前**(finalize 结果一就绪就回包),证明事实(canonical fact)异步后置产生,**绝不让 fact 产生阻塞 finalize 回包**。
- **H3【Mac·inventory 构建别压主线程】** 确认 `/sync/inventory` 的清单构建(`makeSyncManifest` 一线,旧记录在 `:2773/2821/2987` 一带)走后台 / `Task.detached`,与 F 的 apply-metadata 一致;上传期间即便有 inventory 请求进来,也不饿死服务端。

**验收(真机 + trace):**
- 大文件(几十 MB)上传:`metadata→session→chunks→finalize` 全 `success`,**Mac inventory 真出现该新文件**;trace 无 finalize `cancelled`、无并发 `apply-metadata/inventory` 的 `connection lost`。
- 上传期间周期同步暂停、上传完恢复;Mac 端出现 `uploadActionStarted→Completed`。
- 小文件继续成功(不回归)。

---

## 任务 G · 修"停在学习库啥都不做也每 3s 卡 700-900ms"

**诊断:** A 的"变了才发"门 `updatePublished`(`StudyLibraryStore.swift:482`,`guard 旧 != 新 else return false`,机制正确)**只加在了 `StudyLibraryStore` 的字段上,没覆盖 `StudyLibrarySyncCoordinator.connectionStatus`(`@Published`,:48)**。心跳 `performHeartbeat`(每 3s)里:
- `:406 connectionStatus = statusStore.markConnecting(...)`(开头直接赋值)
- `:467 connectionStatus = statusStore.markConnected(...)`(成功后直接赋值)

→ **每 3s 心跳把 connectionStatus "连接中→已连接"翻一遍 = 2 次 `@Published` 发布 = 2 次重渲染整棵昂贵视图树(渐变/毛玻璃/球)→ 每 3s 700-900ms 卡。** 都绕过了 A 的门。

**做(纯状态,绝不碰安全/配对/TLS):**
- **G1.** 已连接且本轮心跳无实际变化时,**不要先置 `markConnecting`**(去掉这个每心跳必发的瞬时翻转);仅在连接态/lastSeen 真正变化时才更新 `connectionStatus`。心跳成功就保持 `.connected`,内部更新 lastSeen 不必触发 `connectionStatus` 重发。
- **G2.** `connectionStatus` 的写入统一走"变了才发"门(语义等价的 `DeviceConnectionStatus` 不发布);`DeviceConnectionStatus` 若未 `Equatable` 则补上,比较要含 lastSeen 之外的语义字段(避免仅 lastSeen 抖动也重发)。
- **G3.** 心跳里的 status-exchange 处理(`makeOutgoingEnvelope` / 消费 incoming)重活放后台,主线程只做最小最终更新,且同样走门。

**验收(真机):** 停在学习库不动时,Xcode 调试窗**不再每 3s 报 700-900ms hang**;发布计数(C 工具)空闲 ≈ 0。

---

## 不准
- `git commit` / 回退现有改动。
- 改冻结清单(安全/配对/TLS/HMAC/证书)。
- 动首页视觉/动画 / 加 `.drawingGroup()`。
- 新增 scaffolding/类型/protocol/route。
- 让 `UploadFlightRecorder` 退回"读整文件+重写"。

## 验收门(全绿)
1. 大文件上传成功、文件真到 Mac、trace 无 finalize `cancelled` / 无 `connection lost`;小文件不回归。
2. 停在学习库不动不再每 3s 卡;发布计数空闲 ≈ 0。
3. 编译零 error;TLS/HMAC/配对/安全逐字未改;**未 git commit**。

## 交付
一次一项(先 H → 真机验大文件上传成 + trace → 再 G → 真机验停着不卡)。每项交:改了哪些文件、编译结果、真机现象 + trace 片段。不接受"应该可以"。
