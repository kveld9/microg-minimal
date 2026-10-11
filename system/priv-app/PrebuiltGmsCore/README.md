# PrebuiltGmsCore Directory Placeholder

This directory mounts over `/system/priv-app/PrebuiltGmsCore` on legacy Android layouts (such as Android 8.1 on Nexus 5X).

## Purpose

1. **Stock Package Suppression**: The `.replace` marker in this folder instructs the root manager to replace the entire directory rather than merging its contents with the stock system partition. This suppresses the stock Google Play Services package (`PrebuiltGmsCore`) that conflicts with microG signatures and permissions.
2. **Payload Placement**: The standalone monolithic microG GmsCore APK (`GmsCore.apk`) is placed in this directory at module assembly time via `scripts/build-module.sh` (sourced from `vendor/` or downloaded via `scripts/fetch-apks.sh`).

Binary `.apk` files are excluded from Git version control.
