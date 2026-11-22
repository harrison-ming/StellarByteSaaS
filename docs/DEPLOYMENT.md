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
- 同机还有 Stalwart (16 域名) 与 Listmonk, 都是生产服务; 任何主机级改动前后都跑 `/usr/local/bin/stalwart-health.sh` (须 16/16 OK). 资源限额与网络隔离见 spec 5 节, 不得放宽.
- 公开 API: `https://app.stellarbyte.ca/api/public/v1`, header `Authorization: <组织 API key>`. 主源 BW 条目见第 2 节 Bitwarden 行, 运行时副本 Windmill secret `u/harrisonvancouver/stellarbyte_api_key`; 轮换须两处同改. 调用方之一 `host/Windmill/totvan_web/fb_share.py` (FB 主页 Totvan, 2026-11-19 起).

## 2. 文件位置 (只列路径, 不含值)

| 位置 | 内容 |
|---|---|
| 仓库 `deploy/contabo/` | `docker-compose.yml`, `docker-compose.local.yml` (本机试跑 override), `.env.example`, `postgres/init/10-databases.sh`, `temporal/dynamicconfig/`, `nginx/stellarpostiz`, `firewall/`, `backup/` (脚本 + systemd 单元模板), `signup-notify/` (新注册 Discord 通知, r6) |
| 服务器 `/opt/stellarpostiz/` | `docker-compose.yml`, `.env` (600), `.env.pre-<rN|fb|hide-ig|gmb|lipage|tiktok|lipage-open|threads|tiktok-business>` / `docker-compose.yml.pre-r6` (每次改 `.env` 前的副本, 含密钥, 600; 只代表当时那一刻, 回滚时不要整份 `cp`, 见第 5 节), `postgres/init/`, `temporal/` (均从仓库复制), `backups/` (700), `decommission-20260908/` (旧 nginx 站点存档) |
| 服务器 `/usr/local/sbin/` | `stellarbyte-backup.sh`, `stellarbyte-docker-user-fw.sh`, `stellarbyte-signup-notify.sh`, 共用 `notify-command-status.sh` (Discord 告警), 主机级 `host-resource-check.sh` (源码 `STELLAR INFRA/machines/contabo/host-monitor/`) |
| 服务器 `/etc/systemd/system/` | `stellarbyte-backup.{service,timer}`, `stellarbyte-backup-watchdog.{service,timer}`, `stellarbyte-docker-user-fw.service`, `stellarbyte-signup-notify.{service,timer}`; 主机级 `host-resource-check.{service,timer}` |
| 服务器 `/etc/nginx/sites-available/stellarpostiz` | 站点 (symlink 到 sites-enabled) |
| 服务器 `/root/.config/stellarbyte/r2-backup.env` (600) | 备份桶 R2 token |
| 服务器 `/root/.config/stellarbyte/signup-notify.env` (600) | `#stellarbyte-signups` 频道 webhook (`DISCORD_WEBHOOK_URL`); 水位线在 `/var/lib/stellarbyte-signup-notify/watermark` |
| 本机 `STELLAR CONFIG/StellarByteSaaS/.env.production` (600) | 生产 `.env` **主源**; 改动先改这里再同步到服务器 |
| 本机 `STELLAR CONFIG/StellarByteSaaS/credentials.md` / `r2-backup.env` (600) | 凭据索引 (无明文) / 备份桶 R2 token 本机副本. 组织与 integration 映射在本仓库 [integrations.md](integrations.md) |
| 本机 `STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json` (600) | Google 登录 client (GCP 项目 `stellarbyte-scheduler-login`, spec D19); 值已进 `.env` 的 `GOOGLE_LOGIN_CLIENT_ID/SECRET` |
| Bitwarden | OAuth: Pinterest `c5fd1a75-…`, LinkedIn `c1153ce7-…`, YouTube 旧 client `cfc8d358-…` (stellar-dev, r8 起不再使用; 新 client `stellarbyte-youtube` 的 JSON 在 `STELLAR CONFIG/StellarByteSaaS/youtube-oauth-client-stellarbyte-youtube.json`, BW 备份 `StellarByte Google OAuth - stellarbyte-youtube` `ff4b845c-…`, 2026-11-21 建); Google 登录 client `StellarByte Google OAuth - stellarbyte-scheduler-login`; GMB client `StellarByte Google OAuth - stellarbyte-gbp` `e06cff8b-…`; LinkedIn 公司页 app `LinkedIn App - StellarByte Pages` `c01a564c-…` (后两条 2026-11-12 写入, 映射表见 `credentials.md`); 授权操作员 app-ops 的邮箱与 SaaS 登录条目 (spec D26, 2026-11-19 建, UUID 见 `credentials.md`); 组织 API key `StellarByteSaaS - Org API Key (StellarByte)` `36fbd054-…` (2026-11-19 建, Organization 字段的组织 ID 待补); TikTok for Business app `TikTok Business App - StellarByte Social Publisher` `6cbf0903-…` (2026-11-21 建, 主源 `.env.production`); 待建: 备份加密私钥 (第 12.3 节) |

