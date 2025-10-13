# StellarByte

<div align="center">

![StellarByte Logo](apps/frontend/public/logo.svg)

**Social Media Management Platform**

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%203.0-green.svg)](https://opensource.org/licenses/AGPL-3.0)
[![Based on Postiz](https://img.shields.io/badge/Based%20on-Postiz-blue)](https://github.com/gitroomhq/postiz-app)

*Explore the social cosmos; there is no limit to your reach.*

[Website](https://stellarbyte.ca) | [Documentation](#documentation) | [Changelog](CHANGELOG.md)

</div>

---

## About

StellarByte is a social media management platform based on [Postiz](https://github.com/gitroomhq/postiz-app). We've enhanced it with custom branding, improved UI/UX, and production-ready deployment configuration.

### Key Features

- **Multi-Platform Support**: Manage Twitter, LinkedIn, Facebook, Instagram, YouTube, TikTok, Reddit, Pinterest, Threads, Discord, and Slack
- **Scheduling**: Schedule posts across multiple platforms
- **Analytics**: Track your social media performance
- **Team Collaboration**: Work with your team members
- **AI Integration**: OpenAI-powered content suggestions
- **Cloudflare R2 Storage**: Reliable cloud storage for media files

### What's Different from Postiz?

- ✨ Custom green branding (#01d408)
- 🎨 Enhanced UI with particles animation
- 🚀 Production-ready Docker deployment
- ⚙️ GitHub Actions CI/CD pipeline
- 📚 Comprehensive deployment documentation

---

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Node.js 20+ (for local development)
- PostgreSQL 16+
- Redis 7+

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/harrison-ming/StellarByteSaaS.git
   cd StellarByteSaaS
   ```

2. **Configure environment variables**
   ```bash
   cp .env.example .env
   # Edit .env and fill in your configuration
   ```

3. **Build and start services**
   ```bash
   # Build Docker image
   docker build -f Dockerfile.dev -t stellarbyte:latest .
   
   # Start services
   docker compose up -d
   ```

4. **Access the application**
   - Frontend: http://localhost:4100
   - Backend API: http://localhost:4000

---

## Environment Configuration

See `.env.example` for a complete list of configuration options.

### Required Configuration

```bash
# Database
POSTGRES_PASSWORD=your_secure_password
DATABASE_URL=postgresql://stellarbyte:password@stellarbyte-postgres:5432/stellarbyte

# Redis
REDIS_URL=redis://stellarbyte-redis:6379

# Security
JWT_SECRET=your_jwt_secret_minimum_32_characters

# Storage (Production)
STORAGE_PROVIDER=cloudflare
CLOUDFLARE_ACCOUNT_ID=your_account_id
CLOUDFLARE_ACCESS_KEY=your_access_key
CLOUDFLARE_SECRET_ACCESS_KEY=your_secret_key
CLOUDFLARE_BUCKETNAME=your_bucket_name
```

### Optional: Social Platform APIs

To enable social media integrations, obtain API keys from respective platforms and add them to your `.env` file.

---

## Deployment

### Production Deployment (107 Server)

1. **Setup SSH access** from GitHub Actions
2. **Configure GitHub Secrets**:
   - `SSH_HOST`: 192.168.1.107
   - `SSH_USER`: ming
   - `SSH_PRIVATE_KEY`: Your SSH private key

3. **Deploy**:
   ```bash
   git push origin main
   # GitHub Actions will automatically deploy
   ```

### Manual Deployment

```bash
# On the 107 server
cd /Users/ming/Documents/host/StellarByte
bash deploy-to-107.sh
```

### Cloudflare Tunnel Setup

Add to your `~/.cloudflared/config.yml`:

```yaml
ingress:
  - hostname: app.stellarbyte.ca
    service: http://localhost:4100
  - service: http_status:404
```

Then create DNS record:
```bash
cloudflared tunnel route dns <tunnel-name> app.stellarbyte.ca
```

---

## Development

### Local Development

```bash
# Install dependencies
pnpm install

# Start development server
pnpm dev

# Build for production
pnpm build
```

### Project Structure

```
StellarByte/
├── apps/
│   ├── frontend/       # Next.js frontend
│   ├── backend/        # NestJS backend
│   ├── workers/        # Background workers
│   └── cron/           # Scheduled tasks
├── libraries/          # Shared libraries
├── docker-compose.yml  # Production configuration
├── Dockerfile.dev      # Docker image definition
└── deploy-to-107.sh    # Deployment script
```

---

## Documentation

- [Changelog](CHANGELOG.md) - Version history and changes
- [License](LICENSE) - AGPL-3.0 license details
- [Deployment Guide](#deployment) - Production deployment instructions

---

## Technology Stack

- **Frontend**: Next.js 14.2.32, React 18, TailwindCSS
- **Backend**: NestJS, Node.js 20
- **Database**: PostgreSQL 16, Redis 7
- **Storage**: Cloudflare R2
- **Deployment**: Docker, GitHub Actions
- **Infrastructure**: Cloudflare Tunnel

---

## Contributing

We welcome contributions! Please feel free to submit issues and pull requests.

### Development Guidelines

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0).

**Key Points**:
- ✅ You can use, modify, and distribute this software
- ✅ If you provide this as a service, you must provide the source code to users
- ✅ Modifications must also be licensed under AGPL-3.0

See [LICENSE](LICENSE) for full details.

### Attribution

StellarByte is based on [Postiz](https://github.com/gitroomhq/postiz-app) by Nevo David.

**Copyright**:
- Original work: Copyright © 2024 Postiz
- Modifications: Copyright © 2025 StellarByte Team

---

## Acknowledgments

- **Postiz** - The original social media management platform
- **Next.js** - The React framework we build upon
- **NestJS** - The backend framework
- **Cloudflare** - For R2 storage and tunnel services

---

## Support

- 📧 Email: support@stellarbyte.ca
- 🐛 Issues: [GitHub Issues](https://github.com/harrison-ming/StellarByteSaaS/issues)
- 🌐 Website: [stellarbyte.ca](https://stellarbyte.ca)

---

<div align="center">

**Made with ❤️ by the StellarByte Team**

*Your co-pilot in the social frontier*

</div>
