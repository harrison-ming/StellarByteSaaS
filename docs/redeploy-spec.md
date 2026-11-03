---
owner: Harrison
review_by: 2027-02-01
doc_type: spec
status: active
supersedes: docs/DEPLOYMENT.md (107 Mac + Cloudflare Tunnel 时代的部署指南, 待阶段 5 改写为 Contabo runbook)
---

# StellarByte 重新上线与上游跟进规范 (执行规范 + 验收依据)

> 本文是 2026-11-03 与 Harrison 讨论定稿的结论. 执行 (人或 agent) 必须以本文为准; 与本文冲突的旧文档以本文为准, 并在阶段 5 修正旧文档.
> 授权范围: Harrison 2026-11-03 授权一次性推进全部阶段, 中途不逐项确认; 但第 9 节"保留给用户的动作"除外.

## 1. 目标与边界

- **目标**: 恢复 `https://app.stellarbyte.ca` 的真实使用功能 (社媒排程发布), 达到商业级可运维水准 (第 8 节验收).
- **代码基线**: 上游 Postiz 正式版 `v2.25.3` (2026-10-24), 不跟 main.
- **保留**: Harrison 原有的 StellarByte 品牌改动 (纯前端), 并覆盖新版新增的品牌露出.
- **可持续**: 以后每个上游正式版都能按第 4 节流程低成本跟进.
- **不影响其他项目**: Contabo 上的 Stalwart 邮件 (15 域名) 与 Listmonk 是生产服务, 第 5 节约束是硬性的.
- **不在本期范围**: Facebook / Instagram (两个 Meta app 都不能发 Page 帖, StellarPage 被限制; 见 11 节), LinkedIn 公司主页, Chrome 扩展, 开放注册, 计费.

## 2. 已确定的决策

| # | 决策 | 依据 |
|---|---|---|
| D1 | 不 merge / 不 rebase 旧 fork; 从 `v2.25.3` 新开主线, 重放补丁 | fork 仅 9 个自有 commit, 落后上游 1593 个; 试合并 13 处冲突 |
| D2 | 后台任务用上游 Temporal; 删除 fork 的 `apps/cron` token 刷新 | 上游 `refreshTokenWorkflow` 已内置 |
| D3 | 设 `RUN_CRON=true` | 否则 `missingPostWorkflow` 不启动, 漏发不补 |
| D4 | 数据库: Contabo 本机 Postgres 容器 (app 与 Temporal 分库), 不再用共享 Supabase | 旧 `postiz` schema 已删且无备份; 共享实例是免费版; 规范禁 postgres 超管直连 |
| D5 | 不部署 Elasticsearch; Temporal visibility 用 SQL (Postgres). 若实测不可行, 允许 ES 单节点 heap 256m 且 mem_limit 640m, 同时须重算第 5.2 节内存预算 | 带 ES 超出主机安全容量 |
| D6 | 镜像由 GitHub Actions 构建并推到 `ghcr.io/harrison-ming/stellarbyte`, Contabo 只 pull, 禁止在 Contabo 上构建 | 构建需约 4GB 内存, 会挤占邮件服务 |
| D7 | 品牌主色统一蓝 `#3450D4`, logo 一并改蓝 (旧绿 `#01d408` 废弃) | commit 2d368f32 "统一品牌主色调为 #3450D4" |
| D8 | 品牌替换做到 A 档: 用户主路径 + 全部 locale; 不做 Agents/MCP 内部名与 Chrome 扩展 | 见第 3 节 |
| D9 | 去掉登录页粒子背景 (react-tsparticles 不兼容 React 19) | — |
| D10 | 开发者 / 公开 API / MCP 设置页隐藏; 页脚加 "Powered by Postiz · Source" 链接到公开仓库 | AGPL-3.0 第 13 条 + 诚实署名 |
| D11 | 关闭开放注册 (`DISABLE_REGISTRATION=true`) | SES 与 StellarMail 共用, 保护发信信誉 |
| D12 | 积压 `pinterest_publisher.content_queue` 中 status=pending 的 113 条: 先导出 CSV 留档, 再删除 | Harrison 2026-11-03 决定 |
| D13 | Pinterest 账号全部重新授权 (可授权的约 24 个; revoked/locked/registration_failed 的单列) | Harrison 2026-11-03 决定 |
| D14 | `platforms/pinterest` 旧的 OAuth / token 刷新工具正式废弃, 今后授权一律走 StellarByte UI | 旧工具写已删除的 Supabase `postiz` schema, 且回调地址与 Postiz 冲突 |
| D15 | 媒体存储: R2 桶 `stellar-postiz` (先关 r2.dev 公开访问), 绑 `media.stellarbyte.ca`, 用只限该桶的 R2 token; 不用 `cdn.stellarbyte.ca` (归 grysto) | — |
| D16 | 先在本机 (Mac, arm64, Docker) 试跑通过, 才上 Contabo | — |