## 3. 部署 / 更新镜像 tag

tag 规则: `stellarbyte-<上游tag>[-rN]`. 已推送的 tag 不改写, 同一上游版本的修订用 `-rN` 递增; 各 rN 的内容见 spec 7.1 节发布表与 8.1 节 tag 列表. **当前线上 r12 (2026-11-21), 回滚目标 r11**; 再往前跳过 r10 (其移除回调对 Meta 的 multipart 请求返回 400), 用 r9. 服务器保留 r11 及更早镜像; 回滚只改 tag, 见第 5 节.

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

新版本发现: `.github/workflows/upstream-release-watch.yml` 每周一比对上游最新 release 与 `UPSTREAM_BASE`, 有新版时开 issue (定时只在默认分支生效, 远端默认分支已于 2026-11-07 改为 `stellarbyte`, 见 spec 第 4 节); 怀疑漏报时人工核对 `gh api repos/gitroomhq/postiz-app/releases/latest --jq .tag_name`. 注意 `gh` 在本仓库默认指向上游, 操作本 fork 的 workflow / 设置要带 `-R harrison-ming/StellarByteSaaS`. 本机试跑: `deploy/contabo/docker-compose.local.yml` (子网 `STELLARBYTE_SUBNET=172.31.250.0/24`, 本机 172.30 已被占用).

## 5. 回滚

- **只回滚 app**: 在当前 `.env` 上只把 `STELLARBYTE_TAG` 改回上一 tag (同第 3 节的 `sed`, 本机主源同改), `docker compose up -d --no-deps app`. 旧镜像在服务器上保留 (第 3 节), 不要在验收前 prune. **不要整份 `cp .env.pre-*`**: 副本只代表当时那一刻, 会丢掉之后加的变量 (例: `.env.pre-r7` 缺 `GOOGLE_GMB_*` / `LINKEDIN_PAGE_*`, GMB 会回退到 stellar-dev 的 client). **r12 → r11**: 只改 tag, 无库改动; r12 下重连的 TikTok Business 频道在 r11 照常发帖, 统计页的粉丝 / 关注 / 获赞 / 视频数仍可用 (token 已带 `user.insights`), 但 r11 新授权的频道不再请求该 scope. **r11 → r9**: 只改 tag (不要回到 r10); `DATA_DELETION_URL` 可留; 回滚期间 Meta 的移除 / 删除回调会 404, Threads 用户移除 app 后频道不会自动清理, 回到 r11 后人工处理. **r9 → r8**: 只改 tag, 无库改动; 回滚后删除 YouTube 频道不再作废 Google 授权 (token 留在已删除行). **r8 → r7**: 只改 tag, `YOUTUBE_CLIENT_*` 保持 `stellarbyte-youtube` 不动: 已接入 YouTube 频道的 refresh token 由该 client 签发, 换回 stellar-dev (`.env.pre-r8`) 会让它刷新失败; r7 按 8 个 scope 发起授权而该 client 只登记了 5 个, 回滚期间不要新连或 Reconnect YouTube. **r7 及更早**: 不建议 (r6 不认 `LINKEDIN_PAGE_*`, 已接入的 LinkedIn 公司页发帖与刷新会失败); 必须时改 tag 并在两边 `HIDDEN_PROVIDERS` 加回 `linkedin-page`, 回到 r7+ 后 Reconnect.
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

恢复到容器内临时库, 逐表计数与源库对比, 结束删除临时库. 最近: 2026-11-03 本地三库一致.

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

最近: 2026-11-04 离机 (R2) 演练, sha256 通过, 恢复后 88 张表计数与线上一致.

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

新注册通知安装 / 重装 (主机需有 `jq` `curl`):

```bash
scp deploy/contabo/signup-notify/stellarbyte-signup-notify.{sh,service,timer} root@161.97.184.77:/root/
ssh root@161.97.184.77 'cd /root && install -m 0700 stellarbyte-signup-notify.sh /usr/local/sbin/ \
  && install -m 0644 stellarbyte-signup-notify.{service,timer} /etc/systemd/system/ && systemctl daemon-reload \
  && /usr/local/sbin/stellarbyte-signup-notify.sh init && systemctl enable --now stellarbyte-signup-notify.timer'
# webhook: /root/.config/stellarbyte/signup-notify.env (600) 一行 DISCORD_WEBHOOK_URL=..., 频道 #stellarbyte-signups
#   (1567570707355803773, webhook 1567570734123843686, bot API 建). 丢失时用 bot token 在该频道重建 webhook.
# 补发某时刻之后的注册: stellarbyte-signup-notify.sh init 'YYYY-MM-DD HH:MM:SS' (UTC), 下一轮 timer 发出.
```

只更新脚本时不要再跑 `init` (会把水位线重置到当前时刻, 跳过未发的注册): 只做 `install -m 0700 ... /usr/local/sbin/`, 再用 `sha256sum` 与仓库比对.

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

