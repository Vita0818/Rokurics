# Rokurics LibraryMetadata Real-Device Debug Switch Runbook

日期：2026-06-07

## Scope

本 runbook 只用于 Debug/internal 真机预检 `libraryMetadata` pilot。它不启用 release/default，不切 read path，不删除 legacy，不启用其它 domain，也不代表真机验证已经完成。

## Preconditions

- 使用 Debug build。
- Settings 中可见 `Debug · 学习库迁移试点`。
- 默认模式为 `off`。
- `generatedArtifacts`、`tombstoneConflict`、`audioUpload`、`recordingMetadata` 仍 staticOnly/defaultOff。
- legacy read/write/fallback 保留。
- 没有真机 jsonl 前，不得声称 pilot 已验证。

## Mode Order

1. `off`
   - `.disabled + nil executor`。
   - app 行为应与原默认路径一致。

2. `diagnosticsOnly`
   - 第一轮真机步骤。
   - 只运行 LandingFreeze/diagnostics。
   - 不构造 executor，不提交，不 suppress legacy。

3. `armTestRootN1`
   - 第二轮步骤。
   - 使用系统临时目录 test root。
   - 构造现有 bootstrap executor，但只 arm/readiness，不写 production root。

4. `executeTestRootN1`
   - 第三轮步骤。
   - 使用系统临时目录 test root。
   - 只限 N=1 libraryMetadata。
   - 不写 production root。

5. `executeProductionRootN1`
   - 必须 UI 二次确认。
   - 确认文案必须说明会允许写真实学习库 metadata 根、只限 libraryMetadata、只限 N=1、保留 rollback 与 legacy fallback、这是第一次真实写。
   - 只有此模式允许 `allowProductionRootWrites=true`。

## Enable DiagnosticsOnly

1. 在 iPhone / Mac Settings 打开 `Debug · 学习库迁移试点`。
2. 选择 `diagnosticsOnly`。
3. iPhone 重新进入连接/同步页面，使 `StudyLibrarySyncCoordinator` 用新设置构造。
4. Mac 重新启动 app 或重新构造 receiver，使 `RokuricsMacApp.makeSecureReceiverService()` 读取新设置。
5. 执行一次普通同步触发。

## Diagnostics Files

iPhone:

- `Documents/Rokurics/Sync/Diagnostics/connection-diagnostics.jsonl`
- 可通过 Xcode Devices & Simulators 下载 app container。

Mac:

- `~/Library/Application Support/Rokurics*/Sync/Diagnostics/connection-diagnostics.jsonl`
- `~/Library/Application Support/Rokurics*/Sync/Diagnostics/canonical-shadow.jsonl`

不要收集或粘贴完整本机路径。

## Verify Default And Release Disabled

- `off` 下 `canonicalLibraryMetadataDebugPilotConfiguration == .disabled`。
- `off` 下 executor 为 nil。
- Release/default 不显示 Debug 区。
- Release/default 不启用 pilot。
- runtimeSwitch 仍 false。
- read path 仍 legacy。

## Verify No Side Effects

检查 diagnostics 和行为：

- 没有 read path cutover。
- 没有 UI 默认行为变化。
- 没有 sync/upload 被 read 触发。
- 没有资源移动。
- 没有 standalone note content write。
- 没有 tombstone/delete/trash/permanent delete/tombstone GC。
- 没有 `receive.json` 非预期 mutation。
- 没有 transcription/note generation 被 pilot 触发。
- legacy fallback retained。

## Collect For Claude

- redacted `connection-diagnostics.jsonl` 事件摘要。
- redacted `canonical-shadow.jsonl` 事件摘要。
- LandingFreeze result。
- libraryMetadata pilot mode。
- node role。
- event counts for:
  - `canonicalLibraryMetadataLandingConfigEvaluated`
  - `canonicalLibraryMetadataLandingReadSideEquivalent`
  - `canonicalLibraryMetadataLandingReadSideDivergent`
  - `canonicalMigrationLandingFreezeViolation`
  - `canonicalLibraryMetadataCanaryStageFailed`
  - `canonicalLibraryMetadataCanaryStageBlocked`
- blocker summary and counts only。

## Do Not Collect

- 完整 metadata JSON。
- standalone note content。
- transcript/note/summary content。
- provider response。
- secrets、tokens、shared secrets。
- complete fingerprints。
- complete hashes。
- request/response bodies。
- absolute local paths。

## Immediate Disable

1. Settings 中将模式改回 `off`。
2. iPhone 重新进入连接/同步页面。
3. Mac 重启 app 或重新构造 receiver。
4. 确认新构造为 `.disabled + nil executor`。

Disable 不需要数据迁移，不触碰 production 数据，不删除 legacy。

## Completion Criteria

代码接线完成只表示 Debug switch 能构造既有 config/executor。真机完成必须有真实设备生成的 jsonl；测试 fixture、simulator output 或单元测试不能替代真机证据。

下一步最小动作：先跑 `diagnosticsOnly`，收集 redacted 真机 jsonl 后交 Claude 审计。不要直接扩到新 domain、read cutover 或 legacy retirement。
