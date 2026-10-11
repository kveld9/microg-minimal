#!/usr/bin/env bash
# check-device.sh - Host-side ADB preflight device inspection
#
# Strictly READ-ONLY: Never modifies the connected device.
# Only inspects device state using non-destructive commands
# (getprop, pm list/path, dumpsys, test/ls).
# POSIX re-exec guard: Ensure execution under bash on the host system or on-device.
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  for _b in /data/data/com.termux/files/usr/bin/bash /system/bin/bash; do
    if [ -x "$_b" ]; then
      exec "$_b" "$0" "$@"
    fi
  done
  echo "Error: check-device.sh requires bash. Run 'bash scripts/check-device.sh' on host with ADB or in Termux with bash." >&2
  exit 1
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.env"

TARGET_SERIAL=""
IS_LOCAL_MODE=0
MIN_SDK_LEVEL=""
STOCK_DIRS_FOUND=0
GSF_DIR_FOUND=0
GOOGLE_PKGS_FOUND=0
BLOCKING_VERDICT=0
FAILING_CHECK=""

DEVICE_MODEL=""
DEVICE_CODENAME=""
DEVICE_SDK_LEVEL=""
ROOT_MANAGER_FINDING="None detected"

declare -a DATA_UPDATE_PKGS=()
declare -a SYSTEM_BASE_PKGS=()
declare -a DETECTED_STOCK_DIRS=()
declare -a DETECTED_STOCK_PKGS=()

print_usage() {
  cat <<'EOF'
Usage: check-device.sh [OPTIONS]

ADB / on-device preflight device inspection for microG Minimal.
Strictly READ-ONLY: This script never modifies the connected device. It only
queries device properties (getprop, pm list/path, dumpsys, test/ls) to verify
compatibility and detect conflicting stock packages.
Supports both host ADB mode (PC connected via USB) and local on-device mode (rooted shell / Termux).

Options:
  --local                Run directly on-device using local Android tools (Termux / root shell).
  -s, --serial <SERIAL>  Target specific ADB device serial number (host mode).
  -h, --help             Display this help message and exit.
EOF
}

handle_local_arg() {
  IS_LOCAL_MODE=1
  if [[ -n "${TARGET_SERIAL}" ]]; then
    echo "Notice: Running in local on-device mode; ignoring serial '${TARGET_SERIAL}'." >&2
    TARGET_SERIAL=""
  fi
}

handle_serial_arg() {
  local serial_val="$1"
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]]; then
    echo "Notice: Running in local on-device mode; ignoring serial '${serial_val}'." >&2
    return 0
  fi
  TARGET_SERIAL="${serial_val}"
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_usage
        exit 0
        ;;
      --local)
        handle_local_arg
        shift
        ;;
      -s|--serial)
        if [[ $# -lt 2 ]]; then
          echo "Error: Missing serial argument for $1" >&2
          exit 1
        fi
        handle_serial_arg "$2"
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
  if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck source=../versions.env
    . "${VERSIONS_FILE}"
    return 0
  fi

  # versions.env remains the single source of truth; fallback exists solely for standalone on-device copies.
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]] || is_local_android_env; then
    echo "Warning: versions.env not found; operating in standalone mode using built-in SDK defaults." >&2
    return 0
  fi

  echo "Error: versions.env not found at ${VERSIONS_FILE}" >&2
  exit 1
}

parse_template_min_sdk_level() {
  local template_file="${REPO_ROOT}/customize.sh.template"
  if [[ ! -f "${template_file}" ]]; then
    return 1
  fi
  grep -E 'if \[ "\$API" -lt [0-9]+ \]; then' "${template_file}" | grep -o -E '[0-9]+' | head -n 1
}

resolve_min_sdk_level() {
  if [[ -n "${MODULE_MIN_API:-}" ]]; then
    MIN_SDK_LEVEL="${MODULE_MIN_API}"
    return 0
  fi

  local parsed
  parsed="$(parse_template_min_sdk_level || true)"
  if [[ -n "${parsed}" ]]; then
    MIN_SDK_LEVEL="${parsed}"
    return 0
  fi

  # versions.env remains the single source of truth; fallback exists solely for standalone on-device copies.
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]]; then
    echo "Warning: Unable to parse API floor from versions.env or template; falling back to default SDK floor 27." >&2
    MIN_SDK_LEVEL="27"
    return 0
  fi

  echo "Error: Failed to resolve minimum SDK level from versions.env or customize.sh.template" >&2
  exit 1
}

