# Hear Here — iOS Application Architecture & UI Design

## 1. Architecture Overview

### Pattern: MVVM + Coordinator

**Choice:** Model-View-ViewModel (MVVM) with a lightweight coordinator pattern for navigation.

**Rationale:**
- MVVM is the natural fit for SwiftUI's declarative, state-driven UI. Views observe ViewModels via `@Observable`, and SwiftUI handles re-rendering automatically.
- TCA (The Composable Architecture) was considered but rejected: it adds significant boilerplate and a learning curve for a team that may include junior developers. The app's domain complexity does not warrant a full unidirectional data flow framework at this stage. If state management becomes unwieldy, TCA can be adopted incrementally per feature.
- Coordinators keep navigation logic out of Views and ViewModels, making flows testable and reusable.

### Dependency Injection

All services (API client, audio engine, location manager) are injected via SwiftUI's `@Environment` using custom `EnvironmentKey` types. This enables easy swapping for previews and tests without a DI framework.

### Concurrency

Swift 6 strict concurrency is adopted project-wide. All async work uses structured concurrency (`async`/`await`, `TaskGroup`). ViewModels are annotated `@MainActor` to guarantee UI-safe state updates.

---

## 2. Project Structure

```
ios/
└── HearHere/
    ├── App/
    │   ├── HearHereApp.swift              # @main entry point
    │   ├── AppCoordinator.swift           # Root navigation coordinator
    │   └── AppEnvironment.swift           # Environment setup, DI
    ├── Features/
    │   ├── Auth/
    │   │   ├── AuthCoordinator.swift
    │   │   ├── AuthViewModel.swift
    │   │   ├── SignInView.swift
    │   │   ├── OnboardingView.swift
    │   │   └── WelcomeView.swift
    │   ├── Discovery/
    │   │   ├── DiscoveryCoordinator.swift
    │   │   ├── MapViewModel.swift
    │   │   ├── MapView.swift
    │   │   ├── NearbyListView.swift
    │   │   ├── RecordingPinView.swift
    │   │   └── RecordingAnnotation.swift
    │   ├── Recording/
    │   │   ├── RecordingCoordinator.swift
    │   │   ├── RecordingViewModel.swift
    │   │   ├── RecordingView.swift
    │   │   ├── RecordingMetadataView.swift
    │   │   ├── LocationPickerView.swift
    │   │   └── RecordingConfirmationView.swift
    │   ├── Playback/
    │   │   ├── PlaybackViewModel.swift
    │   │   ├── PlaybackView.swift
    │   │   └── MiniPlayerView.swift
    │   ├── Profile/
    │   │   ├── ProfileCoordinator.swift
    │   │   ├── ProfileViewModel.swift
    │   │   ├── ProfileView.swift
    │   │   ├── MyRecordingsListView.swift
    │   │   └── RecordingDetailView.swift
    │   └── Settings/
    │       ├── SettingsViewModel.swift
    │       └── SettingsView.swift
    ├── Core/
    │   ├── Network/
    │   │   ├── APIClient.swift            # Central HTTP client
    │   │   ├── APIEndpoints.swift         # Endpoint definitions
    │   │   ├── APIError.swift             # Error types
    │   │   ├── AuthInterceptor.swift      # Attaches Firebase JWT
    │   │   └── DTOs/                      # Request/response Codable models
    │   │       ├── RecordingDTO.swift
    │   │       ├── UserDTO.swift
    │   │       └── NearbyQueryDTO.swift
    │   ├── Location/
    │   │   ├── LocationService.swift      # CoreLocation wrapper
    │   │   └── LocationPermission.swift   # Permission state machine
    │   ├── Audio/
    │   │   ├── AudioRecorder.swift        # AVAudioRecorder wrapper
    │   │   ├── AudioPlayer.swift          # AVPlayer wrapper for streaming
    │   │   └── AudioSession.swift         # AVAudioSession configuration
    │   ├── Auth/
    │   │   ├── AuthService.swift          # Firebase Auth wrapper
    │   │   └── AuthState.swift            # Observable auth state
    │   ├── Storage/
    │   │   ├── UploadManager.swift        # Background upload to S3
    │   │   └── CacheManager.swift         # Local audio cache
    │   └── Models/
    │       ├── Recording.swift            # Domain model
    │       ├── User.swift                 # Domain model
    │       └── ModerationStatus.swift     # Enum: pending, approved, rejected, pending_review
    ├── Shared/
    │   ├── Components/                    # Reusable UI components
    │   │   ├── StatusBadge.swift          # Moderation status indicator
    │   │   ├── AudioWaveformView.swift    # Waveform visualization
    │   │   ├── PermissionPromptView.swift # Generic permission request
    │   │   └── ErrorView.swift            # Inline error display
    │   ├── Extensions/
    │   │   ├── CLLocationCoordinate2D+.swift
    │   │   ├── Date+Formatting.swift
    │   │   └── Duration+Formatting.swift
    │   └── Styles/
    │       ├── Theme.swift                # Colors, typography, spacing
    │       └── ButtonStyles.swift
    └── Resources/
        ├── Assets.xcassets
        ├── Localizable.xcstrings
        └── Info.plist
```

