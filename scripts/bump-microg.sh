#!/usr/bin/env bash
# bump-microg.sh - Automate microG upstream update, metadata rewrites, and package generation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.env"

# shellcheck source=lib-upstream.sh
. "${SCRIPT_DIR}/lib-upstream.sh"

CACHE_DIR="${CACHE_DIR:-"${XDG_CACHE_HOME:-"${HOME:-/tmp}/.cache"}/microg-minimal"}"
DIST_DIR="${DIST_DIR:-"${REPO_ROOT}/dist"}"

TARGET="latest"
CHECK_ONLY=0
DRY_RUN=0

print_usage() {
  cat <<'EOF'
Usage: bump-microg.sh [TAG|--latest] [OPTIONS]

Resolves upstream microG releases, downloads APKs, rewrites versions.env,
updates metadata files, builds the Magisk module, and computes release checksums.

Arguments:
  TAG             Target upstream release tag (e.g., v0.3.17.252432).
  --latest        Query GitHub API for the latest release (default).

Options:
  --check         Check upstream release status without writing files.
  --dry-run       Preview resolved metadata updates without writing files.
  --help, -h      Display this help message and exit.
EOF
}

parse_arguments() {
  for arg in "$@"; do
    case "${arg}" in
      --check)
        CHECK_ONLY=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --latest)
        TARGET="latest"
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      -*)
        echo "Error: Unknown option '${arg}'" >&2
        print_usage >&2
        exit 1
        ;;
      *)
        TARGET="${arg}"
        ;;
    esac
  done
}

load_versions_file() {
  if [[ ! -f "${VERSIONS_FILE}" ]]; then
    echo "Error: versions.env not found at ${VERSIONS_FILE}" >&2
    exit 1
  fi
  # shellcheck source=../versions.env
  . "${VERSIONS_FILE}"
}

download_asset() {
  local url="$1"
  local dest_path="$2"
  local part_path="${dest_path}.part"

  echo "Downloading: ${url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar --output "${part_path}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "${part_path}" "${url}"
  else
    echo "Error: Neither curl nor wget is available." >&2
    return 1
  fi
  mv "${part_path}" "${dest_path}"
}

ensure_cached_asset() {
  local url="$1"
  local asset_name="$2"
  local expected_size="$3"
  local cache_path="${CACHE_DIR}/${asset_name}"

  mkdir -p "${CACHE_DIR}"

  if [[ -f "${cache_path}" ]]; then
    local current_size
    current_size="$(get_file_size "${cache_path}")"
    if [[ -n "${expected_size}" && "${current_size}" == "${expected_size}" ]]; then
      echo "Cache hit for ${asset_name} (${current_size} bytes)"
      echo "${cache_path}"
      return 0
    fi
  fi

  download_asset "${url}" "${cache_path}"
  local downloaded_size
  downloaded_size="$(get_file_size "${cache_path}")"

  if [[ -n "${expected_size}" && "${downloaded_size}" != "${expected_size}" ]]; then
    rm -f "${cache_path}"
    echo "Error: Downloaded size (${downloaded_size}) does not match expected (${expected_size}) for ${asset_name}" >&2
    return 1
  fi

  echo "${cache_path}"
}

generate_checksum_files() {
  local dist_dir="$1"
  local module_version="$2"

  local checksum_file="${dist_dir}/checksums-${module_version}.txt"
  local sha256_sums="${dist_dir}/SHA256SUMS.txt"

  (
    cd "${dist_dir}"
    local zip_pattern="microg-minimal-${module_version}.zip"
    if [[ ! -f "${zip_pattern}" ]]; then
      zip_pattern="microg-minimal-*.zip"
    fi

    echo "==================================================" > "${checksum_file}"
    echo " microG Minimal ${module_version} — Integrity Hashes" >> "${checksum_file}"
    echo "==================================================" >> "${checksum_file}"
    echo "" >> "${checksum_file}"

    echo "## SHA-256" >> "${checksum_file}"
    sha256sum ${zip_pattern} >> "${checksum_file}"
    echo "" >> "${checksum_file}"

    echo "## SHA-512" >> "${checksum_file}"
    sha512sum ${zip_pattern} >> "${checksum_file}"
    echo "" >> "${checksum_file}"

    echo "## MD5" >> "${checksum_file}"
    md5sum ${zip_pattern} >> "${checksum_file}"

    sha256sum ${zip_pattern} > "${sha256_sums}"
  )
  echo "Integrity hashes written to ${checksum_file} and ${sha256_sums}"
}

print_next_steps() {
  local module_version="$1"
  local target_tag="$2"

  echo ""
  echo "=================================================="
  echo " Update Complete: microG Minimal ${module_version}"
  echo "=================================================="
  echo "Upstream Tag:   ${target_tag}"
  echo "Module Archive: ${DIST_DIR}/microg-minimal-${module_version}.zip"
  echo "Checksums:      ${DIST_DIR}/checksums-${module_version}.txt"
  echo "                ${DIST_DIR}/SHA256SUMS.txt"
  echo ""
  echo "Next maintainer steps:"
  echo "  1. Review changes:"
  echo "     git diff"
  echo "  2. Commit update:"
  echo "     git add versions.env module.prop update.json README.md CHANGELOG.md"
  echo "     git commit -m \"chore(microg): bump upstream microG to ${module_version}\""
  echo "  3. Create release tag:"
  echo "     git tag ${module_version}"
  echo "  4. Push commit and tag to publish GitHub Release:"
  echo "     git push origin main"
  echo "     git push origin ${module_version}"
  echo "=================================================="
}

