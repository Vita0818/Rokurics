# Rokurics Canonical Sync Kernel On-Device Trial Runbook v8.63

Status: final gate and runbook for a Debug-only real-device `canonicalFullSync` trial. This runbook does not authorize release/default canonical, legacy retirement, route/security changes, schema migration, physical delete, tombstone GC, or business-logic changes.

No legacy retirement. Do not delete or disable legacy planner, store, routes, read/write paths, fallback, retry drainer, Mac pending sync, or legacy-readable files. `retirementExecutionPerformed=false`.

## Final Gate

`CanonicalSyncKernelCompletionScorecard.v863(...)` and `CanonicalSyncKernelManualSwitchGate` must pass before Phase 6. `canonicalFullSync` is blocked unless all of these are true:

- v8.58 recording metadata real apply ports and read-side seams are ready.
- v8.59 audio commit executor is ready.
- v8.60 inventory/existence gate is ready.
- v8.61 production file port true write is gated.
- v8.62 switch-back proof driver exists and passes on a clone root.
- diagnostics are redacted.
- legacy fallback is available.
- default and release resolve to `oldKernel`.
- owner confirmation and manual backup acknowledgement are present.
- older domain-specific debug switches only restrict or emit diagnostics; they must not enable canonical behavior beyond the master switch.
- iPhone and Mac status cards show the effective source from the resolved master switch, not the requested mode.

## Diagnostics Grep List

Copy redacted jsonl/log diagnostics into a review folder and run:

```sh
rg 'canonicalInventoryRuntime|canonicalSyncRuntime|canonicalExistence|canonicalApplyRuntime|canonicalAudioUploadRuntime|canonicalReadRuntime|canonicalKernelSwitch|Divergent|FreezeViolation|RollbackFailed|ConflictBlocked|ExistingDifferentAudioBlocked|SecurityFailure' .
```

Required event families:

```text
canonicalInventoryRuntime*
canonicalSyncRuntime*
canonicalExistence*
canonicalApplyRuntime*
canonicalAudioUploadRuntime*
canonicalReadRuntime*
canonicalKernelSwitch*
Divergent
FreezeViolation
RollbackFailed
ConflictBlocked
ExistingDifferentAudioBlocked
SecurityFailure
```

## Stop Conditions

Stop immediately, switch both devices back to `oldKernel`, and preserve evidence if any of these occur:

- `Divergent`
- `FreezeViolation`
- `RollbackFailed`
- `SecurityFailure`
- `ExistingDifferentAudioBlocked`
- unexplained `ConflictBlocked` on the object under trial
- release/default resolves to anything except `oldKernel`
- any oldKernel switch-back requires migration, cleanup, deletion, or manual data repair
- diagnostics contain absolute paths, full hashes, secrets, full fingerprints, request/response bodies, provider output, generated content payloads, transcripts, notes, summaries, or audio bytes
- Mac marks audio available from metadata-only existence before finalize proof
- canonical upload uses any route other than the existing secure upload/inventory routes or bypasses TLS/HMAC/nonce/body-hash verification

## Emergency OldKernel Switch-Back Path

1. Set iPhone Settings -> Debug -> Sync Kernel to `oldKernel`.
2. Set Mac Settings -> Debug -> Sync Kernel to `oldKernel`.
3. Restart the Mac receiver if it was already running.
4. Run one oldKernel manual sync.
5. Verify legacy-readable state, upload fallback, and guarded read fallback.
6. Export redacted diagnostics and mark the trial stopped.

Expected: switch-back is a mode switch only. It must not require data migration, staging cleanup, physical delete, tombstone GC, or manual data repair.

## Trial Phases

### 1. Backup

Back up iPhone app data and Mac app data before changing the switch. Store backups outside production app roots. Record `manualBackupAcknowledged=true`.

### 2. oldKernel baseline

Set both devices to `oldKernel`. Run one sync with unchanged data. Export baseline counts and diagnostics. Expected: legacy owns read/write/apply/upload; no canonical owner commits.

### 3. diagnosticsOnly

Set both devices to `diagnosticsOnly`. Run one sync. Expected: diagnostics only; no write, no upload job, no canonical read serving, fallback retained.

### 4. canonicalShadow

Set both devices to `canonicalShadow`. Run one sync. Expected: noCommit/shadow comparison only; legacy executes; any `Divergent` stops the trial.

### 5. canonicalDecisionOnly

Set both devices to `canonicalDecisionOnly`. Run one sync. Expected: canonical may own decision evidence only; apply/upload/read remain legacy.

### 6. canonicalApplyNoAudio

Set both devices to `canonicalApplyNoAudio`. Use non-audio test data. Expected: guarded non-audio apply/existence can run; audio upload remains disabled; read serving remains legacy.

### 7. canonicalFullSync

Proceed only after the final gate passes, owner confirmation is recorded, and backup acknowledgement is present. Set both devices to `canonicalFullSync`. Run one bounded sync first, not an irreplaceable production recording.

Expected: decision, non-audio apply, existence, audio upload, and guarded read use canonical runtimes only with legacy fallback; release/default remains `oldKernel`; no legacy retirement.

### 8. Recording Metadata Modification

Modify metadata for an existing recording on iPhone. Run sync. Expected: recording metadata real apply/read-side diagnostics are redacted and equivalent; legacy-readable state remains valid.

### 9. New Recording Creation

Create a new iPhone recording. Do not manually copy audio to Mac. Expected: iPhone has local audio fact; Mac initially has no proven audio for the object.

### 10. Mac MetadataOnly Existence

Run sync after the new recording exists. Verify Mac consumes `manifest.recordings` as metadata-only existence. Expected: `audioAvailable=false`; no audio hash, byte size, or audio path is asserted without proof.

### 11. Audio Upload Finalize

Allow upload through existing secure transport. Verify start/status/chunk/finalize diagnostics. Expected: Mac marks audio available only after finalize hash and byte-size proof; different existing audio is not overwritten.

### 12. generatedArtifacts Read/Apply

Exercise generated artifact metadata/read/apply through bounded test data. Expected: generated content, provider output, full paths, and full hashes stay out of diagnostics; legacy fallback remains available.

### 13. Tombstone/Conflict No Destructive Test

Exercise tombstone/conflict diagnostics without physical delete, permanent delete, tombstone GC, restore, or auto conflict resolution. Expected: conflict/tombstone state is report/guarded only and non-destructive.

### 14. Switch Back oldKernel

Use the Emergency OldKernel Switch-Back Path. Run oldKernel sync and verify current state remains readable.

### 15. Compare State

Compare oldKernel-readable state before and after `canonicalFullSync`. Expected: canonical writes are legacy-readable or dual-write-compatible; unknown canonical fields are optional and ignored by legacy.

### 16. Export jsonl

Export redacted jsonl/log evidence from both devices. Include mode transitions, scorecard, manual gate result, object/cache/plan/apply/upload/read counts, switch-back proof, redaction proof, blocker report, and grep summary.

### 17. Stop Conditions

Apply the Stop Conditions section throughout every phase. `Divergent`, `FreezeViolation`, `RollbackFailed`, `SecurityFailure`, or `ExistingDifferentAudioBlocked` means stop immediately and switch back to `oldKernel`.

## Evidence Exclusions

Do not include raw app data, user content, absolute paths, full hashes, secrets, full fingerprints, request/response bodies, provider output, transcripts, notes, summaries, generated artifact content, or audio bytes.
