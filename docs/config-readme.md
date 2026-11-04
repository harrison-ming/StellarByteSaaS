---
owner: Harrison
review_by: 2027-02-01
doc_type: readme
status: active
---

# StellarByteSaaS

> 对应项目: `/Users/ming/Documents/host/StellarByteSaaS/`
> 最后更新: 2026-11-04

## 概述

StellarByte 是社交媒体排程发布平台, 基于开源 Postiz (AGPL-3.0) 二次开发: 分支 `stellarbyte` = 上游 `v2.25.3` + StellarByte 品牌与少量补丁 (见 [redeploy-spec.md](redeploy-spec.md) 第 3 节). 2026-11-03 重新上线.

- **访问地址**: https://app.stellarbyte.ca (r6 起开放注册: 邮箱注册须激活, 也可 Google 登录; 快速关闭见 runbook 12.1)
- **开源声明**: AGPL-3.0 源码地址公示在 https://stellarbyte.ca/terms/ 第 16 节 (app 界面不放署名/源码链接, spec D17 / D18)
- **部署位置**: Contabo VPS 161.97.184.77, `/opt/stellarpostiz/`
- **运维 runbook**: [DEPLOYMENT.md](DEPLOYMENT.md) (部署 / 升级 / 回滚 / 备份恢复 / 排障)
- **密钥**: `STELLAR CONFIG/StellarByteSaaS/` (`.env.production` 主源, `credentials.md` 索引, `accounts.md` 组织与账号映射)

## 架构速览

```
Cloudflare (proxied, SSL Full) -> Contabo nginx (安全头 + /api/auth 登录限速) -> 127.0.0.1:4007
└── compose 项目 stellarbyte
    ├── stellarbyte-app       ghcr.io/harrison-ming/stellarbyte-app:<tag> (frontend + backend + Temporal worker)
    │                     当前 stellarbyte-v2.25.3-r6, 回滚 r5; 镜像只由 CI 在推 stellarbyte-* tag 时构建 (D6)
    ├── stellarbyte-postgres  本机 Postgres 17 (库 stellarbyte / temporal / temporal_visibility)
    ├── stellarbyte-redis     Redis 7
    └── stellarbyte-temporal  Temporal 1.28 (SQL visibility)

媒体: R2 stellar-postiz -> https://media.stellarbyte.ca
备份: 每日 pg_dump -> 本地 + R2 stellarbyte-backups (本地与离机恢复演练均通过)
告警: Windmill 外部存活 + 备份 watchdog + 主机资源 -> Discord #errors; 新注册 -> #stellarbyte-signups (宿主 timer)
登录: 邮箱 + Google (独立 client, GCP 项目 stellarbyte-scheduler-login; env GOOGLE_LOGIN_CLIENT_ID/SECRET + 开关 GOOGLE_LOGIN_ENABLED,
      不回退 YOUTUBE_*; client 文件 STELLAR CONFIG/StellarByteSaaS/google-oauth-client.json)
发信: app-noreply@stellarbyte.ca (Stalwart, mx.stellarbyte.ca:587)
```

app 不再使用 Supabase (spec D4; 旧 `postiz` schema 已于 2026-09-08 删除), 也不再用 `cdn.stellarbyte.ca` (D15, 该域归 grysto). Windmill 的 Pinterest 发布链路仍用 Supabase `pinterest_publisher` schema (accounts / content_queue), 与 app 无关.

## Public API

- **Base URL**: `https://app.stellarbyte.ca/api/public/v1`
- **认证**: header `Authorization: <组织 API key>`; key 存 Windmill secret 变量 `u/harrisonvancouver/stellarbyte_api_key`
- **组织 id**: 见 `STELLAR CONFIG/StellarByteSaaS/accounts.md`

| 端点 | 方法 | 说明 |
|------|------|------|
| `/integrations` | GET | 列出已连接账号 |
| `/posts` | POST | 创建发布 (返回 `[{postId, integration}]` 列表) |
| `/posts?startDate=&endDate=` | GET | 查询发布记录 (返回 `{posts}`) |
| `/upload` | POST | 上传媒体 |

### 发布 Pinterest 内容 (示例)

```bash
curl -X POST \
  -H "Authorization: <org_api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "schedule",
    "date": "2026-12-01T02:00:00.000Z",
    "shortLink": false,
    "tags": [],
    "posts": [{
      "integration": {"id": "<integration_id>"},
      "value": [{
        "content": "Pin 描述文字 (<= 500 字符)",
        "image": [{"id": "img-id", "path": "https://media.stellarbyte.ca/xxx.jpg"}]
      }],
      "settings": {
        "__type": "pinterest",
        "board": "<数字 board_id>",
        "title": "Pin 标题",
        "link": "https://shopmomodom.com"
      }
    }]
  }' \
  https://app.stellarbyte.ca/api/public/v1/posts
```

Pinterest 至少要一张图; `date` 必填.

## 账号现状

2026-11-04 (r6) 旧账号与组织已删除 (spec D22), 库内 0 用户 / 0 组织 / 0 integration; Windmill 变量 `stellarbyte_api_key` 中的旧 key 已失效. 待 Harrison 重新注册后: 设超管, 轮换 API key 写回 Windmill, 再授权 Pinterest (23 个可授权账号) / LinkedIn 个人 / YouTube (流程见 runbook 第 12 节). Windmill 相关发布 schedule 保持 disabled.

## 相关文档

- 主机文档: `STELLAR INFRA/machines/contabo/StellarPostiz/README.md`, `STELLAR INFRA/machines/contabo/vps-161.97.184.77.md`
- Pinterest 平台运营: `STELLAR INFRA/platforms/pinterest/`
- Windmill 发布工作流: `STELLAR CONFIG/Windmill/pinterest/`
