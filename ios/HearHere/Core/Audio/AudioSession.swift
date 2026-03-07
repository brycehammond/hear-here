import AVFoundation
import Foundation

/// Manages AVAudioSession configuration for recording and playback.
///
/// Configures the audio session category based on the current use case,
/// and handles interruptions (e.g., phone calls) and route changes
/// (e.g., headphones plugged/unplugged).
///
/// The audio session must be configured before starting any audio operation.
/// Use ``configureForRecording()`` before recording and ``configureForPlayback()``
/// before playback to set the appropriate categories and options.
final class AudioSessionManager: Sendable {
    /// Notification name posted when an audio interruption begins.
    static let interruptionBegan = Notification.Name("AudioSessionInterruptionBegan")

    /// Notification name posted when an audio interruption ends with the option to resume.
    static let interruptionEndedShouldResume = Notification.Name("AudioSessionInterruptionEndedShouldResume")

    /// Notification name posted when the audio route changes (e.g., headphones connected/disconnected).
    static let routeChanged = Notification.Name("AudioSessionRouteChanged")

    #if os(iOS)
    private let session: AVAudioSession

    /// Creates an audio session manager for the shared audio session.
    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        registerForNotifications()
    }
    #else
    init() {}
    #endif

    /// Configures the audio session for recording audio.
    ///
    /// Sets the category to `.playAndRecord` with default mode, which allows
    /// simultaneous input and output. Activates the session.
    ///
    /// - Throws: If the audio session cannot be configured or activated.
    func configureForRecording() throws {
        #if os(iOS)
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif
    }

    /// Configures the audio session for audio playback.
    ///
    /// Sets the category to `.playback`, which enables audio output
    /// and respects the silent switch. Activates the session.
    ///
    /// - Throws: If the audio session cannot be configured or activated.
    func configureForPlayback() throws {
        #if os(iOS)
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
    }

    /// Deactivates the audio session.
    ///
    /// Call this when audio operations are complete to release system
    /// audio resources and allow other apps to use audio.
    ///
    /// - Throws: If the audio session cannot be deactivated.
    func deactivate() throws {
        #if os(iOS)
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Input Ports

    #if os(iOS)
    /// Returns the list of available audio input ports.
    func availableInputPorts() -> [AVAudioSessionPortDescription] {
        session.availableInputs ?? []
    }

    /// Selects the preferred audio input port.
    /// - Parameter port: The port description to set as the preferred input.
    /// - Throws: If the preferred input cannot be set.
    func selectInputPort(_ port: AVAudioSessionPortDescription) throws {
        try session.setPreferredInput(port)
    }
    #endif

    // MARK: - Private

    #if os(iOS)
    private func registerForNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                NotificationCenter.default.post(name: AudioSessionManager.interruptionBegan, object: nil)
            case .ended:
                let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let interruptionOptions = AVAudioSession.InterruptionOptions(rawValue: options)
                if interruptionOptions.contains(.shouldResume) {
                    NotificationCenter.default.post(
                        name: AudioSessionManager.interruptionEndedShouldResume,
                        object: nil
                    )
                }
            @unknown default:
                break
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { _ in
            NotificationCenter.default.post(name: AudioSessionManager.routeChanged, object: nil)
        }
    }
    #endif
}
