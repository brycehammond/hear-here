# Hear Here -- Developer Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Xcode | 16+ | iOS app development |
| Swift | 6 | iOS app language |
| Node.js | 20 | Backend Lambda functions and CDK |
| npm | 10+ | Package management |
| Docker | Latest | Local PostgreSQL + PostGIS |
| AWS CLI | 2.x | AWS resource management |
| AWS CDK CLI | 2.x | Infrastructure deployment |
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
│   ├── DEVELOPER_GUIDE.md         # This document
│   └── GLOSSARY.md                # Key terms
├── ios/                           # iOS app (Xcode project)
│   └── HearHere/
│       ├── App/                   # App entry point, coordinators, DI
│       ├── Features/              # Feature modules (Auth, Discovery, etc.)
│       ├── Core/                  # Network, Location, Audio, Auth services
│       ├── Shared/                # Reusable components, extensions, styles
│       └── Resources/             # Assets, strings, Info.plist
├── backend/                       # Lambda functions (TypeScript)
│   ├── functions/                 # API endpoint handlers
│   │   ├── authorizer/            # Firebase JWT validation
│   │   ├── recordings/            # Recording CRUD
│   │   ├── discovery/             # Nearby recordings query
│   │   ├── users/                 # User profile management
│   │   ├── reports/               # Content reporting
│   │   └── admin/                 # Moderation queue management
│   ├── moderation/                # Step Functions workflow + Lambdas
│   └── shared/                    # Database client, error handling, schemas
├── infra/                         # AWS CDK infrastructure
│   ├── lib/                       # Stack definitions
│   ├── bin/                       # CDK app entry point
│   └── config/                    # Per-environment configuration
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
AUDIO_BUCKET=hearhere-audio-dev
CLOUDFRONT_DOMAIN=cdn-dev.hearhere.app
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
npm install

# Verify CDK compiles
npx cdk synth -c env=dev

# Show what would be deployed
npx cdk diff -c env=dev
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

Each environment runs in a separate AWS account for isolation. See [CLOUD_ARCHITECTURE.md](./CLOUD_ARCHITECTURE.md) for details.

### Secrets Management

Secrets are stored in AWS Secrets Manager and never committed to the repository:

| Secret | Description |
|--------|-------------|
| `DATABASE_URL` | RDS Proxy connection string |
| `OPENAI_API_KEY` | OpenAI API key for content moderation |
| `CLOUDFRONT_KEY_PAIR_ID` | CloudFront signing key pair ID |
| `CLOUDFRONT_PRIVATE_KEY` | CloudFront signing private key |

For local development, use a `.env` file (git-ignored).

---

## Code Style and Conventions

### TypeScript (Backend)

- **Strict mode** enabled in `tsconfig.json`.
- **ESLint** for linting with the recommended TypeScript ruleset.
- **Prettier** for formatting (configured in `.prettierrc`).
- **Naming:** `camelCase` for variables and functions, `PascalCase` for types and interfaces, `SCREAMING_SNAKE_CASE` for error codes and constants.
- **Zod schemas** for all request validation. Infer TypeScript types from Zod schemas, not the other way around.
- **No classes** for Lambda handlers. Export plain `handler` functions.
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

### Infrastructure (CDK)

- **TypeScript** for all CDK code.
- **One stack per concern** (network, storage, database, API, etc.).
- **Resource naming:** `hearhere-{component}-{env}` (e.g., `hearhere-audio-prod`).
- **Environment config** in `infra/config/{env}.ts` files.

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
fix: handle expired pre-signed URLs in upload retry
infra: add CloudWatch alarm for moderation queue backlog
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
| CDK synth | Infrastructure | AWS CDK |
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

Migrations run automatically as a pre-deployment step in the CI/CD pipeline. They execute as a one-off Lambda invocation using the `migration_user` database role (which has DDL permissions).

---

## Deployment

### Infrastructure Deployment

```bash
cd infra

# Deploy all stacks to an environment
npx cdk deploy --all -c env=staging

# Deploy a specific stack
npx cdk deploy hearhere-api-staging -c env=staging

# Preview changes
npx cdk diff -c env=staging
```

### Deployment Pipeline

| Event | Action |
|-------|--------|
| PR opened/updated | CI checks only (no deploy) |
| Merge to `main` | Auto-deploy to staging |
| Manual dispatch with approval | Deploy to production |
| Git tag `v*` | Build iOS release, upload to TestFlight |

### Production Deployment Checklist

1. Verify staging deployment is stable (no new alarms).
2. Run the manual deploy workflow for production.
3. Monitor CloudWatch dashboard for error spikes.
4. Verify the health check endpoint returns 200.

### AWS Authentication

CI/CD authenticates to AWS via OIDC federation (no static credentials). The GitHub Actions workflow assumes an IAM role scoped to the specific environment.

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

**Unit tests** (Vitest) cover Lambda handlers, service logic, and Zod schema validation with mocked database and external service calls.

**Integration tests** run against a local PostgreSQL+PostGIS database (Docker) and test actual database queries including spatial operations.

### iOS Testing

- **Unit tests** (XCTest + Swift Testing) cover ViewModels and services.
- **UI tests** (XCUITest) cover critical user flows.
- **Preview testing** -- every view has Xcode Previews with mock data for all states (loading, error, empty, populated).

### Infrastructure Testing

```bash
cd infra
npx cdk synth -c env=dev  # Validates templates compile
```

---

## Monitoring

### CloudWatch Dashboard

Each environment has a CloudWatch dashboard showing:
- API request rate and error rate
- Lambda invocation count and p99 latency
- RDS CPU, connections, and query latency
- Moderation pipeline throughput and queue depth
- S3 upload volume

### Key Alarms (Production)

| Alarm | Threshold |
|-------|-----------|
| API 5xx error rate | > 5% for 5 min |
| Lambda errors | > 10 in 5 min |
| RDS CPU | > 80% for 10 min |
| Moderation queue backlog | > 100 items for 30 min |
| Moderation queue age | Oldest message > 24 hours |

See [CLOUD_ARCHITECTURE.md](./CLOUD_ARCHITECTURE.md) for the full monitoring and alerting configuration.

---

## Useful Links

- [ARCHITECTURE.md](./ARCHITECTURE.md) -- System architecture
- [DATABASE.md](./DATABASE.md) -- Database schema and queries
- [BACKEND.md](./BACKEND.md) -- Backend API design and Lambda structure
- [IOS_APP.md](./IOS_APP.md) -- iOS app architecture and UI
- [CLOUD_ARCHITECTURE.md](./CLOUD_ARCHITECTURE.md) -- Cloud infrastructure and CI/CD
- [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) -- API reference
- [QA_STRATEGY.md](./QA_STRATEGY.md) -- Testing strategy and test plan
- [GLOSSARY.md](./GLOSSARY.md) -- Key terms and concepts
