# Stylus priority test APK

This is an opt-in Android experiment. Huawei MatePad 11 / M-Pencil 3 support
requires the user's physical-device sign-off; automated checks cannot establish
pen classification, hover delivery, latency, or pressure quality on that device.

Enable **Settings → Stylus priority / palm rejection** (off by default). Existing
finger-drawing and gesture-lock preferences still apply. Pen activity suppresses
finger drawing, pan/zoom, and editing-control taps. Rejected contacts must lift
before they can participate in a later gesture; waiting out the 400 ms cooldown
does not revive a resting palm. Intentional pen taps and keyboard/semantic actions
remain available.

Without hover, the app cannot identify a palm before the first pen contact.
Finger actions already completed before any pen evidence cannot be distinguished
from intentional navigation. Genuine hover refreshes a bounded 400 ms lease;
devices that stop reporting stationary hover will use that expiry as a fallback.
Contact itself remains active until up/cancel/removal. Check both stationary hover
and rapid pen lifts on the actual tablet.

## Build and installation

The `Stylus priority test APK` GitHub Actions workflow runs only on this fork's
`feature/stylus-palm-rejection` branch and uploads artifacts without creating a
release or tag. Its feature-branch push trigger permits the first run without
adding the workflow to pristine `main`. Analysis and targeted tests must pass
before the APK is built and uploaded.

The artifact includes an ARM64 APK, SHA256SUMS, the source commit, SDK versions,
test results, extracted APK manifest, and signature verification output. Verify
the downloaded APK before installation:

```sh
sha256sum -c SHA256SUMS
adb install -r Saber-Fayne-Stylus-Test-arm64.apk
```

Alternatively open the APK on the tablet and temporarily allow installation from
that file manager. Select **Saber Fayne Test**, not the official Saber launcher.
The test ID is `com.adilhanney.saber.fayne.stylustest`; its private app storage and
ContentProvider authorities are separate, and it does not register `nc://`.
Do not point the test app at the official app's custom notes folder.

The workflow uses a disposable debug signing key for this test variant only.
Different workflow runs may have different keys: Android may require uninstalling
the previous **test** app before installing a new build. Export any disposable
test notes you want to keep first. Never uninstall the official application to
resolve a test APK installation error.

To roll back, disable the optional setting, or uninstall only the test package:

```sh
adb uninstall com.adilhanney.saber.fayne.stylustest
```

Uninstalling deletes the test app's private data. The official app has a different
package ID and must remain installed and unchanged.

## Offline Huawei validation matrix

Start logged out, create a disposable local note, and record the tablet OS,
M-Pencil firmware, APK SHA-256, source commit, and the result of each row.

| Case | Expected observation |
| --- | --- |
| Setting off | Existing drawing/navigation and toolbar behavior retained |
| Setting on; pen alone | Continuous strokes with normal pressure and no jumps |
| Pen first, then palm | Writing continues; no finger pan, zoom, or control tap |
| Palm first, then pen | Existing touch gesture stops at pen evidence; pen can draw immediately |
| Two fingers then pen; rapid overlap | No mixed-pointer zoom/focal-point jump after takeover |
| Palm held across successive strokes | Pen keeps drawing; resting palm never becomes a new gesture |
| Pen lift, new fingers at <400 ms | New finger gestures rejected |
| Pen lift, new fingers after >400 ms | One/two-finger navigation returns according to existing locks |
| Moving and stationary hover | Observe suppression and lease expiry; report missing hover |
| Rapid strokes without hover | First pen down works; no need to wait after preceding fingers |
| Pen side button and inverted pen, if supported | Existing eraser behavior; palm lift does not switch tools |
| Touch toolbar, HUD, popup while pen active | No accidental tool, color, undo, zoom-lock, or page action |
| Pen toolbar and popup taps | Intentional editing controls remain operable |
| Cancel interrupted stroke; background/return | No stuck rejection, eraser, scrolling, or phantom stroke |
| Zoom/pan locks; text editing; accessibility | Existing locks and deliberate keyboard/semantic actions preserved |
| Long local writing session | Record missed strokes, latency, pressure quality, battery/heat issues |

## Test-only login exception

Only Android flavor `stylusTest` opens the existing Nextcloud Login Flow v2 login
URL in an external browser. It reuses the existing v2 polling endpoint and the
same credential consumer/storage. Production authentication, server URLs,
encryption, WebDAV, and note formats retain their normal path. The test app has
no official `nc://` callback handler.

The test login screen provides cancel/reopen controls. Closing the browser alone
cannot reliably notify an external app: return to the test app to cancel or
reopen, or let the bounded login timeout expire. Background polling pauses and
resumes when the app returns; the overall deadline still applies.

Cloud development must use mocks only. **Live account testing requires separate
user authorization.** After that authorization, use a dedicated disposable test
account and a disposable note to check login/cancel/timeout/background/return,
then sync and decrypt the test note with an unmodified Ubuntu or Windows Saber
client. Check both directions and compare content, attachments, and handwriting.
Do not perform this check against production notes or provide account secrets in
chat. Keep this gate separate from offline palm rejection validation.

## Gates

- `CODE_READY`: analyzed code and deterministic automated checks pass.
- `APK_BUILD_READY`: exact commit's Actions build, manifest isolation, signature,
  and checksum checks pass, and a downloadable artifact exists.
- `DEVICE_TEST_PENDING`: remains pending until the user records the Huawei matrix
  and explicitly signs off. A passing emulator or CI run does not close it.
