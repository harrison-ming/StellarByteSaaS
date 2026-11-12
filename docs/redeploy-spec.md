---
owner: Harrison
review_by: 2027-02-01
doc_type: spec
status: active
---

# StellarByte 重新上线与上游跟进规范 (执行规范 + 验收依据)

> 本文是 2026-11-03 与 Harrison 讨论定稿的结论 (2026-11-04 追加 D17-D23, 见第 2 节), 并已按实际执行结果修订 (执行结果见第 7.1 节, 运维操作见 [DEPLOYMENT.md](DEPLOYMENT.md)). 执行 (人或 agent) 必须以本文为准; 与本文冲突的旧文档以本文为准.
> 授权范围: Harrison 2026-11-03 授权一次性推进全部阶段, 中途不逐项确认; 但第 9 节"保留给用户的动作"除外.

## 1. 目标与边界

- **目标**: 恢复 `https://app.stellarbyte.ca` 的真实使用功能 (社媒排程发布), 达到商业级可运维水准 (第 8 节验收).
- **代码基线**: 上游 Postiz 正式版 `v2.25.3` (2026-10-24), 不跟 main.
- **保留**: Harrison 原有的 StellarByte 品牌改动 (纯前端), 并覆盖新版新增的品牌露出.
- **可持续**: 以后每个上游正式版都能按第 4 节流程低成本跟进.
- **不影响其他项目**: Contabo 上的 Stalwart 邮件 (16 域名 / 41 账号, 2026-11-03 实测) 与 Listmonk 是生产服务, 第 5 节约束是硬性的.
- **不在本期范围**: Instagram (`instagram_*` 权限未提审), Chrome 扩展, 计费. (开放注册自 r6 起纳入, 见 D21; Facebook Page 自 2026-11-07 起纳入, 见 D24; LinkedIn 公司主页与 Google Business Profile 自 r7 起代码与配置就位, 等平台审批, 见 D25.)

## 2. 已确定的决策

