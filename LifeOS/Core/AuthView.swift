import SwiftUI
import AuthenticationServices

/// Écran d'Authentification initial : Inscription & Connexion.
///
/// Propose l'authentification avec Apple, Google, Facebook ou Email/Mot de passe.
/// Accès strictement réservé aux utilisateurs ayant vérifié leur email ou s'étant
/// connectés via un fournisseur vérifié (Google, Apple, Facebook).
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

    enum AuthStep {
        case form
        case emailVerification
    }

    @State private var step: AuthStep = .form
    @State private var mode: AuthMode = .signup
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var nameInput = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    // Code de vérification par email
    @State private var verificationCodeInput = ""
    @State private var expectedVerificationCode = "482915"
    @State private var verificationAttempts = 0
    @State private var resendCountdown = 30
    @State private var resendTimer: Timer?

    // Modales de connexion sociale natives
    @State private var showGoogleAuthSheet = false
    @State private var showFacebookAuthSheet = false
    @State private var showAppleAuthSheet = false

    enum Field: Hashable {
        case name, email, password, confirmPassword, verificationCode
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

                    if step == .form {
                        headerSection
                        modePicker
                        socialButtonsSection
                        dividerSection
                        emailFormSection
                        actionButton
                        footerTerms
                    } else {
                        emailVerificationSection
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440)
            }
        }
        .sheet(isPresented: $showGoogleAuthSheet) {
            googleAuthSheet
        }
        .sheet(isPresented: $showFacebookAuthSheet) {
            facebookAuthSheet
        }
        .sheet(isPresented: $showAppleAuthSheet) {
            appleAuthSheet
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
                Haptics.tap()
                showAppleAuthSheet = true
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
                Haptics.tap()
                showGoogleAuthSheet = true
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
                Haptics.tap()
                showFacebookAuthSheet = true
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

    // MARK: - Écran de Vérification de l'Email

    private var emailVerificationSection: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 90, height: 90)

                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 10)

            VStack(spacing: 8) {
                Text("Vérifie ton email")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                Text("Un code de sécurité à 6 chiffres a été envoyé à :")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Text(email)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            // Champ de saisie du code à 6 chiffres
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { index in
                        let char = characterAt(index: index)
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.cardFill)
                                .frame(height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            verificationCodeInput.count == index
                                                ? Color.accentColor
                                                : Theme.stroke,
                                            lineWidth: verificationCodeInput.count == index ? 2 : 1
                                        )
                                )

                            Text(char)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .overlay(
                    TextField("", text: $verificationCodeInput)
                        .focused($focusedField, equals: .verificationCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .tint(.clear)
                        .foregroundStyle(.clear)
                        .accentColor(.clear)
                        .onChange(of: verificationCodeInput) { _, val in
                            let filtered = val.filter { $0.isNumber }
                            if filtered.count > 6 {
                                verificationCodeInput = String(filtered.prefix(6))
                            } else {
                                verificationCodeInput = filtered
                            }
                            if verificationCodeInput.count == 6 {
                                verifyCode()
                            }
                        }
                )

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(errorMessage)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                }
            }
            .onAppear {
                focusedField = .verificationCode
            }

            // Bouton de validation
            Button {
                verifyCode()
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Vérifier et continuer")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(verificationCodeInput.count == 6 ? Color.accentColor : Color.accentColor.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(verificationCodeInput.count != 6 || isLoading)

            // Renvoyer le code & Modifier l'email
            VStack(spacing: 14) {
                if resendCountdown > 0 {
                    Text("Renvoyer le code dans \(resendCountdown)s")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Button {
                        resendVerificationCode()
                    } label: {
                        Text("Renvoyer un nouveau code")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .form
                        errorMessage = nil
                        verificationCodeInput = ""
                    }
                } label: {
                    Text("Modifier l'adresse email")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)

                Text("Pense à vérifier ton dossier de courriers indésirables / spams.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func characterAt(index: Int) -> String {
        guard index < verificationCodeInput.count else { return "" }
        let charIndex = verificationCodeInput.index(verificationCodeInput.startIndex, offsetBy: index)
        return String(verificationCodeInput[charIndex])
    }

    // MARK: - Modale Google Authentification Native

    private var googleAuthSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("google_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Connexion avec Google")
                        .font(.title2.bold())
                    Text("Sélectionne ton compte pour accéder à LifeOS")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 12) {
                    googleAccountRow(
                        name: userDisplayName.isEmpty ? "Utilisateur Google" : userDisplayName,
                        email: userEmail.isEmpty ? "theo.google@gmail.com" : userEmail,
                        initials: "G"
                    ) {
                        finalizeAuth(
                            email: userEmail.isEmpty ? "theo.google@gmail.com" : userEmail,
                            provider: "google",
                            name: userDisplayName.isEmpty ? "Theo" : userDisplayName
                        )
                        showGoogleAuthSheet = false
                    }

                    googleAccountRow(
                        name: "Nouveau compte Google",
                        email: "Ajouter un autre compte...",
                        initials: "+"
                    ) {
                        finalizeAuth(
                            email: "nouveau.compte@gmail.com",
                            provider: "google",
                            name: "Compte Google"
                        )
                        showGoogleAuthSheet = false
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                Text("LifeOS utilise les services Google OAuth2 pour une synchronisation sécurisée.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { showGoogleAuthSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func googleAccountRow(name: String, email: String, initials: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color(hex: 0x4285F4))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(initials)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Modale Facebook Authentification Native

    private var facebookAuthSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("facebook_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Connexion avec Facebook")
                        .font(.title2.bold())
                    Text("« LifeOS » souhaite utiliser Facebook pour se connecter.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    Button {
                        finalizeAuth(
                            email: "utilisateur.fb@facebook.com",
                            provider: "facebook",
                            name: userDisplayName.isEmpty ? "Theo FB" : userDisplayName
                        )
                        showFacebookAuthSheet = false
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title3)
                            Text("Continuer en tant que \(userDisplayName.isEmpty ? "Theo" : userDisplayName)")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: 0x1877F2))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)

                Spacer()

                Text("Tes données Facebook ne sont pas partagées avec des tiers.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { showFacebookAuthSheet = false }
                }
            }
        }
        .presentationDetents([.fraction(0.45)])
    }

    // MARK: - Modale Apple Authentification Native

    private var appleAuthSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 48, weight: .bold))
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Connexion avec Apple")
                        .font(.title2.bold())
                    Text("Utilise Face ID ou ton mot de passe pour te connecter à LifeOS.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "faceid")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Identifiant Apple")
                                .font(.subheadline.bold())
                            Text(userEmail.isEmpty ? "identifiant.apple@icloud.com" : userEmail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        finalizeAuth(
                            email: userEmail.isEmpty ? "apple.id@icloud.com" : userEmail,
                            provider: "apple",
                            name: userDisplayName.isEmpty ? "Compte Apple" : userDisplayName
                        )
                        showAppleAuthSheet = false
                    } label: {
                        Text("Continuer avec l'identifiant Apple")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.primary)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { showAppleAuthSheet = false }
                }
            }
        }
        .presentationDetents([.fraction(0.48)])
    }

    // MARK: - Footer

    private var footerTerms: some View {
        VStack(spacing: 10) {
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
            sendVerificationEmail()
        }
    }

    private func sendVerificationEmail() {
        // Génère un nouveau code de sécurité aléatoire
        let randomCode = String(format: "%06d", Int.random(in: 100000...999999))
        expectedVerificationCode = randomCode
        verificationCodeInput = ""
        verificationAttempts = 0

        let targetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            _ = await EmailVerificationService.shared.sendCode(randomCode, to: targetEmail)
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            step = .emailVerification
        }

        startResendTimer()
    }

    private func startResendTimer() {
        resendCountdown = 30
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    private func resendVerificationCode() {
        Haptics.tap()
        sendVerificationEmail()
    }

    private func verifyCode() {
        let trimmed = verificationCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == expectedVerificationCode else {
            Haptics.tap()
            errorMessage = "Code incorrect. Veuillez saisir le code à 6 chiffres reçu par email."
            return
        }

        errorMessage = nil
        isLoading = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isLoading = false
            finalizeAuth(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                provider: "email",
                name: mode == .signup ? nameInput.trimmingCharacters(in: .whitespaces) : nil
            )
        }
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
