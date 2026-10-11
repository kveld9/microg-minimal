#!/system/bin/sh
# customize.sh - Module installation customization script
# Sourced by the module installer (Magisk, KernelSU family, APatch) after
# files are extracted. Uses only the portable installer contract
# (MODPATH, API, ARCH, ui_print, abort, set_perm_recursive).

# Directory replacement list for OverlayFS-based managers
# (KernelSU family, APatch). Their installers replace these stock
# directories with the module copies. Magisk ignores this variable and
# uses the .replace marker files shipped in the module instead.
REPLACE="
/system/priv-app/GmsCoreGo
/system/priv-app/Phonesky
/system/product/priv-app/GmsCore
/system/product/priv-app/Phonesky
/product/priv-app/GmsCore
/product/priv-app/Phonesky
"

print_banner() {
  ui_print "****************************************"
  ui_print " microG Minimal - Split-APK Suppressor  "
  ui_print " Target: Android 9+ (Go & Standard)     "
  ui_print "****************************************"
}

validate_sdk() {
  if [ -z "$API" ]; then
    ui_print "- Warning: API level not detected from environment."
    return 0
  fi

  if [ "$API" -lt 28 ]; then
    abort "! SDK $API detected. Android 9+ (API 28+) is required."
  fi

  if [ "$API" -gt 28 ]; then
    ui_print "- Notice: Detected API $API. Module baseline is API 28 (Android 9 Go)."
  fi
}

validate_arch() {
  if [ -z "$ARCH" ]; then
    ui_print "- Notice: Architecture not detected from environment."
    return 0
  fi

  if [ "$ARCH" != "arm" ] && [ "$ARCH" != "arm64" ]; then
    ui_print "- Warning: Architecture is $ARCH. Proven baseline is 32-bit ARM (armv7)."
  fi
}

check_stock_dir() {
  target_dir="$1"
  if [ -d "$target_dir" ]; then
    ui_print "- Detected stock package directory: $target_dir"
    return 0
  fi
  return 1
}

detect_stock_layout() {
  ui_print "- Inspecting device stock package layout..."
  detected=0

  for stock_path in \
    /system/priv-app/GmsCoreGo \
    /system/priv-app/Phonesky \
    /product/priv-app/GmsCore \
    /system/product/priv-app/GmsCore \
    /product/priv-app/Phonesky \
    /system/product/priv-app/Phonesky
  do
    if check_stock_dir "$stock_path"; then
      detected=1
    fi
  done

  if [ "$detected" -eq 0 ]; then
    ui_print "- Notice: No stock GmsCore or Phonesky dirs detected on active partitions."
  fi
}

ensure_replace_marker() {
  target_dir="$1"
  marker_path="$target_dir/.replace"

  if [ -f "$marker_path" ]; then
    return 0
  fi

  ui_print "- Restoring missing .replace marker in $target_dir"
  mkdir -p "$target_dir"
  touch "$marker_path"
}

ensure_shipped_markers() {
  ensure_replace_marker "$MODPATH/system/priv-app/GmsCoreGo"
  ensure_replace_marker "$MODPATH/system/priv-app/Phonesky"
  ensure_replace_marker "$MODPATH/system/product/priv-app/GmsCore"
  ensure_replace_marker "$MODPATH/system/product/priv-app/Phonesky"
}

verify_payload_apk() {
  apk_path="$1"
  component_name="$2"

  if [ -f "$apk_path" ]; then
    ui_print "- Found payload: $component_name ($(wc -c < "$apk_path" 2>/dev/null || echo "ok") bytes)"
    return 0
  fi

  abort "! Missing $component_name at $apk_path. Build module using scripts/build-module.sh."
}

verify_all_payloads() {
  # Go layout payloads
  verify_payload_apk "$MODPATH/system/priv-app/GmsCoreGo/GmsCoreGo.apk" "GmsCoreGo"
  verify_payload_apk "$MODPATH/system/priv-app/Phonesky/Phonesky.apk" "Phonesky (Go)"

  # Standard layout payloads
  verify_payload_apk "$MODPATH/system/product/priv-app/GmsCore/GmsCore.apk" "GmsCore (Standard)"
  verify_payload_apk "$MODPATH/system/product/priv-app/Phonesky/Phonesky.apk" "Phonesky (Standard)"
}

apply_permissions() {
  ui_print "- Setting file permissions..."
  set_perm_recursive "$MODPATH" 0 0 0755 0644
}

main() {
  print_banner
  validate_sdk
  validate_arch
  detect_stock_layout

  # Ensure directory suppression markers exist for all layouts
  ensure_shipped_markers

  # Validate packaged microG APKs for all layouts
  verify_all_payloads

  apply_permissions

  ui_print "- microG Minimal installation completed."
  ui_print "- Stock packages suppressed via .replace overlays."
  ui_print "- Reboot device to activate microG services."
}

main