execute_check() {
  local release_json="$1"
  local target_tag gms_name gms_url vending_name vending_url
  target_tag="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("tag_name"))' "${release_json}")"
  gms_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_name"))' "${release_json}")"
  gms_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_url"))' "${release_json}")"
  vending_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_name"))' "${release_json}")"
  vending_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_url"))' "${release_json}")"

  echo "=================================================="
  echo " microG Release Status Check (Read-Only)"
  echo "=================================================="
  echo "Current module tag:  ${GMS_RELEASE_TAG}"
  echo "Resolved target tag: ${target_tag}"
  echo "GmsCore asset:       ${gms_name}"
  echo "  URL:               ${gms_url}"
  echo "Phonesky asset:      ${vending_name}"
  echo "  URL:               ${vending_url}"
  if [[ "${GMS_RELEASE_TAG}" == "${target_tag}" ]]; then
    echo "Status: Current module is up-to-date with ${target_tag}."
  else
    echo "Status: Update available (${GMS_RELEASE_TAG} -> ${target_tag})."
  fi
  echo "=================================================="
}

execute_dry_run() {
  local module_version="$1"
  local version_code="$2"
  local target_tag="$3"
  local gms_name="$4"
  local gms_size="$5"
  local vending_name="$6"
  local vending_size="$7"

  echo "=================================================="
  echo " microG Bump Dry-Run Preview (No Writes)"
  echo "=================================================="
  echo "Target Tag:          ${target_tag}"
  echo "New Module Version:  ${module_version}"
  echo "New Version Code:    ${version_code}"
  echo "GmsCore Asset:       ${gms_name} (${gms_size} bytes)"
  echo "Phonesky Asset:      ${vending_name} (${vending_size} bytes)"
  echo ""
  echo "Planned File Updates:"
  echo "  - versions.env (MODULE_VERSION, MODULE_VERSION_CODE, GMS_*, VENDING_*)"
  echo "  - module.prop (version, versionCode)"
  echo "  - update.json (version, versionCode, zipUrl)"
  echo "  - README.md (Last-Known-Good Reference Binaries table row)"
  echo "  - CHANGELOG.md (entry for [${module_version}])"
  echo "=================================================="
}

main() {
  parse_arguments "$@"
  load_versions_file

  local release_json
  release_json="$(resolve_upstream_release "${TARGET}")" || exit 1

  if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    execute_check "${release_json}"
    exit 0
  fi

  local target_tag gms_name gms_url gms_size vending_name vending_url vending_size
  target_tag="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("tag_name"))' "${release_json}")"
  gms_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_name"))' "${release_json}")"
  gms_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_url"))' "${release_json}")"
  gms_size="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_size", ""))' "${release_json}")"
  vending_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_name"))' "${release_json}")"
  vending_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_url"))' "${release_json}")"
  vending_size="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_size", ""))' "${release_json}")"

  local version_info semver module_version version_code
  version_info="$(derive_version_info "${target_tag}")"
  semver="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("semver"))' "${version_info}")"
  module_version="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("module_version"))' "${version_info}")"
  version_code="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("version_code"))' "${version_info}")"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    execute_dry_run "${module_version}" "${version_code}" "${target_tag}" "${gms_name}" "${gms_size}" "${vending_name}" "${vending_size}"
    exit 0
  fi

  local gms_cache_path vending_cache_path
  gms_cache_path="$(ensure_cached_asset "${gms_url}" "${gms_name}" "${gms_size}")"
  vending_cache_path="$(ensure_cached_asset "${vending_url}" "${vending_name}" "${vending_size}")"

  local actual_gms_size actual_gms_sha actual_vending_size actual_vending_sha
  actual_gms_size="$(get_file_size "${gms_cache_path}")"
  actual_gms_sha="$(calculate_sha256 "${gms_cache_path}")"
  actual_vending_size="$(get_file_size "${vending_cache_path}")"
  actual_vending_sha="$(calculate_sha256 "${vending_cache_path}")"

  local today
  today="$(date +%Y-%m-%d)"

  echo "Applying metadata rewrites across repository..."
  apply_project_metadata_updates \
    "${REPO_ROOT}" \
    "${module_version}" \
    "${version_code}" \
    "${semver}" \
    "${target_tag}" \
    "${gms_name}" \
    "${actual_gms_size}" \
    "${actual_gms_sha}" \
    "${vending_name}" \
    "${actual_vending_size}" \
    "${actual_vending_sha}" \
    "${today}"

  echo "Staging payloads via fetch-apks.sh..."
  "${REPO_ROOT}/scripts/fetch-apks.sh"

  echo "Building flashable Magisk module via build-module.sh..."
  "${REPO_ROOT}/scripts/build-module.sh"

  generate_checksum_files "${DIST_DIR}" "${module_version}"
  print_next_steps "${module_version}" "${target_tag}"
}

main "$@"
