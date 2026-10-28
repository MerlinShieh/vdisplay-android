#!/bin/sh
# pull.sh <设备路径> <本地路径> [端口]
# 设备 → 沙箱 的裸流传输（设备端用 toybox nc 推流）
R="$1"; L="$2"; PORT="${3:-9878}"
if [ -z "$R" ] || [ -z "$L" ]; then echo "用法: pull.sh <设备路径> <本地路径> [端口]"; exit 1; fi

rm -f "$L"
nc -l -p "$PORT" > "$L" 2>/dev/null &
NCPID=$!
sleep 0.4

# 设备端同步执行，返回即表示写完
android-shizuku-cli exec "nc -q 1 127.0.0.1 $PORT < $R" >/dev/null 2>&1
sleep 0.3
kill "$NCPID" 2>/dev/null
wait "$NCPID" 2>/dev/null

SIZE=$(stat -c %s "$L" 2>/dev/null || echo 0)
if [ "$SIZE" -lt 100 ]; then echo "FAIL 大小=$SIZE"; exit 1; fi

RM=$(android-shizuku-cli exec "md5sum $R | cut -d' ' -f1" | jq -r '.data.stdout // empty' | tr -d ' \n')
LM=$(md5sum "$L" | cut -d' ' -f1)
if [ "$RM" = "$LM" ]; then echo "OK $L ${SIZE}B md5=$LM"; else echo "MISMATCH 设备=$RM 本地=$LM"; exit 1; fi
