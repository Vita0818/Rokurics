# Rokurics 手动上传 Fallback 引发的 JobNotFound 致命故障只读审计报告

**审计日期：** 2026-06-30
**故障现象：** iPhone 手动点击上传新录音时，百分之百触发“上传失败”
**排查人：** Antigravity (Gemini 3.5 Flash)

---

## 1. 故障核心成因定位

在 [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift) 的上传协调器中，当新内核（Canonical Audio/Transfer Runtime）由于策略拦截（如 explicit manual upload button stays legacy owned）而返回 `nil` 并回退（Fallback）到老内核上传路径时，由于**缺少 Job 初始化注册（Ensure Job）**，直接导致了数据库状态机崩溃。

### 1.1 缺失的 Job 注册调用
在老内核的正常同步或旧版上传逻辑中，系统在操作 Job 账本之前必须先调用 `jobStore.ensureJob(...)`。
但是在 `uploadAndWaitWithActiveTrace` 方法的 Fallback 降级分支中：
* **代码定位**：[RecordingUploadCoordinator.swift:L921-L951](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L921-L951)
* **执行逻辑**：
  ```swift
  // 1. 新内核返回 nil fallback
  if let canonicalStatus = await uploadViaCanonicalAudioRuntimeIfEnabled(...) { return canonicalStatus }

  // 2. 状态直接设为 uploading
  setActiveStatus(.uploading, for: metadata)
  updateErrorMessage(nil, for: metadata.id)

  do {
      let audioURL = try jobStore.audioURL(for: metadata)
      // ... 检查文件大小 ...

      // 3. 致命点：没有调用 ensureJob，直接调用 markAttemptStarted
      let uploadJob = try jobStore.markAttemptStarted(recordingID: metadata.id, now: Date())
  ```

### 1.2 `updateJob` 抛出 `jobNotFound` 异常
当被上传的录音是一个“全新的、从未上传过”的录音时，SQLite 账本（Job Store）内尚未建立对应的上传 Job 数据。
* **代码定位**：[RecordingUploadCoordinator.swift:L2797-2804](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L2797-L2804) 处的 `updateJob`：
  ```swift
  private func updateJob(recordingID: String, mutate: (inout RecordingUploadJob) -> Void) throws -> RecordingUploadJob {
      var ledger = try loadLedger()
      guard var job = ledger.jobs.first(where: { $0.recordingID == recordingID }) else {
          // 这里会直接抛出 jobNotFound 异常
          throw RecordingUploadJobStoreError.jobNotFound(recordingID)
      }
      mutate(&job)
      ...
  }
  ```
因为账本中查不到该录音 ID 的 Job，`markAttemptStarted` 抛出 `jobNotFound`。该 Error 被外层的 `catch` 捕获后，立即将 UI 的上传状态修改为 `.failed` 并更新错误信息。

---

## 2. 修复建议（供 Codex 后续操作）

Codex 在被授权修改业务代码时，应按如下方式在 Coordinator 的 Fallback 分支前插入 `ensureJob`：

```diff
         if let canonicalStatus = await uploadViaCanonicalAudioRuntimeIfEnabled(
             metadata: metadata,
             settings: settings,
             recordingManager: recordingManager,
             traceID: traceID,
             triggerSource: triggerSource,
             localAudioState: localAudioState,
             peerAudioState: peerAudioState,
             ledgerState: uploadLedgerState(try? jobStore.loadJob(recordingID: metadata.id)),
             syncRunID: syncRunID
         ) {
             return canonicalStatus
         }
 
+        // 在尝试 markAttemptStarted 之前，先保证 job 已经在 ledger 中创建
+        _ = try? jobStore.ensureJob(
+            recordingID: metadata.id,
+            uploadMode: metadata.fileSize >= resumableThresholdBytes ? .resumableChunks : .singleRequest,
+            overallState: .none,
+            now: Date()
+        )
+
         setActiveStatus(.uploading, for: metadata)
         updateErrorMessage(nil, for: metadata.id)
```
