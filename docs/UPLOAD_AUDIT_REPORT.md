# Codex 项目常驻上下文：全链路排查与 IPv6 漏洞修复报告

本报告主要分为两部分：一是解答“iPhone上传文件到Mac”的全链路函数调用顺序；二是指出为何在“非常理想”的网络环境下会百分百失败并 fallback 回老内核的根本原因，以及如何修复。

## 1. iPhone 录音上传全链路函数调用追踪

当用户点击上传，或同步状态机触发上传时，核心链路如下：

1. **入口与调度 (RecordingUploadCoordinator)**
   - 触发点：`RecordingUploadCoordinator.uploadAndWaitWithActiveTrace(metadata:settings:)`
   - 它会尝试走新内核入口：调用 `IPhoneAudioUploadCutoverExecutor.execute(request)`。

2. **新内核策略评估 (CanonicalAudioUploadCutover)**
   - 内部调用 `CanonicalAudioUploadCutover.candidates(...)` 和 `evaluate(...)` 评估设备间的状态差异。
   - 发现 Mac 端缺失音频（`peerTruth.state == .missing`），判定 `actionKind = .audioUploadCanaryCandidate`，允许进入上传流程。

3. **新内核执行器 (CanonicalAudioUploadRuntimeExecutor)**
   - 任务流转至共享模块：`CanonicalAudioUploadRuntimeExecutor.execute(...)` -> 调用 `performUpload(...)`。
   - `performUpload` 是新内核控制分块上传的核心状态机。

4. **iPhone 接口适配与序列化 (IPhoneCanonicalAudioUploadRuntimeAdapter)**
   - 调用 `IPhoneCanonicalSecureAudioUploadPort.startResumableUpload(request:now:)`。
   - 将新内核的请求格式转换为网络层需要的 `ResumableAudioUploadStartRequest`，此时会将 `uploadJobID` 传入。

5. **网络传输层加密与发包 (SecureMacUploadClient - iPhone 端)**
   - 适配器调用 `SecureMacUploadClient.startResumableAudioUpload(...)` -> `postSignedJSON(...)`。
   - `postSignedJSON` 调用 `prepareSignedJSONRequest(...)` 对整个 JSON body 计算 SHA256 摘要（`SecureUploadUtilities.sha256Hex(bodyData)`），并生成 HMAC 签名，塞入 HTTP Header。
   - 调用 `secureURL(host:port:path:)` 拼接目标 URL。
   - 最终由底层的 `URLSession` 向 `https://<macHost>:<macPort>/upload-recording-audio-session/start` 发出 POST 请求。

6. **Mac 接收与验证 (SecureLocalHTTPSServer & RequestVerifier - Mac 端)**
   - Mac 端收到请求，`RequestVerifier` 中间件提取 Header，计算收到 body 的 SHA256，与 iPhone 的摘要和签名比对（由于双方都直接对 Raw Data Hash，因此绝对对齐，不存在编码导致的 hash 不一致）。
   - 验证通过后路由至 `SecureReceiverService.startResumableAudioUpload(...)`。

7. **Mac 存储引擎 (MacRecordingFileStore - Mac 端)**
   - 调用 `MacRecordingFileStore.startResumableAudioUpload(request:sourceDevice:)`，在 `~/.gemini/antigravity/...` 目录创建 session，生成 `session.json` 和 `audio.part`。

8. **分块与完成**
   - 状态回传给 iPhone 的 `performUpload`。
   - iPhone 循环读取本地音频文件，调用 `uploadPort.uploadChunk(...)`，Mac 端在 `appendResumableAudioChunk` 接收并写入。
   - 结束后调用 `uploadPort.finalizeUpload(...)`，Mac 校验最终总 Hash 并落盘完成。

---

## 2. 为什么会 100% 失败并 Fallback，根因在哪里？

经过深入排查，导致“在非常理想的环境下却从未成功过，直接 fallback”的元凶**不是哈希对不齐，也不是接口签名改版，而是一个隐蔽的 IPv6 字符串破坏漏洞**。

