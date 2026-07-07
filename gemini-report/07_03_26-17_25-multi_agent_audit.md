MODEL_CHECK_RESULT: 无法确认（此环境没有直接暴露模型名称信息）
PATH_CHECK_RESULT: `/Users/vita/Vitemis/Vela/Rokurics` 匹配预期的 Git root。

FINDINGS:

为了彻底评估整个“录音 -> 同步 -> 转写 -> 回传”链路，我派发了 4 个只读审查子 Agent，对双端（iPhone / Mac）在网络正常、存储充足等常态下的全链路代码进行了函数级、参数级的并发审计模拟。以下是汇总整理后的完整链路详细审计报告：

---

# 🔗 完整闭环链路与函数级/参数级模拟

## 链路一：iPhone端录音、本地存储与清单生成（子 Agent 1 审计结果）
*   **物理录制启动**：
    - 入口函数：`RecordingManager.attemptRecorderStart(label:date:fallback:settings:)`
    - 音频落盘路径：调用 `AudioFileStore.makeRecordingURL(date:fallback:)`，生成类似 `Documents/Rokurics/Recordings/rokurics_<date>{_fallback}.m4a` 的绝对路径，并实例化 `AVAudioRecorder` 执行物理录音。
*   **录音落盘与元数据生成**：
    - 结束函数：`RecordingManager.stopRecording()` -> `finalizeRecording(...)`
    - 核心元数据对象：`RecordingMetadata`
      - `uploadStatus = "localOnly"`
      - `transcriptionStatus = "notStarted"`
      - `noteStatus = "notStarted"`
    - 元数据落盘路径：`AudioFileStore.saveMetadata(metadata)` 序列化后，原子写入 `Documents/Rokurics/Metadata/<recordingID>.json`。
*   **学习库及索引持久化**：
    - 入口函数：`StudyLibraryStore.upsertRecordingMetadata(_:)` -> `save(_:previousMetadata:)`
    - 机制：持久化单个项元数据 JSON 到 `study/items/<itemID>.json`；同时读取、更新并原子写回全局索引 `Documents/Rokurics/study/index.json` 的 `itemMetadataFilesByRecordingID` 和 `itemMetadataFilesByItemID` 映射。
*   **同步前的哈希校验生成**：
    - 元数据哈希：通过 `LocalNetworkSyncMetadataHash.hash(_:)` 对元数据进行排序 Key 的标准化 JSON 序列化，计算 SHA256。
    - 音频特征校验和 (SHA256)：由 `CanonicalFileChecksumRuntime` / `CanonicalChecksumCacheStore` 在后台以 **1MB 分片** 计算整轨 M4A 文件的 SHA256，写入 `canonical-checksum-cache.json` 以便同步时秒传对比。

---

## 链路二：Mac端心跳探针接收与连接状态机更新（子 Agent 2 审计结果）
*   **请求路由匹配**：
    - 入口函数：Mac 端的 `SecureLocalHTTPSServer` 通过底层的端口监听，拦截 `POST /connection/probe` 和 `POST /connection/heartbeat` 请求，分别分发给 `handleConnectionProbeRequest(...)` 和 `handleConnectionHeartbeatRequest(...)`。
*   **请求验证与解密流水线 (HMAC)**：
    - 核心类：`RequestVerifier.verify(method:path:headers:body:now:)`
    - 安全参数要求：验证 `x-rokurics-device-id`、`x-rokurics-timestamp`、`x-rokurics-nonce`、`x-rokurics-body-sha256`、`x-rokurics-signature`。
    - 校验机制：
      1. 时钟偏差校验：偏差必须在 `timestampWindow`（±300秒）内。
      2. 重放攻击防御：比对 `recentNoncesByDeviceID` 中已记录的 Nonce。
      3. Body 哈希校验：使用 `constantTimeEquals` 恒定时间比较计算出的 SHA256 与 `x-rokurics-body-sha256` 是否一致。
      4. 签名校验：将 `method + "\n" + path + "\n" + timestamp + "\n" + nonce + "\n" + bodySHA256` 作为载荷，用配对时协商的 `sharedSecretBase64URL` 秘钥进行 HMAC-SHA256 计算，校验签名。
*   **配对在线状态维护**：
    - 核心类：`DeviceConnectionStatusStore`
    - 校验成功后调用 `recordSignedRequestSucceeded(...)`，将设备状态设为 `.connected`，并在 `device-connection-status.json` 中更新 `lastSeenAt`。

---

