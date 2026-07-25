# 行动指南：用 Android 16 Host 启动 Android 15 / 14 Guest

目标：固定使用较新的 Cuttlefish **host tools**（Android 16 / `aosp-android-latest-release`），分别拉起 **Android 15** 或 **Android 14** 的 guest 镜像。

Host 与 guest 在 cuttlefish 里是两路产物，可以分开指定；仓库样例见  
`base/cvd/cuttlefish/host/cvd_test_configs/tm_phone-tm_watch-main_host_pkg.json`。

---

## 0. 先记住三条铁律

1. **Host 只提供工具**：`bin/`、`lib*`、seccomp、默认 bootloader 等。  
2. **Guest 必须是完整、同 target 的一套镜像**：`boot.img` / `vendor_boot.img` / `super.img`（或等价分区）/ `vbmeta*` / `android-info.txt` 等，全部来自同一 guest build。  
3. **不要用 A16 的 kernel / initramfs 覆盖老 guest**（除非你明确在做 kernel 实验）。默认让 kernel 留在 guest 的 `boot.img` 里。

上一回合里的 `/vendor/bin/boringssl_self_test32` 失败，通常不是 “A16 host 不支持老 guest”，而是 **guest 镜像混用 / 不是纯 `arm64_only`**，导致 init 走到了 32 位 self-test。

---

## 1. 环境准备

### 1.1 安装 cuttlefish Debian 包（本仓库）

```bash
sudo apt install -y git devscripts equivs config-package-dev debhelper-compat golang curl
git clone https://github.com/google/android-cuttlefish
cd android-cuttlefish
tools/buildutils/build_packages.sh
sudo dpkg -i ./cuttlefish-base_*_*64.deb ./cuttlefish-user_*_*64.deb || sudo apt-get install -f
sudo usermod -aG kvm,cvdnetwork,render "$USER"
sudo reboot
```

### 1.2 确认虚拟化

```bash
# KVM
ls -l /dev/kvm
# 组权限生效（reboot 后）
id | grep -E 'kvm|cvdnetwork|render'
```

### 1.3 准备可用的 `cvd`（二选一）

- **A**：先从 Android 16 / latest host package 解出 `bin/cvd`，后续都用它 fetch/create。  
- **B**：本机已装好的 `cvd`（来自本仓库 deb / 本地编译），再去 fetch 分离的 host+guest。

下面命令默认假设 PATH 里已有 `cvd`。

---

## 2. 选定 branch / target

