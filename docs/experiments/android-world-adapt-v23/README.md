# SmartRun android_world_adapt 逆向抽取分析

> 抽取时间：2026-07-25  
> 实例：见 instance_id.txt  
> 属性：`ro.smartrun.android_world_adapt.version=v23`

## 结论

`android_world_adapt` **不是独立开源仓库**，而是 SmartRun 在 Redroid 镜像编译时用
`TARGET_INCLUDE_ANDROID_WORLD_ADAPT=true` 打开的一组镜像侧改动（init/脚本/HAL stub/预装应用/overlay）。

公开可见的“源码路径线索”来自二进制字符串：
`device/redroid/radio-stub/*.cpp`（厂商树路径，未公开）。

## 组件清单（已抽取）

### A. Init / 启动脚本（可读源码级）
| 文件 | 作用 |
|---|---|
| `/vendor/etc/init/init.redroid.rc` | v23 段：boot_completed 且 adapt=1 时启动 telephony bootstrap；含 WiFi v20、Pixel 启动逻辑注释 |
| `/vendor/bin/init.redroid.android-world-telephony.sh` | **v23.2** SMS/MMS DB bootstrap（`mmssms.db`） |
| `/vendor/bin/init.redroid.pixel.sh` | Pixel Launcher / Launcher3 + 圆角图标 overlay 切换 |
| `/vendor/etc/init/smartrun-radio-stub.rc` | Radio AIDL stub 服务定义 |
| `/vendor/etc/vintf/manifest/smartrun-radio-stub.manifest.xml` | VINTF HAL 声明 |
| `/vendor/bin/smartrun-radio-stub` | Radio HAL stub 二进制（~101KB） |

### B. 编译开关（来自 init 注释）
- `TARGET_INCLUDE_ANDROID_WORLD_ADAPT=true` → 写入 `ro.smartrun.build.android_world_adapt=1`
- `ro.smartrun.android_world_adapt.version=v23`

### C. v23 核心行为：Telephony bootstrap
问题：AndroidWorld SMS 任务需要 `com.android.providers.telephony` 的 `mmssms.db`。  
Redroid/FBE 下库在 `/data/user_de/0/...`，冷启动可能未创建。

脚本逻辑：
1. sentinel: `/data/local/tmp/.android-world-telephony-init.done`
2. 循环 `content query content://sms|mms/inbox` 触发 provider onCreate
3. 确认 `/data/user_de/0/com.android.providers.telephony/databases/mmssms.db`
4. 失败则 force-stop provider 再试
5. 成功 touch sentinel；失败不写 sentinel 以便下次开机重试

### D. Radio stub（v24）
- 二进制自称 `smartrun-radio-stub starting (v24)`
- 实现 AIDL：config/sim/modem/network/voice/data/messaging
- 源码路径字符串：`device/redroid/radio-stub/{main,RadioSim,RadioModem,RadioData,RadioMessaging}.cpp`
- 由 `vendor.smartrun.telephony.enabled=1` 拉起

### E. Pixel 桌面（与 AW 视觉/任务环境相关）
- `ro.boot.smartrun.pixel.launcher.enabled=1` → NexusLauncher + `com.smartrun.overlay.pixelicons`
- `=0` → Launcher3 + 关 overlay

### F. 预装 AW 任务 App（data/app 或 system）
含 Markor/Joplin/OsmAnd/OpenTracks/Tasks/MiniWoB/`com.example.androidworld`/Simple Mobile Tools 套件/Appium 等。

## 与上游 Android World 的关系
- 上游：`google-research/android_world`（Python 评测 + Emulator）
- 此处 adapt：让 **Redroid 云镜像**具备 AW 任务所需的 SMS DB、radio stub、桌面、应用集
- **不包含** AndroidEnv gRPC `:8554` a11y forwarder

## 本目录已入库的抽取物

| 文件 | 说明 |
|---|---|
| `init.redroid.android-world-telephony.sh` | v23.2 telephony bootstrap 全文 |
| `init.redroid.pixel.sh` | Pixel/Launcher3 切换脚本 |
| `init.redroid.rc` | 完整 vendor init（含 v20 WiFi / v23 AW 注释） |
| `init.redroid.rc.v23-snippet.rc` | 仅 v23 telephony 段 |
| `smartrun-radio-stub.rc` / `.manifest.xml` | Radio stub 服务与 VINTF |

未入库（体积大）：`com.example.androidworld.apk`、`miniwob.apk`、`smartrun-radio-stub` ELF（实验机 `/tmp/ags-probe/adapt-extract/`）。

## 逆向要点

1. **构建入口**：AOSP/Redroid 产品树开关 `TARGET_INCLUDE_ANDROID_WORLD_ADAPT`，不是运行时动态下载的插件。  
2. **v23 真正“适配”的硬问题**：FBE 下 SMS provider DB 未创建 → AW SMS 任务失败；用 content query 强制 bootstrap。  
3. **radio-stub 源码树线索**：`device/redroid/radio-stub/*.cpp`（闭源/未公开）。  
4. **MiniWoB / androidworld APK**：标准 WebView 任务资源（`assets/html/miniwob/*`），偏基准内容而非 SmartRun 核心逻辑。
