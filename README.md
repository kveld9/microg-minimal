# microG Minimal

A systemless root module that replaces the stock Google Play Services and Play Store with [microG](https://github.com/microg/GmsCore). It works with Magisk, the KernelSU family, and APatch. The system partition is never modified: removing the module and rebooting restores the stock apps.

## What It Does

On affected devices (Android Go, standard Android, and legacy layouts), the stock Play Services and Play Store ship as system packages (including split packages on Go) that cannot be swapped file by file. This module cleanly suppresses those stock packages and provides the microG equivalents as system apps instead.

## Compatibility

- Any of these root managers: Magisk, KernelSU family (KernelSU, KernelSU Next, SukiSU), APatch.
- Android 8.1 or newer, supporting Android Go layouts (`system/priv-app/GmsCoreGo` and `Phonesky`), standard Android layouts (`product/priv-app/GmsCore` and `Phonesky`), and legacy layouts (`system/priv-app/PrebuiltGmsCore`).
- Provides the required system permission grants for microG.
- ARM devices, 32-bit and 64-bit.
- On the KernelSU family, `/system` mounting requires `meta-overlayfs` (the official reference metamodule by KernelSU Developers, available on [MMRL](https://mmrl.dev/repository/grdoglgmr/meta-overlayfs)). Flash it like a normal module, reboot, and verify microG exists under `/system/priv-app/`. Fork managers (e.g. ResuKisu/SukiSU-family) may handle metamodules differently; follow their documentation or support channels.
- No Zygisk required.

## Before Installing

Run the preflight check script from your host computer with bash and host ADB over USB debugging:

```bash
./scripts/check-device.sh
```

Alternatively, copy the script to the device or run from Termux with root:

```bash
su -c bash check-device.sh --local
```

Pre-flash checklist:
- **Clean flash without GApps**: If the ROM includes pre-installed GApps (stock OEM or GApps-bundled custom ROMs), clean-flash a vanilla ROM without GApps.
- **Signature spoofing**: The ROM must support signature spoofing (this module does not provide it). If missing, switch to a spoofing-capable ROM (such as LineageOS for microG) or apply a FakeGApps patch via LSPosed, then verify in microG Self-Check.
- **No `/data` updates**: The installer automatically removes conflicting Play Services and Play Store updates in `/data` and invalidates caches, but does not touch overlays. Uninstallation re-enables overlays disabled by older module versions (/data updates are not restored). Run `./scripts/check-device.sh` beforehand to inspect active updates and verify device compatibility.
- **Unsupported layouts**: If the preflight check reports an incompatible API or unrecognized partition layout, open an issue using the Device Support template and paste the generated report.

## Install

### 1. Download the module zip

Get the latest `microg-minimal-*.zip` from the GitHub Releases page of this repository.

### 2. Flash it on the device

1. Copy the zip to the device.
2. Open the manager app (Magisk, KernelSU, SukiSU, or APatch).
3. Go to Modules -> Install from storage and select the zip.
4. Reboot when the install finishes.

### 3. Verify installation

Open microG Settings and reboot once if prompted. Complete setup using the checklist below.

### 4. Recommended microG configuration

- [ ] **Self-Check**: verify signature spoofing is granted; if not, stop and fix your ROM or spoofing patch ([Before Installing](#before-installing)).
- [ ] **Permissions**: grant location, phone, SMS, contacts, and storage when microG prompts for runtime permissions.
- [ ] **Battery optimization**: battery exemption is applied automatically; do not restrict microG background battery usage.
- [ ] **Google account**: add your account only after Self-Check passes, then enable device registration and Cloud Messaging.
- [ ] **Location**: install a UnifiedNlp backend (such as Mozilla or local GSM/Wi-Fi backends) and enable network-based location.
- [ ] **Exposure Notifications**: keep disabled unless specifically needed.

### 5. Uninstall

1. In the manager app, remove `microG Minimal` from Modules.
2. Reboot. The stock system apps come back automatically.

## Updates

Managers that support the update channel notify about new versions automatically. Every release is also published on the GitHub Releases page of this repository.
