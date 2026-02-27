# Hear Here -- QA Strategy and Test Plan

## 1. Philosophy and TDD Approach

### 1.1 Core Principles

- **Test-Driven Development (TDD)**: Write failing tests before implementation. Red-Green-Refactor is the standard workflow for all production code.
- **Testing Pyramid**: Prioritize fast, isolated unit tests at the base; use fewer integration and end-to-end tests at the top.
- **Shift Left**: Catch defects as early as possible. Static analysis, linting, and unit tests run on every commit.
- **Every Bug Gets a Test**: When a bug is found, write a failing test that reproduces it before fixing it. This test becomes a permanent regression guard.
- **Deterministic Tests**: No flaky tests in CI. Tests that depend on timing, network, or device state must use mocks or controlled environments.

### 1.2 TDD Workflow

**iOS (Swift 6, SwiftUI)**:
1. Developer writes a failing XCTest for the new behavior.
2. Implement the minimum code to make the test pass.
3. Refactor while keeping all tests green.
4. PR requires passing tests before merge.

**Backend (Node.js 20, TypeScript)**:
1. Developer writes a failing Vitest unit test for the handler/service function.
2. Implement the function.
3. Refactor with tests green.
4. Zod schemas validate request input; Kysely queries are tested against real PostgreSQL.
5. Integration tests verify Lambda handler with real DB (Testcontainers) and mocked AWS services.

**Infrastructure (AWS CDK, TypeScript)**:
1. CDK snapshot tests verify infrastructure changes are intentional.
2. CDK assertion tests validate resource properties (e.g., S3 bucket encryption enabled, RDS Proxy configured, Lambda VPC placement).

---

## 2. Testing Pyramid

```
         /  E2E  \            ~5% of tests
        /----------\
       / Integration \        ~20% of tests
      /----------------\
     /    Unit Tests     \    ~75% of tests
    /______________________\
```

### Coverage Targets

| Layer | Target Coverage | Rationale |
|-------|----------------|-----------|
| Unit Tests | >= 80% line coverage | Core business logic, models, ViewModels, service functions |
| Integration Tests | Key paths covered | API endpoints, DB queries, moderation pipeline, auth flow |
| E2E Tests | Critical user journeys | Record, moderate, discover, play -- the four core flows |

### Coverage Enforcement

- iOS: Xcode code coverage reports generated per PR. Enforced via CI gate.
- Backend: Coverage reports via Vitest's built-in `--coverage` flag (c8/istanbul). Fail CI if coverage drops below threshold.
- Coverage is measured on business logic, not boilerplate (exclude generated code, CDK constructs, UI layout-only code).

---

## 3. iOS Testing

### 3.1 Framework and Tooling

| Tool | Purpose |
|------|---------|
| XCTest / Swift Testing | Unit and integration tests for ViewModels, services, models |
| XCUITest | UI automation tests for critical flows |
| swift-snapshot-testing | View snapshot regression tests |
| Protocol-based mocks | Dependency injection via `@Environment` for testability |

### 3.2 Architecture for Testability

The iOS app uses MVVM + Coordinator with `@Observable` (iOS 17+) and protocol-based dependency injection via SwiftUI `@Environment`. Every external dependency (network, audio, location, auth) is accessed through a protocol, enabling mock injection in tests. ViewModels are `@MainActor` and receive dependencies via initializer injection.

```swift
// Example: Protocol for audio recording
protocol AudioRecorderProtocol {
    func startRecording() async throws
    func stopRecording() async throws -> AudioFile
    var isRecording: Bool { get }
    var currentDuration: TimeInterval { get }
}

// Production: AudioRecorder wraps AVAudioRecorder
// Tests: MockAudioRecorder returns controlled results
```

### 3.3 Unit Tests (XCTest)

#### ViewModels

| ViewModel | Test Cases |
|-----------|------------|
| `RecordingViewModel` | Start/stop recording state transitions; duration updates; max duration enforcement (5 min); auto-stop at 5:00; countdown at 4:30; error handling for microphone denial; cancel discards recording |
| `MapViewModel` | Nearby recordings loaded on location update (`loadNearby()`); empty state when no recordings nearby; `searchRadius` parameter respected (default 500m, max 5km); recordings sorted by distance; error handling for location denial; re-center to current location |
| `PlaybackViewModel` | Play/pause/seek state transitions; progress tracking; playback completion handling; streaming error recovery; MiniPlayer state sync |
| `AuthViewModel` | Sign-in with Apple triggers Firebase auth; Sign-in with Google; sign-out clears local state; token refresh flow; `AuthGate` state transitions (loading -> onboarding/authenticated) |
| `ProfileViewModel` | User recordings list loaded via `/recordings/mine`; recording deletion with confirmation; recording status display (pending_upload, pending_moderation, pending_review, approved, rejected); pagination via cursor |
| `SettingsViewModel` | Sign-out flow; delete account flow with confirmation; notification toggle |

#### Services

| Service | Test Cases |
|---------|------------|
| `APIClient` | Request construction (headers, body, URL, base URL per environment); JWT token attachment via `AuthInterceptor`; response parsing (success and typed `APIError` cases); 401 triggers single token refresh and retry; 429 rate limit handling; snake_case to camelCase decoding |
| `LocationService` | `.whenInUse` authorization state changes; `currentLocation` published property updates; accuracy modes (`kCLLocationAccuracyBest` for recording, `kCLLocationAccuracyHundredMeters` for discovery); start/stop updates lifecycle |
| `AudioRecorder` | AAC codec configuration (44.1kHz, 64kbps, mono); duration tracking; max 5-minute enforcement; interruption handling (phone call, route change) |
| `AudioPlayer` | AVPlayer streaming from CloudFront signed URLs; progressive download playback; error recovery |
| `UploadManager` | Background `URLSession` upload task creation; pre-signed URL request; upload progress tracking via delegate; retry on network failure; upload cancellation; persistence of pending uploads across app launches |
| `AuthService` | Firebase Auth wrapper; `@Observable` `AuthState` updates; token retrieval for API requests |
| `CacheManager` | LRU eviction; 100 MB cap; audio file caching for offline playback |
| `NetworkMonitor` | `NWPathMonitor` connectivity state; offline banner trigger |

#### Models

| Model | Test Cases |
|-------|------------|
| `Recording` | JSON decoding from API response (`snake_case` keys); all `ModerationStatus` enum cases; coordinate validation; duration bounds (1-300); distance formatting |
| `User` | JSON decoding; profile update encoding; display name validation (1-50 chars) |
| `AppError` | Mapping from `APIError` to user-facing `errorDescription` and `recoverySuggestion` |

#### Coordinators

| Coordinator | Test Cases |
|-------------|------------|
| `AppCoordinator` | `AuthGate` transitions: `.loading` -> `.onboarding` (no session) / `.authenticated` (active session); `tabSelection` state |
| `DiscoveryCoordinator` | `NavigationPath` push/pop for `PlaybackView`; `popToRoot()` |
| `RecordingCoordinator` | Navigation through recording flow: RecordingView -> MetadataView -> LocationPicker -> ConfirmationView |
| `ProfileCoordinator` | Navigation to RecordingDetailView, SettingsView, PlaybackView |

### 3.4 UI Tests (XCUITest)

| Flow | Steps | Assertions |
|------|-------|------------|
| **Onboarding/Auth** | Launch app -> WelcomeView carousel -> Tap "Get Started" -> Tap "Sign in with Apple" | Navigates to main TabView with Discover tab selected |
| **Record Audio** | Select Record tab -> Grant mic permission (pre-prompt then system) -> Tap record -> Wait 10s -> Tap stop -> Enter subject -> Adjust location on map -> Tap Submit -> Tap Upload | Upload progress shown; "Your recording is being reviewed!" confirmation; appears in Profile > My Recordings with "Under Review" badge |
| **Discover Nearby** | Select Discover tab -> Grant location permission -> View map | Map centered on current location; pins visible for nearby recordings; bottom sheet shows NearbyListView; pull-to-refresh reloads |
| **Play Recording** | Tap recording pin callout / list row -> PlaybackView opens | Subject, description, creator name, mini-map visible; play/pause controls work; scrub bar advances; MiniPlayer appears in tab bar |
| **Delete Recording** | Profile tab -> Swipe recording in MyRecordingsListView -> Confirm delete alert | Recording removed from list |
| **Report Recording** | PlaybackView -> Tap ellipsis menu -> Tap Report -> Select reason -> Submit | Confirmation shown |
| **Settings** | Profile tab -> Tap Settings -> Verify elements | Sign out, delete account, notification toggle, about section visible |

