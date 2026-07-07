# Rokurics Fallback 二次防御与账本静默空覆盖终极修复报告

**审计日期：** 2026-06-30
**排查对象：** 手动点击上传音频失败的 Codex 反馈修正与账本静默覆盖故障终极修复
**排查人：** Antigravity (Gemini 3.5 Flash)

---

## 1. 深度对齐 Codex 反馈与根本成因深挖

Codex 的反馈极具技术水准与代码洞察力。它指出了我上一版补丁的前提误区：
在 [RecordingUploadCoordinator.swift:L842](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L842) 的前置阶段，`ensureJob` 是写在 `do-catch` 内的强 `try` 运行。一旦写入失败，在 842 行即会以 `.failed` 退出，根本不可能走到后面的老内核 Fallback。

那么，既然前置 `ensureJob` 百分之百成功落盘了，为什么到了第 951 行执行 `markAttemptStarted` 还会抛出 `jobNotFound`？

### 1.1 隐患分析：`loadLedger()` 损坏伪装成空账本
* **代码定位**：[RecordingUploadCoordinator.swift:L3085-L3104](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L3085-L3104) 处的 `loadLedger()`：
  ```swift
  do {
      let data = try Data(contentsOf: url)
      let ledger = try Self.decoder.decode(RecordingUploadJobLedger.self, from: data)
      ...
  } catch {
      lastReadError = "upload ledger read failed: \(error.localizedDescription)"
      return .empty // 致命点
  }
  ```
* **逻辑漏洞**：如果账本文件因为多线程并发读写死锁、或者新内核（如 Transfer 运行时）在写入时导致数据损坏，`loadLedger` 会把“账本损坏”伪装成“空账本（`.empty`）”并返回。
* **致命后果**：
  在 fallback 入口之前的其它流程中，如果因为账本读取失败返回了空 `.empty`，那么接下来的任何 `saveJob` 都会将原账本清空覆盖（只剩下当前这一个 Job），这会静默地擦除以前全部的 Job 历史。而在 Fallback 路径的执行间隙中，如果账本被并发擦除，就会导致后面的 `markAttemptStarted` 瞬间抛出 `jobNotFound`。

---

## 2. 三合一终极比对与修复方案

为了彻底解决账本静默损坏以及 Fallback 起始点的稳定性问题，建议采纳以下三位一体的终极修复方案：

### 2.1 修复一：将 `loadLedger()` 解码失败修改为抛出显式错误 (阻止静默空覆盖)
在 `loadLedger()` 捕获到编解码异常时，不再返回空账本，而是通过 `throw error` 阻断后续对原账本的脏写入，保护原账本数据。

* **[MODIFY] [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L3100)**：
```swift
        } catch {
            lastReadError = "upload ledger read failed: \(error.localizedDescription)"
            throw error // 抛出异常，不再返回空账本以防御原账本被擦除
        }
```

### 2.2 修复二：在老内核 Fallback 前加装“二次 EnsureJob 防御保险丝”
在 `uploadViaCanonicalAudioRuntimeIfEnabled` 返回 nil 且即将运行老内核的第 921 行，加装二次 `try ensureJob`，作为多线程/并发擦除窄窗口的安全防火墙：

* **[MODIFY] [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L921)**：
```swift
        // 二次防御强校验：确保在老内核 markAttemptStarted 之前 Job 已成功处于账本中
        do {
            _ = try jobStore.ensureJob(for: metadata, settings: settings, now: Date())
        } catch {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "uploadCoordinatorFallbackEnsureJobFailed",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "fail",
                uploadStatus: metadata.uploadStatus,
                safeErrorMessage: error.localizedDescription
            )
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            setActiveStatus(.failed, for: metadata)
            updateErrorMessage("创建上传任务失败: \(error.localizedDescription)", for: metadata.id)
            return .failed
        }
```

### 2.3 修复三：在 `markAttemptStarted` 抛出 `jobNotFound` 时，记录诊断 Trace 现场
在 `RecordingUploadJobStore` 中公开 `ledgerFileExists` 属性，并在 Fallback 的 catch 块中对 `jobNotFound` 进行专门的 trace 日志记录，暴露当时的账本物理状况：

* **[NEW] [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L2733)**：
```swift
    var ledgerFileExists: Bool {
        guard let url = try? ledgerURL() else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
```

* **[MODIFY] [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L1050)**：
```swift
        } catch {
            if let storeError = error as? RecordingUploadJobStoreError,
               case .jobNotFound(let recID) = storeError {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "uploadCoordinatorJobNotFoundDiagnostic",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: "job_not_found_on_fallback",
                    ledgerLastReadError: jobStore.lastReadError, // 暴露是否因解码失败损坏过
                    ledgerFileExists: jobStore.ledgerFileExists, // 暴露账本文件物理是否存在
                    safeErrorMessage: error.localizedDescription
                )
            }
            let classification = RecordingUploadFailureClassification.classify(error)
```
