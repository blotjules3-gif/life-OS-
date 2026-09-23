import SwiftUI
import AuthenticationServices

/// Écran d'Authentification initial : Inscription & Connexion.
///
/// Propose l'authentification avec Apple, Google, Facebook ou Email/Mot de passe.
/// Une fois l'utilisateur authentifié (`isAuthenticated = true`), l'application
/// enchaîne directement avec l'accueil d'onboarding (`OnboardingWelcome`).
struct AuthView: View {
    var isModal: Bool = false
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKeys.isAuthenticated) private var isAuthenticated = false
    @AppStorage(AppStorageKeys.userEmail) private var userEmail = ""
    @AppStorage(AppStorageKeys.authProvider) private var authProvider = ""
    @AppStorage(AppStorageKeys.userId) private var userId = ""
    @AppStorage(AppStorageKeys.userName) private var userName = ""
    @AppStorage(AppStorageKeys.userDisplayName) private var userDisplayName = ""

    enum AuthMode: String, CaseIterable {
        case login = "Connexion"
        case signup = "Inscription"
    }

    @State private var mode: AuthMode = .signup
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var nameInput = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, email, password, confirmPassword
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    if isModal {
                        HStack {
                            Spacer()
                            Button {
                                Haptics.tap()
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 12)
                    } else {
                        Spacer(minLength: 20)
                    }

                    headerSection

                    modePicker

                    socialButtonsSection

                    dividerSection

                    emailFormSection

                    actionButton

                    footerTerms

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440)
            }
        }
    }

    // MARK: - Header avec Logo Infini

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 96, height: 96)

                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 96, height: 96)

                Image(systemName: "infinity")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 10)

            VStack(spacing: 8) {
                Text("LifeOS")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                Text(mode == .signup
                     ? "Crée ton compte pour synchroniser tes données sur tous tes appareils."
                     : "Bon retour ! Connecte-toi pour retrouver ta progression.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Sélecteur Mode (Connexion / Inscription)

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(AuthMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        mode = m
                        errorMessage = nil
                    }
                    Haptics.tap()
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 15, weight: mode == m ? .bold : .medium))
                        .foregroundStyle(mode == m ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if mode == m {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.cardFill)
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Boutons Réseaux Sociaux (Apple, Google, Facebook)

    private var socialButtonsSection: some View {
        VStack(spacing: 12) {
            // Bouton Apple
            Button {
                signInWithApple()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 19, weight: .semibold))
                    Text("Continuer avec Apple")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            // Bouton Google
            Button {
                signInWithGoogle()
            } label: {
                HStack(spacing: 12) {
                    Image("google_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("Continuer avec Google")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            // Bouton Facebook
            Button {
                signInWithFacebook()
            } label: {
                HStack(spacing: 12) {
                    Image("facebook_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("Continuer avec Facebook")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Séparateur

    private var dividerSection: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)
            Text("ou par email")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Formulaire Email / Mot de Passe

    private var emailFormSection: some View {
        VStack(spacing: 14) {
            if mode == .signup {
                inputField(
                    icon: "person.fill",
                    placeholder: "Ton prénom ou pseudo",
                    text: $nameInput,
                    field: .name
                )
            }

            inputField(
                icon: "envelope.fill",
                placeholder: "Adresse email",
                text: $email,
                field: .email,
                keyboardType: .emailAddress,
                autoCapitalization: .never
            )

            // Champ mot de passe
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                if showPassword {
                    TextField("Mot de passe (6 car. min)", text: $password)
                        .focused($focusedField, equals: .password)
                        .font(.body)
                } else {
                    SecureField("Mot de passe (6 car. min)", text: $password)
                        .focused($focusedField, equals: .password)
                        .font(.body)
                }

                Button {
                    showPassword.toggle()
                    Haptics.tap()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focusedField == .password ? Color.accentColor : Theme.stroke, lineWidth: focusedField == .password ? 1.5 : 1)
            )

            if mode == .signup {
                // Confirmation mot de passe
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)

                    SecureField("Confirmer le mot de passe", text: $confirmPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .font(.body)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focusedField == .confirmPassword ? Color.accentColor : Theme.stroke, lineWidth: focusedField == .confirmPassword ? 1.5 : 1)
                )
            }

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        keyboardType: UIKeyboardType = .default,
        autoCapitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .font(.body)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autoCapitalization)
                .autocorrectionDisabled(field == .email)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focusedField == field ? Color.accentColor : Theme.stroke, lineWidth: focusedField == field ? 1.5 : 1)
        )
    }

    // MARK: - Bouton Principal

    private var actionButton: some View {
        Button {
            submitForm()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(mode == .signup ? "Créer mon compte" : "Se connecter")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Footer

    private var footerTerms: some View {
        VStack(spacing: 10) {
            Button {
                bypassForGuestDemo()
            } label: {
                Text("Explorer sans compte (Mode Découverte)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            Text("En continuant, tu acceptes les conditions d'utilisation et la politique de confidentialité de LifeOS.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions d'Authentification

    private func submitForm() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Veuillez entrer une adresse email valide."
            return
        }

        guard password.count >= 6 else {
            errorMessage = "Le mot de passe doit contenir au moins 6 caractères."
            return
        }

        if mode == .signup && password != confirmPassword {
            errorMessage = "Les mots de passe ne correspondent pas."
            return
        }

        errorMessage = nil
        isLoading = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isLoading = false
            finalizeAuth(
                email: trimmedEmail,
                provider: "email",
                name: mode == .signup ? nameInput.trimmingCharacters(in: .whitespaces) : nil
            )
        }
    }

    private func signInWithApple() {
        Haptics.tap()
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isLoading = false
            finalizeAuth(
                email: "apple.id@icloud.com",
                provider: "apple",
                name: "Compte Apple"
            )
        }
    }

    private func signInWithGoogle() {
        Haptics.tap()
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isLoading = false
            finalizeAuth(
                email: "utilisateur.google@gmail.com",
                provider: "google",
                name: "Compte Google"
            )
        }
    }

    private func signInWithFacebook() {
        Haptics.tap()
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isLoading = false
            finalizeAuth(
                email: "utilisateur.fb@facebook.com",
                provider: "facebook",
                name: "Compte Facebook"
            )
        }
    }

    private func bypassForGuestDemo() {
        Haptics.tap()
        finalizeAuth(
            email: "invite@lifeos.local",
            provider: "guest",
            name: "Invité"
        )
    }

    private func finalizeAuth(email: String, provider: String, name: String?) {
        userEmail = email
        authProvider = provider
        if userId.isEmpty {
            userId = UUID().uuidString
        }
        if let name, !name.isEmpty {
            userDisplayName = name
            if userName.isEmpty {
                userName = name
            }
        }

        Haptics.success()
        withAnimation(.easeInOut(duration: 0.4)) {
            isAuthenticated = true
        }
        dismiss()
    }
}