## 3. 代码策略: 三层品牌方案

### 3.1 分层

| 层 | 内容 | 实现 | 跟进成本 |
|---|---|---|---|
| L1 git 补丁 (少而稳) | 资源 (favicon.ico / favicon.svg / icon.svg / postiz.svg 原地替换); `new-layout/logo.tsx`、`ui/logo-text.component.tsx`; `colors.scss` 变量; 新增 `brand-overrides.scss` 统一覆盖写死的 `#612BD3` 等任意值类; `auth/layout.tsx` 去掉评价与 "20,000+" 改为 StellarByte 标语; `register.tsx` 条款/隐私链接指向 stellarbyte.ca; 页脚署名; 隐藏开发者/API/MCP 页; 隐藏 LinkedIn Page provider | 主线上按主题拆成少量 commit (brand / scopes / hide), 每个上游 tag cherry-pick | 低, 涉及文件多数半年内上游 0 改动 |
| L1' 非品牌补丁 (独立) | Facebook 去 `pages_manage_engagement`; LinkedIn 只保留 `openid profile email w_member_social`、去 `prompt=none`; `refreshTokens()` 中 `return`→`continue` | 单独一个 commit, 便于升级时取舍 (上游 main 61cf1dda 已修 continue, 升级到含它的版本后丢弃) | 中, provider 文件上游改动频繁 |
| L2 构建时替换脚本 | 页面 title、16 种 locale 的值 (只改值不改 key)、写死文案、邮件标题 (`[Postiz]` 等)、OAuth 授权页 "Sign in to Postiz"、onboarding 文案与 "Sign in with Postiz" 入口 | `scripts/brand/apply-brand.mjs` + `scripts/brand/manifest.json`; 在 Dockerfile `pnpm run build` 之前运行 | 无 git 冲突 |
| L3 环境变量 | `NEXT_PUBLIC_BACKEND_URL=/api` (取代旧 backendUrl 代码补丁)、`EMAIL_FROM_NAME=StellarByte`、关闭统计外发 | `.env` | 零 |

### 3.2 替换脚本的硬性要求 (验收项)

1. 每条规则声明目标文件 glob 与期望最少命中数; **命中 0 次即构建失败** (防止上游改文案后规则静默失效).
2. 构建后对用户可见路径做 "Postiz" 残留扫描, 不在白名单 (`scripts/brand/allowlist.txt`, 每条写理由) 中的命中即构建失败.
3. 只改用户可见文本; 不改内部标识: `@gitroom/*` 包名、`POSTIZ_*` 环境变量名、注释、header 名、类名.
4. 开发者文档类真实产品名 (`npm i -g postiz`、`@postiz/node`) 不改名; 所在页面按 D10 隐藏.
5. 脚本可在本机独立运行 (`node scripts/brand/apply-brand.mjs --check`), 输出每条规则命中数.

### 3.3 诚实红线 (业务组合层规定, 必须满足)

- 删除一切 Postiz 自有的社会证明与数据: 登录页 "Over 20,000+ Entrepreneurs"、16 条真人头像评价 (`testomonials.tsx` 及 `public/auth/avatars/*`)、onboarding / 计费页 "10,000+" 类说法.
- 不得出现任何未经证实的用户数、营收、收益承诺.

### 3.4 统计外发

datafa.st (`data-domain="postiz.com"`)、Plausible、dub (`postiz.pro`) 等外发必须在 StellarByte 构建或环境中关闭; 验收时浏览器网络面板中不得出现指向 postiz 域名的请求.

### 3.5 仓库组织

