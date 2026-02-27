# Hear Here — Backend API & Service Design

## 1. Technology Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Runtime | **Node.js 20 (TypeScript)** | Type safety, excellent Azure SDK support, fast Azure Functions cold starts, shared language with Bicep tooling |
| Framework | **None (raw Azure Functions handlers)** | Minimal cold-start overhead; Azure API Management handles routing, auth, and rate limiting — a framework adds no value |
| Database Client | **Kysely** | Type-safe SQL query builder for PostgreSQL; no ORM magic, full PostGIS support via raw SQL escape hatch |
| Validation | **Zod** | Runtime request validation with TypeScript type inference |
| API Gateway | **Azure API Management (Consumption tier)** | Built-in JWT validation policies, rate limiting, analytics; pay-per-call |
| Auth | **Firebase Auth** (validated server-side) | JWT validation via Azure API Management `validate-jwt` policy against Firebase JWKS |
| Infrastructure | **Bicep** | Azure-native IaC; concise, type-safe, first-class VS Code tooling |

### Why Node.js over Python?

Both are viable Azure Functions runtimes. Node.js wins here because: (1) the Bicep tooling and Azure Functions Core Tools have excellent TypeScript support — one language across the stack reduces context switching, (2) cold-start performance is slightly better for Node.js on the Consumption plan, (3) TypeScript provides end-to-end type safety from request validation to database queries.

---

## 2. API Versioning Strategy

**Approach:** URL path versioning — `/v1/...`

All endpoints are prefixed with `/v1`. When breaking changes are needed:

1. Deploy `/v2` endpoints alongside `/v1`
2. Mark `/v1` as deprecated in response headers (`Deprecation: true`, `Sunset: <date>`)
3. iOS app releases target the new version
4. Remove `/v1` after forced-update threshold (minimum 90 days after deprecation)

Non-breaking changes (new optional fields, new endpoints) are added to the current version without bumping.

---

## 3. Error Handling Conventions

### Standard Error Response Format

All errors return a consistent JSON structure:

```json
{
    "error": {
        "code": "RECORDING_NOT_FOUND",
        "message": "The requested recording does not exist.",
        "details": {}
    }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `error.code` | `string` | Machine-readable error code (SCREAMING_SNAKE_CASE) |
| `error.message` | `string` | Human-readable description |
| `error.details` | `object` | Optional structured data (e.g., validation errors) |

### HTTP Status Code Mapping

| Status | Usage |
|--------|-------|
| `400` | Validation errors, malformed requests |
| `401` | Missing or invalid authentication token |
| `403` | Authenticated but not authorized (e.g., deleting someone else's recording) |
| `404` | Resource not found |
| `409` | Conflict (e.g., duplicate report) |
| `413` | Audio file exceeds size limit |
| `422` | Semantically invalid request (e.g., radius > 5000m) |
| `429` | Rate limit exceeded |
| `500` | Internal server error |

### Validation Error Details

```json
{
    "error": {
        "code": "VALIDATION_ERROR",
        "message": "Request validation failed.",
        "details": {
            "fields": [
                { "field": "latitude", "message": "Must be between -90 and 90" },
                { "field": "subject", "message": "Required" }
            ]
        }
    }
}
```

### Error Codes Registry

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Request body/params failed validation |
| `UNAUTHORIZED` | 401 | Missing or invalid JWT |
| `FORBIDDEN` | 403 | User lacks permission for this action |
| `RECORDING_NOT_FOUND` | 404 | Recording ID does not exist |
| `USER_NOT_FOUND` | 404 | User profile not found |
| `RECORDING_NOT_PLAYABLE` | 403 | Recording not yet approved |
| `DUPLICATE_REPORT` | 409 | User already reported this recording |
| `UPLOAD_TOO_LARGE` | 413 | Audio file exceeds 10MB limit |
| `INVALID_RADIUS` | 422 | Radius outside allowed range |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `DAILY_UPLOAD_LIMIT` | 429 | Exceeded 10 recordings/day |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## 4. Rate Limiting & Abuse Prevention

### Rate Limits

Rate limiting is enforced at the Azure API Management level using `rate-limit-by-key` policies, keyed by Firebase UID extracted from the validated JWT.

| Endpoint Category | Rate Limit | Burst |
|-------------------|-----------|-------|
| Discovery (`GET /recordings/nearby`) | 60 req/min | 10 |
| Recording creation (`POST /recordings`) | 10 req/day | 3 |
| Playback URLs (`GET /recordings/{id}/playback`) | 120 req/min | 20 |
| General read endpoints | 100 req/min | 20 |
| Reports (`POST /reports`) | 10 req/hour | 5 |

### Rate Limit Response Headers

Every response includes:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1709000000
```

When exceeded:

```
HTTP/1.1 429 Too Many Requests
Retry-After: 30

{
    "error": {
        "code": "RATE_LIMIT_EXCEEDED",
        "message": "Too many requests. Please retry after 30 seconds.",
        "details": { "retry_after_seconds": 30 }
    }
}
```

### Abuse Prevention Measures

| Threat | Mitigation |
|--------|-----------|
| Spam recordings | 10 uploads/day/user + moderation pipeline |
| Location scraping | Discovery rate limit + minimum radius (50m) + no exact coordinates returned for nearby query (snapped to ~10m grid) |
| Fake reports | 10 reports/hour/user + minimum account age (24h) to report |
| Auth brute force | Firebase Auth handles login rate limiting natively |
| Large uploads | SAS URL with 10MB size constraint + 15-minute expiry |
| Audio format abuse | Blob Storage event triggers validation function; rejects non-audio files before moderation |
| Account farming | Sign in with Apple / Google only (no email/password) — harder to create throwaway accounts |

