# Phase 00 — RAVEN23 source audit and companion architecture

**Audit date:** 2026-11-25  
**Primary repository:** \`m5ham3ds/RAVEN23\`  
**Audited ref:** \`main\`  
**Audited commit:** \`d9418ea5d83658ee82a9bc04062f97a6c9452f65\`  
**Companion repository:** \`m5ham3ds/RAVEN23-PLAYER\`

## 1. Confirmed technology

- Primary app is Flutter/Dart. \`.fvmrc\` pins Flutter 3.35.7 and \`pubspec.yaml\` requires Dart 3.9.x.
- Primary video surface is \`PlayerOne\` in \`lib/screens/common/player.dart\`.
- Both apps use the same BetterPlayer Plus Git dependency. The companion remains a separate package and application ID.
- Primary Android downloads are managed by Media3, not by Dart file copying.

## 2. Primary-app download and offline playback findings

| Concern | Existing source |
|---|---|
| Download metadata and request identity | \`lib/models/offline_download.dart\` |
| Flutter bridge | \`lib/services/offline_download_service.dart\` |
| Flutter state | \`lib/provider/offline_download_provider.dart\` |
| Android Media3 download bridge | \`android/app/src/main/kotlin/com/m5ham3ds/raven23/downloads/StreamDownloadsBridge.kt\` |
| Validated MP4 exporter | \`.../downloads/StreamDownloadExporter.kt\` |
| Download cache/store | \`.../downloads/StreamDownloadStore.kt\` |
| Offline route | \`lib/screens/common/offline_player_screen.dart\` |
| Main player | \`lib/screens/common/player.dart\` |
| External subtitle cache | \`lib/services/subtitle_playback_store.dart\` |
| Subtitle conversion | \`lib/services/subtitle_file_normalizer.dart\` |

Verified from source:
1. Android uses Media3 DownloadManager and queues a validated MP4 export when a download completes.
2. The working export currently lives under the main app's private \`filesDir/offline_exports\`; \`prepareForPlayback\` exposes a private path to Flutter.
3. \`saveCopy\` creates a separate user-visible MediaStore copy. It is not currently a single shared canonical artifact.
4. Existing offline playback uses the same \`PlayerOne\` BetterPlayer UI rather than a separate Media3 PlayerView.
5. \`OfflineDownload\` carries content ID, episode/season, quality, selected subtitle state, stream identity, expected duration, and episode/season metadata.
6. \`SubtitlePlaybackStore\` stores valid WebVTT tracks and a manifest under app-private application support. It retains up to ten subtitle tracks per media key. This private directory is not readable by another package.
7. Explicit public saves currently include the selected exported subtitle where requested; the complete set of cached subtitle tracks is not yet published.

Historical decisions were inspected in:
- \`phases/PHASE63.32_UNIFIED_OFFLINE_PLAYER_AND_DOWNLOAD_SUBTITLE_SELECTION.md\`
- \`phases/PHASE63.38_OFFLINE_LIBRARY_PLAYBACK_EXPORT_AND_DCIM.md\`

## 3. Account and history findings

- Primary authentication is Laravel Sanctum; token storage is \`SecureTokenStore\`.
- Sign-in uses \`POST auth/login\`; profile uses \`GET user/profile\`, under the runtime-configured \`/api/v1/\` API base.
- Each install sends its own persistent install UUID, device name and platform. The companion must have its own identity and authenticated session.
- Recently watched uses revision-aware \`POST sync/recently-watched\`, with movie/episode collections, server revision cursor, update timestamps and tombstones.
- The companion must use the same endpoint semantics rather than inventing a new history API or reading RAVEN23 private token/preferences.
- The companion's local-only videos must never produce a Laravel movie/episode payload.

## 4. Android storage boundary

Android app-private files are isolated by package. RAVEN23 Player cannot scan the primary app's private download cache, MP4 export or subtitle cache. A shared MediaStore artifact/URI is required.

### Selected architecture

- Canonical shared folder: \`Movies/RAVEN23/Library/\`.
- One validated MP4 per completed RAVEN23 download, opened through the same MediaStore content URI by both apps.
- A small versioned JSON manifest records stable download identity and display metadata.
- Every subtitle track is a separate sidecar with stable track key, language, display label, source, format and hearing-impaired flag.
- Player progress and device-local metadata remain in Player's private store.
- A transferred file is a new physical copy on the destination device; this is expected cross-device transfer, not duplicate storage on one phone.

### Safe migration rule

Publish the canonical MediaStore row, validate byte length and SHA-256, publish subtitle sidecars and manifest, reopen and verify, persist the shared URI in the primary store, and only then consider deleting a duplicate private export. If any step fails, keep the original playable export. Do not delete Media3 cache until retry/resume behavior has dedicated tests.

## 5. Local-only phone videos

A video without a valid RAVEN23 manifest is device-local content:
- its progress is stored in Player's private preferences/database;
- its progress is never sent to \`sync/recently-watched\`;
- it has no RAVEN23/TMDB account identity;
- it is never presented as account-library data;
- explicit Transfer may send the file but must not convert it into account data.

## 6. Transfer package

Versioned manifest + video + every associated subtitle, with sizes and SHA-256 hashes. Receiver validates schema/version, safe filenames, sizes, MIME, extensions and checksums before import. RAVEN-origin transfers preserve identity; local-only transfers remain local-only. The first transport uses Android Sharesheet/Quick Share; direct encrypted local-network transfer can reuse the same package format later.

## 7. Current foundation gaps

- This initial companion commit scans public MediaStore videos and plays device-local files.
- MediaStore subtitle discovery is best effort. Some Android releases restrict access to sidecar document files under \`READ_MEDIA_VIDEO\`; a SAF folder grant is required for reliable subtitle discovery.
- The primary repository has not yet been modified to publish completed private exports and every private subtitle track to the canonical shared library.
- Therefore primary-app private legacy downloads do **not** automatically appear in the companion yet.
- Manifest parsing, independent Laravel session/history sync, receiving/importing packages, and verified two-device transfer are later phases.
- Physical-device acceptance remains required for content URI playback, scoped-storage and subtitles.

## 8. Audit scope

The complete primary Git tree was enumerated (2,094 tree entries / 1,859 files). Source inspection covered Flutter/Android configuration, player, download domain and bridge, exporter/store, offline route, subtitle persistence/normalization, Laravel auth/session, recent-history repository/sync/model contracts. This is a focused audit of integration boundaries, not a claim that unrelated catalog, manga, Live TV or advertising modules were line-by-line reviewed.
