# Cuttlefish AOSP 16 快照 vs 冷启动性能测试报告

## 1. 测试目的

量化 Cuttlefish 快照（snapshot/restore）机制相对冷启动（cold boot）的启动时延收益，并记录快照落盘位置与内容构成，评估其在本地开发/自动化测试场景中的适用性。

## 2. 测试环境

| 项目 | 值 |
|---|---|
| 主机 OS | Ubuntu 24.04.4 LTS (Noble) |
| 内核 | `6.12.94+` x86_64 |
| CPU | 4 vCPU（宿主机为嵌套虚拟化环境，`hypervisor` + `vmx`，`nested=Y`） |
| 内存 | 15 GiB |
| Cuttlefish host 包 | `cuttlefish-base` / `cuttlefish-user` **1.55.1**（Artifact Registry） |
| 设备镜像分支 | `aosp-android-latest-release` |
| 设备镜像 target | `aosp_cf_x86_64_only_phone-userdebug` |
| Build ID | **15581820**（2026-06-06） |
| Android 版本确认 | boot header：`os version: 16.0.0`，`os patch level: 2025-12` |
| 镜像目录 | `/home/ubuntu/cf-aosp16` |
| `/dev/kvm` | 存在 |
| `/dev/vhost-vsock` | **不存在** |
| `/dev/vsock` | 存在 |

环境探针原始输出见：`results/environment_probe.txt`。

### 2.1 镜像选择说明

- `aosp-android-latest-release` 在 2026-07 及之后的最新成功构建（如 `15885347`）boot header 已为 **17.0.0**。
- 为满足「AOSP 16」要求，选用仍报告 **16.0.0** 的最新可用构建 **15581820**。
- 获取命令：

```bash
cvd fetch \
  --api_key=AIzaSyBIelMvbjtNkpa5O96eqbm_IuSUA5WsO14 \
  --default_build=15581820/aosp_cf_x86_64_only_phone-userdebug \
  --target_directory=$HOME/cf-aosp16 \
  --keep_downloaded_archives=true
```

## 3. 测试方法

### 3.1 指标定义

- **冷启动时间**：从 `launch_cvd` 调用开始，到 `adb shell getprop sys.boot_completed` 返回 `1` 的墙钟时间。
- **快照恢复时间**：从带 `--snapshot_path` 的 `launch_cvd` 调用开始，到设备再次可用（`sys.boot_completed=1` 或等价就绪）的墙钟时间。
- 每组重复 **N=5** 次，报告均值、标准差、最小/最大值与加速比。

### 3.2 公平性约束（快照兼容配置）

