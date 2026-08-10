#!/usr/bin/env bash
# Cold-boot vs snapshot-restore benchmark for Cuttlefish (AOSP 16).
#
# Measures wall time from launch_cvd invocation until sys.boot_completed=1
# (or until the process returns for snapshot restore readiness).
set -euo pipefail

CF_HOME="${CF_HOME:-$HOME/cf-aosp16}"
SNAPSHOT_PATH="${SNAPSHOT_PATH:-$HOME/cf-snapshots/aosp16-ready}"
RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "$0")/.." && pwd)/results}"
ROUNDS="${ROUNDS:-5}"
MEMORY_MB="${MEMORY_MB:-4096}"
CPUS="${CPUS:-2}"

# Snapshot-compatible launch flags (required by AOSP snapshot docs):
# - disable virtiofs
# - guest_swiftshader GPU
# Optional workaround when /dev/vhost-vsock is missing:
EXTRA_FLAGS=(
  --daemon
  --enable_virtiofs=false
  --gpu_mode=guest_swiftshader
  --memory_mb="${MEMORY_MB}"
  --cpus="${CPUS}"
  --report_anonymous_usage_stats=n
)
if [[ ! -e /dev/vhost-vsock ]]; then
  EXTRA_FLAGS+=(--vhost_user_vsock=true)
fi

mkdir -p "${RESULTS_DIR}" "${SNAPSHOT_PATH%/*}"
export HOME="${CF_HOME}"
export PATH="${CF_HOME}/bin:${PATH}"

ts() { date +%s.%N; }
elapsed() {
  python3 - "$1" "$2" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.3f}")
PY
}

wait_boot_completed() {
  local timeout_s="${1:-600}"
  local start end
  start=$(ts)
  for ((i = 0; i < timeout_s; i++)); do
    if adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{found=1} END{exit !found}'; then
      local boot
      boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      if [[ "${boot}" == "1" ]]; then
        end=$(ts)
        elapsed "${start}" "${end}"
        return 0
      fi
    fi
    sleep 1
  done
  echo "TIMEOUT" >&2
  return 1
}

stop_clean() {
  stop_cvd >/dev/null 2>&1 || true
  sleep 2
}

require_kvm() {
  python3 - <<'PY'
import fcntl, os
fd = os.open("/dev/kvm", os.O_RDWR)
try:
    fcntl.ioctl(fd, 0xAE00)          # KVM_GET_API_VERSION
    vm = fcntl.ioctl(fd, 0xAE01, 0)  # KVM_CREATE_VM
    fcntl.ioctl(vm, 0xAE41, 0)       # KVM_CREATE_VCPU
finally:
    os.close(fd)
PY
}

echo "[bench] CF_HOME=${CF_HOME}"
echo "[bench] SNAPSHOT_PATH=${SNAPSHOT_PATH}"
echo "[bench] ROUNDS=${ROUNDS}"
require_kvm

COLD_CSV="${RESULTS_DIR}/cold_boot_times.csv"
SNAP_CSV="${RESULTS_DIR}/snapshot_restore_times.csv"
echo "round,seconds" > "${COLD_CSV}"
echo "round,seconds" > "${SNAP_CSV}"

echo "[bench] === Cold boot rounds ==="
for ((r = 1; r <= ROUNDS; r++)); do
  stop_clean
  # Powerwash-like clean guest by removing instance overlays between cold boots
  rm -rf "${CF_HOME}/cuttlefish" "${CF_HOME}/cuttlefish_runtime" || true
  t0=$(ts)
  launch_cvd "${EXTRA_FLAGS[@]}"
  # launch_cvd --daemon returns after boot_completed; still verify via adb
  t1=$(ts)
  # If daemon already waited, record that; also confirm property
  boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [[ "${boot}" != "1" ]]; then
    wait_boot_completed 600 >/tmp/boot_wait.txt
    secs="$(cat /tmp/boot_wait.txt)"
  else
    secs="$(elapsed "${t0}" "${t1}")"
  fi
  echo "${r},${secs}" | tee -a "${COLD_CSV}"
done

echo "[bench] === Create snapshot from a ready device ==="
stop_clean
rm -rf "${CF_HOME}/cuttlefish" "${CF_HOME}/cuttlefish_runtime" || true
launch_cvd "${EXTRA_FLAGS[@]}"
adb wait-for-device
adb shell getprop sys.boot_completed | tr -d '\r' | grep -qx 1
rm -rf "${SNAPSHOT_PATH}"
mkdir -p "${SNAPSHOT_PATH}"
cvd snapshot_take --force --auto_suspend --snapshot_path="${SNAPSHOT_PATH}"
{
  echo "snapshot_path=${SNAPSHOT_PATH}"
  echo "taken_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "--- tree ---"
  du -ah "${SNAPSHOT_PATH}" | sort -h | tail -n 80
  echo "--- meta ---"
  if [[ -f "${SNAPSHOT_PATH}/snapshot_meta_info.json" ]]; then
    cat "${SNAPSHOT_PATH}/snapshot_meta_info.json"
  fi
} | tee "${RESULTS_DIR}/snapshot_inventory.txt"

echo "[bench] === Snapshot restore rounds ==="
for ((r = 1; r <= ROUNDS; r++)); do
  stop_clean
  t0=$(ts)
  # Minimal restore path via launch_cvd --snapshot_path (same instance layout)
  launch_cvd "${EXTRA_FLAGS[@]}" --snapshot_path="${SNAPSHOT_PATH}"
  t1=$(ts)
  boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [[ "${boot}" != "1" ]]; then
    wait_boot_completed 300 >/tmp/boot_wait.txt
    secs="$(cat /tmp/boot_wait.txt)"
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
            vals.append(float(row["seconds"]))
    return vals
cold=load(sys.argv[1]); snap=load(sys.argv[2])
def stats(xs):
    return {
        "n": len(xs),
        "samples": xs,
        "mean": statistics.mean(xs),
        "stdev": statistics.stdev(xs) if len(xs)>1 else 0.0,
        "min": min(xs),
        "max": max(xs),
    }
summary={
    "cold_boot": stats(cold),
    "snapshot_restore": stats(snap),
    "speedup_mean": (statistics.mean(cold)/statistics.mean(snap)) if snap and statistics.mean(snap)>0 else None,
    "saved_seconds_mean": statistics.mean(cold)-statistics.mean(snap),
}
with open(sys.argv[3],"w") as f:
    json.dump(summary,f,indent=2)
print(json.dumps(summary, indent=2))
PY

echo "[bench] Results written under ${RESULTS_DIR}"
