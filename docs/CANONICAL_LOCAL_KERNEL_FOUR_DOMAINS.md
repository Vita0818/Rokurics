# Rokurics Canonical Local Kernel · 四域内核定义

**建议保存路径**：`docs/CANONICAL_LOCAL_KERNEL_FOUR_DOMAINS.md`  
**用途**：作为后续 Codex / Claude / 人工审计的上下文基准。  
**日期**：2026-06-14  
**状态**：架构定义与执行路线；不是现状完成声明。

---

## 0. 一句话定义

Rokurics 的新内核不应再被理解为“同步模型”或“canonical diff/apply/read projection”。

它应该被定义为一个可复用的 **Canonical Local Collaboration Kernel**，包含四个一等域：

```text
1. Connection Kernel
   本地局域网 HTTPS、身份、配对、安全通道、heartbeat、peer liveness、syncRequested hint。

2. Transfer Kernel
   文件传输协议、session、chunk、offset、断点续传、finalize proof、retry/backoff。

3. Sync Kernel
   多端状态真相、实时状态交换协议、event-driven sync、diff/LWW、apply plan、read projection。

4. File Kernel
   文件树管理、manifest、metadata store、checksum cache、root-bound write、atomic/rollback、off-main indexing、不卡顿保证。
```

后续任何任务如果只修改 `SyncCore` model、read projection、canary、evidence 或 scorecard，但没有处理四域 owner、状态真相、实时交换、文件不卡顿，就不得声称“新内核完成”。

---

## 1. 为什么必须重新定义内核

之前的 canonical kernel 主要聚焦在：

```text
canonical object model
metadataHash
planner / diff
apply plan
read projection
gate / fallback / scorecard
```

这些都是必要的，但不足以构成产品级同步内核。

实际用户问题暴露出两个根本缺口：

1. **卡顿不是 diff 能解决的**  
   UI read path、file tree rebuild、Mac server inventory、manifest build、checksum/hash、diagnostics IO 都属于运行时与文件域问题。如果 File Kernel 没有明确的 off-main / cache / bounded IO 合同，canonicalFullSync 只会把更多工作叠到主线程。

2. **状态不一致不是 schema 能解决的**  
   状态收敛依赖“何时、由谁、通过哪个通道、带着什么 proof，把哪个状态事实告诉谁”。如果 Connection / Transfer / Realtime Status Exchange 仍被视作 legacy 外围，Sync Kernel 就只能算出正确 plan，但不能保证状态及时一致。

因此新定义必须把连接、上传、同步、文件四个域都纳入 canonical kernel。

---

## 2. 四域边界

| 域 | 必须拥有 | 明确不拥有 |
|---|---|---|
| **Connection Kernel** | peer identity、pairing、local HTTPS carrier、TLS/HMAC adapter boundary、nonce/body hash contract、heartbeat、peer liveness、syncRequested、capability exchange | 不直接决定业务状态；不直接读写文件内容；不直接传大文件块 |
| **Transfer Kernel** | resumable upload/download session、chunk、offset、confirmedBytes、status、resume、finalize proof、retry/backoff、idempotency | 不决定 UI 最终状态；不绕过 Connection 安全；不直接扫描文件树 |
| **Sync Kernel** | status truth、status fact/proof、delta/ack/request、event-driven sync、diff/LWW、apply plan、read projection、conflict/defer/block policy | 不直接做 TLS/HMAC；不直接做大文件 IO；不直接控制平台 UI |
| **File Kernel** | file tree、manifest、metadata store、artifact store、checksum cache、stable file identity、root-bound write、atomic/rollback、off-main scan/hash/index、no-freeze budget | 不决定 peer proof；不直接发网络；不把 local file presence 伪装成 peer confirmed 状态 |

四域之间必须通过协议交换事实，不允许跨层随意读取内部状态。

---

## 3. 总体架构

