# StellarByteSaaS

> 对应项目: `/Users/ming/Documents/host/StellarByteSaaS/`
> 最后更新: 2026-03-07

## 概述

StellarByte 是一个社交媒体管理平台, 基于开源项目 Postiz fork, 支持多平台内容定时发布.

- **访问地址**: https://app.stellarbyte.ca
- **部署位置**: Contabo VPS (161.97.184.77)
- **部署配置**: `/Users/ming/Documents/STELLAR CONFIG/machines/contabo/StellarPostiz/`

## 目录内容

- `accounts.md` — 所有已接入的社交媒体账号映射表 (integration_id, board_id 等)

## 架构速览

```
Contabo VPS (161.97.184.77)
├── stellarpostiz-app (Docker)
│   ├── Frontend (Next.js): 4100
│   └── Backend (NestJS): 4000
└── stellarpostiz-redis (Redis): 6379

数据库: Supabase (apuferwshcgskvltfvnl), schema: postiz
媒体存储: Cloudflare R2 → cdn.stellarbyte.ca
```

## Public API

- **Base URL**: https://app.stellarbyte.ca/api/public/v1
- **认证**: `Authorization: <org_api_key>` header
- **限制**: 30 请求/小时
- **Organization**: Company (faa1c842-d302-4606-9e06-76b30e69acf7)

### 主要端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/integrations` | GET | 列出所有已连接账号 |
| `/posts` | POST | 创建定时发布 |
| `/posts` | GET | 查询发布记录 |
| `/upload` | POST | 上传媒体文件 |

## 发布 Pinterest 内容 (示例)

```bash
curl -X POST \
  -H "Authorization: <org_api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "schedule",
    "date": "2026-03-08T02:00:00.000Z",
    "posts": [{
      "integration": {"id": "<integration_id>"},
      "value": [{
        "content": "Pin 描述文字",
        "image": [{"id": "img-id", "path": "https://cdn.stellarbyte.ca/xxx.jpg"}]
      }],
      "settings": {
        "__type": "pinterest",
        "board": "<board_id>",
        "title": "Pin 标题",
        "link": "https://shopmomodom.com"
      }
    }]
  }' \
  https://app.stellarbyte.ca/api/public/v1/posts
```

## 相关文档

- 部署配置: `/STELLAR CONFIG/machines/contabo/StellarPostiz/README.md`
- Pinterest 发布策略: `/STELLAR CONFIG/STELLARBYTE/pinterest-publisher/outbound-analysis.md`
- Windmill 发布工作流: `/STELLAR CONFIG/Windmill/pinterest/`
