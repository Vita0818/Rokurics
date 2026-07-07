# v9.20 · 消除卡顿 + 修复上传(运行时修复,不 git commit)

> 直接整段贴给 Codex。

---

**版本:v9.20。这是一个新版本号。完成后【不要 git commit、不要回退任何现有改动】**(仓库 20+ 天未提交、170k diff,保持现状继续改)。

**全局硬约束(任何任务都不得违反):**
- 【冻结清单 · 逐字不改其 isolation / async / 时序 / 逻辑】:`MacSecurityUtilities.swift`、`RequestVerifier.swift`、`PairedDeviceStore.swift`、`SelfSignedCertificateBuilder`、TLS 身份/证书、HMAC/nonce、配对链路(`beginPairing` 等)。这是已验证可用且安全的连接地基,之前一碰就导致配对失效。
- 【不动视觉/动画】:`RokuricsHomeView` 的发光球、`TimelineView(.animation)`、`repeatForever`、`Material/blur` 全部保留原样,**不加 `.drawingGroup()`、不删动画**。卡顿不是它造成的,它只是"账单落点"。
- 不新增 scaffolding / 新类型 / 新 protocol / 新 route;**只做运行时修复**。
- 双端(`Rokurics/` 与 `RokuricsMac/`)对称修改,共享逻辑放 `RokuricsShared` 复用。
- 不破坏同步语义 / 数据正确性 / 安全链路。

---

## 任务 A【最高优先 · 真正的卡顿源】消除同步/状态层的 @Published 重渲染风暴

**诊断(Instruments + trace + 代码三方印证):**
- 真机 Time Profiler:主线程 98% 在 CoreGraphics `argb32_shade_axial`(渐变)+ `argb32_image_mark`(毛玻璃/图像合成)。
- trace 热符号含 `Combine PublishedSubject.send` / `Published.withMutation` / `AttributeGraph…withObservation` / `Observation.ObservationTracking` → 是"@Published 不停发布 → SwiftUI 反复重算 body → 重画所有渐变/毛玻璃/球"。
- 代码:`StudyLibraryStore.effectiveSyncStatusByObjectID` 是 `@Published` 字典(iPhone `StudyLibraryStore.swift:142` / Mac `:145`),`refreshEffectiveSyncStatusSnapshot` 每来一个 status fact 就**无条件**写它(iPhone `:466` / Mac `:486`,**没有"变了才写"判断**)。`@Published` 字典改一个键就整份重发 `objectWillChange` → 全库视图重渲染。3s 心跳 / 状态交换 / 上传进度持续产 fact → 持续重渲染 → 占满主线程。

**做(iPhone 与 Mac 的 store 都改):**
- A1. 所有 `@Published` 写入前加"变了才写"门:`effectiveSyncStatusByObjectID[id]`、`allStudyItems`、`allStudyFolders`、`canonicalReadRuntimeResult`、`canonicalReadRuntimeReturnedSource` 等——新值 `==` 旧值就直接 `return`,不赋值、不发布。(相关类型应已 `Equatable`;没有的补上 `Equatable`。)
- A2. `effectiveSyncStatusByObjectID` 改逐项变更检测:只在某 `objectID` 的 `EffectiveSyncStatus` 真正变化时更新该键;并对一波 fact 用 ~200ms 防抖窗口合并成**一次**发布,不要每 fact 发一次。
- A3. 同步 tick(3s 心跳、状态交换、inventory)若本轮**没有任何实际数据/状态变化**,绝不触发 `store.refresh()` 或任何 `@Published` 写入/发布。
- A4. 计算/加载(`loadAllMetadata`、`effectiveStatus` 计算、投影)在后台完成,主线程只做"已就绪结果"的赋值,且赋值也走 A1 的变更门。
- A5. 只去掉"无变化也发布"的冗余,不改状态语义。

---

## 任务 B【上传永远失败】canonical 在 peerSnapshotUnavailable 时未真正上传

**诊断:**
- fullSync 下 canonical 同步因 `peerSnapshotUnavailable / blockedPeerUnavailable` 阻塞,所有域(含音频上传)`DecisionFallback`,**canonical 上传从未真正发起**(connection-diagnostics:`canonicalSyncRuntimePeerSnapshotUnavailable` + 各域 `…DecisionFallback=blockedPeerUnavailable`)。
- 同时 `canonicalShadowLegacyMismatchDetected: canonicalAudioMissing/Unknown` → UI 把"其实已在 Mac 上的文件"显示成需上传/失败(upload-trace 里这些文件 `macReceiveState=completed`,即文件已在对端)。

**做(优先 B1):**
- B1. 当 canonical 因 `peerSnapshotUnavailable / blockedPeerUnavailable` 回退时,**真正执行 legacy 上传链路**(`RecordingUploadCoordinator` 走 `SecureMacUploadClient` 的原上传),并以其结果为准——而不是只记 report-only 然后判失败。即 cutover 结果为 `legacyFallback`/blocked 时,落到真实 legacy 上传。
- B2.(可选,B1 之后)在 inventory 交换时让两端互相提供 canonical 快照,从根上消除 `peerSnapshotUnavailable`。
- B3. 修状态显示:当 legacy 已确认文件在对端(completed / peer proof)时,`EffectiveSyncStatus` 不得显示"需上传/失败"(遵守状态硬规则:有 peer proof / completed 才算完成)。

---

## 任务 C【验证工具】发布 / 重渲染计数器(比帧率更直接)

- C1. 给双端 `StudyLibraryStore` 加"发布计数":每次真正触发 `objectWillChange` / `@Published` 发布时 +1,每秒打点进现有诊断(**走已有异步 writer,不在主线程同步写文件**)。
- C2. 给学习库列表 `body` 加 re-eval 计数,同样打点。
- 目的:连接空闲时应 ≈ 0(修复前应是每秒几十次);进库/改名只在真正变化时少量发布。

---

## 任务 D【低优先 · 防配对偶发失效】HTTPS 监听端口占用 robustness(仅监听层)

**诊断:** `listener_failed = POSIXErrorCode 48 Address already in use`(8787),旧实例没释放端口 → 新监听 bind 失败 → 配对不出码。
**做(只动监听,绝不碰 TLS 身份/HMAC/RequestVerifier/配对时序):**
- NWListener 启用端口重用;退出/重启监听前 `cancel/close` 旧 listener 释放端口;bind 失败(`.addressInUse`)时先关旧监听再重试一次,仍失败记明确诊断并反馈 UI。

---

## 不准(再次强调)
- `git commit` 或回退现有改动。
- 改冻结清单(安全/配对/TLS/HMAC/证书)。
- 动 `RokuricsHomeView` 视觉/动画(球/TimelineView/Material),不加 `.drawingGroup()`。
- 新增 scaffolding/类型/protocol/route。
- 让 `UploadFlightRecorder` 退回"读整文件 + 重写"(保持 append-only + 后台 + 限大小,双端)。

## 验收(真机 + C 计数器)
1. 首页 / 进学习库 / 点录音卡片 / 改名 都不再卡;主线程 CoreGraphics `argb32_*` 占比大幅下降;C 计数器空闲 ≈ 0。
2. 上传能成功(大小文件都成);已在对端的文件不再显示"需上传/失败"。
3. Mac 进库保持不卡;配对稳定出 6 位码、监听 ready。
4. 编译零 error;TLS/HMAC/配对/安全逐字未改;**未 git commit**。

## 交付方式
一次一项(先 A → 真机验不卡 → 再 B → 再 C/D)。每项交:改了哪些文件、编译结果、C 计数器前后对比、真机现象。不接受"应该可以",要真机/计数证据。
