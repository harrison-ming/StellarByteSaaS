---
owner: Harrison
review_by: 2027-02-01
doc_type: runbook
status: active
supersedes: 107 Mac + Cloudflare Tunnel 时代的部署指南 (旧版本文, 见 git 历史 tag legacy/v2.7-fork)
---

# StellarByte 生产 runbook (Contabo)

> 线上: `https://app.stellarbyte.ca` (2026-11-03 重新上线). 设计决策与验收口径见 [redeploy-spec.md](redeploy-spec.md); 本文只写怎么运维. 与 spec 冲突时以 spec 为准并回改本文.

## 1. 架构

```
用户 -> Cloudflare (proxied, SSL Full) -> Contabo 161.97.184.77 nginx :443 (自签名 origin 证书)
     -> 127.0.0.1:4007 -> stellarbyte-app (容器内 nginx :5000: /api -> backend :3000, 其余 -> frontend :4200; orchestrator = Temporal worker)
                           ├─ stellarbyte-postgres  (postgres:17-alpine; 库 stellarbyte / temporal / temporal_visibility)
                           ├─ stellarbyte-redis     (redis:7-alpine, AOF)
                           └─ stellarbyte-temporal  (temporalio/auto-setup:1.28.1, SQL visibility, 无 Elasticsearch / 无 UI)
媒体: R2 桶 stellar-postiz -> https://media.stellarbyte.ca      备份: R2 私有桶 stellarbyte-backups
发信: Stalwart app-noreply@stellarbyte.ca -> mx.stellarbyte.ca:587 STARTTLS (容器出站 25 被 DOCKER-USER 丢弃)
```

- 代码: GitHub `harrison-ming/StellarByteSaaS` 分支 `stellarbyte` = 上游 Postiz `v2.25.3` + StellarByte 补丁 (spec 3 节). 远端 `main` 仍是旧 fork 历史 (tag `legacy/v2.7-fork`).
- 镜像: `ghcr.io/harrison-ming/stellarbyte-app:<tag>` (公开包, 由 `.github/workflows/build-stellarbyte.yml` 在推 tag `stellarbyte-*` 时构建 amd64). Contabo 只 pull, **禁止在 Contabo 上构建**.
- 同机还有 Stalwart (16 域名 / 41 账号, 2026-11-03 实测) 与 Listmonk, 都是生产服务; 任何主机级改动前后都跑 `/usr/local/bin/stalwart-health.sh` (须 16/16 OK). 资源限额与网络隔离见 spec 5 节, 不得放宽.
- 公开 API: `https://app.stellarbyte.ca/api/public/v1`, header `Authorization: <组织 API key>`. key 现只存 Windmill 变量 `u/harrisonvancouver/stellarbyte_api_key` (secret, 运行时副本); 按凭据规范主源应为 BW, 条目 `StellarByteSaaS - Org API Key (StellarByte)` 待建 (已知缺口, 见 `STELLAR CONFIG/StellarByteSaaS/credentials.md` 五节), 建好后轮换须两处同改.

## 2. 文件位置 (只列路径, 不含值)

| 位置 | 内容 |
|---|---|
| 仓库 `deploy/contabo/` | `docker-compose.yml`, `docker-compose.local.yml` (本机试跑 override), `.env.example`, `postgres/init/10-databases.sh`, `temporal/dynamicconfig/`, `nginx/stellarpostiz`, `firewall/`, `backup/` (脚本 + systemd 单元模板), `signup-notify/` (新注册 Discord 通知, r6) |
| 服务器 `/opt/stellarpostiz/` | `docker-compose.yml`, `.env` (600), `.env.pre-<rN|fb|hide-ig|gmb|lipage|tiktok|lipage-open>` / `docker-compose.yml.pre-r6` (每次改 `.env` 前的副本, 含密钥, 600; 只代表当时那一刻, 回滚时不要整份 `cp`, 见第 5 节), `postgres/init/`, `temporal/` (均从仓库复制), `backups/` (700), `decommission-20260908/` (旧 nginx 站点存档) |
| 服务器 `/usr/local/sbin/` | `stellarbyte-backup.sh`, `stellarbyte-docker-user-fw.sh`, `stellarbyte-signup-notify.sh`, 共用 `notify-command-status.sh` (Discord 告警), 主机级 `host-resource-check.sh` (源码 `STELLAR INFRA/machines/contabo/host-monitor/`) |
| 服务器 `/etc/systemd/system/` | `stellarbyte-backup.{service,timer}`, `stellarbyte-backup-watchdog.{service,timer}`, `stellarbyte-docker-user-fw.service`, `stellarbyte-signup-notify.{service,timer}`; 主机级 `host-resource-check.{service,timer}` |
| 服务器 `/etc/nginx/sites-available/stellarpostiz` | 站点 (symlink 到 sites-enabled) |
| 服务器 `/root/.config/stellarbyte/r2-backup.env` (600) | 备份桶 R2 token |
| 服务器 `/root/.config/stellarbyte/signup-notify.env` (600) | `#stellarbyte-signups` 频道 webhook (`DISCORD_WEBHOOK_URL`); 水位线在 `/var/lib/stellarbyte-signup-notify/watermark` |
| 本机 `STELLAR CONFIG/StellarByteSaaS/.env.production` (600) | 生产 `.env` **主源**; 改动先改这里再同步到服务器 |
| 本机 `STELLAR CONFIG/StellarByteSaaS/credentials.md` / `r2-backup.env` (600) | 凭据索引 (无明文) / 备份桶 R2 token 本机副本. 组织与 integration 映射在本仓库 [integrations.md](integrations.md) (2026-11-17 取代原 `accounts.md`) |
| 本机 `STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json` (600) | Google 登录 client (GCP 项目 `stellarbyte-scheduler-login`, spec D19); 值已进 `.env` 的 `GOOGLE_LOGIN_CLIENT_ID/SECRET` |
| Bitwarden | OAuth: Pinterest `c5fd1a75-…`, LinkedIn `c1153ce7-…`, YouTube 旧 client `cfc8d358-…` (stellar-dev, r8 起不再使用; 新 client `stellarbyte-youtube` 的 JSON 在 `STELLAR CONFIG/StellarByteSaaS/youtube-oauth-client-stellarbyte-youtube.json`, BW 条目待建); Google 登录 client `StellarByte Google OAuth - stellarbyte-scheduler-login`; GMB client `StellarByte Google OAuth - stellarbyte-gbp` `e06cff8b-…`; LinkedIn 公司页 app `LinkedIn App - StellarByte Pages` `c01a564c-…` (后两条 2026-11-12 写入, 映射表见 `credentials.md`); 授权操作员 app-ops 的邮箱与 SaaS 登录条目 (spec D26, 2026-11-19 建, UUID 见 `credentials.md`); 待建: 组织 API key, 备份加密私钥 (第 12.3 节) |

