# Rokurics Long Recording Test Plan

1636

This plan is for local, user-driven validation of long recordings. It does not require API keys, shared secrets, or private transcript contents to be written into reports.

## Canonical v8.73 Final App-State Readiness Checks

Purpose:

- Validate that a long-recording paired-device trial starts only after the final app-state readiness gate reports code-level readiness, and that real-device evidence is not confused with local build/test results.

Checks:

- Confirm `CanonicalRealDeviceTrialReadinessGate.v873(...)` reports `READY_FOR_REAL_DEVICE_APP_TRIAL` before switching both ends to `canonicalFullSync`.
- If the gate reports `PARTIAL_WITH_BLOCKERS`, `NOT_READY` or `UNSAFE_TO_TRY_ON_DEVICE`, do not run a long-recording fullSync trial; fix the reported blocker first.
- Start from backed-up test devices and `oldKernel` baseline; confirm default/release oldKernel, Mac receiver start, legacy-secure pairing and oldKernel manual sync.
- Run the switch-back proof on a clone/test root and export redacted `canonical-switch-back-proof.jsonl`; do not treat that proof as paired-device evidence.
- Move through `canonicalShadow`, `canonicalDecisionOnly` and `canonicalApplyNoAudio` before `canonicalFullSync`; do not skip directly to fullSync.
- In `canonicalFullSync`, confirm read cache hit/avoided-rebuild diagnostics, Mac inventory off-main/one-build-per-request diagnostics, and oldKernel skipped canonical build after switching back.
- Create or stop/save a new long recording and confirm event-driven sync is queued without waiting for the 240 second fallback; heartbeat must remain liveness/status/hint only.
- Confirm Mac metadataOnly existence appears quickly with `audioAvailable=false`, then confirm upload candidate/finalize uses the existing secure start/status/chunk/finalize routes.
- Confirm upload, receive, transcription and note status changes refresh status projection/convergence without rerunning AI work or creating upload jobs from view refresh.
- Confirm retry drainer resumes only existing eligible jobs and does not create unrelated fresh jobs or a retry storm.
- Collect redacted connection, sync event, read cache, Mac inventory and upload/finalize diagnostics. Do not include secrets, full hashes, full fingerprints, absolute paths, full metadata JSON, full transcript/note/summary/provider response, raw audio bytes or request/response bodies.
- Stop on Divergent, FreezeViolation, RollbackFailed, SecurityFailure, ExistingDifferentAudioBlocked, metadataOnly-as-audioAvailable, completed-ledger-alone proof, partial receive as audioAvailable, route/security change, RequestVerifier bypass, UI freeze, upload retry storm, sync event storm, heartbeat heavy sync, Mac reverse connection, or oldKernel switch-back failure.
- If no paired iPhone/Mac redacted jsonl is produced, report `REAL_DEVICE_EVIDENCE_RESULT=not run; no real-device evidence produced.`

## Canonical v8.72 Event-Driven Sync Trigger Checks

Purpose:

- Validate that new long recordings and later metadata/status changes enter the existing sync convergence path promptly without turning heartbeat into sync or changing upload routes.

Checks:

- Start from default/release `oldKernel`; confirm 3 second heartbeat remains status/liveness only and the 240 second periodic sync remains fallback.
- Stop/save a new recording and confirm `recordingCreated` queues an immediate sync tick through the unified event queue instead of waiting for the periodic timer.
- Edit recording title, tags or study/folder filing several times quickly and confirm repeated metadata events coalesce into one queued tick.
- Change study folder/item metadata, generated artifact availability or tombstone/conflict marker and confirm a queued sync/status refresh appears without direct heavy sync in the callback.
- Finalize an upload and confirm finalize proof queues status convergence; metadataOnly, completed ledger alone and partial receive must still not be displayed as audio proof.
- On Mac, receive/finalize audio or complete/fail transcription/note generation and confirm Mac sets existing `syncRequested` hint or refreshes local projection; Mac must not connect back to iPhone.
- Confirm status refresh does not rerun transcription or note generation, and view refresh/retry drain does not create unrelated upload jobs.
- Confirm event storm protection: debounce/dedupe, max frequency, sync in-flight no reentry, and at most one follow-up tick after a running sync finishes.
- Confirm no new route, no upload route change and no TLS/HMAC/pinning/nonce/body hash/`RequestVerifier` change.
- Keep diagnostics redacted: no secrets, full hashes, full fingerprints, absolute paths, full metadata JSON, full transcript/note/summary/provider response, raw audio bytes or request/response bodies.
- Treat local build/test as code evidence only. Without paired iPhone/Mac redacted jsonl, report `not run; no real-device evidence produced.` and do not claim real-device convergence validation. Next v8.73 should add the real-device observation runbook and diagnostics gate.

## Canonical v8.71 Live Heartbeat syncRequested Checks

Purpose:

- Validate that a Mac manual sync request can wake the iPhone's existing sync path through the live heartbeat hint without changing long-recording upload routes or sync intervals.

Checks:

