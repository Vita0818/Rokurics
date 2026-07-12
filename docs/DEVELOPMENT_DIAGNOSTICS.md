# Development Diagnostics

本文描述 Rokurics 的开发专用日志收集与存储系统。该系统不提供用户界面，只在 `DEBUG` 构建中写入会话日志；现有用户功能、连接拓扑、同步协议、上传 route 和安全校验不依赖这些日志。

## 目标

- 一次 iPhone 进程运行生成一个 `test-*` 开发会话 ID。
- iPhone 通过可选请求头 `X-Rokurics-Development-Session-ID` 把会话 ID 传给 Mac；Mac 接收后把后续连接、同步和上传事件写入同一会话目录。
- `syncRunID` 和上传 `traceID` 保持为会话内的子关联键。
- 双端连接/同步 JSONL、上传 flight recorder、writer health 和状态快照可以在测试后一次性收集。
- 日志写入不进入 MainActor 文件 IO 热路径，不记录密钥、完整指纹、完整 hash、绝对私有路径、请求/响应 body、音频内容或转写/笔记正文。

## 存储结构

iPhone 根目录：

```text
Library/Application Support/Rokurics/Diagnostics/DevelopmentSessions/<testRunID>/
```

Mac local Debug 根目录：

```text
~/Library/Containers/com.Vita0818.RokuricsMac.local/Data/Library/Application Support/RokuricsLocal/Diagnostics/DevelopmentSessions/<testRunID>/
```

每个会话最多包含：

```text
iphone-events.jsonl
iphone-events.jsonl.1 ... .4
iphone-session.json
iphone-writer-health.json
mac-events.jsonl
mac-events.jsonl.1 ... .4
mac-session.json
mac-writer-health.json
```

事件文件单卷上限为 10 MB，最多保留当前卷和 4 个历史卷。每端最多保留 20 个会话，并清理超过 14 天的旧会话。队列最多暂存 8192 个事件。writer health 记录 queued、written、dropped、redactionRejected、writeFailure、pending、最后写入时间和安全的失败分类。

旧日志继续保留以兼容已有诊断代码：

- 双端 `connection-diagnostics.jsonl`。
- 双端 `upload-trace.jsonl`；上传日志仍以 `traceID` 关联。
- 双端 `device-connection-status.json`、`local-network-sync-state.json`、`study-library-sync-state.json`；Mac 另有 `pending-sync-start-signals.json`。

## 固定测试流程

1. 安装最新 Debug 构建。
2. 完全退出并重新打开 iPhone App，使本轮测试获得新的 `testRunID`。
3. 打开 Mac App，按固定场景完成配对、连接、同步和/或上传。
4. 测试到达成功或失败终态后，不清理 App 数据。
5. 保持 iPhone 通过 USB 连接并解锁，在仓库根目录运行：

```sh
Scripts/collect_development_diagnostics.sh --device '<iPhone UDID 或设备名>'
```

也可以预先设置：

```sh
export ROKURICS_IPHONE_DEVICE='<iPhone UDID 或设备名>'
Scripts/collect_development_diagnostics.sh
```

默认输出到 `codex-report/diagnostics/collection-<UTC 时间>/`。输出包括：

- Mac local/production profile 的开发会话日志、旧连接/上传日志和同步状态快照。
- iPhone Application Support/Document Diagnostics 与 Sync 状态快照。
- `manifest.json`。
- `validation/jsonl-validation.json`，逐文件报告有效行和损坏行。
- `validation/collection-warnings.txt`，记录设备文件缺失或复制失败。

收集脚本不读取 Keychain、TLS 私钥、shared secret、API key、音频文件、完整转写、完整笔记或 provider response。

## 会话关联边界

Mac 在收到 iPhone 请求头之后采用 iPhone 的 `testRunID`。Mac 在 iPhone 首次请求之前产生的 listener 启动、端口切换和配对码签发事件仍可能位于 Mac 自己的进程会话中；收集脚本会同时复制所有仍在保留窗口内的 Mac 会话，事后通过时间戳与端口关联这些前置事件。

`X-Rokurics-Development-Session-ID` 是开发诊断元数据，不是授权或业务协议字段。它不能替代或改变 TLS pinning、HMAC、nonce、防重放、body SHA256、设备凭据或 `RequestVerifier`。

## 自动化测试覆盖

- iPhone：有效 JSONL、manifest、writer health 和私有路径脱敏拒绝。
- Mac：小容量配置下的日志轮转、全部保留文件的 JSONL 解码。
- 双端 Debug generic build 确认共享文件 target membership 和平台 API 可用。