```text
Canonical Local Collaboration Kernel

┌─────────────────────────────────────────────────────────────┐
│  Connection Kernel                                           │
│  peer identity / secure channel / heartbeat / syncRequested  │
└───────────────┬─────────────────────────────────────────────┘
                │ carries envelopes / acks / requests
┌───────────────▼─────────────────────────────────────────────┐
│  Sync Kernel                                                 │
│  status truth / realtime status exchange / diff / apply/read │
└───────┬───────────────────────────────────────────────┬─────┘
        │ consumes proofs                                │ uses file facts
┌───────▼────────────────────────┐         ┌────────────▼──────────────┐
│  Transfer Kernel                │         │  File Kernel              │
│  session/chunk/resume/finalize  │         │  tree/manifest/cache/IO   │
└────────────────────────────────┘         └───────────────────────────┘
```

Rokurics 当前 local HTTPS、TLS、HMAC、RequestVerifier 是 **Connection Adapter**，不是 portable protocol 本身。未来其他项目可以替换为 WebSocket、CloudKit、WebRTC、LAN TCP、Bonjour + HTTP 等 transport。

---

## 4. Connection Kernel

### 4.1 职责

Connection Kernel 负责建立和维护 peer 间的安全、可观察通信通道。

必须覆盖：

```text
node identity
peer identity
pairing
capability negotiation
local HTTPS carrier contract
heartbeat
peer liveness
syncRequested hint
status envelope carrier
connection diagnostics
```

### 4.2 Portable protocol

建议定义：

```swift
struct CanonicalNodeIdentity: Hashable, Codable {
    let nodeID: String
    let deviceRole: CanonicalNodeRole
    let stableDeviceToken: String
}

struct CanonicalPeerLiveness: Codable, Equatable {
    let peerID: String
    let isReachable: Bool
    let lastHeartbeatAt: CanonicalLogicalTime?
    let status: CanonicalPeerConnectionStatus
}

struct CanonicalConnectionEnvelope<Payload: Codable>: Codable {
    let protocolVersion: String
    let sender: CanonicalNodeIdentity
    let receiver: CanonicalNodeIdentity?
    let sequence: UInt64
    let sentAt: CanonicalLogicalTime
    let payload: Payload
}

protocol CanonicalConnectionCarrier {
    associatedtype Payload: Codable

    func send(_ envelope: CanonicalConnectionEnvelope<Payload>) async throws -> CanonicalConnectionAck
    func receive() async throws -> CanonicalConnectionEnvelope<Payload>
}
```

### 4.3 Rokurics adapter

```text
RokuricsLocalHTTPSConnectionAdapter
  - uses existing local HTTPS server/client
  - uses TLS pinning / HMAC / nonce / body hash
  - uses RequestVerifier on Mac
  - carries heartbeat/status/syncRequested/status exchange envelopes
```

### 4.4 Non-goals

Connection Kernel 不应该直接：

```text
mark uploaded
mark audioAvailable
scan file tree
write metadata
read transcript/note/summary content
create upload job
trigger AI generation
```

---

## 5. Transfer Kernel

### 5.1 职责

Transfer Kernel 负责大文件或二进制对象传输。

必须覆盖：

```text
session start
status
chunk upload/download
offset / confirmedBytes
resume
duplicate chunk idempotency
finalize
hash + byteSize verification
abort before finalize if supported
retry / backoff
app restart recovery
no full-file memory load
```

### 5.2 Portable protocol

建议定义：

```swift
struct CanonicalTransferSessionID: Hashable, Codable {
    let rawValue: String
}

struct CanonicalTransferChunk: Codable, Equatable {
    let sessionID: CanonicalTransferSessionID
    let objectID: CanonicalObjectID
    let offset: Int64
    let length: Int
    let chunkHashPrefix: String?
}

struct CanonicalTransferFinalizeProof: Codable, Equatable {
    let sessionID: CanonicalTransferSessionID
    let objectID: CanonicalObjectID
    let byteSize: Int64
    let contentHash: CanonicalHashProof?
    let finalizedAt: CanonicalLogicalTime
    let receiverNodeID: CanonicalNodeID
}

protocol CanonicalTransferPort {
    func start(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession
    func status(_ sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus
    func sendChunk(_ chunk: CanonicalTransferChunk, bytes: AsyncSequenceOfBytes) async throws -> CanonicalTransferChunkAck
    func finalize(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof
}
```

### 5.3 Proof rules

