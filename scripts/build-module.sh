#!/usr/bin/env bash
# build-module.sh - Package flashable Magisk module zip
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.env"

if [[ ! -f "${VERSIONS_FILE}" ]]; then
  echo "Error: versions.env not found at ${VERSIONS_FILE}" >&2
  exit 1
fi

# shellcheck source=../versions.env
. "${VERSIONS_FILE}"

DIST_DIR="${DIST_DIR:-"${REPO_ROOT}/dist"}"
VENDOR_DIR="${VENDOR_DIR:-"${REPO_ROOT}/vendor"}"
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-0}"

parse_arguments() {
  for arg in "$@"; do
    case "${arg}" in
      --skeleton|--dry-run)
        SKIP_DOWNLOAD=1
        ;;
      --help|-h)
        echo "Usage: $0 [--skeleton|--dry-run]"
        echo "Builds a flashable Magisk module zip in dist/."
        echo "Environment variables:"
        echo "  SKIP_DOWNLOAD=1   Build skeleton-only zip without requiring APKs."
        echo "  DIST_DIR=<path>   Override output directory."
        echo "  VENDOR_DIR=<path> Override vendor directory."
        exit 0
        ;;
      *)
        echo "Unknown argument: ${arg}" >&2
        exit 1
        ;;
    esac
  done
}

validate_metadata() {
  local prop_file="${REPO_ROOT}/module.prop"
  if [[ ! -f "${prop_file}" ]]; then
    echo "Error: module.prop not found." >&2
    return 1
  fi

  local prop_version prop_code
  prop_version="$(grep '^version=' "${prop_file}" | cut -d= -f2-)"
  prop_code="$(grep '^versionCode=' "${prop_file}" | cut -d= -f2-)"

  if [[ "${prop_version}" != "${MODULE_VERSION}" ]]; then
    echo "Error: Version mismatch! module.prop has '${prop_version}', versions.env specifies '${MODULE_VERSION}'." >&2
    return 1
  fi

  if [[ "${prop_code}" != "${MODULE_VERSION_CODE}" ]]; then
    echo "Error: versionCode mismatch! module.prop has '${prop_code}', versions.env specifies '${MODULE_VERSION_CODE}'." >&2
    return 1
  fi
}

verify_replace_marker() {
  local marker_file="$1"
  if [[ ! -f "${marker_file}" ]]; then
    echo "Error: Required .replace marker missing at ${marker_file}." >&2
    return 1
  fi
}

verify_skeleton_markers() {
  verify_replace_marker "${REPO_ROOT}/${GMS_TARGET_DIR}/.replace"
  verify_replace_marker "${REPO_ROOT}/${VENDING_TARGET_DIR}/.replace"
  verify_replace_marker "${REPO_ROOT}/${GMS_STD_TARGET_DIR}/.replace"
  verify_replace_marker "${REPO_ROOT}/${VENDING_STD_TARGET_DIR}/.replace"
}

stage_payload() {
  local src_apk="$1"
  local dest_path="$2"
  local component_name="$3"

  if [[ ! -f "${src_apk}" ]]; then
    echo "Error: ${component_name} not found at ${src_apk}." >&2
    echo "Run 'scripts/fetch-apks.sh' first, or use SKIP_DOWNLOAD=1 to build a skeleton zip." >&2
    return 1
  fi

  mkdir -p "$(dirname "${dest_path}")"
  cp "${src_apk}" "${dest_path}"
}

ensure_vendor_payloads() {
  local gms_src="$1"
  local vending_src="$2"

  if [[ -f "${gms_src}" && -f "${vending_src}" ]]; then
    return 0
  fi

  echo "Staged APKs not found in ${VENDOR_DIR}. Invoking fetch-apks.sh..."
  "${REPO_ROOT}/scripts/fetch-apks.sh"
}