- 旧 fork 历史打 tag `legacy/v2.7-fork` 保留 (不删).
- 新主线分支 `stellarbyte` = "v2.25.3 + StellarByte 补丁" (不强推覆盖远端 `main`, 不改写任何已推送历史). 是否把 `main` 改指 / 设默认分支由 Harrison 决定 (第 9 节). 远端 `upstream` = `gitroomhq/postiz-app`.
- 废弃并删除: `package-lock.json`、`deploy-to-107*.sh`、`Deploy to 107` workflow、根目录旧 107 版 `docker-compose.yml` (由 `deploy/contabo/` 取代).
- 新增: `deploy/contabo/` (compose, nginx 站点, 备份脚本, systemd 单元模板, `.env.example`), `scripts/brand/`, `.github/workflows/build-stellarbyte.yml`.
- 线上运行的代码必须与公开仓库一致 (AGPL).

## 4. 上游跟进流程 (每个上游正式版)

1. `git fetch upstream --tags`, 阅读 release notes, 特别留意架构变化 (如 Temporal 级别的重构需人工评估).
2. 从新 tag 开分支 `sync/<tag>`, 按顺序 cherry-pick L1 / L1' 补丁; 已被上游修复的 L1' 改动丢弃.
3. 本机运行 `apply-brand.mjs --check`: 所有规则命中数 > 0, 残留扫描通过.
4. CI 构建 (PR 触发) 通过, 本机 compose 试跑冒烟 (第 8.2 节) 通过.
5. 合入 `stellarbyte`, 打 tag `stellarbyte-<上游tag>` (如 `stellarbyte-v2.25.3`), CI 推镜像同名 tag; Contabo 按 runbook 更新镜像 tag 并验收.
6. 回滚: compose 中镜像 tag 改回上一版本, 重启 app 容器; Postgres 回滚须用升级前的 `pg_dump` (升级前必须手动跑一次备份).

## 5. Contabo 部署硬约束 (保护现有服务)

主机: `161.97.184.77`, 8GB, 4 核, Docker 29.9.2 / Compose v5.7.0, live-restore; 现有 Stalwart (1G, oom_score_adj -500)、listmonk-db (1G, -300)、listmonk-app (512M).

### 5.1 网络与端口

- compose 使用独立网络并显式子网 `172.30.0.0/24`.
- 只发布给宿主 Nginx 的入口端口, **一律 `127.0.0.1:` 前缀**; Postgres、Redis、Temporal 不发布任何端口.
- 不占用 8080 (Stalwart 管理面板) 与 9000 (Listmonk). Temporal UI 本期不部署.
- 在 `DOCKER-USER` 链加规则: 丢弃来自 `172.30.0.0/24` 的出站 tcp/25; 规则须持久化 (重启后仍在) 并写入 runbook.
- 上线后验收: 宿主 `ss -tlnp` 无新的 0.0.0.0 监听; 外部 (本机 Mac) 对 161.97.184.77 扫描 4000-9000, 5432, 6379, 7233 均不可达.

### 5.2 资源

| 容器 | mem_limit (=memswap_limit) | cpus | oom_score_adj |
|---|---|---|---|
| app (backend + frontend + orchestrator) | 2g | 2.0 | 300 |
| redis (`maxmemory 192mb`, AOF 开) | 256m | 0.5 | 200 |
| postgres 17 (`shared_buffers=256MB`, app 库 + temporal 库) | 1g | 1.0 | 0 |
| temporal server (SQL visibility) | 1g | 1.0 | 300 |

总限额 (含现有) 约 7.6G / 物理 7.9G, 有 4G swap; 本机试跑须实测常驻内存并记录, 若常驻超过 4G 须先回到本文调整.

### 5.3 Nginx 与 TLS

- 站点文件名 `stellarpostiz` (字母序在 `listmonk` 之后, 不改变当前兜底站点), 同时 `listen 80` 与 `listen 443 ssl`.
- 证书沿用 `/etc/ssl/certs/origin.crt` (**自签名**, 非 Cloudflare Origin CA); Cloudflare SSL 模式必须保持 Full, 不得改 strict.
- 按新版端口布局重写站点配置 (不得直接套用 `decommission-20260908/` 旧版), 加 `client_max_body_size` (建议 100m, 与 Cloudflare 免费版请求体上限一致) 与 WebSocket upgrade.
- `nginx -t` 通过后 reload; 验收 listmonk-api、smtp-admin 访问行为不变.