组织 API key 在 Settings 里 Rotate, 新值按第 1 节两处同改 (BW 主源 + Windmill secret). 现任超管与组织见 [integrations.md](integrations.md) 第 2 节. R2 `stellar-postiz` 现存对象是频道头像 (Integration.picture 引用, 含已软删除的 integration), 不能删.

#### 授权操作员 app-ops (spec D26, 2026-11-19 已建)

频道授权 (Add Channel) 不用 Harrison 的 Google 账号, 统一用 LOCAL 用户 `app-ops@stellarbyte.ca` (Stalwart principal `sb-app-ops`, PID 74) 在目标号自己的浏览器环境里登录 SaaS. 目的: 不让 Harrison 的 Google 账号出现在多个 HubStudio 反检测环境里 (隐私 + 平台关联风险). 账号长期保留, 用于今后所有频道授权.

重建或换号时照此执行:

1. Stalwart 建 `sb-app-ops` (走 `/add-email`), 邮箱密码与 SaaS 登录密码各一条 BW (UUID 见 `credentials.md` 一节映射表), 写入前须 Harrison 确认.
2. 用 Harrison 的 SaaS 会话发邀请: Settings → Teams 加 `app-ops@stellarbyte.ca`, 角色 USER (等价于 `POST /api/settings/team` `{email, role:"USER", sendEmail:true}`), 邀请链接 `/?org=<token>` 2 天有效, 从 app-ops 收件箱取 (Mac 连不上 IMAP 时见 `STELLAR INFRA/machines/contabo/smtp/credentials.md` "本机 Mac 公网 IP 被 auto-ban" 一节, 应急可在服务器本机收信).
3. 注册: `POST /api/auth/register` (LOCAL, 带 cookie `org=<token>`), 收激活邮件里的 `/auth/activate/<code>`, `POST /api/auth/activate`. 脚本直连要带浏览器 UA, 否则 Cloudflare 返回 1010.
4. 注册会自动给该用户建一个空组织 (该用户在其中是 SUPERADMIN; 现有的是组织 `app-ops` `01bf5429-…`): 先 `pg_dump` 到 `/root/app-ops-<日期>/`, 再把该用户在空组织的 `UserOrganization.disabled` 设 `true` (可逆, 中间件过滤 disabled 组织; **不删组织**, 第 12.3 节). 用 app-ops 登录核对: 只看到组织 StellarByte (USER, 非超管).
5. 每个环境授权完必须在 SaaS 里登出, 再关环境.

已知风险 (已接受, spec D26): 生产未配 Stripe, permissions 全放行, USER 角色在后端可删频道 / 轮换组织 API key / 发帖, 只是前端隐藏; auth cookie 365 天, 登出不在服务端作废, 改密码也不作废已有会话. 紧急作废: 把该用户 `activated` 设 `false` 或删用户; 最后手段轮换 `JWT_SECRET` (全员掉线, 不影响频道 token, 第 12.3 节).

#### Google 登录 (r6, spec D19 / D20)

- 独立 OAuth client `StellarByte App Login` (GCP 项目 `stellarbyte-scheduler-login`), 环境变量 `GOOGLE_LOGIN_CLIENT_ID` / `GOOGLE_LOGIN_CLIENT_SECRET` (取自 `STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json` 的 `.web.client_id` / `.web.client_secret`), 按钮开关 `GOOGLE_LOGIN_ENABLED="true"`. 不回退 `YOUTUBE_*`: 没配 client 时不要打开开关.
- 回调沿用上游 `https://app.stellarbyte.ca/integrations/social/youtube` (`state=login` 区分登录与 YouTube 频道授权), 已在该 client 登记 (另有 `http://localhost:4007/...` 供本机试跑).
- 核对授权链接用的是新 client (只看前缀): `curl -s https://app.stellarbyte.ca/api/auth/oauth/GOOGLE | grep -o 'client_id=[0-9]\{12\}'` 应为 `344812424356`.
- 已验证邮箱关联: Google 账号的已验证邮箱与已有本地 (邮箱注册) 用户相同时, 直接登录该用户 (仅限已激活的本地用户; 未激活的不关联, 照常新建 Google 用户, 防止他人抢注同邮箱后接管), 不新建组织, 不改 `providerName`. Google 返回的 token 必须是发给本 client 的 (`getTokenInfo` 校验 `aud`). 移动端 (上游 app 的 `redirect_uri`) 不在范围, 未在新 client 登记.
- 关闭: `GOOGLE_LOGIN_ENABLED="false"` + `docker compose up -d --no-deps app`.

### 12.2 社媒账号授权

