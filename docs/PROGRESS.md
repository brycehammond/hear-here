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
| Unit Tests | Done | 155 tests passing (validators + functions + integration) |
| Integration Tests | Done | 52 endpoint integration tests (WebApplicationFactory + InMemory DB) |
| Bicep Infrastructure | Partial | Core resources done, missing APIM/CDN |
| Service Integration | Done | Service Bus wired; Event Grid audio validation trigger |
| EF Core Migrations | Done | InitialCreate + AddApnsTokenToUser migrations |

**Estimated overall completeness: ~90%**

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
    HearHere.Api.Tests/    — 103 tests (validators + endpoint integration)
    HearHere.Functions.Tests/ — 52 tests (decision logic, cleanup, audio validation, notifications)
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
| DecisionActivity | Durable activity | Implemented (configurable thresholds via IOptions) |
| NotificationActivity | Durable activity | Implemented (Azure Notification Hubs / APNs) |
| AudioValidationFunction | Event Grid (BlobCreated) | Implemented (size, header, duration checks) |
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

### P1 — Core Gaps (all resolved)

- [x] **Endpoint integration tests**: 52 integration tests added using WebApplicationFactory + InMemory DB + TestAuthHandler covering all endpoint groups (auth, users, recordings, reports, admin, discovery)
- [x] **Audio validation function**: Event Grid-triggered function validates file size (<10MB), audio headers (AAC ADTS / M4A ftyp), and duration (mvhd atom parsing, 5s tolerance)
- [x] **Push notifications**: NotificationActivity now sends real APNs push notifications via Azure Notification Hubs with per-status messages and graceful error handling
- [x] **Moderation thresholds configurable**: Extracted to `ModerationSettings` class with `IOptions<T>` pattern, supporting per-category and default thresholds via configuration

### P2 — Production Readiness (partially resolved)

- [ ] No Azure API Management (no rate limiting, no centralized auth)
- [ ] No Azure Front Door / CDN for playback URL caching
- [x] **Key Vault configuration**: Azure Key Vault configuration provider added for non-Development environments (API + Functions)
- [x] **Managed identity for PostgreSQL**: NpgsqlDataSourceBuilder with periodic AAD token refresh via DefaultAzureCredential in production
- [x] **PostgreSQL HA**: Zone-redundant high availability enabled for production environment in Bicep

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
| Push Notifications | Azure Notification Hubs (APNs) |
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