stage_all_payloads() {
  local stage_dir="$1"

  if [[ "${SKIP_DOWNLOAD}" == "1" ]]; then
    echo "Notice: Skeleton mode active. Skipping APK payload staging."
    return 0
  fi

  local gms_src="${VENDOR_DIR}/${GMS_TARGET_NAME}"
  local vending_src="${VENDOR_DIR}/${VENDING_TARGET_NAME}"

  ensure_vendor_payloads "${gms_src}" "${vending_src}"

  stage_payload "${gms_src}" "${stage_dir}/${GMS_TARGET_DIR}/${GMS_TARGET_NAME}" "GmsCoreGo"
  stage_payload "${vending_src}" "${stage_dir}/${VENDING_TARGET_DIR}/${VENDING_TARGET_NAME}" "Phonesky (Go)"
  stage_payload "${gms_src}" "${stage_dir}/${GMS_STD_TARGET_DIR}/${GMS_STD_TARGET_NAME}" "GmsCore (Standard)"
  stage_payload "${vending_src}" "${stage_dir}/${VENDING_STD_TARGET_DIR}/${VENDING_STD_TARGET_NAME}" "Phonesky (Standard)"
}

copy_dir_marker() {
  local stage_dir="$1"
  local target_rel_dir="$2"

  mkdir -p "${stage_dir}/${target_rel_dir}"
  cp "${REPO_ROOT}/${target_rel_dir}/.replace" "${stage_dir}/${target_rel_dir}/"
}

copy_skeleton_files() {
  local stage_dir="$1"

  cp "${REPO_ROOT}/module.prop" "${stage_dir}/"
  cp "${REPO_ROOT}/customize.sh" "${stage_dir}/"
  cp "${REPO_ROOT}/uninstall.sh" "${stage_dir}/"
  cp "${REPO_ROOT}/sepolicy.rule" "${stage_dir}/"

  mkdir -p "${stage_dir}/META-INF/com/google/android"
  cp "${REPO_ROOT}/META-INF/com/google/android/update-binary" "${stage_dir}/META-INF/com/google/android/"
  cp "${REPO_ROOT}/META-INF/com/google/android/updater-script" "${stage_dir}/META-INF/com/google/android/"

  copy_dir_marker "${stage_dir}" "${GMS_TARGET_DIR}"
  copy_dir_marker "${stage_dir}" "${VENDING_TARGET_DIR}"
  copy_dir_marker "${stage_dir}" "${GMS_STD_TARGET_DIR}"
  copy_dir_marker "${stage_dir}" "${VENDING_STD_TARGET_DIR}"
}

create_zip() {
  local stage_dir="$1"
  local output_zip="$2"

  mkdir -p "$(dirname "${output_zip}")"
  rm -f "${output_zip}"

  (
    cd "${stage_dir}"
    zip -r -q "${output_zip}" .
  )

  zip -T "${output_zip}" >/dev/null
  echo "Package verified: ${output_zip} ($(wc -c < "${output_zip}") bytes)"
}

STAGE_DIR=""
cleanup_staging() {
  if [[ -n "${STAGE_DIR:-}" && -d "${STAGE_DIR}" ]]; then
    rm -rf "${STAGE_DIR}"
  fi
}
trap cleanup_staging EXIT

main() {
  parse_arguments "$@"
  validate_metadata
  verify_skeleton_markers

  STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/microg-build.XXXXXX")"

  copy_skeleton_files "${STAGE_DIR}"
  stage_all_payloads "${STAGE_DIR}"

  local zip_name="${MODULE_ID}-${MODULE_VERSION}.zip"
  if [[ "${SKIP_DOWNLOAD}" == "1" ]]; then
    zip_name="${MODULE_ID}-${MODULE_VERSION}-skeleton.zip"
  fi

  local output_zip="${DIST_DIR}/${zip_name}"
  create_zip "${STAGE_DIR}" "${output_zip}"

  echo "Build successful: ${output_zip}"
}

main "$@"