---

## 5. Complete API Endpoint Specifications

### 5.1 Authentication

Authentication is handled by Firebase Auth on the client. The backend validates Firebase JWTs via Azure API Management's `validate-jwt` inbound policy.

#### API Management JWT Validation

Every request passes through an API Management `validate-jwt` policy that:

1. Extracts the `Authorization: Bearer <token>` header
2. Validates the JWT signature against Firebase's public keys (JWKS endpoint, cached by APIM)
3. Verifies `iss`, `aud`, and `exp` claims
4. Extracts `uid` and custom claims (e.g., `admin: true`)
5. Returns `401` if validation fails
6. Passes `uid` downstream via a custom header `X-User-Id` (set in APIM policy via `set-header`)

```xml
<!-- API Management inbound policy -->
<validate-jwt header-name="Authorization" failed-validation-httpcode="401"
              require-scheme="Bearer">
    <openid-config url="https://securetoken.google.com/{firebase-project-id}/.well-known/openid-configuration" />
    <audiences>
        <audience>{firebase-project-id}</audience>
    </audiences>
    <issuers>
        <issuer>https://securetoken.google.com/{firebase-project-id}</issuer>
    </issuers>
</validate-jwt>
<set-header name="X-User-Id" exists-action="override">
    <value>@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Claims.GetValueOrDefault("user_id", ""))</value>
</set-header>
```

#### POST `/v1/auth/register`

Called once after first Firebase sign-in to create the backend user profile.

**Request:**
```json
{
    "display_name": "Jane Doe"
}
```

**Response (201 Created):**
```json
{
    "id": "firebase-uid-abc123",
    "display_name": "Jane Doe",
    "created_at": "2026-02-26T12:00:00Z"
}
```

**Behavior:**
- Creates a row in the `users` table with the Firebase UID
- If the user already exists, returns `409 CONFLICT` with the existing profile
- `display_name` is required, 1-50 characters

---

### 5.2 User Profile

#### GET `/v1/users/me`

Returns the authenticated user's profile.

**Response (200):**
```json
{
    "id": "firebase-uid-abc123",
    "display_name": "Jane Doe",
    "recording_count": 12,
    "created_at": "2026-02-26T12:00:00Z"
}
```

#### PUT `/v1/users/me`

Updates the authenticated user's profile.

**Request:**
```json
{
    "display_name": "Jane D."
}
```

**Response (200):**
```json
{
    "id": "firebase-uid-abc123",
    "display_name": "Jane D.",
    "recording_count": 12,
    "created_at": "2026-02-26T12:00:00Z"
}
```

**Validation:**
- `display_name`: 1-50 characters, no control characters

---

### 5.3 Recording Upload

#### POST `/v1/recordings`

Creates a recording metadata entry and returns a SAS (Shared Access Signature) URL for direct upload to Azure Blob Storage.

**Request:**
```json
{
    "subject": "The Old Oak Tree",
    "description": "This oak has been standing since 1850. My grandmother used to tell stories under it.",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "duration_sec": 45
}
```

**Validation:**
| Field | Rules |
|-------|-------|
| `subject` | Required, 1-200 characters |
| `description` | Optional, max 2000 characters |
| `latitude` | Required, -90 to 90 |
| `longitude` | Required, -180 to 180 |
| `duration_sec` | Required, 1 to 300 (5 minutes max) |

**Response (201 Created):**
```json
{
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "upload_url": "https://hearhereaudio.blob.core.windows.net/recordings/a1b2c3d4-...?sv=2023-11-03&st=...&se=...&sr=b&sp=cw&sig=...",
    "upload_expires_at": "2026-02-26T12:15:00Z",
    "status": "pending_upload"
}
```

**Behavior:**
1. Validates request body
2. Checks daily upload limit (10/day)
3. Creates recording row in DB with `status = 'pending_upload'`
4. Generates a Blob Storage SAS URL (15-minute expiry, write-only permission, 10MB max content-length via `x-ms-blob-content-length` constraint, `Content-Type: audio/aac`)
5. Returns upload URL to client

**Upload Completion:**
- Azure Blob Storage emits a `BlobCreated` event via Event Grid, which triggers a validation Azure Function that:
  1. Validates the uploaded file is valid audio (checks file header / MIME type)
  2. Updates recording status to `pending_moderation`
  3. Starts the Durable Functions moderation orchestration
- If no upload occurs within 15 minutes, a timer-triggered cleanup function marks the recording as `expired`

#### POST `/v1/recordings/{id}/upload-complete`

Called by the iOS client after successfully uploading audio to Blob Storage via the SAS URL. Acts as an explicit upload confirmation signal.

**Request:** (empty body)

**Response (200):**
```json
{
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "status": "pending_moderation"
}
```

**Behavior:**
1. Verifies the blob exists in Azure Blob Storage and matches expected size
2. Updates status from `pending_upload` to `pending_moderation`
3. Starts the Durable Functions moderation orchestration
4. Returns `404` if recording not found or not owned by user
5. Returns `409` if recording is not in `pending_upload` status

---

### 5.4 Recording Retrieval

#### GET `/v1/recordings/{id}`