#### XCUITest Guidelines

- Use accessibility identifiers for all interactive elements (not text matching).
- Tests run against a local mock server (no real backend).
- Reset app state between tests using `XCUIApplication.launchArguments` (e.g., `--uitesting`, `--mock-api`).
- Keep UI tests focused on navigation and interaction flow, not business logic.
- Run on iPhone 16 simulator, iOS 18.

### 3.5 Snapshot Tests

Snapshot tests verify that views render correctly and detect unintended visual regressions.

| View | Variants Captured |
|------|-------------------|
| `RecordingView` | Idle, recording in progress, countdown at 4:30, max duration reached, mic permission denied |
| `MapView` | No recordings, several pins, loading state, location permission denied |
| `NearbyListView` | Empty state, populated list, loading |
| `RecordingCardView` | Short recording, long description, each `StatusBadge` variant (Under Review, Published, Not Published) |
| `PlaybackView` | Playing, paused, loading, error, streaming |
| `MiniPlayerView` | Playing, paused |
| `ProfileView` | No recordings, with recordings, loading |
| `RecordingMetadataView` | Empty form, filled form, validation error |
| `RecordingConfirmationView` | Ready to upload, uploading with progress, success, error |
| `SignInView` | Default state |
| `WelcomeView` | Each carousel card |
| `SettingsView` | Default state |

**Snapshot test configuration**:
- Captured on a fixed simulator (iPhone 16, iOS 18) for consistency.
- Light and dark mode variants.
- Dynamic Type at default and largest accessibility sizes.
- Snapshots committed to the repository; diffs reviewed in PRs.

### 3.6 Mocking Strategy

| Dependency | Mock Approach |
|------------|---------------|
| **Network (API)** | `MockAPIClient` conforming to `APIClient` protocol. Returns preset responses or throws preset `APIError` values. Injected via `@Environment`. For UI tests, a local HTTP stub server. |
| **Audio (AVFoundation)** | `MockAudioRecorder` / `MockAudioPlayer` conforming to protocols. Simulate recording duration, playback progress, interruptions, and error conditions without real audio hardware. |
| **Location (CoreLocation)** | `MockLocationService` conforming to `LocationService` protocol. Emit preset coordinates, authorization status changes, and errors. |
| **Storage (Keychain/UserDefaults)** | In-memory implementations for tests. |
| **Firebase Auth** | `MockAuthService` returns preset user/token or throws auth errors. Controls `AuthState` observable. |
| **Upload** | `MockUploadManager` simulates upload progress, success, and failure without network calls. |
| **Network Monitor** | `MockNetworkMonitor` controls connectivity state for offline testing. |

---

## 4. Backend Testing

### 4.1 Framework and Tooling

| Tool | Purpose |
|------|---------|
| **Vitest** | Unit and integration tests (TypeScript-native, fast) |
| **Testcontainers** | Spin up PostgreSQL 16 + PostGIS 3.4 in Docker for integration tests |
| **aws-sdk-client-mock** | Mock AWS services (S3, SQS, Step Functions, Transcribe, SNS) |
| **Zod** | Request validation schemas (tested for correctness) |
| **Kysely** | Type-safe SQL query builder (queries tested against real PostGIS) |
| **Artillery or k6** | Load and stress testing |
| **Pact** | Contract testing between iOS client and backend API |

### 4.2 Unit Tests

#### Lambda Handlers

| Handler | Test Cases |
|---------|------------|
| `POST /v1/auth/register` | Creates user with Firebase UID and display_name; 409 if user already exists; display_name required (1-50 chars, no control characters); validates Zod schema |
| `POST /v1/recordings` | Valid recording creation; missing required fields (subject, lat/lng, duration_sec); invalid coordinates (lat > 90, lng > 180); duration exceeds max (300s); generates pre-signed S3 PUT URL with correct constraints (15-min expiry, 10MB max, `Content-Type: audio/aac`); sets status to `pending_upload`; checks daily upload limit (10/day); returns 429 `DAILY_UPLOAD_LIMIT` when exceeded |
| `POST /v1/recordings/{id}/upload-complete` | Verifies S3 object exists; updates status from `pending_upload` to `pending_moderation`; starts Step Functions execution; 404 if not found or not owned; 409 if not in `pending_upload` status |
| `GET /v1/recordings/{id}` | Returns full details for owner (any status); returns public details for non-owner (approved only); 404 `RECORDING_NOT_FOUND` for non-existent; 404 for non-owner viewing unapproved recording |
| `GET /v1/recordings/nearby` | Valid coordinate parsing from query params; radius bounds enforcement (50-5000m); default radius (500m); default limit (20, max 50); cursor-based pagination on `(distance_m, id)`; invalid coordinates rejected (422 `INVALID_RADIUS`); minimum radius (50m) enforced |
| `GET /v1/recordings/{id}/playback` | Returns signed CloudFront URL (1-hour expiry); includes `duration_sec` and `format`; 403 `RECORDING_NOT_PLAYABLE` for unapproved (unless owner); 404 for missing; logs play event (fire-and-forget) |
| `GET /v1/recordings/mine` | Returns only current user's recordings; all statuses included; cursor-based pagination on `(created_at, id)`; status filter query param; default limit 20, max 50 |
| `DELETE /v1/recordings/{id}` | Soft-delete sets `deleted_at`; 204 No Content on success; 404 if not found or not owned by user |
| `GET /v1/users/me` | Returns profile including `recording_count` |
| `PUT /v1/users/me` | Updates display_name (1-50 chars); validates Zod schema |
| `POST /v1/reports` | Creates report; 409 `DUPLICATE_REPORT` if user already reported; validates reason enum (`hate_speech`, `harassment`, `violence`, `sexual_content`, `spam`, `misinformation`, `other`); users cannot report own recordings; auto-triggers re-moderation at 3+ reports from distinct users |

#### Admin Endpoints

| Handler | Test Cases |
|---------|------------|
| `GET /v1/admin/moderation/queue` | Returns recordings with `status = 'pending_review'`; ordered oldest first; includes transcript, moderation_scores, playback_url, report_count; cursor-based pagination; requires admin custom claim |
| `POST /v1/admin/moderation/{recordingId}/decision` | Accepts `decision: 'approved' | 'rejected'` and optional `notes`; updates recording status; creates `moderation_records` audit trail entry; sends push notification; 403 for non-admin users |
| `GET /v1/admin/moderation/stats` | Returns `pending_review`, `reviewed_today`, `auto_approved_today`, `auto_rejected_today`, `avg_review_time_sec`; requires admin claim |

#### Firebase JWT Authorizer

| Test Case | Description |
|-----------|-------------|
| Valid token | Extracts `uid`, `email`, and custom claims; passes to downstream handler via `event.requestContext.authorizer` |
| Expired token | Returns 401 `UNAUTHORIZED` |
| Invalid signature | Returns 401 |
| Missing Authorization header | Returns 401 |
| Malformed token (not JWT) | Returns 401 |
| Admin custom claim | `admin: true` correctly extracted and forwarded |
| Moderator role | `moderator` role detection |
| Cached Firebase public keys | Keys cached for 1 hour; refresh on cache miss |

#### Zod Schema Validation Tests