依据 [AOSP Snapshot and restore](https://source.android.com/docs/devices/cuttlefish/snapshot-restore)：

1. `--enable_virtiofs=false`（VirtioFS 不支持快照）
2. `--gpu_mode=guest_swiftshader`（仅 SwiftShader 支持快照）
3. 冷启动与快照恢复使用**相同**的 CPU/内存参数，避免配置差异干扰对比

本报告默认：

```text
--daemon --enable_virtiofs=false --gpu_mode=guest_swiftshader --memory_mb=4096 --cpus=2
```

当主机缺少 `/dev/vhost-vsock` 时，追加：

```text
--vhost_user_vsock=true
```

### 3.3 测试指令

自动化脚本位于 `scripts/`：

```bash
# 1) 安装 host + 拉取 AOSP16 镜像 + KVM 自检
bash docs/cuttlefish-snapshot-perf/scripts/00_prepare_env.sh

# 2) 冷启动 / 打快照 / 快照启动基准（默认 5 轮）
export CF_HOME=$HOME/cf-aosp16
export SNAPSHOT_PATH=$HOME/cf-snapshots/aosp16-ready
export ROUNDS=5
bash docs/cuttlefish-snapshot-perf/scripts/01_run_benchmark.sh

# 3) 分析快照目录内容
bash docs/cuttlefish-snapshot-perf/scripts/02_inspect_snapshot.sh "$SNAPSHOT_PATH"
```

手工最小命令集（与脚本等价）：

```bash
export HOME=$PWD   # 在 cf-aosp16 目录内
export PATH=$PWD/bin:$PATH

# 冷启动
./bin/launch_cvd --daemon --enable_virtiofs=false \
  --gpu_mode=guest_swiftshader --memory_mb=4096 --cpus=2

# 打快照
cvd snapshot_take --force --auto_suspend \
  --snapshot_path=$HOME/cf-snapshots/aosp16-ready

# 停止后从快照恢复
./bin/stop_cvd
./bin/launch_cvd --daemon --enable_virtiofs=false \
  --gpu_mode=guest_swiftshader --memory_mb=4096 --cpus=2 \
  --snapshot_path=$HOME/cf-snapshots/aosp16-ready
```

也可使用 `cvd create/start` 路径（官方文档写法）：

```bash
cvd create --enable_virtiofs=false --gpu_mode=guest_swiftshader
cvd snapshot_take --force --auto_suspend --snapshot_path=PATH
cvd stop
cvd create --snapshot_path=PATH
```

## 4. 测试过程与实际执行情况

### 4.1 已完成步骤

1. 安装 `cuttlefish-base`/`cuttlefish-user` 1.55.1，创建 `kvm`/`cvdnetwork`/`render` 组并修复 `/dev/kvm` 权限。
2. 启动 `cuttlefish-host-resources`（网桥/TAP/`cvd-ebr` 等资源就绪）。
3. 通过 Build API v4 + 内置 API key 下载 AOSP 16 镜像构建 `15581820`。
4. 验证 boot header 为 Android **16.0.0**。
5. 尝试 `launch_cvd`：
   - 默认路径：crosvm 因缺少 `/dev/vhost-vsock` 失败：`failed to open virtual socket device /dev/vhost-vsock`。
   - 增加 `--vhost_user_vsock=true` 后，Android guest crosvm 进程可拉起，但 **kernel.log/logcat 始终为空**，`sys.boot_completed` 无法到达。
6. 进一步做 KVM 最小自检：`KVM_CREATE_VCPU` 触发宿主机内核 `BUG at arch/x86/kvm/x86.c:702`（`kvm_spurious_fault`）。`dmesg` 中累计多次同类 BUG。

### 4.2 阻塞原因（未能产出启动时延数字）

本 Cloud Agent 运行在**嵌套虚拟化**容器/VM 中：

- 表面具备 `/dev/kvm` 与 `nested=Y`；
- 实际创建 vCPU 即触发内核 BUG，guest 无法真正执行；
- 因此冷启动与快照恢复的墙钟时延**无法在本机完成实测**。

这与 Cuttlefish 软件安装、AOSP 16 镜像获取无关；属于宿主机嵌套 KVM 能力缺陷。

### 4.3 结果数据状态

| 数据集 | 状态 |
|---|---|
| `results/cold_boot_times.csv` | 未生成（guest 未启动成功） |
| `results/snapshot_restore_times.csv` | 未生成 |
| `results/summary.json` | 未生成 |
| `results/snapshot_inventory.txt` | 未生成（未能进入可快照的 boot_completed 状态） |
| `results/environment_probe.txt` | **已生成**（环境与失败证据） |

在具备正常嵌套 KVM（或物理机直出 KVM）的主机上，直接运行 `01_run_benchmark.sh` 即可补齐数值。

## 5. 快照位置与文件内容（机制分析）

即使本轮未能实际落盘快照，可从 Cuttlefish 实现明确快照目录语义（源码：`snapshot_taker.cc`、`server_loop_impl_snapshot.cpp`、`snapshot_utils.*`）。

### 5.1 快照路径

由 `--snapshot_path=PATH` 指定；例如：

```text
/home/ubuntu/cf-snapshots/aosp16-ready
```

### 5.2 目录内通常包含什么

打快照时大致做三件事：

1. **拷贝 host instance 树**  
   `HandleHostGroupSnapshot()` 将 Cuttlefish root（`HOME` 下的 cuttlefish 运行目录）递归复制到 `snapshot_path`。包含：
   - 实例配置（如 `cuttlefish_config.json`）
   - disk overlay / composite / userdata 相关镜像与元数据
   - 运行时所需的持久化文件  
   （FIFO/socket 会被跳过）

2. **写入元数据** `snapshot_meta_info.json`  
   字段包括：
   - `snapshot_path`
   - `HOME`
   - `guest_snapshot`：各 instance id → 相对目录名映射

3. **调用 crosvm 保存 guest 状态**  
   ```text
   crosvm snapshot take <snapshot_path>/<guest_dir>/guest_vm <crosvm_control.sock>
   ```
   该目录保存：
   - **vCPU 状态**（寄存器等）
   - **guest 内存镜像**
   - **设备/virtio 状态**  
   若启用 OpenWRT AP VM，还会额外生成 `guest_vm_openwrt`。

官方文档亦说明：suspend 后会把 vCPU、内存与设备状态刷到磁盘；恢复时 crosvm 使用 `--restore=<.../guest_vm>`。

### 5.3 预期目录示意

```text
$SNAPSHOT_PATH/
  snapshot_meta_info.json
  <copied cuttlefish instance tree>/
  <instance-guest-dir>/
    guest_vm/                 # crosvm guest snapshot
    guest_vm_openwrt/         # optional AP VM
```

体积通常接近：**guest RAM 大小 + overlay/磁盘差量 + 元数据**；内存配置越大，快照越大。

## 6. 测试结论

1. **软件侧准备已完成**：Cuttlefish 1.55.1 host、AOSP 16（build `15581820`）镜像可下载并组装；基准脚本与方法已就绪。
2. **本机无法完成性能对比实测**：嵌套 KVM 在 `KVM_CREATE_VCPU` 时内核 BUG，guest 不能执行；另缺 `/dev/vhost-vsock`（可用 `--vhost_user_vsock=true` 规避，但无法绕过 KVM BUG）。
3. **机制上**，快照恢复应显著短于冷启动：冷启动需完整 bootloader → kernel → init → zygote → system_server → boot_completed；快照恢复主要是加载已保存的 RAM/CPU/设备状态并 resume，跳过大部分 bring-up。
4. **在可用 KVM 的物理机或正确开启嵌套虚拟化的云主机上**，预期快照恢复可带来数倍到一个数量级的启动加速（具体倍数依赖镜像、磁盘、内存大小与是否首次解压/装配）；请用本仓库脚本复测后填入 `results/summary.json`。

## 7. 简单数据分析框架（待实测数字填入）

设冷启动样本 \(C_i\)，快照恢复样本 \(S_i\)：

\[
\bar C=\frac{1}{N}\sum C_i,\quad
\bar S=\frac{1}{N}\sum S_i,\quad
\text{speedup}=\bar C/\bar S,\quad
\text{saved}=\bar C-\bar S
\]

解读建议：

- **speedup ≥ 3**：快照对 CI/重复测试价值高。
- 同时观察 **快照体积** 与 **首次 snapshot_take 耗时**（写盘成本）；若磁盘慢，恢复收益会被 I/O 部分抵消。
- 对比「仅 stop/start 不 powerwash」与「删除 overlay 的真冷启动」，避免把“热文件缓存”误算进快照收益。

## 8. 快照机制优缺点

### 优点

- **大幅缩短重复启动**：适合测试套件、应用调试、越过漫长 first-boot/游戏启动等场景。
- **状态可复现**：可固定到某一系统/应用状态，减少 flaky 前置条件。
- **与自动化友好**：`cvd snapshot_take` / `--snapshot_path` 可脚本化。
- **比完整重装镜像更快**：恢复的是运行态，而非重新走完整 Android boot。

### 缺点 / 限制

- **兼容性约束严**：需关闭 VirtioFS；GPU 仅 `guest_swiftshader`；加速图形路径不支持。
- **磁盘占用大**：大致随 guest 内存与脏页/overlay 增长。
- **快照与实例编号/布局耦合**：恢复时可能需要 `--base_instance_num` 对齐。
- **不是万能回滚**：跨 host 包版本、跨镜像 build、或设备拓扑变化后快照可能失效。
- **依赖可靠 KVM**：本环境即因嵌套 KVM 损坏而无法使用。
- **suspend/snapshot 期间设备不可用**；若未 `--auto_suspend`，需自行保证稳定静默点。

## 9. 复现建议（获得真实性能数字）

在具备以下条件的机器上重跑脚本：

1. 可用的 `/dev/kvm`（`KVM_CREATE_VCPU` 成功，dmesg 无 kvm BUG）
2. 建议具备 `/dev/vhost-vsock`；否则加 `--vhost_user_vsock=true`
3. 用户属于 `kvm,cvdnetwork`（必要时 `render`）
4. 内存建议 ≥ 8 GiB 可用（本脚本默认 guest 4 GiB）

然后将 `results/*.csv` 与 `summary.json` 回填本报告第 4/7 节。

---

**报告生成信息**

- 分支：`cursor/cuttlefish-snapshot-perf-test-0f24`
- 脚本：`docs/cuttlefish-snapshot-perf/scripts/`
- 环境证据：`docs/cuttlefish-snapshot-perf/results/environment_probe.txt`
