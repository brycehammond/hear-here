# Hear Here — Backend Implementation Progress

## Overview

| Category | Status | Completeness |
|----------|--------|--------------|
| API Endpoints | Done | 13/13 endpoints implemented |
| Entity Models | Done | 8/8 entities with full EF Core config |
| DbContext + Indexes | Done | GiST spatial, partial, composite indexes |
| Durable Functions Pipeline | Done | Orchestrator + 6 activities (notifications stub) |
| Background Jobs | Done | 2 timer functions (cleanup uploads, cleanup audio) |
| Validators | Done | 6 FluentValidation validators |
| Unit Tests | Partial | 100 tests passing (validators + function logic) |
| Bicep Infrastructure | Partial | Core resources done, missing APIM/CDN/Event Grid |
| Service Integration | Partial | Service Bus wired; no Event Grid trigger yet |
| EF Core Migrations | Done | InitialCreate migration generated |

**Estimated overall completeness: ~75%**

---

## What's Built

### Solution Structure (5 projects)

```
backend/
  HearHere.slnx
  src/
    HearHere.Shared/       — Entities, DbContext, DTOs, services, exceptions
    HearHere.Api/          — ASP.NET Core Minimal API (13 endpoints)
    HearHere.Functions/    — Azure Functions isolated worker (7 functions)
  tests/
    HearHere.Api.Tests/    — 72 tests (validators)
    HearHere.Functions.Tests/ — 28 tests (decision logic, cleanup)
  infra/
    main.bicep + 8 modules + dev/prod params
```

### API Endpoints (all implemented)

| Group | Endpoints |
|-------|-----------|
| Auth | `POST /v1/auth/register` |
| Users | `GET /v1/users/me`, `PUT /v1/users/me` |
| Recordings | `POST /v1/recordings`, `GET /v1/recordings/{id}`, `DELETE /v1/recordings/{id}`, `GET /v1/recordings/mine`, `POST /v1/recordings/{id}/upload-complete`, `GET /v1/recordings/{id}/playback` |
| Discovery | `GET /v1/recordings/nearby` (PostGIS ST_DWithin) |
| Reports | `POST /v1/reports` (auto-escalation at 3 reports) |
| Admin | `GET /v1/admin/moderation/queue`, `POST /v1/admin/moderation/{id}/decision`, `GET /v1/admin/moderation/stats` |

### Azure Functions

| Function | Trigger | Status |
|----------|---------|--------|
| ModerationOrchestrator | Service Bus queue | Implemented |
| TranscriptionActivity | Durable activity | Implemented (Azure AI Speech REST API) |
| ClassificationActivity | Durable activity | Implemented (OpenAI Moderation API) |
| DecisionActivity | Durable activity | Implemented (threshold logic) |
| NotificationActivity | Durable activity | **Stub** (logs only, no APNs integration) |
| CleanupUploadsFunction | Timer (hourly) | Implemented |
| CleanupAudioFunction | Timer (daily 3AM) | Implemented |

### Bicep Infrastructure

| Module | Resources |
|--------|-----------|
| database.bicep | PostgreSQL Flexible Server + PostGIS |
| storage.bicep | Blob Storage + recordings container |
| functions.bicep | Function App (Consumption) + App Insights |
| api.bicep | App Service for Web API |
| servicebus.bicep | Service Bus + moderation-requests queue |
| keyvault.bicep | Key Vault for secrets |
| keyvault-access.bicep | RBAC role assignments |
| monitoring.bicep | Log Analytics + App Insights |

### Auth

- Microsoft Entra External ID (Azure AD B2C) via Microsoft.Identity.Web
- JWT validation at app level (not via APIM gateway)
- Admin authorization policy for moderation endpoints

---

## Known Issues

### P0 — Blocking (all resolved)

- [x] **Report reason code mismatch**: Fixed — DB constraint now matches API validator (`hate_speech`, `harassment`, `violence`, `sexual_content`, `spam`, `misinformation`, `other`). Report default status changed from `open` to `submitted`.
- [x] **Service Bus not wired**: Fixed — `upload-complete` endpoint now sends a message via `IMessageQueueService` to the `moderation-requests` queue, triggering the Durable Functions orchestrator.
- [x] **No EF Core migrations**: Fixed — `InitialCreate` migration generated with full schema (tables, indexes, constraints, PostGIS extension).

### P1 — Core Gaps

- [ ] No endpoint integration tests (only validators tested)
- [ ] No audio validation function (Event Grid trigger for BlobCreated)
- [ ] Push notifications are a stub (NotificationActivity logs but doesn't send)
- [ ] Moderation thresholds hardcoded (should be App Configuration)

### P2 — Production Readiness

- [ ] No Azure API Management (no rate limiting, no centralized auth)
- [ ] No Azure Front Door / CDN for playback URL caching
- [ ] appsettings.json has placeholder values, no Key Vault references
- [ ] No managed identity auth for PostgreSQL (using password)
- [ ] No high availability for production PostgreSQL

### P3 — Future

- [ ] OpenAPI/Swagger spec generation
- [ ] GDPR user account deletion flow
- [ ] Location name reverse geocoding
- [ ] Play/like counter reconciliation job

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Runtime | .NET 10 |
| API | ASP.NET Core Minimal APIs |
| Background | Azure Functions (Isolated Worker) |
| Database | PostgreSQL 16 + PostGIS (EF Core + Npgsql + NetTopologySuite) |
| Validation | FluentValidation |
| Auth | Microsoft Entra External ID (Azure AD B2C) |
| Storage | Azure Blob Storage |
| Messaging | Azure Service Bus |
| Orchestration | Durable Functions |
| IaC | Bicep |
| Testing | xUnit + FluentAssertions + NSubstitute |

---

## Decision Log

| Decision | Rationale |
|----------|-----------|
| .NET 10 over Node.js | User preference; strong Azure integration |
| Entra ID over Firebase | Azure-native auth, avoids cross-platform dependency |
| ASP.NET Core + Azure Functions (split) | REST API for synchronous, Functions for async processing |
| EF Core over raw SQL | Type-safe queries, migration tooling, spatial support via NTS |
| FluentValidation over DataAnnotations | Richer validation rules, better testability |
| Bicep over Terraform | Azure-native, first-class VS Code support |
