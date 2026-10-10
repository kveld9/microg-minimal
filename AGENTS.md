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

5. **Upstream Update Automation & Single Entry Point**:
   - `scripts/update.sh` is the sole user-facing entrypoint for checking and bumping upstream microG releases.
   - `scripts/lib-upstream.sh`, `scripts/fetch-apks.sh`, and `scripts/build-module.sh` are internal implementation components, not direct user commands.
   - `scripts/update.sh` is the sole programmatic owner of `versions.env` rewrites besides human maintainers.
   - On successful update, `scripts/update.sh` autonomously commits metadata changes and pushes `<branch>` and `<tag>` to `origin`, unless opted out via `--no-commit` or `--no-push`.
   - Never hand-edit generated checksum files (`dist/checksums-*.txt`, `dist/SHA256SUMS.txt`).

6. **Release Publishing Invariant**:
   - Releases are published exclusively via Git tags (`v*`) through `.github/workflows/release.yml`.
   - When executed by maintainers, `scripts/update.sh` autonomously commits and pushes `<branch>` and `<tag>` to `origin`.
   - AI assistants must never execute `git push` directly in autonomous turns; git push remains maintainer-driven (either manually or via maintainer-invoked `update.sh`).
