import AuthenticationServices
import SwiftUI

/// Sign-in screen with Apple and B2C interactive authentication options.
///
/// Provides Sign in with Apple (required for App Store) and a general
/// sign-in button (B2C hosted UI), along with a terms/privacy footer
/// with tappable links.
struct SignInView: View {
    @Bindable var viewModel: AuthViewModel
    var onEmailSignIn: () -> Void = {}

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            // Header
            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("Sign In")
                    .font(.title.weight(.bold))

                Text("Choose how you'd like to sign in")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            // Sign-in buttons
            VStack(spacing: Theme.spacingMD) {
                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task {
                        await viewModel.handleAppleSignIn(result: result)
                    }
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(minHeight: Theme.minTapTarget)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                .accessibilityLabel("Sign in with Apple")

                // Sign in with Google
                Button {
                    Task {
                        await viewModel.signInWithGoogle()
                    }
                } label: {
                    HStack(spacing: Theme.spacingSM) {
                        GoogleLogo()
                            .frame(width: 18, height: 18)
                        Text("Continue with Google")
                            .font(.body.weight(.semibold))
                    }
                }
                .buttonStyle(GoogleButtonStyle())
                .accessibilityLabel("Continue with Google")

                // Continue with email (native sign-in form)
                Button {
                    onEmailSignIn()
                } label: {
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "envelope.fill")
                            .font(.title3)
                        Text("Continue with Email")
                            .font(.body.weight(.semibold))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Continue with email")

                // Error display
                if let error = viewModel.error {
                    ErrorView(message: error) {
                        viewModel.clearError()
                    }
                    .transition(.opacity)
                }

                // Loading indicator
                if viewModel.isLoading {
                    ProgressView("Signing in...")
                        .padding(.top, Theme.spacingSM)
                }
            }
            .padding(.horizontal, Theme.spacingLG)
            .disabled(viewModel.isLoading)

            Spacer()

            // Terms footer
            termsFooter
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingLG)
        }
        .animation(.easeInOut, value: viewModel.error != nil)
    }

    private var termsFooter: some View {
        Text("By continuing, you agree to our [\(Text("Terms of Service").foregroundStyle(Theme.accent))](https://hearhere.app/terms) and [\(Text("Privacy Policy").foregroundStyle(Theme.accent))](https://hearhere.app/privacy)")
            .font(.caption)
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .tint(Theme.accent)
    }
}

// MARK: - Google Brand Components

/// Official Google multicolor "G" logo rendered from brand SVG paths.
/// Source: Google Brand Guidelines (https://developers.google.com/identity/branding-guidelines)
private struct GoogleLogo: View {
    // Google brand colors
    private static let yellow = Color(red: 0.984, green: 0.737, blue: 0.020) // #FBBC05
    private static let red    = Color(red: 0.918, green: 0.263, blue: 0.208) // #EA4335
    private static let green  = Color(red: 0.204, green: 0.659, blue: 0.325) // #34A853
    private static let blue   = Color(red: 0.259, green: 0.522, blue: 0.957) // #4285F4

    // SVG paths from the official Google "G" logo (viewBox 0 0 48 48)
    private static let clipPath = "M44.5 20H24v8.5h11.8C34.7 33.9 30.1 37 24 37c-7.2 0-13-5.8-13-13s5.8-13 13-13c3.1 0 5.9 1.1 8.1 2.9l6.4-6.4C34.6 4.1 29.6 2 24 2 11.8 2 2 11.8 2 24s9.8 22 22 22c11 0 21-8 21-22 0-1.3-.2-2.7-.5-4z"
    private static let yellowPath = "M0 37V11l17 13z"
    private static let redPath    = "M0 11l17 13 7-6.1L48 14V0H0z"
    private static let greenPath  = "M0 37l30-23 7.9 1L48 0v48H0z"
    private static let bluePath   = "M48 48L17 24l-4-3 35-10z"

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 48

            // Draw clipped colored segments
            let clipShape = Path(svgPath: Self.clipPath, scale: scale)

            context.clip(to: clipShape)
            context.fill(Path(svgPath: Self.yellowPath, scale: scale), with: .color(Self.yellow))
            context.fill(Path(svgPath: Self.redPath, scale: scale), with: .color(Self.red))
            context.fill(Path(svgPath: Self.greenPath, scale: scale), with: .color(Self.green))
            context.fill(Path(svgPath: Self.bluePath, scale: scale), with: .color(Self.blue))
        }
    }
}

