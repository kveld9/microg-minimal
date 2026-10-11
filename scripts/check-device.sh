#!/usr/bin/env bash
# check-device.sh - Host-side ADB preflight device inspection
#
# Strictly READ-ONLY: Never modifies the connected device.
# Only inspects device state using non-destructive commands
# (getprop, pm list/path, dumpsys, test/ls).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.env"

TARGET_SERIAL=""
API_FLOOR=""
STOCK_DIRS_FOUND=0
GSF_DIR_FOUND=0
BLOCKING_VERDICT=0
FAILING_CHECK=""

DEVICE_MODEL=""
DEVICE_CODENAME=""
DEVICE_API=""
ROOT_MANAGER_FINDING="None detected"

declare -a DATA_UPDATE_PKGS=()
declare -a SYSTEM_BASE_PKGS=()
declare -a DETECTED_STOCK_DIRS=()
declare -a DETECTED_STOCK_PKGS=()

print_usage() {
  cat <<'EOF'
Usage: check-device.sh [OPTIONS]

Host-side ADB preflight device inspection for microG Minimal.
Strictly READ-ONLY: This script never modifies the connected device. It only
queries device properties (getprop, pm list/path, dumpsys, test/ls) to verify
compatibility and detect conflicting stock packages.

Options:
  -s, --serial <SERIAL>  Target specific ADB device serial number.
  -h, --help             Display this help message and exit.
EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_usage
        exit 0
        ;;
      -s|--serial)
        if [[ $# -lt 2 ]]; then
          echo "Error: Missing serial argument for $1" >&2
          exit 1
        fi
        TARGET_SERIAL="$2"
        shift 2
        ;;
      *)
        echo "Error: Unknown argument '$1'" >&2
        print_usage >&2
        exit 1
        ;;
    esac
  done
}

load_environment() {
  if [[ ! -f "${VERSIONS_FILE}" ]]; then
    echo "Error: versions.env not found at ${VERSIONS_FILE}" >&2
    exit 1
  fi
  # shellcheck source=../versions.env
  . "${VERSIONS_FILE}"
}

parse_template_api_floor() {
  local template_file="${REPO_ROOT}/customize.sh.template"
  if [[ ! -f "${template_file}" ]]; then
    return 1
  fi
  grep -E 'if \[ "\$API" -lt [0-9]+ \]; then' "${template_file}" | grep -o -E '[0-9]+' | head -n 1
}

resolve_api_floor() {
  if [[ -n "${MODULE_MIN_API:-}" ]]; then
    API_FLOOR="${MODULE_MIN_API}"
    return 0
  fi

  local parsed
  parsed="$(parse_template_api_floor || true)"
  if [[ -n "${parsed}" ]]; then
    API_FLOOR="${parsed}"
    return 0
  fi

  echo "Error: Failed to resolve API floor from versions.env or customize.sh.template" >&2
  exit 1
}

adb_cmd() {
  if [[ -n "${TARGET_SERIAL:-}" ]]; then
    adb -s "${TARGET_SERIAL}" "$@"
    return $?
  fi
  adb "$@"
}

check_adb_binary() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "[FAIL] ADB binary not found on PATH." >&2
    echo "Install ADB via your package manager (e.g. android-tools) or Android SDK Platform-Tools." >&2
    return 1
  fi
  return 0
}

check_adb_device() {
  local state_out
  state_out="$(adb_cmd get-state 2>&1 | tr -d '\r' || true)"

  if echo "${state_out}" | grep -q "unauthorized"; then
    echo "[FAIL] Connected ADB device is unauthorized." >&2
    echo "Unlock device screen and accept the USB debugging authorization prompt." >&2
    return 1
  fi

  if [[ "${state_out}" != "device" ]]; then
    echo "[FAIL] No authorized ADB device detected (${state_out})." >&2
    echo "Connect device via USB, enable Developer Options and USB Debugging in device Settings." >&2
    return 1
  fi

  return 0
}

collect_device_info() {
  DEVICE_MODEL="$(adb_cmd shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
  DEVICE_CODENAME="$(adb_cmd shell getprop ro.product.device 2>/dev/null | tr -d '\r' || true)"
}