```text
partial receive != completed
local ledger only != peer proof
metadataOnly != audioAvailable
same hash + same byteSize = no-op proof
finalize proof = receiver accepted bytes/hash/size
peer inventory hash+size match = peer verified proof
existing different hash/size = conflict, no overwrite
```

### 5.4 Rokurics adapter

```text
RokuricsResumableUploadAdapter
  - reuses existing SecureMacUploadClient / RecordingUploadClient
  - reuses existing Mac SecureLocalHTTPSServer upload routes
  - does not add routes
  - does not bypass RequestVerifier / TLS / HMAC / nonce / body hash
```

---

## 6. Sync Kernel

Sync Kernel 是四域中最容易被误解的一层。它不是简单 diff。它必须同时拥有：

```text
object model
diff / LWW
apply plan
status truth
realtime status exchange
event-driven sync policy
read projection
conflict/defer/block policy
```

---

## 7. State Truth Protocol

### 7.1 原则

UI 不应该自己从 upload ledger、receive record、metadataOnly ledger、local file existence、peer inventory 等多个地方拼状态。

所有 UI、planner、upload runtime 应该只读取：

```text
CanonicalEffectiveSyncStatus
```

该状态必须包含 **source** 和 **proof**。

### 7.2 类型建议

```swift
struct CanonicalStatusFact: Codable, Equatable {
    let objectID: CanonicalObjectID
    let domain: CanonicalStatusDomain
    let phase: CanonicalStatusPhase
    let source: CanonicalStatusSource
    let proof: CanonicalStatusProof
    let causality: CanonicalStatusCausality
    let observedAt: CanonicalLogicalTime
    let expiresAt: CanonicalLogicalTime?
}

enum CanonicalStatusPhase: String, Codable {
    case absent
    case localOnly
    case peerUnknown
    case metadataOnly
    case peerKnownMetadataOnly
    case uploadNeeded
    case uploading
    case partialReceive
    case finalizing
    case finalizedLocally
    case peerVerified
    case completed
    case deferred
    case blocked
    case conflict
    case stale
}

enum CanonicalStatusProof: Codable, Equatable {
    case none
    case localFileExists(byteSize: Int64, hashPrefix: String?)
    case localLedgerOnly
    case metadataOnlyLedger
    case partialReceiveRecord(confirmedBytes: Int64)
    case finalizeProof(CanonicalTransferFinalizeProof)
    case peerInventoryHashSizeMatch(byteSize: Int64, hashPrefix: String)
    case peerAck(sequence: UInt64)
    case dualAck(localSequence: UInt64, peerSequence: UInt64)
    case conflictProof(reason: CanonicalConflictReason)
    case expiredProof(previous: String)
}

struct CanonicalEffectiveSyncStatus: Codable, Equatable {
    let objectID: CanonicalObjectID
    let domain: CanonicalStatusDomain
    let phase: CanonicalStatusPhase
    let displayState: CanonicalDisplaySyncState
    let proof: CanonicalStatusProof
    let sourceSummary: CanonicalStatusSourceSummary
    let canDisplayAsComplete: Bool
    let canCreateUploadJob: Bool
    let canSuppressLegacyDuplicate: Bool
    let blocker: CanonicalStatusBlocker?
}
```

### 7.3 Hard rules

这些规则必须是 kernel 规则，不是 UI 约定：

```text
metadataOnly != audioAvailable
receiveRecordOnly != audioAvailable
completed ledger alone != peer proof
partial receive != completed
local file exists != peer has file
expected manifest hash != peer proof
same hash + same byteSize 才是 audio no-op
finalize proof / peer hash-size proof 才能显示 peerVerified/completed
peerUnknown 必须 deferred
existing different audio 必须 conflict/no-overwrite
view refresh 不得创建 upload job
retry drainer 只恢复 existing eligible job，不创建 unrelated fresh job
```

---

## 8. Realtime Status Exchange Protocol

### 8.1 目标

Realtime Status Exchange Protocol 负责交换状态事实，不负责传大文件，也不负责 TLS/HMAC。

它应该能跑在：

```text
heartbeat response
/sync/inventory response
future websocket
CloudKit
WebRTC data channel
LAN HTTP polling
any project-specific transport
```

### 8.2 Envelope

