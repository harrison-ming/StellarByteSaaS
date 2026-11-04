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
- 公开 API: `https://app.stellarbyte.ca/api/public/v1`, header `Authorization: <组织 API key>`. key 存 Windmill 变量 `u/harrisonvancouver/stellarbyte_api_key` (secret).

## 2. 文件位置 (只列路径, 不含值)

| 位置 | 内容 |
|---|---|
| 仓库 `deploy/contabo/` | `docker-compose.yml`, `docker-compose.local.yml` (本机试跑 override), `.env.example`, `postgres/init/10-databases.sh`, `temporal/dynamicconfig/`, `nginx/stellarpostiz`, `firewall/`, `backup/` (脚本 + systemd 单元模板), `signup-notify/` (新注册 Discord 通知, r6) |
| 服务器 `/opt/stellarpostiz/` | `docker-compose.yml`, `.env` (600), `postgres/init/`, `temporal/` (均从仓库复制), `backups/` (700), `decommission-20260908/` (旧 nginx 站点存档) |
| 服务器 `/usr/local/sbin/` | `stellarbyte-backup.sh`, `stellarbyte-docker-user-fw.sh`, `stellarbyte-signup-notify.sh`, 共用 `notify-command-status.sh` (Discord 告警), 主机级 `host-resource-check.sh` (源码 `STELLAR INFRA/machines/contabo/host-monitor/`) |
| 服务器 `/etc/systemd/system/` | `stellarbyte-backup.{service,timer}`, `stellarbyte-backup-watchdog.{service,timer}`, `stellarbyte-docker-user-fw.service`, `stellarbyte-signup-notify.{service,timer}`; 主机级 `host-resource-check.{service,timer}` |
| 服务器 `/etc/nginx/sites-available/stellarpostiz` | 站点 (symlink 到 sites-enabled) |
| 服务器 `/root/.config/stellarbyte/r2-backup.env` (600) | 备份桶 R2 token |
| 服务器 `/root/.config/stellarbyte/signup-notify.env` (600) | `#stellarbyte-signups` 频道 webhook (`DISCORD_WEBHOOK_URL`); 水位线在 `/var/lib/stellarbyte-signup-notify/watermark` |
| 本机 `STELLAR CONFIG/StellarByteSaaS/.env.production` (600) | 生产 `.env` **主源**; 改动先改这里再同步到服务器 |
| 本机 `STELLAR CONFIG/StellarByteSaaS/credentials.md` / `accounts.md` | 凭据索引 (无明文) / 组织与账号映射 |
| 本机 `STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json` (600) | Google 登录 client (GCP 项目 `stellarbyte-scheduler-login`, spec D19); 值已进 `.env` 的 `GOOGLE_LOGIN_CLIENT_ID/SECRET` |
| Bitwarden | OAuth: Pinterest `c5fd1a75-…`, LinkedIn `c1153ce7-…`, YouTube `cfc8d358-…` (只用于频道授权); Google 登录 client 条目 `StellarByte Google OAuth - stellarbyte-scheduler-login` 待 Harrison 写入 |

## 3. 部署 / 更新镜像 tag

tag 规则: `stellarbyte-<上游tag>[-rN]`. 已推送的 tag 不改写, 同一上游版本的修订用 `-rN` 递增 (r2 首个可用镜像; r3 隐藏 Google 登录; r4 Pinterest refresh token 修复; r5 无计费不加载 Stripe.js + 国旗图标自托管; r6 去掉 app 内署名/源码链接, 独立 Google 登录 client + 按已验证邮箱关联本地账号, 开放注册). **当前线上 r6, 回滚目标 r5** (服务器 `.env.pre-r6`, r5 镜像保留). 注意 r5 镜像的 Google 登录读 `YOUTUBE_CLIENT_*`, 回滚到 r5 时把 `GOOGLE_LOGIN_ENABLED` 设回 `false`.

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

