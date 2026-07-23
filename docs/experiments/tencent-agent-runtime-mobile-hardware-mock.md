# 腾讯云 Agent Runtime Mobile / Android World 沙箱试验报告

> 试验日期：2026-07-23  
> 地域：`ap-shanghai`（数据面域名 `ap-shanghai.tencentags.com`）  
> 目的：核实 Mobile / android-world 沙箱底层实现，以及是否官方提供 WiFi / Camera / GNSS / BT 等硬件 mock 能力。  
> 硬件/mock 专项命令复测：2026-07-23 10:22 UTC，Instance `ocfkyyvhr4sv23ydpzefw4yl4vr5atl7j2rmrfiq`（Tool `android-world-probe` / `sdt-pd9yjy00`），原始输出 `/tmp/ags-probe/hw_cmd_matrix/`。

**实测标注图例**

| 标记 | 含义 |
|---|---|
| ✅ 可用 | 命令可执行，输出可用于诊断/观察 |
| ⚠️ 部分可用 | 命令能跑，但 mock/控制效果不完整或未生效 |
| ❌ 不可用 | 命令失败，或作为硬件 mock 无实际效果 |

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
- android-world：`sir6pqwgviu2ezosndhbbl22ax67yrgk6gq6lmtg`、`kfnycb3jrbykfjpodh4jl6hkogaasvynqcbu4r7r`、硬件复测 `ocfkyyvhr4sv23ydpzefw4yl4vr5atl7j2rmrfiq` 等

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

### 2.5 硬件 / mock 专项命令（含实测标注）

> 下列命令均通过 `agr instance mobile adb "$IID" -- shell ...` 在 android-world 实例上复测。  
> 「可用」仅表示 ADB 探查命令能跑；**不等于**官方提供硬件 mock API。

#### WiFi

```bash
# ✅ 可用（诊断）：WiFi 默认 Disabled；SupportedFeatures 有值
agr instance mobile adb "$IID" -- shell 'dumpsys wifi | head -60'
# ✅ 可用（诊断）：可见 ro.boot.smartrun.wifi.enabled=0、wifi.interface=wlan0
agr instance mobile adb "$IID" -- shell 'getprop | grep -iE "wifi|wlan|rssi|bssid"'
# ✅ 可用（诊断）：存在 eth0(UP)、hwsim0(DOWN)；无 wlan0 网卡设备
agr instance mobile adb "$IID" -- shell 'ip link; ls /sys/class/net'
# ❌ 不可用（启用不成功）：svc/cmd 触发后随即 CMD_STA_START_FAILURE，仍 Disabled；wlan0 不存在
agr instance mobile adb "$IID" -- shell 'svc wifi enable; cmd wifi set-wifi-enabled enabled; sleep 3; cmd wifi status'
# ❌ 不可用（无扫描结果）：因 WiFi 无法真正启用
agr instance mobile adb "$IID" -- shell 'cmd wifi start-scan; sleep 2; cmd wifi list-scan-results'
# ❌ 不可用（SoftAP）：start-softap 后仍 SAP disabled / failure
agr instance mobile adb "$IID" -- shell 'cmd wifi start-softap TestAP open'
# ✅ 可用（帮助文本）：cmd wifi help 可列出子命令，但无 RSSI/AP 注入类官方接口
agr instance mobile adb "$IID" -- shell 'cmd wifi help'
```

#### GNSS / Location

