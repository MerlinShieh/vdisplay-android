---
name: virtual-display
description: 在 Android 设备上按需创建"隐藏虚拟屏"，把 App 启动到这块屏上、注入点击/滑动/输入、并抓帧回看，全程不占用用户前台屏幕。当用户说"后台执行/后台跑一下/帮我操作一下 XX App/帮我看一下 XX/别打断我正在用的手机"时，优先使用本技能。
---

# 虚拟屏后台执行（virtual-display）

在 Android 上做"后台操作 App"的默认方案。核心事实：**虚拟屏是同一用户空间里的另一块显示器**，不是沙箱、不是分身 —— 屏上的 App 就是用户本人的那个 App。

## 默认策略（重要）

用户提到以下任何一种意图时，**默认走虚拟屏后台执行**，不要直接抢占前台：

- "后台执行 / 后台跑一下 / 后台帮我弄"
- "帮我看一下 XX / 帮我操作一下 XX App"
- "我要玩手机，你别打断我" / "别占我屏幕"
- 一切需要点界面按钮、且用户可能同时在用手机的任务

流程固定：`start` → 操作（launch/tap/text/shot）→ **`park` 停放到主屏后台** → `stop`。

**任务完成后默认执行 `park`，再 `stop`**（用户已明确要求）：

- `park` = 把任务搬到主屏，**但不抢前台**。恢复前台是两段策略：
  1. **优先**取 `dumpsys activity activities` 里第一处 `topResumedActivity`（主屏真正的顶层），那就是用户正在用的 App，直接 `am start -n <该组件>` 拉回来；
  2. **只有当顶层正好是被搬走的那个 App**（知乎/直播这类会自己抢主屏的）才回退：取主屏任务栈的包名列表（去重保序），跳过被搬走的 App、桌面、SystemUI、设置，选第一个剩下的，用它的 launcher 组件拉回前台。

  **不要只用候选列表**：任务栈顺序不等于最近使用顺序，会出现"把微信拉上来"这种误判（实测踩过）。
- `takeover` = 搬到主屏**并置前**，只在用户明确说"接管/我要看"时才用。
- **`stop` 会再做一次焦点恢复**（重要）：销毁显示会让系统重新评估焦点，可能把刚 `park` 到主屏的任务重新顶到前台，导致"停放白做"。所以 `park` 会把恢复目标写到 `/data/local/tmp/.restore`，`stop` 在拆屏、等 2 秒后再 `am start -n` 一次，然后删除该文件。日志里会看到 `RESTORED_AFTER_STOP <组件>`。
  `takeover` 会主动删除 `.restore`，因为那时就是要它待在前台。
- 用户说"留在后台"时连 `park` 都不做，直接 `stop`。

**收尾是自动的，不许问用户**：任务一结束就执行 `park` → `stop`，然后直接汇报结果。**绝对不要**用"要我 park 还是 stop？"之类的话把决定权推回给用户 —— 那样虚拟屏会一直挂在任务页面上，与"用户随时能接手"的设计相矛盾。

## 前置条件

- Shizuku 已授权（`android-shizuku-cli service status` 返回 `state: READY`）
- 设备上已部署：`/data/local/tmp/vd.jar` 和 `/data/local/tmp/vdisplay`
- 用 `vdisplay status` 自检，`RUNNING`/`STOPPED` 都正常

## 基本用法

所有命令都通过 shell 里的 `android-shizuku-cli exec` 执行：

```sh
android-shizuku-cli exec '/data/local/tmp/vdisplay start'
# → STARTED display=182 sf=11529215047833183923

android-shizuku-cli exec '/data/local/tmp/vdisplay launch com.tencent.mm'
# 也可以显式指定 Activity：launch com.android.settings com.android.settings.MiuiSettings

android-shizuku-cli exec '/data/local/tmp/vdisplay shot /data/local/tmp/.vs/vd.png'
android-shizuku-cli exec '/data/local/tmp/vdisplay tap 360 732'
android-shizuku-cli exec '/data/local/tmp/vdisplay swipe 360 1000 360 300 300'
android-shizuku-cli exec '/data/local/tmp/vdisplay text "hello"'
android-shizuku-cli exec '/data/local/tmp/vdisplay key 4'
android-shizuku-cli exec '/data/local/tmp/vdisplay where com.tencent.mm'
# → display=187（App 当前在哪块屏上）

android-shizuku-cli exec '/data/local/tmp/vdisplay park com.tencent.mm'
# → 停放到主屏后台，不抢前台（默认收尾动作）
# → PARKED task=3105 foreground=com.openminis.app

android-shizuku-cli exec '/data/local/tmp/vdisplay takeover com.tencent.mm'
# → 把正在跑的**同一个任务**整块搬到主屏，状态不丢；用户就能接手了
# → TAKEOVER task=3052 display=0

android-shizuku-cli exec '/data/local/tmp/vdisplay stop'
```

