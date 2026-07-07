# Rokurics Canonical Sync Kernel Manual Switch Runbook v8.45

Status: sync-kernel code-complete wiring for manual trial, plus completion gate and runbook. No release default change.

No legacy retirement. Do not delete legacy planner, store, route, read/write path, fallback, retry drainer, Mac pending sync, or any legacy-readable file. `retirementExecutionPerformed=false` for this runbook and every v8.45 report.

## v8.73 Final App-State Trial Sequence - 2026-06-13

v8.73 is the final app-state readiness gate for the Claude diagnosis. `READY_FOR_REAL_DEVICE_APP_TRIAL` means the code-level read cache, Mac inventory, heartbeat hint, event-driven trigger, status convergence, safety gates, build/test and runbook checks are ready for a paired-device debug/internal trial. It does not mean paired-device validation has already passed. Without real iPhone/Mac redacted jsonl, report `REAL_DEVICE_EVIDENCE_RESULT=not run; no real-device evidence produced.`

Do not start Phase 6 unless `CanonicalRealDeviceTrialReadinessGate.v873(...)` reports `READY_FOR_REAL_DEVICE_APP_TRIAL`. If the result is `PARTIAL_WITH_BLOCKERS`, `NOT_READY` or `UNSAFE_TO_TRY_ON_DEVICE`, stop and fix the blocker first.

### Phase 0. backup / test device

1. Back up iPhone app data.
2. Back up Mac app data.
3. Confirm both apps are debug/internal builds.
4. Confirm default mode is `oldKernel` on both ends.
5. Confirm the Mac receiver starts normally.
6. Confirm pairing and connection remain legacy-secure.

### Phase 1. oldKernel baseline

1. Select `oldKernel` on both ends.
2. Start heartbeat and confirm it remains liveness/status only.
3. Record baseline UI latency and inventory/sync latency.
4. Run manual sync.
5. Verify oldKernel sync/read/upload still works.

### Phase 2. switch-back proof

1. Run the “新旧内核切回证明” debug action.
2. Confirm proof uses a clone/test root, not production root.
3. Export `canonical-switch-back-proof.jsonl`.
4. Stop if proof fails, redaction fails, or root safety rejects the clone.

### Phase 3. canonicalShadow

1. Switch both ends to `canonicalShadow`.
2. Confirm no write, no upload, no canonical read serving.
3. Export diagnostics.
4. Stop on divergence, security issue, or diagnostics leak.

### Phase 4. canonicalDecisionOnly

1. Switch both ends to `canonicalDecisionOnly`.
2. Confirm decision diagnostics only.
3. Confirm no apply, no upload, no canonical read serving.
4. Export diagnostics.

### Phase 5. canonicalApplyNoAudio

1. Switch both ends to `canonicalApplyNoAudio`.
2. Change recording title.
3. Change library metadata.
4. Confirm non-audio apply path works.
5. Confirm no canonical audio upload.
6. Export diagnostics.

### Phase 6. canonicalFullSync

1. Confirm warning, owner approval and manual confirmation.
2. Switch both ends to `canonicalFullSync`.
3. Verify read cache metrics show repeated cache hits and avoided rebuilds.
4. Verify Mac inventory metrics show off-main build and one canonical build per request.
5. Switch back to `oldKernel` once and verify oldKernel skips canonical build.
6. Create a new recording.
7. Stop and save the recording.
8. Confirm event-driven sync is queued and the heartbeat callback does not run heavy sync.
9. Confirm Mac receives metadataOnly quickly and reports `audioAvailable=false`.
10. Confirm audio upload candidate/finalize uses existing secure route.
11. Confirm finalize proof drives status convergence.
12. Rename the recording and confirm metadata sync.
13. Trigger generated artifact availability if possible and confirm projection refresh.
14. Switch back `oldKernel`.
15. Confirm legacy reads the same state without migration or cleanup.
16. Switch `canonicalFullSync` again.
17. Confirm canonical reads the same state.

Required redacted jsonl/diagnostics:

- `connection-diagnostics.jsonl`
- `canonical-shadow.jsonl`
- `canonical-switch-back-proof.jsonl`
- sync event diagnostics
- read cache diagnostics
- Mac inventory diagnostics
- upload/finalize diagnostics

Success criteria:

- UI no longer freezes on repeated read access.
- repeated read cache hits are visible.
- Mac inventory oldKernel skips canonical build.
- canonicalFullSync Mac inventory builds canonical facts once per request.
- Mac manual sync causes iPhone immediate sync instead of waiting for the 240 second fallback.
- New recording queues immediate sync.
- Metadata/status/finalize changes queue convergence refresh.
- View refresh does not create upload jobs.
- Retry drainer does not create unrelated fresh jobs.
- No route/security change.
- No divergence is served as canonical.
- Switch back to oldKernel works.

Stop conditions:

- Divergent
- FreezeViolation
- RollbackFailed
- SecurityFailure
- ExistingDifferentAudioBlocked
- metadataOnly treated as audioAvailable
- completed ledger alone treated as proof/no-op
- partial receive treated as audioAvailable
- unexpected productionRoot write
- route/security changed
- RequestVerifier bypass/failure
- legacy unreadable canonical write
- audio overwrite risk
- unredacted path/hash/content
- UI freeze/hang during read or inventory
- upload retry storm
- sync event storm
- heartbeat callback heavy sync
- Mac reverse connection attempt
- switch back oldKernel fails

## v8.68 Final T7 Sequence - 2026-06-12

v8.68 is the code-completion handoff for a real paired-device trial. `READY_FOR_REAL_DEVICE_CANONICAL_SWITCH` means the code is ready to install and test; it is not a claim that paired-device validation has already passed. Without real iPhone/Mac redacted jsonl, report `realDeviceEvidencePresent=false`.

Final sequence:

1. Backup device/data.
2. Confirm default `oldKernel`.
3. Build/install iPhone app.
4. Build/install Mac app.
5. Start Mac receiver.
6. Verify pairing/connection remains legacy-secure.
7. Run Debug switch-back proof on clone.
8. Export redacted proof jsonl.
9. Switch `oldKernel` baseline.
10. Run sync / inventory baseline.
11. Switch `canonicalShadow`.
12. Verify no write/no upload/no canonical read serving.
13. Switch `canonicalDecisionOnly`.
14. Verify decision diagnostics only; no apply/upload.
15. Switch `canonicalApplyNoAudio`.
16. Verify non-audio metadata apply only; no audio upload.
17. Switch `canonicalFullSync` with confirmation.
18. Test recording metadata write/read.
19. Test library metadata write/read.
20. Test generated artifact availability/read.
21. Test tombstone/conflict safe marker only; no destructive delete.
22. Test new recording metadataOnly existence.
23. Test audio upload finalize.
24. Test read projection.
25. Switch back `oldKernel`.
26. Verify legacy reads same state.
27. Export diagnostics jsonl.
28. Stop if any stop condition appears.

Stop conditions:

- Divergent
- FreezeViolation
- RollbackFailed
- SecurityFailure
- ExistingDifferentAudioBlocked
- metadataOnly treated as audioAvailable
- completed ledger alone treated as no-op
- unexpected productionRoot write
- route/security changed
- RequestVerifier failure/bypass
- legacy unreadable canonical write
- audio overwrite risk
- unredacted path/hash/content
- UI freeze/hang during inventory
- upload retry storm
- switch back oldKernel fails

Do not collect:

- secrets
- full hashes
- full fingerprints
- absolute paths
- full metadata JSON
- full transcript/note/summary/provider response
- raw audio bytes
- request/response bodies

The visible Settings switch must remain a single `内核模式` selector with five choices: `oldKernel`, `canonicalShadow`, `canonicalDecisionOnly`, `canonicalApplyNoAudio`, `canonicalFullSync`. Older domain-specific switches are advanced restrictive diagnostics only and cannot grant authority beyond this selector. Path B transport keeps the existing legacy TLS/HMAC/upload route and `RequestVerifier`.

## v8.67 Addendum - 2026-06-12

v8.67 adds the app Debug Settings entry for T6. iPhone and Mac `Debug · 同步内核` now show “运行新旧内核切回证明”. This button is a pre-device-trial proof driver: it reads the current app data root only as a source, creates a fresh system-temp/test clone, validates the clone with `CanonicalSwitchBackRootSafetyGuard`, then calls the existing realistic-root harness.

Required operator expectations:

