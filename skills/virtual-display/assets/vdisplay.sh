#!/system/bin/sh
# vdisplay - 隐藏虚拟屏服务
B=/data/local/tmp
S=$B/vdisplay.state
L=$B/vdisplay.log
J=$B/vd.jar
TICK=$B/tick.on
TRIG=/sdcard/Scripts/.takeover

running() { [ -f $S ] && [ -n "$(cat $S 2>/dev/null)" ] && kill -0 $(sed -n 's/^pid=//p' $S) 2>/dev/null; }
id_of() { sed -n 's/^display=//p' $S; }
task_of() { sed -n 's/^task=//p' $S; }
pkg_of() { sed -n 's/^pkg=//p' $S; }
name_of() { sed -n 's/^name=//p' $S; }
start_of() { sed -n 's/^start=//p' $S; }
sf_of() { dumpsys SurfaceFlinger --display-id 2>/dev/null | sed -n 's/^Display \([0-9]*\) (Virtual display): displayName="minivd".*/\1/p' | tail -1; }
note() { cmd notification post -S bigtext -t "Minis · 后台运行中" minisvdisplay "$1" >/dev/null 2>&1; }
dur() {
  T=$(start_of); [ -z "$T" ] && { echo ""; return; }
  SEC=$(( $(date +%s) - T ))
  M=$(( SEC / 60 ))
  if [ $M -lt 1 ]; then echo "不到 1 分钟"; else echo "${M} 分钟"; fi
}
post_state() {
  P=$(pkg_of); [ -z "$P" ] && return
  A=$(name_of); [ -z "$A" ] && A=$P
  note "$A · 虚拟屏运行中 · 已运行 $(dur) · 说「接管」切回前台，说「停」结束"
}
# 主屏当前前台组件（用户正在用的 App）
foreground() {
  dumpsys activity activities 2>/dev/null | sed -n '/^Display #0 /,/^Display #[0-9]/p' \
    | grep -m1 topResumedActivity \
    | sed -n 's/.*ActivityRecord{[^ ]* [^ ]* \([^ ]*\) .*/\1/p'
}
task_display() {
  dumpsys activity activities 2>/dev/null | awk -v t="#$1" '
    /^Display #/ { d = substr($2, 2) }
    index($0, "* Task{") > 0 && index($0, t " ") > 0 { print d; exit }'
}
locate() {
  if [ -n "$1" ]; then
    dumpsys activity activities 2>/dev/null | awk -v p="$1" '
      /^Display #/ { d = substr($2, 2) }
      /topResumedActivity=/ && index($0, " " p "/") > 0 { print d; exit }'
  fi
}
ensure() { if ! running; then "$0" start >/dev/null 2>&1; fi; id_of; }
cur_disp() { D=$(locate "$1"); [ -z "$D" ] && D=$(id_of); echo $D; }
shot_disp() { if [ "$1" = "0" ]; then screencap -p "$2"; else screencap -d $(sf_of) -p "$2"; fi; }

case "$1" in
_*) ;;
*) touch $B/.beat ;;
esac
case "$1" in
start)
  if running; then echo "ALREADY display=$(id_of)"; exit 0; fi
  kill $(pgrep -f "vd[.]VdMai[n]") 2>/dev/null; sleep 1
  rm -f $S $L $B/vdisplay.stop
  CLASSPATH=$J setsid app_process /system/bin vd.VdMain --serve > $L 2>&1 < /dev/null &
  i=0
  while [ $i -lt 40 ]; do sleep 1; [ -f $S ] && break; i=$((i+1)); done
  if [ ! -f $S ]; then echo "FAIL"; tail -6 $L; exit 1; fi
  rm -f $TICK; touch $TICK
  setsid sh "$0" _tick > /dev/null 2>&1 < /dev/null &
  setsid sh "$0" _watch > /dev/null 2>&1 < /dev/null &
  echo "STARTED display=$(id_of) sf=$(sf_of)"
  ;;
stop)
  rm -f $TICK
  touch $B/vdisplay.stop; i=0
  while [ $i -lt 10 ]; do sleep 1; pgrep -f "vd[.]VdMai[n]" >/dev/null || break; i=$((i+1)); done
  kill $(pgrep -f "vd[.]VdMai[n]") 2>/dev/null
  kill $(pgrep -f "vdisplay _tic[k]") 2>/dev/null
  kill $(pgrep -f "vdisplay _watc[h]") 2>/dev/null
  rm -f $TRIG
  sleep 1
  rm -f $S $B/vdisplay.stop
  # 销毁显示会触发焦点重算，可能把已停放的任务重新提到前台，这里补一次恢复
  if [ -f $B/.restore ]; then
    RG=$(cat $B/.restore 2>/dev/null)
    sleep 2
    if [ -n "$RG" ]; then am start -n "$RG" >/dev/null 2>&1; fi
    rm -f $B/.restore
    echo "RESTORED_AFTER_STOP $RG"
  fi
  note "虚拟屏已关闭"; echo "STOPPED"
  ;;
_tick)
  while running; do
    post_state
    sleep 55
  done
  ;;
_watch)
  TIK=0
  while running; do
    # 每 30 秒才做一次空闲检查（date/stat 要 spawn 进程，别每轮都跑）
    if [ $TIK -ge 15 ]; then
      TIK=0
      if [ -f $B/.beat ]; then
        NOW=$(date +%s)
        BEAT=$(stat -c %Y $B/.beat 2>/dev/null || echo "$NOW")
        if [ $((NOW - BEAT)) -gt 180 ]; then
          note "虚拟屏空闲 3 分钟，已自动关闭"
          "$0" stop >/dev/null 2>&1
          exit 0
        fi
      fi
    fi
    TIK=$((TIK + 1))
    # 通知栏接管入口（点击写触发文件）
    if [ -f $TRIG ]; then
      rm -f $TRIG
      T=$(task_of)
      if [ -n "$T" ]; then
        cmd activity display move-stack $T 0 >/dev/null 2>&1
        sleep 1
        note "已交还到主屏 · $(name_of)"
      fi
    fi
    sleep 2
  done
  ;;