| Schema | Test Cases |
|--------|------------|
| `RecordingCreate` | All valid inputs pass; missing `subject` fails; `latitude` out of range fails; `duration_sec` > 300 fails; `description` > 2000 chars fails; optional fields default correctly |
| `UserUpdate` | `display_name` 1-50 chars; control characters rejected |
| `ReportCreate` | `recording_id` must be valid UUID; `reason` must be enum value; `description` max 1000 chars |
| `NearbyQuery` | `lat`/`lng` required; `radius` 50-5000; `limit` 1-50 |
| `ModerationDecision` | `decision` must be `approved` or `rejected`; `notes` max 2000 chars |

#### Moderation Pipeline Business Logic

| Test Case | Description |
|-----------|-------------|
| All scores below 0.3 | All category scores below auto-approve threshold -> `AUTO_APPROVE` -> status = `approved` |
| Any score above 0.7 | `hate` score = 0.8 -> `AUTO_REJECT` -> status = `rejected` |
| `hate/threatening` lower threshold | Score = 0.55 (above 0.5 reject threshold for this category) -> `AUTO_REJECT` |
| `self-harm` lower threshold | Score = 0.55 (above 0.5 reject threshold for this category) -> `AUTO_REJECT` |
| Uncertain range (0.3-0.7) | `harassment` score = 0.5 -> `HUMAN_REVIEW` -> status = `pending_review`; SQS message sent |
| Boundary: exactly 0.3 | At auto-approve boundary -> `HUMAN_REVIEW` (conservative) |
| Boundary: exactly 0.7 | At auto-reject boundary -> `AUTO_REJECT` |
| Transcription failure | Transcribe job fails -> retry (max 2 attempts, backoff rate 2x); after max retries -> `HUMAN_REVIEW` with transcription failure flag |
| Empty transcript | Silent audio produces empty transcript -> routed to `HUMAN_REVIEW` |
| OpenAI Moderation API timeout | Retry with backoff; after max retries -> `HUMAN_REVIEW` |
| Notification dispatch | Correct APNs payload for approved ("Your recording '{subject}' is now live!") and rejected ("Your recording '{subject}' could not be approved.") |
| Audio validation | File header validation (AAC/M4A); size < 10MB; duration matches declared `duration_sec` within 5s tolerance; non-audio files rejected before moderation |
| S3 key movement | Approved files copied from `audio/pending/` to `audio/approved/`; rejected to `audio/rejected/` |

### 4.3 Integration Tests

Integration tests run against real PostgreSQL 16 + PostGIS 3.4 via Testcontainers (Docker). AWS services remain mocked via `aws-sdk-client-mock`.

#### Database Integration Tests

| Test Area | Test Cases |
|-----------|------------|
| **Recording CRUD** | Insert recording with PostGIS point via Kysely; read back with correct coordinates (ST_Y/ST_X extraction); update status; soft delete (set `deleted_at`); verify `updated_at` trigger fires |
| **Spatial Queries** | Insert recordings at known coordinates; query nearby with `ST_DWithin` and radius; verify correct recordings returned; verify `ST_Distance` accuracy; verify recordings outside radius excluded; verify only `approved` + `deleted_at IS NULL` returned |
| **Spatial Index Performance** | Insert 10,000 recordings; `EXPLAIN ANALYZE` confirms GiST index scan; nearby query completes within 100ms |
| **Status Filtering** | Only `approved` recordings returned by discovery; all statuses returned for `mine` endpoint; `pending_review` returned for admin moderation queue |
| **User Isolation** | User A cannot see User B's pending/rejected recordings; User A can see User B's approved recordings |
| **Cursor-Based Pagination** | Verify `(distance_m, id)` cursor for nearby; `(created_at, id)` cursor for mine; stable under concurrent inserts; correct page sizes |
| **Denormalized Counters** | `play_count` incremented on play event; `like_count` incremented/decremented on like/unlike; counter reconciliation query produces correct values |
| **Likes** | Unique constraint `(user_id, recording_id)` enforced; like/unlike toggle; like count update |
| **Reports** | Report creation; duplicate prevention; report threshold (3+) triggers re-moderation (status -> `pending_review`) |
| **Tags** | Tag creation (lowercase enforcement); recording_tags many-to-many; cascade delete |
| **Moderation Records (Audit Trail)** | Immutable insert on every status transition; correct `action`, `actor_type`, `from_status`, `to_status`, `scores`; actor_id for human actions |
| **User Account Deletion** | Recordings soft-deleted; user anonymized (display_name = 'Deleted User', email = NULL); likes/plays deleted; reports anonymized |
| **Concurrent Writes** | Two concurrent status updates do not corrupt data; optimistic locking or serializable isolation verified |

#### API Endpoint Integration Tests

Run Lambda handlers with real DB (Testcontainers) and mocked AWS services.

| Endpoint | Test Cases |
|----------|------------|
| `POST /v1/auth/register` | Full flow: create user -> verify DB row with Firebase UID |
| `POST /v1/recordings` | Full flow: create metadata -> get pre-signed URL -> verify DB row with `pending_upload` status |
| `POST /v1/recordings/{id}/upload-complete` | Upload confirm -> status transitions to `pending_moderation` -> Step Functions started |
| `GET /v1/recordings/nearby` | Seed DB with recordings at known coords -> query -> verify correct subset returned sorted by distance |
| `GET /v1/recordings/{id}/playback` | Verify CloudFront signed URL generation with correct expiry |
| `GET /v1/recordings/mine` | Seed user's recordings -> verify all statuses returned -> verify pagination |
| `POST /v1/admin/moderation/{id}/decision` | Approve recording -> status updated -> moderation_records audit entry created -> notification sent |
| `POST /v1/reports` | Create report -> verify DB row -> verify re-moderation at threshold |
| Auth flow | Verify authorizer -> handler pipeline with valid/invalid/expired tokens |

### 4.4 Database Query Testing with Test Fixtures

#### Fixture Strategy

```
backend/tests/fixtures/
    users.sql              -- Seed test users (regular, moderator, admin roles)
    recordings.sql         -- Seed recordings at known coordinates in all statuses
    moderation_records.sql -- Seed moderation audit trail entries
    plays.sql              -- Seed play events for counter tests
    likes.sql              -- Seed likes for counter/toggle tests
    reports.sql            -- Seed reports for threshold tests
    tags.sql               -- Seed tags and recording_tags
    factories.ts           -- TypeScript factory functions with Kysely
```

- Fixtures loaded before each test suite via transaction rollback pattern (begin transaction -> load fixtures -> run tests -> rollback).
- Fixtures include:
  - Recordings at specific lat/lng pairs for spatial query verification.
  - Recordings in every status (`pending_upload`, `pending_moderation`, `approved`, `rejected`, `pending_review`).
  - Users with all role types (`user`, `moderator`, `admin`).
  - Recordings from multiple users for isolation tests.
  - Edge case coordinates: prime meridian (0,0), international date line (180/-180), poles (90/-90).
  - Recordings with various `category` values.
  - Soft-deleted recordings to verify filtering.

#### PostGIS-Specific Tests

| Test | Description |
|------|-------------|
| SRID consistency | All points stored as `GEOGRAPHY(Point, 4326)` |
| Distance accuracy | Known distance between two points matches `ST_Distance` result within 1m tolerance |
| Antimeridian query | Recordings near 180th meridian found correctly |
| Equator query | Recordings near (0, 0) found correctly |
| Pole proximity | Recordings near poles handled without error |
| GiST index usage | `EXPLAIN ANALYZE` confirms GiST index scan, not sequential scan, for nearby queries with `idx_recordings_location` |
| Partial index usage | `EXPLAIN ANALYZE` confirms `idx_recordings_status_approved` partial index used for discovery |
| Composite index usage | `EXPLAIN ANALYZE` confirms `idx_recordings_user_id` used for `mine` queries |

### 4.5 Moderation Pipeline Testing

The moderation pipeline (AWS Step Functions Standard Workflow) is tested at three levels:

#### Unit: Individual Step Logic