Returns details for a single recording. Users can see their own recordings in any status. Other users can only see `approved` recordings.

**Response (200):**
```json
{
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "user_id": "firebase-uid-abc123",
    "display_name": "Jane Doe",
    "subject": "The Old Oak Tree",
    "description": "This oak has been standing since 1850...",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "duration_sec": 45,
    "status": "approved",
    "created_at": "2026-02-26T12:00:00Z"
}
```

**Authorization logic:**
- If `recording.user_id == requester.uid`: return full details (including any status)
- If `recording.status == 'approved'`: return public details
- Otherwise: `404 RECORDING_NOT_FOUND`

#### GET `/v1/recordings/mine`

Lists all recordings by the authenticated user across all statuses.

**Query Parameters:**
| Param | Default | Description |
|-------|---------|-------------|
| `status` | (all) | Filter by status: `pending_upload`, `pending_moderation`, `pending_review`, `approved`, `rejected` |
| `cursor` | (none) | Cursor for pagination (opaque string) |
| `limit` | 20 | Page size, max 50 |

**Response (200):**
```json
{
    "recordings": [
        {
            "id": "a1b2c3d4-...",
            "subject": "The Old Oak Tree",
            "duration_sec": 45,
            "status": "approved",
            "created_at": "2026-02-26T12:00:00Z"
        }
    ],
    "next_cursor": "eyJjcmVhdGVkX2F0Ijo..."
}
```

**Pagination:** Cursor-based using `created_at` + `id` compound cursor (encoded as base64 JSON). Cursor-based pagination is stable under concurrent inserts, unlike offset-based.

#### DELETE `/v1/recordings/{id}`

Soft-deletes a recording. Only the owner can delete their own recordings.

**Response (204 No Content)**

**Behavior:**
1. Sets `status = 'deleted'` and `deleted_at = now()`
2. Does not immediately remove audio from Blob Storage (cleaned up by a timer-triggered function after 30 days)
3. Returns `404` if recording not found or not owned by user

---

### 5.5 Location-Based Discovery

#### GET `/v1/recordings/nearby`

Returns approved recordings near a given location.

**Query Parameters:**
| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `lat` | Yes | — | Latitude (-90 to 90) |
| `lng` | Yes | — | Longitude (-180 to 180) |
| `radius` | No | 500 | Search radius in meters (50 to 5000) |
| `cursor` | No | (none) | Pagination cursor |
| `limit` | No | 20 | Page size, max 50 |

**Response (200):**
```json
{
    "recordings": [
        {
            "id": "a1b2c3d4-...",
            "user_id": "firebase-uid-abc123",
            "display_name": "Jane Doe",
            "subject": "The Old Oak Tree",
            "description": "This oak has been standing since 1850...",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "duration_sec": 45,
            "distance_m": 127.5,
            "created_at": "2026-02-26T12:00:00Z"
        }
    ],
    "next_cursor": "eyJkaXN0YW5jZV9tIjo..."
}
```

**Implementation:**
```sql
SELECT r.id, r.user_id, u.display_name, r.subject, r.description,
       ST_Y(r.location::geometry) AS latitude,
       ST_X(r.location::geometry) AS longitude,
       r.duration_sec,
       ST_Distance(r.location, ST_MakePoint($lng, $lat)::geography) AS distance_m,
       r.created_at
FROM recordings r
JOIN users u ON r.user_id = u.id
WHERE r.status = 'approved'
  AND ST_DWithin(r.location, ST_MakePoint($lng, $lat)::geography, $radius)
ORDER BY distance_m ASC
LIMIT $limit;
```

**Pagination:** Cursor-based on `(distance_m, id)`. Since distance is relative to the query point, pagination is only stable within the same request coordinates.

---

### 5.6 Audio Playback

#### GET `/v1/recordings/{id}/playback`

Returns a time-limited SAS URL for streaming the audio via Azure Front Door / CDN.

**Response (200):**
```json
{
    "playback_url": "https://hearhere.azurefd.net/audio/a1b2c3d4-...?sv=2023-11-03&se=...&sr=b&sp=r&sig=...",
    "expires_at": "2026-02-26T13:00:00Z",
    "duration_sec": 45,
    "format": "aac"
}
```

**Behavior:**
1. Verifies recording exists and `status = 'approved'` (or owner requesting their own)
2. Generates a Blob Storage SAS URL (read-only, 1-hour expiry) routed through Azure Front Door for CDN caching
3. Logs a play event for analytics (fire-and-forget via Application Insights `trackEvent`, does not block response)
4. Returns `403 RECORDING_NOT_PLAYABLE` if recording is not approved and requester is not the owner

---

### 5.7 Reporting

#### POST `/v1/reports`

Report a recording for policy violations.

**Request:**
```json
{
    "recording_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "reason": "hate_speech",
    "description": "Contains discriminatory language against..."
}
```

**Validation:**
| Field | Rules |
|-------|-------|
| `recording_id` | Required, valid UUID, must reference an approved recording |
| `reason` | Required, enum: `hate_speech`, `harassment`, `violence`, `sexual_content`, `spam`, `misinformation`, `other` |
| `description` | Optional, max 1000 characters |

**Response (201 Created):**
```json
{
    "id": "report-uuid-...",
    "recording_id": "a1b2c3d4-...",
    "status": "submitted",
    "created_at": "2026-02-26T12:00:00Z"
}
```

