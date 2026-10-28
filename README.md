# vdisplay-android

**非 root 的 Android「隐藏虚拟屏」后台执行方案** —— 在 Redmi（Android 17 / SDK 37）上实现，用 Shizuku 的 shell 权限驱动一块用户看不见的虚拟屏，把 App 投到上面、注入触摸事件、抓帧读屏。全程不占用前台屏幕，不需要 root。

```
┌──────────────────────────────────────────────────────────────┐
│  沙箱（Alpine）               设备（Android 17）              │
│  ┌──────────────┐  shizuku  ┌──────────────────────────┐   │
│  │ vdisplay.sh  │ ────────▶ │ app_process 宿主 (vd.jar) │   │
│  │  tap/swipe   │           │  → DisplayManager        │   │
│  │  shot/text   │           │  → 虚拟屏 + TaskStackListener │
│  │  grab.sh     │ ◀── nc ── │  screencap -d <sf id>    │   │
│  └──────────────┘           └──────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## 目录

| 路径 | 内容 |
|---|---|
| [`skills/virtual-display/SKILL.md`](skills/virtual-display/SKILL.md) | **主文档**：标准工作循环、前后台决策、过程可见性规范、硬限制、故障排查 |
| `skills/virtual-display/assets/` | 设备端宿主源码（`VdMain.java`）、编译产物 `vd.jar`、控制脚本 `vdisplay.sh`，以及沙箱侧工具链（`push.sh` / `pull.sh` / `grab.sh` / `shrink.py` / `montage.py`） |
| [`coords/`](coords/) | **App 控件坐标映射表**：微信 / 知乎 / B 站国际版。主屏采集，虚拟屏 1:1 复用 |
| [`notes/`](notes/) | 踩坑总结（按主题归类）、设备与部署信息、变更记录 |
| [`memory/`](memory/) | 全局记忆规则 + 每日工作日志（原始记录） |

## 核心设计

**为什么不用 `overlay_display_devices`？**
系统 setting 创建的 overlay 屏 owner 是 `system`，`am start --display` 会被 `SafeActivityOptions.checkPermissions` 直接拒绝（`SecurityException: from null`）。自建屏的 owner 是 shell uid 2000，系统放行 —— 这是整条方案能跑通的关键。

**坐标可以跨屏复用。**
虚拟屏与主屏同参数（1280×2772@520dpi，宿主运行时从 `Display.getRealMetrics()` 读取，不写死）。所以控件树在主屏采集一次，虚拟屏上直接 `input -d <displayId> tap x y` 注入即可。`uiautomator dump` 和 `android-a11y-cli ui dump` 都只读默认屏，读不到虚拟屏。

**回收靠事件驱动，不靠轮询。**
宿主注册 `TaskStackListener`，App 自己抢主屏时（`startActivity` 没带 `launchDisplayId` → 默认投主屏）毫秒级搬回虚拟屏。轮询只兜底。

## 快速开始

```sh
# 部署（一次性）
apk add openjdk17-jdk jq python3 ripgrep py3-pillow
skills/virtual-display/assets/push.sh skills/virtual-display/assets/vd.jar /data/local/tmp/vd.jar
skills/virtual-display/assets/push.sh skills/virtual-display/assets/vdisplay.sh /data/local/tmp/vdisplay

# 跑起来
android-shizuku-cli exec '/data/local/tmp/vdisplay start'
android-shizuku-cli exec '/data/local/tmp/vdisplay launch com.zhihu.android'
skills/virtual-display/assets/grab.sh /var/minis/attachments/s1.jpg com.zhihu.android
android-shizuku-cli exec '/data/local/tmp/vdisplay park && /data/local/tmp/vdisplay stop'
```

完整用法见 [SKILL.md](skills/virtual-display/SKILL.md)。

## 已知限制

- 锁屏/息屏时虚拟屏被 Keyguard 覆盖，只适合用户醒着用手机的场景
- 视频、Unity/UE 游戏、DRM 内容在虚拟屏上黑屏
- 虚拟屏上的任务在最近任务里看不到，用户**唯一**的接管入口是 `vdisplay takeover <pkg>`
- 通知栏只能发不可点的通知（shell 身份建不了 PendingIntent）

## 许可

个人项目，无特殊许可。