## 3. 部署 / 更新镜像 tag

tag 规则: `stellarbyte-<上游tag>[-rN]`. 已推送的 tag 不改写, 同一上游版本的修订用 `-rN` 递增 (r2 首个可用镜像; r3 隐藏 Google 登录; r4 Pinterest refresh token 修复; r5 无计费不加载 Stripe.js + 国旗图标自托管; r6 去掉 app 内署名/源码链接, 独立 Google 登录 client + 按已验证邮箱关联本地账号, 开放注册; r7 LinkedIn 公司页改用 CMA 权限与独立 app 变量, 隐藏 gmb; r8 YouTube 频道授权收窄到 5 个 scope, `YOUTUBE_CLIENT_*` 换成 GCP `stellarbyte-youtube` 的 client). **当前线上 r8 (2026-11-13), 回滚目标 r7** (r7 / r6 / r5 / r4 镜像保留; 回滚只改 tag, 见第 5 节).

```bash
# 0. 本机: 打 tag 推送, 等 CI "Build StellarByte image" 成功
git tag stellarbyte-v2.25.3-rN && git push origin stellarbyte-v2.25.3-rN
gh run list -R harrison-ming/StellarByteSaaS -L 3

# 1. 服务器: 升级前手动备份一次 (回滚 Postgres 只能靠它)
ssh root@161.97.184.77 'systemctl start stellarbyte-backup.service && systemctl status stellarbyte-backup.service --no-pager | grep Active'

# 2. 改 tag: 本机主源 .env.production 与服务器 /opt/stellarpostiz/.env 两边同改 STELLARBYTE_TAG
ssh root@161.97.184.77 'cd /opt/stellarpostiz && cp -p .env .env.pre-rN && sed -i "s/^STELLARBYTE_TAG=.*/STELLARBYTE_TAG=\"stellarbyte-v2.25.3-rN\"/" .env'

# 3. 拉镜像 + 只重建 app (postgres/redis/temporal 不动)
ssh root@161.97.184.77 'cd /opt/stellarpostiz && docker compose pull app && docker compose up -d --no-deps app'

# 4. 验收: healthy (约 1-3 分钟), 登录页, worker
ssh root@161.97.184.77 'docker ps --format "{{.Names}} {{.Status}}" | grep stellarbyte'
curl -s -o /dev/null -w '%{http_code}\n' https://app.stellarbyte.ca/auth/login
```

worker 检查: `docker exec stellarbyte-temporal temporal task-queue describe --task-queue main --address temporal:7233` 的 Pollers 应有 workflow 与 activity 两行; `docker logs stellarbyte-app 2>&1 | grep -i temporal | tail`. 再用管理员账号浏览器登录一次.

改 compose 或 `.env` 其他变量: 先改仓库 / 主源, 再 `scp` 到 `/opt/stellarpostiz/`, `docker compose up -d` (只重建有变化的服务).

## 4. 上游跟进