**Behavior:**
1. Creates a report row in the `reports` table
2. If this recording has accumulated 3+ reports from distinct users, automatically moves it to `pending_review` and queues it for human review
3. Returns `409 DUPLICATE_REPORT` if user already reported this recording
4. Users cannot report their own recordings

---

### 5.8 Moderation (Admin Endpoints)

Admin endpoints require a Firebase JWT with `admin: true` custom claim. This is enforced via a separate API Management policy that checks the claim after JWT validation.

#### GET `/v1/admin/moderation/queue`

Returns recordings pending human review, ordered by oldest first.

**Query Parameters:**
| Param | Default | Description |
|-------|---------|-------------|
| `cursor` | (none) | Pagination cursor |
| `limit` | 20 | Page size, max 50 |

**Response (200):**
```json
{
    "items": [
        {
            "id": "a1b2c3d4-...",
            "subject": "The Old Oak Tree",
            "description": "...",
            "duration_sec": 45,
            "transcript": "This oak has been standing since 1850...",
            "moderation_result": {
                "categories": {
                    "hate": 0.12,
                    "violence": 0.03,
                    "sexual": 0.01
                },
                "flagged": false
            },
            "report_count": 0,
            "playback_url": "https://hearhere.azurefd.net/audio/...",
            "created_at": "2026-02-26T12:00:00Z",
            "user": {
                "id": "firebase-uid-abc123",
                "display_name": "Jane Doe"
            }
        }
    ],
    "next_cursor": "...",
    "total_pending": 42
}
```

#### POST `/v1/admin/moderation/{recordingId}/decision`

Submit a moderation decision for a recording in the review queue.

**Request:**
```json
{
    "decision": "approved",
    "notes": "Content is appropriate, borderline score was a false positive."
}
```

**Validation:**
| Field | Rules |
|-------|-------|
| `decision` | Required, enum: `approved`, `rejected` |
| `notes` | Optional, max 2000 characters (internal reviewer notes) |

**Response (200):**
```json
{
    "id": "a1b2c3d4-...",
    "status": "approved",
    "reviewed_by": "admin-uid-...",
    "reviewed_at": "2026-02-26T14:00:00Z"
}
```

**Behavior:**
1. Updates recording `status` to `approved` or `rejected`
2. Stores reviewer UID and notes in `moderation_reviews` table
3. Sends push notification to recording creator via Azure Notification Hubs / APNs
4. If the recording was in human review via Durable Functions external event, raises the event to resume the orchestration
5. If rejected, the recording is no longer discoverable

#### GET `/v1/admin/moderation/stats`

Dashboard statistics for the moderation queue.

**Response (200):**
```json
{
    "pending_review": 42,
    "reviewed_today": 156,
    "auto_approved_today": 891,
    "auto_rejected_today": 12,
    "avg_review_time_sec": 34
}
```

---

## 6. Content Moderation Pipeline

### 6.1 Architecture

The moderation pipeline is an Azure Durable Functions orchestration triggered when a recording upload is confirmed. It is fully asynchronous — the user does not wait for moderation to complete.

```
Recording Upload Confirmed
    |
    v
[Start Durable Functions Orchestration]
    |
    v
[Activity 1: Start Transcription]
    - Call Azure AI Speech batch transcription REST API
    - Input: Blob Storage audio URL (with SAS token)
    - Orchestrator polls for completion (Durable Functions timer pattern)
    |
    v
[Activity 2: Store Transcript]
    - Function reads transcription result from Azure AI Speech
    - Stores transcript text in recordings.transcript
    |
    v
[Activity 3: Content Classification]
    - Function sends transcript to OpenAI Moderation API
    - Stores raw moderation result in recordings.moderation_result (JSONB)
    |
    v
[Activity 4: Decision Logic]
    - Function evaluates moderation scores against thresholds
    - Decision tree:
        - All category scores < 0.3 -> AUTO_APPROVE
        - Any category score > 0.7 -> AUTO_REJECT
        - Otherwise -> HUMAN_REVIEW
    |
    v
[Branch]
    |-- AUTO_APPROVE --> Update status = 'approved', send push notification
    |-- AUTO_REJECT  --> Update status = 'rejected', send push notification
    |-- HUMAN_REVIEW --> Update status = 'pending_review',
                         send message to Service Bus queue,
                         wait for external event (Durable Functions WaitForExternalEvent)
```

### 6.2 Durable Functions Orchestrator (Pseudocode)

```typescript
import * as df from 'durable-functions';

const orchestrator = df.orchestrator(function* (context) {
    const recordingId = context.df.getInput<string>();

    // Step 1: Start transcription
    const transcriptionJobUrl = yield context.df.callActivity('startTranscription', recordingId);

    // Step 2: Poll for transcription completion
    let transcriptionDone = false;
    while (!transcriptionDone) {
        const status = yield context.df.callActivity('checkTranscription', transcriptionJobUrl);
        if (status === 'Succeeded') {
            transcriptionDone = true;
        } else if (status === 'Failed') {
            // Route to human review on transcription failure
            yield context.df.callActivity('routeToHumanReview', { recordingId, reason: 'transcription_failed' });
            yield context.df.waitForExternalEvent('moderationDecision');
            return;
        } else {
            yield context.df.createTimer(new Date(Date.now() + 30000)); // wait 30s
        }
    }

    // Step 3: Store transcript
    yield context.df.callActivity('storeTranscript', { recordingId, transcriptionJobUrl });

    // Step 4: Classify content
    const moderationResult = yield context.df.callActivity('classifyContent', recordingId);

    // Step 5: Evaluate decision
    const decision = yield context.df.callActivity('evaluateDecision', { recordingId, moderationResult });

    if (decision === 'HUMAN_REVIEW') {
        yield context.df.callActivity('routeToHumanReview', { recordingId, reason: 'uncertain_score' });
        const humanDecision = yield context.df.waitForExternalEvent('moderationDecision');
        yield context.df.callActivity('applyDecision', { recordingId, decision: humanDecision });
    } else {
        yield context.df.callActivity('applyDecision', { recordingId, decision });
    }

    // Step 6: Notify user
    yield context.df.callActivity('sendNotification', recordingId);
});
```

