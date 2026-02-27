# Hear Here

A location-based audio storytelling app for iOS. Users record short audio stories tied to real-world locations. Recordings are moderated for content safety before becoming publicly discoverable by other users who are physically nearby.

## Features

- **Record** audio stories (up to 5 minutes) and pin them to real-world locations
- **Discover** nearby recordings on an interactive map with adjustable radius
- **Stream** audio playback from a CDN with a persistent mini-player
- **Moderate** content automatically via speech-to-text transcription and AI classification, with human review for borderline cases
- **Report** inappropriate content, with automatic escalation when thresholds are met
- **Manage** recordings and account settings, including account deletion

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS App | SwiftUI, Swift 6, MVVM + Coordinator, iOS 17+ |
| Backend | Node.js 20 (TypeScript), Azure Functions, Azure API Management |
| Database | PostgreSQL 16 + PostGIS on Azure Database for PostgreSQL Flexible Server |
| Audio Storage | Azure Blob Storage + Azure Front Door CDN |
| Moderation | Azure Durable Functions, Azure AI Speech, OpenAI Moderation API |
| Auth | Firebase Authentication (Apple, Google) |
| Infrastructure | Bicep (Azure-native IaC) |
| CI/CD | GitHub Actions |
| Admin UI | React (Vite) on Azure Static Web Apps |

## Getting Started

### Prerequisites

- Xcode 16+ with Swift 6
- Node.js 20+
- Docker (for local PostgreSQL)
- Azure CLI and Azure Functions Core Tools
- Firebase CLI

### Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd hear-here

# Backend
cd backend
npm install
docker run --name hearhere-db \
  -e POSTGRES_DB=hearhere \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=localdev \
  -p 5432:5432 \
  -d postgis/postgis:16-3.4
npm run migrate:up

# iOS
open ios/HearHere.xcodeproj

# Infrastructure
cd infra
npm install
az deployment group validate \
  --resource-group hearhere-dev-rg \
  --template-file main.bicep \
  --parameters environments/dev.bicepparam
```

See the [Developer Guide](docs/DEVELOPER_GUIDE.md) for detailed setup instructions.

## Repository Structure

```
hear-here/
├── docs/           # Design documents and guides
├── ios/            # iOS app (Xcode project)
├── backend/        # Azure Functions (TypeScript)
├── infra/          # Bicep infrastructure templates
├── admin/          # Human review admin UI (React)
└── scripts/        # Dev scripts, DB migrations
```

## Documentation

| Document | Description |
|----------|-------------|
| [Project Overview](docs/PROJECT_OVERVIEW.md) | Product description, features, MVP scope, roadmap |
| [Architecture](docs/ARCHITECTURE.md) | System architecture and technology decisions |
| [Database](docs/DATABASE.md) | Schema, data model, queries, and migration strategy |
| [Backend](docs/BACKEND.md) | API design, Azure Functions structure, moderation pipeline |
| [iOS App](docs/IOS_APP.md) | App architecture, UI design, navigation, accessibility |
| [Cloud Architecture](docs/CLOUD_ARCHITECTURE.md) | Azure infrastructure, CI/CD, monitoring, cost estimates |
| [API Documentation](docs/API_DOCUMENTATION.md) | Developer-friendly API reference with examples |
| [Developer Guide](docs/DEVELOPER_GUIDE.md) | Local setup, code style, git workflow, deployment |
| [QA Strategy](docs/QA_STRATEGY.md) | Testing strategy, test plan, quality metrics |
| [Glossary](docs/GLOSSARY.md) | Key terms and concepts |

## Contributing

1. Create a feature branch from `main` (`feature/your-feature` or `fix/your-fix`).
2. Follow the code style conventions described in the [Developer Guide](docs/DEVELOPER_GUIDE.md).
3. Write tests for new functionality.
4. Open a pull request targeting `main` with a clear summary.
5. Ensure all CI checks pass and request a review.

### Commit Messages

```
<type>: <short description>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `infra`.

## License

All rights reserved.
