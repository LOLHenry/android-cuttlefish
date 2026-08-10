#!/usr/bin/env bash
# Restore from existing snapshot with proxy correctly bypassed for AP LAN.
set -euo pipefail
CF_HOME=${CF_HOME:-$HOME/cf-aosp16}
SNAPSHOT_PATH=${SNAPSHOT_PATH:-$HOME/cf-snapshots/aosp16-ready}
RESULTS=${RESULTS:-$HOME/cf-work/docs/cuttlefish-snapshot-perf/results}
mkdir -p "$RESULTS"
export HOME=$CF_HOME
export PATH=$CF_HOME/bin:/usr/bin:$PATH
export ANDROID_SERIAL=0.0.0.0:6520

# Critical: curl/no_proxy does not honor 192.168.* globs used by some envs.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy || true
export no_proxy='127.0.0.1,localhost,192.168.94.2,192.168.94.0/16,192.168.0.0/16'
export NO_PROXY="$no_proxy"

pkill -9 -f 'launch_cvd|run_cvd|/bin/crosvm|cf_vhost|openwrt_control|process_restarter|casimir|wmediumd|gnss_grpc|secure_env|tombstone|log_tee|socket_vsock' 2>/dev/null || true
sleep 2
stop_cvd >/dev/null 2>&1 || true
rm -rf /tmp/cf_avd_1000 /tmp/vsock_* /tmp/cf_env_* 2>/dev/null || true
# Do NOT wipe snapshot; wipe live instance so restore copies fresh
rm -rf "$CF_HOME/cuttlefish" "$CF_HOME/cuttlefish_runtime" "$CF_HOME/cuttlefish_assembly" || true

EXTRA=(
  --daemon
  --enable_sandbox=false
  --enable_virtiofs=false
  --gpu_mode=guest_swiftshader
  --memory_mb=4096
  --cpus=2
  --report_anonymous_usage_stats=n
)

echo "[restore] from $SNAPSHOT_PATH"
t0=$(date +%s.%N)
set +e
launch_cvd "${EXTRA[@]}" --snapshot_path="$SNAPSHOT_PATH" 2>&1 | tee "$RESULTS/restore_once.log"
rc=${PIPESTATUS[0]}
set -e
t1=$(date +%s.%N)
echo "launch_rc=$rc" | tee "$RESULTS/restore_once.txt"
python3 -c "print('restore_wall_s', round($t1-$t0,3))" | tee -a "$RESULTS/restore_once.txt"

adb connect "$ANDROID_SERIAL" >/dev/null || true
for i in $(seq 1 180); do
  b=$(adb -s "$ANDROID_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
  if [[ "$b" == "1" ]]; then
    echo "restore_boot_completed_after_s=$i" | tee -a "$RESULTS/restore_once.txt"
    adb -s "$ANDROID_SERIAL" shell getprop ro.build.version.release | tr -d '\r' | tee -a "$RESULTS/restore_once.txt"
    echo DONE
    exit 0
  fi
  sleep 1
done
echo "TIMEOUT waiting boot after restore (launch_rc=$rc)" | tee -a "$RESULTS/restore_once.txt"
grep -nEi 'Luci|FATAL|exiting with error|completed restore|VIRTUAL_DEVICE' "$CF_HOME/cuttlefish/instances/cvd-1/logs/launcher.log" | tail -40
exit 1
