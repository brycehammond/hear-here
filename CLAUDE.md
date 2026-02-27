# Hear Here - Project Guidelines

## Development Practices

- **Test-Driven Development (TDD):** Always write tests first, then implement the code to make them pass. Follow red-green-refactor: write a failing test, write minimal code to pass, refactor.
- **Testing framework:** xUnit with FluentAssertions for assertions and NSubstitute for mocking.
- **Test location:** Tests go in the corresponding test project under `backend/tests/`.

## Tech Stack

- **Backend:** ASP.NET Core Web API (Minimal APIs) + Azure Functions (Isolated Worker), .NET 10
- **Database:** PostgreSQL + PostGIS via EF Core with Npgsql + NetTopologySuite
- **Validation:** FluentValidation
- **Auth:** Microsoft Entra External ID (Azure AD B2C) with Microsoft.Identity.Web for JWT validation
- **Cloud:** Azure (Blob Storage, Service Bus, Durable Functions)
- **Infrastructure as Code:** Bicep for all Azure resource provisioning

## Project Structure

- `backend/src/HearHere.Shared/` — Shared library (entities, DbContext, models, services)
- `backend/src/HearHere.Api/` — ASP.NET Core Web API
- `backend/src/HearHere.Functions/` — Azure Functions (Isolated Worker)
- `backend/tests/HearHere.Api.Tests/` — API tests
- `backend/tests/HearHere.Functions.Tests/` — Functions tests
- `backend/infra/` — Bicep infrastructure scripts (modules/ for resources, parameters/ for env configs)