| Step | Tests |
|------|-------|
| `start-transcription.ts` | Correct S3 audio URI passed; language code `en-US`; job name includes recording_id; output bucket configured |
| `store-transcript.ts` | Reads Transcribe JSON output from S3; extracts plain text; stores in `recordings.transcript` column |
| `classify-content.ts` | Transcript sent to OpenAI Moderation API; response parsed; per-category scores extracted (`hate`, `hate/threatening`, `harassment`, `self-harm`, `sexual`, `violence`); raw result stored in `recordings.moderation_scores` JSONB |
| `evaluate-decision.ts` | Per-category threshold evaluation; auto-approve (all < 0.3); auto-reject (any > 0.7, or > 0.5 for hate/threatening and self-harm); human review (in between); correct moderation_records audit entry created |
| `validate-audio.ts` | File header check (AAC/M4A magic bytes); size < 10MB; duration within tolerance of declared value; rejects non-audio files |
| `send-notification.ts` | Correct APNs payload per outcome; user device token lookup; SNS publish call |

#### Integration: Step Functions Workflow

Using Step Functions Local (Docker) or mocked Step Functions:

| Test | Description |
|------|-------------|
| Happy path (approved) | Audio uploaded -> validated -> transcribed -> clean classification (all scores < 0.3) -> S3 copy to `audio/approved/` -> status = `approved` -> push notification |
| Happy path (rejected) | Audio -> transcribed -> explicit classification (score > 0.7) -> S3 copy to `audio/rejected/` -> status = `rejected` -> push notification |
| Human review path | Audio -> transcribed -> uncertain (scores between 0.3-0.7) -> SQS message with task token -> status = `pending_review` |
| Transcription failure + retry | Simulate Transcribe failure -> verify retry (max 2 attempts, backoff 2x) -> eventual success |
| OpenAI API failure + retry | Simulate Moderation API failure -> verify retry with backoff |
| Audio validation failure | Invalid file format detected -> status = `rejected` -> user notified |
| End-to-end timing | Full pipeline completes within 2 minutes for a 60-second audio file |
| Human review completion via task token | Admin submits decision -> Step Functions resumes via `SendTaskSuccess` -> routes to approved/rejected -> notification |

#### Human Review Workflow Tests

| Test | Description |
|------|-------------|
| Queue visibility | Pending review recordings appear in `GET /v1/admin/moderation/queue` ordered oldest first |
| Approve action | `POST /v1/admin/moderation/{id}/decision` with `approved` -> status = `approved` -> moderation_records entry (action = `manual_approve`, actor_type = `moderator`) -> notification sent |
| Reject action | Decision = `rejected` -> status = `rejected` -> moderation_records entry (action = `manual_reject`) -> notification with reason |
| Idempotency | Double-approve or double-reject does not cause errors or duplicate notifications |
| Audit trail completeness | Every status transition has a corresponding `moderation_records` row with correct `from_status`, `to_status`, `actor_id` |
| Reviewer notes | Optional `notes` field stored in moderation_records |
| Stats endpoint | `GET /v1/admin/moderation/stats` returns accurate counts for pending, reviewed, auto-approved, auto-rejected, avg review time |

#### Re-Moderation (Report-Triggered) Tests

| Test | Description |
|------|-------------|
| Under threshold | 2 reports from distinct users -> recording remains `approved` |
| At threshold | 3rd report from distinct user -> recording status changes to `pending_review`; removed from discovery; SQS message sent with reports attached |
| Duplicate report | Same user reports twice -> 409 `DUPLICATE_REPORT`; count stays at 1 |
| Report on own recording | Returns error (users cannot report their own recordings) |

### 4.6 Load and Stress Testing

Tool: Artillery or k6.

| Scenario | Configuration | Success Criteria |
|----------|--------------|------------------|
| **Discovery query baseline** | 100 concurrent users querying nearby recordings against 100K recordings in DB | p95 response time < 200ms |
| **Discovery query stress** | 500 concurrent users, sustained for 5 minutes | No errors; p99 < 500ms; DB CPU < 80% |
| **Recording upload burst** | 50 concurrent uploads in 10 seconds | All pre-signed URLs generated; no S3 throttling |
| **Mixed workload** | 70% discovery, 20% playback URL, 10% recording creation | p95 < 300ms across all endpoints |
| **Moderation pipeline throughput** | 100 recordings submitted in 1 minute | All enter pipeline; no SQS dead letters |
| **Cold start measurement** | First request after 15 minutes idle (no provisioned concurrency) | Lambda cold start < 3 seconds |
| **Database connection pool (RDS Proxy)** | Sustained load with 200 concurrent Lambda invocations | No connection exhaustion errors; RDS Proxy multiplexes correctly |
| **API Gateway throttling** | Exceed per-user rate limits | 429 returned with correct `Retry-After` header; legitimate traffic unaffected |

#### Geospatial Query Performance Benchmarks

| Dataset Size | Query Type | Target p95 |
|-------------|-----------|------------|
| 1,000 recordings | `ST_DWithin` 500m radius | < 20ms |
| 10,000 recordings | `ST_DWithin` 500m radius | < 50ms |
| 100,000 recordings | `ST_DWithin` 500m radius | < 100ms |
| 1,000,000 recordings | `ST_DWithin` 500m radius | < 200ms |

Additional geospatial scenarios:
- Geographically clustered data (all recordings in one city) vs. evenly distributed.
- Large radius (5km) with high density area.
- Query near prime meridian, antimeridian, and poles.

---

## 5. API Contract Testing

### 5.1 Approach: Consumer-Driven Contracts with Pact

The iOS app (consumer) defines expected API interactions. The backend (provider) verifies it satisfies those contracts. The OpenAPI 3.1 specification in BACKEND.md serves as the source of truth.

### 5.2 Contract Scope

| Endpoint | Verified Fields |
|----------|----------------|
| `POST /v1/auth/register` | Request: `{ display_name }`. Response 201: `{ id, display_name, created_at }`. Response 409 on duplicate. |
| `POST /v1/recordings` | Request body schema per Zod. Response 201: `{ id, upload_url, upload_expires_at, status: "pending_upload" }` |
| `POST /v1/recordings/{id}/upload-complete` | Response 200: `{ id, status: "pending_moderation" }`. Response 409 if wrong status. |
| `GET /v1/recordings/{id}` | Response: `{ id, user_id, display_name, subject, description, latitude, longitude, duration_sec, status, created_at }` |
| `GET /v1/recordings/nearby` | Response: `{ recordings: [...], next_cursor }`. Each item has `id`, `subject`, `distance_m`, `display_name`, `latitude`, `longitude`. Sorted by `distance_m`. |
| `GET /v1/recordings/{id}/playback` | Response: `{ playback_url, expires_at, duration_sec, format: "aac" }` |
| `GET /v1/recordings/mine` | Response: `{ recordings: [...], next_cursor }`. Includes all status values. |
| `GET /v1/users/me` | Response: `{ id, display_name, recording_count, created_at }` |
| `PUT /v1/users/me` | Request: `{ display_name }`. Response 200: updated user. |
| `POST /v1/reports` | Request: `{ recording_id, reason, description? }`. Response 201: `{ id, recording_id, status: "submitted", created_at }` |
| Error responses | Nested format: `{ "error": { "code": "ERROR_CODE", "message": "...", "details": {} } }`. Verified for 400, 401, 403, 404, 409, 413, 422, 429. |

### 5.3 Contract Testing Workflow

1. iOS developer writes a Pact consumer test defining expected request/response for each interaction.
2. Pact generates a contract file (JSON).
3. Contract file committed to the repository (or published to a Pact Broker).
4. Backend CI runs Pact provider verification against the contract.
5. Contract violations fail the backend build, preventing incompatible deployments.

### 5.4 Schema Validation

In addition to Pact contracts:

- **Backend**: Zod schemas validate all incoming request bodies at runtime. Validation errors return 400 with `VALIDATION_ERROR` code and `details.fields` array.
- **iOS (debug)**: API client validates response bodies against expected Codable types in debug builds. Assertion failures for schema violations during development.
- **OpenAPI spec**: The OpenAPI 3.1 specification in BACKEND.md is the canonical schema reference. Contract tests verify consistency between the spec and actual behavior.

