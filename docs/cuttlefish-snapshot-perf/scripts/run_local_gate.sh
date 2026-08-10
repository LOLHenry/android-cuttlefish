#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$HOME/cf-work/docs/cuttlefish-snapshot-perf"
mkdir -p "$WORK/scripts" "$WORK/results"
cp -a "$ROOT/scripts/"*.sh "$WORK/scripts/"
cp -a "$ROOT/"*.md "$WORK/" 2>/dev/null || true
find "$WORK" -type f -name '*.sh' -exec sed -i 's/\r$//' {} +
chmod +x "$WORK/scripts/"*.sh
# Already in kvm group on this host; avoid sudo (password required).
bash "$WORK/scripts/03_wsl_kvm_selftest.sh" | tee "$HOME/cf-work/kvm_selftest.txt"
