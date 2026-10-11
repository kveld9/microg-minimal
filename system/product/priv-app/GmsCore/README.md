# GmsCore Standard Directory Placeholder

This directory mounts over `/product/priv-app/GmsCore` (and `/system/product/priv-app/GmsCore`) on standard Android layouts.

## Purpose

1. **Stock Package Suppression**: The `.replace` marker in this folder instructs the root manager to replace the entire directory rather than merging its contents with the stock system partition. This suppresses stock Google Play Services packages that conflict with microG signatures and permissions.
2. **Payload Placement**: The standalone microG GmsCore APK (`GmsCore.apk`) is placed in this directory at module assembly time via `scripts/build-module.sh` (sourced from `vendor/` or downloaded via `scripts/fetch-apks.sh`).

Binary `.apk` files are excluded from Git version control.