check_api_level() {
  local api_val
  api_val="$(adb_cmd shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
  DEVICE_API="${api_val}"

  if [[ -z "${api_val}" || ! "${api_val}" =~ ^[0-9]+$ ]]; then
    echo "[FAIL] Unable to read Android SDK API level from device." >&2
    FAILING_CHECK="Unable to read Android SDK API level from device"
    return 1
  fi

  if (( api_val < API_FLOOR )); then
    echo "[FAIL] Android API level: ${api_val} (below minimum floor ${API_FLOOR}). Incompatible device."
    FAILING_CHECK="Android API level ${api_val} is below minimum floor (${API_FLOOR})"
    return 1
  fi

  echo "[PASS] Android API level: ${api_val} (meets minimum floor: ${API_FLOOR})"
  return 0
}

detect_magisk() {
  local packages="$1"
  local prop
  prop="$(adb_cmd shell getprop ro.magisk.version 2>/dev/null | tr -d '\r' || true)"
  [[ -n "${prop}" ]] && return 0
  echo "${packages}" | grep -q "package:com.topjohnwu.magisk" && return 0
  local su_ver
  su_ver="$(adb_cmd shell su -v 2>/dev/null | tr -d '\r' || true)"
  [[ "${su_ver,,}" =~ magisk ]]
}

detect_kernelsu() {
  local packages="$1"
  echo "${packages}" | grep -q -E "package:(me\.weishu\.kernelsu|io\.github\.a13e300\.ksu)" && return 0
  local uname_out
  uname_out="$(adb_cmd shell uname -r 2>/dev/null | tr -d '\r' || true)"
  [[ "${uname_out,,}" =~ ksu ]] && return 0
  local su_ver
  su_ver="$(adb_cmd shell su -v 2>/dev/null | tr -d '\r' || true)"
  [[ "${su_ver,,}" =~ kernelsu ]]
}

detect_apatch() {
  local packages="$1"
  local prop
  prop="$(adb_cmd shell getprop ro.apatch.version 2>/dev/null | tr -d '\r' || true)"
  [[ -n "${prop}" ]] && return 0
  echo "${packages}" | grep -q "package:me.bmax.apatch" && return 0
  local su_ver
  su_ver="$(adb_cmd shell su -v 2>/dev/null | tr -d '\r' || true)"
  [[ "${su_ver,,}" =~ apatch ]]
}

