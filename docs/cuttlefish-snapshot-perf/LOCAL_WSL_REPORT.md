# Cuttlefish AOSP 16：本机 WSL2 冷启动 vs 快照恢复实测

> 对应 PR [#9](https://github.com/LOLHenry/android-cuttlefish/pull/9) / [#10](https://github.com/LOLHenry/android-cuttlefish/pull/10)。云端嵌套 KVM 不可用；本报告在 **Windows 11 + WSL2 Ubuntu** 上跑通。

## 结论（先看这个）

| 指标 | 冷启动 | 快照恢复 |
|---|---|---|
| N | 3 | 3 |
| 样本 (s) | 255.2 / 215.2 / 221.0 | 208.2 / 216.4 / 214.3 |
| **均值** | **230.5 s** | **213.0 s** |
| 标准差 | 21.6 s | 4.2 s |
| 加速比 | — | **约 1.08×**（平均省 ~17.5 s） |

快照**可以**落盘并成功恢复到 `sys.boot_completed=1` / Android 16，但在本机 WSL2 上收益很小：恢复路径要把约 **4.1 GB** 快照树拷回并读回 **~3.4 GB guest RAM**，墙钟时间被磁盘 I/O 主导，与冷启动接近。

---

## 完整 `launch_cvd` 命令

工作目录与环境（两路径共用）：

```bash
cd /home/fangyu/cf-aosp16
export HOME=/home/fangyu/cf-aosp16
export PATH="$HOME/bin:/usr/bin:$PATH"
export ANDROID_SERIAL=0.0.0.0:6520

# 本机 Clash 等代理会劫持 OpenWRT Luci (192.168.94.2)，必须清掉
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export no_proxy='127.0.0.1,localhost,192.168.94.2,192.168.94.0/16'
export NO_PROXY="$no_proxy"
```

### 冷启动

```bash
rm -rf "$HOME/cuttlefish" "$HOME/cuttlefish_runtime" "$HOME/cuttlefish_assembly"
launch_cvd \
  --daemon \
  --enable_sandbox=false \
  --enable_virtiofs=false \
  --gpu_mode=guest_swiftshader \
  --memory_mb=4096 \
  --cpus=2 \
  --report_anonymous_usage_stats=n
```

### 打快照（设备已 `boot_completed=1`）

```bash
snapshot_util_cvd \
  --subcmd=snapshot_take \
  --force \
  --auto_suspend \
  --snapshot_path=/home/fangyu/cf-snapshots/aosp16-ready
```

> 直接 `launch_cvd` 启动时没有 cvd instance group，`cvd snapshot_take` 会报 *No instance groups available*，本机用 `snapshot_util_cvd`。

### 快照恢复

```bash
rm -rf "$HOME/cuttlefish" "$HOME/cuttlefish_runtime" "$HOME/cuttlefish_assembly" /tmp/cf_avd_1000 /tmp/vsock_* /tmp/cf_env_*
launch_cvd \
  --daemon \
  --enable_sandbox=false \
  --enable_virtiofs=false \
  --gpu_mode=guest_swiftshader \
  --memory_mb=4096 \
  --cpus=2 \
  --report_anonymous_usage_stats=n \
  --snapshot_path=/home/fangyu/cf-snapshots/aosp16-ready
```

指标定义：从调用 `launch_cvd` 到其打印 `VIRTUAL_DEVICE_BOOT_COMPLETED` / `Virtual device restored successfully`（`--daemon` 返回）的墙钟时间。

---

## 均值 ~230 s 时延拆解

下列拆解来自基准过程中**可复现的一次冷启动**（打快照前那次，launcher 时间戳 `15:29:40 → 15:33:02`，墙钟 **~202 s**）以及一次完整恢复（`15:42:51 → 15:46:01` 段 + crosvm 自报 restore 耗时）。三轮均值 230 s / 213 s 与此同量级；首轮冷启动偏慢（255 s）含冷缓存。

### 冷启动（代表样例 ~202 s host 墙钟）

| 阶段 | 约耗时 | 依据 |
|---|---|---|
| **A. `assemble_cvd` 主机准备**（读 config、GPU 探测、wipe overlay、组盘） | **~7 s** | `15:29:40` → `15:29:47` Starting monitored subprocesses |
| **B. 拉起 host 进程 + Android/OpenWRT crosvm** | **~1 s** | `15:29:47` → guest U-Boot / OpenWRT `Loaded bzImage` @ `15:29:48` |
| **C. Guest 内核 + Android 用户态启动 → `sys.boot_completed`** | **~151 s（guest uptime）** | kernel.log：`sys.boot_completed=1` @ `[150.77]` |
| **D. 到 `VIRTUAL_DEVICE_BOOT_COMPLETED`（launch_cvd 退出条件）** | **再 ~35 s guest / host 合计到 ~202 s** | kernel `[185.87]` BOOT_COMPLETED；host `15:33:02` |

**Guest 内 `boot_progress_*`（uptime ms，同一冷启动 logcat）：**

| 里程碑 | guest uptime |
|---|---|
| `boot_progress_start`（Zygote） | ~49 s |
| `boot_progress_preload_end` | ~64 s |
| `boot_progress_system_run`（SystemServer） | ~66 s |
| `boot_progress_pms_ready` | ~93 s |
| `boot_progress_ams_ready` | ~124 s |
| `boot_progress_enable_screen` | ~135 s |
| `sys.boot_completed=1` | ~151 s |
| `VIRTUAL_DEVICE_BOOT_COMPLETED` | ~186 s |

**结论：** 冷启动均值 ~230 s 里，**约 85–90% 在 guest Android 启动**（Zygote/PMS/AMS/锁屏广播），主机 assemble 只占个位数秒；SwiftShader + WSL2 嵌套使这一段偏长。

### 快照恢复（代表样例，墙钟 ~213 s 量级）

| 阶段 | 约耗时 | 依据 |
|---|---|---|
| **A. 主机：把快照树 copy 回 `HOME/cuttlefish` + assemble** | **~20–30 s** | `launch_cvd` 打印 `Copy from .../aosp16-ready`；到 `run_cvd` `15:42:51`（相对整轮 ~214 s 起点约 lag 20 s+） |
| **B. OpenWRT AP RAM restore** | **~11 s** | `snapshot: completed restore in 10887ms; mem size: 268435456` |
| **C. Android guest RAM restore（主因）** | **~106 s** | `snapshot: completed restore in 105849ms; mem size: 4296015872`（读回 ~4 GiB `guest_vm/mem`） |
| **D. `crosvm resume` + 主机收尾（网络/Luci/boot state）** | **~90 s** | resume @ `15:44:31` → `Virtual device restored successfully` @ `15:46:01` |

**结论：** 恢复并不跳过「读 4 GB」；在 WSL2 虚拟盘上 **C≈106 s** 已接近冷启动里整段 Android bring-up，再加 A/D，总墙钟与冷启动打平，故加速比仅 ~1.08×。

### 打快照本身（非启动指标，供对照）

| 阶段 | 约耗时 | 依据（`snapshot_take.log`） |
|---|---|---|
| suspend | ~5 s | `15:33:08` → `15:33:13` |
| copy host instance 树 → snapshot 目录 | ~21 s | `15:33:13` → `15:33:34` |
| `crosvm snapshot take`（含 4 GiB mem 写出） | ~93 s | `15:33:34` → `15:35:07` resume |
| **合计** | **~119 s** | |

---

## 环境

| 项 | 值 |
|---|---|
| 主机 | Windows 11，WSL2 Ubuntu（`jean` / `6.6.87.2-microsoft-standard-WSL2`） |
| `.wslconfig` | `nestedVirtualization=true`，memory=12GB，processors=6 |
| KVM 门禁 | `KVM_CREATE_VCPU OK`；`nested=Y`；`/dev/vhost-vsock` 存在 |
| CF host | cuttlefish-base/user **1.57.0** |
| 镜像 | build **15581820** / `aosp_cf_x86_64_only_phone-userdebug` |
| Android | boot header `os version: 16.0.0`，`os patch level: 2025-12` |
| 工作目录 | `/home/fangyu/cf-aosp16` |
| 快照目录 | `/home/fangyu/cf-snapshots/aosp16-ready`（**4.1 G**） |

## 本机踩坑（必读）

1. **沙箱**：默认 minijail 在 WSL 上挂载失败 → 必须 `--enable_sandbox=false`。
2. **`--vhost_user_vsock=true` 与快照互斥**：可用，但快照会报 `snapshot requires VHOST_USER_PROTOCOL_F_DEVICE_STATE`。有 `/dev/vhost-vsock` 时用内核 vsock。
3. **本机 HTTP 代理**：会劫持 OpenWRT Luci（`192.168.94.2`）；启动前 `unset http_proxy`，`no_proxy` 需写具体地址（`192.168.*` 对 curl 无效）。
4. **镜像下载**：`cvd fetch` 直连超时；用 Build API signed URL + 代理 curl（`scripts/download_aosp16.sh`）。

## 快照落盘位置与内容

**路径：** `/home/fangyu/cf-snapshots/aosp16-ready`

```json
{
  "HOME": "/home/fangyu/cf-aosp16",
  "guest_snapshot": { "1": "cuttlefish/instances/cvd-1/guest_snapshot" },
  "snapshot_path": "/home/fangyu/cf-snapshots/aosp16-ready"
}
```

| 路径 | 约大小 | 含义 |
|---|---|---|
| `.../guest_snapshot/guest_vm/mem` | **3.4 G** | Android guest RAM（恢复时延主因） |
| `.../guest_snapshot/guest_vm/{vcpu,bus*,irqchip,...}` | ~数百 KB | vCPU / 设备状态 |
| `.../guest_snapshot/guest_vm_openwrt/mem` | **229 M** | Wi‑Fi AP（OpenWRT）VM RAM |
| `instances/cvd-1/overlay.img` 等 | ~480 M | 主机 instance 树拷贝 |
| **合计** | **~4.1 G** | |

## 原始结果文件

见 `results/`：`cold_boot_times.csv`、`snapshot_restore_times.csv`、`summary.json`、`snapshot_inventory.txt`、`snapshot_du.txt`、`snapshot_contents.md`、`wsl_kvm_selftest_local.txt`、`snapshot_take.log`。

## 建议

- **要明显加速**：裸机 Linux / 快盘 Hyper-V；或减小 `--memory_mb`（按比例缩小 `guest_vm/mem` I/O）。
- **自动化**：快照价值在状态可复现、恢复后立刻可 adb；墙钟在 WSL2 上不必期待数量级提升。
- 不需要 Wi‑Fi AP 时可再评估关掉 OpenWRT，略减 copy/restore 体积。
