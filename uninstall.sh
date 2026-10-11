#!/system/bin/sh
# uninstall.sh - Cleanup script executed when the module is removed in Magisk.
#
# Magisk removes the module directory ($MODPATH) automatically upon reboot.
# Once uninstalled and the device reboots, the systemless overlays covering
# Go layouts (/system/priv-app/GmsCoreGo, /system/priv-app/Phonesky) and
# standard layouts (/product/priv-app/GmsCore, /product/priv-app/Phonesky)
# are removed, cleanly restoring stock system partitions and stock packages.

# Optional cleanup: invalidate package cache to force fresh scan on next boot
if [ -d "/data/system/package_cache" ]; then
  rm -rf /data/system/package_cache/* 2>/dev/null || true
fi

exit 0