新版本发现: `.github/workflows/upstream-release-watch.yml` 每周一比对上游最新 release 与 `UPSTREAM_BASE`, 有新版时开 issue. GitHub 只从**默认分支**运行定时 workflow (手动 Run 也要求文件在默认分支); 远端默认分支仍是 `main`, 所以在默认分支改为 `stellarbyte` (spec 第 9 节, 待 Harrison 决定) 前它不会运行, 期间人工核对 `gh api repos/gitroomhq/postiz-app/releases/latest --jq .tag_name`. 本机试跑: `deploy/contabo/docker-compose.local.yml` (子网 `STELLARBYTE_SUBNET=172.31.250.0/24`, 本机 172.30 已被占用).

## 5. 回滚

- **只回滚 app**: 把 `STELLARBYTE_TAG` 改回上一 tag (服务器上有 `.env.pre-rN` 可直接 `cp` 回去), `docker compose up -d --no-deps app`. 上一版镜像在服务器上保留一版, 不要在验收前 prune.
- **数据库也要回滚** (上游 schema 变更): 停 app -> 用升级前的 dump 恢复 (第 6.3 节) -> 起旧 tag. `prisma db push` 每次启动都会跑, 不可逆的列删除只能靠 dump 恢复.

## 6. 备份与恢复

### 6.1 例行

- `stellarbyte-backup.timer` 每天 03:45 UTC: 三个库 `pg_dump -Fc` -> 校验 -> sha256 + manifest -> `/opt/stellarpostiz/backups/` (保留 14 天) -> 上传 R2 `stellarbyte-backups/stellarbyte/` 并回读校验 (桶 lifecycle 35 天).
- `stellarbyte-backup-watchdog.timer` 每小时 :50: 最新一组须 26h 内, 有效, 且 R2 存在; 失败经 `notify-command-status.sh` 发 Discord (首次失败 + 恢复各一条).
- 媒体在 R2 `stellar-postiz`, 不在备份范围 (R2 自身持久化). Redis 只放队列/缓存, 不备份.

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

组织 API key 在 Settings 里 Rotate, 新值写回 Windmill 变量 `u/harrisonvancouver/stellarbyte_api_key` (第 1 节). 2026-11-04 (r6) 旧账号与组织已删除 (D22: 删除前 dump `/root/r6-predelete-20261104/stellarbyte-predelete.dump`, 单事务 `TRUNCATE "Media", "UserOrganization", "Organization", "User" CASCADE`, 删后 88 表全 0), 旧 key 失效; Harrison 重新注册后须做上面两步. 旧组织上传过 1 个媒体, 其 R2 对象仍在 `stellar-postiz` (无 DB 引用, 未删).

#### Google 登录 (r6, spec D19 / D20)

- 独立 OAuth client `StellarByte App Login` (GCP 项目 `stellarbyte-scheduler-login`), 环境变量 `GOOGLE_LOGIN_CLIENT_ID` / `GOOGLE_LOGIN_CLIENT_SECRET` (取自 `STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json` 的 `.web.client_id` / `.web.client_secret`), 按钮开关 `GOOGLE_LOGIN_ENABLED="true"`. 不回退 `YOUTUBE_*`: 没配 client 时不要打开开关.
- 回调沿用上游 `https://app.stellarbyte.ca/integrations/social/youtube` (`state=login` 区分登录与 YouTube 频道授权), 已在该 client 登记 (另有 `http://localhost:4007/...` 供本机试跑).
- 核对授权链接用的是新 client (只看前缀): `curl -s https://app.stellarbyte.ca/api/auth/oauth/GOOGLE | grep -o 'client_id=[0-9]\{12\}'` 应为 `344812424356`.
- 已验证邮箱关联: Google 账号的已验证邮箱与已有本地 (邮箱注册) 用户相同时, 直接登录该用户 (仅限已激活的本地用户; 未激活的不关联, 照常新建 Google 用户, 防止他人抢注同邮箱后接管), 不新建组织, 不改 `providerName`. Google 返回的 token 必须是发给本 client 的 (`getTokenInfo` 校验 `aud`). 移动端 (上游 app 的 `redirect_uri`) 不在范围, 未在新 client 登记.
- 关闭: `GOOGLE_LOGIN_ENABLED="false"` + `docker compose up -d --no-deps app`.

