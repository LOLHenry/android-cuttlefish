#!/usr/bin/env bash
# Prepare Cuttlefish host packages, groups, and AOSP 16 images.
set -euo pipefail

KEY="${ANDROID_BUILD_API_KEY:-AIzaSyBIelMvbjtNkpa5O96eqbm_IuSUA5WsO14}"
# Newest known aosp-android-latest-release CF build that still reports Android 16
# in the boot image header (later builds moved to 17.x).
BUILD_ID="${CF_AOSP16_BUILD_ID:-15581820}"
TARGET="${CF_TARGET:-aosp_cf_x86_64_only_phone-userdebug}"
CF_HOME="${CF_HOME:-$HOME/cf-aosp16}"

echo "[prepare] Installing cuttlefish host packages (if needed)..."
if ! dpkg -s cuttlefish-base >/dev/null 2>&1; then
  sudo curl -fsSL https://us-apt.pkg.dev/doc/repo-signing-key.gpg \
    -o /etc/apt/trusted.gpg.d/artifact-registry.asc
  sudo chmod a+r /etc/apt/trusted.gpg.d/artifact-registry.asc
  echo "deb https://us-apt.pkg.dev/projects/android-cuttlefish-artifacts android-cuttlefish main" \
    | sudo tee /etc/apt/sources.list.d/artifact-registry.list
  sudo apt-get update
  sudo apt-get install -y cuttlefish-base cuttlefish-user
fi

echo "[prepare] Ensuring groups and /dev/kvm access..."
getent group kvm >/dev/null || sudo groupadd kvm
getent group render >/dev/null || sudo groupadd render
sudo usermod -aG kvm,cvdnetwork,render "$USER" || true
if [[ -e /dev/kvm ]]; then
  sudo chmod 666 /dev/kvm || true
fi

if [[ -x /etc/init.d/cuttlefish-host-resources ]]; then
  sudo /etc/init.d/cuttlefish-host-resources start || true
fi

echo "[prepare] Checking nested KVM health..."
python3 - <<'PY' || {
  echo "[prepare] ERROR: creating a KVM vCPU failed. Nested KVM is not usable."
  echo "[prepare] Cuttlefish cannot boot until the host provides working nested KVM"
  echo "[prepare] and preferably /dev/vhost-vsock (or use --vhost_user_vsock=true)."
  exit 2
}
import fcntl, os, sys
KVM_GET_API_VERSION = 0xAE00
KVM_CREATE_VM = 0xAE01
KVM_CREATE_VCPU = 0xAE41
fd = os.open("/dev/kvm", os.O_RDWR)
try:
    ver = fcntl.ioctl(fd, KVM_GET_API_VERSION)
    vm = fcntl.ioctl(fd, KVM_CREATE_VM, 0)
    vcpu = fcntl.ioctl(vm, KVM_CREATE_VCPU, 0)
    print(f"[prepare] KVM OK api={ver} vm_fd={vm} vcpu_fd={vcpu}")
finally:
    os.close(fd)
PY

echo "[prepare] Fetching AOSP16 CF images build=${BUILD_ID} target=${TARGET} -> ${CF_HOME}"
mkdir -p "${CF_HOME}"
cvd fetch \
  --api_key="${KEY}" \
  --default_build="${BUILD_ID}/${TARGET}" \
  --target_directory="${CF_HOME}" \
  --keep_downloaded_archives=true

"${CF_HOME}/bin/unpack_bootimg" --boot_img "${CF_HOME}/boot.img" --out /tmp/cf-boot-check \
  | tee /tmp/cf-boot-hdr.txt
if ! grep -q "os version: 16" /tmp/cf-boot-hdr.txt; then
  echo "[prepare] WARNING: boot header does not report Android 16.x"
fi

echo "[prepare] Done. CF_HOME=${CF_HOME}"
echo "[prepare] Note: re-login or use 'sg kvm'/'newgrp' so group membership applies."
