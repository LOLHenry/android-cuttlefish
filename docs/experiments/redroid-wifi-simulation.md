# Redroid / Cuttlefish / OpenWrt：WiFi 模拟对比，以及 hostapd 是什么

> 范围：上游 Redroid、Cuttlefish（`wmediumd` + 可选 OpenWrt AP）、SmartRun/腾讯云 AGS Mobile。  
> 依据：Redroid 文档 issue、Cuttlefish 主机工具、SmartRun `init.redroid.rc`、AGS 实测（见 [`tencent-agent-runtime-mobile-hardware-mock.md`](./tencent-agent-runtime-mobile-hardware-mock.md)）。  
> 结论先行：**Redroid 没有与 Cuttlefish `wmediumd` + OpenWrt 对等的官方完整无线介质仿真；各方案里反复出现的 `hostapd` 是 AP（热点）侧协议栈，不是介质仿真器。**

---

## 1. 先分清三层：网卡、空气、热点

完整「像真 WiFi」通常要叠三层。混在一起就会觉得每个方案都有 `hostapd`，却说不清各自差在哪。

```text
┌─────────────────────────────────────────────────────────┐
│ ③ 协议 / 角色（谁当 AP、谁当手机）                         │
│    AP：hostapd（发 beacon、接受关联、WPA 握手）             │
│    STA：wpa_supplicant + Android WifiService（扫描、连接） │
├─────────────────────────────────────────────────────────┤
│ ② 无线介质（空气：丢包、延迟、SNR、是否同信道可见）         │
│    Cuttlefish：wmediumd                                   │
│    默认 hwsim：内核直接拷贝帧，人人互相听得到               │
│    Redroid 官方：无对等产品                                │
├─────────────────────────────────────────────────────────┤
│ ① 虚拟无线网卡（看起来像 wlan0 的 802.11 radio）            │
│    mac80211_hwsim  /  部分场景用 virt_wifi 伪装有线口      │
└─────────────────────────────────────────────────────────┘
```

| 层 | 解决的问题 | 典型组件 | 没有它会怎样 |
|---|---|---|---|
| ① 网卡 | 内核里有没有 `wlan*`、nl80211 | `mac80211_hwsim`、`virt_wifi` | WiFi HAL 起不来，`wlan0` 不存在 |
| ② 空气 | 信号好坏、丢包、多节点拓扑 | **`wmediumd`**（Cuttlefish 集成） | 仍能关联，但无法控 RSSI/干扰 |
| ③ AP 角色 | 必须有一个「热点」应答扫描/关联 | **`hostapd`**（OpenWrt 里也是它） | 扫不到 AP，或只能走假 NetworkInfo |

OpenWrt 出现在 Cuttlefish 一类方案里，是因为它把 **③ + 路由/DHCP** 打成一台迷你路由器镜像；它内部照样跑 `hostapd`，并不是另一种无线物理层。

---

## 2. hostapd 是干什么的

**hostapd** = *Host Access Point Daemon*（hostap / wpa_supplicant 工程的一部分）。

它跑在 **AP（接入点 / 热点）** 一侧，负责 802.11 管理面，例如：

- 发 **beacon**（让附近 STA 扫到 SSID）
- 处理 probe / association / authentication
- **WPA2/WPA3** 四次握手（authenticator）
- 在 Linux 上通常配合 nl80211，把某块无线网卡设成 AP 模式

对侧是手机上的 **wpa_supplicant**（station / STA）：扫描、选网、当客户端做握手。

```text
  手机 / Android Guest                         热点 / 路由器
 ┌─────────────────────┐                    ┌─────────────────────┐
 │ WifiService         │                    │ OpenWrt 或 router ns│
 │ wpa_supplicant (STA)│ ←── 802.11 ──→     │ hostapd (AP)        │
 │ wlan0               │                    │ wlan1 / phy         │
 └─────────────────────┘                    │ dnsmasq / NAT       │
                                            └─────────────────────┘
         ↑                                           ↑
   mac80211_hwsim 虚拟 radio                    同一套虚拟 radio
         ↑                                           ↑
              （可选）wmediumd 决定帧是否送达、延迟多少
```

它 **不是**：

- 虚拟网卡驱动（那是 hwsim / 真芯片驱动）
- 无线信道模型（那是 wmediumd 或真实空气）
- DHCP/NAT（常见是 dnsmasq、Android `dhcpserver`；hostapd 只做到二层 AP）

