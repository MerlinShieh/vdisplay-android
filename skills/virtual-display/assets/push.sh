#!/bin/sh
# push.sh <本地文件> <设备路径> [端口]
# 用 nc 裸流把文件推到设备（设备端有 toybox nc，无需 curl/Auto.js）
# 传输后比对两边 md5，不一致直接报错

L="$1"
R="$2"
PORT="${3:-9877}"

if [ ! -f "$L" ]; then echo "本地文件不存在: $L"; exit 1; fi
if [ -z "$R" ]; then echo "用法: push.sh <本地文件> <设备路径> [端口]"; exit 1; fi

SIZE=$(stat -c %s "$L")
LM=$(md5sum "$L" | cut -d' ' -f1)

# 起一次性裸流服务
(nc -l -p "$PORT" < "$L") &
sleep 0.5

android-shizuku-cli exec "rm -f $R; nc -w 15 127.0.0.1 $PORT > $R" >/dev/null 2>&1
android-shizuku-cli exec "chmod 755 $R" >/dev/null 2>&1 \
  | jq -r '.data.stdout // empty' | tr -d '\n' > /tmp/.push_size
GSIZE=$(cat /tmp/.push_size 2>/dev/null)

RM=$(android-shizuku-cli exec "md5sum $R | cut -d' ' -f1" 2>/dev/null | jq -r '.data.stdout // empty' | tr -d '\n ')

if [ "$LM" = "$RM" ]; then
  echo "OK $R  ${SIZE}B  md5=$LM"
else
  echo "FAIL 本地=$LM 设备=${RM:-无} 设备大小=${GSIZE:-?}"
  exit 1
fi
