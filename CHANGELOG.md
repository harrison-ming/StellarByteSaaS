# Changelog

All notable changes to StellarByte will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-13

### Added - StellarByte Branding
- Green color scheme (#01d408) throughout the application
- New StellarByte logo and branding assets
- Particles animation (triangle pattern) on authentication page
- Brand tagline text on authentication page: "Explore the social cosmos; there is no limit to your reach. StellarByte: Your co-pilot in the social frontier."
- "Return to Homepage" link on auth pages

### Changed - UI/UX Improvements
- Rebranded from Postiz to StellarByte
- Updated all UI colors from purple to green theme
- Modified authentication page layout with particles background
- Enhanced login/registration page visual design

### Added - Infrastructure
- Cloudflare R2 storage integration for avatars and uploads
- Google OAuth integration for user authentication
- GitHub Actions deployment workflow for automated deployments
- Docker compose production configuration with named volumes
- Deployment script with health checks (deploy-to-107.sh)
- Comprehensive environment variable template (.env.example)

### Added - Documentation
- Production deployment guide
- Environment configuration template
- Cloudflare Tunnel setup instructions
- Backup and restore procedures
- Directory structure documentation

### Technical Details
- **Base**: Fork of Postiz v1.0.0
- **License**: AGPL-3.0 (maintained from original)
- **Frontend**: Next.js 14.2.32
- **Backend**: NestJS
- **Database**: PostgreSQL 16 + Redis 7
- **Storage**: Cloudflare R2
- **Deployment**: Docker + GitHub Actions

---

## About This Project

StellarByte is a social media management platform based on [Postiz](https://github.com/gitroomhq/postiz-app). We've enhanced it with:

- Custom green branding
- Improved UI/UX
- Production-ready deployment configuration
- Automated CI/CD pipeline

### Compliance

This project complies with AGPL-3.0 license requirements:
- Source code is publicly available at: https://github.com/harrison-ming/StellarByteSaaS
- All modifications are documented in this changelog
- Original Postiz copyright is preserved in LICENSE file

---

[1.0.0]: https://github.com/harrison-ming/StellarByteSaaS/releases/tag/v1.0.0