---

## 3. Screen Inventory & Navigation Flow

### 3.1 Navigation Architecture

**Root:** `AppCoordinator` manages the top-level navigation state using a `NavigationStack` with a path-based approach.

```swift
@Observable
final class AppCoordinator {
    var authState: AuthGate = .loading
    var tabSelection: Tab = .discover

    enum AuthGate {
        case loading
        case onboarding
        case authenticated
    }

    enum Tab: Hashable {
        case discover
        case record
        case profile
    }
}
```

**Structure:**
```
AppCoordinator
├── AuthGate: .loading → SplashView
├── AuthGate: .onboarding → OnboardingFlow (NavigationStack)
│   ├── WelcomeView
│   └── SignInView
└── AuthGate: .authenticated → TabView
    ├── Tab: Discover → DiscoveryCoordinator (NavigationStack)
    │   ├── MapView (root)
    │   ├── NearbyListView (sheet)
    │   └── PlaybackView (push)
    ├── Tab: Record → RecordingCoordinator (NavigationStack)
    │   ├── RecordingView (root)
    │   ├── RecordingMetadataView (push)
    │   ├── LocationPickerView (sheet)
    │   └── RecordingConfirmationView (push)
    └── Tab: Profile → ProfileCoordinator (NavigationStack)
        ├── ProfileView (root)
        ├── MyRecordingsListView (embedded in ProfileView)
        ├── RecordingDetailView (push)
        ├── SettingsView (push)
        └── PlaybackView (push)
```

### 3.2 Screen Descriptions

#### Splash / Loading
- Shown while Firebase Auth restores the user session.
- Displays the app logo and a subtle activity indicator.
- Transitions to onboarding (no session) or main tab view (active session).

#### Onboarding Flow

**WelcomeView**
- App name, tagline ("Stories live here"), and illustration.
- Brief value proposition in 2-3 carousel cards:
  1. "Discover audio stories pinned to the world around you"
  2. "Record your own and share with the community"
  3. "Every story is reviewed to keep things safe"
- "Get Started" button advances to SignInView.

**SignInView**
- Sign in with Apple button (required for App Store).
- Sign in with Google button.
- "By continuing, you agree to our Terms of Service and Privacy Policy" footer with tappable links.
- On successful sign-in, transitions to the main tab view.

#### Discover Tab

**MapView (root)**
- Full-screen MapKit `Map` view centered on user's current location.
- Custom annotation pins for nearby approved recordings. Pin style: small circular icon with a waveform glyph; color intensity or size indicates recency.
- Tapping a pin shows a callout with subject, distance, and duration. Tapping the callout navigates to PlaybackView.
- Floating "re-center" button to snap back to current location.
- Bottom sheet (detent-based) showing NearbyListView as an alternative browse mode.
- Search radius defaults to 500m; expandable to 5km via a slider or segmented control in the list header.
- Pull-to-refresh on the list reloads nearby recordings.
- Empty state: friendly illustration + "No stories nearby yet. Be the first to record one!" with a button linking to the Record tab.

