# Cuttlefish AOSP 16：本机 WSL2 冷启动 vs 快照恢复实测

> 对应 PR [#9](https://github.com/LOLHenry/android-cuttlefish/pull/9)。云端嵌套 KVM 不可用；本报告在 **Windows 11 + WSL2 Ubuntu** 上跑通。

## 结论（先看这个）

| 指标 | 冷启动 | 快照恢复 |
|---|---|---|
| N | 3 | 3 |
| 样本 (s) | 255.2 / 215.2 / 221.0 | 208.2 / 216.4 / 214.3 |
| **均值** | **230.5 s** | **213.0 s** |
| 标准差 | 21.6 s | 4.2 s |
| 加速比 | — | **约 1.08×**（平均省 ~17.5 s） |

快照**可以**落盘并成功恢复到 `sys.boot_completed=1` / Android 16，但在本机 WSL2 上收益很小：恢复路径要把约 **4.1 GB** 快照树拷回并读回 **~3.4 GB guest RAM**，墙钟时间被磁盘 I/O 主导，与冷启动接近。

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
2. **`--vhost_user_vsock=true` 与快照互斥**：可用，但快照会报  
   `snapshot requires VHOST_USER_PROTOCOL_F_DEVICE_STATE`。  
   有 `/dev/vhost-vsock` 时用内核 vsock，不要开 vhost-user vsock。
3. **本机 HTTP 代理**：`http_proxy=127.0.0.1:7897` 会劫持 OpenWRT Luci（`192.168.94.2`），`launch_cvd` 在恢复后 FATAL。启动前需 `unset http_proxy https_proxy`，并把 `192.168.94.2` 写入 `no_proxy`（`192.168.*` 对 curl 无效）。
4. **镜像下载**：`cvd fetch` 直连 Google 超时；用 Build API **signed URL + 代理 curl** 下载（见 `scripts/download_aosp16.sh`）。

## 快照落盘位置与内容

**路径：** `/home/fangyu/cf-snapshots/aosp16-ready`  
**元数据** `snapshot_meta_info.json`：

```json
{
  "HOME": "/home/fangyu/cf-aosp16",
  "guest_snapshot": { "1": "cuttlefish/instances/cvd-1/guest_snapshot" },
  "snapshot_path": "/home/fangyu/cf-snapshots/aosp16-ready"
}
```

**构成（按体积）：**

| 路径 | 约大小 | 含义 |
|---|---|---|
| `.../guest_snapshot/guest_vm/mem` | **3.4 G** | Android guest RAM 镜像 |
| `.../guest_snapshot/guest_vm/{vcpu,bus*,irqchip,...}` | ~数百 KB | vCPU / 设备状态 |
| `.../guest_snapshot/guest_vm_openwrt/mem` | **229 M** | Wi‑Fi AP（OpenWRT）VM RAM |
| `instances/cvd-1/overlay.img` 等 | ~480 M | 主机侧 instance 树拷贝（disk overlay、log、config） |
| **合计** | **~4.1 G** | |

打快照命令（本机）：

```bash
export HOME=$HOME/cf-aosp16
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
snapshot_util_cvd --subcmd=snapshot_take --force --auto_suspend \
  --snapshot_path=$HOME/cf-snapshots/aosp16-ready
```

（直接 `launch_cvd` 启动时没有 cvd instance group，`cvd snapshot_take` 会报 *No instance groups available*，需用 `snapshot_util_cvd`。）

## 启动参数（公平对比）

```text
--daemon --enable_sandbox=false --enable_virtiofs=false \
--gpu_mode=guest_swiftshader --memory_mb=4096 --cpus=2 \
--report_anonymous_usage_stats=n
```

恢复：同上 + `--snapshot_path=/home/fangyu/cf-snapshots/aosp16-ready`。

## 原始结果文件

见 `results/`：

- `cold_boot_times.csv` / `snapshot_restore_times.csv` / `summary.json`
- `snapshot_inventory.txt` / `snapshot_du.txt` / `snapshot_contents.md`
- `wsl_kvm_selftest_local.txt`
- `snapshot_take.log`

## 建议

- **要明显加速**：在裸机 Linux 或有高速盘的 Hyper-V Ubuntu 上复测；WSL2 大块 `mem` 读写会抹平快照优势。
- **自动化场景**：快照仍有价值（状态可复现、恢复后立刻 `boot_completed=1`），只是墙钟未必更短。
- 若只做冷启动对比、不需要 Wi‑Fi AP，可再试关掉 OpenWRT AP 以缩小快照（需确认当前 host 包对应开关）。
