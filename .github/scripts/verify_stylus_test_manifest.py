"""Check the manifest extracted from the built APK before uploading it."""

import sys
import xml.etree.ElementTree as ET


def verify(manifest_path):
    root = ET.parse(manifest_path).getroot()
    android = "{http://schemas.android.com/apk/res/android}"
    package = "com.adilhanney.saber.fayne.stylustest"
    if root.get("package") != package:
        raise ValueError("APK must have the independently installed test application ID")

    application = root.find("application")
    if application is None or application.get(android + "label") != "Saber Fayne Test":
        raise ValueError("APK must have the distinct Saber Fayne Test launcher label")

    if any(data.get(android + "scheme", "").lower() == "nc" for data in root.iter("data")):
        raise ValueError("Test APK must not register any nc callback")

    for activity in application.findall("activity"):
        if activity.get(android + "name") == "com.linusu.flutter_web_auth_2.CallbackActivity":
            raise ValueError("Official authentication callback activity remains in test APK")

    clipboard_found = False
    for provider in application.findall("provider"):
        authorities = provider.get(android + "authorities", "").split(";")
        if not all(authority.startswith(package + ".") for authority in authorities):
            raise ValueError("Test APK contains a provider authority outside its application ID")
        if provider.get(android + "name") == "com.superlist.super_native_extensions.DataProvider":
            clipboard_found = True
            if authorities != [package + ".SuperClipboardDataProvider"]:
                raise ValueError("Clipboard provider authority is not isolated")
    if not clipboard_found:
        raise ValueError("Expected clipboard provider is missing")

    print("PASS: test application ID, label, provider authorities, and absence of nc callback")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_stylus_test_manifest.py <apkanalyzer-manifest.xml>")
    verify(sys.argv[1])
