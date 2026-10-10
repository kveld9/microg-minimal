# microG Minimal

A systemless root module that replaces the stock Google Play Services and Play Store with [microG](https://github.com/microg/GmsCore) on Android Go devices. The system partition is never modified: removing the module and rebooting restores the stock apps.

## What It Does

On Android Go, the stock Play Services and Play Store ship as split packages that cannot be swapped file by file. This module cleanly suppresses those stock packages and provides the microG equivalents as system apps instead.

## Compatibility

- Android 9 or newer (Go-edition app layout).
- ARM devices, 32-bit and 64-bit.
- Any of these root managers: Magisk, KernelSU family (KernelSU, KernelSU Next, SukiSU), APatch.
- On the KernelSU family, a system-mount helper (a metamodule such as `meta-overlayfs`) is required for the module files to take effect.
- No Zygisk required.

## Install

### Requirements

On the computer used to build the module zip:

- Bash 4+
- `curl` or `wget`
- `sha256sum`
- `zip` and `unzip`

### 1. Download the microG files

```bash
./scripts/fetch-apks.sh
```

Downloads are verified automatically before use.

### 2. Build the module zip

```bash
./scripts/build-module.sh
```

The flashable zip is created in `dist/`.

### 3. Flash it on the device

1. Copy the zip from `dist/` to the device.
2. Open the manager app (Magisk, KernelSU, SukiSU, or APatch).
3. Go to Modules -> Install from storage and select the zip.
4. Reboot when the install finishes.

### 4. Uninstall

1. In the manager app, remove `microG Minimal` from Modules.
2. Reboot. The stock system apps come back automatically.

## Updates

Managers that support the update channel notify about new versions automatically. Every release is also published on the GitHub Releases page of this repository.
