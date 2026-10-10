# GmsCoreGo Directory Placeholder

This directory mounts over `/system/priv-app/GmsCoreGo` on Android 9 Go.

## Purpose

1. **Split-APK Suppression**: The `.replace` marker in this folder informs Magisk to replace the entire directory rather than merging its contents with the stock system partition. This suppresses the stock split-APKs (`base.apk` and configuration splits) that cause `INSTALL_FAILED_DUPLICATE_PERMISSION` and packaging mismatch crashes.
2. **Payload Placement**: The standalone monolithic microG GmsCore APK (`GmsCoreGo.apk`) is placed in this directory at module assembly time via `scripts/build-module.sh` (sourced from `vendor/` or downloaded via `scripts/fetch-apks.sh`).

Binary `.apk` files are excluded from Git version control.