detect_root_traces() {
  local packages="$1"
  local detected=()

  detect_magisk "${packages}" && detected+=("Magisk")
  detect_kernelsu "${packages}" && detected+=("KernelSU")
  detect_apatch "${packages}" && detected+=("APatch")

  if [[ ${#detected[@]} -gt 0 ]]; then
    local names
    names="$(IFS=, ; echo "${detected[*]}")"
    ROOT_MANAGER_FINDING="${names}"
    echo "[PASS] Root manager detected: ${names}"
    return 0
  fi

  ROOT_MANAGER_FINDING="None detected"
  echo "[WARN] Root manager: No Magisk, KernelSU, or APatch traces detected (flashing requires root manager)"
  return 0
}

get_dumpsys_codepaths() {
  local pkg="$1"
  adb_cmd shell dumpsys package "${pkg}" 2>/dev/null | grep -E "codePath=" | tr -d '\r' || true
}

resolve_package_path() {
  local pkg="$1"
  local pm_path
  pm_path="$(adb_cmd shell pm path "${pkg}" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "${pm_path}" ]]; then
    echo "${pm_path}"
    return 0
  fi
  get_dumpsys_codepaths "${pkg}"
}

inspect_single_package() {
  local pkg="$1"
  local path_out
  path_out="$(resolve_package_path "${pkg}")"

  if [[ -z "${path_out}" ]]; then
    echo "[PASS] Stock package ${pkg}: Not installed"
    return 0
  fi

  local ver_out
  ver_out="$(adb_cmd shell dumpsys package "${pkg}" 2>/dev/null | grep -m 1 "versionName=" | sed 's/.*versionName=//' | tr -d '\r' || true)"
  local ver_desc="${ver_out:-unknown}"

  DETECTED_STOCK_PKGS+=("${pkg} (${ver_desc})")

  if echo "${path_out}" | grep -q "/data/app/"; then
    echo "[WARN] Stock package ${pkg}: Installed (/data update detected, version: ${ver_desc})"
    DATA_UPDATE_PKGS+=("${pkg}")
    return 0
  fi

  echo "[WARN] Stock package ${pkg}: Installed (system-only package, version: ${ver_desc})"
  SYSTEM_BASE_PKGS+=("${pkg}")
  return 0
}

check_stock_packages() {
  inspect_single_package "com.google.android.gms"
  inspect_single_package "com.android.vending"
  inspect_single_package "com.google.android.gsf"
}

check_mindthegapps_packages() {
  local packages="$1"
  local mtg_list
  mtg_list="$(echo "${packages}" | grep "package:com.mtg\." | sed 's/package://' || true)"

  [[ -z "${mtg_list}" ]] && return 0

  while IFS= read -r mtg_pkg; do
    [[ -z "${mtg_pkg}" ]] && continue
    echo "[WARN] GApps overlay package detected: ${mtg_pkg} (MindTheGapps)"
    SYSTEM_BASE_PKGS+=("${mtg_pkg}")
  done <<< "${mtg_list}"
}

check_single_stock_dir() {
  local dir_path="$1"
  local exists_val
  exists_val="$(adb_cmd shell "[ -d '${dir_path}' ] && echo 1 || echo 0" 2>/dev/null | tr -d '\r' || echo "0")"

  [[ "${exists_val}" != "1" ]] && return 0

  DETECTED_STOCK_DIRS+=("${dir_path}")

  if [[ "${dir_path}" =~ GoogleServicesFramework ]]; then
    echo "[WARN] Stock GSF directory present: ${dir_path} (not suppressed by module; clean flash required)"
    GSF_DIR_FOUND=1
    return 0
  fi

  echo "[WARN] Stock directory present: ${dir_path} (will be suppressed by module .replace overlay)"
  STOCK_DIRS_FOUND=1
}

check_stock_directories() {
  local dirs=(
    "/${GMS_TARGET_DIR}"
    "/${VENDING_TARGET_DIR}"
    "/${GMS_LEGACY_TARGET_DIR}"
    "/${GMS_STD_TARGET_DIR}"
    "/${VENDING_STD_TARGET_DIR}"
    "/product/priv-app/GmsCore"
    "/product/priv-app/Phonesky"
    "/system/priv-app/GoogleServicesFramework"
    "/product/priv-app/GoogleServicesFramework"
  )

  for d in "${dirs[@]}"; do
    check_single_stock_dir "${d}"
  done

  if [[ "${STOCK_DIRS_FOUND}" -eq 0 ]]; then
    echo "[FAIL] Stock overlay directories: None detected (unsupported or unrecognized partition layout)"
    return 1
  fi

  return 0
}

check_microg_conflicts() {
  local packages="$1"
  local conflict_pkgs
  conflict_pkgs="$(echo "${packages}" | grep -E "package:(org\.microg\.gms\.core|com\.fake\.store|org\.microg\.fakefakes)" | tr '\n' ' ' || true)"

  if [[ -n "${conflict_pkgs}" ]]; then
    echo "[WARN] Conflicting microG/FakeStore package(s) detected: ${conflict_pkgs}"
    return 0
  fi

  echo "[PASS] Conflicting standalone microG/FakeStore packages: None detected"
}

check_signature_spoofing() {
  echo "[WARN] Signature spoofing: UNKNOWN (ADB cannot verify signature spoofing; check microG Self-Check app after reboot)"
}

print_data_update_cleanup() {
  if [[ ${#DATA_UPDATE_PKGS[@]} -eq 0 ]]; then
    echo "No conflicting /data package updates detected."
    echo ""
    return 0
  fi

  echo "Active /data package updates detected! Run these commands to prevent downgrade conflicts:"
  for pkg in "${DATA_UPDATE_PKGS[@]}"; do
    echo "  adb shell pm uninstall --user 0 ${pkg}"
    echo "  adb shell pm clear ${pkg}"
  done
  echo ""
}

print_system_cleanup_note() {
  if [[ ${#SYSTEM_BASE_PKGS[@]} -eq 0 && "${GSF_DIR_FOUND}" -eq 0 ]]; then
    return 0
  fi

  echo "Stock system-base packages or monolithic GApps (e.g. GSF, MindTheGapps) detected:"
  echo "  Notice: Stock system packages cannot be uninstalled via 'pm uninstall'."
  echo "  While this module suppresses stock GmsCore and Phonesky directories,"
  echo "  ROMs with monolithic GApps or conflicting system-base components require"
  echo "  a clean ROM reflash without GApps (Vanilla ROM) prior to installing."
  echo ""
}

print_cleanup_summary() {
  echo ""
  echo "=================================================="
  echo " Preflight Cleanup Guidance"
  echo "=================================================="
  print_data_update_cleanup
  print_system_cleanup_note
  echo "Summary:"
  echo "- If /data updates were listed above, execute the uninstall commands before flashing."
  echo "- After flashing this module and rebooting, open microG Settings -> Self-Check to verify spoofing."
  echo "=================================================="
}

derive_issues_url() {
  local repo_slug=""
  if [[ -f "${REPO_ROOT}/update.json" ]]; then
    repo_slug="$(sed -n 's|.*github\.com/\([^/]*\)/\([^/]*\)/.*|\1/\2|p' "${REPO_ROOT}/update.json" | head -n 1)"
  fi
  if [[ -z "${repo_slug}" && -f "${REPO_ROOT}/module.prop" ]]; then
    repo_slug="$(sed -n 's|.*githubusercontent\.com/\([^/]*\)/\([^/]*\)/.*|\1/\2|p' "${REPO_ROOT}/module.prop" | head -n 1)"
  fi
  if [[ -n "${repo_slug}" ]]; then
    echo "https://github.com/${repo_slug}/issues"
    return 0
  fi
  echo "https://github.com/issues"
}

print_support_report() {
  local issues_url
  issues_url="$(derive_issues_url)"

  local dirs_str="None detected"
  if [[ ${#DETECTED_STOCK_DIRS[@]} -gt 0 ]]; then
    dirs_str="$(IFS=, ; echo "${DETECTED_STOCK_DIRS[*]}")"
  fi

  local pkgs_str="None detected"
  if [[ ${#DETECTED_STOCK_PKGS[@]} -gt 0 ]]; then
    pkgs_str="$(IFS=, ; echo "${DETECTED_STOCK_PKGS[*]}")"
  fi

  echo ""
  echo '```markdown'
  echo "### DEVICE SUPPORT REPORT"
  echo "- **Module Version:** ${MODULE_VERSION:-unknown}"
  echo "- **Device Model:** ${DEVICE_MODEL:-unknown}"
  echo "- **Device Codename:** ${DEVICE_CODENAME:-unknown}"
  echo "- **Android API Level:** ${DEVICE_API:-unknown} (Floor: ${API_FLOOR})"
  echo "- **Root Manager:** ${ROOT_MANAGER_FINDING:-None detected}"
  echo "- **Detected Stock Dirs:** ${dirs_str}"
  echo "- **Detected Stock Packages:** ${pkgs_str}"
  echo "- **Failing Check:** ${FAILING_CHECK}"
  echo '```'
  echo ""
  echo "To request support for this layout, open an issue with the report above:"
  echo "  ${issues_url}"
  echo ""
}

run_all_inspections() {
  local packages_cache
  packages_cache="$(adb_cmd shell pm list packages 2>/dev/null | tr -d '\r' || true)"

  check_api_level || BLOCKING_VERDICT=1
  detect_root_traces "${packages_cache}"
  check_stock_packages
  check_mindthegapps_packages "${packages_cache}"

  if ! check_stock_directories; then
    if [[ "${BLOCKING_VERDICT}" -eq 0 ]]; then
      FAILING_CHECK="No suppressible stock overlay directories detected on device partitions (unknown partition layout)"
      BLOCKING_VERDICT=1
    fi
  fi

  check_microg_conflicts "${packages_cache}"
  check_signature_spoofing
}

main() {
  parse_arguments "$@"
  load_environment
  resolve_api_floor

  check_adb_binary || exit 1
  check_adb_device || exit 1

  echo "=================================================="
  echo " microG Minimal - Device Preflight Check"
  echo "=================================================="

  collect_device_info
  run_all_inspections
  print_cleanup_summary

  if [[ "${BLOCKING_VERDICT}" -ne 0 ]]; then
    print_support_report
    echo "Preflight check FAILED: Blocking incompatibility detected." >&2
    exit 1
  fi

  echo "Preflight check completed."
  exit 0
}

main "$@"