1. Run this button before attempting `canonicalFullSync` on real paired devices.
2. Confirm the UI summary reports `status=passed`, clone root safety accepted, `proofRanOnProductionRoot=false`, realistic-root proof complete, evidence redacted and `realDeviceEvidence=false`.
3. Review the UI-reported `temp/CanonicalSwitchBackProofDebugRunner/<redacted-token>/Diagnostics/canonical-switch-back-proof.jsonl` evidence path. It must contain only redacted root tokens, counts, blocker enums, `evidenceKind=realisticRoot`, `realDeviceEvidencePresent=false` and relative evidence path.
4. Treat any failed/blocked summary as a stop condition; do not switch to `canonicalFullSync` while blockers remain.
5. Do not treat this proof as paired-device evidence. It proves realistic-root code-level reversibility only.

The driver must not write business data in the production root, must not switch the master mode, must not trigger sync/upload or real network requests, and must not run physical delete, permanent delete, tombstone GC, restore/undelete, overwrite of existing different audio, route/security changes or legacy fallback removal. On Mac it must not restart `SecureLocalHTTPSServer`, modify `/sync/inventory`, receiver security, `receive.json`, audio inbox, pending sync, transcription or note generation.

Stop if the JSONL or UI summary contains an absolute path, full hash, full metadata JSON, transcript/note/summary/provider response, request/response body, secret/API key, full fingerprint, delete target path, full local audio path or raw audio bytes. Stop if `evidenceKind` is reported as `realDevice` without an actual paired iPhone/Mac evidence package.

Next step remains v8.68/T7: single master switch UI consolidation and final code-completion gate. v8.67 does not authorize release default canonical or legacy retirement.

## v8.62 Addendum - 2026-06-12

v8.62 adds the Debug/test callable realistic-root switch-back proof driver. The driver reads the current app data root as a source, creates a unique temp/test clone, runs `CanonicalSwitchBackRealisticRootHarness.runKernelSwitchBackProof()` only on that clone, exports `CanonicalSwitchBackEvidencePackage`, and feeds the result into `CanonicalSyncKernelCompletionScorecard.v862(...)`.

Required driver flow:

1. Pass the current iPhone `Documents/Rokurics` root or Mac Application Support root as `appDataRootURL`.
2. Do not pass production Documents/Application Support paths as `cloneRootURL`; omit it or pass a fresh temp/test path.
3. Confirm `CanonicalSwitchBackRootSafetyGuard` accepts the clone root before proof execution.
4. Run the driver only from a Debug build or test harness.
5. Review `proofRanOnProductionRoot=false`, `cloneAccepted=true`, `proofComplete=true`, and `evidenceRedacted=true`.
6. Treat `realDeviceProofStatus=needsRealDeviceEvidence` as expected until paired iPhone/Mac jsonl exists.
7. If `CanonicalSyncKernelCompletionScorecard.v862(...)` reports `realisticRootSwitchBackProofMissing`, `diagnosticsNotRedacted`, or any blocked/unsafe status, do not proceed to manual `canonicalFullSync`.

Driver stop conditions:

- source root is missing or is not a directory
- clone root is production-like, home, repo root, Documents/App Support app root, or unmarked non-temp root
- clone destination already exists
- any domain matrix proof fails
- crash before checkpoint or crash after write before postcondition does not recover or fail closed
- audio interrupted/finalized state is not legacy/canonical readable
- evidence contains absolute paths, full hashes, full metadata/content, request/response body, secret, fingerprint, provider output, delete target path, or raw audio bytes

The driver must not write the production root, must not delete real files, and must not run permanent delete or tombstone GC. It may create and later allow manual cleanup of a fresh temp/test clone only.

## v8.57 Addendum - 2026-06-11

v8.57 adds a code-level realistic-root switch-back proof before any real-device trial. Operators must first run the proof on a backup clone or temp realistic fixture, never on production app data. The required sequence is oldKernel baseline -> canonicalShadow -> canonicalDecisionOnly -> canonicalApplyNoAudio -> canonicalFullSync -> switch back oldKernel -> switch again canonicalFullSync.

Backup and clone requirements:

- Create a backup or test clone outside the production app container.
- Confirm `CanonicalSwitchBackRootSafetyGuard` accepts the root and reports only a redacted root token.
- Do not run destructive/crash harnesses on home, repo root, Documents/App Support production path, app container production root or any unmarked non-temp root.
- Keep the original production library untouched until paired-device manual trial is explicitly approved.

Mode trial expectations:

- `oldKernel` baseline reads all legacy state and remains default/release.
- `canonicalShadow` compares projections only; no write, upload or canonical read serving.
- `canonicalDecisionOnly` evaluates decisions only; no apply, upload or canonical read serving.
- `canonicalApplyNoAudio` may apply safe non-audio domains in the test root; canonical audio upload remains blocked.
- `canonicalFullSync` requires DEBUG/internal, owner approval, manual confirmation, fallback retained and v8.57 proof passing.
- Switching back to `oldKernel` requires no migration, repair, cleanup, physical delete or manual data rewrite.

Additional grep events:

```text
canonicalSwitchBack*
canonicalLegacyCompatibility*
canonicalCrashRecovery*
canonicalReadRuntime*
canonicalAudioUpload*
Divergent
FreezeViolation
RollbackFailed
ExistingDifferentAudioBlocked
SecurityFailure
```

Stop immediately and switch back to `oldKernel` if any of these occur:

- any legacy unreadable state
- any canonical-only disk blocker
- any unredacted diagnostics
- any route/security bypass
- any audio overwrite
- any physical delete
- any permanent delete or tombstone GC
- any rollback failure
- any divergent read while canonical read is served

Evidence package requirements:

- Export `CanonicalSwitchBackEvidencePackage` or equivalent.
- Include mode transitions, domain matrix, crash recovery, compatibility result, switch-back result, fallback availability, diagnostics redaction proof, blocker list and test root safety proof.
- Distinguish synthetic unit proof, realistic-root proof, real-device proof and missing proof.
- If no paired-device jsonl exists, mark real-device proof as missing or `needsRealDeviceEvidence`.

Do not collect or paste secrets, full hashes, full fingerprints, absolute paths, full metadata JSON, full transcript/note/summary/provider response, raw audio bytes, delete target path, or request/response bodies.

## v8.56 Addendum - 2026-06-11

v8.56 consolidates the P0-P2 runtime pieces behind the unified `CanonicalKernelSwitch`. Manual trial operators should treat `Debug · 同步内核` as the only app-facing switch. Older libraryMetadata/debug/canary/pilot controls are advanced restrictive inputs only; they must not override the master switch, must not write production root under `oldKernel`, and must not enable canonical apply/upload/read outside the effective master mode.

Mode expectations:

- `oldKernel`: all canonical owners disabled; legacy inventory, decision, apply, upload and read stay authoritative.
- `diagnosticsOnly`: diagnostics only; no write, no upload, no canonical read serving, no duplicate suppression.
- `canonicalShadow`: shadow/noCommit/parallel comparison only; legacy execution remains authoritative.
- `canonicalDecisionOnly`: canonical decision may be evaluated where gates allow; legacy apply/upload/read remain authoritative.
- `canonicalApplyNoAudio`: canonical decision and non-audio apply may run where gates allow; canonical audio upload remains disabled.
- `canonicalFullSync`: requires DEBUG/internal, manual confirmation, owner approval, legacy fallback, legacy read/write/upload fallback, runtime/domain readiness, diagnostics redaction, route/security unchanged, safe production-root config and switch-back preconditions.

Stop before Phase 6 if any `canonicalKernelSwitch*` diagnostic reports a blocker, especially release/default canonical, missing confirmation, missing owner approval, missing readiness, unsafe diagnostics, route/security risk, contradictory config, production-root unsafe config, unresolved conflict, switch-back hard blocker or canonical-only disk-format blocker.

v8.56 switch-back statement: switching to `oldKernel` disables canonical owners immediately at behavior/config level. It is not yet a realistic-library proof. v8.57/P3-2 must run a backed-up realistic library root through oldKernel -> canonicalFullSync -> oldKernel and prove oldKernel reads without migration, cleanup, deletion or manual data repair.

## v8.46 Addendum - 2026-06-11

v8.46 updates the completion bar without changing the runbook authorization. iPhone inventory runtime now has a background URL/file IO build path, real mainActor attempt/block telemetry, metadata load duration evidence, and same-syncRunID snapshot reuse. Mac `manifest.recordings` can write canonical metadata-only existence only when the store is explicitly configured with an existence apply runtime and port; default store behavior is still no-op.

Do not treat v8.46 as real-device completion. Mac inventory still reports a real mainActor blocker because `SecureLocalHTTPSServer.makeLocalNetworkSyncInventory` remains `@MainActor`. During manual trial, stop and review if `canonicalInventoryRuntime*` diagnostics show `mainActorBlocked=true`, `mainActorHashBlockedCount > 0`, or `mainActorScanBlockedCount > 0` on the Mac side. These values are truthful blocker evidence, not a passing off-main signal.