---

## 6. Content Moderation Test Cases

### 6.1 Audio Content Categories

| Category | Input | Expected Outcome |
|----------|-------|-----------------|
| Clean speech | Person describing a historical building | All scores < 0.3 -> `AUTO_APPROVE` -> `approved` |
| Explicit language | Audio containing hate speech | `hate` score > 0.7 -> `AUTO_REJECT` -> `rejected` |
| Sexual content | Sexually explicit audio | `sexual` score > 0.7 -> `AUTO_REJECT` -> `rejected` |
| Violence | Threats or descriptions of violence | `violence` score > 0.7 -> `AUTO_REJECT` -> `rejected` |
| Self-harm | Content promoting self-harm | `self-harm` score > 0.5 (lower threshold) -> `AUTO_REJECT` -> `rejected` |
| Threatening | Hateful threatening content | `hate/threatening` score > 0.5 (lower threshold) -> `AUTO_REJECT` -> `rejected` |
| Mild language | Casual mild profanity in storytelling | Some scores in 0.3-0.7 range -> `HUMAN_REVIEW` -> `pending_review` |
| Controversial opinion | Political opinion, no hate speech | All scores < 0.3 -> `AUTO_APPROVE` -> `approved` |
| Background music | Speech with background music | Transcript reflects speech only; classified normally |
| Singing | Person singing a song | Lyrics transcribed; classified if clean |

### 6.2 Edge Cases

| Case | Input | Expected Behavior |
|------|-------|-------------------|
| **Silence** | 30 seconds of silence | Empty transcript -> routed to `HUMAN_REVIEW` |
| **White noise** | 60 seconds of static/wind | Transcript empty or gibberish -> `HUMAN_REVIEW` |
| **Very short audio** | 1 second of speech | Transcription attempted; may produce partial text; classified if possible |
| **Maximum length** | Exactly 300 seconds | Accepted; processed normally; `chk_recordings_duration` constraint passes |
| **Over maximum** | 301 seconds | Rejected at API level (Zod validation: `duration_sec` max 300); never enters moderation |
| **Non-speech audio** | Dog barking, car horn | Empty/gibberish transcript -> `HUMAN_REVIEW` |
| **Multilingual** | Spanish narration | Transcribe auto-detects language (future: `IdentifyLanguage`); moderate transcript |
| **Code-switching** | English with Spanish phrases | Transcribe handles mixed language; moderation evaluates full text |
| **Whispered speech** | Very quiet speech | Transcription may be inaccurate; uncertain scores likely -> `HUMAN_REVIEW` |
| **Multiple speakers** | Two people conversing | Transcribed as single stream; moderated normally |
| **Audio with beeps** | Self-censored explicit content | Transcript may contain "[inaudible]"; `HUMAN_REVIEW` if uncertain |
| **Invalid audio file** | Non-audio file with .aac extension | `validate-audio.ts` rejects (checks file header magic bytes); status -> `rejected` before moderation |
| **Oversized file** | 15 MB audio file | Pre-signed URL has 10MB `Content-Length` constraint; upload fails at S3 level |

### 6.3 Workflow State Machine Validation

All valid state transitions (from DATABASE.md Section 6.2):

```
pending_upload      -> pending_moderation   (S3 upload confirmed via upload-complete endpoint)
pending_moderation  -> approved             (auto-approved by classifier, all scores < 0.3)
pending_moderation  -> rejected             (auto-rejected by classifier, any score above reject threshold)
pending_moderation  -> pending_review       (uncertain classification, scores in middle range)
pending_review      -> approved             (human moderator approves)
pending_review      -> rejected             (human moderator rejects)
approved            -> rejected             (admin action: report resolved with removal, 3+ reports)
```

Invalid transitions that must be rejected:

| From | To | Why Invalid |
|------|----|-------------|
| `approved` | `pending_moderation` | Cannot re-moderate approved content (except via report threshold) |
| `rejected` | `approved` | Must go through appeal process (future feature) |
| `pending_upload` | `approved` | Cannot skip moderation |
| `pending_upload` | `rejected` | Must go through validation + moderation (except audio validation failure) |
| Any status | `pending_upload` | Upload status is initial only |

Tests verify:
- Each valid transition updates the DB correctly and writes a `moderation_records` audit entry.
- Each invalid transition is rejected with an appropriate error.
- `updated_at` timestamp updated on every status change (via trigger).
- S3 object moved to correct prefix (`audio/approved/` or `audio/rejected/`) on terminal transitions.
- Push notification sent only on terminal transitions (approved/rejected).

---

## 7. Performance Testing

### 7.1 Upload/Download Performance

| Test | Method | Target |
|------|--------|--------|
| Upload 1 MB audio file (~1 min AAC) to S3 via pre-signed URL | Measure from iOS client on LTE (simulated) | < 5 seconds |
| Upload 2.4 MB audio file (max ~5 min AAC at 64kbps) | Same | < 10 seconds |
| Download/stream 1 MB audio from CloudFront | Measure TTFB + full download from edge PoP | TTFB < 100ms; full < 3s |
| Concurrent uploads (10 users) | Backend: measure pre-signed URL generation latency | < 200ms per URL generation |
| Background upload completion | Upload continues when app is backgrounded (URLSession background config) | Upload completes; `upload-complete` called on resume |

### 7.2 API Response Time Targets

| Endpoint | p50 | p95 | p99 |
|----------|-----|-----|-----|
| `POST /v1/recordings` | 100ms | 200ms | 500ms |
| `POST /v1/recordings/{id}/upload-complete` | 100ms | 200ms | 500ms |
| `GET /v1/recordings/nearby` | 50ms | 150ms | 300ms |
| `GET /v1/recordings/{id}` | 30ms | 100ms | 200ms |
| `GET /v1/recordings/{id}/playback` | 50ms | 150ms | 300ms |
| `GET /v1/recordings/mine` | 50ms | 150ms | 300ms |
| `GET /v1/users/me` | 30ms | 100ms | 200ms |
| `POST /v1/reports` | 50ms | 150ms | 300ms |
| `POST /v1/admin/moderation/{id}/decision` | 100ms | 200ms | 500ms |
| Lambda Authorizer (cold) | - | - | < 500ms |
| Lambda Authorizer (cached, 5 min) | 0ms | 0ms | 0ms (API GW cached) |

### 7.3 Geospatial Query Scaling

See Section 4.6 for detailed benchmarks. Key tests:
- Verify GiST index is used at all dataset sizes (`EXPLAIN ANALYZE`).
- Measure query time as dataset grows from 1K to 1M recordings.
- Test with geographically clustered data (e.g., all recordings in one city) and evenly distributed data.
- Verify partial index `idx_recordings_status_approved` reduces scan for discovery queries.

### 7.4 Concurrency Tests

| Scenario | Test |
|----------|------|
| Simultaneous discovery queries | 200 users query nearby recordings at same coordinates concurrently |
| Simultaneous uploads | 50 users upload recordings at the same time |
| Read/write contention | Users discovering while others upload to same geographic area |
| Moderation pipeline concurrency | 50 recordings enter moderation pipeline simultaneously |
| Like/unlike race | Two users like/unlike the same recording concurrently; counters remain consistent |
| Report threshold race | Three users report simultaneously; re-moderation triggered exactly once |

---

## 8. Security Testing Checklist

### 8.1 Authentication and Authorization

- [ ] Unauthenticated requests to all endpoints return 401 `UNAUTHORIZED`
- [ ] Expired JWT tokens return 401
- [ ] JWT tokens with invalid signatures return 401
- [ ] JWT tokens from wrong Firebase project (wrong `aud`/`iss`) return 401
- [ ] User A cannot read User B's non-approved recordings (returns 404, not 403)
- [ ] User A cannot delete User B's recordings (returns 404)
- [ ] User A cannot modify User B's profile
- [ ] Non-admin users get 403 on `GET /v1/admin/moderation/queue`
- [ ] Non-admin users get 403 on `POST /v1/admin/moderation/{id}/decision`
- [ ] Admin custom claim cannot be self-assigned by client (validated server-side against Firebase public keys)
- [ ] Lambda authorizer caches response for 5 minutes (verify via API Gateway config)