| # | 决策 | 依据 |
|---|---|---|
| D1 | 不 merge / 不 rebase 旧 fork; 从 `v2.25.3` 新开主线, 重放补丁 | fork 仅 9 个自有 commit, 落后上游 1593 个; 试合并 13 处冲突 |
| D2 | 后台任务用上游 Temporal; 删除 fork 的 `apps/cron` token 刷新 | 上游 `refreshTokenWorkflow` 已内置, 但只对声明 `refreshCron` 的 provider 启动 (v2.25.3 为 Threads / Instagram standalone); 其余 provider 在发帖时按需刷新. Pinterest 由 L1' 补丁设 `refreshCron` (r4) |
| D3 | 设 `RUN_CRON=true` | 否则 `missingPostWorkflow` 不启动, 漏发不补 |
| D4 | 数据库: Contabo 本机 Postgres 容器 (app 与 Temporal 分库), 不再用共享 Supabase | 旧 `postiz` schema 已删且无备份; 共享实例是免费版; 规范禁 postgres 超管直连 |
| D5 | 不部署 Elasticsearch; Temporal visibility 用 SQL (Postgres). 若实测不可行, 允许 ES 单节点 heap 256m 且 mem_limit 640m, 同时须重算第 5.2 节内存预算 | 带 ES 超出主机安全容量 |
| D6 | 镜像由 GitHub Actions 构建并推到 `ghcr.io/harrison-ming/stellarbyte-app` (公开包, 随公开仓库; 旧私有包 `stellarbyte` 未授权 Actions, 弃用), Contabo 只 pull, 禁止在 Contabo 上构建 | 构建需约 4GB 内存, 会挤占邮件服务 |
| D7 | 品牌主色统一蓝 `#3450D4`, logo 一并改蓝 (旧绿 `#01d408` 废弃) | commit 2d368f32 "统一品牌主色调为 #3450D4" |
| D8 | 品牌替换做到 A 档: 用户主路径 + 全部 locale; 不做 Agents/MCP 内部名与 Chrome 扩展 | 见第 3 节 |
| D9 | 去掉登录页粒子背景 (react-tsparticles 不兼容 React 19) | — |
| D10 | 开发者 / 公开 API / MCP 设置页 ("Agents / Dev" 与 "Apps" 标签) 对普通用户隐藏, 仅超管 (`isSuperAdmin`) 可见 (偏离原定 "完全隐藏": 管理员要在此轮换组织 API key); onboarding 去掉 Postiz MCP/CLI/API 入口. (原定的 "Powered by Postiz · Source" 页脚已由 D17 取消) | 开发者入口是 Postiz 自有产品, 普通用户用不到 |
| D11 | ~~关闭开放注册 (`DISABLE_REGISTRATION=true`)~~ 已由 D21 取代 (r6) | 原依据: SES 与 StellarMail 共用, 保护发信信誉 |
| D12 | 积压 `pinterest_publisher.content_queue` 中 status=pending 的 112 条 (原估 113, 实际 112): 先导出 CSV 留档, 再删除 | Harrison 2026-11-03 决定 |
| D13 | Pinterest 账号全部重新授权 (可授权的原估约 24 个, 实际 23 个; revoked/locked/registration_failed 的单列) | Harrison 2026-11-03 决定 |
| D14 | `platforms/pinterest` 旧的 OAuth / token 刷新工具正式废弃, 今后授权一律走 StellarByte UI | 旧工具写已删除的 Supabase `postiz` schema, 且回调地址与 Postiz 冲突 |
| D15 | 媒体存储: R2 桶 `stellar-postiz` (先关 r2.dev 公开访问), 绑 `media.stellarbyte.ca`, 用只限该桶的 R2 token; 不用 `cdn.stellarbyte.ca` (归 grysto) | — |
| D16 | 先在本机 (Mac, arm64, Docker) 试跑通过, 才上 Contabo | — |
| D17 | app 前端去掉全部 "Powered by Postiz · Source" 署名与源码链接 (登录页 / 应用内页脚组件删除; 计费 FAQ "Can I trust ... open-source" 条目删除, 其 16 种 locale 值由 L2 清空); 取代 D10 的页脚部分 (r6) | Harrison 2026-11-04 决定: app 界面不放第三方署名 |
| D18 | AGPL-3.0 源码声明改放公开条款页 `https://stellarbyte.ca/terms/` (英文一段: app 基于 Postiz, AGPL-3.0, 修改版完整源码地址 `https://github.com/harrison-ming/StellarByteSaaS`), app 界面不再放 | AGPL-3.0 第 13 条要求向网络用户提供源码获取途径; 条款页是注册时链接的公开页面 |
| D19 | Google 登录只用独立 OAuth client (GCP 项目 `stellarbyte-scheduler-login`, 同意屏幕应用名 "StellarByte", External, 仅 `userinfo.email` + `userinfo.profile`); 环境变量 `GOOGLE_LOGIN_CLIENT_ID` / `GOOGLE_LOGIN_CLIENT_SECRET`, **不回退** `YOUTUBE_*`; 回调仍是上游默认 `${FRONTEND_URL}/integrations/social/youtube` + `state=login`; 按钮仍受 `GOOGLE_LOGIN_ENABLED` 控制 (r6) | 与 stellar-dev 项目的敏感 scope 与品牌隔离 (同 moveset-io 的做法), 登录同意屏幕显示 StellarByte |
| D20 | 按已验证邮箱关联账号: OAuth 登录找不到 (providerId, provider) 对应用户时, 若 provider 报告邮箱已验证 (`getUser` 返回 `emailVerified: true`, 目前只有 Google 设置) 且存在同邮箱的**已激活**本地账号, 直接登录该账号 (未激活的不关联, 防止他人先用该邮箱抢注后接管; Google token 须经 `getTokenInfo` 校验 `aud` 为本 client); 不写 `providerName` / `providerId`, 不改已存字段含义; 其余情况走原注册路径 (r6) | 同一人先邮箱注册后用 Google 登录时不产生第二个组织 |
| D21 | 开放注册 `DISABLE_REGISTRATION=false` (取代 D11); 本地邮箱注册仍须邮件激活; 需要时设回 `true` 并重建 app 即可快速关闭 (runbook 第 12 节) (r6) | Harrison 2026-11-04 决定. 发信信誉风险由激活邮件 + `/api/auth/*` 登录限速 + D23 注册通知人工盯防 |
| D22 | 删除现有唯一账号 (LOCAL) 及其组织与全部组织数据, 删除前 `pg_dump` 留档; Harrison 用新流程自行重新注册; 不预建用户. 之后: 新用户设 `isSuperAdmin=true`, 轮换组织 API key 写回 Windmill `u/harrisonvancouver/stellarbyte_api_key` (旧 key 随旧组织失效) (r6) | 单用户, 不要求向后兼容 |
| D23 | 每次新注册发 Discord 通知 (时间, 邮箱, 组织名, provider): Contabo 宿主 systemd timer 每 5 分钟只读查询 Postgres 新用户 (水位线), 不改 app 代码; webhook/token 只放服务器 root-only env 文件 (r6) | 开放注册后需要人工知道谁注册了; 宿主脚本不进上游补丁, 跟进成本为零 |
| D24 | 接入 Facebook Page: Meta app `StellarPage` (App ID `4160936944155117`) 完成数据访问续期与审核 (用例 "Manage everything on your Page", Published), `.env` 加 `FACEBOOK_APP_ID` / `FACEBOOK_APP_SECRET`, 只重建 app, 无代码改动; 代码请求的 5 个权限经 Graph API 核对均为 live. Instagram 仍不在范围. Meta 审核测试账号 `test@stellarbyte.ca` (组织 "Meta App Review", 非超管; 邮箱 Stalwart `sb-test`) | Harrison 2026-11-07 决定并授权上线 |
| D25 | LinkedIn 公司主页与 Google Business Profile (GMB) 按 SaaS 方式接入, 审批前入口隐藏: (a) LinkedIn 公司页用**独立 LinkedIn app** (Community Management API 必须是 app 上唯一产品, 不能与现有 app `StellarByte` 86kzdi1nd1zs2q 的 Share on LinkedIn / OpenID 共存), 环境变量 `LINKEDIN_PAGE_CLIENT_ID/SECRET` (未设时回退 `LINKEDIN_CLIENT_*`), 公司页 scope 改为 `r_basicprofile w_member_social rw_organization_admin w_organization_social r_organization_social`, 成员身份改走 `/v2/me` (该 app 无 OpenID); 个人号 provider 不变. (b) GMB 用独立 GCP 项目 `stellarbyte-gbp` (编号 56650864023, 同意屏幕 StellarByte) 的 client, 环境变量 `GOOGLE_GMB_CLIENT_ID/SECRET` (上游已有, 无代码改动); 不用 YouTube 的 stellar-dev client, 因其同意屏幕挂着 30+ 个含 Drive 受限权限的 scope, 无法为 SaaS 过 Google 验证. (c) `HIDDEN_PROVIDERS` 保留 `linkedin-page`, 新增 `gmb`, 各自审批通过并实测后再去掉 (r7) | LinkedIn 平台规则; GMB 发帖依赖 Business Profile API 访问 (项目配额默认 0 QPM, 2026-11-12 控制台实测), 申请要求商家资料验证满 60 天, 最早 2027-01-10 (`host/StellarByte/docs/seo/README.md`); 不给 SaaS 用户暴露必然失败的入口 |

