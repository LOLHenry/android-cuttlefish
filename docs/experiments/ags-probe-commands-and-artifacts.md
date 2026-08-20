# 腾讯云 AGS Mobile / android-world 探测：命令与产物索引

> 整理自 2026-07-23 / 2026-07-25 试验会话。  
> 详细结论与实测矩阵见同目录 [`tencent-agent-runtime-mobile-hardware-mock.md`](./tencent-agent-runtime-mobile-hardware-mock.md)。  
> 架构归纳见 [`../architecture/ags-mobile-cube-runtime.md`](../architecture/ags-mobile-cube-runtime.md)。

## 持久化边界

| 类别 | 状态 | 位置 |
|---|---|---|
| 试验报告（命令摘要 + D01–M18 矩阵） | **已入库** | `docs/experiments/tencent-agent-runtime-mobile-hardware-mock.md` |
| adapt 可读脚本 / rc | **已入库** | `docs/experiments/artifacts/android-world-adapt-v23/` |
| 逐条原始 stdout / JSON、ELF、APK、凭证 | **已丢失** | 当时实验机 `/tmp/ags-probe/`（云 agent 销毁后不在） |
| 云端 Tool / Instance | **已删除** | cleanup 后为空；ID 仅文档留档 |

Cloud Agent 会话（含 shell 转录）：

- 主探测：https://cursor.com/agents/bc-79c17a10-26a3-4d64-ab81-2652a0ac500d
- 凭证/CLI 说明：https://cursor.com/agents/bc-934017e9-270d-4f00-8b0c-19441c4e9745

---

## 1. Tool / Instance 对照

| 名称 | ToolId | ToolType | 用途 |
|---|---|---|---|
| `mobile-probe` | `sdt-n5tzhruw` | `mobile` | 底座指纹 |
| `android-world-probe` | `sdt-pd9yjy00` | `android-world` | 适配层 + 硬件矩阵 |
| （adapt 临时） | `sdt-h7zu98n8` | `android-world` | 2026-07-25 抽取后即删 |

| 用途 | InstanceId | 日期 |
|---|---|---|
| mobile 首轮指纹 | `tsrfnfjyucrqqadhjgx333ghavnshqt44zeil7nb` | 07-23 |
| android-world 首轮 | `sir6pqwgviu2ezosndhbbl22ax67yrgk6gq6lmtg` | 07-23 |
| gRPC / 端口复探 | `mfdqms3zicbf2vqsra3b3puyc7waxg6i4jchdowk` | 07-23 |
| 适配层 / 早期 mock / scrcpy | `kfnycb3jrbykfjpodh4jl6hkogaasvynqcbu4r7r` | 07-23 |
| E2B/scrcpy 旁路 | `4moeeh2yrsmv2sr2avggn25gzqfc6uxhd7pirlb5` | 07-23 |
| **硬件矩阵复测 D01–M18** | `ocfkyyvhr4sv23ydpzefw4yl4vr5atl7j2rmrfiq` | 07-23 ~10:22 UTC |
| adapt-extract | `ugerqibnp662fjxbcipqf7hrbgkide3tcub3wfpd` | 07-25 |

地域：`ap-shanghai`（数据面 `ap-shanghai.tencentags.com`）。

---

## 2. 按阶段的命令

### 2.1 Setup

```bash
# agr CLI + platform-tools + e2b SDK
curl -fsSL https://dl.tencentags.com/agr-cli/latest/install.sh | sh
# adb → /tmp/platform-tools

agr init --secret-id "$TENCENTCLOUD_SECRET_ID" --secret-key "$TENCENTCLOUD_SECRET_KEY" --non-interactive
agr config set region ap-shanghai
agr config set domain tencentags.com
```

### 2.2 创建 Tool / Instance

```bash
agr tool create --tool-name "mobile-probe" --tool-type mobile \
  --network-configuration '{"NetworkMode":"PUBLIC"}' --default-timeout 30m \
  -o json --non-interactive

agr tool create --tool-name "android-world-probe" --tool-type android-world \
  --network-configuration '{"NetworkMode":"PUBLIC"}' --default-timeout 30m \
  -o json --non-interactive

agr tool get "$TOOL_ID" -o json
agr instance create --tool-id "$TOOL_ID" --timeout 30m -o json --non-interactive
agr instance get "$INSTANCE_ID" -o json
```

当时辅助脚本（仅实验机）：`/tmp/ags-probe/create_tool_and_probe.sh`、`probe_mobile.py`。

### 2.3 ADB 连接与底座指纹

```bash
agr instance mobile connect "$INSTANCE_ID" -o json
# → AdbAddress，如 127.0.0.1:39967

agr instance mobile adb "$INSTANCE_ID" -- shell getprop
agr instance mobile adb "$INSTANCE_ID" -- shell \
  'getprop | grep -iE "qemu|goldfish|ranchu|cuttlefish|cvd|vsoc|redroid|smartrun|wifi|gps|bluetooth|camera"'
agr instance mobile adb "$INSTANCE_ID" -- shell \
  'cat /sys/class/dmi/id/sys_vendor; cat /sys/class/dmi/id/product_name'
agr instance mobile adb "$INSTANCE_ID" -- shell 'uname -a; cat /proc/cpuinfo | head -40'
agr instance mobile adb "$INSTANCE_ID" -- shell \
  'ls -l /dev | grep -iE "goldfish|qemu|vsoc|cvd|video|gps"'
agr instance mobile adb "$INSTANCE_ID" -- shell \
  'ps -A | grep -iE "qemu|cuttlefish|cvd|goldfish|redroid|crosvm"'
agr instance mobile adb "$INSTANCE_ID" -- shell 'pm list features | head -80'
agr instance mobile adb "$INSTANCE_ID" -- shell 'ss -lntp'
```

