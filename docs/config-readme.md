---
owner: Harrison
review_by: 2027-02-01
doc_type: runbook
status: active
---

# StellarByteSaaS

> 对应项目: `/Users/ming/Documents/host/StellarByteSaaS/`
> 最后更新: 2026-11-22

## 概述

StellarByte 是社交媒体排程发布平台, 基于开源 Postiz (AGPL-3.0) 二次开发: 分支 `stellarbyte` = 上游 `v2.26.0` + StellarByte 品牌与少量补丁 (见 [redeploy-spec.md](redeploy-spec.md) 第 3 节). 2026-11-03 重新上线; 当前线上 tag 见 runbook 第 3 节.

- **访问地址**: https://app.stellarbyte.ca (2026-11-21 起关闭注册, 客户经团队邀请加入, spec D27; 受邀者可邮箱注册 (须激活) 或 Google 登录; 重新开放见 runbook 12.1)
- **开源声明**: AGPL-3.0 源码地址公示在 https://stellarbyte.ca/terms/ 第 16 节 (app 界面不放署名/源码链接, spec D17 / D18)
- **部署位置**: Contabo VPS 161.97.184.77, `/opt/stellarpostiz/`
- **运维 runbook**: [DEPLOYMENT.md](DEPLOYMENT.md) (部署 / 升级 / 回滚 / 备份恢复 / 排障)
- **密钥**: `STELLAR CONFIG/StellarByteSaaS/` (`.env.production` 为生产 `.env` 主源, `credentials.md` 为 BW 映射索引); 文件清单与服务器 `.env.pre-*` 副本用法见 runbook 第 2 / 5 节. 组织, 已接入频道与待接入清单见 [integrations.md](integrations.md); 授权流程见 runbook 12.2-12.3 节

## 架构速览

```
Cloudflare (proxied, app 主机 SSL Full (strict)) -> Contabo nginx (Let's Encrypt 证书, 安全头 + /api/auth 登录限速) -> 127.0.0.1:4007
└── compose 项目 stellarbyte
    ├── stellarbyte-app       ghcr.io/harrison-ming/stellarbyte-app:<tag> (frontend + backend + Temporal worker)
    │                     当前 tag 与回滚目标见 runbook 第 3 / 5 节; 镜像只由 CI 在推 stellarbyte-* tag 时构建 (D6)
    ├── stellarbyte-postgres  本机 Postgres 17 (库 stellarbyte / temporal / temporal_visibility)
    ├── stellarbyte-redis     Redis 7
    └── stellarbyte-temporal  Temporal 1.28 (SQL visibility)

媒体: R2 stellar-postiz -> https://media.stellarbyte.ca
备份: 每日 pg_dump -> 本地 (root only) + age 加密后上传 R2 stellarbyte-backups (演练记录见 runbook 第 6 节)
告警: Windmill 外部存活 + 备份 watchdog + 频道健康 + 主机资源 -> Discord #errors; 新注册 -> #stellarbyte-signups (宿主 timer)
登录: 邮箱 + Google (独立 client, GCP stellarbyte-scheduler-login, spec D19; 详见 runbook 12.1)
频道 client: 各平台 app / 环境变量 / 回调见 runbook 12.2, BW 指针见 credentials.md
发信: app-noreply@stellarbyte.ca (Stalwart, mx.stellarbyte.ca:587)
```

app 不再使用 Supabase (spec D4; 旧 `postiz` schema 已于 2026-09-08 删除), 也不再用 `cdn.stellarbyte.ca` (D15, 该域归 grysto). Windmill 的 Pinterest 发布链路仍用 Supabase `pinterest_publisher` schema (accounts / content_queue), 与 app 无关.

## Public API

- **Base URL**: `https://app.stellarbyte.ca/api/public/v1`
- **认证**: header `Authorization: <组织 API key>`; key 存放与轮换见 [DEPLOYMENT.md](DEPLOYMENT.md) 第 1 节
- **组织 id**: 见 [integrations.md](integrations.md) 第 2 节

常用端点 (完整列表见 `apps/backend/src/public-api/routes/v1/public.integrations.controller.ts`):

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

Pinterest 限制 (`pinterest.provider.ts` / `pinterest.dto.ts`): 至少 1 个媒体, 图片最多 5 张, 视频须恰好 2 个附件 (视频 + 封面); 描述 <= 500 字符, title <= 100; `board` 必填且为纯数字. 请求体 `date` / `shortLink` / `tags` 必填 (`tags` 可为空数组).

## 相关文档

- 主机文档: `STELLAR INFRA/machines/contabo/StellarPostiz/README.md`, `STELLAR INFRA/machines/contabo/vps-161.97.184.77.md`
- Pinterest 平台运营: `STELLAR INFRA/platforms/pinterest/`
- Windmill 发布工作流: 代码 `host/Windmill/pinterest/` (flows / scripts), 说明 `STELLAR CONFIG/Windmill/pinterest/README.md`
