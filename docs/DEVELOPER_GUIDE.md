# Hear Here -- Developer Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Xcode | 16+ | iOS app development |
| Swift | 6 | iOS app language |
| Node.js | 20 | Backend Azure Functions and tooling |
| npm | 10+ | Package management |
| Docker | Latest | Local PostgreSQL + PostGIS |
| Azure CLI | 2.x | Azure resource management |
| Azure Functions Core Tools | 4.x | Local Functions development and deployment |
| Firebase CLI | Latest | Firebase project management |

## Repository Structure

```
hear-here/
├── docs/                          # Technical design documents
│   ├── ARCHITECTURE.md            # System architecture
│   ├── DATABASE.md                # Database schema and data model
│   ├── BACKEND.md                 # Backend API and service design
│   ├── IOS_APP.md                 # iOS app architecture and UI
│   ├── CLOUD_ARCHITECTURE.md      # Cloud infrastructure
│   ├── PROJECT_OVERVIEW.md        # Product overview and roadmap
│   ├── API_DOCUMENTATION.md       # API reference
│   ├── QA_STRATEGY.md             # Testing strategy and test plan
│   ├── DEVELOPER_GUIDE.md         # This document
│   └── GLOSSARY.md                # Key terms
├── ios/                           # iOS app (Xcode project)
│   └── HearHere/
│       ├── App/                   # App entry point, coordinators, DI
│       ├── Features/              # Feature modules (Auth, Discovery, etc.)
│       ├── Core/                  # Network, Location, Audio, Auth services
│       ├── Shared/                # Reusable components, extensions, styles
│       └── Resources/             # Assets, strings, Info.plist
├── backend/                       # Azure Functions (TypeScript)
│   ├── functions/                 # API endpoint handlers
│   │   ├── recordings/            # Recording CRUD
│   │   ├── discovery/             # Nearby recordings query
│   │   ├── users/                 # User profile management
│   │   ├── reports/               # Content reporting
│   │   ├── admin/                 # Moderation queue management
│   │   └── triggers/              # Event Grid and timer triggers
│   ├── moderation/                # Durable Functions orchestrator + activities
│   └── shared/                    # Database client, error handling, schemas
├── infra/                         # Bicep infrastructure templates
│   ├── main.bicep                 # Top-level orchestration
│   ├── modules/                   # Per-concern Bicep modules
│   └── environments/              # Per-environment parameter files
├── admin/                         # Human review admin UI (React)
└── scripts/                       # Dev scripts, DB migrations
```

## Local Development Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd hear-here
```

### 2. Backend Setup

```bash
# Install backend dependencies
cd backend
npm install

# Start a local PostgreSQL + PostGIS database
docker run --name hearhere-db \
  -e POSTGRES_DB=hearhere \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=localdev \
  -p 5432:5432 \
  -d postgis/postgis:16-3.4

# Run database migrations
npm run migrate:up

# Create a .env file for local development
cp .env.example .env
# Edit .env with your local values
```

The `.env` file should contain:

```
DATABASE_URL=postgresql://postgres:localdev@localhost:5432/hearhere
FIREBASE_PROJECT_ID=hearhere-dev
OPENAI_API_KEY=sk-...
STORAGE_ACCOUNT_NAME=hearherestore-dev
FRONT_DOOR_HOSTNAME=cdn-dev.hearhere.app
```

### 3. iOS App Setup

```bash
# Open the Xcode project
open ios/HearHere.xcodeproj

# Or if using workspace
open ios/HearHere.xcworkspace
```

- Swift Package dependencies resolve automatically on first open.
- Select the `HearHere (Development)` scheme for the dev API environment.
- Requires an Apple Developer account for device testing (Sign in with Apple requires provisioning profile).
- Simulator works for most features except push notifications.

#### Environment Configuration

The iOS app reads configuration from `.xcconfig` files:

| Environment | Config File | API Base URL |
|-------------|-------------|-------------|
| Development | `Dev.xcconfig` | `https://api-dev.hearhere.app/v1` |
| Staging | `Staging.xcconfig` | `https://api-staging.hearhere.app/v1` |
| Production | `Release.xcconfig` | `https://api.hearhere.app/v1` |

Firebase configuration is loaded from `GoogleService-Info.plist` (per-environment, not committed to git).

### 4. Infrastructure Setup

```bash
cd infra

# Validate Bicep templates compile
az bicep build --file main.bicep

# Preview what would be deployed
az deployment group what-if \
  --resource-group hearhere-dev-rg \
  --template-file main.bicep \
  --parameters environments/dev.bicepparam
```

