# Agent Operating Guidelines: microG-minimal

## Repository Scope

This repository maintains the minimal systemless Magisk module skeleton, download tooling, and assembly scripts for running microG on Android 9 Go (specifically tablet IT-701A).

## Core Rules & Invariants

1. **Single Source of Truth (`versions.env`)**:
   - `versions.env` strictly owns all version strings, release tags, artifact URLs, target filenames, and SHA256 checksums.
   - Never duplicate version strings, download URLs, or cryptographic hashes across scripts or configuration files. All tooling must derive values directly from `versions.env`.

2. **Zero Binaries in Git**:
   - Never stage or commit `.apk`, `.zip`, `.jar`, `.img`, or compiled binary artifacts to Git.
   - APK artifacts are fetched on demand via `scripts/fetch-apks.sh` and stored in the gitignored `vendor/` directory.
   - Output archives are generated into the gitignored `dist/` directory.

3. **Documentation Synchronization**:
   - Any modification to versions, architecture, paths, commands, or installation logic must immediately update `README.md`, `CHANGELOG.md`, `module.prop`, and `update.json` within the same commit.
   - Maintain consistency between `versions.env`, `module.prop`, and `update.json`.

4. **Environment Portability & Script Standards**:
   - Never hardcode user home directories (`/home/...`) or host-specific paths.
   - Always derive repository root dynamically (`REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`).
   - All shell scripts must maintain `bash -n` validation, pass `set -euo pipefail`, and keep cyclomatic complexity low (CC <= 5) with early guard returns.

5. **Upstream Update Automation**:
   - `scripts/bump-microg.sh` is the sole programmatic owner of `versions.env` rewrites besides human maintainers.
   - Never hand-edit generated checksum files (`dist/checksums-*.txt`, `dist/SHA256SUMS.txt`).

6. **Release Publishing Invariant**:
   - Releases are published exclusively via Git tags (`v*`) through `.github/workflows/release.yml`.
   - Never execute `git push` or create releases autonomously; git push and tag creation are maintainer-driven steps.