- 一律在 StellarByte UI "Add Channel" 走 OAuth (旧 `platforms/pinterest` 授权/刷新工具已废弃, D14). 回调 `https://app.stellarbyte.ca/integrations/social/<provider>`. 在目标号所在的浏览器环境里登录 SaaS 时用**授权操作员 `app-ops@stellarbyte.ca`** (第 12.1 节, D26), 不用 Harrison 的 Google 账号; 登录凭据见 `STELLAR CONFIG/StellarByteSaaS/credentials.md` 一节映射表 app-ops 行. 每个环境授权完登出.
- **Pinterest**: app `stellarbyte` (App ID `1534495`, **Standard access**; redirect URI 已登记 `https://app.stellarbyte.ca/integrations/social/pinterest` 与 `http://localhost:4100/...`; 2026-11-21 在该号环境里核对), 开发者后台 developers.pinterest.com 用公司主号 service@stellarbyte.ca (Pinterest 商业号 `service5093`, BW `Pinterest - StellarByte` `077cd5c7-…`) 登录, 变量 `PINTEREST_CLIENT_ID/SECRET` (BW `c5fd1a75-…`). 长期授权协议与逐账号清单 (前置条件, 身份核对, 回填项, 刷新核对) 见 `STELLAR INFRA/platforms/pinterest/authorization-checklist.md`; 下面是要点. 每个账号必须在它自己的 HubStudio 环境里授权 (BW 条目的 "Browser ID" = HubStudio containerCode; 哪个号用哪个环境先 `acctctl locate`), 不得在本机浏览器混登. 授权前先在该环境确认 pinterest.com 当前登录的就是目标账号 (头像 / 用户名与 `platforms/pinterest/account-status.md` 一致), 再在该环境用 app-ops 登录 StellarByte 并 Add Channel. 授权后核对 UI 显示的用户名, 并按第 12.3 节核对刷新工作流.
  - 前置条件: HubStudio (规则 `STELLAR INFRA/DEPLOY/hubstudio/AGENTS.md`); 账号分组, 试点号与各号进度只记在 `authorization-checklist.md` 第 2 节台账. 批量授权前先完成第 12.3 节 "批量授权前" 两项 (恢复演练, 备份加密).
