# Hear Here -- API Documentation

## Base URL

```
Production:  https://api.hearhere.app/v1
Staging:     https://api-staging.hearhere.app/v1
Development: https://api-dev.hearhere.app/v1
```

All endpoints use HTTPS. HTTP requests are rejected.

## Authentication

Every request must include a Firebase JWT in the `Authorization` header:

```
Authorization: Bearer <firebase_jwt>
```

### How Authentication Works

1. The iOS app signs the user in via Firebase Auth SDK (Apple ID or Google).
2. Firebase issues a JWT ID token.
3. The app sends this JWT with every API request.
4. A Lambda authorizer validates the JWT against Firebase's public keys, verifying the signature, issuer, audience, and expiration.
5. The authorizer extracts the user's `uid` and passes it to the backend handler.

Token refresh is handled automatically by the Firebase SDK. If the backend returns `401 Unauthorized`, the client refreshes the token and retries once.

### Admin Authentication

Admin endpoints (under `/admin/`) require a Firebase JWT with the custom claim `admin: true`. This is set via the Firebase Admin SDK.

---

## Request and Response Format

- All request and response bodies use **JSON** (`Content-Type: application/json`).
- Audio upload and download use **pre-signed URLs** -- audio bytes never pass through the API.
- Dates use **ISO 8601** format (`2026-02-26T12:00:00Z`).
- Field names use **snake_case**.

---

## Error Handling

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
| `error.code` | string | Machine-readable error code (SCREAMING_SNAKE_CASE) |
| `error.message` | string | Human-readable description |
| `error.details` | object | Optional structured data (validation errors, retry info) |

### Validation Errors

Validation failures include field-level details:

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

### Error Code Reference

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Request body or parameters failed validation |
| `UNAUTHORIZED` | 401 | Missing or invalid JWT |
| `FORBIDDEN` | 403 | User lacks permission for this action |
| `RECORDING_NOT_FOUND` | 404 | Recording ID does not exist or is not accessible |
| `USER_NOT_FOUND` | 404 | User profile not found |
| `RECORDING_NOT_PLAYABLE` | 403 | Recording is not yet approved (and requester is not the owner) |
| `DUPLICATE_REPORT` | 409 | User has already reported this recording |
| `UPLOAD_TOO_LARGE` | 413 | Audio file exceeds 10 MB |
| `INVALID_RADIUS` | 422 | Radius is outside the allowed range (50-5000m) |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests -- see `Retry-After` header |
| `DAILY_UPLOAD_LIMIT` | 429 | User has exceeded 10 recordings per day |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## Rate Limiting

Rate limits are enforced per user (identified by Firebase UID).

| Endpoint Category | Limit | Burst |
|-------------------|-------|-------|
| Discovery (`GET /recordings/nearby`) | 60 req/min | 10 |
| Recording creation (`POST /recordings`) | 10 req/day | 3 |
| Playback URLs (`GET /recordings/{id}/playback`) | 120 req/min | 20 |
| General read endpoints | 100 req/min | 20 |
| Reports (`POST /reports`) | 10 req/hour | 5 |

### Rate Limit Headers