## 3. 代码策略: 三层品牌方案

### 3.1 分层

| 层 | 内容 | 实现 | 跟进成本 |
|---|---|---|---|
| L1 git 补丁 (少而稳) | 资源 (favicon.ico / favicon.svg / icon.svg / postiz.svg 原地替换); `new-layout/logo.tsx`、`ui/logo-text.component.tsx`; `colors.scss` 变量; 新增 `brand-overrides.scss` 统一覆盖写死的 `#612BD3` 等任意值类; `auth/layout.tsx` 去掉评价与 "20,000+" 改为 StellarByte 标语; `register.tsx` 条款/隐私链接指向 stellarbyte.ca; 计费 FAQ 删去 "open-source" 条目 (D17, r6); 开发者/API/MCP 页仅超管可见; 登录/注册页 Google 按钮受 `GOOGLE_LOGIN_ENABLED` 控制 (默认隐藏, r3); Google 登录改用独立 client `GOOGLE_LOGIN_CLIENT_*` 并按已验证邮箱关联本地账号 (D19 / D20, r6) | 主线上按主题拆成少量 commit (brand / scopes / hide), 每个上游 tag cherry-pick | 低, 涉及文件多数半年内上游 0 改动 |
| L1' 非品牌补丁 (独立) | Facebook 去 `pages_manage_engagement`; LinkedIn 只保留 `openid profile email w_member_social`、去 `prompt=none`; `refreshTokens()` 中 `return`→`continue`; Pinterest `refreshToken()` 保存响应里的新 refresh_token 并设 `refreshCron = true` (r4, Pinterest continuous refresh token 60 天且每次刷新轮换, 原样回传旧 token 会在约 60 天后失效); 未配置计费时不加载 Stripe.js (`@stripe/stripe-js/pure` + 无 publishable key 不调 `loadStripe`) 与国旗图标自托管 (`public/icons/flags/`, 不再请求 cdn.jsdelivr.net) (r5) | 按主题单独 commit, 便于升级时取舍 (上游 main 61cf1dda 已修 continue; Pinterest 问题截至上游 main bd8353f0 仍在, 可提上游 PR; 上游修复后丢弃) | 中, provider 文件上游改动频繁 |
| L2 构建时替换脚本 | 页面 title、16 种 locale 的值 (只改值不改 key)、写死文案、邮件标题 (`[Postiz]` 等)、OAuth 授权页 "Sign in to Postiz"、onboarding 文案与 "Sign in with Postiz" 入口 | `scripts/brand/apply-brand.mjs` + `scripts/brand/manifest.json`; 在 Dockerfile `pnpm run build` 之前运行 | 无 git 冲突 |
| L3 环境变量 | `NEXT_PUBLIC_BACKEND_URL=https://app.stellarbyte.ca/api` (同源绝对地址, 取代旧 backendUrl 代码补丁; 阶段 2 实测相对值 `/api` 会让 backend 在 `start.mcp.ts` 的 `new URL()` 处崩溃)、`EMAIL_FROM_NAME=StellarByte`、`HIDDEN_PROVIDERS=linkedin-page,instagram,instagram-standalone` (隐藏 LinkedIn 公司主页与 Instagram, 2026-11-07 加 Instagram; 上游机制无代码改动)、`DISABLE_REGISTRATION=false` (D21)、`GOOGLE_LOGIN_ENABLED` + `GOOGLE_LOGIN_CLIENT_ID/SECRET` (D19)、关闭统计外发 | `.env` (模板 `deploy/contabo/.env.example`) | 零 |

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
- 新主线分支 `stellarbyte` = "v2.25.3 + StellarByte 补丁" (不强推覆盖远端 `main`, 不改写任何已推送历史). 默认分支 2026-11-07 已改为 `stellarbyte` (`main` 保留不动). 远端 `upstream` = `gitroomhq/postiz-app`.
- 废弃并删除: `package-lock.json`、`deploy-to-107*.sh`、`Deploy to 107` workflow、根目录旧 107 版 `docker-compose.yml` (由 `deploy/contabo/` 取代).
- 新增: `deploy/contabo/` (compose, `docker-compose.local.yml` 本机试跑 override, nginx 站点, `firewall/`, 备份脚本与 systemd 单元模板, `signup-notify/` (r6), `postgres/init`, `temporal/dynamicconfig`, `.env.example`), `scripts/brand/`, `.github/workflows/build-stellarbyte.yml`, `.github/workflows/upstream-release-watch.yml` + 根目录 `UPSTREAM_BASE` (当前基线上游 tag).
- 线上运行的代码必须与公开仓库一致 (AGPL); 源码获取途径公示在 `https://stellarbyte.ca/terms/` (D18), app 界面不放源码链接 (D17).

## 4. 上游跟进流程 (每个上游正式版)

