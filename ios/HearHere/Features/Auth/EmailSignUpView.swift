import SwiftUI

/// Native email sign-up form with display name, email, and password fields.
struct EmailSignUpView: View {
    @Bindable var viewModel: EmailAuthViewModel

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case displayName, email, password
    }

    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            Spacer()

            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("Create Account")
                    .font(.title.weight(.bold))

                Text("Sign up with your email address")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            VStack(spacing: Theme.spacingMD) {
                TextField("Display Name", text: $viewModel.displayName)
                    .textContentType(.name)
                    .focused($focusedField, equals: .displayName)
                    .padding(Theme.spacingMD)
                    .background(Theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }

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
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
                    .padding(Theme.spacingMD)
                    .background(Theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.signUp() } }

                Text("Password must be at least 8 characters")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await viewModel.signUp() }
                } label: {
                    Text("Create Account")
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
                    ProgressView("Creating account...")
                        .padding(.top, Theme.spacingSM)
                }
            }
            .padding(.horizontal, Theme.spacingLG)

            Spacer()
        }
        .animation(.easeInOut, value: viewModel.error != nil)
    }
}

// MARK: - Previews

#Preview("Email Sign Up") {
    EmailSignUpView(
        viewModel: EmailAuthViewModel(
            authService: PreviewAuthService(),
            apiClient: APIClientKey.defaultValue,
            appCoordinator: AppCoordinator(authService: PreviewAuthService())
        )
    )
}