**NearbyListView (bottom sheet)**
- List of nearby recordings sorted by distance.
- Each row: subject, distance ("120m away"), duration, creator display name.
- Tapping a row navigates to PlaybackView.

#### Playback Screen

**PlaybackView**
- Large card with subject and description.
- Creator display name and "recorded X ago" timestamp.
- Small map snippet showing the recording's pinned location.
- Audio player controls: play/pause, scrub bar with elapsed/remaining time.
- Audio streams from CloudFront signed URL via `AVPlayer`.
- "Report" button (ellipsis menu) to flag inappropriate content.
- Share button to generate a deep link (future feature; placeholder).

**MiniPlayerView**
- Persistent mini-player bar at the bottom of the tab view when audio is actively playing.
- Shows subject, play/pause toggle, and a progress bar.
- Tapping expands to the full PlaybackView.

#### Record Tab

**RecordingView (root)**
- Central record button (large, circular, red) with tap-to-start, tap-to-stop behavior.
- Live recording timer showing elapsed time.
- Audio waveform visualization during recording (simplified amplitude bars).
- Max recording duration: 5 minutes. A countdown appears in the last 30 seconds. Recording auto-stops at 5:00.
- Cancel button to discard and return to idle state.
- On stop, advances to RecordingMetadataView.
- Permission gate: if microphone permission is not granted, shows a prompt explaining why it is needed with a button to open Settings.

**RecordingMetadataView (push)**
- Subject text field (required, max 200 chars).
- Description text area (optional, max 1000 chars).
- Location preview: small map with a draggable pin initialized to the user's current location.
- "Adjust Location" button opens LocationPickerView.
- Audio preview: playback of the just-recorded file.
- "Re-record" button to go back and discard.
- "Submit" button to proceed.

**LocationPickerView (sheet)**
- Full-screen map with a draggable pin.
- Search bar for geocoding an address.
- "Use Current Location" button.
- "Confirm" button saves the selected coordinate and dismisses.

**RecordingConfirmationView (push)**
- Summary card: subject, description snippet, location on mini-map, duration.
- "Upload" button initiates the upload flow.
- Progress indicator during upload.
- On success: "Your recording is being reviewed!" message with estimated review time. Button to view in Profile.
- On failure: retry option with error message.

#### Profile Tab

**ProfileView (root)**
- User avatar (from sign-in provider), display name, email.
- "Edit Profile" row (display name only; navigates inline).
- Section: "My Recordings" with count badge.
- MyRecordingsListView embedded below.
- "Settings" navigation link.

**MyRecordingsListView (embedded)**
- List of the user's recordings sorted by creation date (newest first).
- Each row: subject, date, duration, and a `StatusBadge` showing moderation status.
  - `pending_moderation` / `pending_review`: orange clock icon, "Under Review".
  - `approved`: green checkmark, "Published".
  - `rejected`: red x-mark, "Not Published".
- Tapping a row navigates to RecordingDetailView.
- Swipe-to-delete for own recordings (with confirmation alert).

**RecordingDetailView (push)**
- Full details: subject, description, location map, duration, creation date.
- Prominent moderation status badge with explanation text:
  - Pending: "Your recording is being reviewed. This usually takes less than an hour."
  - Approved: "Your recording is live and discoverable by others nearby."
  - Rejected: "Your recording did not meet our community guidelines." (with option to contact support — future).
- Audio preview (play own recording regardless of status).
- Delete button.

#### Settings

**SettingsView (push from Profile)**
- Account section: email (read-only), sign-out button.
- Notifications toggle (push notification preference).
- About section: app version, terms of service, privacy policy, open-source licenses.
- "Delete Account" button with confirmation flow (deletes Firebase user + all recordings server-side).

---

## 4. Technology Choices

### 4.1 UI Framework: SwiftUI