### 6.3 Moderation Thresholds

| Category | Auto-Approve Below | Auto-Reject Above | Human Review |
|----------|-------------------|-------------------|-------------|
| `hate` | 0.3 | 0.7 | 0.3 - 0.7 |
| `hate/threatening` | 0.2 | 0.5 | 0.2 - 0.5 |
| `harassment` | 0.3 | 0.7 | 0.3 - 0.7 |
| `self-harm` | 0.2 | 0.5 | 0.2 - 0.5 |
| `sexual` | 0.3 | 0.7 | 0.3 - 0.7 |
| `violence` | 0.3 | 0.7 | 0.3 - 0.7 |

These thresholds are stored in Azure App Configuration so they can be tuned without redeployment. The Functions runtime reads them via the App Configuration provider with automatic refresh.

### 6.4 Transcription Details

- **Service:** Azure AI Speech (batch transcription API)
- **Language:** `en-US` initially; add language identification (Azure AI Speech auto-detect) when expanding internationally
- **Output format:** Plain text (extracted from batch transcription JSON result)
- **Storage:** Transcript text stored in `recordings.transcript` column
- **Failure handling:** If transcription fails (unsupported audio, empty audio), the recording is routed to human review with a flag indicating transcription failure

### 6.5 Audio Validation

Before moderation, a validation step checks:

1. File size is within limits (< 10MB)
2. File header matches expected audio format (AAC/M4A)
3. Audio duration matches the declared `duration_sec` (within 5-second tolerance)

Invalid files are rejected immediately without entering the moderation pipeline.

### 6.6 Re-Moderation (Reports)

When a previously approved recording accumulates 3+ user reports:

1. Recording status changes to `pending_review`
2. Recording is removed from discovery results
3. A new message is sent to the Azure Service Bus human review queue with the reports attached
4. Human reviewer sees the reports alongside the original moderation data

---

## 7. Background Job Processing

### 7.1 Jobs Overview

| Job | Trigger | Technology | Description |
|-----|---------|-----------|-------------|
| Audio validation | Blob Storage `BlobCreated` event | Azure Function (Event Grid trigger) | Validates uploaded audio file format and size |
| Moderation pipeline | Recording status change | Durable Functions orchestration | Full transcription + classification workflow |
| Push notification | Moderation decision | Azure Function (activity function within Durable Functions) | Sends APNs notification via Azure Notification Hubs |
| Upload cleanup | Timer schedule (every hour) | Azure Function (timer trigger, CRON: `0 0 * * * *`) | Marks `pending_upload` recordings older than 1 hour as `expired` |
| Audio deletion | Timer schedule (daily) | Azure Function (timer trigger, CRON: `0 0 3 * * *`) | Permanently deletes blobs for recordings in `rejected` or `deleted` status older than 30 days |
| Report threshold check | Report creation | Azure Function (called by report endpoint) | Checks if report count crosses threshold, triggers re-moderation |

### 7.2 Blob Storage Event Pipeline

```
Azure Blob Storage BlobCreated (recordings/ container)
    |
    v
Event Grid Subscription
    |
    v
Audio Validation Function (Event Grid trigger)
    |-- Valid   --> Update status to 'pending_moderation', start Durable Functions orchestration
    |-- Invalid --> Update status to 'rejected', notify user
```

### 7.3 Push Notifications

Notifications are sent via Azure Notification Hubs to Apple Push Notification service (APNs).

**Notification events:**
| Event | Message |
|-------|---------|
| Recording approved | "Your recording '{subject}' is now live!" |
| Recording rejected | "Your recording '{subject}' could not be approved." |
| Recording reported and removed | "Your recording '{subject}' is under review." |

**Implementation:**
- iOS app registers for push notifications and sends the device token to `PUT /v1/users/me` (stored in `users.apns_token`)
- Azure Notification Hubs configured with APNs certificate/token-based authentication
- Activity function within Durable Functions sends notification via Notification Hubs SDK

---

## 8. Azure Functions Project Structure

### 8.1 Project Layout