### 12.2 社媒账号授权

- 一律在 StellarByte UI "Add Channel" 走 OAuth (旧 `platforms/pinterest` 授权/刷新工具已废弃, D14). 回调 `https://app.stellarbyte.ca/integrations/social/<provider>`.
- **Pinterest**: 逐账号操作清单 (授权前置条件, 身份核对, 回填项) 见 `STELLAR INFRA/platforms/pinterest/authorization-checklist.md`; 下面是要点. 每个账号必须在它自己的 HubStudio 环境里授权 (BW 条目的 "Browser ID" = HubStudio containerCode), 不得在本机浏览器混登. 授权前先在该环境确认 pinterest.com 当前登录的就是目标账号 (头像 / 用户名与 `platforms/pinterest/account-status.md` 一致), 再在该环境打开 StellarByte 登录并 Add Channel. 授权后核对 UI 显示的用户名.
- token 刷新: Temporal `refreshTokenWorkflow` 对设了 `refreshCron` 的 provider (Pinterest 自 r4 起, 以及 Threads / Instagram standalone) 在 access token 到期时主动刷新; 其余 provider (LinkedIn / YouTube 等) 在发帖时按需刷新. 失败时 integration 标 `refreshNeeded`, UI 提示重连.
- 授权后回填: Windmill 变量 `publish_accounts` 与 Supabase `pinterest_publisher.accounts` 的 integration_id; `STELLAR CONFIG/StellarByteSaaS/accounts.md`.

## 13. 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| `docker compose pull` 报 ghcr `connection reset by peer` (IPv6) | 网络抖动, 旧容器不受影响; 重试 (`for i in 1 2 3; do docker compose pull app && break; sleep 30; done`). 镜像约 7GB, 首拉约 13 分钟 |
| app 反复重启, 日志 `ERR_INVALID_URL` (start.mcp.ts) | `NEXT_PUBLIC_BACKEND_URL` 必须是绝对地址 `https://app.stellarbyte.ca/api`, 不能是 `/api` |
| app 启动卡在 prisma | 启动脚本每次跑 `pnpm dlx prisma@6.5.0 db push`, 需要容器能访问 registry.npmjs.org; 外网或 npm 故障时启动失败, 恢复后 `docker compose restart app` |
| 磁盘不足 | `df -h /`; `docker system df`; 只删确认无用的旧镜像 (`docker image rm <旧 tag>`), 保留当前与上一版. 不要 `docker volume prune` (同机有 Stalwart / Listmonk 的卷); 主机遗留镜像与匿名卷已于 2026-11-03 清理 (根盘 31% → 15%, 明细见 INFRA vps 文档历史节); 磁盘 > 85% 时 `host-resource-check` 会告警 |
| 备份单元 226/NAMESPACE | `ReadWritePaths` 目录不存在: `install -d -m 0700 /opt/stellarpostiz/backups` |
| Google 登录报 `redirect_uri_mismatch` / `invalid_client` | `GOOGLE_LOGIN_CLIENT_ID/SECRET` 缺失或不是 `stellarbyte-scheduler-login` 的 client; 或 `FRONTEND_URL` 变了而 client 里没登记新回调 (第 12.1 节 "Google 登录") |
| LinkedIn 出现 "LinkedIn Page" | `HIDDEN_PROVIDERS="linkedin-page"` 丢了 |
| 媒体 URL 404 / 双斜杠 | `CLOUDFLARE_BUCKET_URL` 末尾多了 `/` |
| Cloudflare 526 | SSL 模式被改成 strict, 改回 Full |
| 登录返回 429 | 第 9 节登录限速 (每 IP 10 次/分钟); 等 1 分钟. 多人同一出口 IP 频繁误报时再调 `rate` / `burst` |
| 内存紧张 / OOM | `docker stats`; app 上限 2g 由 cgroup 硬限, 先被杀的是 app/temporal (oom_score_adj 300), Stalwart (-500) 受保护 |
