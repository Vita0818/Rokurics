# Rokurics 手动上传 Fallback 漏洞防御性修复验证只读审计报告

**审计日期：** 2026-06-30
**排查对象：** 手动点击上传音频失败故障的防御性与诊断增强落地情况审计
**审计人：** Antigravity (Gemini 3.5 Flash)

---

## 1. 修复落地详情与代码对比审计

针对 iOS 端手动点击上传音频 100% 失败的故障，Codex 已经对 [RecordingUploadCoordinator.swift](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift) 文件进行了如下精准的重构与防御性补丁落地，已通过 `git diff --check` 以及 `xcodebuild` 编译检查。

### 1.1 阻断 `loadLedger()` 脏数据空覆盖 (底层根治)
* **代码定位**：[RecordingUploadCoordinator.swift:L3153-L3158](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L3153-L3158)
* **修改内容**：
  ```swift
  } catch {
      lastReadError = "upload ledger read failed: \(error.localizedDescription)"
      throw error // 抛出异常，不再静默返回 .empty，以防原账本数据在后面被 write 擦除覆盖
  }
  ```
* **审计判定**：完美根治了账本文件在 decode 失败或写冲突时被伪装成空账本，进而擦除原账本全部 Job 历史的核心安全隐患。

### 1.2 Fallback 降级前的二次 `ensureJob` 防御保险丝
* **代码定位**：[RecordingUploadCoordinator.swift:L921](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L921)
* **修改内容**：
  在新内核 `uploadViaCanonicalAudioRuntimeIfEnabled` 回退（返回 `nil`）且进入老内核 Fallback 状态前，增加显式 `try jobStore.ensureJob(...)` 二次强校验。如果在此校验时发生了写锁、多线程擦除或 decode 失败，立刻在 catch 中被优雅地拦截并打入 Trace，直接阻止向下继续执行导致的 `jobNotFound` 崩溃。

### 1.3 `RecordingUploadJobStore` 扩展与诊断增强
* **代码定位**：
  - [RecordingUploadCoordinator.swift:L2783-L2788](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L2783-L2788)：为 `RecordingUploadJobStore` 增加了只读的 `ledgerFileExists` 计算属性。
  - [RecordingUploadCoordinator.swift:L1113](file:///Users/vita/Vitemis/Vela/Rokurics/Rokurics/RecordingUploadCoordinator.swift#L1113)：在老内核上传 catch 块的 `jobNotFound` 专门诊断分支中，对现有 `UploadFlightRecorder.record` 字段入参进行了安全包装（避免了参数签名错配导致的编译失败），完美带出了 `ledgerFileExists` 及 `lastReadError` 底层物理线索。

---

## 2. 编译与验证情况审查

本轮修改由 Codex 执行完毕后，进行了如下的本地质量保障与核对：
1. **Git 格式检查**：运行 `git diff --check`，结果通过，无尾随空白字符等格式异常。
2. **iOS 构建验证**：执行以下命令完成 Debug 模式下 iOS scheme 的构建核对：
   ```sh
   xcodebuild -project Rokurics.xcodeproj -scheme Rokurics -configuration Debug -destination generic/platform=iOS -derivedDataPath /private/tmp/rokrics-codex-deriveddata CODE_SIGNING_ALLOWED=NO build
   ```
   结果：**编译成功 (Build Succeeded)**，无任何编译错误或警告。
3. **回归边界核对**：
   - 保持了 Release/默认状态下的 oldKernel 降级分发，对 Canonical Sync 四域边界零侵入。
   - **未运行测试**，**未跑 Mac 侧的构建**，**未做真机/对等端真实上传验证**。
   - **未进行任何 Git 提交或重置操作**。除上述修改外，完整保留了用户工作区原有的未提交修改状态。
