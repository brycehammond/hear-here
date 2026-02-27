# Hear Here -- Glossary

## A

**AAC (Advanced Audio Coding):** The audio codec used for all recordings. AAC provides good compression with high quality for speech. Files use the `.m4a` container format.

**APNs (Apple Push Notification service):** Apple's service for delivering push notifications to iOS devices. Hear Here uses APNs via Azure Notification Hubs to notify users of moderation outcomes.

**API Management (Azure):** Azure API Management (Consumption tier) routes all client requests to the appropriate Azure Function, handles JWT validation via `validate-jwt` policy, and enforces rate limiting.

**App Configuration (Azure):** Azure App Configuration stores moderation thresholds and feature flags, allowing configuration changes without redeployment.

**Approved:** A recording moderation status indicating the content has passed review (automated or human) and is publicly discoverable.

**Auto-approve:** An automated moderation decision where all content classification scores fall below the safe threshold (< 0.3), causing the recording to be approved without human review.

**Auto-reject:** An automated moderation decision where any content classification score exceeds the unsafe threshold (> 0.7), causing the recording to be rejected without human review.

**Azure AI Speech:** Azure's managed speech-to-text service used for batch transcription of recording audio. The resulting transcript feeds the content moderation pipeline.

**Azure Functions:** The serverless compute platform hosting all backend API handlers. Functions run on the Consumption plan (dev/staging) or Premium plan (production) for VNet integration and pre-warmed instances.

## B

**Bicep:** Azure-native infrastructure-as-code language used to define and deploy all Azure resources. Compiles to ARM templates with no state file to manage.

**Blob Storage (Azure):** Azure's object storage service used to store audio files. Containers include `audio-pending`, `audio-approved`, and `audio-rejected` with lifecycle management policies.

## C

**Content Classification:** The process of evaluating a recording's transcript for policy violations using the OpenAI Moderation API. Returns per-category scores for hate, violence, sexual content, etc.

**Coordinator (iOS):** A design pattern used in the iOS app to manage navigation flow. Each tab has a coordinator that owns a `NavigationStack` and controls screen transitions.

**Cursor-based Pagination:** The pagination strategy used by the API. Instead of page numbers/offsets, each response includes an opaque cursor string that the client sends to fetch the next page.

## D

**Discovery:** The feature that allows users to find nearby recordings. Uses PostGIS spatial queries to find approved recordings within a given radius of the user's location.

**Discovery Radius:** The distance (in meters) within which recordings are returned to a user. Defaults to 500m, configurable up to 5,000m.

**Durable Functions (Azure):** An extension of Azure Functions that provides workflow orchestration. Used to run the moderation pipeline as a durable, checkpointed workflow with built-in retry logic and external event support for human review.

## E

**Event Grid (Azure):** Azure's event routing service. Blob Storage `BlobCreated` events are published via Event Grid to trigger the moderation pipeline when audio uploads complete.

## F

**Firebase Auth:** Google's authentication service used for user sign-in. Supports Sign in with Apple and Google Sign-In. Issues JWTs validated by Azure API Management.

**Firebase UID:** The unique identifier assigned to each user by Firebase Authentication. Used as the primary user identity across the system.

**Flexible Server:** Azure Database for PostgreSQL Flexible Server, the managed PostgreSQL hosting service. Includes built-in PgBouncer connection pooling at no additional cost.

**Front Door (Azure):** Azure Front Door provides CDN, global load balancing, and WAF capabilities in a single service. Used for low-latency audio delivery and admin UI hosting.

## G

**GiST Index:** Generalized Search Tree index type in PostgreSQL. Used by PostGIS for efficient spatial queries on the `recordings.location` column.

**Geography (PostGIS):** A PostGIS data type that represents points on the Earth's surface using latitude/longitude coordinates (SRID 4326). Used to store recording locations with geodesic distance calculations.

## H

**Human Review:** The moderation step where a content moderator manually reviews a recording that received uncertain automated classification scores. Performed via the admin UI. The Durable Functions orchestration waits for an external event to resume.

## J

**JWT (JSON Web Token):** The authentication token format issued by Firebase Auth. Sent as a Bearer token in the `Authorization` header of every API request. Validated by Azure API Management's `validate-jwt` inbound policy.

## K

**Key Vault (Azure):** Azure Key Vault stores secrets such as API keys, database credentials, and connection strings. Azure Functions access secrets via Key Vault references in app settings, using managed identity for authentication.

**Kysely:** A type-safe SQL query builder for TypeScript, used in the backend Azure Functions to interact with PostgreSQL. Provides type inference without ORM abstraction.

## L

**Location Pinning:** The act of attaching a geographic coordinate to a recording when it is created. The user can pin to their current location or adjust the pin manually.

## M

**Managed Identity:** Azure's system-assigned identity for services. Azure Functions use managed identity to access Blob Storage, Key Vault, Service Bus, and PostgreSQL without storing credentials.

**Moderation Pipeline:** The asynchronous workflow (Azure Durable Functions) that processes each new recording: transcription via Azure AI Speech, content classification via OpenAI Moderation API, decision logic, and notification.

**Moderation Record:** An immutable audit trail entry created for every moderation status change on a recording. Stored in the `moderation_records` table.

**MVVM (Model-View-ViewModel):** The architectural pattern used in the iOS app. Views observe ViewModels via `@Observable`, and ViewModels coordinate between views and services.

## N

**Notification Hubs (Azure):** Azure's managed push notification service. Delivers push notifications to iOS devices via APNs using tag-based targeting (e.g., `user:{uid}`).

## O

**OpenAI Moderation API:** An external API used to classify transcript text for content safety. Returns per-category scores (hate, violence, sexual, etc.) that drive moderation decisions.

## P

**Pending Moderation:** A recording status indicating the audio has been uploaded and is awaiting automated content analysis.

**Pending Review:** A recording status indicating automated moderation returned uncertain scores and the recording requires human review.

**PgBouncer:** A connection pooler for PostgreSQL, built into Azure Database for PostgreSQL Flexible Server. Critical for Azure Functions, which create short-lived connections on each invocation.

**PostGIS:** A spatial extension for PostgreSQL that adds geographic data types, spatial indexes, and functions like `ST_DWithin` for proximity queries.

## R

**Recording:** The core entity in Hear Here. An audio file attached to a geographic location with metadata (subject, description) that passes through moderation before becoming publicly discoverable.

**Rejected:** A recording moderation status indicating the content did not pass review. Rejected recordings are not discoverable and are permanently deleted after 30 days.

## S

**SAS URL (Shared Access Signature):** A time-limited, permission-scoped URL generated by the backend that allows the iOS app to upload audio directly to Blob Storage (write-only, 15-minute expiry) or stream audio via Front Door (read-only, 1-hour expiry) without exposing storage account credentials.

**Service Bus (Azure):** Azure's message queue service. Used for the human review queue with message sessions, dead-letter queue, and configurable lock duration.

**Soft Delete:** The deletion strategy for recordings. Setting the `deleted_at` timestamp hides the recording from all queries while retaining the data for 30 days before permanent deletion.

**ST_DWithin:** A PostGIS function that tests whether two geographic points are within a specified distance. Used in the discovery query to find nearby recordings.

## T

**Transcription:** The process of converting a recording's audio to text using Azure AI Speech (batch transcription API). The resulting transcript is used for content moderation.

## Z

**Zod:** A TypeScript-first schema validation library used in backend Azure Function handlers to validate incoming request bodies at runtime.
