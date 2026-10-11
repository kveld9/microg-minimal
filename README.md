# microG Minimal

A systemless root module that replaces the stock Google Play Services and Play Store with [microG](https://github.com/microg/GmsCore). It works with Magisk, the KernelSU family, and APatch. The system partition is never modified: removing the module and rebooting restores the stock apps.

## What It Does

On affected devices (Android Go, standard Android, and legacy layouts), the stock Play Services and Play Store ship as system packages (including split packages on Go) that cannot be swapped file by file. This module cleanly suppresses those stock packages and provides the microG equivalents as system apps instead.

## Compatibility

- Any of these root managers: Magisk, KernelSU family (KernelSU, KernelSU Next, SukiSU), APatch.
- Android 8.1 or newer, supporting Android Go layouts (`system/priv-app/GmsCoreGo` and `Phonesky`), standard Android layouts (`product/priv-app/GmsCore` and `Phonesky`), and legacy layouts (`system/priv-app/PrebuiltGmsCore`).
- Provides the required system permission grants for microG.
- ARM devices, 32-bit and 64-bit.
- On the KernelSU family, a system-mount helper (a metamodule such as `meta-overlayfs`) is required for the module files to take effect.
- No Zygisk required.

## Before Installing

Run the preflight check script from your host machine with the device connected via USB:

```bash
./scripts/check-device.sh
```

Pre-flash checklist:
- **Clean flash without GApps**: If the ROM includes pre-installed GApps (stock OEM or GApps-bundled custom ROMs), clean-flash a vanilla ROM without GApps.
- **Signature spoofing**: The ROM must support signature spoofing (verify with microG Self-Check after install; this module does not provide spoofing).
- **No `/data` updates**: The installer automatically removes conflicting stock updates in `/data` with an on-screen notice during flash. Run `./scripts/check-device.sh` beforehand to inspect active updates and verify device compatibility.
- **Unsupported layouts**: If the preflight check reports an incompatible API or unrecognized partition layout, open an issue using the Device Support template and paste the generated report.

## Install

### 1. Download the module zip

Get the latest `microg-minimal-*.zip` from the GitHub Releases page of this repository.

### 2. Flash it on the device

1. Copy the zip to the device.
2. Open the manager app (Magisk, KernelSU, SukiSU, or APatch).
3. Go to Modules -> Install from storage and select the zip.
4. Reboot when the install finishes.

### 3. Uninstall

1. In the manager app, remove `microG Minimal` from Modules.
2. Reboot. The stock system apps come back automatically.

## Updates

Managers that support the update channel notify about new versions automatically. Every release is also published on the GitHub Releases page of this repository.