坐标空间 = **主屏分辨率**（宿主运行时用 `Display.getRealMetrics()` 读取主屏宽高与 dpi 并据此建屏，不要写死；状态文件里有 `size=1280x2772@520` 可核对）。点之前一律先 `shot` 看一眼，按截图里的位置换算，不要瞎点。

**自动跟随**：`tap / swipe / key / text / shot` 都接受一个可选的包名尾参，脚本会先解析该 App 当前所在的显示器再下发，所以用户把 App 接到主屏后，Agent 的后续操作会自动打在主屏上，不需要重新配置：

```sh
vdisplay tap 360 732 com.tencent.mm      # 无论 App 在虚拟屏还是主屏都能点对
grab.sh /var/minis/attachments/x.jpg com.tencent.mm
```

## 标准工作循环

0. 记住这条铁律：**边做边发图，不要做完再汇总**
1. `start`（若已在 RUNNING 就跳过）
2. `launch <包名>`
3. `shot` → 导出图片 → **把图发到会话** + 用 read_image 看清界面
4. 根据画面 `tap` / `text` / `swipe` / `key`
5. 再 `shot` → **发到会话**确认结果，循环（见"过程可见"一节）
6. 完成后 **`park` → `stop`**（自动，不问用户）

## 截图：只用 `grab.sh`，**绝不经过 /sdcard**（🔴 硬规则）

设备截图落在 `/sdcard/DCIM/**` 会被 MediaStore 收进系统相册 —— 用户会看到一堆莫名其妙的截图，删掉还会变成 `.trashed-*` 残留继续占空间。**禁止再把截图写到 `/sdcard` 下。**

正确姿势：`grab.sh` 把图截到 `/data/local/tmp/.vs/`（MediaStore 不扫描这里），立刻 nc 拉回沙箱，随即删掉设备端原图。全程不碰相册，约 3 秒/张。

```sh
# 压缩版（默认 360x640 JPEG，约 10KB）—— 日常看界面用这个
assets/grab.sh /var/minis/attachments/s1.jpg com.zhihu.android

# 原图（1280x2772）—— OCR、精细读图用
assets/grab.sh /tmp/full.png com.zhihu.android --raw

# 不带包名 = 截当前活动屏幕
assets/grab.sh /var/minis/attachments/s2.jpg
```

拿到本地路径后直接 `read_image`。

- **禁止**：`android-photos list/export` 取截图（那是给用户自己的照片用的）
- **禁止**：`MEDIA_SCANNER_SCAN_FILE` 广播
- 需要多屏批量时：设备端循环 `shot` 到 `/data/local/tmp/.vs/`，`tar` 打包后 `pull.sh` 一次拉回（单次传输别超过 ~3MB，大了会被截断，分批）

### 底层两个脚本

- `pull.sh <设备路径> <本地路径>` —— 设备 → 沙箱。设备端必须用 `nc -q 1`（EOF 后 1 秒退出）；用 `-w 20` 会让每张图卡 30 秒。
- `grab.sh` —— 上面的封装，含"拉完即删"。

### 清理历史残留

```sh
android-shizuku-cli exec 'rm -rf /sdcard/DCIM/Minis'
android-shizuku-cli exec 'content query --uri content://media/external/images/media --projection _id --where "relative_path LIKE \"%Minis%\""'
```

## 前台 or 后台：按 App 类型决策（用户已确认）

**默认后台（虚拟屏）** —— 文本/操作型，画面变化少、不需要实时盯：

- 系统设置、微信/QQ 聊天、支付宝、购物、浏览器、笔记、日历、邮件
- 知乎/微博这类的「消息、列表、评论区」页面

**默认前台（直接在主屏操作，不用虚拟屏）** —— 视频/直播/游戏/导航/通话：

- B 站、抖音、YouTube、X 的视频页、直播页
- 游戏（Unity/UE）、地图导航、视频通话、相机

