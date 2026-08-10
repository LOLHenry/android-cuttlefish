#!/usr/bin/env bash
# WSL2 / nested-host KVM gate check for Cuttlefish.
# Exit 0 only when KVM_CREATE_VCPU succeeds and dmesg shows no fresh kvm BUG.
set -euo pipefail

PASS=0
FAIL=0
ok()  { echo "[PASS] $*"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $*"; FAIL=$((FAIL + 1)); }
info(){ echo "[INFO] $*"; }

echo "=== host ==="
uname -a
if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || grep -qi microsoft /proc/version 2>/dev/null; then
  ok "Running under WSL"
else
  info "Not WSL (bare metal / cloud / other VM) — still valid for this gate check"
fi

echo "=== /dev/kvm ==="
if [[ -e /dev/kvm ]]; then
  ls -l /dev/kvm
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    ok "/dev/kvm readable+writable"
  else
    bad "/dev/kvm present but not RW for $(id -un) (add user to kvm group, re-login)"
  fi
else
  bad "/dev/kvm missing — enable nestedVirtualization / VT-x"
fi

echo "=== CPU virt flags ==="
if grep -qw vmx /proc/cpuinfo; then
  ok "Intel VT-x (vmx) visible"
elif grep -qw svm /proc/cpuinfo; then
  ok "AMD-V (svm) visible"
else
  bad "Neither vmx nor svm in /proc/cpuinfo (L0 did not expose virt extensions)"
fi
grep -qw hypervisor /proc/cpuinfo && info "hypervisor flag set (nested guest)" || info "no hypervisor flag (likely bare metal)"

echo "=== nested module param ==="
NESTED="?"
if [[ -r /sys/module/kvm_intel/parameters/nested ]]; then
  NESTED=$(cat /sys/module/kvm_intel/parameters/nested)
elif [[ -r /sys/module/kvm_amd/parameters/nested ]]; then
  NESTED=$(cat /sys/module/kvm_amd/parameters/nested)
fi
info "nested=$NESTED"
case "$NESTED" in
  Y|1) ok "nested enabled" ;;
  *) info "nested not Y (may still work as L1 if L0 KVM is real)" ;;
esac
echo "=== vsock ==="
if [[ -e /dev/vhost-vsock ]]; then
  ok "/dev/vhost-vsock present"
else
  info "/dev/vhost-vsock missing — use launch flag --vhost_user_vsock=true after KVM works"
  sudo modprobe vhost_vsock 2>/dev/null && ls -l /dev/vhost-vsock && ok "loaded vhost_vsock" \
    || info "could not load vhost_vsock (module absent is OK if using vhost_user_vsock)"
fi
[[ -e /dev/vsock ]] && info "/dev/vsock present" || info "/dev/vsock missing"

echo "=== KVM_CREATE_VCPU (critical) ==="
BUGS_BEFORE=$(dmesg 2>/dev/null | grep -c 'BUG at arch/x86/kvm' || true)
set +e
python3 - <<'PY'
import fcntl, os, sys
KVM_CREATE_VM = 0xAE01
KVM_CREATE_VCPU = 0xAE41
try:
    kvm = os.open("/dev/kvm", os.O_RDWR)
    vm = fcntl.ioctl(kvm, KVM_CREATE_VM, 0)
    vcpu = fcntl.ioctl(vm, KVM_CREATE_VCPU, 0)
    os.close(vcpu)
    os.close(vm)
    os.close(kvm)
    print("KVM_CREATE_VCPU OK")
except Exception as e:
    print("KVM_CREATE_VCPU FAIL:", e)
    sys.exit(1)
PY
PY_RC=$?
set -e
BUGS_AFTER=$(dmesg 2>/dev/null | grep -c 'BUG at arch/x86/kvm' || true)

if [[ $PY_RC -eq 0 ]]; then
  ok "KVM_CREATE_VCPU succeeded"
else
  bad "KVM_CREATE_VCPU failed or process crashed (segfault) — nested KVM broken"
fi

if [[ "$BUGS_AFTER" -gt "$BUGS_BEFORE" ]]; then
  bad "dmesg grew kvm BUG count ($BUGS_BEFORE -> $BUGS_AFTER); sample:"
  dmesg 2>/dev/null | grep -E 'BUG at arch/x86/kvm|kvm_spurious_fault' | tail -5 || true
else
  ok "no new arch/x86/kvm BUG in dmesg"
fi

echo
echo "=== summary: PASS=$PASS FAIL=$FAIL ==="
if [[ $FAIL -gt 0 || $PY_RC -ne 0 ]]; then
  cat <<'EOF'
RESULT: NOT READY for Cuttlefish.

On Windows WSL2:
  1) Run scripts/wsl2_enable_nested.ps1 as Administrator
  2) Confirm BIOS VT-x/AMD-V on; wsl --update; nestedVirtualization=true
  3) Re-run this script
  4) If still FAIL: use bare-metal Ubuntu or Hyper-V Linux VM with working nested KVM
     (Cuttlefish launch flags cannot bypass KVM_CREATE_VCPU kernel BUG)
EOF
  exit 1
fi

echo "RESULT: KVM gate OK — proceed to 00_prepare_env.sh / launch_cvd"
exit 0