- **Facebook Page** (2026-11-07 起, spec D24): Meta app `StellarPage` (App ID `4160936944155117`, Business 类型, 已过审并 Published), 环境变量 `FACEBOOK_APP_ID` / `FACEBOOK_APP_SECRET` (主源 `.env.production`). 代码请求的 5 个权限 `pages_show_list` / `business_management` / `pages_manage_posts` / `pages_read_engagement` / `read_insights` 须全部为 live (Advanced), 任一不是则非 app 角色用户授权报 "Invalid Scopes". 核对: `GET https://graph.facebook.com/v21.0/4160936944155117/permissions?access_token=<APP_ID>|<SECRET>` (不要把 secret 打到终端). 回调 `https://app.stellarbyte.ca/integrations/social/facebook` 在 Facebook Login for Business 设置里登记. 只覆盖 Facebook Page: "Instagram (Facebook Business)" 共用这组变量, 但 `instagram_*` 权限未提审, 不要对用户开放.
- **TikTok** (`tiktok`, Content Posting API, 2026-11-17 起): developers.tiktok.com app `StellarByte` (ID 7565701807872346168, Ownership Individual, Login Kit + Content Posting API, Direct Post 已开但从未申请审计) (client key 前缀 `awtt`), 变量 `TIKTOK_CLIENT_ID` / `TIKTOK_CLIENT_SECRET` (BW `TikTok Developer App - StellarByte` `eb9775c2-…` → `.env.production`). 两边 `.env` 已配 (2026-11-17). 回调 `https://app.stellarbyte.ca/integrations/social/tiktok` 已登记; app 只开了 4 个 scope `user.info.basic` / `user.info.profile` / `video.publish` / `video.upload`, 代码还请求 `user.info.stats` / `video.list`, 所以目前授权会报 "Missing required permissions". 未审计: 只能发 SELF_ONLY, 账号须为私密, 每 24 小时最多 5 个用户; 审计政策不接受管理自己或团队账号的工具, 此路不用于客户发帖, 2026-11-21 起入口加进 `HIDDEN_PROVIDERS` 隐藏. 无刷新工作流 (未设 `refreshCron`).
  - **TikTok for Business** (`tiktok-business`, 客户发帖走这条, 2026-11-21 上线): 上游代码, 所有 `stellarbyte-v2.25.3*` 镜像都带; 唯一改动是 r12 补 `user.insights` scope (commit 72f372ec). 主体: TikTok Business Center "StellarByte" (7416952762119815184), 2026-11-20 认证为 STELLAR BYTE TECHNOLOGY CORP. (证书 BC1414030); business-api.tiktok.com 开发者类型 Agency, 已提交 Accounts API Access Application Form.
  - Marketing API app `StellarByte Social Publisher` (App ID `7710534234384891912`) 2026-11-20 创建, **2026-11-21 Approved** (Online); scope 只选 "TikTok accounts" (获批为 All); Advertiser redirect URL 与 TikTok account holder redirect URL 都是 `https://app.stellarbyte.ca/integrations/social/tiktok-business/` (代码拼的是 `${FRONTEND_URL}/integrations/social/tiktok-business/`, 结尾斜杠必须有); logo 用 StellarByte 蓝色图标. 后台 (business-api.tiktok.com) 在 `harrison-personal` profile 里登录; 查看 Secret 要邮箱验证码 (发到开发者账号的 iCloud 隐藏邮箱); **不要点 Secret 旁的 Reset** (会作废生产 Secret). IP Allowlist 与 Request Signing 未开启, 开启前须先登记服务器出口 IP / 公钥, 否则发帖全部失败. API 频率档位 Basic.
  - 代码: 变量 `TIKTOK_BUSINESS_CLIENT_ID` (= App ID) / `TIKTOK_BUSINESS_CLIENT_SECRET` (主源与 BW 备份见第 2 节, 2026-11-21 两边 `.env` 已配, 改前副本 `.env.pre-tiktok-business`; 上线核对: 公开 API `GET /public/v1/social/tiktok-business` 返回的授权链接 client_key 与回调正确, TikTok 接受该 client_key 并进入登录页); scope (r12 起 7 个) `user.info.basic,user.info.username,user.info.stats,user.insights,video.list,video.upload,video.publish` (`checkScopes` 校验, 缺任一授权失败); API base `https://business-api.tiktok.com/open_api/v1.3`.
  - 限制: 每个号每分钟 6 条, 每天 15 条; access token 1 天, refresh token 1 年; 没有隐私参数 (只能公开发); 发帖由 TikTok 从 `media.stellarbyte.ca` 拉取视频 (Business API 只有拉取方式, 无文件直传). **媒体域名须在本 Business app 下做 URL 所有权验证, 2026-11-21 已完成**: 未验证时 TikTok 拉取报 40002 "Please review our URL ownership verification rules", 帖子标 ERROR (不可重试). developers.tiktok.com 旧 app 的 URL properties 已验证 `stellarbyte.ca`, 但对本 app 无效. 验证只能走 API (后台无入口): `POST /business/property/add/` 带 `app_id` + `secret` + `url_property_meta {property_type: 1 (域名), url: "stellarbyte.ca"}`, 返回 `tiktok-developers-site-verification=...` 签名, 加到 Cloudflare `stellarbyte.ca` 根域 TXT 记录 (备注写明本 app, 不可删, 与旧 app 的同名 TXT 并存), 再调 `POST /business/property/verify/` (同样参数) 得 `property_status: 1`; 根域验证覆盖 `media.stellarbyte.ca`. 换 app 或换媒体域名时重做.
  - 已接入: 2026-11-21 首个频道 `matrix-tiktok` (FaithsHorizon, 测试用自有号), 在该号遗留 HubStudio 环境里由 app-ops 授权, 授权页列 6 项权限 (头像与显示名, 统计, 用户名, 公开视频, 发布, 上传草稿), 回调成功入库, access token 24 小时 (按需刷新). 2026-11-21 域名验证后经公开 API 发测试帖成功 (公开可见, item 7710780571156319502); 帖子刚发布时 releaseURL 只是主页地址, 视频 id 在打开帖子时由 `resolveReleaseId` 补全 (TikTok 延迟返回 post id, 属预期). 统计: `/business/get/` 的粉丝 / 关注 / 获赞 / 视频数字段要 `user.insights` (缺时报 40130), r12 已加入 scope; r12 之前授权的频道须在原环境由 app-ops 重新 Add Channel 一次 (同 internalId 复用原 integration id, 授权页只追加请求 "Read your TikTok user analytics"). `matrix-tiktok` 2026-11-21 已重连, 公开 API `GET /public/v1/analytics/:id` 返回粉丝 50 / 视频 8 等全部字段. 客户 Saylo (元象科技) 的两个新 TikTok 号待注册养号后同样授权.
  - 共用前端与 TikTok UX 指南的已知差距: 隐私选项写死 (不读 `creator_info`); `comment` 默认开; 音乐使用同意只在品牌开关打开时显示. `MIGRATE_PROVIDERS=tiktok:tiktok-business` 未设 (库里没有 `tiktok` 频道可迁).