发现: workflow `upstream-release-watch.yml` 每周一 06:17 UTC (及手动 `workflow_dispatch`) 比较上游最新 release 与 `UPSTREAM_BASE`, 有新版且无同名 open issue 时开 issue "上游新版本 <tag>: 按 redeploy-spec 第 4 节跟进" (附本节清单). **GitHub 只从默认分支运行 schedule, `workflow_dispatch` 也要求 workflow 文件存在于默认分支**; 远端默认分支 2026-11-07 已改为 `stellarbyte`, 每周 schedule 生效 (当天手动 Run 一次 success). 怀疑漏报时人工核对: `gh api repos/gitroomhq/postiz-app/releases/latest --jq .tag_name`.

1. `git fetch upstream --tags`, 阅读 release notes, 特别留意架构变化 (如 Temporal 级别的重构需人工评估).
2. 从新 tag 开分支 `sync/<tag>`, 按顺序 cherry-pick L1 / L1' 补丁; 已被上游修复的 L1' 改动丢弃.
3. 本机运行 `apply-brand.mjs --check`: 所有规则命中数 > 0, 残留扫描通过.
4. CI 构建 (PR 触发) 通过, 本机 compose 试跑冒烟 (第 8.2 节) 通过.
5. 合入 `stellarbyte`, 把 `UPSTREAM_BASE` 改为新 tag, 打 tag `stellarbyte-<上游tag>` (如 `stellarbyte-v2.25.3`), CI 推镜像同名 tag; Contabo 按 runbook 更新镜像 tag 并验收.
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
- 安全头与登录限速只写在本站点文件内 (不改全局 `nginx.conf`, 不改 Cloudflare zone): HSTS 6 个月不带 preload, nosniff, `X-Frame-Options SAMEORIGIN`, `Referrer-Policy strict-origin-when-cross-origin`, 最小 `Permissions-Policy`; `/api/auth/*` 未登录端点按访客真实 IP 限速并返回 429 (2026-11-04 补, 细节 runbook 第 9 节).

### 5.4 邮件

- 新建 Stalwart 专用账号 (如 `app-noreply@stellarbyte.ca`), 经 `mx.stellarbyte.ca:587` STARTTLS 提交, 出站走 SES. 走 `/add-email` 流程.
- 禁止容器直连对外 25.

### 5.5 备份与监控

- 新 Postgres 每日 `pg_dump -Fc` (03:45 UTC, 避开 Listmonk 03:15), 本地保留 + 上传私有 R2, 带回读校验与 watchdog; 照搬 `/usr/local/sbin/listmonk-backup.sh` 模式. **验收须完成一次恢复演练** (恢复到临时库并计数核对).
- 全部容器 `restart: unless-stopped` + healthcheck; 外部存活检查失败时通过 Discord 告警 (`STELLAR INFRA/DEPLOY/discord/`); 主机资源 (磁盘 / 内存 / swap / OOM) 每 10 分钟检查, 越线经同一通知器告警 (2026-11-04 补).
- 日志 json-file 10m×3.

### 5.6 凭据

- 生产 `.env` 主源: `STELLAR CONFIG/StellarByteSaaS/.env.production`; 服务器 `/opt/stellarpostiz/.env` 权限 600.
- JWT_SECRET、Postgres 密码、Redis 密码全部新生成; **不得复用**旧 compose 中的 Redis 密码 (已在会话输出中暴露过).
- OAuth 凭据取自 Bitwarden: Pinterest `c5fd1a75-…`, LinkedIn `c1153ce7-…`, YouTube `cfc8d358-…` (HOST DEV, 只用于 YouTube 频道授权). Google 登录用独立 client (D19): 下载的 JSON 落 `STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json`, 值进 `.env` 的 `GOOGLE_LOGIN_CLIENT_ID/SECRET`, BW 备份条目 "StellarByte Google OAuth - stellarbyte-scheduler-login" (2026-11-07 已写入, UUID 见 `STELLAR CONFIG/StellarByteSaaS/credentials.md`).
- 新部署跑通后, 删除 `/opt/stellarpostiz/docker-compose.yml.bak*` 与旧 compose (含明文旧密码).

## 6. 跨系统连带处理

| 系统 | 动作 | 时机 |
|---|---|---|
| Windmill | 新建 secret 变量 `u/harrisonvancouver/stellarbyte_api_key` (新 org API key; 2026-11-07 已写回组织 StellarByte 的 key, D22); 更新 `publish_accounts` 与 `pinterest_publisher.accounts` 的 integration_id; 7 个脚本核对 URL/字段 | 账号授权后 |
| Windmill 定时任务 | 5 个相关 schedule **保持 disabled**, 由 Harrison 决定何时开启 | 见第 9 节 |
| Supabase `pinterest_publisher.content_queue` | 导出 pending 112 条为 CSV (落 `~/STELLAR_OUTPUT/_tmp/stellarbyte-redeploy-2026-11/`), 然后删除 | 阶段 4 |
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
| 4 账号与连带 | Pinterest (全部可授权账号) / LinkedIn 个人 / YouTube 授权; 第 6 节各项 | 每个 provider 至少一个账号授权成功; token 续期机制就位 (Pinterest: `refreshTokenWorkflow` 已注册; LinkedIn / YouTube: 上游等价机制 = 发帖时按需刷新, 无独立工作流) |
| 5 文档 | 第 10 节文档清单全部更新; DEPLOYMENT.md 改写为 Contabo runbook | `doc-check` 无陈旧项 |

