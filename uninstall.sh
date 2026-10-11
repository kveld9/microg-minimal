#!/system/bin/sh
# uninstall.sh - Cleanup script executed when the module is removed in Magisk.
#
# Magisk removes the module directory ($MODPATH) automatically upon reboot.
# Once uninstalled and the device reboots, the systemless overlays covering
# Go layouts (/system/priv-app/GmsCoreGo, /system/priv-app/Phonesky),
# standard layouts (/product/priv-app/GmsCore, /product/priv-app/Phonesky),
# legacy layouts (/system/priv-app/PrebuiltGmsCore, /system/priv-app/Phonesky),
# and permission/sysconfig configurations are removed, cleanly restoring
# stock system partitions and stock packages.
#
# Note: Conflicting /data updates removed during module installation are NOT
# restored when the module is uninstalled. The stock ROM system base returns
# upon reboot, and any subsequent updates can re-download normally via the
# Play Store or microG update path.
#
# MindTheGapps overlay packages disabled during module installation are also
# NOT automatically re-enabled on module removal (per-user state persists).
# Users can restore them via 'pm install-existing <pkg>' or a clean ROM reflash.

# Optional cleanup: invalidate package cache to force fresh scan on next boot
if [ -d "/data/system/package_cache" ]; then
  rm -rf /data/system/package_cache/* 2>/dev/null || true
fi

exit 0