### 5.4 邮件

- 新建 Stalwart 专用账号 (如 `app-noreply@stellarbyte.ca`), 经 `mx.stellarbyte.ca:587` STARTTLS 提交, 出站走 SES. 走 `/add-email` 流程.
- 禁止容器直连对外 25.

### 5.5 备份与监控

- 新 Postgres 每日 `pg_dump -Fc` (03:45 UTC, 避开 Listmonk 03:15), 本地保留 + 上传私有 R2, 带回读校验与 watchdog; 照搬 `/usr/local/sbin/listmonk-backup.sh` 模式. **验收须完成一次恢复演练** (恢复到临时库并计数核对).
- 全部容器 `restart: unless-stopped` + healthcheck; 外部存活检查失败时通过 Discord 告警 (`STELLAR INFRA/DEPLOY/discord/`).
- 日志 json-file 10m×3.

### 5.6 凭据

- 生产 `.env` 主源: `STELLAR CONFIG/StellarByteSaaS/.env.production`; 服务器 `/opt/stellarpostiz/.env` 权限 600.
- JWT_SECRET、Postgres 密码、Redis 密码全部新生成; **不得复用**旧 compose 中的 Redis 密码 (已在会话输出中暴露过).
- OAuth 凭据取自 Bitwarden: Pinterest `c5fd1a75-…`, LinkedIn `c1153ce7-…`, Google/YouTube `cfc8d358-…` (HOST DEV).
- 新部署跑通后, 删除 `/opt/stellarpostiz/docker-compose.yml.bak*` 与旧 compose (含明文旧密码).

## 6. 跨系统连带处理

| 系统 | 动作 | 时机 |
|---|---|---|
| Windmill | 新建 secret 变量 `u/harrisonvancouver/stellarbyte_api_key` (新 org API key); 更新 `publish_accounts` 与 `pinterest_publisher.accounts` 的 integration_id; 7 个脚本核对 URL/字段 | 账号授权后 |
| Windmill 定时任务 | 5 个相关 schedule **保持 disabled**, 由 Harrison 决定何时开启 | 见第 9 节 |
| Supabase `pinterest_publisher.content_queue` | 导出 pending 113 条为 CSV (落 `~/STELLAR_OUTPUT/_tmp/stellarbyte-redeploy-2026-11/`), 然后删除 | 阶段 4 |
| `platforms/pinterest/` | `oauth.py`、`oauth_api.py`、`db.py`、`scripts/refresh_tokens_api.py` 标记废弃 (文件头 + README), 不再运行 | 阶段 4 |
| `host/StellarView/supabase/migrations/20260202_001_create_postiz_schema.sql` | 文件头加注释停用 (会 `GRANT ALL ... TO anon`), 不再执行 | 阶段 4 |
| Cloudflare | 新增 proxied A `app` → 161.97.184.77; `media` 绑 R2 `stellar-postiz`; 调试期可加 Cloudflare Access, 上线验收后移除或为 `/api/public/*` 加旁路 | 阶段 3 |
| OAuth app 回调 | 核对 Pinterest / LinkedIn / Google 后台 redirect URI 为 `https://app.stellarbyte.ca/integrations/social/<provider>` | 阶段 4 |

## 7. 阶段计划

| 阶段 | 内容 | 退出条件 |
|---|---|---|
| 0 仓库准备 | 提交本地 6 个下线改动留档; 打 tag `legacy/v2.7-fork`; 加 `upstream` remote | tag 已推送 |
| 1 代码 | 基于 v2.25.3 实现第 3 节 L1/L1'/L2/L3; CI workflow | `apply-brand --check` 通过; `pnpm build` 本机通过 |
| 2 本机试跑 | Mac 上 compose 全栈 (含 Temporal SQL visibility) 冒烟 | 第 8.2 节全部通过; 记录常驻内存 |
| 3 Contabo 部署 | 第 5 节全部约束; DNS; R2; 邮件账号; 备份; 监控 | 第 8.3 节全部通过 |
| 4 账号与连带 | Pinterest (全部可授权账号) / LinkedIn 个人 / YouTube 授权; 第 6 节各项 | 每个 provider 至少一个账号授权成功且 token 刷新工作流已注册 |
| 5 文档 | 第 10 节文档清单全部更新; DEPLOYMENT.md 改写为 Contabo runbook | `doc-check` 无陈旧项 |