判断依据：**任务是否需要连续画面更新，或用户可能想实时盯着**。是 → 前台；否则 → 后台。

### 前台操作的姿势

```sh
am start -n <包名>/<Activity>          # 直接在主屏打开
# 操作完切回用户原来的 App：
am start -n <用户原前台组件>
```

要提前告诉用户"接下来会占用屏幕，大约 N 秒"。

### 运行时切换的判据

1. 后台任务里 `reclaim` 日志出现 **≥3 次**（同一个 App 反复抢主屏）→ 说明它不适合虚拟屏，改用前台。
2. 页面进入视频/直播/游戏 → 主动说明并改走前台。
3. 用户说"我要看/接管" → `takeover`。

## 过程可见：边执行边出图（用户规则，强制）

用户要求：**在操作过程中就把截图渲染到当前对话窗口**，不要等任务全部做完再汇总展示 —— 事后列步骤图没有意义。

执行节奏（严格遵守）：

1. **每发生一次页面变化**（launch、跳转、弹窗、列表换页）→ 立刻 `shot` → `export` → `shrink`
2. **一凑够两张就拼成一张** `montage.py`，**立刻发出来**，不要攒着
3. 任务结束剩下**单张**时，单独发那一张（不拼）
4. 每一步输出都紧跟在该操作之后，**与后续工具调用混排**，形成"操作 → 出图 → 操作 → 出图"的实时节奏
5. **每一步都要有精简的文字描述**（见下节"步骤播报格式"），图片只是佐证

### 步骤播报格式（强制）

每个动作/判断都要单独一行，短、具体、可追：

```
**步骤 2 · 点击 WLAN**
判断：目标行在列表第一个，坐标 (360,733)，可直接点。
```
```
**步骤 4 · 等待加载**
判断：列表为空且顶部有转圈 → 网络慢，再等 2 秒重拍一张。
```

要求：

- **动作**：写明做了什么（打开/点击/滑动/输入/返回），带上目标名称
- **判断**：写明依据（"看到第几个图标""列表已到底""弹窗挡住按钮"），不必配图
- 一次输出只讲一步，**不要合并成一大段事后总结**
- 图文顺序：先写步骤标题 + 判断，再贴图（有变化才贴）

回传命令（一条搞定，不走相册）：

```sh
/var/minis/skills/virtual-display/assets/grab.sh /var/minis/attachments/<名>.jpg <包名>
```

返回的路径直接 `read_image`，默认已压成 360×640 JPEG（约 10KB）。需要原图做 OCR 时加 `--raw`。

**文件名不用纠结唯一性** —— `grab.sh` 每次都从设备删掉原图，不存在旧文件命中问题。

**必须拼接才并排**：Markdown 图片是块级元素、表格里插图也不渲染（都实测过），所以并排靠 `montage.py`：

```sh
python3 /var/minis/skills/virtual-display/assets/montage.py /var/minis/attachments/steps.jpg a.jpg b.jpg
# → 横向拼接 + 左上角序号，约 750×660 / 23KB
```

超过三步时按两两分条发，长图太宽会导致字太小。

## 硬限制（必须向用户说明，不要隐瞒）

- **锁屏/息屏时完全失效**：Keyguard 会盖住虚拟屏，抓到的只有锁屏时钟。所以它只适合"用户醒着在用手机"的场景，不能当夜间定时任务用。开工前可检查 `dumpsys power | grep mWakefulness`，不是 `Awake` 就先请用户解锁。
- **不是隔离环境**：虚拟屏上的 App 与主屏是同一份数据、同一个账号。能读消息就能发消息。涉及支付、转账、删除、发送消息等动作，**先问用户确认**。
- **声音和通知照旧**：App 照常外放声音、弹通知，用户能感知到。
- **部分 App 黑屏**：视频类、Unity/UE 游戏、DRM 内容渲染不出来；文本类 App（设置、微信、浏览器、购物）正常。
- **虚拟屏参数必须与主屏一致，且不许写死**：宿主启动时用 `Display.getRealMetrics()` 读取主屏真实宽高与 densityDpi 再建屏（日志打印 `MAIN_DISPLAY ...`，状态文件有 `size=` 字段）。**不要在代码/文档里写死分辨率或 dpi** —— 换设备、改显示设置都要自动跟随。
  为什么必须一致：早期写死 720×1280@320 时，App 按 320dpi 排版并缓存字号行高，搬到主屏（520dpi）后**文字重叠错行，且只有 force-stop 重启 App 才恢复**（用户实测知乎）。改成与主屏一致后已验证：干净启动 = 文字完全正常。