android-world 额外：

```bash
agr instance mobile adb "$INSTANCE_ID" -- shell \
  'getprop | grep -iE "smartrun|android_world|redroid|gms|pixel"'
agr instance mobile adb "$INSTANCE_ID" -- shell 'pm list packages -3'
# 端口观察：常见 5555 / 4723 / 8000；无 Emulator gRPC 8554
```

**结果摘要（已入库报告）**：非 Emulator / 非 Cuttlefish；Cube + SmartRun/Redroid Android 14。

### 2.4 硬件 / mock 矩阵（D01–M18）

实例：`ocfkyyvhr4sv23ydpzefw4yl4vr5atl7j2rmrfiq`。  
原始输出（已丢失）：`/tmp/ags-probe/hw_cmd_matrix/`。  
逐条标注表见主报告 **§3.5**。

诊断类（节选）：

```bash
agr instance mobile adb "$IID" -- shell 'dumpsys wifi | head -60'          # D01
agr instance mobile adb "$IID" -- shell 'ip link; ls /sys/class/net'       # D03
agr instance mobile adb "$IID" -- shell 'dumpsys location | head -100'     # D04
agr instance mobile adb "$IID" -- shell cat /vendor/bin/init.redroid.gps.sh
agr instance mobile adb "$IID" -- shell 'cat /data/vendor/gps/gnss'        # D06
agr instance mobile adb "$IID" -- shell 'dumpsys bluetooth_manager | head'
agr instance mobile adb "$IID" -- shell 'dumpsys media.camera | head -80'
agr instance mobile adb "$IID" -- shell dumpsys sensorservice              # D12 无传感器
```

注入 / 控制尝试（节选）：

```bash
# 写 gnss 文件可成功，但 dumpsys location 仍 null（非有效 mock）
# cmd location add-test-provider → MOCK_LOCATION 拒绝
# svc wifi enable → CMD_STA_START_FAILURE，无 wlan0
# svc bluetooth enable → 打印 Success，状态仍 OFF
agr instance mobile --help   # 仅 connect/disconnect/adb/list，无硬件 mock 子命令
```

**结论**：诊断命令大多可用；官方硬件 mock API **不存在**。

### 2.5 android_world_adapt v23 抽取（2026-07-25）

```bash
agr instance mobile connect "$IID"
agr instance mobile adb "$IID" -- shell "cat '/vendor/bin/init.redroid.android-world-telephony.sh'"
agr instance mobile adb "$IID" -- shell "cat '/vendor/bin/init.redroid.pixel.sh'"
agr instance mobile adb "$IID" -- shell "cat '/vendor/etc/init/init.redroid.rc'"
agr instance mobile adb "$IID" -- shell "cat '/vendor/etc/init/smartrun-radio-stub.rc'"
agr instance mobile adb "$IID" -- shell "cat '/vendor/etc/vintf/manifest/smartrun-radio-stub.manifest.xml'"
agr instance mobile adb "$IID" -- shell 'strings /vendor/bin/smartrun-radio-stub | head'
agr instance mobile adb "$IID" -- shell \
  'pm list packages -f | grep -iE "smartrun|androidworld|miniwob"'
```

| 已入库（`artifacts/android-world-adapt-v23/`） | 未入库（仅当时 `/tmp/ags-probe/adapt-extract/`） |
|---|---|
| `init.redroid.android-world-telephony.sh` | `smartrun-radio-stub` ELF |
| `init.redroid.pixel.sh` | 评测相关大 APK |
| `init.redroid.rc` / `*.v23-snippet.rc` | `strings/`、`pulled/` 全量 dump |
| `smartrun-radio-stub.rc` / `.manifest.xml` | |

分析正文：主报告 **§3.2.1**。

### 2.6 Cleanup

```bash
agr instance mobile disconnect --all
agr instance delete "$INSTANCE_ID" --ignore-not-found
agr tool delete sdt-n5tzhruw -o json    # 及 sdt-pd9yjy00 等
agr instance list
agr tool list
```

---

## 3. 实验机 `/tmp/ags-probe/` 目录（已丢失）

| 路径 | 内容 |
|---|---|
| `create_tool_and_probe.sh` / `probe_mobile.py` / `env.sh` | 脚本与会话凭证（勿再入库） |
| `adb_probe*.txt` / `adb_extra.txt` | mobile 指纹 |
| `aw_probe.txt` / `aw_adapt_detail.txt` / `aw_grpc_check.txt` | android-world 指纹 / 端口 |
| `hw_mock_probe{,2,3}.txt` | 早期硬件专项 |
| `hw_cmd_matrix/D01…D13`、`M01…M18` | 矩阵复测原始输出 |
| `*_connect.json` / `*_instance*.json` | connect / instance 元数据 |
| `scrcpy_*.txt` | 投屏会话 |
| `adapt-extract/` | 2026-07-25 全量抽取（含 ELF/APK） |

需要逐条原始输出时：只能从上述 Cloud Agent 转录中检索，或按主报告 §6 复现清单重跑。

---

## 4. 已入库产物速查

```text
docs/experiments/
├── tencent-agent-runtime-mobile-hardware-mock.md   # 主报告（方法/矩阵/结论）
├── ags-probe-commands-and-artifacts.md             # 本索引
└── artifacts/android-world-adapt-v23/
    ├── init.redroid.android-world-telephony.sh
    ├── init.redroid.pixel.sh
    ├── init.redroid.rc
    ├── init.redroid.rc.v23-snippet.rc
    ├── smartrun-radio-stub.rc
    └── smartrun-radio-stub.manifest.xml
```

最短复现路径：主报告 **§6**。
