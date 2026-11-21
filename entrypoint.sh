#!/bin/bash
set -eu

# /data 可能被卷挂载整目录覆盖（持久化场景）。镜像内程序存放在 /opt/ttnode，
# 启动时引导到 /data，与官方镜像布局保持一致（官方 ENTRYPOINT 为 /data/run.sh）。

mkdir -p /data

# run.sh / ttrun.sh：随镜像更新，每次启动都覆盖为镜像内版本
install -m 0755 /opt/ttnode/run.sh /data/run.sh
install -m 0755 /opt/ttnode/run.sh /data/ttrun.sh

# ttmanager：若 /data 已存在（例如挂卷持久化后保存的自更新版本），则保留不覆盖；
# 需要强制刷新时删除 /data/ttmanager 后重启容器即可（见 README）
if [ ! -f /data/ttmanager ]; then
  install -m 0755 /opt/ttnode/ttmanager /data/ttmanager
fi

cd /data
exec ./run.sh "$@"
