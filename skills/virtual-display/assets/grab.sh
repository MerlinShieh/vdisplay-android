#!/bin/sh
# grab.sh <本地路径> [pkg] [--raw]
# 设备截图 → 沙箱，全程不经过 /sdcard，所以不进系统相册、不占媒体库。
#   默认：拉回后按 360x640 JPEG q55 压缩（约 10KB），原图立即从设备删除
#   --raw：保留 1280x2772 原图（需要 OCR / 精细读图时用），同样会删设备端文件
# 例：grab.sh /var/minis/attachments/s1.jpg com.zhihu.android
#     grab.sh /tmp/full.png com.bilibili.app.in --raw

L="$1"; PKG="$2"; MODE="$3"
PORT=9881
BASE=$(dirname "$0")

if [ -z "$L" ]; then echo "用法: grab.sh <本地路径> [pkg] [--raw]"; exit 1; fi

RN="/data/local/tmp/.vs/grab_$$_$(date +%s).png"
TMP="/tmp/.grab_$$.png"

android-shizuku-cli exec "mkdir -p /data/local/tmp/.vs; /data/local/tmp/vdisplay shot $RN $PKG" >/dev/null 2>&1

if [ ! -f "$BASE/pull.sh" ]; then echo "缺少 pull.sh"; exit 1; fi
sh "$BASE/pull.sh" "$RN" "$TMP" "$PORT" >/dev/null 2>&1

# 无论成功失败，立刻清掉设备端原图
android-shizuku-cli exec "rm -f $RN" >/dev/null 2>&1

if [ ! -f "$TMP" ]; then echo "FAIL 拉取失败"; exit 1; fi

if [ "$MODE" = "--raw" ]; then
  mv "$TMP" "$L"
  echo "OK $L $(stat -c %s "$L")B"
else
  python3 "$BASE/shrink.py" "$TMP" "$L"
  rm -f "$TMP"
fi
