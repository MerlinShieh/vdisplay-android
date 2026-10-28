# 变更记录

## 2026-10-27 · 方案落地

- 验证 A 路线（`overlay_display_devices`）失败：`SecurityException`（owner 是 system）
- 走通 B 路线：`app_process` 宿主 + `createPackageContext("com.android.shell")`
- 固化服务化产物：`vd.jar` + `vdisplay` 脚本
- 写技能 `virtual-display`，入全局记忆
- 实测：启动设置 → 点 WLAN → 抓帧确认，全程主屏前台未变

**当日踩坑**：
- 系统上下文包名不行（`packageName must match the owner uid`）
- 进程内 `startActivity` 不行（`package=android does not belong to uid=2000`）
- `--windowingMode 5` 在 MIUI 上无效
- 一度误判"跨屏搬任务已不支持"——实际是把 taskId 当 stackId 传错了

## 2026-10-28 · 坐标表体系 + 工具链加固

**坐标表**
- 新增 `coords/wechat.md`、`coords/zhihu.md`、`coords/bilibili_in.md`
- 明确"主屏采集、虚拟屏复用"的工作方式
- B 站补充**视频播放页**整页坐标（操作条 / UP 主区 / 四连 / 相关推荐 / 评论区）
- 各表标注禁点项：知乎「全部已读」、B 站「一键已读」「发布」「发弹幕」「评论输入框」、微信输入框

**工具链**
- 新增 `grab.sh`：截图 → 拉回 → 删设备端，不再经过 `/sdcard`
- `pull.sh` 从 `nc -w 20` 改为 `nc -q 1`，单张传输 31 s → 2 s
- `vdisplay shot` 默认路径从 `/sdcard/vdisplay.png` 改为 `/data/local/tmp/.vs/vdisplay.png`
- 新增 `pull.sh` 反向传输能力（原来只有 push）

**修复**
- `vdisplay swipe` 参数错位导致静默失效（见 gotchas 第 1 条）
- `stop` 二次抢焦点的竞态（`.restore` 文件机制）
- 宿主反射：`taskId` 在父类 `TaskInfo`，需沿继承链查找

**清理**
- 删除 `/sdcard/DCIM/Minis` 及其 8.5 MB `.trashed-*` 残留，媒体库记录归零

**用户规则固化**（写入 SKILL.md 与 GLOBAL.md）
1. 边执行边出图，不许事后汇总；并排必须 `montage.py` 拼图，表格里不放图
2. 截图必须压缩（`shrink.py` → 360×640 JPEG ≈ 10 KB）
3. 每步播报格式：`**步骤 N · <动作>**` + 判断依据
4. 收尾自动 `park` → `stop`，不问用户
5. 文本/操作型 App → 虚拟屏；视频/直播/游戏/导航/通话 → 前台；reclaim ≥3 次改前台

**实战记录**
- 知乎：推荐页首条 → 点进回答页 → 读完「袋鼠」的回答
- B 站：搜索 → 极客湾主页（563.9 万粉）→ 最新视频《旗舰手机芯片大横评》→ 翻 46 屏读完前 100 条评论
- 视频数据：181.5 万播放 / 3.5 万弹幕 / 32641 评论 / 21 万赞
