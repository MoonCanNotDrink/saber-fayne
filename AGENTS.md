# Saber Fayne — Codex development guidance

This repository is a fork of `saber-notes/saber`. Work on the **`feature/stylus-palm-rejection`** branch only. The default `main` branch is a pristine upstream baseline and must remain unchanged.

## Goal

Implement **optional stylus-priority palm rejection** for Android, targeting a Huawei MatePad 11 with an M-Pencil 3. The user will perform real-device validation after development. Do not claim Huawei compatibility based solely on CI or an emulator.

## Inspect before editing

Read the current implementation and related tests, especially:
- `lib/components/canvas/canvas_gesture_detector.dart`
- `lib/components/canvas/interactive_canvas.dart`
- `lib/pages/editor/editor.dart`
- `lib/data/prefs.dart`, editor toolbar/settings and `test/stylus_test.dart`
- `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`
- `.github/workflows/android.yml`, `.gitmodules`

Review upstream GitHub issues #1830 and #1730. Check current code instead of assuming those reports explain the root cause.

## Behaviour and compatibility requirements

- Introduce a user-visible, optional `Stylus priority / palm rejection` setting, **off by default** pending device testing.
- Prefer per-pointer tracking and gesture recognizer arbitration over merely ignoring touch events in late callbacks.
- Maintain stylus handwriting, pressure, eraser behaviour, rapid strokes and toolbar interactions initiated intentionally with the pen.
- While stylus contact or genuine hover is active, reject unintended finger pan/zoom/draw gestures and finger taps on editing controls. Preserve normal one- and two-finger navigation when stylus is inactive, with a bounded cooldown (start at 400 ms; tune only with evidence).
- Handle pen-first, palm-first, simultaneous fingers/pen, pointer cancellation and fast transitions; document any hardware/OS limitations if stylus hover is missing.
- Preserve existing settings, gesture locks, other platforms and accessibility as far as practical.
- **Do not alter** Nextcloud official-server URLs, authentication, WebDAV sync semantics, encryption, note formats, migration logic or desktop compatibility.

## Build and safety boundaries

- Produce a **separately installable Android test APK** with a distinct application ID and label. Consider ContentProvider authorities and the shared `nc` login callback, ensuring the modified app cannot interfere with the official app. Keep upstream production identifiers untouched when feasible.
- The fork contains a Flutter git submodule; use the repository-pinned toolchain and dependencies before considering upgrades.
- Prefer an isolated/manual GitHub Actions test-APK workflow that uploads an artifact. Avoid automatically publishing to Play Store, releases or tags.
- Never request real cloud passwords, encryption passwords or sensitive data. Do not access or mutate the user's production notes, account or other devices.
- Do not deploy, publish releases, merge to `main`, submit upstream PRs, or bypass failed tests without explicit user approval.
- Avoid scope creep and refactors unrelated to touch handling.

### Approved test-only authentication exception

The user has explicitly approved external-browser login exclusively for the
Android `stylusTest` APK. Gate it with Android platform detection and Flutter's
actual `appFlavor`, not a general production preference. This APK must have its
own application ID, label and ContentProvider authorities, and must not register
the official app's `nc://` callback. Reuse the existing Nextcloud Login Flow v2
initialisation, polling and credential-storage implementation; do not add an
authentication protocol or alter production authentication, encryption, WebDAV
sync or note formats. Handle cancellation, a bounded timeout, backgrounding and
returning to the app. Browser closure alone cannot be detected by an external
launcher: give the user explicit cancel/reopen controls. A killed app starts a
new login attempt rather than persisting a pending authentication token.
Use mocked transports for cloud tests. Live-account and cross-device
sync/decryption checks still require the user's separate authorisation.

## Verification and deliverables

1. Add deterministic tests for stylus-only, pen-first, palm-first, multiple pointers, pointer cancel, hover and no-hover fallbacks, cooldown, toolbar accidental tap prevention, finger navigation recovery, pressure/eraser and the feature-off path.
2. Run `flutter analyze`, relevant widget/unit tests and Android APK build where the environment permits. Record commands, exact outcomes and blockers. Do not claim unexecuted tests passed.
3. Supply the feature diff, commit SHA, build workflow run and artifact links, APK checksum, exact installation steps and rollback procedure.
4. Provide a Huawei tablet manual test matrix, including a disposable test note and separate sync/decryption verification against an unmodified Ubuntu/Windows client only **after** the user authorises live account testing.
5. Report independent gates: `CODE_READY`, `APK_BUILD_READY` and `DEVICE_TEST_PENDING`. Final adoption requires the user's real-device sign-off.

If an input or build limitation prevents a trustworthy solution, stop and document the issue instead of silently claiming completion.
