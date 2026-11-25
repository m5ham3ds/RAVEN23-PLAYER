# RAVEN23 Player

A standalone Flutter companion player for the RAVEN23 ecosystem. It is designed to work without the RAVEN23 app installed for ordinary on-device videos, and to read the same shared offline media library once the companion-library bridge is enabled in RAVEN23.

## Project status

**Foundation phase — implementation in progress.** This repository is intentionally independent from `m5ham3ds/RAVEN23`.

| Capability | Current state |
|---|---|
| Standalone Android app shell | Implemented in this foundation |
| Browse Android MediaStore videos | Implemented in this foundation |
| Play local video with BetterPlayer Plus | Implemented in this foundation |
| Device-local playback progress | Implemented in this foundation |
| Scan the future shared RAVEN23 media folder | Implemented; current legacy private downloads are not yet exposed |
| RAVEN23 download/subtitle shared-library bridge | Planned in Phase 01; requires a compatible change in the main app |
| Laravel account and watch-history sync | Planned in Phase 02; contract is documented |
| Cross-device Transfer with subtitle/metadata package | Planned in Phase 03 |
| Verified release APK and device acceptance | Pending CI and physical-device validation |

Do not interpret a video appearing in the main app's private Downloads screen as proof that it is already accessible to this app. Android isolates application-private files. Phase 01 migrates the canonical playable export into a shared, indexed media location and gives both apps a stable manifest reference; it must not create a second permanent copy.

## Technology alignment

- Flutter **3.35.7** and Dart 3.9.x, matching the current `.fvmrc` in RAVEN23.
- Dart / Flutter, matching the primary application.
- BetterPlayer Plus from the same Git repository used by RAVEN23, so the playback engine is shared.
- Android MediaStore for public shared video discovery; app-private SQLite/preferences are reserved for player-only state.
- Laravel Sanctum and the existing `/api/v1/sync/recently-watched` contract for account history. Local-device videos never enter that contract.

## Build

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Build an ARM64 Android APK:

```bash
flutter build apk --release --target-platform android-arm64
```

The Laravel API base URL is deployment configuration, not hard-coded into the source. Pass it using `--dart-define=LARAVEL_API_URL=https://your-host.example/api/v1/` or configure it in the app's account settings. Never commit credentials, Sanctum tokens, or private signing keys.

## Shared-library contract

The canonical shared location is `Movies/RAVEN23/Library` (Android MediaStore relative path). The primary app will publish one validated MP4 per completed download and a small JSON manifest plus zero or more subtitle sidecars. RAVEN23 Player will reference the same MediaStore item; it will not copy a video into its private files just to play it. Subtitle files may be cached locally because they are small, but the source sidecars and language metadata remain in the shared library.

Manifest requirements and migration/rollback details are in [Phase 00 — audit and architecture](docs/PHASES/PHASE00_AUDIT_AND_ARCHITECTURE.md).

## Scope boundary

The source app remains the authority for streaming-provider metadata, download identity, TMDB media identity, and user-owned RAVEN23 downloads. This player is the authority for its UI and local-only device media. Account watch progress is synchronized only for media carrying a valid RAVEN23 media identity. Local videos are never presented as account-library data and are never uploaded.

See [the implementation roadmap](docs/PHASES/MASTER_IMPLEMENTATION_ROADMAP.md) before implementing a later phase.