## 链路三：Mac端转写调度与状态广播（子 Agent 3 审计结果）
*   **转写触发机制**：
    - **确认：非自动开始**。Mac 端在 `audioUploadResponse(...)` 收到音频后，其在 `receive.json` 中的 `processingStatus` 仅设为 `"notStarted"`。必须由用户在 Mac UI 界面（如 `MacAudioInboxView` 或 `MacStudyLibraryView`）手动点击转写，调用 `TranscriptionCoordinator.startTranscription(recordingID:)`。
*   **转写规划与 Provider 调度**：
    - 切片规划：调用 `LongAudioTranscriptionPlanner.plan(duration:)`。
      - 阈值：若时长超过 30 分钟（1800秒），转为 `.chunked` 切片模式（每 15 分钟切一片）。
    - 音频裁剪转码：调用 `AudioPreprocessor.prepareAudio(for:)`，利用 `AVAssetReader`（在 `NativeAudioConverter` 中）提取时间区间并将 M4A 转码为 WAV 临时文件。
    - Provider 调用：`WhisperCppTranscriptionProvider.transcribe(...)`，通过 `runProcess(...)` 调起外部可执行文件 `whisper-cli` 进行本地转写。
    - 合并与落盘：切片转写完成后，调用 `TranscriptionChunkMerger.merge(...)`，并使用 `TranscriptStore` 保存最终的 `transcript.json` 和 `transcript.md`。
*   **转写状态更新与本地广播**：
    - 状态写入：`MacRecordingFileStore.updateTranscriptionStatus` 将转写状态（`completed`、路径等）写回对应录音的 `receive.json`，并调用 `postInboxChanged()`。
    - 状态收敛信号发射：通过 `LocalNetworkSyncEventTrigger.postStatusConvergenceRefresh(.transcriptionStatusChanged, ...)` 发出 `.localNetworkSyncEventTriggered` 通知。
    - 信号排队：`SecureReceiverService` 捕获该通知后，调用 `queueMacSyncEvent`，经过 0.75 秒去抖防抖后，调用 `drainMacSyncEventQueue()` 生成一个唯一的 `syncRunID`，并使用 `deviceConnectionStatusStore.recordPendingSyncRequest(...)` 包装成下行 `syncStartSignal`（等待 iPhone 的下一次 Probe 心跳拉取）。

---

## 链路四：双端工件（转写文本）同步握手与校验（子 Agent 4 审计结果）
*   **下行下载计划生成**：
    - 当 iPhone 的下一次 Probe 心跳在 Mac 端被消费时，`SecureLocalHTTPSServer.probeResponse(...)` 会调用 `consumePendingSyncStartSignal`，返回 `syncRequested = true`。
    - iPhone 收到心跳响应，触发 `LocalNetworkSyncEngine.performSync`，调用 `LocalNetworkSyncDiffPlanner`。
    - 规划器对比双端 Inventory，发现 Mac 端有新工件，在 `plan.downloadArtifactActions` 中生成工件下载动作为 `.downloadArtifact`。
*   **工件请求发送 (iPhone -> Mac)**：
    - iPhone 调用 `downloadPeerArtifact(...)`。若工件小于等于 4MB，直接调用 `SecureMacUploadClient.requestLocalNetworkSyncArtifact(...)`，向 Mac 发起带有安全签名的 `POST /sync/artifact-request` 请求。
*   **Mac 端安全读取文件与传输**：
    - Mac 端通过 `RequestVerifier` 验签后，由 `LocalNetworkSyncArtifactFileService.safeFileURL(...)` 解析工件路径。
      - *安全防线*：通过 `validateLogicalPathToken` 严格防范目录穿越攻击（如禁止空路径、禁止包含 `..`、校验前缀后缀如 `transcripts/` 和 `.md`）。
    - Mac 端在后台线程通过 `FileHandle` 读取工件内容，计算该分片的 SHA256，返回 `LocalNetworkSyncArtifactResponse`。
*   **iPhone 校验落盘与原子替换**：
    - 校验数据：iPhone 验证返回包中的 `checksum` 与数据实际哈希是否匹配。
    - 临时暂存：先写入 `Sync/Incoming/<artifactID>.part` 临时文件。
    - 原子替换：调用 `atomicReplace(tempURL:destinationURL:)`，使用 `FileManager.default.replaceItemAt(...)` 或 `moveItem` 原子性地将转写文本替换到最终物理路径，避免写入过程断电造成破损。

---

# ⚠️ 链路潜在漏洞与失败点深度剖析

