# 设备与部署

## 设备

| 项 | 值 |
|---|---|
| 型号 | Redmi 25060RK16C（dali） |
| 系统 | Android 17 / SDK 37 |
| 主屏 | 1280×2772 @ 520dpi |
| 存储 | 515 GB（已用 ~396 GB） |
| Shizuku | 已授权，uid 2000（adb 方式启动） |
| 无障碍服务 | 已开启 |

## 权限模型

整条方案依赖 **Shizuku 的 shell 权限**（uid 2000），不需要 root：

- `DisplayManager.createVirtualDisplay` —— 以 shell uid 建屏，owner 是自己，`am start --display` 才放行
- `am start --display` / `am force-stop`
- `input -d <displayId> tap|swipe|text|keyevent`
- `screencap -d <SurfaceFlinger display id>`
- `cmd activity display move-stack`（takeover / park）
- `content query`（MediaStore 查询）

**不需要 root 的部分**：读不了 `/data/data/<pkg>`，所以拿不到 App 内的登录 token（这也是评论 API 只能翻 UI 的原因）。

## 文件清单

| 设备路径 | 说明 |
|---|---|
| `/data/local/tmp/vd.jar` | 宿主进程（`app_process` + dex） |
| `/data/local/tmp/vdisplay` | 控制脚本，`start/stop/launch/takeover/park/where/tap/swipe/key/text/shot/step/notify` |
| `/data/local/tmp/.vs/` | **截图暂存区**（MediaStore 不扫描，绝不用 `/sdcard`） |
| `/data/local/tmp/.beat` | 空闲看门狗心跳，3 分钟无命令自动 stop |
| `/data/local/tmp/.restore` | `park` 写入，`stop` 后据此二次恢复焦点 |
| `/data/local/tmp/vdisplay.log` | 宿主日志（`MAIN_DISPLAY`、`RECLAIM_EVENT`、`RESTORED_AFTER_STOP`） |

## 编译链

```sh
# 沙箱侧
apk add openjdk17-jdk jq python3 ripgrep py3-pillow
# 反编译 Android 17 的 android.jar 用于编译 VdMain.java，再用 r8 打包
javac -source 1.8 -target 1.8 -bootclasspath android.jar -d out VdMain.java
java -cp r8.jar com.android.tools.r8.R8 --release --minimal-main-dex ...
```

编译产物 `assets/vd.jar` 只有 7 KB。

## 传输（沙箱 ↔ 设备）

设备**没有 curl / wget**，但 toybox 有 `nc`。所以走裸流 + md5 校验：

| 方向 | 脚本 | 要点 |
|---|---|---|
| 沙箱 → 设备 | `push.sh` | 沙箱 `nc -l`，设备 `nc -w 15 127.0.0.1 <port>`；传完 `chmod 755` |
| 设备 → 沙箱 | `pull.sh` | 设备 `nc -q 1 127.0.0.1 <port> < file`（**必须 `-q 1`**，用 `-w 20` 每张图卡 30 秒） |

沙箱和设备共享 loopback（PRoot 与 Android 同一网络栈），所以 `127.0.0.1` 直连。

单次传输上限约 3 MB，批量要 tar 分批发。

## 性能

- 事件驱动回收后，宿主 8 秒 0 tick，合计 ≈ 1% 单核，内存 ~123 MB
- 空闲轮询 2 秒一次；有任务时 200ms
- `grab.sh` 一张图约 3 秒（截 + 传 + 删）

## 一次完整调用的耗时参考

| 操作 | 耗时 |
|---|---|
| `vdisplay start` | ~3 s |
| `vdisplay launch <pkg>` | 7–10 s（App 冷启动） |
| `grab.sh` 单张 | ~3 s |
| `tap` + 等页面 | 5–8 s |
| `vdisplay stop` | ~2 s |
