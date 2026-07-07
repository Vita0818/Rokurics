# Rokurics 手动上传全链路函数拓扑与新内核规避 Fallback 方案只读审计报告

**审计日期：** 2026-06-30
**排查对象：** 手动点击上传音频事件的完整函数调用拓扑与新内核阻断规避方案
**排查人：** Antigravity (Gemini 3.5 Flash)

---

## 1. 手动点击上传音频全链路函数调用拓扑 (按执行顺序)

当用户在 iPhone 端手动点击上传按钮，且系统在时钟同步、文件完整、配对成功的理想状态下运行，所涉及的完整函数调用拓扑如下：

### 1.1 iPhone 客户端触发与决策阶段
1. **[UI] `RecordingLibraryView.uploadRecording`** 或 **`RecordingStudyDetailPage.uploadCurrentRecording`**：
   - 触发手动上传入口，将 `triggerSource` 设为 `.manualUploadButton`。
2. **[Coordinator] [RecordingUploadCoordinator.swift:upload(...)](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L619)**：
   - 检查任务是否在 active 列表中，并发起异步 Task 执行 `uploadAndWait`。
3. **[Coordinator] `RecordingUploadCoordinator.uploadAndWaitWithActiveTrace(...)`**：
   - 获取 trace ID 并载入 `jobStore` 中的 Job 状态。
4. **[Coordinator] `RecordingUploadCoordinator.localAudioDecisionState(...)`**：
   - 计算本地音频文件的 SHA256 与文件大小，确定 `localAudioState` 为 `.available`。
5. **[Decision Evaluator] [StudyLibrarySyncModels.swift:evaluateRecordingAudioUploadDecision(...)](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/StudyLibrarySyncModels.swift#L685)**：
   - 传入本地状态、对等端状态与触发源，判定 `shouldCreateUploadJob == true`。
6. **[Coordinator] `RecordingUploadCoordinator.uploadViaCanonicalAudioRuntimeIfEnabled(...)`**：
   - 系统尝试使用新内核接管手动上传。

---

### 1.2 新内核判定与 Fallback 拦截阶段
7. **[Coordinator] `RecordingUploadCoordinator.uploadViaCanonicalTransferRuntimeIfEnabled(...)`**：
   - 内部发现 configuration 处于新内核传输模式，继续分发。
8. **[Decision Evaluator] [CanonicalAudioUploadCutover.swift:evaluate(...)](file:///Users/vita/Vitemis/Vela/Rokurics/RokuricsShared/SyncCore/CanonicalAudioUploadCutover.swift#L522)**：
   - **拦截点 1**：由于入参中的 trigger 是 `.manualUploadButton`（即 `isExplicitManualUploadButton`），代码第 544 行直接添加了 `.manualUploadButtonLegacyOwned` 阻断器，并将 candidate 状态标记为 `.blocked`。
9. **[Executor] [IPhoneAudioUploadCutoverExecutor.swift:execute(...)](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/IPhoneAudioUploadCutoverExecutor.swift#L109)**：
   - 调用 `canExecute` (底层调用 `uploadReadiness`)，因 candidate 状态非 `.complete` 判定 readiness 校验失败，直接返回 outcome 为 `.blocked`。
10. **[Coordinator] `RecordingUploadCoordinator.uploadViaCanonicalAudioRuntimeIfEnabled(...)`**：
    - 捕获到 outcome 为 `.blocked`，在 `switch` 中匹配到 `case .blocked` 分支，返回 `nil`，正式 fallback 回退到老内核。

---

### 1.3 老内核 Fallback 崩溃阶段 (当前 Bug)
11. **[Coordinator] `RecordingUploadCoordinator.uploadAndWaitWithActiveTrace(...)`** (第 921 行往下)：
    - 将活跃状态置为 `.uploading`。
12. **[Job Store] `RecordingUploadJobStore.markAttemptStarted(...)`**：
    - 试图通过 `updateJob` 更新此录音的上传尝试状态。
13. **[Job Store] `RecordingUploadJobStore.updateJob(...)`**：
    - **故障点 2**：在 SQLite 账本里寻找此录音 ID 的 Job。由于该录音是新录制的，账本中尚无记录，且 Fallback 路径上**没有调用 `ensureJob`**，导致 `guard let job` 判定失败并抛出 `jobNotFound` 异常。
14. **[Coordinator] `RecordingUploadCoordinator.uploadAndWaitWithActiveTrace(...)`** (外层 `catch`)：
    - 捕获 `jobNotFound` 错误，调用 `recordingManager.updateUploadStatus(..., status: .failed)` 将 UI 强行显示为 **“上传失败”**。

---

## 2. 新内核规避 Fallback 改造方案

要想让新内核直接支持手动点击上传，而不 Fallback 到老内核，新内核必须补齐以下两个维度的代码实现：

### 2.1 规避决策层拦截 (Candidate Decision Unblock)
必须在候选人状态生成器中，移去对手动上传按钮的强行拦截逻辑。
* **文件定位**：[CanonicalAudioUploadCutover.swift](file:///Users/vita/Vitemis/Vela/Rokurics/RokuricsShared/SyncCore/CanonicalAudioUploadCutover.swift)
* **改造内容**：
  在 `evaluate` 方法的 `isExplicitManualUploadButton` 判断分支中，不能直接返回 `status: .blocked`。应当允许其作为正常的 `.upload` 候选进行处理。
  ```swift
  // 修改前 (第 544 行)：
  if trigger.isExplicitManualUploadButton {
      blockers.append(.manualUploadButtonLegacyOwned)
      diagnostics.append(.canonicalAudioUploadManualButtonLegacyOwned)
      return make(..., status: .blocked, ...)
  }
  
  // 修改建议：
  // 应当仿照 peer 状态评估，将其置为可执行状态，例如：
  if trigger.isExplicitManualUploadButton {
      // 允许进入下一阶段的 readiness 校验，不再强行阻断
  }
  ```

### 2.2 补齐适配层的 Context 恢复能力 (Adapter Context Recovery)
由于 `IPhoneCanonicalTransferAdapter` 采用非持久化的内存字典 `contexts` 保存会话上下文，在 coordinator 重新实例化或实例重置时，会导致 resume 阶段因 context 丢失而报错 `sessionContextMissing`。
* **文件定位**：[IPhoneCanonicalTransferAdapter.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/IPhoneCanonicalTransferAdapter.swift)
* **改造内容**：
  当调用 `context(for sessionID:)` 发现内存字典 `contexts` 中不存在对应 Key 时，应当具备从持久化存储（如 `jobStore` 的 sqlite 记录、或者通过 `sessionID` 反向解构出的状态）重构 `SessionContext` 的能力，而不是直接抛出致命异常：
  ```swift
  private func context(for sessionID: CanonicalTransferSessionID) throws -> SessionContext {
      if let context = contexts[sessionID] {
          return context
      }
      // 补齐：若内存缺失，根据 sessionID 或 recordingID 从 SQLite 中反向查询 byteSize、contentHash，重组 SessionContext 并写回内存
      if let restoredContext = try? restoreContextFromPersistentLedger(sessionID: sessionID) {
          contexts[sessionID] = restoredContext
          return restoredContext
      }
      throw IPhoneCanonicalTransferAdapterError.sessionContextMissing(sessionID.rawValue)
  }
  ```
