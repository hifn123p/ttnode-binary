# syntax=docker/dockerfile:1
# =============================================================
# 甜糖星愿 (TTNode) — 官方 CDN 最新二进制的容器化封装
#
# 结构复刻官方镜像 registry.cn-hangzhou.aliyuncs.com/tiptime/ttnode，
# 但 /data/ttmanager 不用镜像内置的旧版，而是在构建时从官方 CDN
# 拉取最新版（与裸机安装 auto.sh 下载的 ttmanager2 同源、同地址）。
# 二进制不在仓库中留存，均在构建时下载。
# =============================================================
FROM debian:trixie

ARG TARGETARCH
# 若程序在容器内走“按镜像更新”的路径，让它更新到本镜像的最新版
ARG UPDATE_IMAGE=""

ENV container_name=ttnode \
    NODE_TYPE=ttnode \
    mode=normal \
    TZ=Asia/Shanghai \
    UpdateImage=${UPDATE_IMAGE}

# 运行依赖对齐官方镜像（去掉仅编译期使用的 *-dev 包）
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget jq tzdata \
      iftop sysstat qrencode \
      inetutils-ping inetutils-traceroute \
      procps iproute2 iptables \
 && rm -rf /var/lib/apt/lists/*

# 从官方 CDN 下载最新 ttmanager（amd64 / arm64 / arm32），并做完整性冒烟检查
RUN set -eux; \
    case "${TARGETARCH}" in \
      arm) TTARCH="arm32" ;; \
      *)   TTARCH="${TARGETARCH}" ;; \
    esac; \
    mkdir -p /opt/ttnode; \
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
      -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
      "https://tiptime-api.com/cdn/ttmanager2/latest/ttmanager_${TTARCH}" \
      -o /opt/ttnode/ttmanager; \
    chmod +x /opt/ttnode/ttmanager; \
    # 校验：ELF 魔数 + 体积（防止 CDN 限频返回错误页）
    [ "$(od -An -tx1 -N4 /opt/ttnode/ttmanager | tr -d ' \n')" = "7f454c46" ]; \
    [ "$(stat -c%s /opt/ttnode/ttmanager)" -gt 10000000 ]

# 官方镜像里 run.sh 与 ttrun.sh 为同一脚本（保活入口），先放进内置目录，
# 由 entrypoint 在启动时引导到 /data（这样 /data 也可以整目录挂卷持久化）
COPY run.sh /opt/ttnode/run.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/ttnode/run.sh

WORKDIR /data
ENTRYPOINT ["/entrypoint.sh"]
