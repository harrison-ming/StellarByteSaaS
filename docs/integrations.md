---
owner: Harrison
review_by: 2027-02-17
doc_type: spec
status: active
supersedes: STELLAR CONFIG/StellarByteSaaS/accounts.md
---

# StellarByte 频道接入 (integration 与发布映射)

> 本文不含任何密钥 (凭据索引在 `STELLAR CONFIG/StellarByteSaaS/credentials.md`).
> 授权流程与 token 长期可用规则: [DEPLOYMENT.md](DEPLOYMENT.md) 第 12 节.

## 1. 事实源

- **integration id 的唯一事实源是 SaaS 库** (Contabo 本机 Postgres 容器 `stellarbyte-postgres`, 库 `stellarbyte`, 表 `"Integration"`; 旧 Supabase 时期的 integration id 全部失效).
- 全局账号表 `STELLAR INFRA/platforms/_shared/accounts.json` 的 `bindings` 是唯一允许的镜像 (带 `asOf`): 哪个账号接入了哪个 integration, 一律 `acctctl locate <账号 key>` 查, 本文不再抄 id. Pinterest 账号的 integration id 写在 `platforms/pinterest/account-status.json` (Pinterest 台账).
- 在 UI 添加 / 重连频道后, 回填上述镜像; Windmill `publish_accounts` 与 Supabase `pinterest_publisher.accounts` 里的 id 是运行时副本, 发布前以 SaaS 库为准.

## 2. 组织与用户

| 项 | 值 |
|---|---|
| 组织 | StellarByte, ID `f27d1cfd-cc6b-430d-bf67-aef513364fea` |
| 公开 API key | 主源 BW `StellarByteSaaS - Org API Key (StellarByte)`, 运行时副本 Windmill secret `u/harrisonvancouver/stellarbyte_api_key`; 轮换见 [DEPLOYMENT.md](DEPLOYMENT.md) 第 1 节 |
| 超管 | `harrison.vancouver@gmail.com` (GOOGLE 登录, 账号 key `personal-google`, 2026-11-07 设 isSuperAdmin) |
| 授权操作员 | `app-ops@stellarbyte.ca` (LOCAL, 组织 StellarByte 角色 USER, 2026-11-19 建, spec D26; 建号步骤与风险见 [DEPLOYMENT.md](DEPLOYMENT.md) 12.1) — SaaS 用户本身不进账号表 (收信邮箱作为 email 账号登记); 凭据映射见 `STELLAR CONFIG/StellarByteSaaS/credentials.md` 映射表 app-ops 行 |
| Meta App Review 测试 | `test@stellarbyte.ca` (组织 "Meta App Review", 非超管; 凭据见 credentials.md) |

## 3. 已接入与待接入 (2026-11-22)

- 已接入 (组织 StellarByte): Facebook Page `blessaura-facebook`, `totvan-facebook` (2026-11-07); LinkedIn 个人 `personal-linkedin` (2026-11-12; 没有 refresh token, 2027-01-11 前须手动 Reconnect, 见 DEPLOYMENT.md 12.3); LinkedIn 公司页 `stellarbyte-linkedin` (StellarByte Technology Ltd., 2026-11-19); YouTube `easternblessing-youtube-2` (神機君, 2026-11-19); Threads `accessoryocean-threads` (@accessory.ocean, 2026-11-20, Threads Tester; 测试组织 "Meta App Review" 另接一份供 Meta 审核); TikTok for Business `matrix-tiktok` (FaithsHorizon, 2026-11-21, 测试用, 见 DEPLOYMENT.md 12.2); Pinterest `easternblessing-pinterest` (EasternBlessing, 2026-11-22, 刷新工作流已在跑; 不在第 4 节映射内).
- 待接入: Threads 其他账号 (App Review 2026-11-20 已提交, 过审前只能授权 Threads Testers); TikTok for Business 其他账号 (Saylo 两个新号待注册养号后授权, 见 DEPLOYMENT.md 12.2; 旧 Content Posting 入口 `tiktok` 已隐藏); Pinterest 第 4 节映射内的账号 (全部待重新授权); Google Business Profile 与 Instagram (含 instagram-standalone) 入口隐藏 (`HIDDEN_PROVIDERS`; GMB 的 Business Profile API 申请 2027-01-10 起才能提交, spec D25).
- 平台审核中: Threads App Review (见上). YouTube 的 Google 验证 2026-11-21 已通过 (DEPLOYMENT.md 12.2).
- 第 4 节映射内的账号授权前, 对应 Pinterest / agent_flow 发布 schedule 保持 disabled.

## 4. Pinterest 发布映射

publisher slug 与主板 board 映射以本节为主源; `platforms/pinterest/authorization-checklist.md` 回填表, `STELLAR CONFIG/Windmill/pinterest/README.md` 与 agent-flow `multi-channel-design.md` 里的 board ID 是副本, 改动时同步或改为指向本节:

| Windmill / publisher slug | 账号 key | 主板 Board ID | 关联站点 |
|---|---|---|---|
| `bible-grace` | `matrix-pinterest` | `1095500746798046659` (Scripture) | bibleinspiredliving.com |
| `bible-ways` | `matrix-pinterest-8` | `909305049704572934` (Daily Grace for Tired Moms) | — |
| `pet-gripestwisty` | `matrix-pinterest-4` | `888546270172035776` | — |
| `momodom-momo` | `momodom-pinterest` | `1061020062151574776` (Momo French Bulldog) | shopmomodom.com |
| `pinterest-bible` (agent-flow) | `matrix-pinterest` | `1095500746798046659` | — |
| `pinterest-pet` (agent-flow) | `matrix-pinterest-4` | `888546270172035776` | — |

momodompet 其他 board: Social `1061020062151306851` (PUBLIC), Products `1061020062151306738` (PROTECTED). 其余可授权 Pinterest 账号: `acctctl list --platform pinterest` 中 status=active 的 (2026-11-22 共 24 个, 其中 `easternblessing-pinterest` 已接入).

## 5. 维护

- 查 integration: 服务器上 `docker exec stellarbyte-postgres psql -U postgres -d stellarbyte -c 'select id, name, "providerIdentifier", "internalId", disabled from "Integration" where "deletedAt" is null;'`, 或公开 API `GET /api/public/v1/integrations` (key 取 Windmill secret).
- Board ID: StellarByte 频道的 boards 列表, 或 Pinterest API `GET /v5/boards`.
- 授权只走 StellarByte UI (旧 `platforms/pinterest` OAuth / token 刷新工具已废弃, spec D14); token 刷新机制, 需手动 Reconnect 的频道与告警见 [DEPLOYMENT.md](DEPLOYMENT.md) 12.3 与第 7 节.