- **App 被"带坏"后的处理**：`am force-stop <包名>` 再重新启动，不要试图靠移动任务修复。
- **App 会自己"抢主屏"（常见）**：App 内部 `startActivity` 起新任务且没带 `launchDisplayId` 时，Android 默认投到**默认显示器**。知乎、X、B 站直播页都这样，跟"是否可调整大小"无关（它们都是 `RESIZE_MODE_RESIZEABLE_VIA_SDK_VERSION`）。
  **对策**：**回收优先走事件、轮询只做兜底**。宿主注册 `TaskStackListener`（重写 `onActivityLaunchOnSecondaryDisplayRerouted` / `onTaskMovedToFront`），App 被改投主屏的瞬间就 `moveRootTaskToDisplay` 搬回，日志 `RECLAIM_EVENT`；兜底轮询降到（有任务 2s / 空闲 5s）。实测开销 **≈1% 单核**（最初每秒 spawn dumpsys 是 9–13%）。

**回收逻辑细节**：（**自适应间隔**：有任务在虚拟屏时 **200ms**，空闲时 **2 秒**；用 binder 调 `IActivityTaskManager.getTasks(8,false,false,0)` 查任务所在屏，跑出去就 `moveRootTaskToDisplay` 搬回；反射字段只解析一次后缓存），不再 spawn `dumpsys`；shell 侧 `_watch` 只做文件级检查（触发文件 + 每 30 秒一次空闲判断），跑出虚拟屏就 `move-stack` 拉回（实测 0→208 约 2 秒内），日志记 `RECLAIM task=... 0->N (#n)`。实测开销：活跃 ~3% 单核、空闲 ~1% 单核（早期用每秒 spawn dumpsys 的方案是 9–13%）；连续 10 次仍抢就停止回收并通知"反复抢占主屏"，避免和 App 打架。
  **局限**：抢屏那一两秒画面仍会闪现在主屏上，无法完全消除。
- **视频/直播页面会自己跳到主屏**：实测哔哩哔哩点开直播间后，任务被系统移回 display 0（两次复现，不是用户操作）。所以视频类 App 不适合虚拟屏；真要跑，进播放页后必须再 `move-stack` 搬回去，而且随时可能再次跳走。这类任务建议直接前台执行。
- **不能后台点"另一个 App 的弹窗"**：虚拟屏上的界面是独立的，主屏的弹窗它看不到。
- 同一时刻只能有 1 块虚拟屏（服务单例）。

## 生命周期与可见性（回答"会不会自己跑 / 我能不能看到"）

- **不会自启**：设备上只有两个静态文件（`vd.jar` 3.4 KB、`vdisplay` 2 KB），没有开机自启、没有守护进程、没有定时任务。只有 Agent 收到用户消息（或 `minis-scheduled` 任务触发）执行命令时才会拉起宿主；Minis 被杀掉后它也不会自己重启。
- **进程会残留**：宿主是 `setsid` 脱离的，任务中断且没 `stop` 会一直挂着（曾实测出现 2 个残留）。脚本已加固：`start` 和 `stop` 都会 `kill` 所有 `vd.VdMain` 进程。保险起见收尾一律 `stop`，或先 `status` 检查。
- **系统 UI 里没有入口**：虚拟屏画面只输出到 ImageReader，不渲染到任何物理屏幕，所以不存在"切到那块屏"的操作。
- **最近任务里不会出现它**：实测确认，虚拟屏上的任务不在主屏的最近任务列表中（列表里出现的"设置"卡片是另一个残留在主屏的任务，别混淆）。用户没有任何系统入口能切到虚拟屏的任务上。
- **想监看/接手就 `takeover`**：需要让用户看到或接手时，跑 `vdisplay takeover <包名>` 把任务整块搬到主屏（见下一节）；只想让用户瞄一眼进展，就 `shot` 抓图发到聊天。

## 状态通知（每个后台任务都会发）

`launch` 成功后在系统通知栏发一条通知，让用户知道"有个 App 正在别的屏幕上跑"：