```
backend/
├── functions/
│   ├── recordings/
│   │   ├── create.ts             # POST /recordings
│   │   ├── get.ts                # GET /recordings/{id}
│   │   ├── delete.ts             # DELETE /recordings/{id}
│   │   ├── mine.ts               # GET /recordings/mine
│   │   ├── upload-complete.ts    # POST /recordings/{id}/upload-complete
│   │   └── playback.ts           # GET /recordings/{id}/playback
│   ├── discovery/
│   │   └── nearby.ts             # GET /recordings/nearby
│   ├── users/
│   │   ├── register.ts           # POST /auth/register
│   │   ├── get-me.ts             # GET /users/me
│   │   └── update-me.ts          # PUT /users/me
│   ├── reports/
│   │   └── create.ts             # POST /reports
│   ├── admin/
│   │   ├── queue.ts              # GET /admin/moderation/queue
│   │   ├── decision.ts           # POST /admin/moderation/{id}/decision
│   │   └── stats.ts              # GET /admin/moderation/stats
│   └── triggers/
│       ├── blob-created.ts       # Event Grid trigger: audio validation
│       ├── cleanup-uploads.ts    # Timer trigger: expire stale uploads
│       └── cleanup-audio.ts      # Timer trigger: delete old rejected/deleted blobs
├── moderation/
│   ├── orchestrator.ts           # Durable Functions orchestrator
│   ├── start-transcription.ts    # Activity: start Azure AI Speech batch job
│   ├── check-transcription.ts    # Activity: poll transcription status
│   ├── store-transcript.ts       # Activity: read and store transcript result
│   ├── classify-content.ts       # Activity: call OpenAI Moderation API
│   ├── evaluate-decision.ts      # Activity: apply thresholds, decide outcome
│   ├── route-to-human-review.ts  # Activity: send to Service Bus queue
│   ├── apply-decision.ts         # Activity: update DB status
│   └── send-notification.ts      # Activity: push notification via Notification Hubs
├── shared/
│   ├── db.ts                     # Kysely database client (connection via managed identity)
│   ├── errors.ts                 # Standard error classes
│   ├── response.ts               # Standard response helpers
│   ├── auth.ts                   # Auth context extraction (reads X-User-Id header from APIM)
│   └── schemas/                  # Zod validation schemas
│       ├── recording.ts
│       ├── user.ts
│       └── report.ts
├── host.json                     # Azure Functions host configuration
├── local.settings.json           # Local dev settings (git-ignored)
├── package.json
└── tsconfig.json
```

### 8.2 Handler Pattern

Every Azure Function HTTP handler follows this structure:

```typescript
import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { z } from 'zod';
import { db } from '../shared/db';
import { errorResponse, jsonResponse } from '../shared/response';
import { getAuthContext } from '../shared/auth';

const RequestSchema = z.object({
  subject: z.string().min(1).max(200),
  // ...
});

async function createRecording(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const auth = getAuthContext(req); // reads X-User-Id header set by APIM
    const body = RequestSchema.parse(await req.json());

    // Business logic...

    return jsonResponse(201, result);
  } catch (err) {
    return errorResponse(err);
  }
}

app.http('createRecording', {
  methods: ['POST'],
  authLevel: 'anonymous', // auth handled by APIM
  route: 'v1/recordings',
  handler: createRecording,
});
```

### 8.3 Database Connection Management

Azure Functions connect to PostgreSQL via **Azure Database for PostgreSQL Flexible Server** using **managed identity authentication** (Microsoft Entra / AAD). This eliminates the need for database passwords in configuration.

- The Function App's system-assigned managed identity is granted the `azure_ad_user` role in PostgreSQL
- Kysely is configured with `@azure/identity` to acquire short-lived access tokens for database connections
- Connection pooling: Azure Functions on the Consumption plan reuse connections within a single instance; for higher concurrency, the Premium plan with VNET integration and PgBouncer sidecar can be used
- Connection string pattern: `postgresql://funcapp-identity@hearhere-db.postgres.database.azure.com:5432/hearhere?sslmode=require`

### 8.4 host.json Configuration

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    },
    "logLevel": {
      "default": "Information",
      "Host.Results": "Error",
      "Function": "Information"
    }
  },
  "extensions": {
    "durableTask": {
      "hubName": "HearHereModeration",
      "storageProvider": {
        "type": "azure-storage"
      }
    },
    "serviceBus": {
      "prefetchCount": 10,
      "autoCompleteMessages": false
    }
  },
  "functionTimeout": "00:05:00"
}
```

---

## 9. OpenAPI Specification (Key Endpoints)

```yaml
openapi: 3.1.0
info:
  title: Hear Here API
  version: 1.0.0
  description: Location-based audio storytelling platform API

servers:
  - url: https://api.hearhere.app/v1
    description: Production (via Azure API Management)

security:
  - firebaseAuth: []