## 8. 验收标准

### 8.1 代码

- 主线 `stellarbyte` = `v2.25.3` + 补丁 commit, `git log v2.25.3..stellarbyte` 只有 StellarByte 补丁.
- 品牌: 登录、注册、侧栏、页面标题、邮件、OAuth 授权页、onboarding 无 Postiz 字样 (白名单除外); 主色蓝; 无 Postiz 社会证明; 页脚有署名与源码链接.
- CI 构建成功并推送 `ghcr.io/harrison-ming/stellarbyte:stellarbyte-v2.25.3` (amd64).

### 8.2 本机冒烟

- 全部容器 healthy; `prisma db push` 完成; Temporal 工作流 worker 已连接.
- 注册首个管理员 (注册关闭前的首用户或命令行创建), 登录, 创建组织 API key.
- 上传媒体到 R2 并能在页面显示; 创建一条定时帖到 "预览/草稿" 路径 (不发真实平台).
- 浏览器网络面板无 postiz 域名外发.

### 8.3 Contabo 上线

- `https://app.stellarbyte.ca` 正常; 第 5.1 节端口扫描通过; 出站 25 被拦截 (容器内 `nc -zv gmail-smtp-in.l.google.com 25` 失败); listmonk-api / smtp-admin / 邮件收发不受影响 (Stalwart 健康探测脚本通过).
- 备份已跑一次并完成恢复演练; 外部存活告警已验证可触发.
- 资源: 上线 24h 内无 OOM, Stalwart 内存与延迟无异常.

### 8.4 商业级底线

HTTPS 全站; 注册关闭; 所有密钥新生成且不入 git; 每日备份 + 恢复演练; 告警; 资源限额; runbook 含部署、升级、回滚、恢复; 公开源码一致 (AGPL).

## 9. 保留给用户的动作

- 开启 Windmill 自动发布定时任务 (会对真实账号发帖).
- 是否让远端 `main` 改指新主线 `stellarbyte` (需强推或改默认分支; 旧历史已由 tag `legacy/v2.7-fork` 保留).
- Bitwarden 写入 (全局规则要求逐条确认, hook 硬拦): 执行中需要入 BW 的条目汇总成清单交用户.
- 需要人工登录 / 2FA / 验证码的平台授权.
- Meta (Facebook / Instagram) 接入与 StellarPage 数据访问续期.
- 删除 Contabo 上的遗留镜像与匿名卷 (可回收约 12G, 非必要).

## 10. 需同步更新的文档

`docs/config-readme.md`; `docs/DEPLOYMENT.md` (改写); `STELLAR INFRA/machines/contabo/StellarPostiz/README.md`; `machines/contabo/vps-161.97.184.77.md` (Docker 版本、证书为自签名、站点列表、遗留物、Stalwart 无备份); `DEPLOY/cloudflare/usage-by-project.md` 与 `resource.md/json`; `domains/stellarbyte.ca.md`; `STELLAR CONFIG/StellarByteSaaS/accounts.md`; `STELLAR CONFIG/HarrisonMing/credentials.md`; `platforms/pinterest/` (README、account-status、automation、token-refresh-issue); `STELLAR CONFIG/Windmill/pinterest/README.md`; `STELLAR CONFIG/Windmill/agent-flow/multi-channel-design.md`; `host/Windmill/CLAUDE.md`; `machines/MacMini/pinterest-publisher/README.md` (整篇过期).

## 11. 已知风险与未决

- 新应用与邮件服务同机: 资源与网络已隔离, 但整机级故障 (入侵、供应商停机) 会同时影响两者. 彻底隔离需换机器.
- Meta: StellarPage app 因 2026-10-17 未完成数据访问续期被限制 API; 续期需要可访问的应用地址与测试账号. StellarByte Login app 只有 email/public_profile. 本期不接.
- Temporal SQL visibility 未实测 (D5 有退路).
- Stalwart 邮件数据无任何备份 (与本项目无关, 建议另立项).
- 审计证据与试做补丁 (临时): `/private/tmp/claude-501/-Users-ming-Documents-host-StellarByteSaaS/dd90af70-e826-47ec-ad4b-68bfc08b149e/scratchpad/branding/`.
