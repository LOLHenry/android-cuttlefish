#!/usr/bin/env bash
# Cold-boot vs snapshot-restore benchmark for Cuttlefish (AOSP 16) on WSL2.
set -euo pipefail

# Bypass local HTTP proxy for OpenWRT AP Luci (192.168.94.2) — curl ignores 192.168.* globs.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy || true
export no_proxy='127.0.0.1,localhost,192.168.94.2,192.168.94.0/16,192.168.0.0/16'
export NO_PROXY="$no_proxy"

CF_HOME="${CF_HOME:-$HOME/cf-aosp16}"
SNAPSHOT_PATH="${SNAPSHOT_PATH:-$HOME/cf-snapshots/aosp16-ready}"
RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "$0")/.." && pwd)/results}"
ROUNDS="${ROUNDS:-3}"
MEMORY_MB="${MEMORY_MB:-4096}"
CPUS="${CPUS:-2}"
export ANDROID_SERIAL="${ANDROID_SERIAL:-0.0.0.0:6520}"

# Snapshot-compatible + WSL2-required:
# - enable_sandbox=false (minijail mount fails on WSL)
# - kernel /dev/vhost-vsock (NOT --vhost_user_vsock; that breaks snapshot DEVICE_STATE)
EXTRA_FLAGS=(
  --daemon
  --enable_sandbox=false
  --enable_virtiofs=false
  --gpu_mode=guest_swiftshader
  --memory_mb="${MEMORY_MB}"
  --cpus="${CPUS}"
  --report_anonymous_usage_stats=n
)

mkdir -p "${RESULTS_DIR}" "${SNAPSHOT_PATH%/*}"
export HOME="${CF_HOME}"
export PATH="${CF_HOME}/bin:/usr/bin:${PATH}"

ts() { date +%s.%N; }
elapsed() {
  python3 - "$1" "$2" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.3f}")
PY
}

adb_boot() {
  adb -s "${ANDROID_SERIAL}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true
}
ensure_adb() { adb connect "${ANDROID_SERIAL}" >/dev/null 2>&1 || true; }

wait_boot_completed() {
  local timeout_s="${1:-600}" start end
  start=$(ts)
  for ((i = 0; i < timeout_s; i++)); do
    ensure_adb
    if [[ "$(adb_boot)" == "1" ]]; then
      end=$(ts); elapsed "${start}" "${end}"; return 0
    fi
    sleep 1
  done
  echo "TIMEOUT" >&2; return 1
}

stop_clean() {
  pkill -9 -f 'launch_cvd|run_cvd|/bin/crosvm|cf_vhost|openwrt_control|process_restarter|casimir|wmediumd|gnss_grpc|secure_env|tombstone_receiver|log_tee|socket_vsock|vhost_user|snapshot_util' 2>/dev/null || true
  stop_cvd >/dev/null 2>&1 || true
  sleep 2
  rm -rf /tmp/cf_avd_1000 /tmp/vsock_* /tmp/cf_env_* 2>/dev/null || true
}

require_kvm() {
  python3 - <<'PY'
import fcntl, os
fd = os.open("/dev/kvm", os.O_RDWR)
try:
    fcntl.ioctl(fd, 0xAE00); vm = fcntl.ioctl(fd, 0xAE01, 0); fcntl.ioctl(vm, 0xAE41, 0)
finally:
    os.close(fd)
PY
}

echo "[bench] CF_HOME=${CF_HOME} SNAPSHOT_PATH=${SNAPSHOT_PATH} ROUNDS=${ROUNDS}"
echo "[bench] FLAGS=${EXTRA_FLAGS[*]}"
require_kvm
chmod 666 /dev/kvm /dev/vhost-vsock 2>/dev/null || true

COLD_CSV="${RESULTS_DIR}/cold_boot_times.csv"
SNAP_CSV="${RESULTS_DIR}/snapshot_restore_times.csv"
echo "round,seconds" > "${COLD_CSV}"
echo "round,seconds" > "${SNAP_CSV}"

