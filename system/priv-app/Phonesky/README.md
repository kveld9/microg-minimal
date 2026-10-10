# Phonesky Directory Placeholder

This directory mounts over `/system/priv-app/Phonesky` on Android 9 Go.

## Purpose

1. **Split-APK Suppression**: The `.replace` marker in this folder instructs Magisk to suppress the stock Google Play Store (`Phonesky`) directory and its split-APKs.
2. **Payload Placement**: The microG Companion APK (formerly FakeStore, package `com.android.vending`) is placed here as `Phonesky.apk` during module assembly via `scripts/build-module.sh`. This satisfies apps requiring Google Play Store presence without running the heavyweight stock Play Store client.

Binary `.apk` files are excluded from Git version control.