has_local_android_tools() {
  command -v getprop >/dev/null 2>&1 && command -v pm >/dev/null 2>&1
}

is_local_android_env() {
  ! command -v adb >/dev/null 2>&1 && has_local_android_tools
}

detect_transport_mode() {
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]]; then
    return 0
  fi
  if is_local_android_env; then
    IS_LOCAL_MODE=1
    echo "Notice: ADB binary not found, but local Android tools detected. Enabling local on-device mode." >&2
  fi
}

exec_local_cmd() {
  if [[ $# -gt 0 && "$1" == "shell" ]]; then
    shift
  fi
  if [[ $# -eq 1 ]]; then
    sh -c "$1"
    return $?
  fi
  "$@"
}

adb_cmd() {
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]]; then
    exec_local_cmd "$@"
    return $?
  fi
  if [[ -n "${TARGET_SERIAL:-}" ]]; then
    adb -s "${TARGET_SERIAL}" "$@"
    return $?
  fi
  adb "$@"
}

check_adb_binary() {
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]]; then
    return 0
  fi
  if ! command -v adb >/dev/null 2>&1; then
    echo "[FAIL] ADB binary not found on PATH." >&2
    echo "Install ADB via your package manager (e.g. android-tools) or Android SDK Platform-Tools." >&2
    echo "If running directly on an Android device (e.g. Termux), run with --local." >&2
    return 1
  fi
  return 0
}

check_adb_device() {
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]]; then
    echo "Notice: Running in local on-device mode; skipping ADB device authorization check."
    return 0
  fi
  local state_out
  state_out="$(adb_cmd get-state 2>&1 | tr -d '\r' || true)"

  if echo "${state_out}" | grep -q "unauthorized"; then
    echo "[FAIL] Connected ADB device is unauthorized." >&2
    echo "Unlock device screen and accept the USB debugging authorization prompt." >&2
    return 1
  fi

  if [[ "${state_out}" != "device" ]]; then
    if [[ -z "${TARGET_SERIAL:-}" ]] && has_local_android_tools; then
      IS_LOCAL_MODE=1
      echo "Notice: No authorized ADB device found (${state_out}), but local Android tools detected. Falling back to local on-device mode." >&2
      return 0
    fi
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