echo "[bench] === Cold boot rounds ==="
for ((r = 1; r <= ROUNDS; r++)); do
  stop_clean
  rm -rf "${CF_HOME}/cuttlefish" "${CF_HOME}/cuttlefish_runtime" "${CF_HOME}/cuttlefish_assembly" || true
  t0=$(ts)
  launch_cvd "${EXTRA_FLAGS[@]}"
  t1=$(ts)
  ensure_adb
  if [[ "$(adb_boot)" != "1" ]]; then
    secs="$(wait_boot_completed 600)"
  else
    secs="$(elapsed "${t0}" "${t1}")"
  fi
  echo "${r},${secs}" | tee -a "${COLD_CSV}"
done

echo "[bench] === Create snapshot ==="
stop_clean
rm -rf "${CF_HOME}/cuttlefish" "${CF_HOME}/cuttlefish_runtime" "${CF_HOME}/cuttlefish_assembly" || true
launch_cvd "${EXTRA_FLAGS[@]}"
ensure_adb
adb -s "${ANDROID_SERIAL}" wait-for-device
[[ "$(adb_boot)" == "1" ]]
rm -rf "${SNAPSHOT_PATH}"; mkdir -p "${SNAPSHOT_PATH}"
snapshot_util_cvd --subcmd=snapshot_take --force --auto_suspend --snapshot_path="${SNAPSHOT_PATH}" \
  2>&1 | tee "${RESULTS_DIR}/snapshot_take.log"
{
  echo "snapshot_path=${SNAPSHOT_PATH}"
  echo "taken_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  du -sh "${SNAPSHOT_PATH}"
  echo "--- tree ---"
  du -ah "${SNAPSHOT_PATH}" | sort -h | tee "${RESULTS_DIR}/snapshot_du.txt" | tail -n 80
  echo "--- meta ---"
  cat "${SNAPSHOT_PATH}/snapshot_meta_info.json"
} | tee "${RESULTS_DIR}/snapshot_inventory.txt"

echo "[bench] === Snapshot restore rounds ==="
for ((r = 1; r <= ROUNDS; r++)); do
  stop_clean
  rm -rf "${CF_HOME}/cuttlefish" "${CF_HOME}/cuttlefish_runtime" "${CF_HOME}/cuttlefish_assembly" || true
  t0=$(ts)
  launch_cvd "${EXTRA_FLAGS[@]}" --snapshot_path="${SNAPSHOT_PATH}"
  t1=$(ts)
  ensure_adb
  if [[ "$(adb_boot)" != "1" ]]; then
    secs="$(wait_boot_completed 300)"
  else
    secs="$(elapsed "${t0}" "${t1}")"
  fi
  echo "${r},${secs}" | tee -a "${SNAP_CSV}"
done

stop_clean

python3 - "${COLD_CSV}" "${SNAP_CSV}" "${RESULTS_DIR}/summary.json" <<'PY'
import csv, json, statistics, sys
def load(path):
    vals=[]
    with open(path) as f:
        for row in csv.DictReader(f):
            if row["seconds"]!="TIMEOUT": vals.append(float(row["seconds"]))
    return vals
cold,snap=load(sys.argv[1]),load(sys.argv[2])
def stats(xs):
    if not xs: return {"n":0,"samples":[]}
    return {"n":len(xs),"samples":xs,"mean":statistics.mean(xs),
            "stdev":statistics.stdev(xs) if len(xs)>1 else 0.0,
            "min":min(xs),"max":max(xs)}
summary={"cold_boot":stats(cold),"snapshot_restore":stats(snap),
         "speedup_mean":(statistics.mean(cold)/statistics.mean(snap)) if cold and snap and statistics.mean(snap)>0 else None,
         "saved_seconds_mean":(statistics.mean(cold)-statistics.mean(snap)) if cold and snap else None}
json.dump(summary, open(sys.argv[3],"w"), indent=2)
print(json.dumps(summary, indent=2))
PY
echo "[bench] Results under ${RESULTS_DIR}"
