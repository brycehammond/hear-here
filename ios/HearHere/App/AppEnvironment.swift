import SwiftUI

// MARK: - Environment Keys

struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient = APIClient(
        baseURL: URL(string: "https://dev-api.hearhere.app/v1")!,
        authInterceptor: AuthInterceptor(tokenProvider: AppPreviewTokenProvider())
    )
}

struct AuthServiceKey: EnvironmentKey {
    static let defaultValue: any AuthServiceProtocol = PreviewAuthService()
}

struct LocationServiceKey: EnvironmentKey {
    static let defaultValue: any LocationServiceProtocol = LocationService()
}

struct AudioRecorderKey: EnvironmentKey {
    static let defaultValue: any AudioRecorderProtocol = AudioRecorder()
}

struct AudioPlayerKey: EnvironmentKey {
    static let defaultValue: any AudioPlayerProtocol = AudioPlayer()
}

struct AudioEngineKey: EnvironmentKey {
    static let defaultValue: any AudioEngineProtocol = AudioEngine()
}

struct UploadManagerKey: EnvironmentKey {
    static let defaultValue: UploadManager = UploadManager()
}

struct CacheManagerKey: EnvironmentKey {
    static let defaultValue: CacheManager = CacheManager()
}

struct NetworkMonitorKey: EnvironmentKey {
    static let defaultValue: NetworkMonitor = NetworkMonitor()
}

// MARK: - EnvironmentValues Extensions

extension EnvironmentValues {
    var apiClient: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }

    var authService: any AuthServiceProtocol {
        get { self[AuthServiceKey.self] }
        set { self[AuthServiceKey.self] = newValue }
    }

    var locationService: any LocationServiceProtocol {
        get { self[LocationServiceKey.self] }
        set { self[LocationServiceKey.self] = newValue }
    }

    var audioRecorder: any AudioRecorderProtocol {
        get { self[AudioRecorderKey.self] }
        set { self[AudioRecorderKey.self] = newValue }
    }

    var audioPlayer: any AudioPlayerProtocol {
        get { self[AudioPlayerKey.self] }
        set { self[AudioPlayerKey.self] = newValue }
    }

    var audioEngine: any AudioEngineProtocol {
        get { self[AudioEngineKey.self] }
        set { self[AudioEngineKey.self] = newValue }
    }

    var uploadManager: UploadManager {
        get { self[UploadManagerKey.self] }
        set { self[UploadManagerKey.self] = newValue }
    }

    var cacheManager: CacheManager {
        get { self[CacheManagerKey.self] }
        set { self[CacheManagerKey.self] = newValue }
    }

    var networkMonitor: NetworkMonitor {
        get { self[NetworkMonitorKey.self] }
        set { self[NetworkMonitorKey.self] = newValue }
    }
}

// MARK: - App Environment Factory

/// Factory for creating real and preview service environments.
enum AppEnvironment {

    /// Configures the real production/development environment services.
    static func configureReal(
        authService: AuthService
    ) -> some View {
        let interceptor = AuthInterceptor(tokenProvider: authService)
        let baseURLString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://dev-api.hearhere.app/v1"
        let baseURL = URL(string: baseURLString)!
        let apiClient = APIClient(baseURL: baseURL, authInterceptor: interceptor)
        let locationService = LocationService()
        let audioRecorder = AudioRecorder()
        let audioPlayer = AudioPlayer()
        let audioEngine = AudioEngine()
        let uploadManager = UploadManager()
        let cacheManager = CacheManager()
        let networkMonitor = NetworkMonitor()

        return EmptyView()
            .environment(\.apiClient, apiClient)
            .environment(\.authService, authService)
            .environment(\.locationService, locationService)
            .environment(\.audioRecorder, audioRecorder)
            .environment(\.audioPlayer, audioPlayer)
            .environment(\.audioEngine, audioEngine)
            .environment(\.uploadManager, uploadManager)
            .environment(\.cacheManager, cacheManager)
            .environment(\.networkMonitor, networkMonitor)
    }
}

// MARK: - Preview Helpers

/// Minimal token provider for SwiftUI previews and environment defaults.
final class AppPreviewTokenProvider: TokenProviding {
    func currentToken() async throws -> String { "preview-token" }
    func refreshToken() async throws -> String { "preview-token-refreshed" }
}

/// Minimal auth service for SwiftUI previews and environment defaults.
@Observable
final class PreviewAuthService: @unchecked Sendable, AuthServiceProtocol {
    var state: AuthState = .signedOut

    func signInWithApple(authorization: ASAuthorization) async throws -> User {
        let user = User.preview
        state = .signedIn(user)
        return user
    }

    func signInInteractively() async throws -> User {
        let user = User.preview
        state = .signedIn(user)
        return user
    }

    func signOut() throws {
        state = .signedOut
    }

    func restoreSession() async {
        state = .signedOut
    }
}

// MARK: - Preview Data

extension User {
    static let preview = User(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        displayName: "Jane Explorer",
        email: "jane@example.com",
        recordingCount: 12,
        createdAt: Date().addingTimeInterval(-86400 * 30)
    )
}

extension Recording {
    static let previewNearby = Recording(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        userId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        subject: "Sunset at Golden Gate Bridge",
        description: "The sound of waves crashing against the shore as the sun sets behind the bridge.",
        latitude: 37.8199,
        longitude: -122.4783,
        durationSeconds: 154,
        status: .approved,
        createdAt: Date().addingTimeInterval(-3600),
        distanceMeters: 120
    )

    static let previewPending = Recording(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        userId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        subject: "Morning Birds in the Park",
        description: "A chorus of birds at dawn in Golden Gate Park.",
        latitude: 37.7694,
        longitude: -122.4862,
        durationSeconds: 87,
        status: .pendingModeration,
        createdAt: Date().addingTimeInterval(-600),
        distanceMeters: 350
    )

    static let previewRejected = Recording(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
        userId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        subject: "Street Sounds",
        description: nil,
        latitude: 37.7749,
        longitude: -122.4194,
        durationSeconds: 42,
        status: .rejected,
        createdAt: Date().addingTimeInterval(-86400),
        distanceMeters: nil
    )

    static let previewList: [Recording] = [
        .previewNearby,
        .previewPending,
        Recording(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            userId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            subject: "Cable Car Bell",
            description: "The distinctive ring of a cable car on Powell Street.",
            latitude: 37.7855,
            longitude: -122.4098,
            durationSeconds: 23,
            status: .approved,
            createdAt: Date().addingTimeInterval(-7200),
            distanceMeters: 480
        ),
        Recording(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            userId: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            subject: "Chinatown Ambience",
            description: "The busy sounds of Chinatown during lunchtime.",
            latitude: 37.7941,
            longitude: -122.4078,
            durationSeconds: 210,
            status: .approved,
            createdAt: Date().addingTimeInterval(-14400),
            distanceMeters: 750
        ),
    ]
}

import AuthenticationServices
