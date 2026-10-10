# Changelog

All notable changes to the microG Minimal Magisk module will be documented in this file.

## [v0.3.17] - 2026-10-10

### Added
- Initial minimal Magisk module skeleton compatible with Magisk v20.4+ and v30.x.
- Split-APK directory suppression via `.replace` markers for `system/priv-app/GmsCoreGo` and `system/priv-app/Phonesky`.
- Baseline microG GmsCore v0.3.17 (`GmsCoreGo.apk`) and microG Companion / FakeStore (`Phonesky.apk`).
- Reproducible download and build tooling (`scripts/fetch-apks.sh` and `scripts/build-module.sh`).
- Single source of truth configuration in `versions.env`.
- Online update channel definition in `update.json`.