```bash
# ✅ 可用（诊断）：providers 存在；gps last location=null，mStarted=false
agr instance mobile adb "$IID" -- shell 'dumpsys location | head -100'
# ✅ 可用（诊断）：可读 init.redroid.gps.sh（默认深圳市民中心坐标）
agr instance mobile adb "$IID" -- shell cat /vendor/bin/init.redroid.gps.sh
# ✅ 可用（诊断）：默认文件可读 LatitudeDegrees=22.5435929 ...
agr instance mobile adb "$IID" -- shell 'ls -la /data/vendor/gps; cat /data/vendor/gps/gnss'
# ✅ 可用（帮助）：help 文本可打印（adb exit 常为 255，属 cmd help 常见行为）
agr instance mobile adb "$IID" -- shell 'cmd location help'
# ⚠️ 部分可用（文件可写，定位未验证生效）：写入北京坐标成功并持久；dumpsys 仍 last location=null
agr instance mobile adb "$IID" -- shell 'printf "LatitudeDegrees=39.9042\nLongitudeDegrees=116.4074\nAltitudeMeters=50\nBearingDegrees=10\nSpeedMetersPerSec=1\n" > /data/vendor/gps/gnss'
# ✅ 可用（开关）：set-location-enabled true → is-location-enabled=true
agr instance mobile adb "$IID" -- shell 'cmd location set-location-enabled true; cmd location is-location-enabled'
# ❌ 不可用（Android test provider）：SecurityException MOCK_LOCATION（uid 0 / shell 均失败）
agr instance mobile adb "$IID" -- shell 'cmd location providers add-test-provider mockgps --requiresSatellite --supportsAltitude --supportsSpeed --supportsBearing'
agr instance mobile adb "$IID" -- shell 'cmd location providers set-test-provider-location mockgps --location 31.23,121.47 --accuracy 5'
```

#### BT / Camera / Sensor / Battery

