import SwiftUI

/// Native email and password sign-in form.
struct EmailSignInView: View {
    @Bindable var viewModel: EmailAuthViewModel
    var onCreateAccount: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, password
    }

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("Sign In with Email")
                    .font(.title.weight(.bold))
            }

            Spacer()

            VStack(spacing: Theme.spacingMD) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .padding(Theme.spacingMD)
                    .background(Theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .padding(Theme.spacingMD)
                    .background(Theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.signIn() } }

                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    Text("Sign In")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isLoading)

                if let error = viewModel.error {
                    ErrorView(message: error) {
                        viewModel.clearError()
                    }
                    .transition(.opacity)
                }

                if viewModel.isLoading {
                    ProgressView("Signing in...")
                        .padding(.top, Theme.spacingSM)
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            Spacer()

            Button {
                onCreateAccount()
            } label: {
                Text("Don't have an account? ") +
                Text("Create one").foregroundColor(Theme.accent).bold()
            }
            .font(.callout)
            .foregroundStyle(Theme.secondary)
            .padding(.bottom, Theme.spacingLG)
        }
        .animation(.easeInOut, value: viewModel.error != nil)
    }
}

// MARK: - Previews

#Preview("Email Sign In") {
    EmailSignInView(
        viewModel: EmailAuthViewModel(
            authService: PreviewAuthService(),
            apiClient: APIClientKey.defaultValue,
            appCoordinator: AppCoordinator(authService: PreviewAuthService())
        ),
        onCreateAccount: {}
    )
}