launch)
  D=$(ensure); [ -z "$D" ] && { echo "FAIL_START"; exit 1; }
  if [ -n "$3" ]; then C="$2/$3"; else C=$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$2" 2>/dev/null | tail -1); fi
  case "$C" in
    */*)
      am start --display $D -n "$C" 2>&1 | tail -1
      sleep 2
      T=$(dumpsys activity activities 2>/dev/null | sed -n "/^Display #$D /,\$p" | grep -m1 "\* Task{" | grep -o "#[0-9]*" | head -1 | tr -d '#')
      sed -i '/^task=/d;/^pkg=/d;/^name=/d;/^start=/d' $S
      { echo "task=$T"; echo "pkg=$2"; echo "name=$2"; echo "start=$(date +%s)"; } >> $S
      post_state
      echo "ON_VD task=${T:-?} display=$D" ;;
    *) echo "NO_ACTIVITY $2" ;;
  esac
  ;;
setname)
  sed -i "/^name=/d" $S; echo "name=$2" >> $S
  post_state; echo "NAME=$2" ;;
# 把虚拟屏任务搬到主屏「后台」：不抢前台，保留用户当前正在用的 App
park)
  T=$(task_of); [ -z "$T" ] && { echo "NO_TASK"; exit 1; }
  MYPKG=$(pkg_of)
  # 1) 真正的前台组件：dumpsys 里第一处 topResumedActivity 就是主屏顶层
  TOP=$(dumpsys activity activities 2>/dev/null | grep -m1 "topResumedActivity=" \
        | sed -n 's/.*ActivityRecord{[^ ]* [^ ]* \([^ ]*\) .*/\1/p')
  TOPPKG=${TOP%%/*}
  # 2) 候选兜底：主屏任务栈包名，去重保序
  CANDS=$(dumpsys activity activities 2>/dev/null | sed -n '/^Display #0 /,$p' \
        | grep -o "A=[0-9]*:[^ ]*" | sed 's/^A=[0-9]*://' | awk '!seen[$0]++' | head -6)
  cmd activity display move-stack $T 0 >/dev/null 2>&1
  sleep 2
  RESTORE=""
  skipped() {
    case "$1" in
      ""|"$MYPKG"|com.miui.home|com.android.systemui|com.android.settings) return 0 ;;
    esac
    return 1
  }
  # 优先恢复"搬走之前真正在前台的那个"，只有它正是被搬走的 App 时才回退到候选
  if ! skipped "$TOPPKG"; then
    RESTORE=$TOP
  else
    for p in $CANDS; do
      skipped "$p" && continue
      C=$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$p" 2>/dev/null | tail -1)
      case "$C" in */*) RESTORE=$C; break ;; esac
    done
  fi
  if [ -n "$RESTORE" ]; then
    am start -n "$RESTORE" >/dev/null 2>&1
    echo "$RESTORE" > $B/.restore
    sleep 1
  else
    rm -f $B/.restore
  fi
  D=$(locate "$2")
  sed -i '/^pkg=/d;/^task=/d' $S
  note "已停放到主屏后台 · $(name_of)"
  echo "PARKED task=$T display=${D:-?} restored=${RESTORE:-none}"
  ;;
takeover)
  T=$(task_of); [ -z "$T" ] && { echo "NO_TASK"; exit 1; }
  cmd activity display move-stack $T 0 >/dev/null 2>&1
  sleep 2
  D=$(locate "$2")
  sed -i '/^task=/d;/^pkg=/d' $S
  rm -f $B/.restore
  note "已交还到主屏 · $(name_of)"
  echo "TAKEOVER task=$T display=${D:-?}"
  ;;
tap) D=$(cur_disp "$4"); input -d $D tap $2 $3; echo "ok display=$D" ;;
swipe) D=$(cur_disp "$7"); input -d $D swipe $2 $3 $4 $5 ${6:-300}; echo "ok display=$D" ;;
key) D=$(cur_disp "$3"); input -d $D keyevent $2; echo "ok display=$D" ;;
text) D=$(cur_disp "$3"); input -d $D text "$2"; echo "ok display=$D" ;;
where) D=$(cur_disp "$2"); echo "display=$D" ;;
notify) note "$2"; echo "NOTIFIED" ;;
# 实时步骤播报：更新通知栏文案（同 tag 覆盖，不堆叠）
step) note "$(name_of) · $2"; echo "STEP $2" ;;
shot)
  D=$(cur_disp "$3"); [ -z "$D" ] && { echo "NO_DISPLAY"; exit 1; }
  O=${2:-/data/local/tmp/.vs/vdisplay.png}; shot_disp "$D" "$O" >/dev/null 2>&1 && echo "SHOT $O display=$D"
  ;;
status)
  if running; then echo "RUNNING display=$(id_of) task=$(task_of) app=$(name_of) 已运行=$(dur)"; else echo "STOPPED"; fi ;;
*)
  echo "usage: vdisplay start|stop|status|launch <pkg> [act]|setname <名称>|park [pkg]|takeover [pkg]|where <pkg>|tap x y [pkg]|swipe x1 y1 x2 y2 [ms] [pkg]|key CODE [pkg]|text S [pkg]|shot [path] [pkg]|notify <文本>" ;;
esac
