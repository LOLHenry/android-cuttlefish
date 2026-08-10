#!/usr/bin/env bash
# Inventory a Cuttlefish snapshot directory and describe contents.
set -euo pipefail

SNAPSHOT_PATH="${1:-$HOME/cf-snapshots/aosp16-ready}"
OUT="${2:-$(cd "$(dirname "$0")/.." && pwd)/results/snapshot_contents.md}"

if [[ ! -d "${SNAPSHOT_PATH}" ]]; then
  echo "Snapshot path not found: ${SNAPSHOT_PATH}" >&2
  exit 1
fi

{
  echo "# Snapshot inventory"
  echo
  echo "- Path: \`${SNAPSHOT_PATH}\`"
  echo "- Generated: \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Total size: \`$(du -sh "${SNAPSHOT_PATH}" | awk '{print $1}')\`"
  echo
  echo "## Top-level entries"
  echo '```'
  ls -la "${SNAPSHOT_PATH}"
  echo '```'
  echo
  if [[ -f "${SNAPSHOT_PATH}/snapshot_meta_info.json" ]]; then
    echo "## snapshot_meta_info.json"
    echo '```json'
    cat "${SNAPSHOT_PATH}/snapshot_meta_info.json"
    echo '```'
    echo
  fi
  echo "## File list (name, size)"
  echo '```'
  find "${SNAPSHOT_PATH}" -printf '%s\t%p\n' | sort -n | awk '{
    split("B KB MB GB TB", u); s=$1; i=1;
    while (s>=1024 && i<5) {s/=1024; i++}
    printf "%8.1f %-2s  %s\n", s, u[i], substr($0, index($0,$2))
  }'
  echo '```'
  echo
  echo "## Expected semantic contents"
  echo
  echo "Based on Cuttlefish host implementation (\`snapshot_taker.cc\`, \`server_loop_impl_snapshot.cpp\`):"
  echo
  echo "1. **Host instance tree copy** of the Cuttlefish root under \`HOME\` (disk overlays, configs, sockets omitted where FIFO/socket)."
  echo "2. **\`snapshot_meta_info.json\`** metadata: snapshot path, HOME, guest_snapshot map per instance."
  echo "3. **Guest VM snapshot directory** (\`.../guest_vm\`) produced by \`crosvm snapshot take\`:"
  echo "   - vCPU register/state"
  echo "   - guest RAM image"
  echo "   - virtio / device state"
  echo "4. Optional **OpenWRT AP VM** snapshot as \`guest_vm_openwrt\` when Wi‑Fi AP VM is enabled."
} > "${OUT}"

echo "Wrote ${OUT}"
