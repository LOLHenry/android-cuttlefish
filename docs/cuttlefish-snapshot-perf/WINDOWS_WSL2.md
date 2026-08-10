# Windows 本机跑 Cuttlefish：WSL2 嵌套 KVM 实操清单

目标：在 **本机 Windows + WSL2** 上让 `KVM_CREATE_VCPU` 成功，再启动 Cuttlefish。  
Cloud Agent / 一般嵌套云主机 **无法代替** 你的 Windows 本机验证；本目录脚本需在你的 PC 上执行。

## 0. 先分清两层虚拟化

```text
L0: Windows Hyper-V
L1: WSL2 Linux（这里装 cuttlefish / 跑 launch_cvd）
L2: Android guest（crosvm）
```

Cuttlefish 需要 L1 里的 KVM 真正能创建 vCPU。  
`/dev/kvm` 存在 ≠ 可用；必须以自检为准。

## 1. Windows 侧（管理员 PowerShell）

```powershell
# 更新 WSL
wsl --update
wsl --version

# 写入用户配置（允许嵌套）
$cfg = @"
[wsl2]
nestedVirtualization=true
memory=12GB
processors=6
swap=0
"@
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value $cfg -Encoding ASCII

wsl --shutdown
Start-Sleep -Seconds 3
```

可选：若本机用 Hyper-V 管理可见的 Linux VM（非纯 WSL），对那台 VM：

```powershell
Get-VM | Select-Object Name, State
Set-VMProcessor -VMName "<VM名>" -ExposeVirtualizationExtensions $true
```

BIOS 需开启 VT-x / AMD-V。关掉会独占虚拟化的旧版 VMware 等冲突软件。

一键脚本：`scripts/wsl2_enable_nested.ps1`。

## 2. WSL 内自检（必须先过）

```bash
bash docs/cuttlefish-snapshot-perf/scripts/03_wsl_kvm_selftest.sh
```

脚本会检查：

| 检查项 | 期望 |
|---|---|
| `/dev/kvm` | 存在且可写 |
| CPU flags | 有 `vmx` 或 `svm`，通常还有 `hypervisor` |
| `nested` | `Y` / `1` |
| `KVM_CREATE_VM` + `KVM_CREATE_VCPU` | 打印 `OK`，进程不 segfault |
| `dmesg` | 无 `BUG at arch/x86/kvm` / `kvm_spurious_fault` |
| `/dev/vhost-vsock` | 有更好；没有则启动时加 `--vhost_user_vsock=true` |

**自检失败就不要装/跑 Cuttlefish**——后面只会反复踩同一内核 BUG。

## 3. 自检通过后再准备 Cuttlefish

```bash
bash docs/cuttlefish-snapshot-perf/scripts/00_prepare_env.sh
# 然后按 TEST_REPORT.md 拉取 AOSP16 镜像并 launch
```

## 4. 自检失败时的本机替代路径

| 方案 | 适用 |
|---|---|
| Hyper-V 完整 Ubuntu VM + `ExposeVirtualizationExtensions` | WSL2 嵌套坏、但 Hyper-V 嵌套偶发可用 |
| 双系统 / 外置盘裸机 Ubuntu | 正式冷启动/快照基准（最推荐） |
| 远程 Linux 有 KVM 的机器 | Windows 只做 SSH/adb 客户端 |

不要关嵌套虚拟化来「绕过」——关了就没有可用 KVM，Cuttlefish 更无法运行。

## 5. 与 Cloud Agent 实测的对应关系

在嵌套已损坏的主机上（与坏的 WSL2 同类症状）：

- `/dev/kvm` 存在，`nested=Y`，CPU 有 `vmx` + `hypervisor`
- `python3` / `qemu-system-x86_64` 一执行 `KVM_CREATE_VCPU` 即 segfault
- `dmesg`: `kernel BUG at arch/x86/kvm/x86.c:702`（`kvm_spurious_fault`）
- `vhost_vsock` 模块可能根本不存在

这类故障 **无法** 用 Cuttlefish 启动参数修复；必须修好 L0（Windows Hyper-V 嵌套）或换非嵌套 Linux 主机。