components:
  securitySchemes:
    firebaseAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
      description: Firebase Authentication JWT token

  schemas:
    Error:
      type: object
      required: [error]
      properties:
        error:
          type: object
          required: [code, message]
          properties:
            code:
              type: string
              example: RECORDING_NOT_FOUND
            message:
              type: string
              example: The requested recording does not exist.
            details:
              type: object

    RecordingCreate:
      type: object
      required: [subject, latitude, longitude, duration_sec]
      properties:
        subject:
          type: string
          minLength: 1
          maxLength: 200
        description:
          type: string
          maxLength: 2000
        latitude:
          type: number
          minimum: -90
          maximum: 90
        longitude:
          type: number
          minimum: -180
          maximum: 180
        duration_sec:
          type: integer
          minimum: 1
          maximum: 300

    RecordingCreateResponse:
      type: object
      properties:
        id:
          type: string
          format: uuid
        upload_url:
          type: string
          format: uri
        upload_expires_at:
          type: string
          format: date-time
        status:
          type: string
          enum: [pending_upload]

    Recording:
      type: object
      properties:
        id:
          type: string
          format: uuid
        user_id:
          type: string
        display_name:
          type: string
        subject:
          type: string
        description:
          type: string
        latitude:
          type: number
        longitude:
          type: number
        duration_sec:
          type: integer
        distance_m:
          type: number
          description: Distance from query point (only in nearby results)
        status:
          type: string
          enum: [pending_upload, pending_moderation, pending_review, approved, rejected]
        created_at:
          type: string
          format: date-time

    RecordingList:
      type: object
      properties:
        recordings:
          type: array
          items:
            $ref: '#/components/schemas/Recording'
        next_cursor:
          type: string
          nullable: true

    PlaybackResponse:
      type: object
      properties:
        playback_url:
          type: string
          format: uri
        expires_at:
          type: string
          format: date-time
        duration_sec:
          type: integer
        format:
          type: string
          enum: [aac]

    User:
      type: object
      properties:
        id:
          type: string
        display_name:
          type: string
        recording_count:
          type: integer
        created_at:
          type: string
          format: date-time

    ReportCreate:
      type: object
      required: [recording_id, reason]
      properties:
        recording_id:
          type: string
          format: uuid
        reason:
          type: string
          enum: [hate_speech, harassment, violence, sexual_content, spam, misinformation, other]
        description:
          type: string
          maxLength: 1000

    ReportResponse:
      type: object
      properties:
        id:
          type: string
          format: uuid
        recording_id:
          type: string
          format: uuid
        status:
          type: string
          enum: [submitted]
        created_at:
          type: string
          format: date-time

paths:
  /auth/register:
    post:
      summary: Register user profile after Firebase sign-in
      tags: [Auth]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [display_name]
              properties:
                display_name:
                  type: string
                  minLength: 1
                  maxLength: 50
      responses:
        '201':
          description: User profile created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'
        '409':
          description: User already exists

  /users/me:
    get:
      summary: Get current user profile
      tags: [Users]
      responses:
        '200':
          description: User profile
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'
    put:
      summary: Update current user profile
      tags: [Users]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                display_name:
                  type: string
                  minLength: 1
                  maxLength: 50
      responses:
        '200':
          description: Updated user profile
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'

  /recordings:
    post:
      summary: Create recording and get SAS upload URL
      tags: [Recordings]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/RecordingCreate'
      responses:
        '201':
          description: Recording created with SAS upload URL
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/RecordingCreateResponse'
        '429':
          description: Daily upload limit exceeded

  /recordings/mine:
    get:
      summary: List current user's recordings
      tags: [Recordings]
      parameters:
        - name: status
          in: query
          schema:
            type: string
            enum: [pending_upload, pending_moderation, pending_review, approved, rejected]
        - name: cursor
          in: query
          schema:
            type: string
        - name: limit
          in: query
          schema:
            type: integer
            minimum: 1
            maximum: 50
            default: 20
      responses:
        '200':
          description: Paginated list of user's recordings
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/RecordingList'

  /recordings/nearby:
    get:
      summary: Discover nearby approved recordings
      tags: [Discovery]
      parameters:
        - name: lat
          in: query
          required: true
          schema:
            type: number
            minimum: -90
            maximum: 90
        - name: lng
          in: query
          required: true
          schema:
            type: number
            minimum: -180
            maximum: 180
        - name: radius
          in: query
          schema:
            type: integer
            minimum: 50
            maximum: 5000
            default: 500
        - name: cursor
          in: query
          schema:
            type: string
        - name: limit
          in: query
          schema:
            type: integer
            minimum: 1
            maximum: 50
            default: 20
      responses:
        '200':
          description: Nearby recordings sorted by distance
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/RecordingList'

  /recordings/{id}:
    get:
      summary: Get recording details
      tags: [Recordings]
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Recording details
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Recording'
        '404':
          description: Recording not found
    delete:
      summary: Delete own recording (soft delete)
      tags: [Recordings]
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '204':
          description: Recording deleted
        '404':
          description: Recording not found or not owned by user

  /recordings/{id}/upload-complete:
    post:
      summary: Confirm audio upload completion
      tags: [Recordings]
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Upload confirmed, moderation started
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: string
                    format: uuid
                  status:
                    type: string
                    enum: [pending_moderation]
        '409':
          description: Recording not in pending_upload status

  /recordings/{id}/playback:
    get:
      summary: Get signed playback URL
      tags: [Playback]
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Playback URL
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/PlaybackResponse'
        '403':
          description: Recording not approved

  /reports:
    post:
      summary: Report a recording
      tags: [Reports]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ReportCreate'
      responses:
        '201':
          description: Report submitted
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ReportResponse'
        '409':
          description: Already reported this recording

  /admin/moderation/queue:
    get:
      summary: Get moderation review queue
      tags: [Admin]
      parameters:
        - name: cursor
          in: query
          schema:
            type: string
        - name: limit
          in: query
          schema:
            type: integer
            minimum: 1
            maximum: 50
            default: 20
      responses:
        '200':
          description: Paginated moderation queue

  /admin/moderation/{recordingId}/decision:
    post:
      summary: Submit moderation decision
      tags: [Admin]
      parameters:
        - name: recordingId
          in: path
          required: true
          schema:
            type: string
            format: uuid
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [decision]
              properties:
                decision:
                  type: string
                  enum: [approved, rejected]
                notes:
                  type: string
                  maxLength: 2000
      responses:
        '200':
          description: Decision recorded

  /admin/moderation/stats:
    get:
      summary: Moderation dashboard statistics
      tags: [Admin]
      responses:
        '200':
          description: Moderation stats
