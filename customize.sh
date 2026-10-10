#!/system/bin/sh
# customize.sh - Magisk module installation customization script
# Executed during module flash in Magisk app or recovery environment.

print_banner() {
  ui_print "****************************************"
  ui_print " microG Minimal - Split-APK Suppressor  "
  ui_print " Target: Android 9 Go (API 28, armv7)   "
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

verify_payload_apk() {
  apk_path="$1"
  component_name="$2"

  if [ -f "$apk_path" ]; then
    ui_print "- Found payload: $component_name ($(wc -c < "$apk_path" 2>/dev/null || echo "ok") bytes)"
    return 0
  fi

  abort "! Missing $component_name at $apk_path. Build module using scripts/build-module.sh."
}

apply_permissions() {
  ui_print "- Setting file permissions..."
  set_perm_recursive "$MODPATH" 0 0 0755 0644
}

main() {
  print_banner
  validate_sdk
  validate_arch

  # Ensure directory suppression markers exist
  ensure_replace_marker "$MODPATH/system/priv-app/GmsCoreGo"
  ensure_replace_marker "$MODPATH/system/priv-app/Phonesky"

  # Validate packaged microG APKs
  verify_payload_apk "$MODPATH/system/priv-app/GmsCoreGo/GmsCoreGo.apk" "GmsCoreGo"
  verify_payload_apk "$MODPATH/system/priv-app/Phonesky/Phonesky.apk" "Phonesky"

  apply_permissions

  ui_print "- microG Minimal installation completed."
  ui_print "- Stock split-APKs suppressed via .replace overlays."
  ui_print "- Reboot device to activate microG services."
}

main