### 8.2 Input Validation

- [ ] SQL injection via subject/description fields (Kysely parameterized queries prevent this)
- [ ] SQL injection via latitude/longitude query parameters
- [ ] XSS in subject/description fields (stored XSS -- content served as JSON, not HTML)
- [ ] Oversized request body rejected (API Gateway payload size limit)
- [ ] Invalid JSON body returns 400 `VALIDATION_ERROR`, not 500 `INTERNAL_ERROR`
- [ ] Path traversal in recording ID parameter (UUID format enforced)
- [ ] Unicode/emoji in text fields handled correctly
- [ ] Null bytes in string fields rejected by Zod validation
- [ ] `duration_sec` boundary values: 0 (rejected), 1 (accepted), 300 (accepted), 301 (rejected)
- [ ] `latitude` boundary values: -90.001 (rejected), -90 (accepted), 90 (accepted), 90.001 (rejected)
- [ ] `radius` boundary values: 49 (rejected), 50 (accepted), 5000 (accepted), 5001 (rejected, 422 `INVALID_RADIUS`)

### 8.3 S3 and File Security

- [ ] Pre-signed upload URLs expire after 15 minutes
- [ ] Pre-signed upload URL scoped to correct S3 key (user cannot overwrite other files)
- [ ] Pre-signed upload URL only allows PUT (not GET or DELETE)
- [ ] Pre-signed URL enforces `Content-Type: audio/aac` and max `Content-Length: 10MB`
- [ ] Uploaded file validated (audio file header check in `validate-audio.ts`)
- [ ] S3 bucket has all four Block Public Access settings enabled
- [ ] CloudFront Origin Access Control (OAC) -- S3 only accessible via CloudFront
- [ ] CloudFront signed URLs expire correctly (1 hour)
- [ ] Audio files organized by status prefix (`audio/pending/`, `audio/approved/`, `audio/rejected/`)

### 8.4 Rate Limiting

- [ ] Discovery rate limit enforced: 60 req/min per user (burst: 10)
- [ ] Recording creation rate limit: 10 req/day per user (burst: 3)
- [ ] Playback URL rate limit: 120 req/min per user (burst: 20)
- [ ] General read endpoints: 100 req/min per user (burst: 20)
- [ ] Report rate limit: 10 req/hour per user (burst: 5)
- [ ] Rate limit response includes `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers
- [ ] 429 response includes `Retry-After` header and `RATE_LIMIT_EXCEEDED` error code

### 8.5 Data Privacy

- [ ] User's precise location never stored in database (only recording locations)
- [ ] Discovery endpoint does not reveal other users' current locations
- [ ] Discovery endpoint snaps coordinates to ~10m grid (prevents exact location scraping)
- [ ] Minimum discovery radius (50m) enforced
- [ ] Deleted recordings' audio files permanently deleted from S3 after 30 days (lifecycle policy)
- [ ] User account deletion anonymizes user row (`display_name` = 'Deleted User', `email` = NULL, `firebase_uid` = 'deleted_<uuid>')
- [ ] User account deletion deletes associated likes and plays
- [ ] User account deletion soft-deletes all recordings
- [ ] User account deletion deletes Firebase Auth account via Admin SDK
- [ ] No PII beyond Firebase UID, display name, and email stored

### 8.6 Transport Security

- [ ] All API communication over TLS 1.2+ (API Gateway HTTPS only)
- [ ] S3 pre-signed URLs use HTTPS
- [ ] CloudFront URLs use HTTPS (HTTP redirects to HTTPS)
- [ ] RDS connections use TLS (`rds.force_ssl = 1` parameter group)
- [ ] iOS app enforces ATS (App Transport Security)
- [ ] No sensitive data in URL query parameters (lat/lng are not sensitive per design; user tokens only in headers)

### 8.7 Infrastructure Security

- [ ] RDS in private subnets, no public IP
- [ ] Lambda in VPC private subnets with NAT Gateway for outbound
- [ ] VPC endpoints for S3 and Secrets Manager (avoids NAT for AWS services)
- [ ] Database credentials stored in Secrets Manager, rotated every 30 days
- [ ] Separate database roles: `app_user` (no DDL), `migration_user` (DDL)
- [ ] Lambda execution roles follow least privilege (per-function roles)
- [ ] GitHub Actions uses OIDC federation (no static AWS credentials)
- [ ] Production AWS account has SCPs restricting `DeleteBucket`, `DeleteDBInstance`
- [ ] CloudFormation stack termination protection enabled in production

---

## 9. CI/CD Integration

### 9.1 Pipeline Stages

```
Commit -> Lint/Format -> Unit Tests -> Integration Tests -> Contract Tests -> Build -> Deploy Staging -> E2E Tests -> Deploy Production
```

### 9.2 Stage Details

#### On Every Commit / PR

| Stage | What Runs | Gate Criteria | Time Budget |
|-------|-----------|---------------|-------------|
| **Lint & Format** | SwiftLint (iOS), ESLint + Prettier (backend TypeScript) | Zero warnings on new/changed code | < 1 min |
| **Type Check** | TypeScript strict mode (`tsc --noEmit`) | Zero errors | < 1 min |
| **Unit Tests (iOS)** | XCTest + Swift Testing suite, snapshot tests | All pass; coverage >= 80% on changed files | < 3 min |
| **Unit Tests (Backend)** | Vitest suite | All pass; coverage >= 80% on changed files | < 2 min |
| **CDK Snapshot Tests** | Infrastructure diff check | Snapshot matches or intentionally updated | < 1 min |
| **Contract Tests** | Pact consumer verification (iOS PR) or provider verification (backend PR) | All contracts satisfied | < 1 min |
| **Security Scan** | `npm audit` (backend), Swift package audit (iOS) | No critical/high vulnerabilities | < 1 min |

**Total PR check time target: < 10 minutes.**

#### On Merge to Main

| Stage | What Runs | Gate Criteria | Time Budget |
|-------|-----------|---------------|-------------|
| **Full Unit + Integration Tests** | All unit tests + DB integration tests (Testcontainers with PostGIS) | All pass | < 10 min |
| **Build iOS App** | Xcode 16 archive build (`xcodebuild`) | Build succeeds | < 5 min |
| **Deploy to Staging** | CDK deploy to staging AWS account (OIDC auth) | Deployment succeeds | < 5 min |
| **Run DB Migrations** | `npm run migrate:up` against staging DB | Migrations succeed | < 1 min |
| **E2E Smoke Tests** | Core flows against staging (record, discover, play) | All pass | < 10 min |
| **Smoke Test** | Hit health check endpoint on staging | 200 OK | < 1 min |

**Total merge pipeline time target: < 32 minutes.**

#### Before Production Deploy (Manual Promotion)

| Stage | What Runs | Gate Criteria |
|-------|-----------|---------------|
| **Full E2E Suite** | All XCUITest flows against staging | All pass |
| **Load Test (short)** | 5-minute Artillery/k6 run against staging | p95 within targets (Section 7.2) |
| **Security Scan** | `npm audit`, Snyk or Trivy container scan | No critical/high vulnerabilities |
| **CDK Diff Review** | `cdk diff` output reviewed for unexpected changes | Approved by tech lead |
| **Manual QA Sign-off** | QA engineer verifies release candidate on staging | Sign-off recorded in deploy ticket |

#### Nightly / Weekly

| Cadence | What Runs |
|---------|-----------|
| Nightly | Full load test suite (30 min, larger dataset) against staging |
| Nightly | Dependency vulnerability scan (all packages) |
| Weekly | Full security test suite (OWASP checklist, Section 8) |
| Weekly | Snapshot test reference update review |
| Weekly | Moderation accuracy audit (false positive/negative rates) |

### 9.3 CI Environment

| Component | Tool |
|-----------|------|
| CI/CD Platform | GitHub Actions |
| iOS Build | GitHub-hosted macOS runner (Xcode 16) or self-hosted Mac |
| Backend Tests | GitHub-hosted Linux runner (Ubuntu) |
| Integration Tests | Linux runner with Docker (Testcontainers: PostgreSQL 16 + PostGIS 3.4) |
| AWS Authentication | OIDC federation (no static credentials) |
| Staging Environment | Dedicated AWS account (`hearhere-staging`), deployed via CDK |
| Production Environment | Dedicated AWS account (`hearhere-prod`), manual promotion |
| Test Results | JUnit XML format for GitHub Actions test reporting |
| Coverage Reports | Uploaded as PR comment (Codecov or similar) |

### 9.4 iOS CI Workflow

```yaml
# Triggers: push to main, PRs targeting main (changes in ios/)
Steps:
  1. Checkout code
  2. Select Xcode 16
  3. Resolve Swift packages (SPM)
  4. Build (xcodebuild -scheme HearHere -destination 'platform=iOS Simulator,name=iPhone 16')
  5. Run unit tests + snapshot tests
  6. Run UI tests (on merge to main only)
  7. Generate coverage report
