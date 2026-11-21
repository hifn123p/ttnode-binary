#!/bin/bash
folder="/var/run/ttmanager"
pidfile="$folder/ttrun.pid"
# 检查文件夹是否存在
if [ ! -d "$folder" ]; then
    # 如果文件夹不存在，则创建文件夹
    mkdir -p "$folder"
fi
current_pid=$$
current_program=$(basename "$0")

if [ -f "$pidfile" ]; then
    # 读取已存在的 PID
    existing_pid=$(cat "$pidfile")
    # 检查进程是否存在并且程序名字一致
    if [ ! "$existing_pid" = "$current_pid" ] && ps -p "$existing_pid" > /dev/null; then
      cmdline=$(tr '\0' ' ' < /proc/"$existing_pid"/cmdline)
          script_path=$(echo "$cmdline" | awk '{print $2}')
      if [ "$(basename "$script_path")" = "$current_program" ]; then
        echo "已存在保活程序"
        exit 0
      fi
    fi
fi

# 将当前PID写入文件
if ! echo "$current_pid" > "$pidfile"; then
    echo "无法写入 PID 文件: $pidfile"
else
    echo "PID 写入成功"
fi

dir=/data
get_exe_path() {
    cache_path="$dir/.cache/.execfilepath"
    if [ -f "$cache_path" ]; then
        cat "$cache_path"
    else
        echo "$(pwd)/ttmanager"
    fi
}
get_exe_path
main_id=$(pidof "$(get_exe_path)")

bootCount=0
startCmd="$(get_exe_path) $* > /dev/null 2>&1 &"

# 已经启动了就监听老程序
if [ -n "$main_id" ]; then
  echo "监听后台程序 $main_id"
  while ps -p "$main_id" > /dev/null; do
    sleep 10
  done
  echo "后台程序退出"
fi
echo "启动程序，启动命令【$startCmd】"
eval "$startCmd"
pid=$!

# 第二次运行时删除默认启动节点的参数
args=("$@")
new_args=()
for (( i=0; i<$#; i++ )); do
    if [[ ${args[i]} == "-t" ]]; then
        (( i++ ))
    else
        new_args+=("${args[i]}")
    fi
done

start_time=$(date +%s)
while true; do
  # 等待程序退出
  if wait $pid; then
      echo "进程已退出，重新启动"
  else
      echo "进程异常退出，重新启动"
  fi
  if [ $bootCount -gt 3 ] && [ -f "$(get_exe_path).bak" ]; then
    echo "程序异常，回滚"
	if [ ! "$(md5sum "$(get_exe_path).bak" | awk '{print $1}')" = "$(md5sum "$(get_exe_path)" | awk '{print $1}')" ]; then
    	mv "$(get_exe_path)".bak "$(get_exe_path)"
	fi
    bootCount=0
  fi
  running_time=$(( $(date +%s) - $start_time ))
  echo -e "StartTime: $(date -d@$start_time +"%F %T") RestartCount: $bootCount\nRunningTime: $(($running_time/3600)) Hours $(($running_time%3600/60)) Minutes $((running_time%60)) Seconds"
  # start_time 与当前相差一小时
  if [ $running_time -gt 3600 ]; then
	# 当作正常退出，计数归0
	start_time=$(date +%s)
	bootCount=0
  else
  	((bootCount+=1))
  fi
  startCmd="$(get_exe_path) ${new_args[*]} > /dev/null 2>&1 &"
  echo "启动程序，启动命令【$startCmd】"
  eval "$startCmd"
  pid=$!

done