```bash
# ✅ 可用（诊断）：adapter enabled=false / state=OFF；sim HAL 在跑
agr instance mobile adb "$IID" -- shell 'dumpsys bluetooth_manager | head -40'
agr instance mobile adb "$IID" -- shell 'getprop | grep -i bluetooth'
# ⚠️ 部分可用（enable 返回 Success，但状态仍 OFF / Service not connected）
agr instance mobile adb "$IID" -- shell 'svc bluetooth enable; sleep 2; dumpsys bluetooth_manager | head -30'
# ✅ 可用（诊断）：1 个 Front/External camera，/dev/video42 存在；无注入子命令
agr instance mobile adb "$IID" -- shell 'dumpsys media.camera | head -80'
agr instance mobile adb "$IID" -- shell 'ls -la /dev/video*'
# ❌ 不可用（传感器）：No Sensors on the device；devInitCheck=-19
agr instance mobile adb "$IID" -- shell dumpsys sensorservice
# ⚠️ 部分可用（电池 stub 文件可写，sysfs 未挂上）：/data/vendor/battery/.../capacity 98→55；
#    /sys/class/power_supply 无效；dumpsys battery level=0 present=false
agr instance mobile adb "$IID" -- shell 'head -40 /vendor/bin/init.redroid.battery.sh'
agr instance mobile adb "$IID" -- shell 'echo 55 > /data/vendor/battery/power_supply/battery/capacity; cat /data/vendor/battery/power_supply/battery/capacity; cat /sys/class/power_supply/battery/capacity'
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

**镜像内 stub（非官方 API）——2026-07-23 复测结论**：

| 能力 | 官方 API | 镜像现象 | 实测标注 |
|---|---|---|---|
| WiFi / AP / 信号强度 | 无 | `smartrun.wifi.enabled=0`；`hwsim0` DOWN；`wlan0` 设备不存在 | ❌ 启用失败（STA_START_FAILURE）；扫描/SoftAP 无效；无 RSSI/AP 注入 |
| Camera | 无 | 1× Front/External + `/dev/video42` | ✅ dumpsys 可读；❌ 无注入命令 |
| GNSS | 无 | GNSS HAL + `/data/vendor/gps/gnss` | ⚠️ 文件可写；❌ `last location` 仍 null；❌ test provider 被 MOCK_LOCATION 拒绝 |
| BT | 无 | `bluetooth@1.1-service.sim` | ⚠️ `svc bluetooth enable` 回报 Success 但状态仍 OFF |
| 运动传感器 | 无 | feature 声明有，service 无设备 | ❌ `No Sensors on the device` |
| 电池 | 无 | `/data/vendor/battery` 文件 stub | ⚠️ 文件可改；❌ sysfs 未挂载，`dumpsys battery` level=0 |
| Radio | 无 | `smartrun-radio-stub` | 仅 stub 存在，无产品级 mock API |

### 3.4 阶段 D：与云手机 CPH 的边界

云手机（1801）文档含：

- `setLocationWithParams`
- `setSensorWithParams`
- `startCameraMediaPlayWithParams` / `displayCameraImageWithParams`
- 等批量设备控制接口

这些**不能**当作 Agent Runtime Mobile 沙箱的官方能力。

### 3.5 硬件 / mock 专项命令实测矩阵（2026-07-23）

复测环境：

- Tool：`android-world-probe`（`sdt-pd9yjy00`）
- Instance：`ocfkyyvhr4sv23ydpzefw4yl4vr5atl7j2rmrfiq`
- ADB：`agr instance mobile connect` → `127.0.0.1:39967`
- 原始输出目录：`/tmp/ags-probe/hw_cmd_matrix/`（`D01`–`D13`、`M01`–`M18`）

#### 诊断类命令

| ID | 命令意图 | Exit | 实测标注 | 关键结果摘要 |
|---|---|---|---|---|
| D01 | `dumpsys wifi \| head` | 0 | ✅ 可用 | `WifiState 0`，`Current wifi mode: DisabledState`，`Wi-Fi is disabled` |
| D02 | wifi 相关 getprop | 0 | ✅ 可用 | `ro.boot.smartrun.wifi.enabled=0`；`wifi.interface=wlan0`；HAL/wificond running |
| D03 | `ip link` / net | 0 | ✅ 可用 | `eth0` UP；`hwsim0` DOWN；**无** `wlan0` 设备 |
| D04 | `dumpsys location` | 0 | ✅ 可用 | gps/network/fused 存在；各 `last location=null`；gps `mStarted=false` |
| D05 | `cat init.redroid.gps.sh` | 0 | ✅ 可用 | 默认写入深圳市民中心坐标到 `/data/vendor/gps/gnss` |
| D06 | 读 gnss 文件 | 0 | ✅ 可用 | 默认 `22.5435929, 114.0572401` |
| D07 | `cmd location help` | 255* | ✅ 可用 | help 文本完整打印（*Android `cmd help` 常见非 0） |
| D08 | `dumpsys bluetooth_manager` | 0 | ✅ 可用 | `enabled: false`，`state: OFF`，`Bluetooth Service not connected` |
| D09 | bluetooth getprop | 0 | ✅ 可用 | `vendor.bluetooth-1-1` running |
| D10 | `dumpsys media.camera` | 0 | ✅ 可用 | 1 camera，Facing Front，HardwareLevel EXTERNAL，device `142` |
| D11 | `ls /dev/video*` | 0 | ✅ 可用 | `/dev/video42` 存在 |
| D12 | `dumpsys sensorservice` | 0 | ❌ 不可用 | `No Sensors on the device`；`devInitCheck : -19` |
| D13 | battery script / sysfs | 0 | ⚠️ 部分可用 | script 存在；`/sys/class/power_supply/battery/capacity` **No such file** |

#### 注入 / 控制尝试

| ID | 命令意图 | Exit | 实测标注 | 关键结果摘要 |
|---|---|---|---|---|
| M01 | 写 gnss 为北京坐标 | 0 | ⚠️ 部分可用 | 文件变为 `39.9042,116.4074`；属未文档化内部文件 |
| M02 | `set-location-enabled true` | 0 | ✅ 可用 | `is-location-enabled` → `true` |
| M03 | `add-test-provider mockgps` | 255 | ❌ 不可用 | `SecurityException: ... not allowed to perform MOCK_LOCATION` |
| M04 | `set-test-provider-location` | 255 | ❌ 不可用 | 同上 MOCK_LOCATION |
| M05 | appops allow 后重试 | 255 | ❌ 不可用 | 仍 MOCK_LOCATION（uid 0 / shell） |
| M06 | GPS extra + 再 dumpsys | 0 | ❌ 不可用（作 mock） | `last location` 仍全部 `null`；`mStarted=false` |
| M07 | `svc wifi enable` | 1† | ❌ 不可用 | 短暂切 Enabled 后 `CMD_STA_START_FAILURE` / `WifiNative Failure`；`wlan0` does not exist；`hwsim0` DOWN |
| M08 | `cmd wifi help` | 0 | ✅ 可用（仅帮助） | 有 status/scan/softap/suggestion；**无** RSSI/AP 注入 API |
| M09 | `svc bluetooth enable` | 0 | ⚠️ 部分可用 | 打印 `enable: Success`，但 2s 后仍 `enabled: false` / Service not connected |
| M10 | 写 battery capacity 文件 | 0 | ⚠️ 部分可用 | `/data/vendor/battery/.../capacity`：`98 → 55`；sysfs 路径不存在 |
| M11 | 查找 camera/mock 相关 cmd | 0 | ✅ 可用（探查） | 有 `wifi`/`location`/`media.camera`/`sensorservice`；vendor 仅 `init.redroid.gps.sh`，无 inject/mock 工具 |
| M12 | 完整 sensorservice | 0 | ❌ 不可用 | 同 D12：无传感器 |
| M13 | 写坐标后复查 location | 0 | ❌ 不可用（作 mock） | gnss 文件已是北京坐标，但 gps `last location=null`，`ProviderRequest[OFF]` |
| M14 | GNSS HAL 进程 | 0 | ✅ 可用（诊断） | `android.hardware.gnss-service` 在跑；`ro.kernel.qemu.gps=1` |
| M15 | `cmd wifi` status/scan | 0 | ❌ 不可用 | `Wifi is disabled`；`No scan results`；`smartrun.wifi.enabled=0` |
| M16 | 打开定位设置后再查 | 0 | ❌ 不可用（作 mock） | `location_mode=3`；各 provider `last location=null` |
| M17 | `cmd wifi start-softap` | 0 | ❌ 不可用 | `SAP is disabled`；`onStateChanged ... failure` |
| M18 | battery sysfs/mount | 0 | ⚠️ 部分可用 | data 文件在；`/sys/class/power_supply: Invalid argument`；`dumpsys battery` `present: false` `level: 0` |

† M07 的非 0 主要来自管道/`ip link show wlan0` 失败；关键失败点是 WiFi STA 启动失败。

#### 总评

| 目标 | 结论 |
|---|---|
| 把专项命令当 **ADB 诊断工具** | 大部分 ✅ 可用 |
| 把专项命令当 **可控硬件 mock**（WiFi AP/RSSI、GNSS 生效定位、Camera 注入、BT、传感器） | ❌ 不可用 / 仅 ⚠️ 残缺 stub |
| 是否存在官方硬件 mock 产品能力 | **否** |
---

## 4. 实验发现（摘要）

1. **官方未提供硬件 mock 产品能力**（WiFi 信号/AP、Camera、GNSS、BT、传感器等）。控制面只有 Appium / ADB / scrcpy。  
2. **底层不是 Emulator，也不是 Cuttlefish**；是 Cube Hypervisor + SmartRun/Redroid Android 14。  
3. **android-world 不是另一套虚拟化**，而是同底座加 AW 应用与适配（v23）。  
4. **专项命令复测**：诊断类 dumpsys/getprop/ip **大多可用**；作为 mock——WiFi 启用/扫描/SoftAP **失败**，GNSS 文件可写但 **location 不更新**，`cmd location` test provider **被拒绝**，BT enable **名成功实失败**，传感器 **无设备**，电池文件可写但 **sysfs 未挂上**。  
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
| `hw_mock_probe.txt` / `hw_mock_probe2.txt` / `hw_mock_probe3.txt` | 早期硬件 mock 专项 dumpsys / GPS 文件注入 / 网卡 |
| `hw_cmd_matrix/`（`D01`–`D13`、`M01`–`M18`） | **2026-07-23 复测**逐条命令 JSON/文本结果 |
| `hw_test_instance_id.txt` | 复测 InstanceId |
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
实机复测表明：报告中的硬件/mock 专项命令作为 **诊断（dumpsys/getprop）大多可用**；作为 **可控 mock（WiFi/GNSS/Camera/BT/传感器）基本不可用**，仅残留未文档化、不可靠的文件 stub。若业务需要可控硬件仿真，应评估其他方案（例如完整 Android Emulator、云手机 CPH，或自建自定义环境）。
