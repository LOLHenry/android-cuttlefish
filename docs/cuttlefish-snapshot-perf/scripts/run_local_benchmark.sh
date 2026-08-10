#!/usr/bin/env bash
# Local WSL runner for cold-boot vs snapshot benchmark.
set -euo pipefail

export http_proxy="${http_proxy:-http://127.0.0.1:7897}"
export https_proxy="${https_proxy:-http://127.0.0.1:7897}"

SCRIPT_SRC=/mnt/d/00-codes/cursor-projects/02-cuttlefish/docs/cuttlefish-snapshot-perf
WORK=$HOME/cf-work/docs/cuttlefish-snapshot-perf
mkdir -p "$WORK/scripts" "$WORK/results"
cp -a "$SCRIPT_SRC/scripts/"*.sh "$WORK/scripts/"
find "$WORK/scripts" -type f -name '*.sh' -exec sed -i 's/\r$//;1s/^\xef\xbb\xbf//' {} +
chmod +x "$WORK/scripts/"*.sh

export CF_HOME="${CF_HOME:-$HOME/cf-aosp16}"
export SNAPSHOT_PATH="${SNAPSHOT_PATH:-$HOME/cf-snapshots/aosp16-ready}"
export RESULTS_DIR="$WORK/results"
export ROUNDS="${ROUNDS:-5}"
export MEMORY_MB="${MEMORY_MB:-4096}"
export CPUS="${CPUS:-2}"

# Ensure host resources + adb
if [[ -x /etc/init.d/cuttlefish-host-resources ]]; then
  # may need root; ignore failure if already up
  /etc/init.d/cuttlefish-host-resources start 2>/dev/null || true
fi
command -v adb >/dev/null || export PATH="/usr/lib/android-sdk/platform-tools:$PATH"
# Prefer platform-tools from host package if present
export PATH="${CF_HOME}/bin:${PATH}"

echo "[runner] CF_HOME=$CF_HOME"
ls -lah "$CF_HOME/bin/launch_cvd" "$CF_HOME/boot.img"
"$CF_HOME/bin/unpack_bootimg" --boot_img "$CF_HOME/boot.img" --out /tmp/cf-boot-check | grep -E 'os version|os patch'

# Save environment probe
{
  echo "=== date ==="; date -u
  echo "=== uname ==="; uname -a
  echo "=== free ==="; free -h
  echo "=== kvm ==="; ls -l /dev/kvm /dev/vhost-vsock /dev/vsock 2>&1
  echo "=== nested ==="; cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || true
  echo "=== cvd version ==="; cvd version 2>&1 || true
  echo "=== packages ==="; dpkg -s cuttlefish-base cuttlefish-user 2>&1 | grep -E '^(Package|Version):'
  echo "=== boot ==="; cat /tmp/cf-boot-hdr.txt 2>/dev/null || "$CF_HOME/bin/unpack_bootimg" --boot_img "$CF_HOME/boot.img" --out /tmp/cf-boot-check
} | tee "$RESULTS_DIR/environment_probe_wsl.txt"

bash "$WORK/scripts/01_run_benchmark.sh"
bash "$WORK/scripts/02_inspect_snapshot.sh" "$SNAPSHOT_PATH" "$RESULTS_DIR/snapshot_contents.md"

# Mirror results back to Windows-mounted docs tree
mkdir -p "$SCRIPT_SRC/results"
cp -a "$RESULTS_DIR"/* "$SCRIPT_SRC/results/" || true
echo "[runner] DONE. Results in $RESULTS_DIR and $SCRIPT_SRC/results"
