# ttnode-binary — 甜糖星愿官方二进制版的 Docker 封装

官方 docker 镜像（`registry.cn-hangzhou.aliyuncs.com/tiptime/ttnode:latest`）更新慢，官方主要维护的是裸机二进制版（`wget -O auto.sh https://tiptime-api.com/cdn/tt_installer/auto.sh && bash auto.sh`）。

本仓库把**官方 CDN 上的最新二进制**封装成 docker 镜像发布到 ghcr.io，让你在飞牛 NAS 上既能享受二进制版的更新速度，又保持 docker 隔离。

## 工作原理（来自对官方安装链路与官方镜像的静态分析）

```
auto.sh  →  下载 tt_installer_{amd64|arm64|arm32}
         →  tt_installer 装依赖(iptables/iproute2/jq/wget)、写 cron 自启
         →  下载主程序 ttmanager_{arch}
            （地址：https://tiptime-api.com/cdn/ttmanager2/latest/ttmanager_{arch}）
         →  ttmanager 负责下载/更新节点核心并保活（自带自更新逻辑）
```

官方 docker 镜像的内部结构（通过匿名拉取镜像 manifest + 各层解包确认）：

- 基础镜像 `debian:trixie`，依赖：`ca-certificates curl wget jq iftop sysstat qrencode inetutils-ping inetutils-traceroute procps iproute2 iptables`
- 主程序放 `/data/ttmanager`，入口 `./run.sh`（保活循环：崩溃计数、`.bak` 回滚、自动重启）
- 环境变量：`container_name=ttnode`、`NODE_TYPE=ttnode`、`mode=normal`、`TZ=Asia/Shanghai`
- 节点数据目录 `/mnt/data/ttnode`（硬编码在程序里）

本仓库镜像的差异只有一个：**`ttmanager` 在构建时从官方 CDN 拉最新版**（与裸机安装同源同地址），并且本镜像的 `run.sh` 直接取自官方镜像层，行为 100% 一致。二进制不进仓库，全部构建时下载。

## 使用步骤

### 1. 建仓库并触发构建

1. 在 GitHub 新建仓库（例如 `ttnode-binary`，**Public** 最省事），把本目录全部文件推上去：
   ```bash
   cd 甜糖
   git init
   git add Dockerfile entrypoint.sh run.sh .dockerignore docker-compose.yml .github/
   git commit -m "ttnode binary docker packaging"
   git branch -M main
   git remote add origin https://github.com/hifn123p/ttnode-binary.git
   git push -u origin main
   ```
2. 推送后会自动触发 Actions 构建；也可到 **Actions 页 → build-ttnode-image → Run workflow** 手动触发。
3. 构建产物：`ghcr.io/hifn123p/ttnode-binary:latest`（多架构：amd64 / arm64 / armv7，另有 `20251121` 式日期标签）。
4. **首次构建后**，到仓库右侧 Packages → 该镜像 → Package settings，把可见性改为 **Public**（否则 NAS 拉取需要先 `docker login ghcr.io`）。

### 2. 飞牛 NAS 上部署

SSH 或飞牛的 Docker/compose 界面里，用仓库根目录的 `docker-compose.yml`：

```bash
mkdir -p /vol2/1000/ttnode          # 节点数据目录，按你的实际数据盘调整
# 编辑 docker-compose.yml，把 image 改成你的 ghcr 地址
docker compose pull && docker compose up -d
docker logs -f ttnode
```

挂载点与官方镜像完全一致：

| 挂载 | 用途 |
|---|---|
| `/vol2/1000/ttnode:/mnt/data/ttnode` | 节点缓存数据（换你的数据盘路径） |
| `/var/run/docker.sock` | 程序的容器管理/自更新 |
| `/proc:/host/proc:ro` | 读取宿主机硬件信息 |

> `network_mode: host` + `privileged` + `/dev/mem` 与你现有的官方镜像 compose 相同，无需改动策略。
> 若你的 NAS 内核没有 `/dev/mem` 导致启动报错，删掉 `devices` 那两行即可。

### 3. 更新

- **自动**：GitHub Actions 每周一（北京时间 11:17）自动重新构建，拉取 CDN 最新 ttmanager 并推送 `:latest`。
- **手动**：Actions 页 Run workflow，或改代码 push 触发。
- **NAS 端应用更新**：
  ```bash
  docker compose pull && docker compose up -d
  ```
- 容器内的 ttmanager 本身也保留官方裸机版的自更新能力；若开启了 `/data` 挂卷，自更新产物可跨重启保留。

## 从官方镜像迁移

挂载路径、网络模式、环境变量全部一致，节点数据目录 `/mnt/data/ttnode` 不变 → **设备绑定与缓存不丢**。直接停掉旧容器、改 image 后 `up -d` 即可。

## 常见问题

- **`docker pull` 报 401/403**：ghcr 包还是 Private，按上面第 1 步改为 Public，或在 NAS 上 `docker login ghcr.io`（密码用 GitHub PAT，需 `read:packages`）。
- **想强制刷新容器内程序**：`docker exec ttnode rm -f /data/ttmanager /data/.cache/.execfilepath && docker restart ttnode`（entrypoint 会重新从镜像引导，镜像内为构建时的 CDN 最新版）。
- **镜像太旧想立刻拿最新二进制**：到 Actions 手动触发一次构建，再 `docker compose pull && up -d`。
- **构建失败提示下载失败**：官方 CDN 有频率限制，workflow 内置了重试；重新 Run workflow 即可。

## 目录结构

```
├── Dockerfile                  # 复刻官方镜像结构，构建时拉 CDN 最新 ttmanager
├── entrypoint.sh               # 启动引导 /opt/ttnode → /data（兼容 /data 挂卷）
├── run.sh                      # 官方镜像自带的保活脚本（原样取自官方镜像层）
├── docker-compose.yml          # 飞牛 NAS 部署配置
├── .github/workflows/build.yml # CI：多架构构建 → ghcr.io
├── .dockerignore
└── analysis/                   # 静态分析产物（不进镜像、不必上传）
```