```swift
struct CanonicalStatusExchangeEnvelope: Codable, Equatable {
    let protocolVersion: String
    let senderNodeID: CanonicalNodeID
    let receiverNodeID: CanonicalNodeID?
    let sequence: UInt64
    let sentAt: CanonicalLogicalTime
    let deltas: [CanonicalStatusDelta]
    let acknowledgements: [CanonicalStatusAck]
    let requests: [CanonicalStatusRequest]
}

struct CanonicalStatusDelta: Codable, Equatable {
    let factID: CanonicalStatusFactID
    let objectID: CanonicalObjectID
    let fact: CanonicalStatusFact
    let replacesFactIDs: [CanonicalStatusFactID]
}

struct CanonicalStatusAck: Codable, Equatable {
    let ackedFactID: CanonicalStatusFactID
    let receiverNodeID: CanonicalNodeID
    let result: CanonicalStatusAckResult
    let observedAt: CanonicalLogicalTime
}

struct CanonicalStatusRequest: Codable, Equatable {
    let requestID: String
    let objectID: CanonicalObjectID?
    let domain: CanonicalStatusDomain?
    let kind: CanonicalStatusRequestKind
}
```

### 8.3 Delta examples

```text
recording A: metadataOnly observed on Mac
recording A: uploadNeeded on iPhone
recording A: uploadSession started
recording A: confirmedBytes = 3145728
recording A: finalizeProof accepted
recording A: peerVerified hash+size match
transcript A: generatedArtifactAvailable
note A: noteStatus changed
syncRequested: Mac wants iPhone to pull now
```

### 8.4 Ack examples

```text
I saw status fact X at sequence 241
I incorporated proof Y into my local truth engine
I rejected fact Z because stale/conflict/unsupported
I need full inventory because status proof is insufficient
```

### 8.5 Request examples

```text
send current status facts for object A
send audio proof for recording A
please run sync soon
my status facts may be stale; send inventory
```

---

## 9. File Kernel

### 9.1 职责

File Kernel 必须确保文件树和 manifest 的构建不会卡 UI。

必须拥有：

```text
file tree snapshot
manifest builder
metadata store abstraction
artifact store abstraction
checksum cache
content hash provider
root-bound write
atomic write
rollback
postcondition verification
crash recovery facts
bounded indexing
background scan/hash
```

### 9.2 No-freeze contract

File Kernel 必须保证：

```text
no full tree scan on MainActor
no full manifest build on MainActor
no full-file hash on MainActor
no repeated tree rebuild per UI access
no synchronous diagnostics/status JSONL write on MainActor hot path
cache hit skips hash
cache key is content-stable, not generatedAt-only
all expensive work has duration diagnostics
```

### 9.3 Interface sketch

```swift
protocol CanonicalFileTreeProvider {
    func snapshot(reason: CanonicalFileSnapshotReason) async throws -> CanonicalFileTreeSnapshot
}

protocol CanonicalManifestBuilder {
    func buildManifest(from snapshot: CanonicalFileTreeSnapshot) throws -> CanonicalManifest
}

protocol CanonicalChecksumCache {
    func lookup(_ key: CanonicalChecksumCacheKey) async -> CanonicalChecksumLookupResult
    func store(_ record: CanonicalChecksumCacheRecord) async throws
}

protocol CanonicalRootBoundWriter {
    func write(_ request: CanonicalRootBoundWriteRequest) async throws -> CanonicalRootBoundWriteResult
    func rollback(_ checkpoint: CanonicalRollbackCheckpoint) async throws
}
```

---

## 10. Cross-domain invariants

这些约束必须跨四域统一执行：

```text
Default/release = oldKernel unless explicitly overridden in debug/internal.
Legacy fallback retained until explicit retirement project.
No route/security bypass.
No production-root write without explicit gate.
No UI state without proof.
No status completion without peer proof.
No file tree/hash/index work on MainActor hot path.
No event callback executes heavyweight sync inline.
No retry/view refresh creates unrelated upload job.
No diagnostics leak full path/hash/content/secret.
```

---

## 11. Kernel switch ownership model

四域应统一受一个主开关控制：

```text
oldKernel
canonicalShadow
canonicalDecisionOnly
canonicalApplyNoAudio
canonicalFullSync
blocked
```

