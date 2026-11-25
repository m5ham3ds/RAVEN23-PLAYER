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

For a local installable preview build, set `android/local.properties` with your Flutter SDK and Android SDK paths, install Gradle 8.14, then generate the wrapper once:

```bash
cd android
gradle wrapper --gradle-version 8.14 --distribution-type all
cd ..
flutter build apk --debug --target-platform android-arm64
```

## Android signing and installation

The CI pipeline verifies every APK with Android's `apksigner`, checks the package ID, and checks that the ARM64 Flutter library is present before publishing the artifact.

- Without signing secrets, CI produces an **installable debug-signed preview APK**. It is intended for device testing, not public release. Hosted runners create their debug key independently, so a later preview may not be accepted as an in-place update; uninstall the previous preview first, or configure a persistent release key.
- With all four signing secrets configured, CI produces a **release-signed APK**. Keep the keystore and passwords private and back them up securely; losing the keystore prevents signed updates to users who installed an app with that key.

To prepare a persistent release key locally, run `keytool -genkeypair -v -keystore raven23-player-release.jks -alias raven23-player -keyalg RSA -keysize 2048 -validity 10000`. Store the keystore safely outside this repository. Add these GitHub Actions repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `RAVEN23_KEYSTORE_BASE64` | Base64 encoding of the complete `.jks` file |
| `RAVEN23_KEYSTORE_PASSWORD` | Keystore password |
| `RAVEN23_KEY_ALIAS` | `raven23-player` |
| `RAVEN23_KEY_PASSWORD` | Key password |

For example, create the Base64 value with `base64 -w 0 raven23-player-release.jks` on Linux/Termux. Never commit the keystore or its passwords to Git.

GitHub Actions installs Flutter 3.35.7, Java 17, Android SDK 36 and Gradle 8.14, generates the Android wrapper, runs formatting/analyze/tests, builds the APK, verifies its signature and package metadata, then attaches the installable APK as a workflow artifact. Workflow: `.github/workflows/android-ci.yml`.

## Shared-library contract

The canonical shared folder is `Movies/RAVEN23/Library/`. The primary app will publish one validated MP4 plus a versioned JSON manifest and subtitle sidecars. RAVEN23 Player will open the same MediaStore item rather than copying its video bytes into private storage.

Read:
- [Source audit and architecture](docs/PHASES/PHASE00_AUDIT_AND_ARCHITECTURE.md)
- [Master implementation roadmap](docs/PHASES/MASTER_IMPLEMENTATION_ROADMAP.md)
- [Phase 01 cross-repository shared-library contract](docs/PHASES/PHASE01_SHARED_LIBRARY_INTEGRATION.md)

## Scope boundaries

The primary app owns RAVEN download state, stream source identity and account media identity. The Player owns its interface and local-only video state. Only a validated RAVEN manifest may make a media item eligible for account-history sync. No app-private session token is read from the other package.