### 5. Admin UI Setup

```bash
cd admin
npm install
npm run dev
```

The admin UI runs at `http://localhost:5173` and requires a Firebase user with the `admin: true` custom claim.

---

## Environment Configuration

### Three Environments

| Environment | Purpose | Auto-deploy |
|-------------|---------|-------------|
| dev | Development and experimentation | Manual |
| staging | Pre-production validation | On merge to `main` |
| production | Live users | Manual with approval |

Each environment uses a separate Azure resource group for isolation. See [CLOUD_ARCHITECTURE.md](./CLOUD_ARCHITECTURE.md) for details.

### Secrets Management

Secrets are stored in Azure Key Vault and never committed to the repository:

| Secret | Description |
|--------|-------------|
| `DATABASE_URL` | PostgreSQL Flexible Server connection string |
| `OPENAI_API_KEY` | OpenAI API key for content moderation |
| `SPEECH_SERVICE_KEY` | Azure AI Speech service key |
| `NOTIFICATION_HUB_CONNECTION` | Azure Notification Hubs connection string |

For local development, use a `.env` file (git-ignored).

---

## Code Style and Conventions

### TypeScript (Backend)

- **Strict mode** enabled in `tsconfig.json`.
- **ESLint** for linting with the recommended TypeScript ruleset.
- **Prettier** for formatting (configured in `.prettierrc`).
- **Naming:** `camelCase` for variables and functions, `PascalCase` for types and interfaces, `SCREAMING_SNAKE_CASE` for error codes and constants.
- **Zod schemas** for all request validation. Infer TypeScript types from Zod schemas, not the other way around.
- **No classes** for function handlers. Export plain `handler` functions.
- **Kysely** for database queries. Use raw SQL only for PostGIS-specific functions.

### Swift (iOS)

- **Swift 6** strict concurrency enabled project-wide.
- **SwiftUI** for all views. No UIKit unless SwiftUI has a gap.
- **`@Observable`** macro for ViewModels and services.
- **`@MainActor`** annotation on all ViewModels.
- **Dependency injection** via SwiftUI `@Environment` with custom `EnvironmentKey` types.
- **Naming:** Follow Swift API Design Guidelines. Types are `PascalCase`, properties and methods are `camelCase`.
- **No Combine.** Use `async`/`await` with structured concurrency.
- **Protocols** for all services to enable mock injection in tests.

### Infrastructure (Bicep)

- **Bicep** for all infrastructure-as-code.
- **One module per concern** (network, storage, database, API, etc.).
- **Resource naming:** `hearhere-{component}-{env}` (e.g., `hearhere-api-prod`).
- **Environment config** in `infra/environments/{env}.bicepparam` files.

---

## Git Workflow

### Branching Model

- `main` -- Production-ready code. Auto-deploys to staging on merge.
- Feature branches -- Created from `main`, named `feature/{description}` or `fix/{description}`.
- No long-lived development branches.

### Workflow

1. Create a feature branch from `main`.
2. Make changes and commit with clear, descriptive messages.
3. Push the branch and open a pull request targeting `main`.
4. CI runs automatically (lint, type check, tests, security scan).
5. Request review from at least one team member.
6. Merge via squash merge after approval and passing CI.

### Commit Message Format

```
<type>: <short description>

<optional body explaining why, not what>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `infra`.

Examples:
```
feat: add cursor-based pagination to nearby endpoint
fix: handle expired SAS URLs in upload retry
infra: add Azure Monitor alert for moderation queue backlog
```

---

## Pull Request Process

### PR Template

Every PR should include:

1. **Summary** -- What changed and why (1-3 sentences).
2. **Testing** -- How the change was tested (unit tests, manual testing, etc.).
3. **Screenshots** -- For UI changes, include before/after screenshots.

### Review Checklist

- [ ] Code follows the project style conventions
- [ ] No hardcoded secrets or credentials
- [ ] New endpoints have request validation (Zod schemas)
- [ ] Error cases are handled and return appropriate error codes
- [ ] Database queries use parameterized values (no SQL injection)
- [ ] iOS views support Dynamic Type and VoiceOver
- [ ] Tests cover the happy path and key error cases

### CI Checks

All PRs must pass:

| Check | Scope | Tool |
|-------|-------|------|
| Lint | Backend | ESLint |
| Type check | Backend | TypeScript compiler |
| Unit tests | Backend | Vitest |
| Security scan | Backend | npm audit |
| Bicep lint | Infrastructure | az bicep lint |
| Build | iOS | xcodebuild |
| Unit tests | iOS | XCTest |

---

## Database Migrations

Migrations are managed with `node-pg-migrate` and stored in `scripts/migrations/`.

### Running Migrations

```bash
# Apply all pending migrations
cd backend
npm run migrate:up