### Mode semantics

| Mode | Connection | Transfer | Sync | File |
|---|---|---|---|---|
| oldKernel | legacy connection owner | legacy transfer owner | legacy sync owner | legacy file path, canonical diagnostics off | 
| canonicalShadow | carrier may carry diagnostics only | no canonical transfer commit | status/diff shadow only | safe snapshots only |
| canonicalDecisionOnly | connection unchanged | no canonical transfer commit | canonical decision/status truth may evaluate | file facts read-only |
| canonicalApplyNoAudio | connection unchanged | audio transfer blocked | non-audio sync/apply/status allowed | root-bound non-audio writes gated |
| canonicalFullSync | canonical connection protocol over Rokurics adapter | canonical transfer protocol over Rokurics adapter | full status truth/exchange/diff/apply/read | file kernel runtime owner |
| blocked | legacy fallback | legacy fallback | legacy fallback | legacy fallback |

---

## 12. Diagnostics requirements

Diagnostics must answer three questions:

```text
Why is the app slow?
Why did status not converge?
Which proof supports each displayed state?
```

Minimum diagnostics:

### Performance

```text
readProjectionRebuildDurationMs
readProjectionCacheHit/Miss/RebuildCount
studyTreeRebuildDurationMs
fileTreeSnapshotDurationMs
manifestBuildDurationMs
checksumCacheHit/Miss/StaleCount
hashDurationMs
mainActorLongTaskDurationMs
routeDurationMs
diagnosticsWriteDurationMs
```

### State convergence

```text
statusFactProduced
statusDeltaSent
statusDeltaReceived
statusAckSent
statusAckReceived
statusFactRejected
statusProofExpired
syncRequestedHintAdvertised
syncRequestedHintConsumed
eventTriggerQueued
eventTriggerCoalesced
eventToSyncStartLatencyMs
peerProofUnavailable
finalizeProofAccepted
metadataOnlyRejectedAsAudioProof
completedLedgerRejectedAsPeerProof
```

### Redaction

Diagnostics must not include:

```text
absolute path
full hash
secret
full fingerprint
full metadata JSON
request/response body
raw audio bytes
full transcript/note/summary/provider response
```

---

## 13. Rokurics adapter mapping

| Canonical domain | Rokurics adapter |
|---|---|
| Connection Kernel | existing local HTTPS server/client, pairing, TLS, HMAC, nonce, body hash, RequestVerifier |
| Transfer Kernel | SecureMacUploadClient, RecordingUploadClient, SecureLocalHTTPSServer resumable upload routes |
| Sync Kernel | StudyLibrarySyncCoordinator, LocalNetworkSyncAppService, heartbeat/status envelopes, event queue, inventory/apply/read runtime |
| File Kernel | StudyLibraryStore, MacRecordingFileStore, AudioFileStore, checksum cache, manifest builders, root-bound apply ports |

Adapter rule:

```text
Portable kernel defines protocol and state machine.
Rokurics adapter supplies actual transport, storage, platform lifecycle and UI integration.
```

---

## 14. Roadmap: v9 four-domain kernel rebuild

### v9.0 — Kernel Contract Freeze

只定义四域协议和边界：

```text
CanonicalConnectionProtocol
CanonicalTransferProtocol
CanonicalSyncStatusTruthProtocol
CanonicalRealtimeStatusExchangeProtocol
CanonicalFileProtocol
Cross-domain invariants
Diagnostics taxonomy
```

不改 app 行为。

### v9.1 — File Kernel Runtime

先修不卡顿：

```text
file tree snapshot
manifest builder
checksum cache
content-stable read cache
background indexing
async diagnostics writer
MainActor long-task guard
```

验收：UI repeated access、Mac route inventory、manifest/hash/diagnostics 不再卡主线程。

### v9.2 — Connection Kernel Runtime

把连接语义纳入 canonical：

```text
peer liveness
heartbeat as carrier
syncRequested as protocol request
status exchange envelope carrier
connection diagnostics
```

Rokurics adapter 继续复用 local HTTPS/TLS/HMAC/RequestVerifier。

### v9.3 — Transfer Kernel Runtime

把上传抽成可复用协议：