按 [redeploy-spec.md](redeploy-spec.md) 第 4 节 (fetch tag -> `sync/<tag>` 分支 cherry-pick L1/L1' -> `node scripts/brand/apply-brand.mjs --check` -> CI + 本机 compose 冒烟 -> 合入 `stellarbyte`, 更新根目录 `UPSTREAM_BASE`, 打 tag -> 本文第 3 节上线).

新版本发现: `.github/workflows/upstream-release-watch.yml` 每周一比对上游最新 release 与 `UPSTREAM_BASE`, 有新版时开 issue. GitHub 只从**默认分支**运行定时 workflow (手动 Run 也要求文件在默认分支); 远端默认分支 2026-11-07 已改为 `stellarbyte`, 每周 schedule 生效 (当天手动 Run 一次 success); 怀疑漏报时人工核对 `gh api repos/gitroomhq/postiz-app/releases/latest --jq .tag_name`. 注意 `gh` 在本仓库默认指向上游, 操作本 fork 的 workflow / 设置要带 `-R harrison-ming/StellarByteSaaS`. 本机试跑: `deploy/contabo/docker-compose.local.yml` (子网 `STELLARBYTE_SUBNET=172.31.250.0/24`, 本机 172.30 已被占用).

## 5. 回滚

- **只回滚 app**: 在当前 `.env` 上只把 `STELLARBYTE_TAG` 改回上一 tag (同第 3 节的 `sed`, 本机主源同改), `docker compose up -d --no-deps app`. 上一版镜像在服务器上保留 (r7 / r6 / r5 / r4, 同第 3 节), 不要在验收前 prune. **不要整份 `cp .env.pre-*`**: 副本只代表当时那一刻, 会丢掉之后加的变量 (例: `.env.pre-r7` 没有 2026-11-12 加的 `GOOGLE_GMB_*` / `LINKEDIN_PAGE_*`, GMB 会回退到 stellar-dev 的 YouTube client; `.env.pre-r6` 还缺 `FACEBOOK_APP_*` / `GOOGLE_LOGIN_CLIENT_*`, `HIDDEN_PROVIDERS` 只有 `linkedin-page`, 且 `DISABLE_REGISTRATION="true"`). **r8 → r7**: 只改 tag, `YOUTUBE_CLIENT_*` 保持 `stellarbyte-youtube` 不动: 已接入的神機君 (2026-11-19) 的 refresh token 由该 client 签发, 换回 stellar-dev (`.env.pre-r8`) 会让它刷新失败. r7 按 8 个 scope 发起授权, 而该 client 同意屏只登记了 5 个, 回滚期间不要新连或 Reconnect YouTube, 回到 r8 后再操作. **r7 → r6**: 改 tag 并在两边 `.env` 的 `HIDDEN_PROVIDERS` 加回 `linkedin-page`; r6 不认 `LINKEDIN_PAGE_*`, 公司页回退 `LINKEDIN_CLIENT_*` (另一个 app), 已接入的 StellarByte Technology Ltd. (由 `StellarByte Pages` 授权) 发帖与刷新会失败, 回到 r7+ 后需 Reconnect. **r6 → r5**: 改 tag 并设 `GOOGLE_LOGIN_ENABLED="false"` (r5 的 Google 登录读 `YOUTUBE_CLIENT_*`). 沿用当前 compose 即可 (`docker-compose.yml.pre-r6` 不必还原).
- **数据库也要回滚** (上游 schema 变更): 停 app -> 用升级前的 dump 恢复 (第 6.4 节, 三库同一组) -> 起旧 tag. `prisma db push` 每次启动都会跑, 不可逆的列删除只能靠 dump 恢复.

## 6. 备份与恢复

### 6.1 例行

- `stellarbyte-backup.timer` 每天 03:45 UTC: 三个库 `pg_dump -Fc` -> 校验 -> sha256 + manifest -> `/opt/stellarpostiz/backups/` (保留 14 天) -> 上传 R2 `stellarbyte-backups/stellarbyte/` 并回读校验 (桶 lifecycle 35 天).
- `stellarbyte-backup-watchdog.timer` 每小时 :50: 最新一组须 26h 内, 有效, 且 R2 存在; 失败经 `notify-command-status.sh` 发 Discord (首次失败 + 恢复各一条).
- 媒体在 R2 `stellar-postiz`, 不在备份范围 (R2 自身持久化). Redis 只放队列/缓存, 不备份.
- dump 未加密, 而 `Integration` 表的社媒 token / refresh token 是明文 (第 12.3 节), 拿到 dump 即拿到全部频道授权. 加 age 加密列为待办 (第 12.3 节); 在此之前 dump 只放 root-only 目录与私有桶, 不得复制到别处.

### 6.2 命令

```bash
systemctl start stellarbyte-backup.service          # 立即备份
systemctl list-timers 'stellarbyte*' --no-pager      # 下次/上次运行
journalctl -u stellarbyte-backup.service -n 50 --no-pager
/usr/local/sbin/stellarbyte-backup.sh verify /opt/stellarpostiz/backups/<file>.dump
STELLARBYTE_R2_CONFIG_FILE=/root/.config/stellarbyte/r2-backup.env /usr/local/sbin/stellarbyte-backup.sh watchdog
```

### 6.3 恢复演练 (每季度一次, 升级前后各一次)

```bash
/usr/local/sbin/stellarbyte-backup.sh restore-drill /opt/stellarpostiz/backups/<stellarbyte 最新>.dump
```

恢复到容器内临时库, 逐表计数与源库对比, 结束删除临时库. 2026-11-03 首次演练三库全部一致 (输出 `/root/stellarbyte-predeploy-20261103/restore-drill-*.txt`).

离机演练 (证明 R2 那份能用, 不依赖本地目录): 把 R2 最新一组下载到临时目录再对它跑 restore-drill, 完事删掉下载.

```bash
W=/root/r2-drill-$(date +%Y%m%d); install -d -m 0700 $W && cd $W
( set -a; . /root/.config/stellarbyte/r2-backup.env; set +a
  export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY AWS_DEFAULT_REGION=auto
  f=$(aws s3 ls s3://$R2_BUCKET/stellarbyte/ --endpoint-url $R2_ENDPOINT | awk '{print $4}' | grep '^stellarbyte-stellarbyte-.*\.dump$' | sort | tail -1)
  for a in "" .sha256 .manifest; do aws s3 cp s3://$R2_BUCKET/stellarbyte/$f$a ./ --endpoint-url $R2_ENDPOINT --only-show-errors; done )
chmod 600 * && sha256sum -c *.sha256 && /usr/local/sbin/stellarbyte-backup.sh restore-drill $W/*.dump
cd / && rm -f $W/* && rmdir $W
```

2026-11-04 离机演练: 下载 `stellarbyte-stellarbyte-20261104T034551Z.dump` (222,394 字节), sha256 通过且与本地副本逐字节相同, 恢复后 88 张表计数与线上一致, 临时库已删 (输出 `/root/followup-e-20261103/restore-drill-offsite-stellarbyte.txt`).

### 6.4 真实恢复

> 下列命令未在生产执行过 (已演练的是 6.3 的临时库恢复); 执行前先对当前库再备份一次.
> **红线**: `stellarbyte` + `temporal` + `temporal_visibility` 三库必须一起恢复, 且只用**同一组 (同一时间戳)** 的备份: 常规恢复用最新一组, 回滚上游 schema 时用升级前手动备份的那一组 (第 5 节). 只恢复业务库会丢掉 Temporal 里的 `refresh_<integrationId>` 刷新工作流, Pinterest token 到期后不再自动续期 (第 12.3 节). 重建实例 / 换机器同理: 必须带库迁移, 不得用空库起新实例 (2026-11-03 旧 integration 全部作废的根因是换了空库, 不是换 key).

```bash
cd /opt/stellarpostiz && docker compose stop app temporal
docker exec -i stellarbyte-postgres pg_restore -U postgres -d stellarbyte --clean --if-exists --no-owner --role=stellarbyte < backups/<file>.dump
# temporal / temporal_visibility 同理 (--role=temporal); 然后
docker compose up -d
```

## 7. 监控与告警

| 检查 | 位置 | 告警 |
|---|---|---|
| 外部存活 (`/auth/login` + `/api/` 每 5 分钟, 失败重试一次, 只在状态变化时发) | Windmill `u/harrisonvancouver/ops/stellarbyte_liveness_check` + schedule `ops/stellarbyte_liveness_schedule`; 源码 `host/Windmill/ops/stellarbyte_liveness_check.py` | Discord #errors (DOWN / RECOVERED) |
| 备份 / watchdog | systemd 单元 (第 6 节); Stalwart 备份同理 (`stalwart-backup*.timer`, 见 INFRA vps 文档) | Discord #errors (ALERT / RECOVERY, 只在状态变化时发) |
| 容器健康 | compose healthcheck + `restart: unless-stopped` | 无主动告警, 由外部存活覆盖 |
| 新注册通知 (每 5 分钟, 只读查询 `User` 表新行, 按水位线逐条发: 时间 / 邮箱 / 组织 / provider) | `stellarbyte-signup-notify.timer` (源码 `deploy/contabo/signup-notify/`); 看水位线与待发数 `stellarbyte-signup-notify.sh status` | Discord `#stellarbyte-signups` (Ops 分类, webhook); 脚本失败经 `notify-command-status.sh` 发 #errors (`stellarbyte-signup-notify`) |
| 主机资源 (每 10 分钟: 根盘 > 85%, MemAvailable < 12%, swap 用量 > 1G, 新的内核 OOM kill) | `host-resource-check.timer`; 看数值 `host-resource-check.sh status` | Discord #errors (`host-resource-disk/-mem/-swap/-oom`, 状态变化时发) |
| 容器资源 | `docker stats --no-stream`; `free -h` | 人工; 常驻约 app 1.4G / temporal 0.2G / pg 0.2G |

新注册通知安装 / 重装 (主机需有 `jq` `curl`; 2026-11-04 首次安装):

```bash
scp deploy/contabo/signup-notify/stellarbyte-signup-notify.{sh,service,timer} root@161.97.184.77:/root/
ssh root@161.97.184.77 'cd /root && install -m 0700 stellarbyte-signup-notify.sh /usr/local/sbin/ \
  && install -m 0644 stellarbyte-signup-notify.{service,timer} /etc/systemd/system/ && systemctl daemon-reload \
  && /usr/local/sbin/stellarbyte-signup-notify.sh init && systemctl enable --now stellarbyte-signup-notify.timer'
# webhook: /root/.config/stellarbyte/signup-notify.env (600) 一行 DISCORD_WEBHOOK_URL=..., 频道 #stellarbyte-signups
#   (1567570707355803773, webhook 1567570734123843686, bot API 建). 丢失时用 bot token 在该频道重建 webhook.
# 补发某时刻之后的注册: stellarbyte-signup-notify.sh init 'YYYY-MM-DD HH:MM:SS' (UTC), 下一轮 timer 发出.
```

只更新脚本时不要再跑 `init` (会把水位线重置到当前时刻, 跳过未发的注册): 只做 `install -m 0700 ... /usr/local/sbin/`, 再用 `sha256sum` 与仓库比对. 2026-11-12 按此方式重装到仓库版 (加 email / org 截断 200 字符与 `init` 参数校验), 脚本 / service / timer 三者 sha256 与仓库一致, 水位线未变; 旧脚本留在服务器 `/root/stellarbyte-signup-notify.sh.pre-20261112`.

告警演练 (不动备份数据): 用真实检查名临时缩短新鲜度窗口触发失败, 再跑正式单元恢复; #errors 应先后收到 ALERT 与 RECOVERY (2026-11-04 两个 watchdog 均已验证).

```bash
STELLARBYTE_BACKUP_DIR=/opt/stellarpostiz/backups STELLARBYTE_R2_CONFIG_FILE=/root/.config/stellarbyte/r2-backup.env STELLARBYTE_BACKUP_MAX_AGE_MINUTES=1 \
  /usr/local/sbin/notify-command-status.sh --name stellarbyte-backup-watchdog -- /usr/local/sbin/stellarbyte-backup.sh watchdog   # 预期 exit 1 + ALERT
systemctl start stellarbyte-backup-watchdog.service                                                                                  # RECOVERY
/usr/local/sbin/host-resource-check.sh self-test     # 资源告警链路, 用独立名 host-resource-selftest
```

## 8. 网络与防火墙

- 只发布 `127.0.0.1:4007`; Postgres/Redis/Temporal 不发布端口. 子网 `172.30.0.0/24`.
- `DOCKER-USER` 规则 "丢弃 172.30.0.0/24 出站 tcp/25" 由 `stellarbyte-docker-user-fw.service` 在每次 docker 启动后重放 (本机无 netfilter-persistent, Docker 重启会清空 DOCKER-USER). 检查: `/usr/local/sbin/stellarbyte-docker-user-fw.sh check`; 计数 `iptables -vnL DOCKER-USER`.
- 验收方法: 容器内 `nc -zv -w5 gmail-smtp-in.l.google.com 25` 必须超时, `mx.stellarbyte.ca 587` 必须通.

## 9. Nginx 与 Cloudflare

- 站点 `stellarpostiz` (字母序在 `listmonk` 之后, 不改变兜底站点); `client_max_body_size 100m`; WebSocket upgrade; X-Forwarded-Proto=http 时 301 到 https. 改动后 `nginx -t && systemctl reload nginx`, 并确认 listmonk-api / smtp-admin 行为不变.
- 安全头 (2026-11-04): HSTS `max-age=15552000` (6 个月, 不带 includeSubDomains / preload), nosniff, `X-Frame-Options SAMEORIGIN` (应用只嵌 youtube.com, 自己不被嵌), Referrer-Policy `strict-origin-when-cross-origin`, `Permissions-Policy` 关 camera / microphone / geolocation / payment / usb. 主机 `nginx.conf` http 级另有一套全局头; nginx 的 `add_header` 不叠加, 站内写了就不再继承全局, 所以站点文件里必须列全, 加新头时别只写一条.
- 登录限速: `/api/auth/{login,register,forgot,forgot-return,activate,resend-activation}` 按访客真实 IP (全局 `real_ip_header CF-Connecting-IP`) `10r/m burst=5 nodelay`, 超出 429. 2026-11-04 实测连续错误密码第 6 次起 429, 约 1 分钟后恢复. 查: `grep ' 429 ' /var/log/nginx/access.log` (拒绝日志是 warn 级, error.log 不记).
- 仓库副本与服务器必须一致: `sha256sum /etc/nginx/sites-available/stellarpostiz` 对比 `deploy/contabo/nginx/stellarpostiz`.
- 证书 `/etc/ssl/certs/origin.crt` 是**自签名** (不是 Cloudflare Origin CA), 所以 Cloudflare SSL 模式**必须保持 Full, 不得改 Full (strict)**, 否则全部站点 526.
- DNS: proxied A `app` -> 161.97.184.77; `media` 为 R2 自定义域. 台账 `STELLAR INFRA/DEPLOY/cloudflare/usage-by-project.md`.
- Cloudflare 会自动注入 `static.cloudflareinsights.com` (zone RUM), 是 r5 之后唯一已知的第三方请求 (Stripe.js 只在配置了 Stripe key 时加载, 国旗图标自托管于 `/icons/flags/`).

## 10. R2

| 桶 | 用途 | 访问 | token |
|---|---|---|---|
| `stellar-postiz` | 媒体 | 自定义域 `media.stellarbyte.ca` (r2.dev 已关), CORS 只放行 app 域 | 只限该桶的 R2 token, 在 `.env` 的 `CLOUDFLARE_*` |
| `stellarbyte-backups` | 数据库备份 | 私有, r2.dev 关 | 只限该桶, 在 `/root/.config/stellarbyte/r2-backup.env` |

`CLOUDFLARE_BUCKET_URL` 末尾不能有 `/` (代码自己拼 `/`). 新建 token 后约 30 秒才生效.

## 11. 邮件

- 账号 `app-noreply@stellarbyte.ca` (Stalwart principal `sb-app-noreply`), `EMAIL_PROVIDER=nodemailer`, 提交到 `mx.stellarbyte.ca:587` STARTTLS. 发信用于激活与通知.
- Stalwart 每日 03:00 UTC 冷备份到本地 + 私有 R2 `stalwart-backups` (停机约 8 秒, 2026-11-03 起); 备份与健康检查见 `STELLAR INFRA/machines/contabo/vps-161.97.184.77.md`.

## 12. 管理员与账号授权

### 12.1 注册与管理员

- **注册开放** (r6 起, spec D21): `DISABLE_REGISTRATION="false"` (主源 `.env.production` 与服务器 `.env`; compose 用 `${DISABLE_REGISTRATION:-true}` 插值, 未设置时默认关闭). 本地邮箱注册须点激活邮件; Google 注册直接激活. 每个新注册约 5 分钟内发到 Discord `#stellarbyte-signups` (第 7 节).
- **快速关闭注册** (遇到滥用 / 发信信誉告警): 两边 `.env` 改 `DISABLE_REGISTRATION="true"`, 然后 `cd /opt/stellarpostiz && docker compose up -d --no-deps app` (约 1-3 分钟 healthy). 关闭后已有用户照常登录, 新注册返回 400 "Registration is disabled" (库里已有组织时).
- **管理员 (超管)**: 普通注册即可, 之后授超管 (可见 "Agents / Dev" 与 "Apps" 设置页, D10):

```bash
docker exec -it stellarbyte-postgres psql -U postgres -d stellarbyte \
  -c "UPDATE \"User\" SET \"isSuperAdmin\" = true WHERE email = '<管理员邮箱>';"
```

组织 API key 在 Settings 里 Rotate, 新值按第 1 节写回 (Windmill; BW 条目建好后两处同改). 2026-11-04 (r6) 旧账号与组织已删除 (D22: 删除前 dump `/root/r6-predelete-20261104/stellarbyte-predelete.dump`, 单事务 `TRUNCATE "Media", "UserOrganization", "Organization", "User" CASCADE`, 删后 88 表全 0), 旧 key 失效. 2026-11-07 Harrison (`harrison.vancouver@gmail.com`, Google 登录) 已设超管, 组织 StellarByte 的 key 已写回 Windmill. R2 `stellar-postiz` 里无 DB 引用的 5 个遗留对象 (旧组织媒体, 授权重试头像, 部署探针) 已于 2026-11-07 删除, 现存对象是频道头像 (Integration.picture 引用, 含已软删除的 integration, 不能删).

#### 授权操作员 app-ops (spec D26, 2026-11-19 已建)

频道授权 (Add Channel) 不用 Harrison 的 Google 账号, 统一用 LOCAL 用户 `app-ops@stellarbyte.ca` (Stalwart principal `sb-app-ops`, PID 74) 在目标号自己的浏览器环境里登录 SaaS. 目的: 不让 Harrison 的 Google 账号出现在多个 HubStudio 反检测环境里 (隐私 + 平台关联风险). 账号长期保留, 用于今后所有频道授权.

2026-11-19 建成 (重建或换号时照此执行):

1. Stalwart 建 `sb-app-ops` (走 `/add-email`), 邮箱密码与 SaaS 登录密码各一条 BW (UUID 见 `credentials.md` 一节映射表), 写入前须 Harrison 确认.
2. 用 Harrison 的 SaaS 会话发邀请: Settings → Teams 加 `app-ops@stellarbyte.ca`, 角色 USER (等价于 `POST /api/settings/team` `{email, role:"USER", sendEmail:true}`), 邀请链接 `/?org=<token>` 2 天有效, 从 app-ops 收件箱取 (Mac 连不上 IMAP 时见 `STELLAR INFRA/machines/contabo/smtp/credentials.md` "本机 Mac 公网 IP 被 auto-ban" 一节, 应急可在服务器本机收信).
3. 注册: `POST /api/auth/register` (LOCAL, 带 cookie `org=<token>`), 收激活邮件里的 `/auth/activate/<code>`, `POST /api/auth/activate`. 脚本直连要带浏览器 UA, 否则 Cloudflare 返回 1010.
4. 注册会自动给该用户建一个空组织 (2026-11-19 为组织 `app-ops` `01bf5429-…`, 该用户在其中是 SUPERADMIN): 先 `pg_dump` (2026-11-19 放 `/root/app-ops-20261119/`), 再把该用户在空组织的 `UserOrganization.disabled` 设 `true` (可逆, 中间件过滤 disabled 组织). 2026-11-19 用 app-ops 登录核对: 只看到组织 StellarByte (USER, 非超管), 能看到该组织全部频道.
5. 每个环境授权完必须在 SaaS 里登出, 再关环境.

已知风险 (已接受): 生产未配 Stripe, permissions 全放行, USER 角色在后端可删频道 / 轮换组织 API key / 发帖, 只是前端隐藏; auth cookie 365 天, 登出不在服务端作废, 改密码也不作废已有会话. 紧急作废: 把该用户 `activated` 设 `false` 或删用户; 最后手段轮换 `JWT_SECRET` (全员掉线, 不影响频道 token, 第 12.3 节).

#### Google 登录 (r6, spec D19 / D20)

- 独立 OAuth client `StellarByte App Login` (GCP 项目 `stellarbyte-scheduler-login`), 环境变量 `GOOGLE_LOGIN_CLIENT_ID` / `GOOGLE_LOGIN_CLIENT_SECRET` (取自 `STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json` 的 `.web.client_id` / `.web.client_secret`), 按钮开关 `GOOGLE_LOGIN_ENABLED="true"`. 不回退 `YOUTUBE_*`: 没配 client 时不要打开开关.
- 回调沿用上游 `https://app.stellarbyte.ca/integrations/social/youtube` (`state=login` 区分登录与 YouTube 频道授权), 已在该 client 登记 (另有 `http://localhost:4007/...` 供本机试跑).
- 核对授权链接用的是新 client (只看前缀): `curl -s https://app.stellarbyte.ca/api/auth/oauth/GOOGLE | grep -o 'client_id=[0-9]\{12\}'` 应为 `344812424356`.
- 已验证邮箱关联: Google 账号的已验证邮箱与已有本地 (邮箱注册) 用户相同时, 直接登录该用户 (仅限已激活的本地用户; 未激活的不关联, 照常新建 Google 用户, 防止他人抢注同邮箱后接管), 不新建组织, 不改 `providerName`. Google 返回的 token 必须是发给本 client 的 (`getTokenInfo` 校验 `aud`). 移动端 (上游 app 的 `redirect_uri`) 不在范围, 未在新 client 登记.
- 关闭: `GOOGLE_LOGIN_ENABLED="false"` + `docker compose up -d --no-deps app`.

### 12.2 社媒账号授权

- 一律在 StellarByte UI "Add Channel" 走 OAuth (旧 `platforms/pinterest` 授权/刷新工具已废弃, D14). 回调 `https://app.stellarbyte.ca/integrations/social/<provider>`. 在目标号所在的浏览器环境里登录 SaaS 时用**授权操作员 `app-ops@stellarbyte.ca`** (第 12.1 节, D26), 不用 Harrison 的 Google 账号; 登录凭据见 `STELLAR CONFIG/StellarByteSaaS/credentials.md` 一节映射表 app-ops 行. 每个环境授权完登出.
- **Pinterest**: 长期授权协议与逐账号清单 (前置条件, 身份核对, 回填项, 刷新核对) 见 `STELLAR INFRA/platforms/pinterest/authorization-checklist.md`; 下面是要点. 每个账号必须在它自己的 HubStudio 环境里授权 (BW 条目的 "Browser ID" = HubStudio containerCode; 哪个号用哪个环境先 `acctctl locate`), 不得在本机浏览器混登. 授权前先在该环境确认 pinterest.com 当前登录的就是目标账号 (头像 / 用户名与 `platforms/pinterest/account-status.md` 一致), 再在该环境用 app-ops 登录 StellarByte 并 Add Channel. 授权后核对 UI 显示的用户名, 并按第 12.3 节核对刷新工作流.
  - 前置条件: HubStudio (规则 `STELLAR INFRA/DEPLOY/hubstudio/AGENTS.md`); 账号分组, 试点号与各号进度只记在 `authorization-checklist.md` 第 2 节台账. 批量授权前先完成第 12.3 节 "批量授权前" 待办 (含 Pinterest 后台访问级别与 redirect URI 复核).
- **Facebook Page** (2026-11-07 起, spec D24): Meta app `StellarPage` (App ID `4160936944155117`, Business 类型, 已过审并 Published), 环境变量 `FACEBOOK_APP_ID` / `FACEBOOK_APP_SECRET` (主源 `.env.production`). 代码请求的 5 个权限 `pages_show_list` / `business_management` / `pages_manage_posts` / `pages_read_engagement` / `read_insights` 须全部为 live (Advanced), 任一不是则非 app 角色用户授权报 "Invalid Scopes". 核对: `GET https://graph.facebook.com/v21.0/4160936944155117/permissions?access_token=<APP_ID>|<SECRET>` (不要把 secret 打到终端). 回调 `https://app.stellarbyte.ca/integrations/social/facebook` 在 Facebook Login for Business 设置里登记. 只覆盖 Facebook Page: "Instagram (Facebook Business)" 共用这组变量, 但 `instagram_*` 权限未提审, 不要对用户开放.
- **TikTok** (2026-11-17 起): Harrison 早先注册并已过审的 TikTok 开发者 app (client key 前缀 `awtt`), 变量 `TIKTOK_CLIENT_ID` / `TIKTOK_CLIENT_SECRET` (BW `TikTok Developer App - StellarByte` `eb9775c2-…` → `.env.production`). 2026-11-17 两边 `.env` 写入并重建 app, `client_credentials` 换 token 成功 (key/secret 有效), 线上授权链接 `client_key` 正确. **首次授权前须在 TikTok 开发者后台核对**: 回调 `https://app.stellarbyte.ca/integrations/social/tiktok` 已登记 (TikTok 登录前不校验回调, 只能在首次授权时验证); 代码请求的 6 个 scope `user.info.basic` / `user.info.profile` / `user.info.stats` / `video.list` / `video.upload` / `video.publish` 全部已开通, 授权回调时缺任一个会报 "Missing required permissions". 未过 Content Posting API 审计的 app 只能发仅自己可见的内容. 无刷新工作流 (未设 `refreshCron`), 发帖时按需刷新. 每个号在它自己的环境 (`acctctl locate`) 里用 app-ops 授权.
- **LinkedIn 公司页** (r7, spec D25; 2026-11-19 起开放): 独立 LinkedIn app `StellarByte Pages` (只挂 Community Management API, Development tier 已获批), 变量 `LINKEDIN_PAGE_CLIENT_ID/SECRET` (不设则回退 `LINKEDIN_CLIENT_*`), 回调 `/integrations/social/linkedin-page`. 授权的 LinkedIn 成员必须是目标公司页的管理员; Development tier 只适合自有公司页, 给其他用户用需先升 Standard tier (开发者后台 Products 页 Request upgrade, 需录屏). Development tier 配额 (2026-11-19 开发者后台 Analytics 实测): 每个接口每天 500 次/app, 100 次/授权成员 (`posts` CREATE 即发帖, 同一成员授权的所有公司页共用这 100 次); BATCH_GET 类只有 2 次/app/天, 授权时列公司页用的 `organizationsLookup` 属此类, 所以每天最多约 2 次 Add Channel / Reconnect. **须在获批后 12 个月内 (约 2027-11) 申请 Standard tier, 否则 LinkedIn 以不活跃为由收回 API 权限**; Standard 被拒不能用同一 app 重申, 只能新建 app 重走 Development tier. 无刷新工作流, access token 2 个月, 到期前发帖时按需刷新; refresh token 失效后在 UI Reconnect. 自有公司页 StellarByte Technology Ltd. 已接入 (2026-11-19, 账号 `stellarbyte-linkedin`, 在 Harrison 本人的 `harrison-personal` profile 里用其个人 LinkedIn 授权, SaaS 端用 Harrison 账号登录; 本人环境, 不违反 D26).
- **YouTube** (r8, 2026-11-19 起): GCP 项目 `stellarbyte-youtube` 的 Web client, 变量 `YOUTUBE_CLIENT_ID` / `YOUTUBE_CLIENT_SECRET` (JSON 在 `STELLAR CONFIG/StellarByteSaaS/youtube-oauth-client-stellarbyte-youtube.json`, BW 备份待建); Google 登录不用此 client. 代码只请求 5 个 scope (`userinfo.profile` / `userinfo.email` / `youtube.readonly` / `youtube.upload` / `yt-analytics.readonly`, `youtube.provider.ts`), 回调 `/integrations/social/youtube` 已在该 client 登记. 同意屏 In production 但未验证: 授权时显示 "Google 尚未验证此应用", 点 "高级 → 继续"; 终身 100 个授权用户上限; 敏感 scope 验证还缺演示视频. 频道属于品牌账号时, 在 Google 账号选择页要选品牌账号本身, 代码按所选身份 `mine=true` 列频道. YouTube 2026-11-02 起取消 "未审计项目上传锁私享" 的规定 (revision history 2026-11-02), 2026-11-19 经 SaaS 实测 unlisted 上传保持 unlisted, 未被锁. 配额: `videos.insert` 单独计数, 默认每天 100 次 (全项目共用), 其他接口 10,000 单位/天; 频道自身另有不公开的上传上限 (社区实测约 4-10 条/天). 合规审计 (Audit and Quota Extension Form) 只在申请超额配额时需要. 上传固定带 `notifySubscribers=true`, 公开视频会通知订阅者. 只拿 `youtube.upload` / `youtube.readonly`, 不能经 API 删除或改已上传视频 (在 YouTube Studio 操作). 无刷新工作流, 发帖时按需刷新. 已接入: 神機君 (账号 `easternblessing-youtube-2`, 品牌 EasternBlessing, 2026-11-19).
- **Google Business Profile** (r7, spec D25): 入口在 `HIDDEN_PROVIDERS` 里隐藏, 等平台审批. GMB 用 GCP 项目 `stellarbyte-gbp` 的 client `StellarByte SaaS GMB`, 变量 `GOOGLE_GMB_CLIENT_ID/SECRET` (不设则回退 `YOUTUBE_CLIENT_*` 即 stellar-dev, 不要这样用), 回调 `/integrations/social/gmb`; Business Profile API 未获批时项目配额 0, 授权后列门店会失败. 获批后: 两边 `.env` 去掉 `HIDDEN_PROVIDERS` 里对应项, `docker compose up -d --no-deps app`, 授权并发测试帖 (spec 第 9 节).
- 已接入频道总表见 [integrations.md](integrations.md) 第 3 节; token 刷新机制与长期可用的红线见第 12.3 节.
- 授权后回填: Windmill 变量 `publish_accounts` 与 Supabase `pinterest_publisher.accounts` 的 integration_id; `host/StellarByteSaaS/docs/integrations.md`; 全局账号表 `STELLAR INFRA/platforms/_shared/accounts.json` 对应账号的 `bindings` (Pinterest 例外: integrationId 写 `platforms/pinterest/account-status.json`), 然后 `acctctl gen && acctctl lint`. integration id 的事实源是 SaaS `Integration` 表, 以上都是副本; token 只在 DB, 不进 BW.

### 12.3 授权与 token 长期可用

事实 (代码已核实, v2.25.3 + r8):

- `Integration` 表的 `token` / `refreshToken` 明文存储 (`integration.repository.ts`), 不用 `JWT_SECRET` 加密: 轮换 `JWT_SECRET` 只让用户会话掉线, 不影响任何频道 token.
- Pinterest: access token 30 天; continuous refresh token 60 天, 每次刷新轮换 (r4 起保存新 refresh token, spec L1').
- `refreshTokenWorkflow` (workflow id `refresh_<integrationId>`) 只在 OAuth 连接时启动, 之后没有任何补启机制. 刷新失败**一次**即把 integration 标 `refreshNeeded` 并退出工作流 (`refresh.integration.service.ts:77-107`), 只能在 UI 里 Reconnect. 发帖时若 token 已过期会顺手刷新一次.
- 其余 provider (LinkedIn / YouTube 等) 无刷新工作流, 只在发帖时按需刷新; Facebook Page token 长期有效, 但 90 天数据访问期内无活动需重连 (spec 7.1 D24 行).
- 删除组织会把该组织 integration 的 token 哈希掉, 不可逆.

运维红线:

- 授权后**不得删除组织** (含 D26 的空组织只做 disabled, 不删).
- 不得更换已有频道所用的 app / OAuth client (`PINTEREST_CLIENT_*`, `FACEBOOK_APP_*`, `LINKEDIN_CLIENT_*`, `LINKEDIN_PAGE_CLIENT_*`, `YOUTUBE_CLIENT_*`, `TIKTOK_CLIENT_*`) 或 `FRONTEND_URL`: 已有 token 与回调都绑定在上面, 换了该平台的频道全部要重授 (回滚时同理, 见第 5 节).
- 重建实例必须带库迁移, 不得用空库; 恢复时三库一起且只用同一组备份 (第 6.4 节).

待办 (按时限):

| 时限 | 项 | 状态 |
|---|---|---|
| 批量授权前 | 补一次恢复演练 (第 6.3 节, r6-r8 上线后未做) | 待做 |
| 批量授权前 | 备份加 age 加密 (公钥上服务器, 私钥存 BW 新条目 `StellarByteSaaS - Backup Encryption Key`, 写入须 Harrison 确认); 改脚本后重跑恢复演练 | 待做 |
| 首个 Pinterest 号授权当天 | 核对 Temporal 中存在 `refresh_<integrationId>` 工作流 (方法见 `platforms/pinterest/authorization-checklist.md` 第 1 节第 9 步) | 待授权 |
| 首个 Pinterest 号首次刷新前 (授权后约 30 天) | r10 补丁上线: 刷新失败退避重试 (不再一次失败即 `refreshNeeded`); 对设了 `refreshCron` 的 provider 的 integration 补启刷新工作流 (`WorkflowIdConflictPolicy` = USE_EXISTING, 已在跑的不重复) | 待开发 |
| 同上 | watchdog 告警 (发 #errors): Pinterest integration `refreshNeeded=true`; `refresh_<id>` 工作流数 < 设了 `refreshCron` 的 integration 数; `tokenExpiration` 已过期 | 待开发 |
| 首次刷新后 (授权后约 30 天) | 核对该 integration 的 refresh token 已更换 (只比对哈希, 不打印值) | 待授权 |
| 授权前 | Harrison 在 Pinterest 开发者后台复核 app 访问级别 (Standard / Trial) 与 redirect URI (第 12.2 节) | 待 Harrison |

## 13. 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| `docker compose pull` 报 ghcr `connection reset by peer` (IPv6) | 网络抖动, 旧容器不受影响; 重试 (`for i in 1 2 3; do docker compose pull app && break; sleep 30; done`). 镜像约 7GB, 首拉约 13 分钟 |
| app 反复重启, 日志 `ERR_INVALID_URL` (start.mcp.ts) | `NEXT_PUBLIC_BACKEND_URL` 必须是绝对地址 `https://app.stellarbyte.ca/api`, 不能是 `/api` |
| app 启动卡在 prisma | 启动脚本每次跑 `pnpm dlx prisma@6.5.0 db push`, 需要容器能访问 registry.npmjs.org; 外网或 npm 故障时启动失败, 恢复后 `docker compose restart app` |
| 磁盘不足 | `df -h /`; `docker system df`; 只删确认无用的旧镜像 (`docker image rm <旧 tag>`), 保留当前与上一版. 不要 `docker volume prune` (同机有 Stalwart / Listmonk 的卷); 主机遗留镜像与匿名卷已于 2026-11-03 清理 (根盘 31% → 15%, 明细见 INFRA vps 文档历史节); 磁盘 > 85% 时 `host-resource-check` 会告警 |
| 备份单元 226/NAMESPACE | `ReadWritePaths` 目录不存在: `install -d -m 0700 /opt/stellarpostiz/backups` |
| Google 登录报 `redirect_uri_mismatch` / `invalid_client` | `GOOGLE_LOGIN_CLIENT_ID/SECRET` 缺失或不是 `stellarbyte-scheduler-login` 的 client; 或 `FRONTEND_URL` 变了而 client 里没登记新回调 (第 12.1 节 "Google 登录") |
| 添加频道里出现 Instagram / Google My Business (审批前) | `HIDDEN_PROVIDERS="instagram,instagram-standalone,gmb"` 丢了 (两边 `.env`), 改后 `docker compose up -d --no-deps app` |
| Google My Business 授权报 `redirect_uri_mismatch` | `stellarbyte-gbp` 的 client 未登记 `https://app.stellarbyte.ca/integrations/social/gmb`; 或 `.env` 里 `GOOGLE_GMB_CLIENT_*` 丢了 (例如整份 `cp` 旧副本回滚), 代码回退到 stellar-dev 的 YouTube client, 而该 client 不登记 `/gmb` 回调 (spec D25) |
| 非测试用户 Google 登录报 "access blocked / app is being tested" | GCP `stellarbyte-scheduler-login` 同意屏幕被改回 Testing; Audience 页 Publish (2026-11-07 起为 In production) |
| Facebook 授权报 "Invalid Scopes" / "URL blocked" / app 不可用 | 某权限不再是 live (第 12.2 节核对命令), 或回调未登记, 或 Meta 要求年度数据访问续期 (StellarPage 曾因 2026-10-17 未续期被限制) |
| Pinterest 频道提示需重连 (`refreshNeeded`) | 刷新失败一次即退出工作流, 不会自愈 (第 12.3 节); 在该号自己的 HubStudio 环境用 app-ops 登录后 Reconnect, 之后核对 `refresh_<id>` 工作流重新出现 |
| 媒体 URL 404 / 双斜杠 | `CLOUDFLARE_BUCKET_URL` 末尾多了 `/` |
| Cloudflare 526 | SSL 模式被改成 strict, 改回 Full |
| 登录返回 429 | 第 9 节登录限速 (每 IP 10 次/分钟); 等 1 分钟. 多人同一出口 IP 频繁误报时再调 `rate` / `burst` |
| 内存紧张 / OOM | `docker stats`; app 上限 2g 由 cgroup 硬限, 先被杀的是 app/temporal (oom_score_adj 300), Stalwart (-500) 受保护 |
