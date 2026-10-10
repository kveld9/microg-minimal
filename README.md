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

---

## Mantenimiento / Update Flow

### Upstream Source
Monitor upstream releases on GitHub:
- [microG GmsCore Releases](https://github.com/microg/GmsCore/releases)

### Single-Command Update
When a new upstream release drops, execute the single update command from the repository root:

```bash
# Standard interactive update: checks upstream, displays summary, prompts, updates, commits, tags, and pushes
./scripts/update.sh

# Read-only status check (never writes files, exits 0 if up-to-date, 2 if update available)
./scripts/update.sh --check

# Target an explicit upstream release tag
./scripts/update.sh v0.3.18.252432

# Non-interactive mode (skips confirmation prompt)
./scripts/update.sh --yes

# Update and build locally without git operations (prints manual commands)
./scripts/update.sh --no-commit

# Update, build, commit, and tag locally without pushing to remote
./scripts/update.sh --no-push
```

### Complete Maintenance Workflow
1. **Prerequisites**:
   Ensure a Git remote named `origin` is configured pointing to your repository:
   ```bash
   git remote add origin git@github.com:<owner>/microg-minimal.git
   ```
2. **Run Update Command**:
   Execute `./scripts/update.sh`.
   The script queries the latest upstream microG release and compares it with `versions.env`.
   - If up-to-date: displays current status and exits `0` with zero file modifications.
   - If an update is available: displays the resolved asset summary and asks for confirmation:
     `Proceed with update to <tag>? [y/N]`
3. **Automated Package Assembly (on confirmation)**:
   Upon confirmation, `./scripts/update.sh` autonomously:
   - Resolves upstream assets dynamically by prefix (`com.google.android.gms-*.apk` and `com.android.vending-*.apk`).
   - Downloads payloads into `${XDG_CACHE_HOME:-~/.cache}/microg-minimal`.
   - Computes SHA-256 checksums and exact byte sizes.
   - Rewrites owned fields in `versions.env`.
   - Synchronizes `module.prop` and `update.json`.
   - Updates the Last-Known-Good table in `README.md` and appends a release entry to `CHANGELOG.md`.
   - Stages payloads via `./scripts/fetch-apks.sh` and builds `dist/microg-minimal-<version>.zip` via `./scripts/build-module.sh`.
   - Generates multi-hash integrity records (`dist/checksums-<version>.txt`) and standard checksums (`dist/SHA256SUMS.txt`).
4. **Automated Commit & Push (Default Flow)**:
   Unless opted out via `--no-commit` or `--no-push`, the script automatically completes the release cycle:
   - Checks Git preconditions (valid work tree, active branch, and `origin` remote configured).
   - Stages exactly: `versions.env`, `module.prop`, `update.json`, `README.md`, `CHANGELOG.md`.
   - Commits with message: `chore(microg): bump upstream microG to <target_tag>`.
   - Creates local release tag: `<version>` (e.g., `v0.3.18`).
   - Pushes branch (`git push origin <branch>`) followed by tag (`git push origin <version>`).
   - Pushing the tag triggers `.github/workflows/release.yml` on GitHub Actions, which builds the module archive, computes multi-hash checksums, and attaches them to the new GitHub Release.
5. **Manual & Recovery Modes**:
   - If `--no-commit` is passed, metadata changes and build artifacts remain uncommitted, and manual Git commands are displayed.
   - If `--no-push` is passed, commit and tag are created locally, but not pushed to `origin`.
   - If remote push fails or `origin` is missing, local changes and tags are preserved with copy-pasteable manual commands to recover:
     ```bash
     git push origin <branch>
     git push origin <version>
     ```

### Numeric Version Code Scheme
`versionCode` is computed using the deterministic formula:
```text
versionCode = (MAJOR * 100000) + (MINOR * 10000) + (PATCH * 10) + SUBPATCH
```
- Current baseline: `v0.3.17` -> `(0 * 100000) + (3 * 10000) + (17 * 10) + 0` = `30170`.
- Incremental example: `v0.3.18` -> `(0 * 100000) + (3 * 10000) + (18 * 10) + 0` = `30180`.
- Subpatch example: `v0.3.16.1` -> `(0 * 100000) + (3 * 10000) + (16 * 10) + 1` = `30161`.

### update.json Synchronization
The `zipUrl` in `update.json` points to:
`https://github.com/kveld/microg-minimal/releases/download/<version>/microg-minimal-<version>.zip`
This URL matches the GitHub Release tag created in step 5, ensuring Magisk update checks locate the published archive.

### Handling Upstream Asset Naming Changes
Upstream microG GmsCore releases publish standard APKs matching:
- GmsCore: `com.google.android.gms-*.apk` (excluding `-hw.apk` Huawei variants and `.asc` signatures).
- Phonesky: `com.android.vending-*.apk` (excluding `-hw.apk` Huawei variants and `.asc` signatures).

If microG upstream alters asset naming patterns, `scripts/update.sh` fails loudly with an explicit error message instead of guessing URLs. To adapt, update the asset matching rules in `scripts/lib-upstream.sh` (`parse_release_assets` function).

---

## Magisk Update Channel Configuration

Magisk checks `update.json` via the URL specified in `module.prop` (`updateJson` property).

When publishing a new release:
1. Pushing tag `v*` triggers `.github/workflows/release.yml` which uploads `dist/microg-minimal-v<version>.zip` to GitHub Releases.
2. Ensure `update.json` in the default branch reflects the release version, numeric version code, and the direct download URL in `zipUrl`.