- **Threads** (2026-11-19 起): 独立 Meta app `StellarByte Threads` (App ID `1152802037157122`, 业务 Stellar BYTE Technology CORP., 用例 Access the Threads API), 变量 `THREADS_APP_ID` / `THREADS_APP_SECRET` 填的是 **Threads App ID `1861985238835189`** 与 Threads App Secret (不是 Meta App ID; BW `Meta App - StellarByte Threads` `289f46fb-…`). 回调 `https://app.stellarbyte.ca/integrations/social/threads` 已登记. 有刷新工作流 (`refreshCron`, 60 天长效 token).
  - App Review: 代码请求的 4 个权限 `threads_basic` / `threads_content_publish` / `threads_manage_replies` / `threads_manage_insights` **2026-11-20 已提交 (Review in progress, Meta 称多数 20 天内出结果)**. 提交材料: 录屏 (测试账号 `test@stellarbyte.ca`, `~/STELLAR_OUTPUT/_tmp/threads-app-review-2026-11-20/`), Reviewer instructions, Data handling 处理方 Contabo GmbH / Cloudflare, Inc.; 4 个权限的测试调用只在 30 天内有效, 被拒重提须重跑. 过审后: Meta 后台 Publish app, 更新本条与 integrations.md 第 3 节.
  - 过审前只有 Threads Testers 能授权 (Meta 后台 Use cases → Access the Threads API → Settings → Add or Remove Threads Testers, 对方须在 Threads 设置 → 帐户 → 网站权限里接受邀请). 测试组织 "Meta App Review" 里也接了 @accessory.ocean 供审核员测试, 审核期间他们发的帖会公开出现在该号.
  - 平台回调 (r10/r11): Uninstall / Delete Callback URL 为 `https://app.stellarbyte.ca/api/integrations/platform-callback/threads/deauthorize` 与 `/delete`; 验 Meta `signed_request` 且 `issued_at` 在 1 小时内; 移除通知清 token, 标 refreshNeeded 并站内通知重连; 删除请求按 UI 删除频道同样处理 (删帖 + 软删 + 清 token), 返回 `DATA_DELETION_URL` 与确认码 (只写日志不入库). **实测: 用户在 Threads 移除 app 时 Meta 同时发两个回调 (移除通知 multipart/form-data, 删除通知 urlencoded), 所以移除 app = 该号在本库的频道被删除, 要继续用须重新授权 (同一 internalId 复用原 integration id).**
  - Threads 只能用 Instagram 账号登录; 被封的 IG 号进 Threads 会跳到 `accounts/disabled`, 换号前要先清掉 threads.com / instagram.com 的登录 cookie, 否则会自动 SSO 回被封号.
- **LinkedIn 公司页** (r7, spec D25; 2026-11-19 起开放): 独立 LinkedIn app `StellarByte Pages` (只挂 Community Management API, Development tier 已获批), 变量 `LINKEDIN_PAGE_CLIENT_ID/SECRET` (不设则回退 `LINKEDIN_CLIENT_*`), 回调 `/integrations/social/linkedin-page`. 授权的 LinkedIn 成员必须是目标公司页的管理员; Development tier 只适合自有公司页, 给其他用户用需先升 Standard tier (开发者后台 Products 页 Request upgrade, 需录屏). Development tier 配额: 每个接口每天 500 次/app, 100 次/授权成员 (`posts` CREATE 即发帖, 同一成员授权的所有公司页共用这 100 次); BATCH_GET 类只有 2 次/app/天, 授权时列公司页用的 `organizationsLookup` 属此类, 所以每天最多约 2 次 Add Channel / Reconnect. **须在获批后 12 个月内 (约 2027-11) 申请 Standard tier, 否则 LinkedIn 以不活跃为由收回 API 权限**; Standard 被拒不能用同一 app 重申, 只能新建 app 重走 Development tier. 无刷新工作流, access token 2 个月, 到期前发帖时按需刷新; refresh token 失效后在 UI Reconnect. 自有公司页 StellarByte Technology Ltd. 已接入 (2026-11-19, 账号 `stellarbyte-linkedin`, 在 Harrison 本人的 `harrison-personal` profile 里用其个人 LinkedIn 授权, SaaS 端用 Harrison 账号登录; 本人环境, 不违反 D26).
- **YouTube** (r8, 2026-11-19 起): GCP 项目 `stellarbyte-youtube` 的 Web client, 变量 `YOUTUBE_CLIENT_ID` / `YOUTUBE_CLIENT_SECRET` (主源与 BW 备份见第 2 节; 控制台已不能再查看 Secret); Google 登录不用此 client. 代码只请求 5 个 scope (`userinfo.profile` / `userinfo.email` / `youtube.readonly` / `youtube.upload` / `yt-analytics.readonly`, `youtube.provider.ts`), 回调 `/integrations/social/youtube` 已在该 client 登记. 同意屏 In production, External; **Google 验证已通过** (2026-11-21 Verification Center 核对: Branding 与 Data access 均为 verified), 授权时不再显示 "未验证" 页. 已验证的 scope 正好是代码请求的这 5 个 (敏感: `youtube.readonly` / `youtube.upload`); 页面显示的 100 人上限 (已用 2) 只约束未获批 scope, 只请求已批 scope 时不适用. **代码新增任何 scope 都要重新提交验证**, 否则授权会回到 "未验证" 页并重新计入 100 人终身上限; 验证材料: 演示视频 https://youtu.be/yvaEVct19a4 (不公开, 在基本透明频道), 隐私政策第 6 节 (`host/StellarByte` PR #23). 隐私政策第 6 节须与代码请求的 scope 和数据处理保持一致 (`youtube.provider.ts` 注释). 频道属于品牌账号时, 在 Google 账号选择页要选品牌账号本身, 代码按所选身份 `mine=true` 列频道. 未审计项目上传不再被锁私享 (YouTube 2026-11-02 政策变更, 11-19 实测 unlisted 保持 unlisted). 配额: `videos.insert` 单独计数, 默认每天 100 次 (全项目共用), 其他接口 10,000 单位/天; 频道自身另有不公开的上传上限 (社区实测约 4-10 条/天). 合规审计 (Audit and Quota Extension Form) 只在申请超额配额时需要. 上传固定带 `notifySubscribers=true`, 公开视频会通知订阅者. 只拿 `youtube.upload` / `youtube.readonly`, 不能经 API 删除或改已上传视频 (在 YouTube Studio 操作). 删除频道即作废授权 (第 12.3 节). 无刷新工作流, 发帖时按需刷新.
- **Google Business Profile** (r7, spec D25): 入口在 `HIDDEN_PROVIDERS` 里隐藏; Business Profile API 访问申请尚未提交 (2027-01-10 起可提交, 见 spec 第 9 节). GMB 用 GCP 项目 `stellarbyte-gbp` 的 client `StellarByte SaaS GMB`, 变量 `GOOGLE_GMB_CLIENT_ID/SECRET` (不设则回退 `YOUTUBE_CLIENT_*` 即 stellar-dev, 不要这样用), 回调 `/integrations/social/gmb`; Business Profile API 未获批时项目配额 0, 授权后列门店会失败. 获批后: 两边 `.env` 去掉 `HIDDEN_PROVIDERS` 里对应项, `docker compose up -d --no-deps app`, 授权并发测试帖.
- 已接入频道总表见 [integrations.md](integrations.md) 第 3 节; token 刷新机制与长期可用的红线见第 12.3 节.
- 授权后回填: Windmill 变量 `publish_accounts` 与 Supabase `pinterest_publisher.accounts` 的 integration_id; `host/StellarByteSaaS/docs/integrations.md`; 全局账号表 `STELLAR INFRA/platforms/_shared/accounts.json` 对应账号的 `bindings` (Pinterest 例外: integrationId 写 `platforms/pinterest/account-status.json`), 然后 `acctctl gen && acctctl lint`. integration id 的事实源是 SaaS `Integration` 表, 以上都是副本; token 只在 DB, 不进 BW.

