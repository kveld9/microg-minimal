# Changelog

All notable changes to the microG Minimal Magisk module will be documented in this file.

## [v0.3.21] - 2026-10-11

### Changed
- Automated metadata alignment across repository manifests with no functional module changes.

## [v0.3.20] - 2026-10-11

### Fixed
- Installer safety: dropped overlay auto-disable to prevent breaking zygote idmap state on flash.
- Cache invalidation: wipe package and resource caches (`/data/system/package_cache`, `/data/resource-cache`) during install.
- Module uninstallation: restore and re-enable overlays modified by earlier module releases.

## [v0.3.19] - 2026-10-11

### Added
- Auto-release publishing workflow triggered on module-code changes with semantic versioning guards.
- Tracked release guard helper script (`scripts/release-version.py`).

### Fixed
- Metadata author identifier displayed consistently as `kveld9`.
- Installer baseline notification updated to reflect Android 8.1 multi-layout coverage.

### Documentation
- Actionable troubleshooting guidance for signature spoofing and OverlayFS requirements.
- Step-by-step post-installation microG setup checklist.

## [v0.3.18] - 2026-10-11

### Added
- Multi-layout support covering standard Android `system/product` alongside Go partitions.
- Compatibility overlays for Android 8.1 legacy `PrebuiltGmsCore`, `PrebuiltGmsCorePi`, and `PrebuiltGmsCorePix` layouts.
- Packaged microG priv-app permissions, default permissions, and sysconfig XML definitions.
- Custom ROM GApps suite coverage including MindTheGapps, NikGapps, BitGapps, and OpenGapps.
- Standalone ADB host and on-device `scripts/check-device.sh` diagnostic check tool with automated cleanup guidance.
- Installer auto-disable for conflicting GApps overlays and automated cleanup of existing `/data/app` updates at flash time.
- Slim module packaging staging payloads once and fanning out to target directories at install time (reduced archive size from ~600MB to ~115MB).

### Fixed
- Overlay candidate validation to ensure only system packages are targeted before disabling.
- Preflight automatic shell re-execution under Bash with transport discovery on host and device.
- CI installer template paths and variable linting.

## [v0.3.17] - 2026-10-10

### Added
- Initial minimal Magisk module skeleton compatible with Magisk v20.4+ and v30.x.
- Split-APK directory suppression via `.replace` markers for `system/priv-app/GmsCoreGo` and `system/priv-app/Phonesky`.
- Baseline microG GmsCore v0.3.17 (`GmsCoreGo.apk`) and microG Companion / FakeStore (`Phonesky.apk`).
- Reproducible download and build tooling (`scripts/fetch-apks.sh` and `scripts/build-module.sh`).
- Single source of truth configuration in `versions.env`.
- Online update channel definition in `update.json`.
