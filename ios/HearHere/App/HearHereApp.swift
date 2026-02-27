import SwiftUI

/// The main entry point for the Hear Here iOS application.
///
/// Sets up the service environment (backed by Azure AD B2C via MSAL)
/// and shows the appropriate root view based on the app coordinator's
/// auth gate state: a loading splash, the onboarding/sign-in flow,
/// or the main tab view.
@main
struct HearHereApp: App {
    @State private var coordinator: AppCoordinator
    @State private var authService: AuthService
    @State private var apiClient: APIClient
    @State private var locationService: LocationService
    @State private var audioRecorder: AudioRecorder
    @State private var audioPlayer: AudioPlayer
    @State private var uploadManager: UploadManager
    @State private var cacheManager: CacheManager
    @State private var networkMonitor: NetworkMonitor

    init() {
        let auth = AuthService()
        let interceptor = AuthInterceptor(tokenProvider: auth)
        let baseURLString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "https://dev-api.hearhere.app/v1"
        let baseURL = URL(string: baseURLString)!

        _authService = State(initialValue: auth)
        _coordinator = State(initialValue: AppCoordinator(authService: auth))
        _apiClient = State(initialValue: APIClient(baseURL: baseURL, authInterceptor: interceptor))
        _locationService = State(initialValue: LocationService())
        _audioRecorder = State(initialValue: AudioRecorder())
        _audioPlayer = State(initialValue: AudioPlayer())
        _uploadManager = State(initialValue: UploadManager())
        _cacheManager = State(initialValue: CacheManager())
        _networkMonitor = State(initialValue: NetworkMonitor())
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(\.apiClient, apiClient)
                .environment(\.authService, authService)
                .environment(\.locationService, locationService)
                .environment(\.audioRecorder, audioRecorder)
                .environment(\.audioPlayer, audioPlayer)
                .environment(\.uploadManager, uploadManager)
                .environment(\.cacheManager, cacheManager)
                .environment(\.networkMonitor, networkMonitor)
                .task {
                    await coordinator.restoreSession()
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch coordinator.authState {
        case .loading:
            splashView
        case .onboarding:
            OnboardingView(coordinator: coordinator)
        case .authenticated:
            mainTabView
        }
    }

    private var splashView: some View {
        VStack(spacing: Theme.spacingMD) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Hear Here")
                .font(.largeTitle.weight(.bold))
            ProgressView()
                .padding(.top, Theme.spacingSM)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hear Here, loading")
    }

    private var mainTabView: some View {
        TabView(selection: $coordinator.tabSelection) {
            MapView()
                .tabItem {
                    Label("Discover", systemImage: "map")
                }
                .tag(AppCoordinator.Tab.discover)

            // Placeholder until recording feature is built
            Text("Record")
                .tabItem {
                    Label("Record", systemImage: "mic.circle.fill")
                }
                .tag(AppCoordinator.Tab.record)

            // Placeholder until profile feature is built
            Text("Profile")
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(AppCoordinator.Tab.profile)
        }
    }
}
