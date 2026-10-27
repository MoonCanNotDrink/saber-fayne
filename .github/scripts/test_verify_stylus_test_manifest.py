"""Regression checks for accidentally uploading a conflicting Android artifact."""

import contextlib
import io
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from verify_stylus_test_manifest import verify


ANDROID = "{http://schemas.android.com/apk/res/android}"
PACKAGE = "com.adilhanney.saber.fayne.stylustest"
MANIFEST = f"""<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="{PACKAGE}">
    <application android:label="Saber Fayne Test">
        <activity android:name="com.adilhanney.saber.MainActivity" />
        <provider android:name="com.superlist.super_native_extensions.DataProvider"
            android:authorities="{PACKAGE}.SuperClipboardDataProvider" />
        <provider android:name="androidx.startup.InitializationProvider"
            android:authorities="{PACKAGE}.androidx-startup" />
    </application>
</manifest>"""


class TestApkIsolationValidator(unittest.TestCase):
    def validate(self, manifest):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "AndroidManifest.xml"
            ET.ElementTree(manifest).write(path)
            with contextlib.redirect_stdout(io.StringIO()):
                verify(path)

    def test_accepts_isolated_apk_manifest(self):
        self.validate(ET.fromstring(MANIFEST))

    def test_rejects_official_application_id(self):
        manifest = ET.fromstring(MANIFEST)
        manifest.set("package", "com.adilhanney.saber")
        with self.assertRaisesRegex(ValueError, "application ID"):
            self.validate(manifest)

    def test_rejects_indistinguishable_launcher_label(self):
        manifest = ET.fromstring(MANIFEST)
        manifest.find("application").set(ANDROID + "label", "Saber")
        with self.assertRaisesRegex(ValueError, "label"):
            self.validate(manifest)

    def test_rejects_shared_callback_on_any_activity(self):
        for scheme in ("nc", "NC"):
            with self.subTest(scheme=scheme):
                manifest = ET.fromstring(MANIFEST)
                activity = manifest.find("application/activity")
                intent_filter = ET.SubElement(activity, "intent-filter")
                ET.SubElement(intent_filter, "data", {ANDROID + "scheme": scheme})
                with self.assertRaisesRegex(ValueError, "nc callback"):
                    self.validate(manifest)

    def test_rejects_remaining_official_callback_activity(self):
        manifest = ET.fromstring(MANIFEST)
        ET.SubElement(
            manifest.find("application"),
            "activity",
            {ANDROID + "name": "com.linusu.flutter_web_auth_2.CallbackActivity"},
        )
        with self.assertRaisesRegex(ValueError, "callback activity"):
            self.validate(manifest)

    def test_rejects_shared_authority_even_on_another_provider(self):
        for authorities in (
            "com.adilhanney.saber.androidx-startup",
            f"{PACKAGE}.androidx-startup;com.adilhanney.saber.extra",
            "${applicationId}.androidx-startup",
            "",
        ):
            with self.subTest(authorities=authorities):
                manifest = ET.fromstring(MANIFEST)
                provider = manifest.find("application").findall("provider")[1]
                provider.set(ANDROID + "authorities", authorities)
                with self.assertRaisesRegex(ValueError, "outside its application ID"):
                    self.validate(manifest)

    def test_rejects_missing_clipboard_provider(self):
        manifest = ET.fromstring(MANIFEST)
        application = manifest.find("application")
        application.remove(application.find("provider"))
        with self.assertRaisesRegex(ValueError, "clipboard provider is missing"):
            self.validate(manifest)

    def test_rejects_wrong_clipboard_authority_with_valid_package_prefix(self):
        manifest = ET.fromstring(MANIFEST)
        manifest.find("application/provider").set(
            ANDROID + "authorities", PACKAGE + ".wrongClipboard"
        )
        with self.assertRaisesRegex(ValueError, "Clipboard provider authority"):
            self.validate(manifest)


if __name__ == "__main__":
    unittest.main()
