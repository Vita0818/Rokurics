# Codex 项目常驻上下文

本文是未来 Codex 每轮进入本仓库时的入口文件。执行任何代码修改、配置修改、构建脚本修改或测试源码修改之前，必须先按顺序阅读并核对下列文档：

1. `docs/CURRENT_STATE.md`
2. `docs/PROJECT_MAP.md`
3. `docs/ARCHITECTURE.md`
4. `docs/DO_NOT_BREAK.md`
5. `docs/TESTING.md`
6. `docs/NEXT_TARGET.md`（如果存在）
6. `docs/SYNC_STATE_AUDIT.md`

如果文档与源码、Xcode 配置、测试或脚本冲突，必须以当前源码和配置为准，并在最终报告中明确指出冲突位置和采用源码为准的原因。

## 工作目录检查

每轮开始先在项目根目录执行：

```sh
pwd
git rev-parse --show-toplevel
git status --short
```

要求：

- `pwd` 与 `git rev-parse --show-toplevel` 必须指向同一个仓库根目录。
- 如果当前目录不是 Git root，停止修改，只报告路径问题。
- 读取 `git status --short` 后，先区分用户已有改动与本轮计划改动；不得覆盖、回退或清理用户已有改动。

## 修改边界

本仓库是 Swift/Xcode 多 target 项目，包含 iPhone app、macOS app、Live Activity extension、共享 SwiftUI/模型层、测试和辅助脚本。

未来常规任务可以按用户要求修改业务源码；但在只要求项目自查或文档更新的任务中，只允许修改：

- `AGENTS.md`
- `docs/` 下的项目说明文档

除非用户明确要求，不要修改：

- `Rokurics/`
- `RokuricsMac/`
- `RokuricsShared/`
- `RokuricsLiveActivities/`
- `RokuricsLiveActivitiesShared/`
- `RokuricsTests/`
- `RokuricsMacTests/`
- `RokuricsUITests/`
- `RokuricsMacUITests/`
- `Rokurics.xcodeproj/`
- `Scripts/`

## 禁止事项

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不引入新依赖，不改构建脚本，不改测试源码，除非任务明确要求。
- 不把密钥、token、证书私钥、shared secret、账号密码、完整指纹、完整 API 响应、完整转写文本或个人隐私路径写入文档。
- 不绕过 TLS 证书指纹校验、HMAC 签名、nonce 重放防护、Keychain/安全范围书签等安全机制。
- 不把 iPhone/Mac 的同步模型、存储 JSON schema、路径约束当作一次性内部细节随意改名或删除。

## 项目理解要求

修改前至少确认：

- target 和入口：`Rokurics/RokuricsApp.swift`、`RokuricsMac/RokuricsMacApp.swift`、`RokuricsLiveActivities/RecordingLiveActivityWidget.swift`。
- iPhone 录音与上传链路：`RecordingManager`、`AudioFileStore`、`RecordingUploadCoordinator`、`RecordingUploadClient`、`SecureMacUploadClient`。
- Mac 接收与处理链路：`SecureReceiverService`、`SecureLocalHTTPSServer`、`RequestVerifier`、`MacRecordingFileStore`、`AudioInboxStore`。
- 学习库与同步链路：`StudyFilingModels`、`StudyLibraryStore`、`StudyLibrarySyncModels`、`StudyLibrarySyncCoordinator`、`ConnectionSyncStateStores`。
- 转写/笔记/聊天链路：`TranscriptionCoordinator`、`WhisperCppTranscriptionProvider`、`NoteGenerationCoordinator`、`ChatCoordinator`、`RokuricsShared/ChatModels.swift`。
- 安全与文件访问：`KeychainStore`、`MacIdentityManager`、`PairingManager`、`SecurityScopedFileAccess`、`RokuricsMac/RokuricsMac.entitlements`。

## 文档索引

- `docs/PROJECT_MAP.md`：目录、target、入口、关键文件和生成物地图。
- `docs/ARCHITECTURE.md`：总体架构、主要链路、数据模型、同步和安全机制。
- `docs/CURRENT_STATE.md`：当前真实状态、已有能力、风险、工作区改动。
- `docs/TESTING.md`：环境、构建、测试、lint/format 与手动验证方式。
- `docs/DO_NOT_BREAK.md`：工程禁区、数据格式、协议、路径和回归要求。
- `docs/NEXT_TARGET.md`：临时下一目标记录；目标完成或不再有效后删除。
- `docs/SYNC_STATE_AUDIT.md`：连接、上传、本地网络同步状态机、触发源、no-op 边界、retry 和诊断信号。
- `docs/LongRecordingTestPlan.md`：长录音本地验证计划。

## 完成标准

完成任务前至少做到：

- 说明本轮实际阅读/检查过哪些源码、配置或测试。
- 只修改任务范围内文件。
- 保留用户已有改动。
- 运行与任务相称的检查；文档任务至少运行 `git diff --check` 与 `git status --short`。
- 将本轮已完成的持久性改动及时回写到相关项目文档；若无需更新文档，最终报告说明原因。
- 如未运行构建或测试，最终报告必须明确写“未运行构建/测试”。

## 最终报告格式

最终报告建议包含：

1. `MODEL_CHECK_RESULT`：当前模型名称；无法确认时写无法确认。
2. `PATH_CHECK_RESULT`：`pwd`、Git root、是否匹配预期。
3. `FILES_WRITTEN`：新增/修改文件。
4. `PROJECT_AUDIT_SUMMARY`：识别到的项目结构、主要模块和关键链路。
5. `DOCS_CONTENT_SUMMARY`：各文档内容摘要。
6. `VALIDATION_RESULT`：实际运行命令与结果。
7. `UNCERTAINTIES`：无法确认、需要人工确认的点。
8. `NEXT_RECOMMENDED_ACTION`：下一步建议；不要自动继续改业务源码。

## Imported Claude Cowork project instructions

Claude 任何时候都不应当修改代码；Codex 可以按本文件边界和用户任务要求正常修改代码。