check_sdk_level() {
  local sdk_val
  sdk_val="$(adb_cmd shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
  DEVICE_SDK_LEVEL="${sdk_val}"

  if [[ -z "${sdk_val}" || ! "${sdk_val}" =~ ^[0-9]+$ ]]; then
    echo "[FAIL] Unable to read Android SDK API level from device." >&2
    FAILING_CHECK="Unable to read Android SDK API level from device"
    return 1
  fi

  if (( sdk_val < MIN_SDK_LEVEL )); then
    echo "[FAIL] Android API level: ${sdk_val} (below minimum floor ${MIN_SDK_LEVEL}). Incompatible device."
    FAILING_CHECK="Android API level ${sdk_val} is below minimum floor (${MIN_SDK_LEVEL})"
    return 1
  fi

  echo "[PASS] Android API level: ${sdk_val} (meets minimum floor: ${MIN_SDK_LEVEL})"
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

  GOOGLE_PKGS_FOUND=1
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

check_nikgapps_packages() {
  local packages="$1"
  local nik_list
  nik_list="$(echo "${packages}" | grep "package:com.nikgapps.overlay\." | sed 's/package://' || true)"

  [[ -z "${nik_list}" ]] && return 0

  while IFS= read -r nik_pkg; do
    [[ -z "${nik_pkg}" ]] && continue
    echo "[WARN] GApps overlay package detected: ${nik_pkg} (NikGapps)"
    SYSTEM_BASE_PKGS+=("${nik_pkg}")
  done <<< "${nik_list}"
}

check_bitgapps_packages() {
  local packages="$1"
  local bit_list
  bit_list="$(echo "${packages}" | grep "package:com.bitgapps\." | sed 's/package://' || true)"

  [[ -z "${bit_list}" ]] && return 0

  while IFS= read -r bit_pkg; do
    [[ -z "${bit_pkg}" ]] && continue
    echo "[WARN] GApps overlay package detected: ${bit_pkg} (BitGapps)"
    SYSTEM_BASE_PKGS+=("${bit_pkg}")
  done <<< "${bit_list}"
}

check_opengapps_marker() {
  local prop_exists
  prop_exists="$(adb_cmd shell "[ -f /system/etc/g.prop ] && echo 1 || echo 0" 2>/dev/null | tr -d '\r' || echo "0")"
  [[ "${prop_exists}" != "1" ]] && return 0

  local addon_type
  addon_type="$(adb_cmd shell "grep '^ro.addon.type=' /system/etc/g.prop 2>/dev/null | cut -d= -f2" | tr -d '\r' || true)"
  local type_desc="${addon_type:-gapps}"

  echo "[WARN] GApps marker detected: /system/etc/g.prop (OpenGapps, type: ${type_desc})"
  SYSTEM_BASE_PKGS+=("OpenGapps (/system/etc/g.prop)")
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
    "/${GMS_TARGET_DIR:-system/priv-app/GmsCoreGo}"
    "/${VENDING_TARGET_DIR:-system/priv-app/Phonesky}"
    "/${GMS_LEGACY_TARGET_DIR:-system/priv-app/PrebuiltGmsCore}"
    "/${GMS_LEGACY_PI_TARGET_DIR:-system/priv-app/PrebuiltGmsCorePi}"
    "/${GMS_LEGACY_PIX_TARGET_DIR:-system/priv-app/PrebuiltGmsCorePix}"
    "/${GMS_PROD_LEGACY_TARGET_DIR:-system/product/priv-app/PrebuiltGmsCore}"
    "/${GMS_STD_TARGET_DIR:-system/product/priv-app/GmsCore}"
    "/${VENDING_STD_TARGET_DIR:-system/product/priv-app/Phonesky}"
    "/product/priv-app/PrebuiltGmsCore"
    "/product/priv-app/GmsCore"
    "/product/priv-app/Phonesky"
    "/system/priv-app/GoogleServicesFramework"
    "/product/priv-app/GoogleServicesFramework"
  )

  for d in "${dirs[@]}"; do
    check_single_stock_dir "${d}"
  done

  if [[ "${STOCK_DIRS_FOUND}" -gt 0 ]]; then
    return 0
  fi

  if [[ "${GOOGLE_PKGS_FOUND}" -eq 0 ]]; then
    echo "[PASS] Stock overlay directories: None detected (clean device, nothing to suppress)"
    return 0
  fi

  echo "[FAIL] Stock overlay directories: None detected (unsupported or unrecognized partition layout)"
  return 1
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

get_pm_cmd_prefix() {
  if [[ "${IS_LOCAL_MODE}" -eq 1 ]]; then
    echo "pm"
    return 0
  fi
  echo "adb shell pm"
}

print_uninstall_commands() {
  local cmd_prefix
  cmd_prefix="$(get_pm_cmd_prefix)"

  echo "Active /data package updates detected! Run these commands to prevent downgrade conflicts:"
  for pkg in "$@"; do
    echo "  ${cmd_prefix} uninstall --user 0 ${pkg}"
  done
  echo ""
}

print_gsf_data_note() {
  for pkg in "${DATA_UPDATE_PKGS[@]}"; do
    if [[ "${pkg}" == "com.google.android.gsf" ]]; then
      echo "Notice: com.google.android.gsf /data update detected (not suppressed by module; clean flash required)."
      echo ""
      return 0
    fi
  done
}

print_data_update_cleanup() {
  local uninstall_pkgs=()
  for pkg in "${DATA_UPDATE_PKGS[@]}"; do
    case "${pkg}" in
      com.google.android.gms|com.android.vending)
        uninstall_pkgs+=("${pkg}")
        ;;
    esac
  done

  if [[ ${#uninstall_pkgs[@]} -gt 0 ]]; then
    print_uninstall_commands "${uninstall_pkgs[@]}"
  elif [[ ${#DATA_UPDATE_PKGS[@]} -eq 0 ]]; then
    echo "No conflicting /data package updates detected."
    echo ""
  fi

  print_gsf_data_note
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
  echo "- **Android API Level:** ${DEVICE_SDK_LEVEL:-unknown} (Floor: ${MIN_SDK_LEVEL})"
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

  check_sdk_level || BLOCKING_VERDICT=1
  detect_root_traces "${packages_cache}"
  check_stock_packages
  check_mindthegapps_packages "${packages_cache}"
  check_nikgapps_packages "${packages_cache}"
  check_bitgapps_packages "${packages_cache}"
  check_opengapps_marker

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
  detect_transport_mode
  resolve_min_sdk_level

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