- 标题：`Minis · 后台运行中`
- 正文：`<包名> · 正在虚拟屏上运行 · 说「接管」切回前台，说「停」结束`
- `takeover` 会把同一 tag 更新成 `已交还到主屏`；`stop` 更新成 `虚拟屏已关闭`
- 自定义文案：`vdisplay notify "哔哩哔哩 · 老实憨厚的笑笑 直播间 ｜ 声音播放中 · 说「接管」切回前台"` —— 脚本只能拿到包名，**建议 launch 后用 notify 覆盖一次**，把 App 中文名和当前页面写清楚

限制：**Toast 做不到** —— shell 进程尝试 `Toast.makeText` 会被拒：`SecurityException: Package android is not owned by uid 2000`（和通知一样，进程包名与 uid 不匹配）。所以"实时反馈"只能用 `cmd notification post` 走通知栏。

其他限制：

- shell 无法创建 PendingIntent（`getIntentSender() ... not allowed to send as package android`），所以**通知没有点击动作**，点它不会跳转，更不会把任务拉回前台。它纯粹是状态提示。
- 用户手动滑掉通知不影响后台运行，只是看不到状态了。

## 与用户的边界：App 会"从主屏消失"

这是本方案最容易引起误解的地方，务必主动告知用户：

- App 一旦跑到虚拟屏上，**用户在主屏既看不到，也没有任何系统入口切过去**（虚拟屏画面不输出到物理屏，任务也不在主屏最近任务里）。
- **点桌面图标也无效**：已由用户实测确认 —— 点图标后任务仍在虚拟屏（`where` 仍为 VD 的 display id），主屏前台不变，等于什么都没发生。系统把 launcher intent 重新投递给了虚拟屏上的那个已有任务。
- **但可以整块接出来**：`cmd activity display move-stack <taskId> 0` 实测有效 —— 任务连同 Activity 状态一起搬到主屏，前台继续，**不是重新启动、不丢进度**。脚本已封装成 `takeover`。
- 搬过来之后，虚拟屏就是空的了，可以放心 `stop`。

对应的处理规则：

1. **短租期**：虚拟屏只在真正操作的窗口期存在，做完立刻 `stop`，不要长期挂着。
2. **收尾用 `park`，接手才 `takeover`**：默认 `park`（搬过去但不抢前台，用户无感）；用户说"我来/我要看/接管"才用 `takeover`（搬到前台）。**不要**用重新启动 App 的方式代替，那样会丢状态。
3. **开工前一句话**：如果我要操作的是用户此刻正在用的 App，先说清楚"接下来这一小会儿这个 App 会从你的屏幕上消失，想接手随时说一声"。
4. **自动跟随**：`tap/shot` 带上包名时脚本会重新解析显示器，所以接手后我的后续动作会继续打在主屏，不会失灵。
5. **不适合的场景**：视频、直播、导航、通话这类用户需要实时盯着的 App，默认走前台操作，不要用虚拟屏。
6. **用户喊停**：立刻 `takeover`（或 `stop`），把控制权交回去。

## 用户自己手动接管（不经过 Agent）

已经给用户做好一个 **Auto.js 悬浮球**：`/sdcard/Scripts/vd-takeover.js`

- 点一下 → 接管；长按拖动可换位置；日志写 `/sdcard/Scripts/vd-run.log`
- **注意**：这台设备的 Auto.js 只会调 `su`（无 root 直接失败），拿不到 shell。所以球的实现是**写触发文件** `/sdcard/Scripts/.takeover`，由脚本里的 `_watch` 守护进程（2 秒轮询）执行 `move-stack`。球自己不做特权操作。
- 触发链路：`vdisplay start` 会拉起 `_tick`（刷通知）和 `_watch`（盯触发文件）；接管成功后 watcher 自行退出。
- 需要用户手动做的一步：在 Auto.js 里打开该脚本并点运行（要授权无障碍 + 悬浮窗）。
- **此版本 Auto.js 的坑（已实测）**：`floaty.rawWindow` 没有 `setOnTouchListener`；`win.setOnLongClickListener` 会抛 `Cannot convert function to interface`。能用的写法是 `floaty.window` + 对子控件 `win.txt.click(...)`。
- 已验证链路：点球 → 写 `/sdcard/Scripts/.takeover` → 守护进程 2 秒内 `move-stack` → 任务回到主屏（实测任务 #3055 从 display 193 搬到 0）。
- 脚本重复运行会产生多个球，重启用 `am force-stop org.autojs.autojs`。

## 关掉虚拟屏的方式（没有系统入口）

虚拟屏不在最近任务、不在设置里，用户**没有系统 UI 入口**。可用的方式只有：