# Rollback the last migration
npm run migrate:down

# Create a new migration
npm run migrate:create -- <migration-name>
```

### Migration Principles

1. **Forward-only in production.** Write new migrations to undo changes rather than rolling back.
2. **No breaking changes without a multi-step migration.** Renaming a column requires: add new column, backfill, switch application code, drop old column.
3. **All migrations are idempotent** where possible (use `IF NOT EXISTS`).
4. **Migrations run inside a transaction.** PostgreSQL DDL is transactional.
5. **Test migrations locally** against a Docker PostgreSQL before pushing.

### Production Deployment

Migrations run automatically as a pre-deployment step in the CI/CD pipeline. They execute as a one-off Azure Function invocation using the `migration_user` database role (which has DDL permissions).

---

## Deployment

### Infrastructure Deployment

```bash
cd infra

# Deploy all resources to an environment
az deployment group create \
  --resource-group hearhere-staging-rg \
  --template-file main.bicep \
  --parameters environments/staging.bicepparam

# Preview changes
az deployment group what-if \
  --resource-group hearhere-staging-rg \
  --template-file main.bicep \
  --parameters environments/staging.bicepparam
```

### Deployment Pipeline

| Event | Action |
|-------|--------|
| PR opened/updated | CI checks only (no deploy) |
| Merge to `main` | Auto-deploy to staging |
| Manual dispatch with approval | Deploy to production |
| Git tag `v*` | Build iOS release, upload to TestFlight |

### Production Deployment Checklist

1. Verify staging deployment is stable (no new alerts).
2. Run the manual deploy workflow for production.
3. Monitor Azure Dashboard for error spikes.
4. Verify the health check endpoint returns 200.

### Azure Authentication

CI/CD authenticates to Azure via OIDC federation (no static credentials). The GitHub Actions workflow uses a federated credential on an Azure AD app registration, scoped to the specific environment's resource group.

---

## Testing

### Backend Testing

```bash
cd backend

# Run unit tests
npm test

# Run tests in watch mode
npm run test:watch

# Run integration tests (requires local PostgreSQL)
npm run test:integration
```

**Unit tests** (Vitest) cover Azure Function handlers, service logic, and Zod schema validation with mocked database and external service calls.

**Integration tests** run against a local PostgreSQL+PostGIS database (Docker) and test actual database queries including spatial operations.

### iOS Testing

- **Unit tests** (XCTest + Swift Testing) cover ViewModels and services.
- **UI tests** (XCUITest) cover critical user flows.
- **Preview testing** -- every view has Xcode Previews with mock data for all states (loading, error, empty, populated).

### Infrastructure Testing

```bash
cd infra
az bicep build --file main.bicep  # Validates templates compile
```

---

## Monitoring

### Azure Dashboard

Each environment has an Azure Dashboard showing:
- API request rate and error rate
- Azure Functions execution count and p99 latency
- PostgreSQL Flexible Server CPU, connections, and query latency
- Moderation pipeline throughput and Service Bus queue depth
- Blob Storage upload volume

### Key Alerts (Production)

| Alert | Threshold |
|-------|-----------|
| API 5xx error rate | > 5% for 5 min |
| Function failures | > 10 in 5 min |
| PostgreSQL CPU | > 80% for 10 min |
| Moderation queue backlog | > 100 items for 30 min |
| Moderation queue age | Oldest message > 24 hours |

See [CLOUD_ARCHITECTURE.md](./CLOUD_ARCHITECTURE.md) for the full monitoring and alerting configuration.

---

## Useful Links

- [ARCHITECTURE.md](./ARCHITECTURE.md) -- System architecture
- [DATABASE.md](./DATABASE.md) -- Database schema and queries
- [BACKEND.md](./BACKEND.md) -- Backend API design and Azure Functions structure
- [IOS_APP.md](./IOS_APP.md) -- iOS app architecture and UI
- [CLOUD_ARCHITECTURE.md](./CLOUD_ARCHITECTURE.md) -- Cloud infrastructure and CI/CD
- [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) -- API reference
- [QA_STRATEGY.md](./QA_STRATEGY.md) -- Testing strategy and test plan
- [GLOSSARY.md](./GLOSSARY.md) -- Key terms and concepts
