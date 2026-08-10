#!/usr/bin/env bash
# Download AOSP16 CF artifacts via Build API signed URLs (works behind local proxy).
set -euo pipefail

export http_proxy="${http_proxy:-http://127.0.0.1:7897}"
export https_proxy="${https_proxy:-http://127.0.0.1:7897}"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export no_proxy="${no_proxy:-localhost,127.0.0.1}"
export NO_PROXY="$no_proxy"

BUILD_ID="${CF_AOSP16_BUILD_ID:-15581820}"
TARGET="${CF_TARGET:-aosp_cf_x86_64_only_phone-userdebug}"
CF_HOME="${CF_HOME:-/home/fangyu/cf-aosp16}"
DL="${CF_HOME}/downloads"
IMG_NAME="aosp_cf_x86_64_only_phone-img-${BUILD_ID}.zip"
HOST_NAME="cvd-host_package.tar.gz"
API="https://www.googleapis.com/android/internal/build/v3/builds/${BUILD_ID}/${TARGET}/attempts/latest/artifacts"

mkdir -p "$DL" "$CF_HOME"
cd "$CF_HOME"

signed_url() {
  local name="$1"
  curl -fsS --connect-timeout 30 --max-time 60 \
    "${API}/${name}/url" | python3 -c 'import sys,json; print(json.load(sys.stdin)["signedUrl"])'
}

download_one() {
  local name="$1"
  local out="$DL/$name"
  if [[ -f "$out" && -s "$out" ]]; then
    echo "[dl] reuse existing $out ($(du -h "$out" | awk '{print $1}'))"
    return 0
  fi
  echo "[dl] resolving signed URL for $name"
  local url
  url=$(signed_url "$name")
  echo "$url" > "${out}.url"
  echo "[dl] downloading $name ..."
  curl -fL --connect-timeout 30 --retry 5 --retry-delay 5 \
    -o "${out}.partial" "$url"
  mv "${out}.partial" "$out"
  echo "[dl] done $out ($(du -h "$out" | awk '{print $1}'))"
}

download_one "$HOST_NAME"
download_one "$IMG_NAME"

echo "[dl] unpacking into $CF_HOME"
# Clean previous partial fetch dirs that are empty-ish
rm -rf "$CF_HOME/bin" "$CF_HOME/lib64" "$CF_HOME/etc" 2>/dev/null || true
tar -xvf "$DL/$HOST_NAME" -C "$CF_HOME"
unzip -o "$DL/$IMG_NAME" -d "$CF_HOME"

echo "[dl] verify boot header"
"$CF_HOME/bin/unpack_bootimg" --boot_img "$CF_HOME/boot.img" --out /tmp/cf-boot-check \
  | tee /tmp/cf-boot-hdr.txt
if ! grep -q "os version: 16" /tmp/cf-boot-hdr.txt; then
  echo "[dl] ERROR: not Android 16" >&2
  exit 2
fi
echo "[dl] OK Android 16 at $CF_HOME"
ls -lah "$CF_HOME/bin/launch_cvd" "$CF_HOME/boot.img" "$CF_HOME/super.img"