Android 自己当热点（SoftAP）时，**手机进程里也会起一份 hostapd**——角色仍是 AP，只是 AP 和 STA 在同一台设备上。仿真方案里再起一份 hostapd，是为了给「被测那台 Android」提供一个可扫到、可关联的对端，而不是重复实现 WiFi HAL。

---

## 3. 为什么每个完整方案里都有 hostapd

因为 **WiFi 至少是两端协议**：一端 STA、一端 AP。虚拟化只解决「网卡从哪来」，不自动产生一个热点。

| 方案 | STA 在哪 | AP（hostapd）在哪 | 为什么必须有 |
|---|---|---|---|
| **Cuttlefish** | Guest Android `wpa_supplicant` | 常在 **OpenWrt AP VM**（或等价 AP 根文件系统）里 | Guest 要扫到 SSID、完成关联；OpenWrt 用 hostapd 当无线 AP |
| **Android Emulator / Goldfish** | Guest | Guest/vendor 里的 `simulated_hostapd` 一类配置 | 同样需要虚拟 AP 发 beacon |
| **上游 Redroid + hwsim** | 容器内 Android | 自建 netns / 第二块 hwsim radio 上跑 hostapd | 作者 POC 与社区脚本都是「一块 radio 当 STA、一块当 AP」 |
| **SmartRun v20**（镜像内） | `wpa_supplicant` + `wlan0` | **router namespace** 里 `redroid_hostapd` 管 `wlan1` | `init.redroid.rc` 写明：hostapd + DHCP + NAT，eth0 迁入 router ns |
| **仅 virt_wifi / 假 NetworkInfo** | 可无真实关联 | **可以没有 hostapd** | 只把有线伪装成 WiFi，或把 Ethernet 谎称 WiFi；没有 802.11 AP |

所以：**不是「WiFi 模拟 = hostapd」**，而是「只要还走真实 802.11 关联，就必须有 AP 实现；Linux 世界里这个实现几乎总是 hostapd」。  
Cuttlefish 写 OpenWrt、Redroid 写 hostapd，说的是同一层（③），OpenWrt 多包了路由发行版。

`wmediumd` 不替代 hostapd：没有 AP，介质仿真器没有可转发的关联后数据面；没有介质仿真器，hostapd 仍能在 hwsim 默认「全连通」模式下工作。

---

## 4. 方案对比

### 4.1 总表

| 能力 | Cuttlefish | 上游 Redroid | SmartRun（AGS 镜像） |
|---|---|---|---|
| 虚拟 radio | `mac80211_hwsim` | 可行，非一等公民 | 有（`create_radios2` / hwsim） |
| 无线介质（丢包/延迟/SNR） | **`wmediumd` 官方集成** | **无** | **无证据有 wmediumd** |
| AP / DHCP / NAT | 常配 **OpenWrt AP VM**（内含 hostapd） | 需自建 ns + **hostapd** | 容器内 router ns + **hostapd** + DHCP（v20） |
| 产品化开关 | `cvd` 配置开箱 | 官方 wifi 分支曾因构建失败撤掉 | `ro.boot.smartrun.wifi.enabled`（AGS 实测 **=0**） |
| 扫描 / 关联 / SoftAP | 可用 | 自建成功后可用 | 默认关；强开实测失败 |
| RSSI / 信道 / 多节点拓扑 | wmediumd 可配 | 无官方 | 无官方注入 API |

### 4.2 拓扑对比

```text
Cuttlefish（完整向）
  Guest Android wlan (STA, wpa_supplicant)
       ↕ mac80211_hwsim
  Host wmediumd          ← 丢包 / 延迟 / SNR / 拓扑
       ↕
  OpenWrt AP VM          ← 内部 hostapd + 路由/DHCP

Redroid / SmartRun（常见完整拼装）
  Android wpa_supplicant (STA)
       ↕
  mac80211_hwsim
       ↕                 ← 无独立空气模型（内核直接拷帧）
  同机 hostapd (AP) + DHCP/NAT

Redroid 轻量 workaround
  Ethernet / virt_wifi
       → App 以为是 WiFi（假 NetworkInfo 或伪装 iface）
  可以没有 hostapd，也没有 wmediumd
```

### 4.3 和「完整 WiFi」需求的对应

| 需求 | Cuttlefish + wmediumd（+ OpenWrt） | 上游 Redroid | AGS 默认 SmartRun |
|---|---|---|---|
| 设置里能开 WiFi、能扫到 AP | ✅ | 自建 hwsim+hostapd 后可能 ✅ | ❌ 默认关 |
| 可控 RSSI / 丢包 / 漫游 | ✅ wmediumd | ❌ | ❌ |
| 多设备同信道干扰 | ✅ | ❌（需自接 wmediumd） | ❌ |
| App 只要求 `isWifiConnected` | ✅ | 假 NetworkInfo 即可 | 上网走 eth0，不是 WiFi |