/// Minimal SVG path parser for the subset of commands used by the Google G logo.
private extension Path {
    init(svgPath: String, scale: CGFloat) {
        self.init()
        var current = CGPoint.zero
        var i = svgPath.startIndex

        func skipWhitespaceAndCommas() {
            while i < svgPath.endIndex && (svgPath[i] == " " || svgPath[i] == ",") {
                i = svgPath.index(after: i)
            }
        }

        func parseNumber() -> CGFloat {
            skipWhitespaceAndCommas()
            let start = i
            if i < svgPath.endIndex && (svgPath[i] == "-" || svgPath[i] == "+") {
                i = svgPath.index(after: i)
            }
            var hasDot = false
            while i < svgPath.endIndex {
                if svgPath[i].isNumber {
                    i = svgPath.index(after: i)
                } else if svgPath[i] == "." && !hasDot {
                    hasDot = true
                    i = svgPath.index(after: i)
                } else {
                    break
                }
            }
            return CGFloat(Double(svgPath[start..<i]) ?? 0) * scale
        }

        func parsePoint() -> CGPoint {
            CGPoint(x: parseNumber(), y: parseNumber())
        }

        while i < svgPath.endIndex {
            skipWhitespaceAndCommas()
            guard i < svgPath.endIndex else { break }
            let cmd = svgPath[i]
            if cmd.isLetter {
                i = svgPath.index(after: i)
            }

            switch cmd {
            case "M":
                let p = parsePoint()
                move(to: p)
                current = p
                // Implicit lineTo after M
                while i < svgPath.endIndex && !svgPath[i].isLetter {
                    skipWhitespaceAndCommas()
                    if i < svgPath.endIndex && !svgPath[i].isLetter {
                        let p = parsePoint()
                        addLine(to: p)
                        current = p
                    }
                }
            case "L":
                while i < svgPath.endIndex && !svgPath[i].isLetter {
                    skipWhitespaceAndCommas()
                    if i < svgPath.endIndex && !svgPath[i].isLetter {
                        let p = parsePoint()
                        addLine(to: p)
                        current = p
                    }
                }
            case "l":
                while i < svgPath.endIndex && !svgPath[i].isLetter {
                    skipWhitespaceAndCommas()
                    if i < svgPath.endIndex && !svgPath[i].isLetter {
                        let delta = parsePoint()
                        let p = CGPoint(x: current.x + delta.x, y: current.y + delta.y)
                        addLine(to: p)
                        current = p
                    }
                }
            case "H":
                let x = parseNumber()
                let p = CGPoint(x: x, y: current.y)
                addLine(to: p)
                current = p
            case "h":
                let dx = parseNumber()
                let p = CGPoint(x: current.x + dx, y: current.y)
                addLine(to: p)
                current = p
            case "V":
                let y = parseNumber()
                let p = CGPoint(x: current.x, y: y)
                addLine(to: p)
                current = p
            case "v":
                let dy = parseNumber()
                let p = CGPoint(x: current.x, y: current.y + dy)
                addLine(to: p)
                current = p
            case "C":
                while i < svgPath.endIndex && !svgPath[i].isLetter {
                    let c1 = parsePoint()
                    let c2 = parsePoint()
                    let p = parsePoint()
                    addCurve(to: p, control1: c1, control2: c2)
                    current = p
                }
            case "c":
                while i < svgPath.endIndex && !svgPath[i].isLetter {
                    skipWhitespaceAndCommas()
                    if i < svgPath.endIndex && !svgPath[i].isLetter {
                        let dc1 = parsePoint()
                        let dc2 = parsePoint()
                        let dp = parsePoint()
                        let c1 = CGPoint(x: current.x + dc1.x, y: current.y + dc1.y)
                        let c2 = CGPoint(x: current.x + dc2.x, y: current.y + dc2.y)
                        let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                        addCurve(to: p, control1: c1, control2: c2)
                        current = p
                    }
                }
            case "s":
                while i < svgPath.endIndex && !svgPath[i].isLetter {
                    skipWhitespaceAndCommas()
                    if i < svgPath.endIndex && !svgPath[i].isLetter {
                        let dc2 = parsePoint()
                        let dp = parsePoint()
                        let c2 = CGPoint(x: current.x + dc2.x, y: current.y + dc2.y)
                        let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                        addCurve(to: p, control1: c2, control2: c2)
                        current = p
                    }
                }
            case "z", "Z":
                closeSubpath()
            default:
                break
            }
        }
    }
}

/// Button style matching Google's branding guidelines: white background with subtle border.
private struct GoogleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? .white : Color(white: 0.2))
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .padding(.horizontal, Theme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMD)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMD)
                    .stroke(colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.8), lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Sign In") {
    let viewModel = AuthViewModel(
        authService: PreviewAuthService(),
        apiClient: APIClientKey.defaultValue,
        appCoordinator: AppCoordinator(authService: PreviewAuthService())
    )
    SignInView(viewModel: viewModel)
}

#Preview("Loading") {
    let viewModel = AuthViewModel(
        authService: PreviewAuthService(),
        apiClient: APIClientKey.defaultValue,
        appCoordinator: AppCoordinator(authService: PreviewAuthService())
    )
    SignInView(viewModel: viewModel)
        .onAppear { viewModel.isLoading = true }
}

#Preview("Error") {
    let viewModel = AuthViewModel(
        authService: PreviewAuthService(),
        apiClient: APIClientKey.defaultValue,
        appCoordinator: AppCoordinator(authService: PreviewAuthService())
    )
    SignInView(viewModel: viewModel)
        .onAppear { viewModel.error = "Authentication failed. Please try again." }
}