Required v8.46 evidence additions:

- iPhone `mainActorHashAttemptCount=0` and `mainActorScanAttemptCount=0` for background inventory builds.
- iPhone duplicate build reuse evidence for the same `syncRunID`.
- Mac explicit `manifest.recordings` metadata-only ledger apply evidence with `audioAvailable=false`.
- Mac default store no-ledger-write evidence.
- Mac inventory mainActor blocker count reviewed and either fixed in a later build or explicitly accepted as a manual-trial blocker.

## Purpose

This runbook turns the v8.37-v8.44 canonical sync kernel work into an end-to-end manual switch trial. The trial may generate real-device evidence for a future audit. It does not authorize release default canonical, schema migration, physical move/delete, or legacy retirement.

## Required Evidence Package

Use `CanonicalSyncKernelEvidenceExporter` or equivalent redacted manual bundle. Include:

- mode transitions
- object counts
- cache counts
- canonical plan used / legacy fallback / blocked counts
- apply success / failure counts
- upload success / failure counts
- read divergence counts
- switch-back proof summary
- redaction proof

Exclude:

- absolute paths
- full hashes
- secrets, tokens, certificate private keys, full fingerprints
- request/response bodies
- full transcript, note, summary, provider output, or generated content
- audio bytes

## Required Grep Events