### 7.1 执行结果 (2026-11-03 至 2026-11-04)

逐项证据记录在 `~/STELLAR_OUTPUT/_tmp/stellarbyte-redeploy-2026-11/progress.md` (按阶段分节; 临时目录, 截图与演练输出同目录).

| 阶段 | 状态 | 要点与证据 |
|---|---|---|
| 0 | 完成 | tag `legacy/v2.7-fork` (e7f02d3b) 已推送; `upstream` remote |
| 1 | 完成 | `stellarbyte` 分支补丁 commit 见 `git log v2.25.3..stellarbyte`; `apply-brand --check` 34/34, 残留 0; 本机 `pnpm build` 通过 |
| 2 | 完成 | 本机 compose 4/4 healthy, Temporal SQL visibility 一次通过 (D5 无需退路); 常驻约 1.75G; 恢复演练通过. 偏差: 本机子网改 `STELLARBYTE_SUBNET` 可配 |
| 3 | 完成 | Contabo 上线, 端口扫描 / 出站 25 拦截 / Stalwart 健康 16/16 / 备份 + R2 回读 + 恢复演练 / Discord 存活告警均通过; 8.3 的 "24h 无 OOM" 已复核: 2026-11-07 运行约 4.6 天, oom_kill 0, 见第 9 节 |
| 4 | 部分完成 | 完成: 积压 112 条导出并删除; API key 曾轮换并入 Windmill secret (r6 删除旧组织后失效; 2026-11-07 新组织 StellarByte 的 key 已写回 Windmill (D22)); 7 个脚本核对 (修 2 个); redirect URI 核对 (LinkedIn / Google 已登记, Pinterest 待首次授权验证); r3 / r4 上线. Facebook Page 已授权; LinkedIn 个人号 `Harrison Ming` 2026-11-12 已授权; **待 Harrison**: Pinterest / YouTube 授权 (第 9 节) |
| 5 | 完成 | runbook [DEPLOYMENT.md](DEPLOYMENT.md) 改写, `config-readme.md` / README 更新, 第 10 节跨仓库文档同步 (各仓库本地 commit) |
| 跟进 C (主机) | 完成 | DOCKER-USER 规则重放幂等; 清理遗留镜像与匿名卷 (根盘 31% → 15%); Stalwart 冷备份上线 (本地 + 私有 R2 `stalwart-backups`, 停机约 8 秒) 并恢复演练 41 账号 / 16 域名一致 |
| 跟进 E (加固与演练) | 完成 | nginx 安全头 + 登录限速 (连续错误密码第 6 次起 429, 约 1 分钟恢复; listmonk-api / smtp-admin 与上线前快照一致); 两个备份 watchdog 告警演练 (ALERT + RECOVERY 到 #errors); `host-resource-check.timer` 上线并 self-test; 从 R2 下载的离机恢复演练 88 表一致; 外部安全检查见第 11 节. stalwart-health 前后 16/16 |
| 跟进 A (r5 等) | 完成 | r5 (commit 49d517da, tag `stellarbyte-v2.25.3-r5`): Stripe.js 改 `pure` 入口且无 key 不加载, 国旗图标自托管; `apply-brand --check` 34/34; 镜像 CI run 41733918707 成功; 上线前备份 success, app healthy, worker 在线; 登录 + launches + settings + 语言弹窗全程无 stripe / jsdelivr 请求 (仅余 cloudflareinsights). 上游监视 workflow + `UPSTREAM_BASE` (f13a4998), 默认分支已改, schedule 生效 (第 4 节). 上游 PR 补丁与草稿已备, 未提交 (第 9 节) |
| r6 (2026-11-04, D17-D23) | 完成 | commit 5ad33c16 / e61ef9ef / 9e4ed163, tag `stellarbyte-v2.25.3-r6`, 镜像 CI run 41865783123; `apply-brand --check` 32/32, 残留 0. 生产: 上线前 pg_dump (`/root/r6-predelete-20261104/`), app healthy, Google 授权链接 client_id 前缀 `344812424356`; 旧账号与组织已删 (88 表全 0; 旧 Media 行对应的 1 个 R2 对象留在 `stellar-postiz`); 注册通知端到端到 `#stellarbyte-signups` 已验证; 条款页第 16 节上线 (`host/StellarByte` 06ebd04). 回滚: `.env.pre-r6` + r5 镜像 (runbook 第 5 节). 细节见 progress.md r6 节 |
| r7 (2026-11-12, D25) | 完成 (入口仍隐藏, 等审批) | commit 4edfccf1, tag `stellarbyte-v2.25.3-r7`, 镜像 CI run 43192067794 与 Build run 43192067222 均 success. 只改 `linkedin.page.provider.ts` + env 模板. 生产: 上线前备份 success, stalwart-health 前后 16/16; 两边 `.env` 改 `STELLARBYTE_TAG` 与 `HIDDEN_PROVIDERS` (加 `gmb`), 副本 `.env.pre-r7` (服务器) / `.env.production.pre-r7` (本机); app 约 2 分钟 healthy, worker workflow + activity 在线, 登录页 200. 影响面: 生产库无 linkedin-page / gmb / youtube integration (上线前查询: facebook 3, linkedin 1). GCP: stellar-dev 的 `StellarByte SaaS App` client 加了回调 `/integrations/social/gmb` (修截图里的 `redirect_uri_mismatch`, 新 client 就位后可删); 新项目 `stellarbyte-gbp` 已建并启用 Account Management / Business Information / Performance 三个 API (`mybusiness.googleapis.com` v4 是私有 API, 获批前无法启用). 回滚: `.env.pre-r7` + r6 镜像 |
| Facebook Page (2026-11-07, D24) | 完成 (测试帖 PUBLISHED 后已删, 第 9 节) | Meta 测试账号: Stalwart 新建 `sb-test` (PID 71), app 注册 `test@stellarbyte.ca` 经 IMAP 取激活链接激活并 API 登录 200; 先前未激活的 iCloud 测试账号与组织单事务删除. 凭据: App Secret 经 Graph API 换 app token 校验通过, 5 个权限 live; 主源与服务器 `.env` 逐 key 哈希一致 (服务器副本 `.env.pre-fb`); 上线前备份 set `20261107T195541Z`; `up -d --no-deps app` 约 95s healthy, 容器内变量已生效, Temporal worker 已连接, stalwart-health 前后 16/16, `oom_kill` 0. Add Channel → Facebook Page 跳转 Facebook 登录页无报错, client_id / redirect_uri / scope 正确. 首个授权: Page `BlessAura` (760948253779464) 连在测试组织 "Meta App Review" (2026-11-07 已迁到组织 StellarByte); 随后 Page `Totvan` (773088619228647) 同组织授权, 同样校验通过; `inBetweenSteps=false`; `debug_token`: type PAGE, is_valid, 长期 token (`expires_at` 0), `data_access_expires_at` 2027-02-05 (90 天, 期间用户无活动则需重连), 含 `pages_manage_posts`. 2026-11-07 经公开 API 向 BlessAura 发测试帖 PUBLISHED 后已删除 (第 9 节) |

## 8. 验收标准

### 8.1 代码

- 主线 `stellarbyte` = `v2.25.3` + 补丁 commit, `git log v2.25.3..stellarbyte` 只有 StellarByte 补丁.
- 品牌: 登录、注册、侧栏、页面标题、邮件、OAuth 授权页、onboarding 无 Postiz 字样 (白名单除外); 主色蓝; 无 Postiz 社会证明; app 前端无 "Powered by" 署名与源码链接 (D17), `https://stellarbyte.ca/terms/` 有 AGPL 源码声明 (D18).
- CI 构建成功并推送 `ghcr.io/harrison-ming/stellarbyte-app:<tag>` (amd64, 公开包). 已推送的 tag 不改写, 修订用 `-rN`: 首个 tag `stellarbyte-v2.25.3` 推旧私有包 `stellarbyte` 无权限失败; `-r2` 首个可用镜像 (改推公开包 `stellarbyte-app`); `-r3` 隐藏 Google 登录按钮; `-r4` Pinterest refresh token 修复; `-r5` 无计费不加载 Stripe.js + 国旗图标自托管; `-r6` 去掉 app 内署名/源码链接, 独立 Google 登录 client + 已验证邮箱关联, 开放注册 (D17-D23); `-r7` LinkedIn 公司页改用 CMA 权限与独立 app 变量 (当前线上, D25).

### 8.2 本机冒烟

- 全部容器 healthy; `prisma db push` 完成; Temporal 工作流 worker 已连接.
- 注册首个管理员 (浏览器自助注册), 登录, 设超管后创建组织 API key.
- 上传媒体到 R2 并能在页面显示; 创建一条定时帖到 "预览/草稿" 路径 (不发真实平台).
- 浏览器网络面板无 postiz 域名外发.

### 8.3 Contabo 上线

- `https://app.stellarbyte.ca` 正常; 第 5.1 节端口扫描通过; 出站 25 被拦截 (容器内 `nc -zv gmail-smtp-in.l.google.com 25` 失败); listmonk-api / smtp-admin / 邮件收发不受影响 (Stalwart 健康探测脚本通过).
- 备份已跑一次并完成恢复演练; 外部存活告警已验证可触发.
- 资源: 上线 24h 内无 OOM, Stalwart 内存与延迟无异常.

### 8.4 商业级底线

HTTPS 全站; 注册开放但本地注册须邮件激活, `/api/auth/*` 限速, 新注册 Discord 通知 (D21 / D23); 所有密钥新生成且不入 git; 每日备份 + 恢复演练; 告警; 资源限额; runbook 含部署、升级、回滚、恢复; 线上代码与公开仓库一致且源码地址在条款页公示 (AGPL, D18).

## 9. 保留给用户的动作 (截至 2026-11-12 仍待办)

只剩必须由 Harrison 本人登录 / 选择 / 付费才能推进的项:

- **Pinterest 授权 (23 个可授权账号, 清单 `STELLAR INFRA/platforms/pinterest/authorization-checklist.md`)**: 账号都在 HubStudio 环境里. 2026-11-07 复查: 本机 HubStudio 客户端在运行, 但本地 API 返回 code 26 "团队当前套餐为免费版, 无法使用 API"; ALIEN 连接机仍不可达. 需升级 HubStudio 套餐, 或 Harrison 在客户端里逐个打开环境按 runbook 12.2 节授权 (授权前核对环境内登录身份). 首个号授权后再验第 11 节的 Pinterest 刷新与回调两项.
- **LinkedIn 公司页 (D25)**: ① ~~新建 app~~ 已完成 (2026-11-12): app `StellarByte Pages` (app id 264232906, Client ID `86tgm8gikrc1qp`), 关联公司页 StellarByte Technology Ltd., 回调 `https://app.stellarbyte.ca/integrations/social/linkedin-page` 已登记, client id/secret 已写入两边 `.env` 的 `LINKEDIN_PAGE_CLIENT_*` (副本 `.env.pre-lipage` / `.env.production.pre-lipage`), app 重建后 healthy; BW 备份待用户确认写入; ② 公司页验证 (Page Admin 打开验证链接后 "Yes, Confirm!", 需本人点) 与 Community Management API Development tier 申请 (只加这一个产品, 申请表法律名称写 STELLAR BYTE TECHNOLOGY CORP., 需本人提交); ③ 获批后去掉 `HIDDEN_PROVIDERS` 里的 `linkedin-page`, `up -d --no-deps app`, 授权公司页并发测试帖; ④ 对外给其他用户用需再申请 Standard tier (需录屏演示).
- **Google Business Profile (D25)**: ① ~~同意屏幕~~ 已完成 (2026-11-12, Harrison 本人勾选条款后 Create; External, Testing); ② ~~Web client~~ 已完成 (2026-11-12): client `StellarByte SaaS GMB` (`56650864023-igvq9…`), 回调 `https://app.stellarbyte.ca/integrations/social/gmb`, Data Access 登记 `userinfo.email` / `userinfo.profile` / `business.manage` (控制台把 `business.manage` 列为非敏感), 已写入两边 `.env` 的 `GOOGLE_GMB_CLIENT_*` (副本 `.env.pre-gmb` / `.env.production.pre-gmb`), app 重建后 healthy, 容器内 client 前缀核对一致; BW 备份待用户确认写入; ③ 2027-01-10 起用项目编号 56650864023 提交 Business Profile API 访问申请; ④ 获批后启用 `mybusiness.googleapis.com`, 同意屏幕 Publish 为 In production (现为 Testing, 只有测试用户能授权), 去掉 `HIDDEN_PROVIDERS` 里的 `gmb`; 之后可删 stellar-dev `StellarByte SaaS App` client 上的 `/gmb` 回调.
- **YouTube**: 选定要绑定的频道后授权.
- 授权后: 回填 Windmill 变量 `publish_accounts` 与 Supabase `pinterest_publisher.accounts` 的 integration_id, 更新 `STELLAR CONFIG/StellarByteSaaS/accounts.md` 与全局账号表 (Pinterest 的 integrationId 写 `platforms/pinterest/account-status.json`, 其他平台写 `platforms/_shared/accounts.json` 的 `bindings`, 再 `acctctl lint`, 见 `docs/DEPLOYMENT.md` 12.2); 再决定是否开启 5 个 disabled 的 Windmill 发布 schedule (会对真实账号发帖).
- **BlessAura Page token 需作废重授**: 2026-11-07 排查 R2 引用时, 一条 grep 把 BlessAura Page 的 access token 打印进了 agent 对话 (未写入文件). 作废方法: Facebook → 设置 → 商业集成 (Business Integrations) 移除 StellarPage 后重新在 app 里连接 BlessAura, 或改 Facebook 密码 (会让全部 Page token 失效, 之后两个 Page 都要重连).
- 已知低风险第三方请求: 只剩 static.cloudflareinsights.com (Cloudflare zone RUM 自动注入, 关闭在 Cloudflare 面板 Web Analytics, **影响同 zone 其他站点**); 是否关闭由 Harrison 定.
- 上游 PR (Pinterest refresh token, b91ac78a): 草稿在 `~/STELLAR_OUTPUT/_tmp/stellarbyte-redeploy-2026-11/upstream-pr/`. 上游 `CONTRIBUTING.md` 不接受主要由 AI 生成的 PR 且需签 CLA, agent 不代提; 走 issue 或由 Harrison 改写后提交.
- Meta 数据访问续期为年度要求, 到期前在 Meta 后台 Required actions 处理.

2026-11-12 已完成: LinkedIn 个人号授权 (`Harrison Ming`, 生产库 linkedin integration 1 条); 授权后回填全局账号表按 runbook 12.2 进行.

2026-11-07 已完成 (原第 9 节项):
- Harrison (`harrison.vancouver@gmail.com`, Google 登录) 设 `isSuperAdmin=true`; 组织 StellarByte (`f27d1cfd-…`) 的 API key 写回 Windmill `u/harrisonvancouver/stellarbyte_api_key`, 公开 API 200. 组织 key 在注册时由服务端随机生成且未暴露过, 未再轮换.
- Google 登录: GCP `stellarbyte-scheduler-login` 同意屏幕原为 **Testing** (只有测试用户能用 Google 登录), 补齐 Branding 的首页 / 隐私 / 条款链接后 Publish 为 In production (只用非敏感 scope, 无需 Google 审核); 用 Harrison 的 Google 账号实测登录进已有账号, 未新建用户.
- Facebook Page: BlessAura / Totvan 从 "Meta App Review" 组织迁到 StellarByte 组织 (迁前备份 20261107T230019Z); 经公开 API 向 BlessAura 发测试帖 PUBLISHED, Graph API 确认后已删除. `HIDDEN_PROVIDERS` 加 `instagram,instagram-standalone`, app 重建约 70s healthy, 添加频道列表已无 Instagram.
- Bitwarden: (a)-(e) 待写条目与 `test@stellarbyte.ca` 条目全部写入 (UUID 见 `STELLAR CONFIG/StellarByteSaaS/credentials.md`), 两个邮箱用 BW 中密码 IMAP 回读登录通过; `~/Desktop/Facebookapp` 明文已删.
- GitHub: 默认分支改为 `stellarbyte`; `Close inactive issues` 手动禁用 (改默认分支后它因 stellarbyte 分支上有同名文件被重新激活过); "Resolve staging conflicts" 只存在于上游仓库, fork 里没有; `Upstream release watch` 手动跑一次 success, 每周 schedule 生效.
- 上线复核: 截至 2026-11-07 运行约 4.6 天, `/proc/vmstat oom_kill` 0, 全部容器 OOMKilled=false 且 0 次重启, 可用内存约 5.2G, swap 基本未用, `stalwart-health.sh` 16/16.

## 10. 需同步更新的文档

`docs/config-readme.md`; `docs/DEPLOYMENT.md` (改写); `STELLAR INFRA/machines/contabo/StellarPostiz/README.md`; `machines/contabo/vps-161.97.184.77.md` (Docker 版本、证书为自签名、站点列表、遗留物、定时任务与备份); `DEPLOY/cloudflare/usage-by-project.md` 与 `resource.md/json`; `domains/stellarbyte.ca.md`; `STELLAR CONFIG/StellarByteSaaS/accounts.md`; `STELLAR CONFIG/HarrisonMing/credentials.md`; `platforms/pinterest/` (README、account-status、automation、token-refresh-issue); `STELLAR CONFIG/Windmill/pinterest/README.md`; `STELLAR CONFIG/Windmill/agent-flow/multi-channel-design.md`; `host/Windmill/CLAUDE.md`; `machines/MacMini/pinterest-publisher/README.md` (整篇过期).

## 11. 已知风险与未决

- 新应用与邮件服务同机: 资源与网络已隔离, 但整机级故障 (入侵、供应商停机) 会同时影响两者. 彻底隔离需换机器.
- Meta: StellarPage 2026-10-17 因未完成数据访问续期被限制, 2026-11-07 续期与审核通过 (D24). 年度续期漏做会再次被限制, 届时 Facebook 发帖全部失败. Instagram 未提审, 入口已用 `HIDDEN_PROVIDERS` 隐藏 (2026-11-07); 提审通过后从该变量去掉 `instagram,instagram-standalone`.
- LinkedIn 公司页 / GMB (D25): 代码已上线但入口隐藏, `/v2/me` 身份获取与公司页发帖要等 CMA 获批后才能实测; GMB 发帖 (v4 localPosts) 依赖 Business Profile API 获批.
- r4 的 Pinterest 刷新修复依据官方文档与代码审读, 还没有真实 integration 可验证: 首个 Pinterest 账号授权后, 确认 Temporal 中有 `refresh_<integrationId>` 工作流, 并在约 30 天 access token 到期时确认刷新成功且 DB 中 refresh token 已更换.
- Pinterest 回调 URI 是否已在 Pinterest 后台登记, 只能在首次授权时验证.
- 上游不接受 AI 生成的 PR: L1' 补丁回馈上游只能走 issue 或人工重写, 因此 L1' 补丁可能长期自维护.
- 审计证据与试做补丁 (临时): `/private/tmp/claude-501/-Users-ming-Documents-host-StellarByteSaaS/dd90af70-e826-47ec-ad4b-68bfc08b149e/scratchpad/branding/` (会话级临时目录, 可能已被清理).
- 外部安全检查 (2026-11-04, 从本机 Mac):
  - 端口: IPv4 / IPv6 只有 22 / 587 / 993 可连; 80 / 443 只对 Cloudflare 段开放 (Mac 直连不通, 比验收要求更严); 25 从 Mac 测不到 (本机网络封出站 25, 服务器侧 ufw 放行, 11-03 已验证); 3000 / 4007 / 5432 / 6379 / 7233 / 8080 / 9000 等均不通. 主机对外监听只有 22 / 25 / 80 / 443 / 587 / 993.
  - TLS: 边缘 TLS 1.3 (Google Trust Services 证书, Cloudflare 自动续期), TLS 1.0 / 1.1 被拒; 响应头见 5.3.
  - `pnpm audit --prod` (分支 `stellarbyte`, 3318 个依赖): critical 1 / high 11 (另 moderate 46, low 14), 全部是上游依赖, 不升级: critical `@sentry/nextjs` 10.56.0 (GHSA-mchm-gjx6-7h55, 需开启 Sentry tunnel route 才可利用; `next.config.js` 未配 `tunnelRoute`, 生产 `NEXT_PUBLIC_SENTRY_DSN` 为空, 不受影响; 修复要把 4 个 `@sentry/*` 从 10.56 升到 10.75+, 不算无行为变化的小补丁). high: `node-forge` 1.4.0 ×7 (经 `google-p12-pem`, 只在用 .p12 服务账号密钥时走到), `zod` 3.x (GHSA-mrhx-c7xc-m3w5, 大集合校验耗内存), `axios` 带的 `follow-redirects` 1.16.1, `query-string` 带的 `decode-uri-component` 0.2.2, `graphql-scalars` 1.25.0 (经 `@copilotkit/runtime` / `type-graphql`). 跟上游版本走 (第 4 节), 每次跟进时复跑 `pnpm audit --prod --audit-level high`.