### 12.3 授权与 token 长期可用

事实 (代码已核实, v2.25.3 + r12):

- `Integration` 表的 `token` / `refreshToken` 明文存储 (`integration.repository.ts`), 不用 `JWT_SECRET` 加密: 轮换 `JWT_SECRET` 只让用户会话掉线, 不影响任何频道 token.
- Pinterest: access token 30 天; continuous refresh token 60 天, 每次刷新轮换 (r4 起保存新 refresh token, spec L1').
- `refreshTokenWorkflow` (workflow id `refresh_<integrationId>`) 只在 OAuth 连接时启动, 之后没有任何补启机制. 刷新失败**一次**即把 integration 标 `refreshNeeded` 并退出工作流 (`refresh.integration.service.ts` 的 `refreshProcess`), 只能在 UI 里 Reconnect. 发帖时若 token 已过期会顺手刷新一次.
- 设了 `refreshCron` 的只有 Pinterest (r4) / Threads / Instagram standalone; 其余 (LinkedIn / YouTube / TikTok / TikTok Business 等) 无刷新工作流, 只在发帖时按需刷新; Facebook Page token 长期有效, 但 90 天数据访问期内无活动需重连 (spec 7.1 D24 行).
- 删除组织会把该组织 integration 的 token 哈希掉, 不可逆. r9 起删除账号前先对支持作废的 provider (YouTube) 作废授权.
- 删除频道 (r9): provider 实现 `revokeToken` 时 (目前只有 YouTube) 删除即作废平台授权并清空该行 token / refreshToken; 同一平台账号 (`rootInternalId`) 在任一组织还有未删除频道时跳过作废 (2026-11-19 实测: 删除后 Google 账号的已关联应用里 YouTube 权限消失); 失败只记日志不阻塞删除, 无重试队列. 已知未覆盖: 并发删除竞态, r9 之前已软删除仍持 token 的行 (2026-11-19 生产库 YouTube 为 0).

运维红线:

- 授权后**不得删除组织** (含 D26 的空组织只做 disabled, 不删).
- 不得更换已有频道所用的 app / OAuth client (`PINTEREST_CLIENT_*`, `FACEBOOK_APP_*`, `LINKEDIN_CLIENT_*`, `LINKEDIN_PAGE_CLIENT_*`, `YOUTUBE_CLIENT_*`, `TIKTOK_CLIENT_*`, `TIKTOK_BUSINESS_CLIENT_*`, `THREADS_APP_*`) 或 `FRONTEND_URL`: 已有 token 与回调都绑定在上面, 换了该平台的频道全部要重授 (回滚时同理, 见第 5 节).
- 重建实例必须带库迁移, 不得用空库; 恢复时三库一起且只用同一组备份 (第 6.4 节).

待办 (按时限):

| 时限 | 项 | 状态 |
|---|---|---|
| 批量授权前 | 补一次恢复演练 (第 6.3 节, r6-r12 上线后未做) | 待做 |
| 批量授权前 | 备份加 age 加密 (公钥上服务器, 私钥存 BW 新条目 `StellarByteSaaS - Backup Encryption Key`, 写入须 Harrison 确认); 改脚本后重跑恢复演练 | 待做 |
| 首个 Pinterest 号授权当天 | 核对 Temporal 中存在 `refresh_<integrationId>` 工作流 (方法见 `platforms/pinterest/authorization-checklist.md` 第 1 节第 9 步; Threads 2026-11-20 已核对 `refresh_cmwoaxm0p0001p681lqslxofp` Running, 机制可用) | 待授权 |
| 首个 Pinterest 号首次刷新前 (授权后约 30 天) | 刷新补丁 (r13 或之后) 上线: 刷新失败退避重试 (不再一次失败即 `refreshNeeded`); 对设了 `refreshCron` 的 provider 的 integration 补启刷新工作流 (`WorkflowIdConflictPolicy` = USE_EXISTING, 已在跑的不重复) | 待开发 |
| 同上 | watchdog 告警 (发 #errors): Pinterest integration `refreshNeeded=true`; `refresh_<id>` 工作流数 < 设了 `refreshCron` 的 integration 数; `tokenExpiration` 已过期 | 待开发 |
| 首次刷新后 (授权后约 30 天) | 核对该 integration 的 refresh token 已更换 (只比对哈希, 不打印值) | 待授权 |

## 13. 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| `docker compose pull` 报 ghcr `connection reset by peer` (IPv6) | 网络抖动, 旧容器不受影响; 重试 (`for i in 1 2 3; do docker compose pull app && break; sleep 30; done`); 反复被重置时临时在 `/etc/hosts` 把 ghcr.io 与 pkg-containers.githubusercontent.com 映射到 IPv4, 拉完立即还原 (r9 / r11 / r12 用过). 镜像约 7GB, 首拉约 13 分钟 |
| app 反复重启, 日志 `ERR_INVALID_URL` (start.mcp.ts) | `NEXT_PUBLIC_BACKEND_URL` 必须是绝对地址 `https://app.stellarbyte.ca/api`, 不能是 `/api` |
| app 启动卡在 prisma | 启动脚本每次跑 `pnpm dlx prisma@6.5.0 db push`, 需要容器能访问 registry.npmjs.org; 外网或 npm 故障时启动失败, 恢复后 `docker compose restart app` |
| 磁盘不足 | `df -h /`; `docker system df`; 只删确认无用的旧镜像 (`docker image rm <旧 tag>`), 保留当前 tag 与第 3 节写明的回滚目标 tag. 不要 `docker volume prune` (同机有 Stalwart / Listmonk 的卷); 磁盘 > 85% 时 `host-resource-check` 会告警 |
| 备份单元 226/NAMESPACE | `ReadWritePaths` 目录不存在: `install -d -m 0700 /opt/stellarpostiz/backups` |
| Google 登录报 `redirect_uri_mismatch` / `invalid_client` | `GOOGLE_LOGIN_CLIENT_ID/SECRET` 缺失或不是 `stellarbyte-scheduler-login` 的 client; 或 `FRONTEND_URL` 变了而 client 里没登记新回调 (第 12.1 节 "Google 登录") |
| 添加频道里出现 Instagram / Google My Business (审批前) 或旧 TikTok (`tiktok`) | `HIDDEN_PROVIDERS="instagram,instagram-standalone,gmb,tiktok"` 丢了 (两边 `.env`), 改后 `docker compose up -d --no-deps app` |
| Google My Business 授权报 `redirect_uri_mismatch` | `stellarbyte-gbp` 的 client 未登记 `https://app.stellarbyte.ca/integrations/social/gmb`; 或 `.env` 里 `GOOGLE_GMB_CLIENT_*` 丢了 (例如整份 `cp` 旧副本回滚), 代码回退到 stellar-dev 的 YouTube client, 而该 client 不登记 `/gmb` 回调 (spec D25) |
| 非测试用户 Google 登录报 "access blocked / app is being tested" | GCP `stellarbyte-scheduler-login` 同意屏幕被改回 Testing; Audience 页 Publish (2026-11-07 起为 In production) |
| Facebook 授权报 "Invalid Scopes" / "URL blocked" / app 不可用 | 某权限不再是 live (第 12.2 节核对命令), 或回调未登记, 或 Meta 要求年度数据访问续期 (StellarPage 曾因 2026-10-17 未续期被限制) |
| Pinterest 频道提示需重连 (`refreshNeeded`) | 刷新失败一次即退出工作流, 不会自愈 (第 12.3 节); 在该号自己的 HubStudio 环境用 app-ops 登录后 Reconnect, 之后核对 `refresh_<id>` 工作流重新出现 |
| 媒体 URL 404 / 双斜杠 | `CLOUDFLARE_BUCKET_URL` 末尾多了 `/` |
| Cloudflare 526 | SSL 模式被改成 strict, 改回 Full |
| 登录返回 429 | 第 9 节登录限速 (每 IP 10 次/分钟); 等 1 分钟. 多人同一出口 IP 频繁误报时再调 `rate` / `burst` |
| 内存紧张 / OOM | `docker stats`; app 上限 2g 由 cgroup 硬限, 先被杀的是 app/temporal (oom_score_adj 300), Stalwart (-500) 受保护 |
