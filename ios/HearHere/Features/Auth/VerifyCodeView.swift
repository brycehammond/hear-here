import SwiftUI

/// OTP verification code input screen shown during sign-up.
struct VerifyCodeView: View {
    @Bindable var viewModel: EmailAuthViewModel

    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("Verify Your Email")
                    .font(.title.weight(.bold))

                if let info = viewModel.codeInfo {
                    Text("We sent a \(info.codeLength)-digit code to **\(info.sentTo)**")
                        .font(.body)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: Theme.spacingMD) {
                TextField("Verification Code", text: $viewModel.verificationCode)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospaced())
                    .focused($codeFocused)
                    .padding(Theme.spacingMD)
                    .background(Theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))

                Button {
                    Task { await viewModel.submitCode() }
                } label: {
                    Text("Verify")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isLoading)

                Button {
                    Task { await viewModel.resendCode() }
                } label: {
                    Text("Resend Code")
                        .font(.callout)
                }
                .foregroundStyle(Theme.accent)
                .disabled(viewModel.isLoading)

                if let error = viewModel.error {
                    ErrorView(message: error) {
                        viewModel.clearError()
                    }
                    .transition(.opacity)
                }

                if viewModel.isLoading {
                    ProgressView("Verifying...")
                        .padding(.top, Theme.spacingSM)
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            Spacer()
        }
        .animation(.easeInOut, value: viewModel.error != nil)
        .onAppear { codeFocused = true }
    }
}

// MARK: - Previews

#Preview("Verify Code") {
    let vm = EmailAuthViewModel(
        authService: PreviewAuthService(),
        apiClient: APIClientKey.defaultValue,
        appCoordinator: AppCoordinator(authService: PreviewAuthService())
    )
    VerifyCodeView(viewModel: vm)
        .onAppear {
            vm.codeInfo = SignUpCodeInfo(sentTo: "j***@example.com", codeLength: 6)
        }
}
