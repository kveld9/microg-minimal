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
   - `README.md` is end-user documentation only (install, flash, uninstall, updates). Never put internals there: no hashes, sizes, versionCode formula, `update.sh` flags, or asset naming rules.
   - `scripts/update.sh` owns `versions.env`, `module.prop`, `update.json`, and `CHANGELOG.md` rewrites on every bump. Update `README.md` only when user-facing behavior or install steps change.
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

7. **English Only (100% of the repo)**:
   - Every tracked file is written strictly in English: docs, code, comments, commit messages, config descriptions, and release notes.
   - Never introduce non-English prose in any new or edited file. Fix any non-English text on sight within the touched scope.

## Maintainer Workflow (internal, never for README.md)

- Building from source (maintainers/contributors only). Requirements: Bash 4+, `curl` or `wget`, `sha256sum`, `zip`/`unzip` (`python3` and `git` for the update flow). Then `./scripts/fetch-apks.sh` (downloads verify automatically) and `./scripts/build-module.sh` (flashable zip goes to `dist/`; `--skeleton` builds offline without APKs).
- Upstream source: `https://github.com/microg/GmsCore/releases`. `scripts/update.sh` is the sole entrypoint (`--check`, `--dry-run`, `--yes`, `--no-commit`, `--no-push`, explicit `TAG`); `lib-upstream.sh` holds the shared logic, including `parse_release_assets`.
- Upstream asset selection: `com.google.android.gms-*.apk` and `com.android.vending-*.apk`, excluding `-hw.apk` Huawei variants and `.asc` signatures. On naming changes the updater fails loudly; adapt the match rules, never guess URLs.
- `versionCode` formula: `(MAJOR * 100000) + (MINOR * 10000) + (PATCH * 10) + SUBPATCH` (e.g. `v0.3.17` -> `30170`).
- `update.json` `zipUrl` pattern: `https://github.com/kveld9/microg-minimal/releases/download/<version>/microg-minimal-<version>.zip`, matching the tag release published by the workflow.
- Proven baseline reference lives in `versions.env` (`GMS_*` / `VENDING_*` size and SHA256 fields, reference device context); never duplicate hashes into other files.
- Multi-manager support: Magisk (native, `.replace` markers), KernelSU family (KernelSU, KernelSU Next, SukiSU via `REPLACE` in `customize.sh`; `system` mounting there requires a metamodule such as `meta-overlayfs`), APatch (native OverlayFS, `REPLACE` supported). `META-INF/.../update-binary` delegates to the Magisk binary when present, otherwise runs the built-in fallback installer; `customize.sh` uses only the portable installer contract.
