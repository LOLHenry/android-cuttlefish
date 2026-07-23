# 腾讯云 Agent Runtime Mobile / Android World 沙箱试验报告

> 试验日期：2026-07-23  
> 地域：`ap-shanghai`（数据面域名 `ap-shanghai.tencentags.com`）  
> 目的：核实 Mobile / android-world 沙箱底层实现，以及是否官方提供 WiFi / Camera / GNSS / BT 等硬件 mock 能力。

---

## 1. 产品信息

| 项 | 内容 |
|---|---|
| 产品 | 腾讯云 **Agent Runtime / Agent 沙箱服务**（文档产品 ID：1814） |
| 相关文档 | [工具类型说明](https://cloud.tencent.com/document/product/1814/132209)、[手机操作](https://cloud.tencent.com/document/product/1814/127484)、[操作指南 PDF](https://main.qcloudimg.com/raw/document/product/pdf/1814_123818_cn.pdf) |
| 预置 Tool 类型 | `mobile`、`android-world`（控制台/产品动态中有 Android World 公测） |
| 官方控制面 | Appium UiAutomator2 + ADB（`agr instance mobile`）+ scrcpy 投屏 |
| CLI | `agr`（AGR CLI） |
| SDK 兼容 | E2B SDK（替换 `E2B_DOMAIN` / `E2B_API_KEY`） |
| 易混淆产品 | **云手机 CPH**（产品 1801）另有 `setLocation` / `setSensor` / 摄像头媒体注入 API，**不属于** Agent Runtime Mobile |

### 1.1 本次创建的 Tool / Instance

| 名称 | ToolId | ToolType | 说明 |
|---|---|---|---|
| `mobile-probe` | `sdt-n5tzhruw` | `mobile` | 标准 Mobile 沙箱探测 |
| `android-world-probe` | `sdt-pd9yjy00` | android-world 类预置 | Android World 适配镜像探测 |

典型实例规格（探测时）：CPU `4600m`，Memory `8768Mi`，网络 `PUBLIC`。

示例 InstanceId：

- mobile：`tsrfnfjyucrqqadhjgx333ghavnshqt44zeil7nb`
- android-world：`sir6pqwgviu2ezosndhbbl22ax67yrgk6gq6lmtg`、`kfnycb3jrbykfjpodh4jl6hkogaasvynqcbu4r7r` 等

---

## 2. 试验方法

### 2.1 总体思路

1. **文档核对**：检索 Agent Runtime 官方文档/CLI schema，确认是否存在硬件 mock API。  
2. **实机创建**：用 `agr` 创建 `mobile` / android-world Tool 与 Instance。  
3. **ADB 指纹探测**：通过 `agr instance mobile connect/adb` 读取 `getprop`、DMI、进程、HAL、端口，判断是否为 Emulator / Cuttlefish / Redroid。  
4. **硬件面探测**：对 WiFi、GNSS、BT、Camera、Sensor 做 `dumpsys` / 文件 / 网卡检查。  
5. **注入尝试**：对镜像内发现的 GPS 文件、Android `cmd location` test provider 做写入/调用验证。

### 2.2 环境准备

```bash
# 凭证（试验用 SecretId/SecretKey + E2B/AGS API Key；用后建议轮换）
export TENCENTCLOUD_SECRET_ID=...
export TENCENTCLOUD_SECRET_KEY=...
export E2B_API_KEY=...
export REGION=ap-shanghai
export E2B_DOMAIN=ap-shanghai.tencentags.com

# CLI / ADB
agr init --secret-id "$TENCENTCLOUD_SECRET_ID" --secret-key "$TENCENTCLOUD_SECRET_KEY" --non-interactive
agr config set region "$REGION"
agr config set domain tencentags.com
# platform-tools adb 放入 PATH（试验中使用 /tmp/platform-tools）
```

### 2.3 创建 Tool 与 Instance

```bash
# Mobile
agr tool create \
  --tool-name "mobile-probe" \
  --tool-type mobile \
  --network-configuration '{"NetworkMode":"PUBLIC"}' \
  --default-timeout 30m \
  -o json --non-interactive

# Android World（控制台/产品侧预置类型；试验中 tool-type 按控制台可用类型创建）
agr tool create \
  --tool-name "android-world-probe" \
  ...

agr instance create --tool-id "$TOOL_ID" --timeout 30m -o json --non-interactive
agr instance get "$INSTANCE_ID" -o json
```

辅助脚本（试验机本地路径 `/tmp/ags-probe/`）：

- `create_tool_and_probe.sh`：创建 mobile Tool/Instance 并跑首轮 ADB 指纹
- `probe_mobile.py`：E2B SDK 创建沙箱的备选路径

### 2.4 ADB 连接与通用探测命令

```bash
INSTANCE_ID=...

agr instance mobile connect "$INSTANCE_ID" -o json
# 得到 AdbAddress，如 127.0.0.1:41649

agr instance mobile adb "$INSTANCE_ID" -- shell getprop
agr instance mobile adb "$INSTANCE_ID" -- shell 'getprop | grep -iE "qemu|goldfish|ranchu|cuttlefish|cvd|vsoc|redroid|smartrun|wifi|gps|bluetooth|camera"'
agr instance mobile adb "$INSTANCE_ID" -- shell 'cat /sys/class/dmi/id/sys_vendor; cat /sys/class/dmi/id/product_name'
agr instance mobile adb "$INSTANCE_ID" -- shell 'uname -a; cat /proc/cpuinfo | head -40'
agr instance mobile adb "$INSTANCE_ID" -- shell 'ls -l /dev | grep -iE "goldfish|qemu|vsoc|cvd|video|gps"'
agr instance mobile adb "$INSTANCE_ID" -- shell 'ps -A | grep -iE "qemu|cuttlefish|cvd|goldfish|redroid|crosvm"'
agr instance mobile adb "$INSTANCE_ID" -- shell 'pm list features | head -80'
agr instance mobile adb "$INSTANCE_ID" -- shell 'ss -lntp'   # 或 netstat 等价查看监听端口
```

### 2.5 硬件 / mock 专项命令

```bash
# WiFi
agr instance mobile adb "$IID" -- shell dumpsys wifi
agr instance mobile adb "$IID" -- shell 'getprop | grep -iE "wifi|wlan|rssi|bssid"'
agr instance mobile adb "$IID" -- shell 'ip link; ls /sys/class/net'

# GNSS / Location
agr instance mobile adb "$IID" -- shell dumpsys location
agr instance mobile adb "$IID" -- shell cat /vendor/bin/init.redroid.gps.sh
agr instance mobile adb "$IID" -- shell 'ls -la /data/vendor/gps; cat /data/vendor/gps/gnss'
agr instance mobile adb "$IID" -- shell cmd location help
agr instance mobile adb "$IID" -- shell 'printf "LatitudeDegrees=39.9042\nLongitudeDegrees=116.4074\nAltitudeMeters=50\nBearingDegrees=10\nSpeedMetersPerSec=1\n" > /data/vendor/gps/gnss'
agr instance mobile adb "$IID" -- shell 'cmd location providers add-test-provider mockgps --requiresSatellite'
# （试验中因 MOCK_LOCATION appops 失败）

# BT
agr instance mobile adb "$IID" -- shell dumpsys bluetooth_manager
agr instance mobile adb "$IID" -- shell 'getprop | grep -i bluetooth'

# Camera / Sensor
agr instance mobile adb "$IID" -- shell dumpsys media.camera
agr instance mobile adb "$IID" -- shell dumpsys sensorservice
agr instance mobile adb "$IID" -- shell 'ls -la /dev/video*'

# Battery（对照：镜像内文件 mock）
agr instance mobile adb "$IID" -- shell head -80 /vendor/bin/init.redroid.battery.sh
agr instance mobile adb "$IID" -- shell 'cat /sys/class/power_supply/battery/capacity'
```

### 2.6 官方能力核对命令 / 文档

```bash
agr instance mobile --help
# 仅有：connect / disconnect / adb / list
# 无 wifi/gps/camera/sensor/bluetooth mock 子命令

# 文档核对关键词：硬件 mock、WiFi、GPS、传感器、蓝牙、摄像头
# 结果：Agent Runtime 文档未提供对应控制 API；CPH 文档另有批量 GPS/传感器/摄像头接口
```

### 2.7 scrcpy 观察（UI 通路）

官方示例路径：通过沙箱 host + `access_token` 拼 `scrcpy_url`，或数据面端口代理（常见 8000 / ws-scrcpy）。  
控制端口观察（android-world 实例内）：

| 端口 | 用途（观察） |
|---|---|
| 5555 | adbd |
| 4723 | Appium |
| 8000 / 8886 | scrcpy / WebSocket 投屏相关 |
| **无 8554** | 未发现 Emulator gRPC（AndroidEnv 常用） |

---

## 3. 实验过程与结果

### 3.1 阶段 A：底层是什么？

**假设**：文档出现 `emulator-5554` 字样 → 可能是经典 AVD Emulator；或异构沙箱文章语境 → 可能是 Cuttlefish + `cvd-host_package`。

**观测结果（mobile 与 android-world 一致）**：

| 检查项 | 结果 | 含义 |
|---|---|---|
| `ro.kernel.qemu` | 空 | 非典型 qemu/AVD 标记 |
| `/sys/class/dmi/id/*` | `cube-hypervisor` / `Cube Hypervisor` | 跑在 Cube Hypervisor MicroVM 上 |
| `ro.hardware.gralloc` | `redroid` | Redroid 图形栈 |
| `ro.build.display.id` / odm fingerprint | `smartrun_android_x86_64` / `SmartRun/.../redroid_x86_64_only:14/...` | SmartRun 定制 Redroid Android 14 |
| Cuttlefish 迹象（`cvd`/`vsoc` 设备与进程） | **未发现** | 非 Cuttlefish |
| 产品外观 | OnePlus `PJZ110` skin（cosmetic） | 真实 ABI/构建仍是 x86_64 SmartRun |

**结论**：运行栈为 **Cube Hypervisor MicroVM + Redroid/SmartRun x86_64 Android 14 (API 34)**，不是经典 Emulator，也不是 Cuttlefish。

### 3.2 阶段 B：mobile vs android-world

| 项 | mobile | android-world |
|---|---|---|
| 底座 | SmartRun/Redroid Android 14 | 同底座 |
| 适配层 | 无 AW 专用 props | `ro.smartrun.android_world_adapt.version=v23` |
| 预装 | 基础系统 + Appium 组件 | Markor、Joplin、OsmAnd、OpenTracks、Tasks、Chrome、MiniWoB、Pixel Launcher、GMS-AW 变体等 |
| Telephony | — | `smartrun-radio-stub` / android_world telephony init |
| Emulator gRPC `:8554` | 无 | 无 |
| 官方控制 | Appium + ADB + scrcpy | 同 |

**结论**：android-world ≈ mobile 底座 + SmartRun `android_world_adapt`；**没有**官方 AndroidEnv/a11y-gRPC 兼容层文档与端口。

### 3.3 阶段 C：官方是否提供硬件 mock？

**文档 / CLI**：未发现 WiFi RSSI/AP、Camera 注入、GNSS 注入、BT mock、传感器注入的产品 API。官方能力止于 UI 自动化链路。

**镜像内 stub（非官方 API）实测**：

| 能力 | 官方 API | 镜像现象 | 注入/可控性 |
|---|---|---|---|
| WiFi / AP / 信号强度 | 无 | WiFi 默认关闭：`ro.boot.smartrun.wifi.enabled=0`；`dumpsys wifi` 为 Disabled；存在 `hwsim0`（mac80211_hwsim）与 `wlan0` 相关 prop | **无**文档化注入接口；未验证可控 AP/RSSI mock |
| Camera | 无 | 1 个 Front/External HAL（`device@1.1/external/142`），`/dev/video42` | **无**官方图片/视频注入 API |
| GNSS | 无 | GNSS HAL 存在；`init.redroid.gps.sh` 写默认坐标到 `/data/vendor/gps/gnss`（默认深圳市民中心） | 文件可写（试验改写为北京坐标成功）；**未文档化**；`dumpsys location` 在未 start GPS 请求时 `last location=null` |
| Android test provider | — | `cmd location providers ...` 存在 | shell/root 调 `add-test-provider` 报 `SecurityException: MOCK_LOCATION` |
| BT | 无 | `android.hardware.bluetooth@1.1-service.sim` running；adapter 默认 OFF | **无**官方 mock 控制 |
| 运动传感器 | 无 | feature 声明 accelerometer/compass，但 `dumpsys sensorservice` → **No Sensors on the device** | 实质上不可用 |
| 电池 | 无 | `init.redroid.battery.sh` 把 `/data/vendor/battery` bind 到 `/sys/class/power_supply` | 文件级 stub，非产品 API |
| Radio | 无 | `smartrun-radio-stub` running | 基带 stub，非完整 modem mock API |

### 3.4 阶段 D：与云手机 CPH 的边界

云手机（1801）文档含：

- `setLocationWithParams`
- `setSensorWithParams`
- `startCameraMediaPlayWithParams` / `displayCameraImageWithParams`
- 等批量设备控制接口

这些**不能**当作 Agent Runtime Mobile 沙箱的官方能力。

---

## 4. 实验发现（摘要）

1. **官方未提供硬件 mock 产品能力**（WiFi 信号/AP、Camera、GNSS、BT、传感器等）。控制面只有 Appium / ADB / scrcpy。  
2. **底层不是 Emulator，也不是 Cuttlefish**；是 Cube Hypervisor + SmartRun/Redroid Android 14。  
3. **android-world 不是另一套虚拟化**，而是同底座加 AW 应用与适配（v23）。  
4. **镜像内部存在部分 stub**（GPS 文件、电池 sysfs、BT sim HAL、external camera、radio stub、hwsim0），属于实现细节，无 SLA/文档，不适合作为业务依赖。  
5. **上游 AndroidWorld / AndroidEnv 依赖的 Emulator gRPC(8554) a11y 通路在此环境不存在**；若要复用原 pipeline，需自建适配，而非依赖腾讯官方兼容说明。  
6. **Android 版本不可在 mobile/android-world 预置类型上配置**；仅 `custom` 可自带镜像（且 custom 面向容器配置，不等同于官方 Android 硬件仿真）。  
7. **安全提醒**：试验中使用的 API Key / Secret 曾出现在交互上下文，建议在控制台轮换。

---

## 5. 原始产物索引

试验过程落盘于实验机 `/tmp/ags-probe/`（未全部入库）：

| 文件 | 内容 |
|---|---|
| `create_tool_and_probe.sh` | 创建 Tool/Instance + 首轮 ADB 探测脚本 |
| `probe_mobile.py` | E2B SDK 探测脚本 |
| `adb_probe.txt` / `adb_probe2.txt` / `adb_extra.txt` | mobile 指纹与传感器/相机 |
| `aw_probe.txt` / `aw_adapt_detail.txt` / `aw_grpc_check.txt` | android-world 指纹、适配层、端口 |
| `hw_mock_probe.txt` / `hw_mock_probe2.txt` / `hw_mock_probe3.txt` | 硬件 mock 专项 dumpsys / GPS 文件注入 / 网卡 |
| `*_connect.json` / `*_instance*.json` | connect / instance 元数据 |
| `scrcpy_*.txt` | 投屏会话相关记录 |

---

## 6. 复现清单（最短路径）

```bash
# 1) 初始化
agr init --secret-id "$TENCENTCLOUD_SECRET_ID" --secret-key "$TENCENTCLOUD_SECRET_KEY" --non-interactive
agr config set region ap-shanghai
agr config set domain tencentags.com

# 2) 起实例（已有 Tool 可复用 ToolId）
INSTANCE_ID=$(agr instance create --tool-id sdt-n5tzhruw --timeout 30m -o json --jq '.Data.InstanceId')

# 3) 连 ADB 并确认底座
agr instance mobile connect "$INSTANCE_ID"
agr instance mobile adb "$INSTANCE_ID" -- shell 'getprop ro.build.display.id; getprop ro.hardware.gralloc; cat /sys/class/dmi/id/product_name'

# 4) 核对官方 mobile 子命令范围
agr instance mobile --help

# 5) 核对硬件面
agr instance mobile adb "$INSTANCE_ID" -- shell 'dumpsys wifi | head; dumpsys sensorservice | head; dumpsys media.camera | head; dumpsys bluetooth_manager | head; cat /data/vendor/gps/gnss'

# 6) 清理
agr instance delete "$INSTANCE_ID" --ignore-not-found
```

---

## 7. 结论

**腾讯云 Agent Runtime 的 Mobile / Android World 沙箱：官方不提供可调用的硬件 mock 能力。**  
实机仅能看到 Redroid/SmartRun 层的部分 HAL/stub；若业务需要可控的 WiFi/GNSS/Camera/BT/传感器仿真，应评估其他方案（例如完整 Android Emulator、云手机 CPH，或自建自定义环境），而不是依赖 Agent Runtime 官方文档中不存在的接口。
