# Phonesky Standard Directory Placeholder

This directory mounts over `/product/priv-app/Phonesky` (and `/system/product/priv-app/Phonesky`) on standard Android layouts.

## Purpose

1. **Stock Package Suppression**: The `.replace` marker in this folder instructs the root manager to suppress the stock Google Play Store directory and its contents.
2. **Payload Placement**: The microG Companion APK (formerly FakeStore, package `com.android.vending`) is placed here as `Phonesky.apk` during module assembly via `scripts/build-module.sh`. This satisfies apps requiring Google Play Store presence without running the heavyweight stock Play Store client.

Binary `.apk` files are excluded from Git version control.
