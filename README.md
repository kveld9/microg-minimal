# microG Minimal

A systemless root module that replaces the stock Google Play Services and Play Store with [microG](https://github.com/microg/GmsCore). It works with Magisk, the KernelSU family, and APatch. The system partition is never modified: removing the module and rebooting restores the stock apps.

## What It Does

On affected devices (typical Android Go), the stock Play Services and Play Store ship as split packages that cannot be swapped file by file. This module cleanly suppresses those stock packages and provides the microG equivalents as system apps instead.

## Compatibility

- Any of these root managers: Magisk, KernelSU family (KernelSU, KernelSU Next, SukiSU), APatch.
- Android 9 or newer, on devices whose stock Play Services and Play Store use the Go-edition app layout.
- ARM devices, 32-bit and 64-bit.
- On the KernelSU family, a system-mount helper (a metamodule such as `meta-overlayfs`) is required for the module files to take effect.
- No Zygisk required.

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