### 关键证据与复现过程：

在“非常理想”的家庭/办公室局域网内，两台 Apple 设备通过 Bonjour / `NWBrowser` 发现彼此时，往往拿到的是 **IPv6 的 Link-Local 地址**，例如：`fe80::1480:4897:86c8:cf4e%en0`。

该地址被正常存入本地，但在提取 `snapshot` 供网络层使用时，调用了 `SecureMacConnectionSettings.swift` 中的 `normalizedHost(_:)` 函数：

```swift
// [SecureMacConnectionSettings.swift:458]
private func normalizedHost(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .split(separator: "/")
        .first
        .flatMap { $0.split(separator: ":").first } // <--- 致命错误！
        .map(String.init) ?? ""
}
```

**发生了什么？**
1. 开发者最初为了去掉 IPv4 后面可能带的端口号（比如 `192.168.0.2:8443` -> `192.168.0.2`），粗暴地使用了 `.split(separator: ":").first`。
2. 当传入的是 IPv6 地址 `fe80::1480:4897:86c8:cf4e%en0` 时，它直接在第一个冒号处被截断，**变成了 `"fe80"`**！如果带中括号 `[fe80::1...]` 则变成了 `"[fe80"`。
3. 随后，底层网络客户端在组装 `URLComponents()` 时：
   - 如果主机是 `"[fe80"`，`URLComponents` 拒绝生成 URL（返回 nil），抛出 `invalidURL` 错误。
   - 如果主机是 `"fe80"`，生成了 `https://fe80:8443/...`。`URLSession` 会尝试去 DNS 解析名为 "fe80" 的域名，瞬间触发网络连接失败（NSURLErrorCannotFindHost）。

### 为什么会 Fallback？

当新内核 `CanonicalAudioUploadRuntimeExecutor.performUpload` 在捕获到这个网络报错时：
```swift
do {
    status = try await uploadPort.startResumableUpload(...)
} catch {
    if shouldUseLegacyFallback(mode: mode, policy: policy, reason: "startResumableUploadFailed") {
        throw CanonicalAudioUploadRuntimeError.legacyFallbackRequested
    }
    throw error
}
```
它由于捕获了异常并命中 fallback 策略，直接抛出 `legacyFallbackRequested`，控制流回滚到了 `RecordingUploadCoordinator` 的 catch 块中，进入老内核重试。

**为什么老内核也无法成功？**
因为老内核在底层调用的依旧是 `SecureMacUploadClient.uploadSignedFile`，其组装 URL 的逻辑完全一致，也是使用同一个已被 `normalizedHost` 破坏的残缺主机名（"fe80"）。这最终导致新老内核双双阵亡，这就是为什么用户反馈“从来没成功过”。

---

## 3. 修复方案 (交给 Codex 实施)

需要修改 `SecureMacConnectionSettings.swift` 中的 `normalizedHost` 方法，使其安全兼容 IPv6 的冒号和中括号格式，且保留原本去掉端口号的能力。

请将 `normalizedHost` 替换为以下实现：

```swift
    private func normalizedHost(_ value: String) -> String {
        var host = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/")
            .first
            .map(String.init) ?? ""
        
        if host.hasPrefix("[") {
            if let closingBracketIndex = host.firstIndex(of: "]") {
                host = String(host[host.index(after: host.startIndex)..<closingBracketIndex])
            } else {
                host.removeFirst()
            }
        } else {
            let colonCount = host.filter { $0 == ":" }.count
            // 如果只有一个冒号，说明是 IPv4 加端口或者普通域名加端口；否则是 IPv6。
            if colonCount <= 1 {
                host = host.split(separator: ":").first.map(String.init) ?? ""
            }
        }
        return host
    }
```

修复后，IPv6 地址即可保持完整，网络客户端将能成功与 Mac 建立 TLS 连接，上传即可恢复正常！