到 [ci.android.com](https://ci.android.com/) 核对名称（branch / target 会随时间变化）。

| 角色 | 建议 branch | arm64 建议 target |
|---|---|---|
| Host (A16 / latest) | `aosp-android-latest-release` | `aosp_cf_arm64_only_phone-userdebug` |
| Guest A15 | `aosp-android15-gsi`（或以 CI 上可见的 A15 CF branch 为准） | 优先 `aosp_cf_arm64_only_phone-userdebug` |
| Guest A14 | `aosp-android14-gsi` | 有 `*_only_*` 用 only；没有则用 `aosp_cf_arm64_phone-userdebug` |

x86_64 主机把 `arm64` 换成 `x86_64` 即可（例如 `aosp_cf_x86_64_only_phone-userdebug`）。

> A14 的 e2e 在仓库里用的是同 branch 的 `aosp_cf_x86_64_phone-userdebug`（非 only）。跨版本时 **host 用 only、guest 用非 only** 可以试，但 guest 自身必须自洽；不要把 only / 非 only 的分区互相拼。

配套 JSON 样例：

- [`examples/a16-host-a15-guest-arm64.json`](examples/a16-host-a15-guest-arm64.json)
- [`examples/a16-host-a14-guest-arm64.json`](examples/a16-host-a14-guest-arm64.json)

---

## 3. 路径 A：一条命令 fetch + create（推荐）

### 3.1 Android 15 guest

```bash
WORKDIR=$PWD/cf-a16host-a15guest
mkdir -p "$WORKDIR"

cvd fetch \
  --host_package_build=aosp-android-latest-release/aosp_cf_arm64_only_phone-userdebug \
  --default_build=aosp-android15-gsi/aosp_cf_arm64_only_phone-userdebug \
  --target_directory="$WORKDIR"

HOME="$WORKDIR" cvd create \
  --host_path="$WORKDIR" \
  --product_path="$WORKDIR" \
  --daemon
```

### 3.2 Android 14 guest

```bash
WORKDIR=$PWD/cf-a16host-a14guest
mkdir -p "$WORKDIR"

# 先在 CI 确认该 branch 是否有 arm64_only；没有就把 target 改成 aosp_cf_arm64_phone-userdebug
cvd fetch \
  --host_package_build=aosp-android-latest-release/aosp_cf_arm64_only_phone-userdebug \
  --default_build=aosp-android14-gsi/aosp_cf_arm64_only_phone-userdebug \
  --target_directory="$WORKDIR"

HOME="$WORKDIR" cvd create \
  --host_path="$WORKDIR" \
  --product_path="$WORKDIR" \
  --daemon
```

### 3.3 用 JSON（`cvd load`）

```bash
# 按需改 docs/examples 里的 branch/target 后：
cvd load docs/examples/a16-host-a15-guest-arm64.json
# 或
cvd load docs/examples/a16-host-a14-guest-arm64.json
```

---

## 4. 路径 B：手工解压两套产物

适用于已经从 CI 下好 zip / tar 的情况。

```bash
HOST_DIR=$PWD/a16-host
GUEST_DIR=$PWD/a15-guest   # 或 a14-guest

mkdir -p "$HOST_DIR" "$GUEST_DIR"

# Host：只解 cvd-host_package.tar.gz（来自 A16 / latest 的 build）
tar -xvf /path/to/a16/cvd-host_package.tar.gz -C "$HOST_DIR"

# Guest：只解对应版本的 *-img-*.zip（不要把 A16 的 img 解进来）
unzip /path/to/a15/aosp_cf_arm64_only_phone-img-XXXXXX.zip -d "$GUEST_DIR"

# 启动：host_path 与 product_path 分开
HOME="$GUEST_DIR" "$HOST_DIR/bin/cvd" create \
  --host_path="$HOST_DIR" \
  --product_path="$GUEST_DIR" \
  --daemon
```

**禁止**：把 A16 host package 和 A15/A14 img 解压到同一个目录互相覆盖后再启动。

---

## 5. 启动后验收（必做）

```bash
# 设备在线
adb devices

# 版本应是 15 或 14，而不是 16
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk

# arm64_only 预期
adb shell getprop ro.zygote
# 期望: zygote64

adb shell getprop ro.product.cpu.abilist32
# 期望: 空

adb shell getprop ro.product.cpu.abilist64
# 期望: arm64-v8a

adb shell getprop sys.boot_completed
# 期望: 1
```

串口 / 主机日志位置（常见）：

```bash
ls "$HOME"/cuttlefish/instances/cvd-1/logs/
# 或 WORKDIR 下的 cuttlefish 运行时目录
```

重点搜：

```text
boringssl_self_test
boringssl-self-check-failed
cannot execv
Exec format error
```

---

## 6. 故障排查清单

### 6.1 `boringssl_self_test32` / `boringssl-self-check-failed`

**重要：** `lunch` / 编译配置叫 `arm64_only_phone`，不等于运行时一定是 only。

A15 上 vendor/system 都是按 `ro.zygote` 选择触发脚本：

- `ro.zygote=zygote64` → 只 `exec_start` `*_test64`
- `ro.zygote=zygote64_32` → 会 `exec_start` `*_test32`（以及 64）

init 对 `property:ro.product.cpu.abilist32=*` 的规则是：**属性必须非空才匹配**。  
真正的 64-only 上 `abilist32` 为空，即使旧式 abilist 触发脚本也不会启动 32 位测试。

因此：只要日志里出现 `starting service 'boringssl_self_test32...`，就说明运行时 **不是** 纯 `zygote64` only 路径。

| 检查 | 正常（arm64_only） | 异常含义 |
|---|---|---|
| `ro.zygote` | `zygote64` | `zygote64_32` / 其它 → 不是 only，或 vendor 被混包 |
| `abilist32` | 空 | 非空 → 会走 32 位 self-test（尤其旧式 rc / 混包） |
| init 日志 | 只见 `*_test64` | 出现 `starting service 'boringssl_self_test32` |
| `/vendor/bin/boringssl_self_test32` | 通常不存在 | 存在 → vendor 很像非 only 或被替换过 |

**离线核对（不必等开机成功）：**

```bash
GUEST_DIR=...   # product_path

# 1) 看 android-info / 产物名是否真是 only
grep -E 'device|name|abi' "$GUEST_DIR/android-info.txt" 2>/dev/null || true
ls "$GUEST_DIR" | grep -E 'img|android-info'

# 2) 从 vendor 镜像看 zygote / abilist（需要 simg2img/debugfs 或已解出的 vendor）
# 期望 vendor build.prop 含：
#   ro.zygote=zygote64
#   ro.vendor.product.cpu.abilist32=   (空)
# 且存在：
#   /vendor/etc/boringssl_self_test.zygote64.rc
# 不应依赖 zygote64_32.rc 来启动 self-test

# 3) kernel/init 日志里搜触发证据
grep -E "boringssl_self_test|ro.zygote|abilist32|boringssl-self-check" \
  "$HOME"/cuttlefish/instances/*/logs/* 2>/dev/null
```

处理：

1. **清掉旧目录后重新 fetch**，`--default_build` 全程同一个 `aosp_cf_arm64_only_phone-...`，不要另加 `--system_build` 指向非 only。  
2. 不要把 A16/非 only 的 `vendor*.img` / `super.img` 解压进 A15 only 目录。  
3. 不要用 A16 kernel 覆盖 guest `boot.img`。  
4. 对照实验：同一套 A15 only 镜像，用 **A15 matched host** 启一次。  
   - matched 也挂 → guest 镜像本身不是 only / 已损坏  
   - matched 能起、仅 A16 host 挂 → 见下一节「6.1.1」

#### 6.1.1 matched A15 host 能起、A16 host 不起（已确认时）

此时不要再怀疑 lunch 名；优先 diff **host 静默注入的东西**。

| 优先级 | 差异点 | 怎么验证 |
|---|---|---|
| 1 | **Bootloader** | guest 目录通常没有 `bootloader`；assemble 会改用 host 包内 `etc/bootloader_<arch>/bootloader.<vmm>`。A15 host→A16 host 时这里会换掉 |
| 2 | 目录混用 | A16 `cvd-host_package.tar.gz` 解压覆盖到 A15 目录，或 `host_path`/`product_path` 指错 |
| 3 | kernel/initramfs 被覆盖 | 日志里是否出现非空 `kernel_path` / `kernel_hotswapped` |
| 4 | 新 host 的 bootconfig/APEX | 一般晚于 boringssl；先确认 test32 是否真的被 `starting service` |

**推荐复现步骤（分离目录 + 钉死 A15 bootloader）：**

```bash
# 目录分离，避免覆盖
A16_HOST=$PWD/a16-host
A15_GUEST=$PWD/a15-guest
A15_HOST=$PWD/a15-host   # matched 能开机的那套 host

# 1) 先确认 A16 host + A15 guest（分离目录）是否仍复现
HOME=$A15_GUEST $A16_HOST/bin/cvd create \
  --host_path=$A16_HOST \
  --product_path=$A15_GUEST \
  --daemon

# 2) 若复现：强制用 A15 host 包里的 bootloader（路径按 arch/vmm 改）
# arm64 + crosvm 常见：
BL=$A15_HOST/etc/bootloader_aarch64/bootloader.crosvm

HOME=$A15_GUEST $A16_HOST/bin/cvd create \
  --host_path=$A16_HOST \
  --product_path=$A15_GUEST \
  --bootloader=$BL \
  --daemon
```

也可 fetch 时显式拉 A15 bootloader：

```bash
cvd fetch \
  --host_package_build=aosp-android-latest-release/aosp_cf_arm64_only_phone-userdebug \
  --default_build=aosp-android15-gsi/aosp_cf_arm64_only_phone-userdebug \
  --bootloader_build=aosp-android15-gsi/aosp_cf_arm64_only_phone-userdebug \
  --target_directory=$PWD/cf-mixed
```

**仍失败时，从 A16 失败日志里贴这几行（比猜测有用）：**

```text
bootloader=...
kernel_path=...
Parsing file .../boringssl_self_test...
starting service 'boringssl_self_test...
cannot execv(...boringssl_self_test...
```

若 `starting service` 是 `*_test64` 而不是 `*_test32`，说明之前对 “32” 的判断需要按实际 service 名修正。

### 6.2 卡在 early boot / HAL / APEX

新 host 可能写入 `androidboot.vendor.apex.*`（keymint、gatekeeper、hwcomposer 等）。老 guest 若缺对应 vendor APEX，可能在 boringssl 之后失败。

处理思路：

1. 对比能开机的同版本 matched host+guest 与当前 mixed 启动的 bootconfig / logcat。  
2. 确认 guest 目录自带 `bootloader`；若没有，host 会回落用 A16 默认 bootloader——可尝试从同版本 guest build 取 bootloader，或用 `--bootloader=` 显式指定。  
3. 暂时收窄功能面：关闭不必要的 HAL / 图形加速选项做二分（按你环境已有 flag）。

### 6.3 fetch / 权限失败

- CI 私有产物需要 `--credential_source=...`。  
- `Permission denied` on `/dev/kvm` 或 vhost：确认用户组 + 已 reboot。  
- `cvd` 找不到：用 host package 里的 `bin/cvd`，或把该 `bin` 加进 PATH。

### 6.4 对照实验（强烈建议）

同一台机器上做三组，快速定位是 “跨版本” 还是 “镜像本身坏了”：

| 实验 | Host | Guest | 预期 |
|---|---|---|---|
| A | A15 matched | A15 | 应能开机 |
| B | A16 | A15（本指南） | 目标场景 |
| C | A14 matched | A14 | 应能开机 |
| D | A16 | A14（本指南） | 目标场景 |

若 A/C 失败 → 先修镜像/环境；若仅 B/D 失败 → 再查 bootloader / bootconfig / 混包。

---

## 7. 日常命令速查

```bash
# 状态
cvd status
adb shell getprop sys.boot_completed

# 停实例
cvd stop
# 或
HOME="$WORKDIR" ./bin/stop_cvd

# 清实例数据后重来（按需）
cvd clear   # 若你的 cvd 版本支持；否则删 WORKDIR 下 cuttlefish 运行时目录
```

WebRTC UI（若启用）：按 host 日志里打印的端口访问（常见 `https://localhost:8443`）。

---

## 8. 最小决策树

```text
要用 A16 host 起老 guest？
├─ guest 全部分区来自同一 A15/A14 build？ ──否──> 重新 fetch / 重新解压，禁止混包
├─ 需要 arm64_only？
│  ├─ 是 → ro.zygote 必须是 zygote64；出现 *_test32 即镜像不纯
│  └─ 否 → 接受 zygote64_32，并确保 guest 内核支持 32-bit (COMPAT)
├─ 是否覆盖了 kernel_path / initramfs？ ──是──> 先去掉，用 guest boot.img 内 kernel
└─ matched 同版本能开机、仅 mixed 失败？
   └─ 查 bootloader 来源 + androidboot.vendor.apex.* 与老 guest 是否匹配
```

---

## 9. 参考

- Host / guest 分离样例：`base/cvd/cuttlefish/host/cvd_test_configs/tm_phone-tm_watch-main_host_pkg.json`
- 本指南样例：`docs/examples/a16-host-a15-guest-arm64.json`、`docs/examples/a16-host-a14-guest-arm64.json`
- `cvd fetch`：`--host_package_build`（host tools）、`--default_build`（guest 镜像）
- `cvd create`：`--host_path`、`--product_path`
