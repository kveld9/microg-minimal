#!/usr/bin/env bash
# update.sh - Single entrypoint for upstream microG checking and automated updating
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
ASSUME_YES=0
OUTPUT_JSON=0

print_usage() {
  cat <<'EOF'
Usage: update.sh [TAG] [OPTIONS]

Single entry-point command for microG Minimal upstream release updates.

By default (no flags), checks for the latest upstream release. If up-to-date,
it reports status and exits 0. If an update is available, it displays the release
summary and asks for confirmation before downloading assets, rewriting metadata,
and building the flashable module package.

Arguments:
  TAG             Target an explicit upstream release tag (e.g., v0.3.18.252432).

Options:
  --latest        Explicitly check against latest upstream release (default).
  --check         Read-only status check; never writes files. Exits 0 if up-to-date,
                  2 if an update is available.
  --yes, -y       Skip interactive confirmation prompt (non-interactive mode).
  --dry-run       Preview planned metadata changes without writing files.
  --json          Output check status in machine-readable JSON format.
  --help, -h      Display this help message and exit.
EOF
}

parse_arguments() {
  for arg in "$@"; do
    case "${arg}" in
      --check)
        CHECK_ONLY=1
        ;;
      --yes|-y)
        ASSUME_YES=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --json)
        OUTPUT_JSON=1
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

print_json_summary() {
  local current_tag="$1"
  local target_tag="$2"
  local is_update="$3"
  local release_json="$4"

  python3 -c '
import sys, json

current_tag = sys.argv[1]
target_tag = sys.argv[2]
is_update = (sys.argv[3] == "true")
release_data = json.loads(sys.argv[4])

output = {
    "current_tag": current_tag,
    "target_tag": target_tag,
    "update_available": is_update,
    "gms_asset": release_data.get("gms_name"),
    "gms_url": release_data.get("gms_url"),
    "gms_size": release_data.get("gms_size"),
    "vending_asset": release_data.get("vending_name"),
    "vending_url": release_data.get("vending_url"),
    "vending_size": release_data.get("vending_size")
}

print(json.dumps(output, indent=2))
' "${current_tag}" "${target_tag}" "${is_update}" "${release_json}"
}

print_text_summary() {
  local current_tag="$1"
  local target_tag="$2"
  local is_update="$3"
  local gms_name="$4"
  local gms_url="$5"
  local gms_size="$6"
  local vending_name="$7"
  local vending_url="$8"
  local vending_size="$9"

  echo "=================================================="
  echo " microG Upstream Release Status"
  echo "=================================================="
  echo "Current module tag:  ${current_tag}"
  echo "Target upstream tag: ${target_tag}"
  echo ""
  if [[ "${is_update}" == "true" ]]; then
    echo "Status: UPDATE AVAILABLE"
    echo ""
    echo "Resolved Upstream Assets:"
    echo "  - GmsCore:  ${gms_name} (${gms_size} bytes)"
    echo "    URL:      ${gms_url}"
    echo "  - Phonesky: ${vending_name} (${vending_size} bytes)"
    echo "    URL:      ${vending_url}"
  else
    echo "Status: UP-TO-DATE (No update needed)"
  fi
  echo "=================================================="
}

confirm_update() {
  local target_tag="$1"
  if [[ "${ASSUME_YES}" -eq 1 ]]; then
    return 0
  fi

  local reply=""
  read -r -p "Proceed with update to ${target_tag}? [y/N] " reply || true
  case "${reply}" in
    [yY]|[yY][eE][sS])
      return 0
      ;;
    *)
      echo "Update cancelled."
      return 1
      ;;
  esac
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
  echo " microG Update Dry-Run Preview (No Writes)"
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

execute_update_pipeline() {
  local module_version="$1"
  local version_code="$2"
  local semver="$3"
  local target_tag="$4"
  local gms_name="$5"
  local gms_url="$6"
  local gms_size="$7"
  local vending_name="$8"
  local vending_url="$9"
  local vending_size="${10}"

  local gms_cache_path vending_cache_path
  gms_cache_path="$(ensure_cached_asset "${CACHE_DIR}" "${gms_url}" "${gms_name}" "${gms_size}")"
  vending_cache_path="$(ensure_cached_asset "${CACHE_DIR}" "${vending_url}" "${vending_name}" "${vending_size}")"

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

main() {
  parse_arguments "$@"
  load_versions_file

  local current_tag="${GMS_RELEASE_TAG}"
  local release_json
  release_json="$(resolve_upstream_release "${TARGET}")" || exit 1

  local target_tag gms_name gms_url gms_size vending_name vending_url vending_size
  target_tag="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("tag_name"))' "${release_json}")"
  gms_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_name"))' "${release_json}")"
  gms_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_url"))' "${release_json}")"
  gms_size="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_size", ""))' "${release_json}")"
  vending_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_name"))' "${release_json}")"
  vending_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_url"))' "${release_json}")"
  vending_size="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_size", ""))' "${release_json}")"

  local is_update="false"
  if [[ "${current_tag}" != "${target_tag}" ]]; then
    is_update="true"
  fi

  if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    if [[ "${OUTPUT_JSON}" -eq 1 ]]; then
      print_json_summary "${current_tag}" "${target_tag}" "${is_update}" "${release_json}"
    else
      print_text_summary "${current_tag}" "${target_tag}" "${is_update}" \
        "${gms_name}" "${gms_url}" "${gms_size}" \
        "${vending_name}" "${vending_url}" "${vending_size}"
    fi
    if [[ "${is_update}" == "true" ]]; then
      exit 2
    fi
    exit 0
  fi

  local version_info semver module_version version_code
  version_info="$(derive_version_info "${target_tag}")"
  semver="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("semver"))' "${version_info}")"
  module_version="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("module_version"))' "${version_info}")"
  version_code="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("version_code"))' "${version_info}")"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    execute_dry_run "${module_version}" "${version_code}" "${target_tag}" \
      "${gms_name}" "${gms_size}" "${vending_name}" "${vending_size}"
    exit 0
  fi

  if [[ "${is_update}" == "false" && "${TARGET}" == "latest" ]]; then
    print_text_summary "${current_tag}" "${target_tag}" "false" \
      "${gms_name}" "${gms_url}" "${gms_size}" \
      "${vending_name}" "${vending_url}" "${vending_size}"
    exit 0
  fi

  print_text_summary "${current_tag}" "${target_tag}" "${is_update}" \
    "${gms_name}" "${gms_url}" "${gms_size}" \
    "${vending_name}" "${vending_url}" "${vending_size}"

  if ! confirm_update "${target_tag}"; then
    exit 0
  fi

  execute_update_pipeline \
    "${module_version}" "${version_code}" "${semver}" "${target_tag}" \
    "${gms_name}" "${gms_url}" "${gms_size}" \
    "${vending_name}" "${vending_url}" "${vending_size}"
}

main "$@"