Every response includes:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1709000000
```

When the limit is exceeded:

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

---

## Pagination

List endpoints use **cursor-based pagination**. Each response includes a `next_cursor` field. Pass it as the `cursor` query parameter to fetch the next page.

```
GET /v1/recordings/mine?limit=20
GET /v1/recordings/mine?limit=20&cursor=eyJjcmVhdGVkX2F0Ijo...
```

Cursors are opaque strings. Do not parse or construct them.

---

## Endpoints

### Auth

#### POST `/v1/auth/register`

Called once after first Firebase sign-in to create the backend user profile.

**Request:**
```json
{
    "display_name": "Jane Doe"
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `display_name` | string | Yes | 1-50 characters |

**Response (201 Created):**
```json
{
    "id": "firebase-uid-abc123",
    "display_name": "Jane Doe",
    "created_at": "2026-02-26T12:00:00Z"
}
```

**Errors:**
- `409` -- User already exists (returns the existing profile)

---

### Users

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

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `display_name` | string | Yes | 1-50 characters, no control characters |

**Response (200):**
```json
{
    "id": "firebase-uid-abc123",
    "display_name": "Jane D.",
    "recording_count": 12,
    "created_at": "2026-02-26T12:00:00Z"
}
```

---

### Recordings

#### POST `/v1/recordings`

Creates a recording metadata entry and returns a pre-signed S3 upload URL.

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

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `subject` | string | Yes | 1-200 characters |
| `description` | string | No | Max 2000 characters |
| `latitude` | number | Yes | -90 to 90 |
| `longitude` | number | Yes | -180 to 180 |
| `duration_sec` | integer | Yes | 1 to 300 |

**Response (201 Created):**
```json
{
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "upload_url": "https://hearhere-audio.s3.amazonaws.com/uploads/a1b2c3d4-...?X-Amz-Algorithm=...",
    "upload_expires_at": "2026-02-26T12:15:00Z",
    "status": "pending_upload"
}
```

**After receiving the response:**
1. Upload the `.m4a` audio file to `upload_url` via HTTP PUT with `Content-Type: audio/aac`.
2. Call `POST /v1/recordings/{id}/upload-complete` to confirm.

**Errors:**
- `429 DAILY_UPLOAD_LIMIT` -- Exceeded 10 recordings per day

#### POST `/v1/recordings/{id}/upload-complete`

Confirms the audio upload is complete and triggers the moderation pipeline.

**Request:** Empty body.

**Response (200):**
```json
{
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "status": "pending_moderation"
}
```

**Errors:**
- `404` -- Recording not found or not owned by user
- `409` -- Recording is not in `pending_upload` status

#### GET `/v1/recordings/{id}`

Returns details for a single recording.

**Authorization logic:**
- Owner can see their recording in any status.
- Other users can only see recordings with status `approved`.
- Otherwise returns `404`.

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

#### GET `/v1/recordings/mine`

Lists all recordings by the authenticated user across all statuses.

**Query Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `status` | string | (all) | Filter: `pending_upload`, `pending_moderation`, `pending_review`, `approved`, `rejected` |
| `cursor` | string | (none) | Pagination cursor |
| `limit` | integer | 20 | Page size (1-50) |

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

#### DELETE `/v1/recordings/{id}`

Soft-deletes a recording. Only the owner can delete their own recordings. Audio is permanently removed from S3 after 30 days.

**Response:** `204 No Content`

**Errors:**
- `404` -- Recording not found or not owned by user

---

### Discovery

#### GET `/v1/recordings/nearby`

Returns approved recordings near a given location, sorted by distance.

**Query Parameters:**

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `lat` | number | Yes | -- | Latitude (-90 to 90) |
| `lng` | number | Yes | -- | Longitude (-180 to 180) |
| `radius` | integer | No | 500 | Search radius in meters (50-5000) |
| `cursor` | string | No | (none) | Pagination cursor |
| `limit` | integer | No | 20 | Page size (1-50) |

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

**Errors:**
- `422 INVALID_RADIUS` -- Radius outside the 50-5000m range

---

### Playback

#### GET `/v1/recordings/{id}/playback`

Returns a time-limited signed CloudFront URL for streaming audio.

**Response (200):**
```json
{
    "playback_url": "https://cdn.hearhere.app/audio/a1b2c3d4-...?Expires=...&Signature=...&Key-Pair-Id=...",
    "expires_at": "2026-02-26T13:00:00Z",
    "duration_sec": 45,
    "format": "aac"
}
```

The `playback_url` is valid for 1 hour. A play event is logged automatically.

**Errors:**
- `403 RECORDING_NOT_PLAYABLE` -- Recording is not approved (and requester is not the owner)
- `404 RECORDING_NOT_FOUND` -- Recording does not exist

---

### Reports

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

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `recording_id` | string (UUID) | Yes | Must reference an approved recording |
| `reason` | string | Yes | One of: `hate_speech`, `harassment`, `violence`, `sexual_content`, `spam`, `misinformation`, `other` |
| `description` | string | No | Max 1000 characters |

**Response (201 Created):**
```json
{
    "id": "report-uuid-...",
    "recording_id": "a1b2c3d4-...",
    "status": "submitted",
    "created_at": "2026-02-26T12:00:00Z"
}
```

If a recording accumulates 3+ reports from distinct users, it is automatically sent for human review.

**Errors:**
- `409 DUPLICATE_REPORT` -- User has already reported this recording
- Users cannot report their own recordings

---

### Admin -- Moderation

These endpoints require the `admin: true` custom claim in the Firebase JWT.

#### GET `/v1/admin/moderation/queue`

Returns recordings pending human review, ordered oldest first.

**Query Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `cursor` | string | (none) | Pagination cursor |
| `limit` | integer | 20 | Page size (1-50) |

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
            "playback_url": "https://cdn.hearhere.app/audio/...",
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

Submit a moderation decision.

**Request:**
```json
{
    "decision": "approved",
    "notes": "Content is appropriate, borderline score was a false positive."
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `decision` | string | Yes | `approved` or `rejected` |
| `notes` | string | No | Max 2000 characters (internal reviewer notes) |

**Response (200):**
```json
{
    "id": "a1b2c3d4-...",
    "status": "approved",
    "reviewed_by": "admin-uid-...",
    "reviewed_at": "2026-02-26T14:00:00Z"
}
```

A push notification is sent to the recording's creator.

#### GET `/v1/admin/moderation/stats`

Moderation dashboard statistics.

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

## Recording Upload Flow (End-to-End)

1. **Create recording:** `POST /v1/recordings` with metadata. Receive `upload_url`.
2. **Upload audio:** HTTP PUT to `upload_url` with the `.m4a` file and `Content-Type: audio/aac`. The pre-signed URL expires after 15 minutes and enforces a 10 MB size limit.
3. **Confirm upload:** `POST /v1/recordings/{id}/upload-complete`. Status changes to `pending_moderation`.
4. **Moderation runs asynchronously:** Transcription, content classification, and decision logic.
5. **User is notified:** Push notification when the recording is approved or rejected.
6. **Recording becomes discoverable:** If approved, it appears in nearby discovery queries.

## Moderation Decision Thresholds

| Category | Auto-Approve (below) | Auto-Reject (above) | Human Review |
|----------|---------------------|---------------------|-------------|
| hate | 0.3 | 0.7 | 0.3 - 0.7 |
| hate/threatening | 0.2 | 0.5 | 0.2 - 0.5 |
| harassment | 0.3 | 0.7 | 0.3 - 0.7 |
| self-harm | 0.2 | 0.5 | 0.2 - 0.5 |
| sexual | 0.3 | 0.7 | 0.3 - 0.7 |
| violence | 0.3 | 0.7 | 0.3 - 0.7 |

Thresholds are configurable without redeployment.

---

## API Versioning

The API uses URL path versioning (`/v1/`). Non-breaking changes (new optional fields, new endpoints) are added to the current version. Breaking changes require a new version (`/v2/`), with the old version deprecated for at least 90 days before removal.