- Primary UI framework. All views built in SwiftUI.
- Minimum deployment target: **iOS 17**. This gives access to `@Observable` macro, `NavigationStack` with typed paths, `MapKit` SwiftUI integration, and bottom sheet detents.
- UIKit is only used where SwiftUI gaps exist (none anticipated for this app's scope).

### 4.2 Maps: MapKit

- `Map` view with `Annotation` for recording pins.
- `MKLocalSearch` for geocoding in LocationPickerView.
- Clustering via `MapKit`'s built-in annotation clustering for dense areas.
- No third-party map SDK needed.

### 4.3 Audio: AVFoundation

- **Recording:** `AVAudioRecorder` with AAC codec (see Section 5).
- **Playback:** `AVPlayer` for streaming from CloudFront signed URLs. `AVPlayer` supports HTTP progressive download, enabling playback before the full file is downloaded.
- **Audio Session:** Configured via `AVAudioSession` with category `.playAndRecord` during recording and `.playback` during playback. Handles interruptions (phone calls) and route changes (headphones plugged/unplugged).

### 4.4 Authentication: Firebase Auth SDK

- `FirebaseAuth` Swift package.
- `ASAuthorizationController` integration for Sign in with Apple.
- `GoogleSignIn` SDK for Google sign-in.
- Token refresh handled automatically by Firebase SDK.
- `AuthService` wraps Firebase to expose a clean `@Observable` `AuthState`.

### 4.5 Networking: URLSession-Based API Client

**No third-party HTTP library.** `URLSession` with `async`/`await` is sufficient.

```swift
@Observable
final class APIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let authService: AuthService

    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        type: T.Type
    ) async throws -> T
}
```

**Key behaviors:**
- `AuthInterceptor` automatically attaches the Firebase JWT to every request. If a 401 is received, it refreshes the token once and retries.
- `JSONDecoder` with `.iso8601` date strategy and `keyDecodingStrategy = .convertFromSnakeCase`.
- Errors mapped to typed `APIError` enum: `.unauthorized`, `.notFound`, `.serverError(statusCode:)`, `.networkUnavailable`, `.decodingError`.
- No Combine; all async.

### 4.6 Location: CoreLocation

- `CLLocationManager` wrapped in `LocationService` (an `@Observable` class).
- Requests `.whenInUse` authorization (no background location needed).
- Provides a `currentLocation` published property for the map and recording features.
- Uses `CLLocationManager.startUpdatingLocation()` for the map view; stops updates when the view disappears.
- Accuracy: `kCLLocationAccuracyBest` during recording (to pin accurately), `kCLLocationAccuracyHundredMeters` for discovery (saves battery).

---

## 5. Audio Recording Implementation

### 5.1 Format & Quality

| Setting | Value | Rationale |
|---------|-------|-----------|
| Codec | AAC (`kAudioFormatMPEG4AAC`) | Excellent compression/quality ratio; natively supported on iOS and via CloudFront |
| Sample Rate | 44,100 Hz | Standard for speech; no benefit to going higher |
| Bit Rate | 64 kbps | Sufficient for voice; keeps files small (~480 KB/min) |
| Channels | Mono | Speech is mono; halves file size vs. stereo |
| Container | `.m4a` (MPEG-4) | Standard AAC container; broad compatibility |

**Maximum file size estimate:** 5 minutes at 64 kbps mono = ~2.4 MB.

### 5.2 Recording Configuration

```swift
let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 44_100,
    AVNumberOfChannelsKey: 1,
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    AVEncoderBitRateKey: 64_000
]
```

### 5.3 Maximum Duration

- Hard limit: **5 minutes** (enforced client-side and validated server-side).
- A countdown timer appears at 4:30.
- Recording auto-stops at 5:00 with a gentle notification.
- Rationale: keeps stories concise, limits storage costs, speeds up moderation (transcription is billed per minute).

### 5.4 Upload Strategy

**Pre-signed URL upload via `URLSession` background upload task.**

Flow:
1. App calls `POST /v1/recordings` with metadata. Server responds with a pre-signed S3 PUT URL (15-minute expiry).
2. App creates a `URLSessionUploadTask` using a **background `URLSession` configuration**. This allows the upload to continue if the user backgrounds the app.
3. The upload task PUTs the `.m4a` file directly to S3.
4. S3 event notification triggers the moderation pipeline server-side.

**Resume support:** Background `URLSession` tasks are automatically retried by the OS on network failure. For explicit retry, the app stores the pre-signed URL and recording file path locally and re-creates the upload task on next launch if the previous one failed.

**Upload progress:** Tracked via `URLSessionTaskDelegate.urlSession(_:task:didSendBodyData:)` and exposed to the UI through `UploadManager`.

```swift
final class UploadManager: @unchecked Sendable {
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "app.hearhere.upload"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func upload(fileURL: URL, to presignedURL: URL) -> UploadTask
}
```

---

## 6. Offline Capability Strategy

### Scope: Minimal Offline, Graceful Degradation

Full offline mode is not a launch requirement. The strategy is to degrade gracefully and cache where practical.

### What works offline:
- **Draft recordings:** Audio files are saved locally. If the network is unavailable, the recording is queued locally and uploaded when connectivity returns.
- **Cached discovery data:** The most recently fetched nearby recordings list is cached (in-memory + disk). If the user opens the app offline, they see the last-known nearby recordings.
- **Cached audio:** Any previously played audio file can be replayed from the local cache (managed by `CacheManager`, LRU eviction, 100 MB cap).
- **Profile and own recordings list:** Cached from last fetch.

### What requires connectivity:
- Discovering new nearby recordings (requires API call).
- Uploading recordings (queued until online).
- Authentication (initial sign-in).
- Streaming audio not previously cached.

### Implementation:
- `CacheManager` stores audio files on disk with LRU eviction.
- `UploadManager` persists pending uploads to a local JSON file and processes the queue on `NWPathMonitor` connectivity change.
- `NWPathMonitor` is used to observe network status. A `NetworkMonitor` service publishes connectivity state, and the UI shows a non-intrusive banner ("You're offline. Some features are unavailable.") when disconnected.

---

## 7. Permission Handling

### 7.1 Permissions Required

| Permission | When Requested | Usage |
|------------|---------------|-------|
| Microphone (`.microphone`) | When user first taps Record | Audio recording |
| Location (`.locationWhenInUse`) | When user first opens Discover tab or Record tab | Map centering, discovery queries, pinning recording location |
| Push Notifications | After first recording upload | Moderation result notifications |

### 7.2 UX Flow

Permissions are requested **just-in-time**, not at app launch. Each permission follows this pattern:

1. **Pre-prompt screen:** Before triggering the system dialog, show a custom screen explaining *why* the permission is needed, with the app's own branding. Example for microphone: "Hear Here needs microphone access to record your stories." with an illustration and a "Continue" button.
2. **System dialog:** Triggered by the "Continue" button. This is the standard iOS permission dialog.
3. **Denied state:** If the user denies, the feature area shows a non-blocking explanation with a "Open Settings" button that deep-links to the app's Settings page via `UIApplication.openSettingsURLString`.
4. **No repeated nagging:** If denied, the app does not re-ask. The settings link is always available.

### 7.3 Location-Specific Handling

- Only `.whenInUse` is requested. Background location is unnecessary.
- If location is denied, the Discover tab shows a search-by-address fallback (geocode a typed address to query nearby recordings).
- Recording without location permission: the user must manually place the pin on LocationPickerView instead of auto-centering.

### 7.4 Notification Permission

- Requested after the user's first successful recording upload, with context: "Want to know when your recording is approved? Enable notifications."
- Not required for core functionality; moderation status is also visible in the Profile tab.

---

## 8. State Management

### 8.1 Approach: @Observable + SwiftUI Environment

SwiftUI's native `@Observable` macro (iOS 17+) replaces the need for Combine-based `ObservableObject`. Each ViewModel is an `@Observable` class annotated with `@MainActor`.

### 8.2 State Layers

| Layer | Mechanism | Scope |
|-------|-----------|-------|
| View state (form fields, toggles) | `@State` | Single view |
| Feature state (recording flow, map state) | `@Observable` ViewModel | Feature scope, owned by coordinator |
| App-wide state (auth, current user, network status) | `@Observable` services in `@Environment` | Global |
| Persisted state (cached recordings, pending uploads) | `UserDefaults` / files on disk via services | Across launches |

### 8.3 Data Flow

```
View (@State for local UI state)
  ↓ calls methods on
ViewModel (@Observable, @MainActor)
  ↓ calls
Services (APIClient, AudioRecorder, LocationService, etc.)
  ↓
ViewModel updates its published properties
  ↓
SwiftUI re-renders View
```

### 8.4 Example ViewModel

```swift
@Observable
@MainActor
final class MapViewModel {
    private let apiClient: APIClient
    private let locationService: LocationService

    var recordings: [Recording] = []
    var selectedRecording: Recording?
    var isLoading = false
    var error: AppError?
    var searchRadius: Double = 500 // meters

    init(apiClient: APIClient, locationService: LocationService) {
        self.apiClient = apiClient
        self.locationService = locationService
    }

    func loadNearby() async {
        guard let location = locationService.currentLocation else { return }
        isLoading = true
        error = nil
        do {
            recordings = try await apiClient.request(
                .nearbyRecordings(
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    radius: searchRadius
                ),
                type: [Recording].self
            )
        } catch {
            self.error = AppError(error)
        }
        isLoading = false
    }
}
```

---

## 9. Navigation Architecture

### 9.1 NavigationStack with Typed Paths

Each tab has its own `NavigationStack` with a typed navigation path. This keeps navigation state explicit and programmatically controllable.

```swift
@Observable
final class DiscoveryCoordinator {
    var path = NavigationPath()

    enum Destination: Hashable {
        case playback(Recording)
    }

    func showPlayback(_ recording: Recording) {
        path.append(Destination.playback(recording))
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}
```

### 9.2 Tab-Level Structure

```swift
struct MainTabView: View {
    @State private var appCoordinator: AppCoordinator

    var body: some View {
        TabView(selection: $appCoordinator.tabSelection) {
            Tab("Discover", systemImage: "map", value: .discover) {
                DiscoveryNavigationView()
            }
            Tab("Record", systemImage: "mic.circle.fill", value: .record) {
                RecordingNavigationView()
            }
            Tab("Profile", systemImage: "person", value: .profile) {
                ProfileNavigationView()
            }
        }
    }
}
```

### 9.3 Sheets and Modals

- **Bottom sheet (NearbyListView):** Presented using `.sheet` with `presentationDetents([.medium, .large])`.
- **LocationPickerView:** Presented as a full-screen `.sheet`.
- **Confirmation dialogs:** Standard `.alert` and `.confirmationDialog` modifiers.

### 9.4 Deep Linking (Future)

The coordinator pattern supports deep linking by parsing a URL into a `Destination` and pushing it onto the appropriate tab's navigation path. The structure is ready for this but implementation is deferred to a future milestone.

---

## 10. Accessibility

### 10.1 VoiceOver

- All interactive elements have descriptive `accessibilityLabel` and `accessibilityHint`.
- Map pins include accessible descriptions: "Recording: [subject], [distance] away, [duration]".
- Audio player controls: "Play [subject]", "Pause", "Seek to [time]".
- StatusBadge announces moderation status: "Status: Under Review", "Status: Published".
- Custom waveform views provide a text summary via `accessibilityRepresentation`.

### 10.2 Dynamic Type

- All text uses semantic font styles (`.title`, `.body`, `.caption`) and scales with Dynamic Type.
- Layout is tested at the largest accessibility text sizes; views use `ScrollView` where content may overflow.
- No hardcoded font sizes.

### 10.3 Color & Contrast

- Moderation status communicated via both color AND icon/text (not color alone).
- All colors meet WCAG 2.1 AA contrast ratios (4.5:1 for body text, 3:1 for large text).
- Supports both light and dark mode via semantic asset catalog colors.

### 10.4 Motor Accessibility

- All tap targets are at least 44x44 points.
- The record button is large (80pt diameter) and centrally placed.
- Swipe-to-delete has an alternative via an explicit delete button in RecordingDetailView.
- No gestures that require multi-finger or complex motion; all interactions have a tap-based alternative.

### 10.5 Audio Accessibility

- Recordings have subject and description text that serve as an alternative for users who cannot hear audio.
- Future consideration: display transcript (from moderation pipeline) as a text alternative on PlaybackView.

---

## 11. Error Handling Strategy

### 11.1 User-Facing Errors

Errors are displayed contextually near the failed action, not as modal alerts (which are disruptive).

| Error Type | UI Treatment |
|-----------|-------------|
| Network unavailable | Top banner: "No internet connection" (persists while offline) |
| API error (4xx/5xx) | Inline error view below the failed content area with a "Retry" button |
| Upload failure | Recording confirmation screen shows error with "Retry Upload" button |
| Location unavailable | Contextual message in map view with "Open Settings" link |
| Microphone denied | Full-screen prompt on Record tab explaining how to enable |

### 11.2 Error Types

```swift
enum AppError: LocalizedError {
    case networkUnavailable
    case unauthorized
    case serverError(statusCode: Int)
    case notFound
    case uploadFailed(underlying: Error)
    case locationUnavailable
    case microphoneDenied
    case recordingTooLong
    case unknown(Error)

    var errorDescription: String? { /* user-friendly message */ }
    var recoverySuggestion: String? { /* actionable suggestion */ }
}
```

---

## 12. Testing Strategy

### 12.1 Architecture for Testability

- All services conform to protocols, enabling mock injection.
- ViewModels receive service dependencies via initializer injection.
- No singletons; all state is owned and injected.

### 12.2 Test Layers

| Layer | Framework | What to Test |
|-------|-----------|-------------|
| ViewModels | XCTest + Swift Testing | Business logic, state transitions, error handling |
| Services | XCTest | API client request building, response parsing, error mapping |
| Views | Xcode Previews | Visual verification of all states (loading, error, empty, populated) |
| Integration | XCUITest | Critical user flows: sign in, record, upload, discover, playback |
| Snapshots | `swift-snapshot-testing` (optional) | Regression testing for key screens |

### 12.3 Preview Strategy

Every view has a Xcode Preview with:
- Mock data for the populated state.
- Empty state.
- Error state.
- Loading state.

This enables rapid visual iteration without running the full app.

---

## 13. Third-Party Dependencies

| Dependency | Purpose | Justification |
|-----------|---------|--------------|
| `firebase-ios-sdk` (Auth module only) | Authentication | Required for Firebase Auth |
| `google-sign-in-ios` | Google Sign-In | Required for Google auth provider |

**Philosophy:** Minimize third-party dependencies. URLSession replaces Alamofire. SwiftUI + @Observable replaces Combine-heavy patterns. MapKit replaces Mapbox. The only external dependencies are auth-related SDKs where there is no practical first-party alternative.

---

## 14. Build & Configuration

### 14.1 Environments

| Environment | API Base URL | Firebase Project |
|------------|-------------|-----------------|
| Development | `https://dev-api.hearhere.app/v1` | `hearhere-dev` |
| Staging | `https://staging-api.hearhere.app/v1` | `hearhere-staging` |
| Production | `https://api.hearhere.app/v1` | `hearhere-prod` |

Configuration is managed via Xcode build configurations and `.xcconfig` files. `Info.plist` references environment variables for the API base URL and Firebase config file path.

### 14.2 Swift Package Manager

All dependencies are managed via SPM (no CocoaPods or Carthage).

### 14.3 Minimum Requirements

- **iOS 17.0+**
- **Swift 6**
- **Xcode 16+**
