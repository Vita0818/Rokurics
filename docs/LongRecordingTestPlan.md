# Rokurics Long Recording Test Plan

1636

This plan is for local, user-driven validation of long recordings. It does not require API keys, shared secrets, or private transcript contents to be written into reports.

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
