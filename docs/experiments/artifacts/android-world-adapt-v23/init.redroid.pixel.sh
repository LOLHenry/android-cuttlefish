#!/system/bin/sh
# v30 Pixel Launcher runtime switch
# androidboot.smartrun.pixel.launcher.enabled=1 = Pixel desktop + round icons
# androidboot.smartrun.pixel.launcher.enabled=0 = Launcher3 + AOSP default icons

PIXEL="com.google.android.apps.nexuslauncher"
AOSP="com.android.launcher3"
PIXEL_HOME="$PIXEL/.NexusLauncherActivity"
AOSP_HOME="$AOSP/.uioverrides.QuickstepLauncher"
ICON_OVERLAY="com.smartrun.overlay.pixelicons"

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 0.5; done
sleep 2

MODE=$(getprop ro.boot.smartrun.pixel.launcher.enabled)
MODE=${MODE:-1}

echo "[pixel-init] mode=$MODE"

if [ "$MODE" = "0" ]; then
    # Launcher3 + AOSP square icons
    echo "[pixel-init] Launcher3 + Square icons"
    pm enable $AOSP 2>/dev/null
    pm disable $PIXEL 2>/dev/null
    cmd package set-home-activity "$AOSP_HOME" 2>/dev/null
    cmd overlay disable $ICON_OVERLAY 2>/dev/null
    pm enable com.android.quicksearchbox 2>/dev/null
else
    # Pixel Launcher + Round icons (default)
    echo "[pixel-init] Pixel Launcher + Round icons"
    pm disable $AOSP 2>/dev/null
    pm enable $PIXEL 2>/dev/null
    cmd package set-home-activity "$PIXEL_HOME" 2>/dev/null
    cmd overlay enable $ICON_OVERLAY 2>/dev/null
    pm disable com.android.quicksearchbox 2>/dev/null
fi

echo "[pixel-init] Done."
