#!/system/bin/sh
# uninstall.sh - Cleanup script executed when the module is removed.
#
# Magisk / KernelSU / APatch removes the module directory ($MODPATH) upon reboot.
# Overlays, mounts, and XML configurations vanish with the module directory on
# reboot, cleanly restoring stock system partitions and stock packages.
#
# State restoration details:
# - Conflicting /data updates removed during module installation are NOT
#   restorable (the stock ROM system base returns upon reboot, and the store
#   re-downloads updates normally).
# - GApps overlays (MindTheGapps, NikGapps, BitGapps) disabled by older module
#   versions ARE re-enabled here via best-effort 'pm install-existing'.
# - Package and resource caches are invalidated again to force a consistent
#   package/overlay rescan at next boot.

revert_overlay() {
  pkg="$1"
  if [ -z "$pkg" ]; then
    return 0
  fi
  if ! pm install-existing "$pkg" >/dev/null 2>&1; then
    echo "Warning: Failed to re-enable overlay $pkg" >&2
  fi
  return 0
}

revert_overlay_candidate() {
  line="$1"
  case "$line" in
    package:com.mtg.*|com.mtg.*|\
    package:com.nikgapps.overlay.*|com.nikgapps.overlay.*|\
    package:com.bitgapps.*|com.bitgapps.*)
      revert_overlay "${line#package:}"
      ;;
  esac
}

revert_gapps_overlays() {
  if ! command -v pm >/dev/null 2>&1; then
    return 0
  fi

  pkg_list="$(pm list packages -u 2>/dev/null || true)"
  case "$pkg_list" in
    *package:*) ;;
    *) pkg_list="$(pm list packages 2>/dev/null || true)" ;;
  esac

  echo "$pkg_list" | tr -d '\r' | while IFS= read -r line || [ -n "$line" ]; do
    revert_overlay_candidate "$line"
  done
}

# Best-effort revert of overlays disabled by older module versions
revert_gapps_overlays

# Invalidate package and resource caches to force a fresh rescan on next boot
if [ -d "/data/system/package_cache" ]; then
  rm -rf /data/system/package_cache/* 2>/dev/null || true
fi
if [ -d "/data/resource-cache" ]; then
  rm -rf /data/resource-cache/* 2>/dev/null || true
fi

exit 0
