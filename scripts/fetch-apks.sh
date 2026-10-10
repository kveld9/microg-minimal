#!/usr/bin/env bash
# fetch-apks.sh - Download and verify microG APKs based on versions.env
set -euo pipefail

# Dynamic path resolution (no hardcoded absolute paths)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.env"

if [[ ! -f "${VERSIONS_FILE}" ]]; then
  echo "Error: versions.env not found at ${VERSIONS_FILE}" >&2
  exit 1
fi

# Source authoritative version specifications
# shellcheck source=../versions.env
. "${VERSIONS_FILE}"

VENDOR_DIR="${VENDOR_DIR:-"${REPO_ROOT}/vendor"}"
CACHE_DIR="${CACHE_DIR:-"${XDG_CACHE_HOME:-"${HOME:-/tmp}/.cache"}/microg-minimal"}"

check_tool() {
  local tool_name="$1"
  if ! command -v "${tool_name}" >/dev/null 2>&1; then
    echo "Error: Required command '${tool_name}' is not installed." >&2
    return 1
  fi
  return 0
}

ensure_directories() {
  mkdir -p "${VENDOR_DIR}" "${CACHE_DIR}"
}

calculate_sha256() {
  local target_file="$1"
  sha256sum "${target_file}" | awk '{print $1}'
}

verify_sha256() {
  local target_file="$1"
  local expected_hash="$2"
  local component_name="$3"

  if [[ ! -f "${target_file}" ]]; then
    return 1
  fi

  local actual_hash
  actual_hash="$(calculate_sha256 "${target_file}")"

  if [[ "${actual_hash}" != "${expected_hash}" ]]; then
    echo "Error: SHA256 mismatch for ${component_name} (${target_file})" >&2
    echo "  Expected: ${expected_hash}" >&2
    echo "  Actual:   ${actual_hash}" >&2
    return 1
  fi

  echo "OK: ${component_name} SHA256 verified (${actual_hash})"
  return 0
}

download_to_cache() {
  local url="$1"
  local cache_file="$2"
  local part_file="${cache_file}.part"

  echo "Downloading: ${url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar --output "${part_file}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "${part_file}" "${url}"
  else
    echo "Error: Neither curl nor wget is available." >&2
    return 1
  fi

  mv "${part_file}" "${cache_file}"
}

fetch_payload() {
  local component_name="$1"
  local url="$2"
  local expected_hash="$3"
  local target_filename="$4"

  local dest_path="${VENDOR_DIR}/${target_filename}"
  local cache_path="${CACHE_DIR}/${target_filename}"

  # Reuse valid file if already in vendor directory
  if verify_sha256 "${dest_path}" "${expected_hash}" "${component_name}" 2>/dev/null; then
    echo "${component_name} is already present and valid in ${dest_path}."
    return 0
  fi

  # Check if cached file exists and is valid
  if ! verify_sha256 "${cache_path}" "${expected_hash}" "${component_name}" 2>/dev/null; then
    download_to_cache "${url}" "${cache_path}"
    if ! verify_sha256 "${cache_path}" "${expected_hash}" "${component_name}"; then
      rm -f "${cache_path}" "${cache_path}.part"
      echo "Error: Downloaded payload for ${component_name} failed hash verification." >&2
      return 1
    fi
  fi

  cp "${cache_path}" "${dest_path}"
  echo "Staged ${component_name} to ${dest_path}"
}

main() {
  check_tool sha256sum
  ensure_directories

  echo "Fetching microG artifacts defined in versions.env..."
  fetch_payload "GmsCore (${GMS_VERSION})" "${GMS_URL}" "${GMS_SHA256}" "${GMS_TARGET_NAME}"
  fetch_payload "Phonesky (${VENDING_VERSION})" "${VENDING_URL}" "${VENDING_SHA256}" "${VENDING_TARGET_NAME}"

  echo "All payloads fetched and verified successfully in ${VENDOR_DIR}."
}

main "$@"