Collect redacted diagnostics for these event families:

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
```

Suggested local grep after copying diagnostics into a review folder:

```sh
rg 'canonicalInventoryRuntime|canonicalSyncRuntime|canonicalExistence|canonicalApplyRuntime|canonicalAudioUploadRuntime|canonicalReadRuntime|canonicalKernelSwitch|Divergent|FreezeViolation|RollbackFailed|ConflictBlocked|ExistingDifferentAudioBlocked' .
```

## Stop Conditions

Stop immediately and switch back to `oldKernel` if any of these occur:

- `Divergent` event not already explained by an allowed test-only divergent mode.
- `FreezeViolation`.
- `RollbackFailed`.
- `ConflictBlocked` on the object under trial.
- `ExistingDifferentAudioBlocked`.
- any security route failure, route mismatch, TLS/HMAC/nonce/body-hash verification failure, or RequestVerifier failure.
- diagnostics show an absolute path, full hash, secret, full fingerprint, request/response body, content payload, provider output, or audio bytes.
- Mac receives metadata-only existence but marks audio available before finalize proof.
- canonical upload bypasses existing secure upload routes.
- release/default resolves to anything except `oldKernel`.
- oldKernel switch-back requires migration, cleanup, deletion, or manual data repair.

## Phases

### 0. Backup

1. Back up iPhone app data and Mac app data before changing the debug switch.
2. Record `manualBackupAcknowledged=true` in the manual audit notes.
3. Confirm the backup copy is outside the app production root.

Gate expectation: `CanonicalSyncKernelManualSwitchGate` must block until backup acknowledgement is true.

### 1. oldKernel baseline diagnostics

1. Set both devices to `oldKernel`.
2. Run one manual sync with unchanged data.
3. Export baseline counts and diagnostics.

Expected:

- default mode is `oldKernel`
- release mode is `oldKernel`
- no canonical owner commits
- legacy-readable state unchanged

### 2. diagnosticsOnly

1. Switch both devices to `diagnosticsOnly`.
2. Run one manual sync.
3. Collect inventory/sync/apply/existence/audio diagnostics.

Expected:

- no commit
- no upload job
- no canonical read serving
- legacy fallback remains available

### 3. canonicalShadow

1. Switch both devices to `canonicalShadow`.
2. Run one manual sync.
3. Collect canonical plan/projection and read parallel comparison.

Expected:

- canonical evaluates shadow/noCommit only
- legacy executes
- `Divergent` count is zero or the trial stops

### 4. canonicalDecisionOnly

1. Switch both devices to `canonicalDecisionOnly`.
2. Run one manual sync on stable metadata.
3. Compare canonical plan used/fallback/blocked counts.

Expected:

- canonical may own decision only
- apply/upload/read remain legacy
- fallback counts are captured and explained

### 5. canonicalApplyNoAudio

1. Switch both devices to `canonicalApplyNoAudio`.
2. Use non-audio test data only.
3. Verify recording metadata, library metadata, generated artifact metadata, tombstone/conflict, and recording existence apply diagnostics.

Expected:

- non-audio apply can commit only through guarded runtime
- audio upload remains legacy/disabled
- read serving remains legacy
- rollback and postcondition evidence are present

### 6. canonicalFullSync on test data

1. Switch both devices to `canonicalFullSync` only after owner approval and manual confirmation.
2. Use bounded test data first, not an irreplaceable production recording.
3. Run sync and export evidence.

Expected:

- sync/apply/existence/audio/read are guarded with fallback
- no release/default behavior change
- no legacy retirement

### 7. switch back oldKernel

1. Switch both devices back to `oldKernel`.
2. Run manual sync.
3. Record switch-back transition in evidence.

Expected:

- no migration
- no cleanup
- no deletion
- oldKernel reads current data

### 8. compare legacy-readable state

1. Compare oldKernel-readable state before and after canonicalFullSync.
2. Verify canonical writes were legacy-readable or dual-write-compatible.
3. Verify unknown canonical fields are optional and ignored by legacy.

Expected:

- switch-back proof remains valid
- `retirementExecutionPerformed=false`

### 9. canonicalFullSync on paired devices

1. Reconfirm backup and owner approval.
2. Switch both paired real devices to `canonicalFullSync`.
3. Run one manual paired-device sync.

Expected:

- real-device evidence starts here
- all diagnostics remain redacted
- any blocker stops the run

### 10. create new iPhone recording

1. Create a new iPhone recording.
2. Let metadata enter the learning library.
3. Do not manually copy audio to Mac.

Expected:

- iPhone records local audio fact
- Mac initially has no proven audio for the new object

### 11. verify Mac metadata-only existence

1. Run sync.
2. Verify Mac consumes `manifest.recordings`.
3. Confirm Mac records metadata-only existence in canonical existence diagnostics.

Expected:

- Mac peer existence is present
- `audioAvailable=false`
- no hash, byte size, or audio path is reported without real audio proof

### 12. verify upload candidate

1. Run iPhone sync after Mac metadata-only existence is visible.
2. Inspect `canonicalExistence*` and upload candidate diagnostics.

Expected:

- peer metadataOnly becomes upload candidate
- peerUnknown remains deferred
- same hash + same byte size is the only audio no-op
- completed ledger alone is not no-op proof

### 13. verify Mac receives audio

1. Allow upload through existing secure transport.
2. Verify resumable start/status/chunk/finalize diagnostics.
3. Confirm Mac final audio appears only after finalize hash and byte-size proof.

Expected:

- no new route
- no TLS/HMAC/nonce/body-hash bypass
- no overwrite of different existing audio
- upload success/failure counts exported
- existing secure routes only; no new route appears in evidence

### 14. verify read projection

1. Run guarded read evaluation.
2. Verify `canonicalReadRuntime*` diagnostics.
3. Compare canonical and legacy projections.

Expected:

- divergence count zero
- legacy fallback still available
- read projection contains no paths, full hashes, content payloads, or audio bytes

### 15. monitor divergences

1. Keep both devices paired.
2. Run repeated sync/read cycles across unchanged data and one metadata edit.
3. Collect all required grep events.

Expected:

- no unexplained `Divergent`
- no `FreezeViolation`
- no `RollbackFailed`
- no `ConflictBlocked`
- no `ExistingDifferentAudioBlocked`
- fallback counts are bounded and explained

### 16. stop conditions

Apply the Stop Conditions section above. If any condition occurs, stop the trial and go to Phase 17.

### 17. rollback/switch-back procedure

1. Switch iPhone to `oldKernel`.
2. Switch Mac to `oldKernel`.
3. Restart Mac receiver if it was already running.
4. Run oldKernel manual sync.
5. Verify legacy-readable state and upload/read fallback.
6. Preserve the evidence package for audit.

Expected:

- rollback is a mode switch, not data migration
- no production data is deleted
- no staging cleanup is required to make oldKernel read

### 18. evidence package for Claude/manual audit

Submit a redacted package with:

- scorecard status
- domain readiness matrix
- manual switch gate result
- mode transition list
- required grep event summary
- object/cache/plan/apply/upload/read counts
- switch-back proof
- redaction proof
- blocker report
- statement: `retirementExecutionPerformed=false`

Do not include raw app data, user content, full paths, full hashes, secrets, full fingerprints, request/response bodies, provider output, or audio bytes.