上游维护者原话大意（[redroid-doc#10](https://github.com/remote-android/redroid-doc/issues/10)）：用 `mac80211_hwsim` 仿真可行，完整 WiFi 更建议 Android Emulator；也可把 WiFi `NetworkInfo` 映射成 Ethernet。社区后续还有 `virt_wifi` 讨论（[#791](https://github.com/remote-android/redroid-doc/issues/791)）。

---

## 5. SmartRun / AGS 上的实际状态

镜像里写过接近「容器内 AP」的路径（抽取物 [`artifacts/android-world-adapt-v23/init.redroid.rc`](./artifacts/android-world-adapt-v23/init.redroid.rc)）：

- `androidboot.smartrun.wifi.enabled=1` → `init.redroid.wifi.sh`
- 创建 router netns、`create_radios2`、**hostapd**、DHCP、NAT，eth0 迁入 router ns（注释称 v20）
- 依赖 **mac80211_hwsim**（注释还提到旧版 dnsmasq 在 hwsim netlink 上空转）

AGS 默认部署（2026-07 实测）：

| 观测 | 值 | 含义 |
|---|---|---|
| `ro.boot.smartrun.wifi.enabled` | **0** | 不跑 `redroid_wifi_setup` / hostapd |
| `wifi.interface` | `wlan0` | 属性有，接口未必有 |
| `ip link` | `eth0` UP，`hwsim0` **DOWN**，**无 wlan0** | radio 未真正起来 |
| `svc wifi enable` | `CMD_STA_START_FAILURE` | STA 起不来 |
| scan / SoftAP | 空 / failure | 无可用无线面 |
| `cmd wifi help` | 有 status/scan/softap | **无** RSSI/AP 注入 API |

**代码路径像可开的 hwsim+hostapd；云上产品默认关死，也没有对外 WiFi mock API。**

---

## 6. 用户面感知

| 角色 | 感知 |
|---|---|
| **AGS 默认 App / Agent** | 上网走 **eth0**；设置里 WiFi 关或打不开；扫不到网。只关心「有网」的 App 通常仍可用；强依赖 `WifiManager` / 扫热点 / SoftAP / WiFi RTT 的会失败。 |
| **自建 Redroid + 打开 hwsim/hostapd** | 设置里可能出现可关联的固定热点，像「连上某个 AP 的手机」。仍难控信号与多 AP 拓扑。 |
| **假 NetworkInfo / virt_wifi** | 部分 App 显示「已连接 WiFi」，无真实扫描列表与 RSSI。 |
| **云手机 CPH** | 另有设备注入类 API，**不要**和 AGS Mobile Redroid 沙箱混为一谈。 |

---

## 7. 怎么选

- 需要可脚本化的信道 / 多 AP / 丢包：优先 **Cuttlefish（或 Emulator）+ wmediumd**，而不是在 Redroid 上补齐。
- 需要真实 802.11 关联但不需要空气模型：Redroid/SmartRun 的 **hwsim + hostapd**（须内核模块 + 打开启动开关）。
- 只需 App 以为在 WiFi 上：**假 Connectivity** 或 `virt_wifi`，可以没有 hostapd，也不是 Cuttlefish 那套。

---

## 8. 参考

- 本仓库实测：[`tencent-agent-runtime-mobile-hardware-mock.md`](./tencent-agent-runtime-mobile-hardware-mock.md) §2.5 / §3.5（D01–D03、M07、M15、M17）
- SmartRun WiFi 服务定义：[`artifacts/android-world-adapt-v23/init.redroid.rc`](./artifacts/android-world-adapt-v23/init.redroid.rc)
- Redroid：[Virtual Wifi #10](https://github.com/remote-android/redroid-doc/issues/10)、[mac80211_hwsim #167](https://github.com/remote-android/redroid-doc/issues/167)、[improve Virtual Wifi #791](https://github.com/remote-android/redroid-doc/issues/791)
- 内核：[`mac80211_hwsim`](https://www.kernel.org/doc/Documentation/networking/mac80211_hwsim/mac80211_hwsim.rst)
- AOSP：[`platform/external/wmediumd`](https://android.googlesource.com/platform/external/wmediumd/)
- hostapd 上游：https://w1.fi/hostapd/
