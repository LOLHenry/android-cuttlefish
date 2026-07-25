#!/vendor/bin/sh
# SmartRun Android World Adaptation (v23.2)
# Telephony provider bootstrap: ensure mmssms.db exists for AndroidWorld SMS tasks.
#
# Fix (v23.2): Android 14 FBE stores the db under /data/user_de/0/ instead of
# /data/data/. The script now checks the correct FBE path.

SENTINEL=/data/local/tmp/.android-world-telephony-init.done
DB_DIR=/data/user_de/0/com.android.providers.telephony/databases
DB_PATH=$DB_DIR/mmssms.db
LOG_TAG=aw_tel_init

log() {
    /system/bin/log -t "$LOG_TAG" "$@"
    echo "[$LOG_TAG] $*"
}

# Fast exit if already done.
if [ -f "$SENTINEL" ] && [ -f "$DB_PATH" ]; then
    log "already bootstrapped: $DB_PATH exists"
    exit 0
fi

log "bootstrap starting..."

# Retry loop: ContentResolver may not be ready immediately after boot_completed.
# Wait up to ~30s for the provider to respond.
for i in 1 2 3 4 5 6; do
    /system/bin/content query \
        --uri content://sms/inbox \
        --projection _id >/dev/null 2>&1
    rc_sms=$?

    /system/bin/content query \
        --uri content://mms/inbox \
        --projection _id >/dev/null 2>&1
    rc_mms=$?

    if [ -f "$DB_PATH" ]; then
        log "mmssms.db created after attempt $i (sms rc=$rc_sms mms rc=$rc_mms)"
        break
    fi

    log "attempt $i: db not yet present (sms rc=$rc_sms mms rc=$rc_mms), sleeping 5s"
    sleep 5
done

# Fallback: if still not created, try force-stopping and manually triggering
# the provider process.
if [ ! -f "$DB_PATH" ]; then
    log "fallback: force-stop + retry"
    /system/bin/am force-stop com.android.providers.telephony 2>/dev/null
    sleep 2
    /system/bin/content query --uri content://sms/inbox --projection _id >/dev/null 2>&1
    sleep 2
fi

if [ -f "$DB_PATH" ]; then
    log "bootstrap OK: $DB_PATH size=$(stat -c%s "$DB_PATH" 2>/dev/null)"
    mkdir -p "$(dirname "$SENTINEL")"
    touch "$SENTINEL"
    exit 0
else
    log "bootstrap FAILED: $DB_PATH still missing"
    # Do not mark sentinel so next boot retries.
    exit 1
fi