| 方式 | 说明 |
|---|---|
| `vdisplay stop` | ✅ 最直接，Agent 收尾会自动调用 |
| 空闲看门狗 | ✅ `_watch` 发现超过 **3 分钟**没有任何 `vdisplay` 命令（心跳文件 `/data/local/tmp/.beat`），自动 `stop` 并通知 |
| 重启手机 | ✅ 一定生效，偏重 |
| 杀 Minis App | ❌ 宿主是 `setsid` 脱离的独立进程，杀 App 不会连带死 |

所以 Agent 中断时（对话被关、进程被杀），最多再空转 3 分钟就会自行收尾。

## 常见故障

| 现象 | 处理 |
|---|---|
| `FAIL` | `cat /data/local/tmp/vdisplay.log` 看堆栈；多半是 Shizuku 掉线或残留 state |
| `NO_DISPLAY` | 服务已死但 state 残留：`rm /data/local/tmp/vdisplay.state` 后重新 `start` |
| `NOT_RUNNING` | 先 `start` |
| `NO_ACTIVITY <pkg>` | 包名错了，或该 App 没有 LAUNCHER 入口，改用 `launch <pkg> <activity>` |
| 抓到的是锁屏时钟 | 设备锁屏了，请用户解锁后重试 |
| 抓到全黑 | 该 App 在虚拟屏上渲染失败（视频/游戏），改用前台操作 |

## 重新部署（设备被清或 jar 丢失）

资产在 `assets/`：

- `vd.jar` → 推到 `/data/local/tmp/vd.jar`
- `vdisplay.sh` → 推到 `/data/local/tmp/vdisplay` 并 `chmod 755`

**传文件用 `assets/push.sh`（nc 裸流，一步搞定，自动校验 md5）**：

```sh
/var/minis/skills/virtual-display/assets/push.sh /var/minis/workspace/vd.jar /data/local/tmp/vd.jar
# → OK /data/local/tmp/vd.jar  5125B  md5=4fc02ad3...
```

原理：沙箱 `nc -l` 一次性把文件裸流吐出 → 设备 `toybox nc 127.0.0.1 <port> > 目标` → 两边比对 md5。

> 设备**没有 curl/wget**，但有 toybox 的 `nc/netcat`（实测可用）。以前靠 Auto.js 下载或 base64 分块（8 段、出过误码），现在都不需要了。
> 若一次失败，换端口重试即可（脚本默认 9877）。

`android-shizuku-cli file push` 只能设备内互拷，**不能**从 /var/minis 直接推到设备，别用它跨端传。

重新编译（改了 `VdMain.java` 时）：

```sh
apk add openjdk17-jdk
curl -sL -o /tmp/android.jar https://repo1.maven.org/maven2/org/robolectric/android-all/14-robolectric-10818077/android-all-14-robolectric-10818077.jar
curl -sL -o /tmp/r8.jar https://maven.google.com/com/android/tools/r8/8.3.37/r8-8.3.37.jar
javac -source 8 -target 8 -cp /tmp/android.jar -d /tmp/out /tmp/src/vd/VdMain.java
java -cp /tmp/r8.jar com.android.tools.r8.D8 --lib /tmp/android.jar --min-api 30 --output /tmp/outdex /tmp/out/vd/*.class
# 打包：把 classes.dex 塞进 zip 改名 vd.jar
```

## 实现要点（排查时看）

- 宿主是 `app_process` 跑在 **shell uid (2000)** 下的 dex，`ActivityThread.systemMain()` 取系统上下文，再用 `createPackageContext("com.android.shell")` 换成 shell 包名 —— 否则 `createVirtualDisplay` 会抛 `packageName must match the owner uid`。
- 屏是 `VIRTUAL_DISPLAY_FLAG_PUBLIC | OWN_CONTENT_ONLY`，表面是尺寸与主屏一致的 ImageReader（必须持续消费帧，否则生产者阻塞）。
- 启动 App 只能用 `am start --display <id>`；进程内 `Context.startActivity` 会抛 `package=android does not belong to uid=2000`。
- 屏的 owner 是 uid 2000，所以 `am start --display` 走的是 owner 分支 —— 这也是唯一能在非 root 设备上投放 Activity 的方式（系统拥有的 overlay 屏会被 `SafeActivityOptions` 拒绝）。
- 停止靠 `/data/local/tmp/vdisplay.stop` 哨兵文件，宿主检测到就释放显示器并退出。