```

### 9.5 Backend CI Workflow

```yaml
# Triggers: push to main, PRs targeting main
Steps:
  1. Checkout code
  2. Setup Node.js 20
  3. Install dependencies (npm ci)
  4. Lint (ESLint) + format check (Prettier)
  5. Type check (tsc --noEmit)
  6. Unit tests (vitest run --coverage)
  7. Integration tests (vitest run --config vitest.integration.config.ts)
     # Requires Docker for Testcontainers
  8. Security scan (npm audit)
```

### 9.6 Infrastructure CI Workflow

```yaml
# Triggers: push to main, PRs targeting main (changes in infra/)
Steps:
  1. Checkout code
  2. Setup Node.js 20
  3. Install CDK dependencies (npm ci)
  4. CDK synth (validate templates compile)
  5. CDK diff (post infrastructure changes as PR comment)
  6. CDK snapshot tests (vitest)
```

---

## 10. Test Data Management

### 10.1 Principles

- Test data is code. Seed scripts and fixtures are version-controlled.
- No production data in test environments.
- Test data is reproducible: running the seed script always produces the same state.
- Personally identifiable data is never used in tests; use synthetic data only.

### 10.2 Test Data Layers

#### Unit Tests
- Data is created inline within each test. No shared mutable state between tests.
- Factory functions generate valid model instances with sensible defaults and overridable fields.

```swift
// iOS example
func makeRecording(
    id: UUID = UUID(),
    subject: String = "Test Recording",
    latitude: Double = 37.7749,
    longitude: Double = -122.4194,
    status: ModerationStatus = .approved,
    durationSec: Int = 30
) -> Recording { ... }
```

```typescript
// Backend example (TypeScript)
function buildRecording(overrides: Partial<Recording> = {}): Recording {
  return {
    id: randomUUID(),
    user_id: 'test-user-uuid',
    subject: 'Test Recording',
    latitude: 37.7749,
    longitude: -122.4194,
    status: 'approved',
    duration_sec: 30,
    audio_s3_key: 'audio/approved/test.aac',
    audio_format: 'aac',
    play_count: 0,
    like_count: 0,
    created_at: new Date().toISOString(),
    ...overrides,
  };
}
```

#### Integration Tests
- SQL fixture files loaded per test suite (see Section 4.4).
- Transaction rollback pattern ensures test isolation.
- Kysely factory functions create records via the actual query builder for type safety.

#### Staging Environment
- Seed script populates staging with:
  - 5 test user accounts (roles: 2 regular, 1 moderator, 1 admin, 1 new user with no recordings).
  - 100 recordings at known locations (San Francisco, New York, London) in all statuses.
  - 10 recordings in the human review queue with varying moderation scores.
  - Play and like events for counter testing.
  - Tags applied to recordings.
  - Sample reports at various stages.
- Seed script is idempotent (can be re-run safely via `INSERT ... ON CONFLICT DO NOTHING`).

#### Load Testing
- Generator script creates N recordings with randomized but valid coordinates within target regions.
- Separate from staging seed data; loaded into a dedicated load-test database instance.

### 10.3 Audio Test Files

A set of reference audio files stored in the test suite:

| File | Content | Duration | Format | Purpose |
|------|---------|----------|--------|---------|
| `clean_speech.aac` | Person describing a park | 30s | AAC 64kbps mono | Happy path moderation |
| `silence.aac` | Pure silence | 30s | AAC | Edge case: empty transcript |
| `short.aac` | One word | 1s | AAC | Minimum duration edge case |
| `max_duration.aac` | Continuous speech | 300s | AAC | Maximum duration boundary |
| `noise.aac` | Wind/traffic sounds | 15s | AAC | Non-speech edge case |
| `multilingual.aac` | Spanish narration | 20s | AAC | Language detection test |
| `not_audio.aac` | Text file with .aac extension | N/A | Invalid | Audio validation rejection test |

These files are small and committed to the repository under `backend/tests/fixtures/audio/`.

---

## 11. Bug Tracking and Regression Workflow

### 11.1 Bug Lifecycle

```
Reported -> Triaged -> Reproduced (test written) -> Fixed -> Verified -> Closed
```

| Stage | Action | Responsible |
|-------|--------|-------------|
| **Reported** | Bug filed in GitHub Issues with template | Anyone |
| **Triaged** | Severity assigned (P0-P3); assigned to engineer | QA / Tech Lead |
| **Reproduced** | Failing test written that demonstrates the bug | Assigned engineer |
| **Fixed** | Code fix implemented; failing test now passes | Assigned engineer |
| **Verified** | QA verifies fix in staging; no regressions | QA engineer |
| **Closed** | Merged to main; deployed to staging (auto) then production (manual) | Automated |

### 11.2 Bug Report Template

```markdown
## Bug Report

**Summary**: [One-line description]

**Severity**: P0 (app crash/data loss) | P1 (feature broken) | P2 (degraded experience) | P3 (cosmetic)

**Steps to Reproduce**:
1. ...
2. ...
3. ...

**Expected Behavior**: ...

**Actual Behavior**: ...

**Environment**: iOS version, device model, backend stage (dev/staging/prod), app version

**Screenshots/Logs**: [Attach]

