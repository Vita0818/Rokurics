# Rokurics 二次确保 Job 与防静默异常的防御性修复方案只读审计报告

**审计日期：** 2026-06-30
**故障排查：** 手动上传 Fallback 后 `jobNotFound` 崩溃的二次防御性修复
**排查人：** Antigravity (Gemini 3.5 Flash)

---

## 1. 对齐 Codex 审查结论与底层异常隐患分析

Codex 提出的反馈极其准确：在 `uploadAndWaitWithActiveTrace` 的前置第 842 行，系统确实已经调用过 `try? jobStore.ensureJob(for: metadata, settings: settings, now: Date())`。

既然前置已经执行过 `ensureJob`，但在老内核 Fallback 起点的第 951 行执行 `markAttemptStarted` 时依然抛出 `jobNotFound` 异常，这证实了：**前置的 `ensureJob` 或其内部的 `saveJob` 落盘操作实际上抛出了异常，但被 `try?` 静默吞掉，导致 Job 并未真正持久化到 SQLite/JSON 账本中。**

### 1.1 `loadLedger()` 编解码吞错隐患
在 [RecordingUploadCoordinator.swift:L3100-3103](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L3100-L3103) 中：
```swift
} catch {
    lastReadError = "upload ledger read failed: \(error.localizedDescription)"
    return .empty
}
```
当账本文件发生并发写锁冲突、损坏或解码失败时，`loadLedger()` 会静默吞掉 Error 并返回空账本 `.empty`。虽然这保证了读取不崩溃，但若接着调用 `saveJob` 就会将整个账本清空覆盖（只剩当前这一个 Job）。如果在写入阶段又因并发或写保护抛出异常，整个 Job 就会彻底丢失。

### 1.2 `try?` 静默失败导致账本写空
在前置第 842 行，由于 `try?` 屏蔽了 `ensureJob` 的抛错，当 SQLite 物理写入失败（如 Sandbox 读写权限受限或写锁死锁）时，程序静默忽略并继续往下走。到了 fallback 分支时，`markAttemptStarted` 便无法在账本中找到对应的记录，从而抛出不匹配的 `jobNotFound` 错误。

---

## 2. 二次强校验防御性修复方案 (修改推荐)

为了防止静默失败的隐患继续向后蔓延，并确保在老内核执行时 Job 必然就绪，我们建议采纳防御性编程：**在老内核 Fallback 入口处进行 `try` 二次强校验确保 Job 存在，并对任何抛错进行显式捕获与日志留痕。**

### 2.1 修复代码设计 (仅需修改一处)

在 [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift) 第 921 行，在进入老内核上传前：

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
 
+        // 防御性二次强校验：确保在老内核 markAttemptStarted 之前 Job 已在账本中创建成功
+        // 使用 try 而非 try?，防止因物理写保护、死锁或解析损坏引发的静默失败向后蔓延
+        do {
+            _ = try jobStore.ensureJob(for: metadata, settings: settings, now: Date())
+        } catch {
+            UploadFlightRecorder.record(
+                side: .iPhone,
+                stage: "uploadCoordinatorFallbackEnsureJobFailed",
+                traceID: traceID,
+                recordingID: metadata.id,
+                eventResult: "fail",
+                uploadStatus: metadata.uploadStatus,
+                safeErrorMessage: error.localizedDescription
+            )
+            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
+            setActiveStatus(.failed, for: metadata)
+            updateErrorMessage("创建上传任务失败: \(error.localizedDescription)", for: metadata.id)
+            return .failed
+        }
+
         setActiveStatus(.uploading, for: metadata)
         updateErrorMessage(nil, for: metadata.id)
```

### 2.2 方案可行性验证与传参拓扑
1. **[调用] `jobStore.ensureJob(for: metadata, settings: settings, now: Date())`**：
   * *参数*：传入老内核所需签名匹配的 `metadata` 与 `settings`。
   * *结果*：若因并发写失败，在此处立刻抛错并由 `catch` 优雅捕获，将底层的真实写异常（如 `ledgerWriteFailed`）通过 `UploadFlightRecorder` 进行精确记录，避免向后蔓延成逻辑相悖的 `jobNotFound` 崩溃。
2. **[调用] `jobStore.markAttemptStarted(recordingID: metadata.id, now: Date())`**：
   * *结果*：由于上一环已通过强校验，此环必能顺利定位 Job。