结合 4 个子 Agent 的反馈，我们定位了如下深层次的漏洞与断链隐患：

1.  **心跳同步信号的一次性“毁灭性消费” (Destructive Consumption)**：
    - **位置**：`SecureLocalHTTPSServer.probeResponse`
    - **逻辑**：Mac 端从内存中 `pop`（并物理删除）`syncStartSignal` 发生在**发送 HTTP 响应之前**。
    - **漏洞**：如果此时网络突然断开、或者 TCP 链接因超时重置，iPhone 将无法收到含有 `syncRequested=true` 的响应。由于信号已被 Mac 从队列中永久删除，Mac 不会重试，iPhone 也就不会自动拉取最新的转写，导致同步断链，除非用户在 iPhone 再次手动触发“立即同步”。

2.  **通知 ID 12位字符截断漏洞 (Recording ID Truncation)**：
    - **位置**：`LocalNetworkSyncEventTrigger.swift` 的 `postStatusConvergenceRefresh` 等方法中：
      ```swift
      if let recordingID {
          userInfo[recordingIDUserInfoKey] = String(recordingID.prefix(12))
      }
      ```
    - **漏洞**：广播通知 `.localNetworkSyncEventTriggered` 时，它将 `recordingID` 截断为了 12 位前缀。虽然目前 Mac 的接收端 `SecureReceiverService` 仅将此 12 位 ID 用于日志和控制流，但如果有任何新模块或测试试图利用通知中的该 ID 检索数据库或在沙盒中查找具体文件，将会由于 ID 不完整而引发查询失败。

3.  **转写切片无断点恢复能力 (All-or-Nothing Chunking)**：
    - **位置**：`TranscriptionCoordinator.swift` 中的 Chunks 遍历。
    - **漏洞**：针对大于 30 分钟的长音频，若在 10 个切片的转写过程中，第 9 个切片因为 `whisper-cli` 偶发挂起或资源不足失败，整个转写任务会直接中断并被标记为 `failed`。用户下一次点击重试时，**必须从 Chunk 0 开始重新转写**，已经成功的前 8 个分片无法被复用，对设备的 CPU/电池造成严重的无效开销。

4.  **音频损坏导致 AVAssetReader 崩溃阻断转写**：
    - **位置**：`NativeAudioConverter.swift` 中使用 `AVAssetReader` 处理 M4A 转换。
    - **漏洞**：如果 iPhone 上传过来的 M4A 音频在传输中发生了部分物理损坏，或者缺少音轨描述符，`AVAssetReader` 初始化或启动时会直接抛出 `nativeAudioReaderFailed` 错误。由于缺乏降级容错（例如使用 FFmpeg 容错读取或跳过受损帧），该文件的转写将永久失败。

5.  **沙盒安全书签失效 (Sandbox Security Bookmark Expiry)**：
    - **位置**：`WhisperCppTranscriptionProvider` 对可执行文件路径和模型路径的验证。
    - **漏洞**：在 macOS 严格沙盒下，通过 Security-Scoped Bookmarks 获取外部 `whisper-cli` 和模型的读取权限。如果用户系统发生配置重置，或者文件位置被物理移动，书签会直接失效，抛出权限异常且无自动修复引导。

6.  **iPhone 状态缓存 JSON 破损导致 IO 风暴**：
    - **位置**：`CanonicalChecksumCacheStore.swift` 缓存加载。
    - **漏洞**：如果 `canonical-checksum-cache.json` 遭到逻辑损坏，系统在同步初始化时会回退到完全重新计算本地所有音频的 SHA256。因为需要以 1MB 为分块遍历所有大音频文件，会引发严重的磁盘 IO 暴涨和 CPU 占用，这可能直接触发 iOS 系统的后台热量或功耗熔断机制，导致 APP 被强制杀掉。

---

FILES_WRITTEN:
- `gemini-report/07_03_26-17_25-multi_agent_audit.md` (已保存至项目根目录的只读审查报告目录)

VALIDATION_RESULT:
由于处于只读模式且子 Agent 容器不包含编译/运行环境，未执行构建和测试。仅执行了深度的静态代码审查与时序模拟。

NEXT_RECOMMENDED_ACTION:
目前已完成全部 4 条链路的并发模拟和漏洞梳理。如您希望针对上述某些高风险漏洞（如心跳下行信号的毁灭性消费逻辑、ID 截断问题、或断点续传能力）进行修复，请将相应指令下达给 **Codex** 进行代码级修改。本次只读审计到此圆满结束。