```text
session
chunk
offset
status
resume
finalize proof
retry/backoff
idempotency
```

Rokurics adapter 继续复用已有安全上传路由。

### v9.4 — Sync State Truth Protocol

写状态真相层：

```text
CanonicalStatusFact
CanonicalStatusProof
CanonicalEffectiveSyncStatus
CanonicalStatusTruthEngine
CanonicalStatusReconciliation
```

所有 UI 状态必须从 EffectiveSyncStatus 来。

### v9.5 — Realtime Status Exchange Protocol

写状态交换层：

```text
CanonicalStatusExchangeEnvelope
CanonicalStatusDelta
CanonicalStatusAck
CanonicalStatusRequest
sequence / logical clock
stale / expire / conflict policy
```

不新增 Rokurics route，只通过 adapter 承载。

### v9.6 — Rokurics Integration Gate

四域全部接入主开关：

```text
oldKernel -> legacy all domains
canonicalShadow -> diagnostics only
canonicalDecisionOnly -> status/diff only
canonicalApplyNoAudio -> non-audio apply
canonicalFullSync -> connection/transfer/sync/file all canonical owners through adapters
```

fullSync 只有四域 gates 全绿才允许。

---

## 15. “完成”的定义

新内核完成必须同时满足：

```text
Connection Kernel owns peer liveness and status exchange carrier.
Transfer Kernel owns resumable transfer state machine and finalize proof.
Sync Kernel owns status truth, status exchange, diff/apply/read and event triggers.
File Kernel owns file tree, manifest, checksum and no-freeze runtime.
One kernel switch controls all four domains.
OldKernel can immediately switch back to legacy.
UI state comes only from EffectiveSyncStatus.
No MainActor heavy file/sync/status work.
No route/security bypass.
No fake completion without peer proof.
Diagnostics can explain latency and non-convergence.
```

如果任何一项缺失，不得宣称 canonical kernel 完成。

---

## 16. Prompt preamble for future Codex / Claude work

后续所有 prompt 建议以此开头：

```text
本项目的 canonical kernel 包含四个一等域：Connection、Transfer、Sync、File。

Connection 负责本地局域网 HTTPS carrier、身份、配对、heartbeat、syncRequested、peer liveness。
Transfer 负责文件传输协议、session、chunk、offset、断点续传、finalize proof、retry/backoff。
Sync 负责状态真相协议、实时状态交换协议、diff/LWW、apply plan、event-driven sync、read projection。
File 负责文件树、manifest、metadata store、checksum cache、root-bound write、atomic/rollback、off-main indexing 和 no-freeze guarantees。

任何只修改 SyncCore model / read projection / canary / evidence，
但不处理四域 owner、状态真相、实时交换、文件不卡顿的任务，
不得声称新内核完成。

Portable canonical protocol 不得写死 Rokurics local HTTPS/TLS/HMAC；
Rokurics 只能作为 adapter 实现这些协议。

默认/release 仍 oldKernel；legacy fallback 保留；
不得新增 route，不得绕过 RequestVerifier/TLS/HMAC/pinning/nonce/body hash；
不得把 metadataOnly/completed ledger/partial receive 当 peer proof；
不得在 MainActor hot path 做 file tree / manifest / hash / diagnostics IO。
```

---

## 17. Claude 审计建议关注点

给 Claude 审计时，应要求它重点判断：

1. 四域边界是否清晰。
2. 是否仍把 Connection / Transfer 视为 legacy 外围。
3. 状态真相是否有 proof，而不是 display string。
4. UI 是否只读 EffectiveSyncStatus。
5. Realtime Status Exchange 是否 transport-independent。
6. Rokurics adapter 是否仍保留 TLS/HMAC/RequestVerifier。
7. File Kernel 是否有 no-freeze 合同。
8. 所有 heavy path 是否 off-main / cached / bounded。
9. 诊断是否足以解释 9000ms 卡顿和状态不收敛。
10. “完成”是否同时覆盖 Connection、Transfer、Sync、File 四域。

---

## 18. Final principle

```text
新内核不是“同步模型”。
新内核是一个本地协作内核。

它必须同时保证：
连接可信，传输可恢复，状态有证明，同步能实时收敛，文件树不卡顿。
```