```

---

## 10. Service Layer Architecture

### Service Boundaries

The backend is organized into logical services, each deployed as one or more Azure Functions within a single Function App:

```
┌─────────────────────────────────────────────────────┐
│              Azure API Management                    │
│    (routing, JWT validation, rate limiting)          │
└─────────┬──────────┬──────────┬──────────┬──────────┘
          │          │          │          │
    ┌─────▼────┐ ┌───▼──────┐ ┌▼────────┐ ┌▼──────────┐
    │Recording │ │Discovery │ │User     │ │Admin      │
    │Service   │ │Service   │ │Service  │ │Service    │
    │          │ │          │ │         │ │           │
    │- create  │ │- nearby  │ │- register│ │- queue   │
    │- get     │ │          │ │- get me │ │- decision │
    │- delete  │ │          │ │- update │ │- stats    │
    │- mine    │ │          │ │         │ │           │
    │- upload  │ │          │ │         │ │           │
    │- playback│ │          │ │         │ │           │
    │- report  │ │          │ │         │ │           │
    └─────┬────┘ └────┬─────┘ └────┬────┘ └─────┬─────┘
          │           │            │             │
          └───────────┴─────┬──────┴─────────────┘
                            │
                  ┌─────────▼──────────┐
                  │    PostgreSQL       │
                  │ (Flexible Server)   │
                  └────────────────────┘

              ┌──────────────────────────────┐
              │   Moderation Pipeline         │
              │   (Durable Functions)         │
              │                               │
              │ AI Speech → Classify → Decide │
              │    → Notify                   │
              └──────────────────────────────┘
```

### Shared Concerns

All services share these cross-cutting concerns via the `shared/` module:

| Concern | Implementation |
|---------|---------------|
| **Database access** | Kysely client with managed identity auth to Flexible Server |
| **Error handling** | Custom error classes (`NotFoundError`, `ForbiddenError`, `ValidationError`) mapped to HTTP responses |
| **Request validation** | Zod schemas per endpoint |
| **Auth context** | Helper extracting `uid` from `X-User-Id` header (set by API Management `validate-jwt` + `set-header` policies) |
| **Response formatting** | `jsonResponse(status, body)` and `errorResponse(err)` helpers |
| **Logging** | Structured logging via Application Insights SDK (`@applicationinsights/web`) with request ID correlation |
| **Configuration** | Azure App Configuration for feature flags and moderation thresholds; Key Vault references for secrets |

---

## 11. Deployment & CI/CD Notes

### Azure Functions Packaging

- The Function App is built using **esbuild** for fast TypeScript compilation and tree-shaking
- All functions are deployed as a single Function App (keeps cold-start pool warm across endpoints)
- Shared code in `shared/` is inlined into each function's bundle at build time
- Deploy via `func azure functionapp publish` or GitHub Actions with `azure/functions-action`

### Environment Configuration

| Setting | Source | Description |
|---------|--------|-------------|
| `DATABASE_HOST` | App Configuration | Flexible Server hostname |
| `DATABASE_NAME` | App Configuration | Database name (`hearhere`) |
| `STORAGE_ACCOUNT_NAME` | App Configuration | Blob Storage account for audio files |
| `STORAGE_CONTAINER_NAME` | App Configuration | Container name (`recordings`) |
| `FRONT_DOOR_HOSTNAME` | App Configuration | Azure Front Door endpoint hostname |
| `FIREBASE_PROJECT_ID` | App Configuration | Firebase project for JWT validation |
| `OPENAI_API_KEY` | Key Vault reference | OpenAI API key for moderation |
| `NOTIFICATION_HUB_CONNECTION` | Key Vault reference | Azure Notification Hubs connection string |
| `SPEECH_SERVICE_KEY` | Key Vault reference | Azure AI Speech service key |
| `SPEECH_SERVICE_REGION` | App Configuration | Azure AI Speech region |
| `SERVICEBUS_CONNECTION` | Managed identity | Service Bus namespace (no connection string needed) |

### Managed Identity Access

The Function App's system-assigned managed identity is granted:

| Resource | Role | Purpose |
|----------|------|---------|
| Blob Storage | Storage Blob Data Contributor | Read/write audio blobs, generate user delegation SAS |
| Key Vault | Key Vault Secrets User | Read secrets (API keys, connection strings) |
| Service Bus | Azure Service Bus Data Sender | Send messages to moderation queue |
| PostgreSQL Flexible Server | `azure_ad_user` role | Database access via AAD token |
| App Configuration | App Configuration Data Reader | Read configuration values |

### Function Timeout & Scaling Configuration

| Function Type | Timeout | Plan | Notes |
|---------------|---------|------|-------|
| HTTP triggers (all API endpoints) | 30s | Consumption | Default for HTTP-triggered functions |
| Event Grid trigger (audio validation) | 5 min | Consumption | Reads blob to validate |
| Timer triggers (cleanup) | 5 min | Consumption | Batch operations |
| Durable orchestrator | 7 days | Consumption | Long-running workflow with checkpoints; actual compute is in short-lived activities |
| Durable activities | 5 min | Consumption | Individual moderation steps |

**Note:** Unlike Lambda where memory is configurable per function, Azure Functions on the Consumption plan allocates 1.5 GB memory to all functions in the app. The Premium plan (EP1) offers configurable instance sizes if more memory is needed for the discovery/PostGIS workload.
