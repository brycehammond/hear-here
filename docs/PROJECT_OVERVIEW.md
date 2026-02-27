# Hear Here -- Project Overview

## Mission

Hear Here connects people to places through audio storytelling. Users record short audio stories tied to real-world locations, creating a living, location-based layer of human experience. Every recording is moderated for safety before becoming discoverable by others who are physically nearby.

## Target Audience

- **Storytellers and local historians** who want to share knowledge about places -- their history, culture, architecture, or personal significance.
- **Explorers and travelers** who want to discover the stories behind the places they visit.
- **Community members** who want to contribute to a richer, more connected sense of place.

The initial audience is English-speaking iOS users in the United States, with planned expansion to additional languages and regions.

## Key Features

### Record Audio Stories
Users record audio (up to 5 minutes) and pin it to a real-world location. They provide a subject and optional description. The audio is uploaded in the background, even if the user switches apps.

**User story:** As a user, I want to record an audio story about a place I care about, so others can hear it when they visit.

### Content Moderation
Every recording passes through an automated moderation pipeline before becoming public. Audio is transcribed and analyzed for policy violations. High-confidence decisions are automated; uncertain cases are routed to human reviewers. Users receive push notifications when their recording is approved or rejected.

**User story:** As a user, I want to know that the content I encounter is safe and appropriate, so I can trust the platform.

### Discover Nearby Recordings
Users open a map centered on their location and see pins for approved recordings within a configurable radius (default 500m, up to 5km). A list view provides an alternative browsing experience.

**User story:** As a user, I want to discover audio stories near my current location, so I can learn about the places around me.

### Stream Audio Playback
Tapping a recording streams the audio from a CDN. A mini-player persists at the bottom of the screen while navigating. Play events are tracked for analytics.

**User story:** As a user, I want to listen to recordings while I walk, so I can experience stories in the places they describe.

### User Profile and Recording Management
Users can view their own recordings with moderation status, delete recordings, and manage their profile and account settings. Account deletion is supported for privacy compliance.

**User story:** As a user, I want to see the status of my recordings and manage my account, so I have control over my content and data.

### Content Reporting
Users can report recordings they believe violate community guidelines. Recordings that accumulate multiple reports are automatically sent for human review.

**User story:** As a user, I want to report inappropriate content, so the platform remains safe for everyone.

## MVP Scope

The MVP includes the following:

| Feature | Included in MVP |
|---------|:---------------:|
| Sign in with Apple / Google | Yes |
| Record audio (up to 5 min, AAC) | Yes |
| Pin recording to location with subject and description | Yes |
| Background upload to Azure Blob Storage | Yes |
| Automated content moderation (transcription + classification) | Yes |
| Human review queue with admin UI | Yes |
| Push notifications for moderation outcomes | Yes |
| Map-based discovery with nearby recordings | Yes |
| List view of nearby recordings | Yes |
| Audio streaming playback with mini-player | Yes |
| User profile with recording list and status | Yes |
| Recording deletion | Yes |
| Content reporting | Yes |
| Account deletion | Yes |
| Offline draft recordings (queued upload) | Yes |
| Cached playback of previously heard recordings | Yes |
| Tags and categories | No (post-MVP) |
| Likes and play counts (visible to users) | No (post-MVP) |
| Social features (following, comments) | No (post-MVP) |
| Android app | No (post-MVP) |
| Multi-language transcription | No (post-MVP) |
| Deep linking / sharing | No (post-MVP) |
| Transcript display on playback | No (post-MVP) |

## Architecture Summary

- **iOS app:** SwiftUI + Swift 6, MVVM + Coordinator pattern, iOS 17+
- **Backend:** Node.js 20 (TypeScript) on Azure Functions, behind Azure API Management
- **Database:** PostgreSQL 16 with PostGIS on Azure Database for PostgreSQL Flexible Server
- **Audio storage:** Azure Blob Storage with Azure Front Door CDN
- **Moderation:** Azure Durable Functions orchestrating Azure AI Speech + OpenAI Moderation API
- **Authentication:** Firebase Auth (Sign in with Apple, Google Sign-In)
- **Infrastructure:** Bicep (Azure-native IaC)
- **CI/CD:** GitHub Actions

For full technical details, see the design documents in the [docs/](.) directory:
- [ARCHITECTURE.md](./ARCHITECTURE.md) -- System architecture and technology decisions
- [DATABASE.md](./DATABASE.md) -- Database schema and data model
- [BACKEND.md](./BACKEND.md) -- Backend API and service design
- [IOS_APP.md](./IOS_APP.md) -- iOS app architecture and UI design
- [CLOUD_ARCHITECTURE.md](./CLOUD_ARCHITECTURE.md) -- Cloud infrastructure and deployment

## Future Roadmap

### Near-term (post-MVP)
- Tags and categories for recordings
- Visible like and play counts
- Transcript display on playback view
- Deep linking and sharing of recordings

### Medium-term
- Android app (backend is platform-agnostic)
- Multi-language transcription and content moderation
- Social features (following creators, activity feed)
- Curated walking tours and playlists

### Long-term
- Multi-region deployment for global coverage
- Offline mode with pre-downloaded area packs
- AR integration for spatial audio experiences
- Partner/institutional accounts for museums, parks, and cultural organizations
