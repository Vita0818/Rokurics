# v9.21 · 首连不卡(E) + 上传可用(F)—— 把同步处理搬离饱和主线程

> 接 v9.20 任务 A(@Published 渲染风暴已修)。直接整段贴给 Codex。完成后【不要 git commit、不要回退现有改动】。

**全局硬约束(任何任务都不得违反):**
- 【冻结·逐字不改 isolation/async/时序/逻辑】`MacSecurityUtilities.swift`、`RequestVerifier.swift`、`PairedDeviceStore.swift`、`SelfSignedCertificateBuilder`、TLS 身份/证书、HMAC/nonce、配对(`beginPairing`)。
- 【不动视觉/动画】`RokuricsHomeView` 的发光球/`TimelineView`/`Material` 保留原样,不加 `.drawingGroup()`。
- 不新增 scaffolding/类型/protocol/route;只做运行时修复。双端共享逻辑放 `RokuricsShared`。
- 不破坏同步语义/数据正确性/安全链路。

**背景(为什么 E、F 是同一件事):** 上传失败的真因已查实——iPhone 上传第一步 `/sync/apply-metadata` 报 "The network connection was lost.";Mac 路由 `handleLocalNetworkSyncApplyMetadataRequest`(:4996)只记到 `uploadActionStarted`、无 `uploadActionCompleted/Failed` → **Mac 的 `@MainActor` HTTPS 服务端被主线程繁忙拖住、来不及响应 → iPhone 超时断连 → 上传失败。** 同理,iPhone 首连要在主线程应用对端整份库 → 卡几秒。**根因都是"重处理压在 @MainActor 上"。** A 已减轻 @Published 风暴;E、F 再把这两处大处理搬下主线程。

---

## 任务 E · iPhone 首连全量同步搬后台(消除首次进库卡几秒)

**诊断:** 首次连接要应用对端整份库,`StudyLibraryStore.applySyncManifest`(`@MainActor`,Rokurics `StudyLibraryStore.swift:132`/`:1253`)在主线程同步处理全量(解析+比对+构建) → 卡几秒。本地清单构建已 background(`makeSyncManifestInBackground`),但"应用对端清单"这步还在主线程。

**做(iPhone 为主;Mac 的 `applySyncManifest` 若同样在主线程也一并改):**
1. 把"应用对端清单"的重处理(解析 incoming manifest、与本地比对、计算变更集、哈希/路径解析)放到**后台 actor / `Task.detached`**;`applySyncManifest` 改为 `async`,调用方 `await`。
2. 只把**最终的最小变更**在主线程上做 `@Published` 应用,且**复用 A 的"变了才写"门 + 合并**(无变化不写不发布)。
3. UI 先显示已有/缓存数据;后台同步完再增量更新。绝不在主线程对整份库做同步全量处理。

**验收(真机):** iPhone 首次连接后进学习库**不卡**(后台同步,UI 即时);大库也不卡。

---

## 任务 F · Mac HTTPS 服务端及时响应(修上传 "network connection lost")

**诊断:** `SecureLocalHTTPSServer` 是 `@MainActor`(:52);`/sync/apply-metadata` 路由 `handleLocalNetworkSyncApplyMetadataRequest`(:4996)→ `localNetworkSyncApplyMetadataResponseForVerifiedDeviceInBackground` + `existingInboxAudioDiverged` 冲突检测(count 上千万)。主线程繁忙 / 处理过重时,`sendJSON` 迟迟发不出 → iPhone 超时断连 → 上传失败、进重试 backoff。

**做(只动响应/处理路径,不碰 TLS/HMAC/RequestVerifier/配对时序):**
1. `requestVerifier.verify(...)` 保持同步、原样(安全)。验签通过后,**把响应构建与冲突检测真正放后台、且有界**,尽快 `sendJSON` 把响应发出去——不要在 `@MainActor` 上长时间占用。
2. `existingInboxAudioDiverged` 冲突检测**不得对每个录音做无界/全量重算**(避免逐文件大哈希);用 size+mtime 缓存或增量,控制单次耗时。必要时"先返回响应,冲突异步处理"。
3. 确认上传链路:apply-metadata 成功 → 后续音频块上传也能在主线程繁忙时被服务端及时受理(同样不被 @MainActor 饿死)。

**验收(真机 + trace):**
- Mac 端上传时出现 `uploadActionStarted → uploadActionCompleted`(不再只 Started)。
- iPhone 端不再 `secureRequestFailed: "The network connection was lost."`;`uploadCoordinatorClientCallStarted → success`。
- 文件**真正传到 Mac**(Mac inventory 出现新文件);大小文件都成。

---

## 验证工具(随 E/F 一起加,若 A 轮未加)
- 双端 `StudyLibraryStore` 加"发布计数":每次真正触发 `objectWillChange`/@Published 发布 +1,每秒打点(走异步 writer,不主线程同步写)。连接空闲应 ≈ 0;首连/上传期间只在真正变化时少量发布。

## 不准
- `git commit` / 回退现有改动。
- 改冻结清单(安全/配对/TLS/HMAC/证书)。
- 动首页视觉/动画 / 加 `.drawingGroup()`。
- 新增 scaffolding/类型/protocol/route。
- 让 `UploadFlightRecorder` 退回"读整文件+重写"(保持 append-only+后台+限大小)。

## 验收门(全绿)
1. iPhone 首连进库不卡;Mac 进库保持不卡;发布计数空闲 ≈ 0。
2. 上传成功:Mac `uploadActionStarted→Completed`、iPhone 无 "connection lost"、文件真正到 Mac。
3. 编译零 error;TLS/HMAC/配对/安全逐字未改;**未 git commit**。

## 交付
一次一项(先 E → 真机验首连不卡 → 再 F → 真机验上传成)。每项交:改了哪些文件、编译结果、真机现象 + trace 片段(E 看进库耗时/发布计数;F 看 uploadActionStarted→Completed 与 iPhone 上传成功)。不接受"应该可以"。
