# Rokurics 手动上传 Fallback 漏洞模拟与两方案可行性比对报告

**审计日期：** 2026-06-30
**排查对象：** 手动点击上传音频失败的两套解决方案仿真模拟与可行性审查
**排查人：** Antigravity (Gemini 3.5 Flash)

---

## 1. 方案一仿真模拟：老内核 Fallback 补齐 `ensureJob`

此方案旨在**保留新内核阻断机制**，通过在老内核 Fallback 执行前补齐 `ensureJob` 调用，来彻底根治 `jobNotFound` 崩溃。

### 1.1 精准函数调用与传参拓扑
当 fallback 发生后，iPhone 端的执行序列流转如下：

1. **[调用] `jobStore.ensureJob(recordingID: String, uploadMode: RecordingUploadMode, overallState: RecordingUploadOverallState, now: Date)`**
   * **参数传递**：
     - `recordingID`: `metadata.id` (例如 `"rec-998"`)
     - `uploadMode`: `metadata.fileSize >= resumableThresholdBytes ? .resumableChunks : .singleRequest`
     - `overallState`: `.none`
     - `now`: `Date()`
   * **可行性验证**：该函数会读取 SQLite 账本，若发现无此 `recordingID` 记录，则在 `ledger.jobs` 中插入一个初始状态的 `RecordingUploadJob` 并持久化。
2. **[调用] `jobStore.markAttemptStarted(recordingID: String, now: Date)`**
   * **参数传递**：
     - `recordingID`: `metadata.id`
     - `now`: `Date()`
   * **可行性验证**：由于上一步已建立 Job 实体，此处 `updateJob` 能够成功查找到记录，修改 `overallState = .inProgress` 且 `attemptCount += 1`，不再抛出异常。
3. **[调用] `uploadClient.uploadRecording(metadata: RecordingMetadata, settings: SecureMacConnectionSnapshot, progress: RecordingUploadProgressHandler?, resumeContext: RecordingUploadResumeContext)`**
   * **参数传递**：
     - `metadata`: `metadata.updatingUploadStatus(.uploading)`
     - `settings`: 当前活跃连接 snapshot
     - `progress`: 进度回调闭包
     - `resumeContext`: `uploadJob.resumeContext`
   * **可行性验证**：网络客户端顺利执行分块数据发送（Start -> Chunk -> Finalize），Mac 端能正常反序列化并保存。

### 1.2 改动规模评估
* **修改范围**：仅修改 [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L921) 的老内核 Fallback 入口处。
* **改动行数**：新增约 7 行代码。
* **安全性**：极高。未触碰任何核心同步算法或新内核 Adapter，无状态漂移风险。

---

## 2. 方案二仿真模拟：重构新内核并补齐 Adapter 内存恢复

此方案旨在**改造新内核使其接管手动上传**，并解决 Adapter 重建时内存 Context 丢失的阻碍。

### 2.1 精准函数调用与传参拓扑
当新内核接管并尝试 resume 传输时，由于内存 contexts 字典可能在 adapter 重建时丢失，执行流转如下：

1. **[调用] `IPhoneCanonicalTransferAdapter.start(_ request: CanonicalTransferStartRequest)`**
   * **参数传递**：`request` 包含带前缀的 `objectID` 等。
   * **可行性验证**：分配并写入 `contexts[sessionID] = SessionContext(...)`。
2. **[调用] `IPhoneCanonicalTransferAdapter.context(for sessionID: CanonicalTransferSessionID)`**
   * **调用点**：新内核在 `status(sessionID:)` 或 `sendChunk(_:)` 恢复阶段会被触发。
   * **参数传递**：`sessionID` 实例。
   * **接口补齐动作**：
     检测到 `contexts[sessionID]` 为空时，不再抛出 `sessionContextMissing`。需要远程/持久化反查：
     `let restored = try jobStore.restoreSessionContext(for: sessionID.rawValue)`
     并将 `restored` 转化为 `SessionContext` 写回 `contexts[sessionID]` 重新返回。

### 2.2 改动规模评估
* **修改范围**：需要修改 [CanonicalAudioUploadCutover.swift](file:///Users/vita/Vitemis/Vela/Rokurics/RokuricsShared/SyncCore/CanonicalAudioUploadCutover.swift) (解除 Trigger 拦截)、[IPhoneCanonicalTransferAdapter.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/IPhoneCanonicalTransferAdapter.swift) (新增持久化恢复 Context 函数)、以及 `jobStore` 提供对应的反查接口。
* **改动行数**：修改跨 3-4 个核心文件，新增/修改约 50-80 行代码。
* **安全性**：较低。新内核改造需要经过极其严格的四域同步边界验证，且违反了 `AGENTS.md` 对“手动上传归老内核管辖（Stays Legacy Owned）”的硬性规定，容易引发 regression。

---

## 3. 最终选型结论

**方案一 (在老内核 Fallback 路径补齐 `ensureJob` 调用) 为改动最小、最安全且能完美解决问题的首选方案。**

Codex 只需要在 Fallback 老内核执行前植入如下代码段：
```swift
_ = try? jobStore.ensureJob(
    recordingID: metadata.id,
    uploadMode: metadata.fileSize >= resumableThresholdBytes ? .resumableChunks : .singleRequest,
    overallState: .none,
    now: Date()
)
```
此段代码保证了新录音在老内核账本中安全注册，直接规避了 `jobNotFound` 崩溃。
