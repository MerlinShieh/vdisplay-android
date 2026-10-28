# 踩坑记录

按主题归类，每条都是实测结论，不是推测。

---

## 1. 注入静默失败：`input` 参数顺序

`input` 的语法是 `input [<source>] [-d DISPLAY_ID] <command>`，**`-d` 必须在子命令之前**。

```sh
input -d 231 swipe 640 2200 640 1200 300    # ✅
input swipe 640 2200 640 1200 300 -d 231    # ❌ 静默失败，不报错
```

**症状**：命令看似执行、返回 ok，但画面 md5 完全不变。因为事件被注入到了默认屏（主屏）——你以为在滑虚拟屏，其实在滑用户的前台。

**排查方法**：操作前后对比 `screencap` 的 md5。不变 → 先怀疑注入参数，再怀疑 App。

**连带 bug**：`vdisplay.sh` 的 `swipe` 一度参数错位（把 `$6` 当时长、`$7` 当包名，实际反了），导致整条命令失效。已修为
`swipe) D=$(cur_disp "$7"); input -d $D swipe $2 $3 $4 $5 ${6:-300}`。

---

## 2. 截图污染相册

**错误做法**：`screencap -p /sdcard/DCIM/Minis/x.png` + `MEDIA_SCANNER_SCAN_FILE` 广播 + `android-photos export`。

三个后果：
1. 被 MediaStore 收进系统相册，用户看到一堆莫名其妙的图
2. `rm` 之后**不是真删** —— MediaStore 会改名成 `.trashed-<id>-<name>` 塞进回收站，文件仍在、记录仍在（实测残留 8.5 MB）
3. 多一次无谓的媒体库往返

**正确做法**：截图落 `/data/local/tmp/.vs/`（MediaStore 不扫描该路径，实测 `content query` 记录数 0），nc 拉回沙箱后立刻删设备端。封装就是 `grab.sh`。

**禁用**：`android-photos list/export` 处理截图、`MEDIA_SCANNER_SCAN_FILE`。

---

## 3. `nc` 传输超时陷阱

设备端 toybox nc 的 `-w` 是**连接**超时，不是传输超时。`nc -w 20 <ip> <port> < file` 发完数据后仍会挂住等连接关闭，实测每张图卡 **31 秒**。

正确参数是 **`-q 1`**（EOF 后 1 秒退出）：

```sh
nc -q 1 127.0.0.1 9881 < file    # ✅ 2 秒
nc -w 20 127.0.0.1 9881 < file   # ❌ 31 秒
```

另外单次传输别超过 ~3 MB，再大容易被截断。批量就 tar 打包分批发。

---

## 4. 虚拟屏不能写死分辨率/密度

早期建屏时写死 720×1280@320，App 字号缓存被污染，知乎出现**文字重叠**，只能 `am force-stop` 恢复。

改为宿主运行时从 `Display.getRealMetrics()` 读主屏参数再建屏，与主屏完全一致（1280×2772@520dpi），坐标才能 1:1 复用。

---

## 5. 窗口树 dump 读不到虚拟屏

`uiautomator dump --compressed` 和 `android-a11y-cli ui dump` **都只读默认显示器（主屏）**，拿不到虚拟屏上的控件树。

推论：
- **采集阶段必须前台**（把 App 拉到主屏，dump，拿到 `resource-id` + `bounds` 中心点）
- **使用阶段直接在虚拟屏注入坐标**

B 站国际版（`com.bilibili.app.in`）是 Compose 界面，`uiautomator dump` 会报 `could not get idle state`（首页 feed 持续动画不 idle），改用 `android-a11y-cli ui dump`，并且**很多元素只有 `contentDesc` 没有 `text`**，解析时要两个字段都取。

---

## 6. `uiautomator dump` 的坑：只读主屏

同第 5 条，另注意：如果一个 App 同时在主屏和虚拟屏有任务，dump 出来的是主屏那个。

---

## 7. 跨屏搬任务：用 rootTaskId，不是 taskId

```sh
cmd activity display move-stack <rootTaskId> <displayId>   # ✅
```

早期把 `taskId` 当 `stackId` 传给 `move-stack`，报"找不到 stack"，一度误判成"跨屏搬任务已不支持"。实际参数类型搞错了。这是 `takeover` / `park` 的实现基础。

---

## 8. 宿主反射：字段在父类

Android 17 的 `ActivityManager.RunningTaskInfo` 里，`taskId` 字段定义在父类 `TaskInfo`，直接 `getDeclaredField("taskId")` 拿不到，要**沿继承链往上找**。同理 `getTasks(int, boolean, boolean, int)` 的签名在不同版本有差异，已缓存反射对象。

---

## 9. shell 身份发不了通知

- `getIntentSender() ... not allowed to send as package android`
- 宿主进程发也失败：`Package android is not owned by uid 2000`
- **Toast 同样失败**（包名/uid 不匹配）

只能 `cmd notification post` 发**不可点击**的通知，tag 固定 `minisvdisplay`。

---

## 10. 知乎短内容容器页在虚拟屏上不滚动（已定位为误判）

一度以为 `ShortContainerHostActivity` 对虚拟屏的触摸事件响应异常，试了 `input swipe`、`PageDown`、连续快滑全部无效。

**真相是第 1 条的参数 bug**，事件全打到主屏去了。修复后该页面滚动完全正常。教训：遇到"点了没反应"先查注入参数，不要先怀疑 App 兼容性。

---

## 11. `stop` 会二次抢前台

销毁虚拟屏时系统重算焦点，会把 park 过的任务顶回前台。对策：`park` 时写 `/data/local/tmp/.restore`，`stop` 拆屏后 2 秒再 `am start -n` 恢复一次（日志 `RESTORED_AFTER_STOP`）。`takeover` 会清掉该文件。

---

## 12. 抢占主屏的 App 自己会跑掉

知乎启动后会**自己跳到主屏**（`where` 变 display=0，虚拟屏抓帧全黑 6358 字节）。B 站直播间/视频页也会请求前台。

对策：宿主注册 `TaskStackListener`，`onActivityLaunchOnSecondaryDisplayRerouted` 事件驱动回收（毫秒级），轮询只兜底。reclaim ≥3 次的 App 建议直接改前台操作。

---

## 13. 剪贴板在后台不可用

Android 10+ 限制非前台 App 读剪贴板（`clipboard_requires_foreground`），`android-clipboard` 和 `cmd clipboard` 都不行。

**输入中文的替代方案**：不要用 `input text`（只支持 ASCII，中文静默失败），改用 intent 直达目标页，例如

```sh
am start -a android.intent.action.VIEW -d "bilibili://space/25876945" --display 232
```

注意：如果 App 在主屏和虚拟屏都能处理这个 intent，系统会弹「打开方式」选择器，要点对应的 App 图标。

---

## 14. push 覆盖文件会丢执行权限

`push.sh` 用 `nc` 裸流覆盖设备端文件后，权限位变成 `rw-rw-rw-`，`vdisplay` 脚本失去可执行权限。脚本里已加 `chmod 755`。

---

## 15. 截图文件名必须唯一（旧流程的问题）

`android-photos export` 靠文件名去媒体库查 id，同名会命中历史文件导错图。改用 `grab.sh` 后每次拉完即删，这个问题自然消失。