- Start from default/release `oldKernel`; confirm the Mac manual sync UI can enter the waiting state and Mac still does not connect back to iPhone.
- Confirm the iPhone heartbeat remains a 3 second status/liveness heartbeat and does not perform inventory exchange inline.
- Tap manual sync on Mac, then confirm the heartbeat/status response advertises `syncRequested` and the iPhone queues an immediate sync tick without waiting for the 240 second periodic timer.
- Confirm duplicate heartbeat hints while a sync is pending or running are deduped/debounced and do not create a sync storm.
- Confirm the queued tick uses the existing secure sync path and does not add or change routes, upload routes, TLS/HMAC/pinning/nonce/body hash, `RequestVerifier`, pairing or Keychain behavior.
- Confirm oldKernel and any manually selected canonical mode still follow the current kernel switch, decision, read, apply and upload gates; heartbeat itself must not create upload jobs.
- Confirm Mac pending manual sync is marked consumed/started/cleared or remains observable after iPhone sends inventory/sync.
- Keep diagnostics redacted: no secrets, full hashes, full fingerprints, absolute paths, full metadata JSON, full transcript/note/summary/provider response, raw audio bytes or request/response bodies.
- Treat local build/test as code evidence only. Long-recording convergence status requires paired iPhone/Mac redacted jsonl; without that, do not claim real-device convergence validation.

## Canonical v8.68 T7 Manual Switch Checks

Purpose:

- Validate long-recording upload/read behavior only after the single `内核模式` master switch and final code-completion gate allow a real paired-device trial.

Checks:

- Start in default/release `oldKernel` and confirm legacy upload/read still owns the flow.
- Confirm the DEBUG Settings switch exposes only `oldKernel`, `canonicalShadow`, `canonicalDecisionOnly`, `canonicalApplyNoAudio`, and `canonicalFullSync`.
- Run the Debug switch-back proof on a clone before fullSync.
- Move through `canonicalShadow`, `canonicalDecisionOnly`, and `canonicalApplyNoAudio` before `canonicalFullSync`; do not skip directly to fullSync.
- Confirm `canonicalApplyNoAudio` never starts canonical audio upload.
- Enable `canonicalFullSync` only with confirmation, owner approval, legacy fallback, route/security unchanged, diagnostics redaction, readiness and switch-back gates passing.
- During long recording upload, stop on Divergent, FreezeViolation, RollbackFailed, SecurityFailure, ExistingDifferentAudioBlocked, metadataOnly-as-audioAvailable, completed-ledger-alone no-op, unexpected productionRoot write, RequestVerifier bypass, retry storm or switch-back failure.
- Keep diagnostics redacted: no secrets, full hashes, full fingerprints, absolute paths, full metadata JSON, full transcript/note/summary/provider response, raw audio bytes or request/response bodies.
- Treat local build/test and realistic-root proof as code evidence only. Long-recording real-device status requires paired iPhone/Mac redacted jsonl.

## Canonical v8.66 T4-T5 Executor/Port Injection Checks

Purpose:

- Validate that canonical production executors and audio upload ownership are injected only through the master switch and only after the `canonicalFullSync` production-root gate allows them.

Checks:

- Start with default/release oldKernel and confirm canonical production ports/executors are nil/disabled while legacy upload remains owner.
- Confirm diagnosticsOnly, canonicalShadow, and canonicalDecisionOnly do not create production writes or canonical audio upload jobs.
- Confirm canonicalApplyNoAudio can expose non-audio apply/existence availability but blocks canonical audio upload.
- Confirm canonicalFullSync without owner approval or manual confirmation remains blocked/dry-run.
- Confirm canonicalFullSync with owner approval, manual confirmation, legacy fallback, legacy-readable/readiness, route/security, and root-safety gates can construct production-root non-audio ports and canonical audio executor.
- Confirm the audio executor still uses the existing secure start/status/chunk/finalize route path and does not add routes or bypass RequestVerifier.
- Confirm metadataOnly and receiveRecordOnly remain upload-needed states, not audioAvailable states.
- Keep diagnostics redacted and do not treat simulator, local build/test, fixture root, or fake clock results as real-device evidence.

## Canonical v8.55 audioUpload Domain Readiness Checks

Purpose:

- Validate that audioUpload can act as a guarded canonical domain under explicit `canonicalFullSync`, while default/release oldKernel and legacy fallback remain intact.

Checks:

- Start with default/release oldKernel and confirm upload/status remains legacy-owned.
- In explicit DEBUG/internal `canonicalFullSync`, confirm audioUpload canonical decision is evaluated and can be selected only when the gate allows it.
- Confirm `canonicalApplyNoAudio` blocks canonical audio upload while still allowing non-audio domains.
- Confirm peer metadataOnly, receiveRecordOnly, or studyItemOnly becomes uploadNeeded only when local audio exists; none are audioAvailable.
- Confirm peerUnknown remains deferred and does not fall back into overwrite.
- Confirm same hash plus same byteSize becomes noOpSameAudio; hash-only or size-only does not.
- Confirm different hash or byteSize, including existing different Mac audio, becomes conflict/no-overwrite.
- Confirm upload uses existing secure start/status/chunk/finalize routes and clients only.
- Interrupt during chunk upload, restart, and confirm resume uses existing job plus server-confirmed `confirmedBytes`.
- Confirm view refresh and read/status projection do not create an upload job.
- Confirm finalized Mac proof is required before iPhone marks uploaded/completed or suppresses exact legacy duplicate.
- Switch oldKernel -> canonicalFullSync -> oldKernel and confirm legacy can read the same upload/completed/interrupted status without migration.
- Keep diagnostics redacted: no absolute path, full hash, secret, full fingerprint, request/response body, raw audio bytes, full metadata JSON, transcript, note, summary, or provider response.

