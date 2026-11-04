# StellarByteSaaS

> 对应项目: `/Users/ming/Documents/host/StellarByteSaaS/`
> 最后更新: 2026-11-04

## 概述

StellarByte 是社交媒体排程发布平台, 基于开源 Postiz (AGPL-3.0) 二次开发: 分支 `stellarbyte` = 上游 `v2.25.3` + StellarByte 品牌与少量补丁 (见 [redeploy-spec.md](redeploy-spec.md) 第 3 节). 2026-11-03 重新上线.

- **访问地址**: https://app.stellarbyte.ca (注册关闭, 仅管理员)
- **部署位置**: Contabo VPS 161.97.184.77, `/opt/stellarpostiz/`
- **运维 runbook**: [DEPLOYMENT.md](DEPLOYMENT.md) (部署 / 升级 / 回滚 / 备份恢复 / 排障)
- **密钥**: `STELLAR CONFIG/StellarByteSaaS/` (`.env.production` 主源, `credentials.md` 索引, `accounts.md` 组织与账号映射)

## 架构速览

```
Cloudflare (proxied, SSL Full) -> Contabo nginx (安全头 + /api/auth 登录限速) -> 127.0.0.1:4007
└── compose 项目 stellarbyte
    ├── stellarbyte-app       ghcr.io/harrison-ming/stellarbyte-app:<tag> (frontend + backend + Temporal worker)
    ├── stellarbyte-postgres  本机 Postgres 17 (库 stellarbyte / temporal / temporal_visibility)
    ├── stellarbyte-redis     Redis 7
    └── stellarbyte-temporal  Temporal 1.28 (SQL visibility)

媒体: R2 stellar-postiz -> https://media.stellarbyte.ca
备份: 每日 pg_dump -> 本地 + R2 stellarbyte-backups (本地与离机恢复演练均通过)
告警: Windmill 外部存活 + 备份 watchdog + 主机资源 -> Discord #errors
发信: app-noreply@stellarbyte.ca (Stalwart, mx.stellarbyte.ca:587)
```

不再使用 Supabase (旧 `postiz` schema 已于 2026-09-08 删除), 也不再用 `cdn.stellarbyte.ca`.

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

截至 2026-11-03 新组织 integration 数为 0, 旧 integration_id 全部作废; Pinterest (约 24 个) / LinkedIn 个人 / YouTube 待重新授权 (流程见 runbook 第 12.2 节). Windmill 相关发布 schedule 保持 disabled.

## 相关文档

- 主机文档: `STELLAR INFRA/machines/contabo/StellarPostiz/README.md`, `STELLAR INFRA/machines/contabo/vps-161.97.184.77.md`
- Pinterest 平台运营: `STELLAR INFRA/platforms/pinterest/`
- Windmill 发布工作流: `STELLAR CONFIG/Windmill/pinterest/`
