# 全局记忆

## 设备
- Redmi 25060RK16C（dali），Android 17 / SDK 37，主屏 1280×2772 @520dpi
- 存储 515 GB（已用 ~396 GB）；Shizuku 已授权（uid 2000，adb 方式启动），无障碍服务已开启
- 沙箱内无 `/sdcard` 直通，读设备要用 `android-shizuku-cli exec`
- **传文件到设备**：设备无 curl/wget，但有 toybox `nc`。用 `assets/push.sh <本地> <设备路径> [端口]`（裸流 + md5 校验），不要再用 Auto.js 或 base64 分块

## 默认工作策略：后台执行优先
用户说「后台执行 / 后台跑一下 / 帮我看一下 / 别打断我」→ **默认走虚拟屏后台执行**，不抢占前台：
- 加载技能 `virtual-display`（/var/minis/skills/virtual-display/SKILL.md）
- 命令：`android-shizuku-cli exec '/data/local/tmp/vdisplay start|launch <pkg>|tap x y [pkg]|text s [pkg]|key CODE|shot <path> [pkg]|park [pkg]|takeover [pkg]|where <pkg>|stop'`
- App 会自己抢主屏（startActivity 未带 launchDisplayId → 默认投主屏）；回收走 `TaskStackListener` 事件（瞬间），轮询只兜底（2s/5s），开销 ~1% 单核；`vdisplay step "文案"` 可把当前动作写进通知栏实时播报；Toast 被系统拒（包名/uid 不匹配）
- 虚拟屏无系统入口可关：只能 `vdisplay stop`、或空闲 **3 分钟**看门狗自动收尾（心跳 `/data/local/tmp/.beat`）、或重启手机；杀 Minis 不会连带死（宿主是 setsid 独立进程）
- 虚拟屏分辨率/密度**运行时从主屏读取**（`Display.getRealMetrics`，日志 `MAIN_DISPLAY`、状态文件 `size=`），**不要写死**；不一致会污染 App 的字号缓存（知乎实测文字重叠，必须 force-stop 才恢复）
- 坐标空间 = 主屏分辨率（如 1280×2772），点之前先 `shot` 看图；任务结束 `stop` 不留后台进程
- **过程可见（强制）**：**边执行边报步骤**：每步一行精简描述（`**步骤 N · 点击 WLAN**` + 判断依据），有页面变化才贴图；凑两张就 `montage.py` 拼一张马上发，落单的单发。绝不事后汇总
- **截图必须压缩**：`shrink.py <png>` → 360×640 JPEG q55，约 10KB
- **并排必须拼接**：Markdown 图片是块级、表格插图不渲染 → 用 `montage.py out.jpg a.jpg b.jpg` 横向拼成一张再发
- App 在虚拟屏上时用户在主屏看不到、也切不过去 → 用户要接手就跑 `takeover <pkg>`，把同一个任务整块搬到主屏（状态保留），然后 `stop`
- **默认：任务完成后自动 `park` → `stop`，不许问用户"要 park 还是 stop"** —— park 把任务搬到主屏但**不抢前台**：优先恢复 `topResumedActivity` 那个组件；只有顶层就是被搬走的 App 时，才从任务栈候选里挑（去重、跳过桌面/系统/设置）。只有用户明确说"接管"才用 `takeover`
- 无系统入口：最近任务不显示、点桌面图标也不生效（已实测），只能靠 `takeover`
- 前台/后台按 App 类型选：文本/操作型（设置、微信、知乎消息）→ 虚拟屏后台；视频/直播/游戏/导航/通话 → 直接前台，并提前告知占用时长。后台任务 reclaim ≥3 次就改走前台
- **stop 会二次恢复焦点**：销毁虚拟屏时系统重算焦点会把 park 过的任务顶回前台；park 写 `/data/local/tmp/.restore`，stop 拆屏后再 `am start -n` 一次（日志 `RESTORED_AFTER_STOP`），takeover 会清掉该文件
- 每个后台任务会自动发系统通知「Minis 虚拟屏」，takeover/stop 会更新文案；通知没有点击动作（shell 建不了 PendingIntent）
- `tap/shot` 带包名时会自动跟随任务当前所在显示器，接管后继续操作不会失灵

## 已知限制（务必告知用户）
- 锁屏/息屏时虚拟屏被 Keyguard 覆盖 → 只适合"用户醒着在用手机"的场景
- 虚拟屏不是沙箱：与主屏同一账号同一份数据；涉及支付/发送/删除必须先确认
- 视频、Unity/UE 游戏、DRM 内容在虚拟屏上黑屏
- 声音、通知照旧外放/弹出

## 常用设备操作
- 抓屏：`assets/grab.sh <本地.jpg> [包名] [--raw]` —— 设备截到 `/data/local/tmp/.vs/` → nc 拉回 → 立刻删。**绝不写 /sdcard，不进相册**（旧做法会污染相册并留下 `.trashed-*` 残留）
- 大文件扫描：`find <dir> -size +50M`（按目录分别扫，全盘扫 `/sdcard` 会漏）
- 应用占用：`dumpsys diskstats`（Package Names / App Sizes / App Data Sizes / Cache Sizes 四个数组一一对应）