## Canonical v8.50 Upload Retry Drain and State Consistency Checks

Purpose:

- Validate that interrupted upload retry/restart behavior resumes an existing job and only reports completion after Mac finalized proof.

Checks:

- Create a real paired-device recording with default/release oldKernel baseline and legacy fallback available.
- In explicit DEBUG/internal canonicalFullSync or approved runtime config, interrupt a chunked upload after Mac has a partial session.
- Restart the iPhone app and confirm retry recovery resumes the existing canonical or legacy job; do not create a fresh unrelated job.
- Confirm resume starts from server-confirmed `confirmedBytes` after status refresh.
- Confirm view refresh does not create an upload job.
- Confirm peerUnknown remains deferred unless an existing valid session is being status-refreshed/resumed by the retry path.
- Confirm metadataOnly and receiveRecordOnly are not shown as audio available.
- Confirm completed local ledger alone is not shown as uploaded before peer/finalize proof.
- Confirm finalized Mac proof is accepted before iPhone marks uploaded.
- Confirm same hash plus same byteSize becomes no-op on the next run.
- Confirm different hash or byteSize becomes conflict/no-overwrite.
- Confirm diagnostics contain only relative/safe identifiers, session prefixes, offsets, counts, sizes, states, reasons and hash prefixes.

## Canonical v8.49 Audio Upload Checks

Purpose:

- Validate the real paired-device audio upload commit path after metadata-only existence has been observed.

Checks:

- Start with default/release behavior disabled and legacy fallback available.
- In explicit DEBUG/internal canonicalFullSync or approved runtime config, confirm peer metadataOnly or receiveRecordOnly becomes an upload candidate, not audioAvailable.
- Confirm upload uses existing secure start/status/chunk/finalize routes; no new route or abort route is used.
- Confirm chunked upload resumes from server-confirmed offset after interruption.
- Confirm finalize reports byteSize and hash proof before iPhone marks uploaded.
- Confirm Mac Audio Inbox shows audio available only after finalize proof.
- Confirm same hash plus same byteSize becomes no-op on the next run.
- Confirm existing different Mac audio is conflict/no-overwrite.
- Keep diagnostics redacted: no absolute path, full hash, shared secret, fingerprint, request/response body, raw audio bytes, transcript, note, summary, or provider response.

## 10-15 Minute Test

Purpose:

- Verify upload, regular transcription, and note generation have no regression.

Checks:

- iPhone upload succeeds.
- Audio Inbox shows the recording as received.
- `transcript.md` is generated.
- `note.md` is generated after the user starts note generation.
- `receive.json` keeps valid `transcriptionStatus` and `noteStatus`.

## 35-45 Minute Test

Purpose:

- Trigger chunked transcription without needing a full lecture-length recording.

Checks:

- `receive.json` has `transcriptionMode = chunked`.
- Chunk count matches the 15-minute chunk plan.
- Partial transcript files exist under the transcript chunk output area.
- Final `transcript.md` is merged in chunk order.
- Note generation remains available from the existing Audio Inbox flow.

## 2-3 Hour Test

Purpose:

- Validate the minimum real university lecture scale.

Checks:

- iPhone upload does not crash.
- Mac receive path does not show memory pressure from full request buffering.
- Failed transcription can be located by chunk index.
- Final `transcript.md` is produced after all successful chunks merge.
- Chunked note generation creates `sections/section_000.md`, `sections/section_001.md`, and so on.
- Final `note.md` is generated.
- `receive.json` contains complete long-task metadata: `transcriptionMode`, `transcriptionChunks`, `noteGenerationMode`, and `noteSections`.

## Failure Location Table

Upload failure:

- Check body hash and HMAC verification.
- Check temp upload file creation and cleanup.
- Check size limit and network timeout.
- Confirm the receiver still uses HTTPS, certificate pinning, and HMAC.

Transcription failure:

- Check failed chunk index.
- Check per-chunk timeout.
- Check model path and security-scoped bookmark state.
- Check bundled helper launch diagnostics.

Note generation failure:

- Check failed note section index.
- Check selected provider configuration.
- Check model context/token limit.
- Check request timeout and endpoint availability.

## Reporting Rules

- Do not include complete transcript text.
- Do not include API keys.
- Do not include shared secrets.
- Do not include complete provider response JSON.
- Use the local diagnostic report marker `1636` when attaching long-task reports.
