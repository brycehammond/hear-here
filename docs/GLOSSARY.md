# Hear Here -- Glossary

## A

**AAC (Advanced Audio Coding):** The audio codec used for all recordings. AAC provides good compression with high quality for speech. Files use the `.m4a` container format.

**APNs (Apple Push Notification service):** Apple's service for delivering push notifications to iOS devices. Hear Here uses APNs via Amazon SNS to notify users of moderation outcomes.

**API Gateway:** AWS API Gateway (HTTP API) that routes all client requests to the appropriate Lambda function, handles rate limiting, and invokes the JWT authorizer.

**Approved:** A recording moderation status indicating the content has passed review (automated or human) and is publicly discoverable.

**Auto-approve:** An automated moderation decision where all content classification scores fall below the safe threshold (< 0.3), causing the recording to be approved without human review.

**Auto-reject:** An automated moderation decision where any content classification score exceeds the unsafe threshold (> 0.7), causing the recording to be rejected without human review.

## C

**CDK (AWS Cloud Development Kit):** The infrastructure-as-code tool used to define and deploy all AWS resources. Written in TypeScript.

**CloudFront:** AWS CDN service used to serve audio files to listeners with low latency via edge locations. Access is controlled with signed URLs.

**Content Classification:** The process of evaluating a recording's transcript for policy violations using the OpenAI Moderation API. Returns per-category scores for hate, violence, sexual content, etc.

**Coordinator (iOS):** A design pattern used in the iOS app to manage navigation flow. Each tab has a coordinator that owns a `NavigationStack` and controls screen transitions.

**Cursor-based Pagination:** The pagination strategy used by the API. Instead of page numbers/offsets, each response includes an opaque cursor string that the client sends to fetch the next page.

## D

**Discovery:** The feature that allows users to find nearby recordings. Uses PostGIS spatial queries to find approved recordings within a given radius of the user's location.

**Discovery Radius:** The distance (in meters) within which recordings are returned to a user. Defaults to 500m, configurable up to 5,000m.

## F

**Firebase Auth:** Google's authentication service used for user sign-in. Supports Sign in with Apple and Google Sign-In. Issues JWTs validated by the backend.

**Firebase UID:** The unique identifier assigned to each user by Firebase Authentication. Used as the primary user identity across the system.

## G

**GiST Index:** Generalized Search Tree index type in PostgreSQL. Used by PostGIS for efficient spatial queries on the `recordings.location` column.

**Geography (PostGIS):** A PostGIS data type that represents points on the Earth's surface using latitude/longitude coordinates (SRID 4326). Used to store recording locations with geodesic distance calculations.

## H

**Human Review:** The moderation step where a content moderator manually reviews a recording that received uncertain automated classification scores. Performed via the admin UI.

## J

**JWT (JSON Web Token):** The authentication token format issued by Firebase Auth. Sent as a Bearer token in the `Authorization` header of every API request. Validated server-side by a Lambda authorizer.

## K

**Kysely:** A type-safe SQL query builder for TypeScript, used in the backend Lambda functions to interact with PostgreSQL. Provides type inference without ORM abstraction.

## L

**Lambda Authorizer:** A Lambda function attached to API Gateway that validates Firebase JWTs on every request. Extracts the user's UID and passes it to downstream handlers.

**Location Pinning:** The act of attaching a geographic coordinate to a recording when it is created. The user can pin to their current location or adjust the pin manually.

## M

**Moderation Pipeline:** The asynchronous workflow (AWS Step Functions) that processes each new recording: transcription, content classification, decision logic, and notification.

**Moderation Record:** An immutable audit trail entry created for every moderation status change on a recording. Stored in the `moderation_records` table.

**MVVM (Model-View-ViewModel):** The architectural pattern used in the iOS app. Views observe ViewModels via `@Observable`, and ViewModels coordinate between views and services.

## O

**OpenAI Moderation API:** An external API used to classify transcript text for content safety. Returns per-category scores (hate, violence, sexual, etc.) that drive moderation decisions.

## P

**Pending Moderation:** A recording status indicating the audio has been uploaded and is awaiting automated content analysis.

**Pending Review:** A recording status indicating automated moderation returned uncertain scores and the recording requires human review.

**PostGIS:** A spatial extension for PostgreSQL that adds geographic data types, spatial indexes, and functions like `ST_DWithin` for proximity queries.

**Pre-signed URL:** A time-limited URL generated by the backend that allows the iOS app to upload audio directly to S3 (for uploads) or stream audio from CloudFront (for playback) without exposing credentials.

## R

**RDS (Relational Database Service):** The AWS managed service hosting the PostgreSQL 16 database with PostGIS.

**RDS Proxy:** A managed connection pooler between Lambda functions and RDS. Prevents connection exhaustion caused by Lambda's per-invocation connection pattern.

**Recording:** The core entity in Hear Here. An audio file attached to a geographic location with metadata (subject, description) that passes through moderation before becoming publicly discoverable.

**Rejected:** A recording moderation status indicating the content did not pass review. Rejected recordings are not discoverable and are permanently deleted after 30 days.

## S

**Soft Delete:** The deletion strategy for recordings. Setting the `deleted_at` timestamp hides the recording from all queries while retaining the data for 30 days before permanent deletion.

**Step Functions:** AWS Step Functions, the orchestration service used to run the moderation pipeline as a state machine with built-in retry logic and execution history.

**ST_DWithin:** A PostGIS function that tests whether two geographic points are within a specified distance. Used in the discovery query to find nearby recordings.

## T

**Transcription:** The process of converting a recording's audio to text using AWS Transcribe. The resulting transcript is used for content moderation.

## Z

**Zod:** A TypeScript-first schema validation library used in backend Lambda handlers to validate incoming request bodies at runtime.
