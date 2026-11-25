# RAVEN23 Player

Standalone Flutter companion video player for the RAVEN23 ecosystem.

## Current implementation status

**Foundation phase committed; GitHub Actions validation required.**

| Capability | State |
|---|---|
| Independent Android/Flutter app | Implemented |
| MediaStore video scanning | Implemented |
| Device-local video playback with BetterPlayer Plus | Implemented |
| Device-local playback resume | Implemented |
| Basic Transfer package with metadata and SHA-256 | Implemented |
| Shared RAVEN23 download library | Contract designed; primary-app bridge is Phase 01 |
| All RAVEN23 subtitle tracks | Phase 01; current scanner is best effort until SAF support |
| Independent Laravel login and watch-history sync | Phase 02 |
| Transfer receive/import and two-device verification | Phase 03 |
| Full PlayerOne UI parity and release hardening | Phase 04 |

A video in the primary app's private Downloads screen is **not yet automatically accessible** to this app. Android isolates app-private storage. Phase 01 publishes the validated shared video once into MediaStore and gives both apps the same content URI. The companion must not make a second permanent video copy to play it.

## Technology alignment

- Flutter 3.35.7 / Dart 3.9.x, matching the primary repository's `.fvmrc`.
- Dart / Flutter, matching the primary application.
- The same BetterPlayer Plus Git dependency used by RAVEN23.
- Android MediaStore for public/shared media; app-private preferences for local player progress.
- Laravel Sanctum and the revision-aware `sync/recently-watched` contract are reserved for Phase 02.
- Local phone videos never become account-library data.

## Build

```bash
flutter pub get
flutter analyze
flutter test
```

For a local Android build, set `android/local.properties` with your Flutter SDK and Android SDK paths, install Gradle 8.14, then generate the wrapper once:

```bash
cd android
gradle wrapper --gradle-version 8.14 --distribution-type all
cd ..
flutter build apk --release --target-platform android-arm64
```

GitHub Actions installs Flutter 3.35.7, Java 17, Android SDK 36 and Gradle 8.14, generates the Android wrapper, runs formatting/analyze/tests, then builds an ARM64 release APK. The APK is attached as a workflow artifact; production signing is intentionally not configured in source. Workflow: `.github/workflows/android-ci.yml`.

## Shared-library contract

The canonical shared folder is `Movies/RAVEN23/Library/`. The primary app will publish one validated MP4 plus a versioned JSON manifest and subtitle sidecars. RAVEN23 Player will open the same MediaStore item rather than copying its video bytes into private storage.

Read:
- [Source audit and architecture](docs/PHASES/PHASE00_AUDIT_AND_ARCHITECTURE.md)
- [Master implementation roadmap](docs/PHASES/MASTER_IMPLEMENTATION_ROADMAP.md)
- [Phase 01 cross-repository shared-library contract](docs/PHASES/PHASE01_SHARED_LIBRARY_INTEGRATION.md)

## Scope boundaries

The primary app owns RAVEN download state, stream source identity and account media identity. The Player owns its interface and local-only video state. Only a validated RAVEN manifest may make a media item eligible for account-history sync. No app-private session token is read from the other package.
