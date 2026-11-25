# RAVEN23 Player — master implementation roadmap

A successful compile is not enough to close a phase. Use focused tests, CI and Android device acceptance. The primary app and companion are separate repositories and must be changed together when a shared contract requires it.

## Phase 00 — audit and standalone foundation

**State:** source audit recorded; Android media scanner, standalone Flutter shell, BetterPlayer surface, device-local progress and basic verified share package created. CI/device validation pending.

Exit criteria:
- Flutter analyze and unit tests pass.
- ARM64 Android release APK builds in GitHub Actions.
- Ordinary phone videos play locally and resume after app restart.
- Ordinary videos never produce account-history data.
- App discovers the agreed shared folder without privately duplicating its video bytes.

## Phase 01 — shared offline download library (both repositories)

**State:** contract specified; primary-app implementation pending.

Primary repository:
1. Add a MediaStore publisher and versioned manifest writer to the Android download bridge.
2. Publish each completed validated Media3 export once to \`Movies/RAVEN23/Library/\`.
3. Publish all cached subtitle tracks, not only the selected download subtitle.
4. Persist shared MediaStore URI, row ID, digest, manifest version and publication state in the download record.
5. Migrate old completed exports safely: publish and verify first, then remove only a redundant export.
6. Route primary offline playback through the shared URI while preserving PlayerOne controls and episode selection.
7. Keep Media3 cache deletion separate and protected by retry/resume tests.

Companion repository:
- Parse manifest v1 and show title/movie/series/episode metadata.
- Enumerate all subtitle tracks and allow selection.
- Play shared MediaStore URI directly without a second private video copy.
- Reconcile deleted, renamed and updated items.

Exit criteria:
- A downloaded MP4 and HLS/DASH title appear in Player without a second permanent video copy.
- Both apps reference one MediaStore row and identical bytes/hash.
- Arabic and English subtitles both appear after restart.
- Airplane-mode playback and downloaded episode switching work.
- Failed/interrupted publish preserves old playable file and retries without duplicates.

## Phase 02 — independent account and synced history

**State:** primary contract audited; companion implementation pending.

- Companion signs in independently to the same runtime-configured Laravel \`/api/v1/\` base URL.
- Each install uses a unique persistent device UUID and its own Sanctum token. Never read another package's private session.
- Queue progress locally; upload only validated RAVEN media identities through \`sync/recently-watched\`.
- Respect server revision cursor, version timestamps, tombstones and account isolation.
- Device-local videos remain excluded from payloads under every circumstance.

Exit criteria:
- Start a RAVEN download in Player and see it in the same account's RAVEN23 Continue Watching list after sync.
- Newer playback progress wins on both devices.
- Account switch/sign-out never sends old queued progress as another user.
- Local-only items remain device-only after sign-out.

## Phase 03 — Transfer send/receive

**State:** package v1 share-out scaffold exists; receiving and verified import pending.

- Send videos with all subtitles, metadata and hashes.
- Accept packages from Android Sharesheet/Quick Share and show a review screen.
- Validate safe filenames, schema, sizes, MIME types, extensions and hashes.
- Publish each received video once into shared MediaStore and subtitles separately.
- Preserve RAVEN23 identity and mark phone-local items as local-only.
- Add duplicate detection, resumable local-network transfer and explicit import conflict choices.

Exit criteria:
- Transfer a movie and episode between two devices.
- Verify video and subtitle hashes after receipt.
- Received content appears in both Player and RAVEN23 without a second library copy on target device.
- Local-only transfers do not enter account sync.

## Phase 04 — playback parity and release

- Add subtitle chooser, labels, style/timing controls, audio selection where supported, orientation, fullscreen, PiP and episode queue.
- Add Arabic/RTL and English localization, accessibility, error recovery and low-storage protection.
- Run Flutter unit/widget, Android JVM, instrumentation and two-device acceptance suites.
- Publish signed artifacts only using user-owned signing secrets; verify ARM64-only artifact metadata.

## Invariants

1. One shared video artifact per RAVEN23 download on one device.
2. A manifest, not a filename alone, establishes RAVEN account-media identity.
3. Local phone videos are excluded from account history.
4. Keep every subtitle track, not only the active track.
5. Main app owns RAVEN download state and identity; Player owns playback UI and local-video state.
6. Never embed production URLs, account credentials or signing keys.
7. A failed sync/transfer/publication never deletes the only valid media file.