**Labels**: `bug`, `P0`/`P1`/`P2`/`P3`, `ios`/`backend`/`infra`
```

### 11.3 Severity Definitions and SLAs

| Severity | Definition | Response Time | Resolution Time |
|----------|-----------|---------------|-----------------|
| **P0** | App crash, data loss, security vulnerability, moderation bypass | Immediate | < 4 hours |
| **P1** | Core feature broken (cannot record, discover, or play) | < 2 hours | < 24 hours |
| **P2** | Feature degraded but workaround exists | < 8 hours | Next sprint |
| **P3** | Cosmetic, minor UX issue | Next triage | Backlog |

### 11.4 Regression Prevention

- Every bug fix must include a test that would have caught the bug.
- These regression tests are tagged/labeled (e.g., `@regression`) for easy identification.
- The full regression suite runs on every PR and on merge to main.
- Regression test count is tracked as a quality metric (it should grow over time as bugs are found and fixed).

### 11.5 Release Qualification

Before each App Store release:

1. All automated tests pass (unit, integration, contract, E2E, snapshot).
2. Full manual QA pass on staging (checklist in release ticket).
3. No open P0 or P1 bugs.
4. Load test results reviewed (no degradation vs. previous release).
5. Security scan clean (no new critical/high vulnerabilities).
6. TestFlight beta tested for minimum 48 hours with no new crash reports.
7. Moderation pipeline verified: submit test recordings in each content category and verify correct outcomes.
8. Accessibility audit: VoiceOver walkthrough of all critical flows.

---

## 12. Test Directory Structure

```
hear-here/
+-- ios/
|   +-- HearHere/
|       +-- Tests/
|           +-- UnitTests/
|           |   +-- ViewModels/
|           |   |   +-- RecordingViewModelTests.swift
|           |   |   +-- MapViewModelTests.swift
|           |   |   +-- PlaybackViewModelTests.swift
|           |   |   +-- AuthViewModelTests.swift
|           |   |   +-- ProfileViewModelTests.swift
|           |   |   +-- SettingsViewModelTests.swift
|           |   +-- Services/
|           |   |   +-- APIClientTests.swift
|           |   |   +-- LocationServiceTests.swift
|           |   |   +-- AudioRecorderTests.swift
|           |   |   +-- AudioPlayerTests.swift
|           |   |   +-- UploadManagerTests.swift
|           |   |   +-- AuthServiceTests.swift
|           |   |   +-- CacheManagerTests.swift
|           |   +-- Models/
|           |   |   +-- RecordingTests.swift
|           |   |   +-- UserTests.swift
|           |   |   +-- AppErrorTests.swift
|           |   +-- Coordinators/
|           |   |   +-- AppCoordinatorTests.swift
|           |   |   +-- DiscoveryCoordinatorTests.swift
|           |   |   +-- RecordingCoordinatorTests.swift
|           |   +-- Mocks/
|           |       +-- MockAPIClient.swift
|           |       +-- MockAudioRecorder.swift
|           |       +-- MockAudioPlayer.swift
|           |       +-- MockLocationService.swift
|           |       +-- MockAuthService.swift
|           |       +-- MockUploadManager.swift
|           |       +-- MockNetworkMonitor.swift
|           +-- SnapshotTests/
|           |   +-- RecordingViewSnapshotTests.swift
|           |   +-- MapViewSnapshotTests.swift
|           |   +-- NearbyListViewSnapshotTests.swift
|           |   +-- PlaybackViewSnapshotTests.swift
|           |   +-- MiniPlayerViewSnapshotTests.swift
|           |   +-- ProfileViewSnapshotTests.swift
|           |   +-- RecordingMetadataViewSnapshotTests.swift
|           |   +-- RecordingConfirmationViewSnapshotTests.swift
|           |   +-- StatusBadgeSnapshotTests.swift
|           |   +-- __Snapshots__/       # Reference images
|           +-- UITests/
|               +-- OnboardingFlowUITests.swift
|               +-- RecordingFlowUITests.swift
|               +-- DiscoveryFlowUITests.swift
|               +-- PlaybackFlowUITests.swift
|               +-- ProfileFlowUITests.swift
|               +-- SettingsFlowUITests.swift
+-- backend/
|   +-- tests/
|       +-- unit/
|       |   +-- recordings/
|       |   |   +-- create.test.ts
|       |   |   +-- get.test.ts
|       |   |   +-- delete.test.ts
|       |   |   +-- mine.test.ts
|       |   |   +-- upload-complete.test.ts
|       |   |   +-- playback.test.ts
|       |   +-- discovery/
|       |   |   +-- nearby.test.ts
|       |   +-- users/
|       |   |   +-- register.test.ts
|       |   |   +-- get-me.test.ts
|       |   |   +-- update-me.test.ts
|       |   +-- reports/
|       |   |   +-- create.test.ts
|       |   +-- admin/
|       |   |   +-- queue.test.ts
|       |   |   +-- decision.test.ts
|       |   |   +-- stats.test.ts
|       |   +-- authorizer/
|       |   |   +-- authorizer.test.ts
|       |   +-- moderation/
|       |   |   +-- validate-audio.test.ts
|       |   |   +-- start-transcription.test.ts
|       |   |   +-- store-transcript.test.ts
|       |   |   +-- classify-content.test.ts
|       |   |   +-- evaluate-decision.test.ts
|       |   |   +-- send-notification.test.ts
|       |   +-- schemas/
|       |       +-- recording.test.ts
|       |       +-- user.test.ts
|       |       +-- report.test.ts
|       +-- integration/
|       |   +-- api/
|       |   |   +-- recordings.integration.test.ts
|       |   |   +-- discovery.integration.test.ts
|       |   |   +-- users.integration.test.ts
|       |   |   +-- reports.integration.test.ts
|       |   |   +-- admin.integration.test.ts
|       |   +-- db/
|       |   |   +-- spatial-queries.integration.test.ts
|       |   |   +-- recording-crud.integration.test.ts
|       |   |   +-- status-transitions.integration.test.ts
|       |   |   +-- counters.integration.test.ts
|       |   |   +-- likes.integration.test.ts
|       |   |   +-- reports-threshold.integration.test.ts
|       |   |   +-- user-deletion.integration.test.ts
|       |   |   +-- moderation-audit.integration.test.ts
|       |   |   +-- index-usage.integration.test.ts
|       |   +-- moderation/
|       |       +-- pipeline.integration.test.ts
|       +-- contract/
|       |   +-- pact/
|       |       +-- provider-verification.test.ts
|       |       +-- pacts/            # Contract JSON files from iOS consumer
|       +-- load/
|       |   +-- discovery-load.yml    # Artillery scenario
|       |   +-- upload-load.yml
|       |   +-- mixed-workload.yml
|       |   +-- geospatial-scale.yml
|       +-- security/
|       |   +-- auth-bypass.test.ts
|       |   +-- input-validation.test.ts
|       |   +-- s3-access.test.ts
|       |   +-- rate-limiting.test.ts
|       +-- fixtures/
|           +-- audio/
|           |   +-- clean_speech.aac
|           |   +-- silence.aac
|           |   +-- short.aac
|           |   +-- max_duration.aac
|           |   +-- noise.aac
|           |   +-- multilingual.aac
|           |   +-- not_audio.aac
|           +-- users.sql
|           +-- recordings.sql
|           +-- moderation_records.sql
|           +-- plays.sql
|           +-- likes.sql
|           +-- reports.sql
|           +-- tags.sql
|           +-- factories.ts
+-- infra/
    +-- test/
        +-- network-stack.test.ts
        +-- storage-stack.test.ts
        +-- database-stack.test.ts
        +-- api-stack.test.ts
        +-- moderation-stack.test.ts
        +-- cdn-stack.test.ts
        +-- notification-stack.test.ts
        +-- monitoring-stack.test.ts
        +-- dns-stack.test.ts
        +-- snapshots/                # CDK snapshot files
```

---

## 13. Metrics and Quality Dashboard

### Key Quality Metrics (tracked per sprint/release)

| Metric | Target | How Measured |
|--------|--------|--------------|
| Unit test pass rate | 100% | CI reports (GitHub Actions) |
| Code coverage (unit) | >= 80% | Vitest coverage (backend), Xcode coverage (iOS) |
| Integration test pass rate | 100% | CI reports |
| E2E test pass rate | >= 98% (2% flake budget) | CI reports |
| Mean time to detect (bug age) | < 1 sprint | Bug creation date vs. commit that introduced it |
| Mean time to fix (P0/P1) | < 24 hours | Bug timestamps |
| Regression test count | Growing | Test suite tag counts |
| Flaky test count | 0 | CI flake tracker |
| Moderation false positive rate | < 5% | Moderation audit (human review of auto-approved) |
| Moderation false negative rate | < 1% | Moderation audit (reports on auto-approved content) |
| API p95 latency | Per Section 7.2 targets | CloudWatch custom metrics |
| Discovery query p95 at current dataset size | Per Section 4.6 targets | CloudWatch `DiscoveryQueryLatency` |
| Lambda cold start rate | < 5% of invocations | CloudWatch `ColdStart` metric |
| Moderation pipeline end-to-end time | < 2 minutes (median) | CloudWatch `ModerationLatency` |
| SQS human review queue depth | < 100 at end of business day | CloudWatch alarm |
| RDS CPU utilization (production) | < 80% sustained | CloudWatch alarm |
