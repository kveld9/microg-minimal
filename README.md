# microG Minimal (Split-APK Suppressor)

A minimal, systemless Magisk module providing [microG GmsCore](https://github.com/microg/GmsCore) and microG Companion (`Phonesky`) on Android 9 Go.

## Overview

### The Problem: Stock Split-APKs

On Android 9 Go devices (specifically proven on tablet IT-701A), stock Google Play Services (`GmsCoreGo`) and Google Play Store (`Phonesky`) are deployed as split-APKs comprising a base package and architecture- or language-specific configuration splits (for example, `base.apk`, `split_config.arm64_v8a.apk`, and localized split packages).

Attempting to replace stock Google Play Services using simple user-level installs or standard Magisk directory overlays creates packaging conflicts. If replacement APKs are merged into the existing system directories, Android's `PackageManager` detects conflicting split definitions alongside the replacement monolithic APK, resulting in installation errors or runtime service crashes.

### The Solution: Systemless Suppression via `.replace`

This module leverages Magisk's `.replace` directory marker in:
- `system/priv-app/GmsCoreGo/.replace`
- `system/priv-app/Phonesky/.replace`

The `.replace` marker instructs Magisk's overlay system to mount the module's directory directly over the stock partition location without merging existing files. This suppresses all original stock split-APKs and allows monolithic microG APK binaries to function as system-level privileged applications.

---

## Target Device Profile

- **Device**: Tablet IT-701A
- **Operating System**: Android 9 Pie (Go Edition)
- **API Level**: SDK 28
- **CPU Architecture**: 32-bit ARM (`armv7l` / `armeabi-v7a`)
- **Partition Layout**: A-only system
- **Root Environment**: Magisk v20.4+ / Magisk v30.x (Zygisk not required)

---

## Last-Known-Good Reference Binaries

The following binary artifacts were proven operational on the reference tablet IT-701A. Binary files are not committed to Git; they are downloaded dynamically via scripts.

| Component | Target System Path | Upstream Package | File Size (Bytes) | SHA256 Checksum |
| :--- | :--- | :--- | :--- | :--- |
| **GmsCore** | `system/priv-app/GmsCoreGo/GmsCoreGo.apk` | `com.google.android.gms` (v0.3.17) | 108,113,833 | `e5e6cba078bdec812b5450599350e5c1a12c8b7438da5bf77123af170f8c1a35` |
| **Phonesky** | `system/priv-app/Phonesky/Phonesky.apk` | `com.android.vending` (v0.3.17) | 4,210,169 | `9b8616011cc8f026bcbbe094df850794abb9d6d9f23214d7a8f8c4d1033ea012` |

---

## Non-Goals

- **No Aurora Store Packaging**: Aurora Store (v4.7.5+) operates as a standalone user application (`/data/app/`). It is not bundled in this systemless module.
- **No Direct GSF Modification**: Google Services Framework (`GoogleServicesFramework`) is not removed or altered beyond package-hiding or disabling.
- **No Vendored Binaries in Git**: All APK binaries and zip packages remain strictly excluded from repository tracking.

---

## Installation & Build Instructions

### 1. Requirements

- Bash 4+
- `curl` or `wget`
- `sha256sum`
- `zip` and `unzip`

### 2. Fetch Binaries

To download the verified microG release APKs defined in `versions.env`:

```bash
./scripts/fetch-apks.sh
```

Artifacts are cached in `${XDG_CACHE_HOME:-~/.cache}/microg-minimal` and staged in `vendor/` after cryptographic verification.

### 3. Build Flashable Module Zip

To package the flashable Magisk module:

```bash
./scripts/build-module.sh
```

The resulting zip archive is generated in `dist/microg-minimal-v0.3.17.zip`.

#### Dry-Run / Skeleton Build (Offline Verification)

To verify archive packaging without network connectivity or APK payloads:

```bash
SKIP_DOWNLOAD=1 ./scripts/build-module.sh
# or
./scripts/build-module.sh --skeleton
```

This generates `dist/microg-minimal-v0.3.17-skeleton.zip` and verifies zip structure via `zip -T`.

### 4. Flashing to Device

1. Transfer `dist/microg-minimal-v0.3.17.zip` to the target device via ADB or local storage:
   ```bash
   adb push dist/microg-minimal-v0.3.17.zip /sdcard/Download/
   ```
2. Open the **Magisk App** on the device.
3. Navigate to **Modules** -> **Install from storage**.
4. Select `microg-minimal-v0.3.17.zip`.
5. Reboot the device after flashing completes.

### 5. Uninstallation

1. Open the **Magisk App** -> **Modules**.
2. Tap **Remove** on `microG Minimal`.
3. Reboot the device. Magisk will remove `/data/adb/modules/microg-minimal`, restoring stock system partitions.

---

## Version Bump Procedure

All component versions, download URLs, and cryptographic hashes are governed by `versions.env`.

To update the module:
1. Update `versions.env`:
   - Set `GMS_VERSION`, `GMS_RELEASE_TAG`, and `GMS_URL`.
   - Update `GMS_SHA256` with the checksum from the new release.
   - Set `VENDING_VERSION`, `VENDING_RELEASE_TAG`, `VENDING_URL`, and `VENDING_SHA256`.
   - Update `MODULE_VERSION` and increment `MODULE_VERSION_CODE`.
2. Synchronize `update.json`:
   - Update `version` and `versionCode` to match `versions.env`.
   - Point `zipUrl` to the newly published release asset URL.
3. Update `CHANGELOG.md` with release notes.
4. Run `./scripts/build-module.sh` to assemble the new release package.

---

## Magisk Update Channel Configuration

Magisk checks `update.json` via the URL specified in `module.prop` (`updateJson` property).

When publishing a new release:
1. Upload `dist/microg-minimal-v<version>.zip` to GitHub Releases.
2. Ensure `update.json` in the default branch reflects the release version, numeric version code, and the direct download URL in `zipUrl`.
