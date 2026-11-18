import SwiftUI

struct AccountLoginView: View {
    @ObservedObject var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var isSigningIn = false
    @State private var showsPassword = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password, revealedPassword }

    private var submittedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isSigningIn && !submittedEmail.isEmpty && !password.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let isSplit = geometry.size.width >= 880

            HStack(spacing: 0) {
                if isSplit {
                    welcomePanel(height: geometry.size.height)
                        .frame(width: min(geometry.size.width * 0.43, 550))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !isSplit {
                            brandLockup(color: AdaColors.navy)
                                .padding(.bottom, 4)
                        }

                        signInCard
                        demoCard

                        #if DEBUG
                        Button {
                            store.isAuthSheetPresented = true
                        } label: {
                            Label("API settings", systemImage: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AdaColors.secondaryInk)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSigningIn)
                        .frame(maxWidth: .infinity)
                        #endif
                    }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 28)
                    .padding(.vertical, isSplit ? 34 : 20)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .background(AdaColors.canvas)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: isSplit ? AdaLayout.containerRadius : 0,
                    bottomLeadingRadius: isSplit ? AdaLayout.containerRadius : 0
                ))
            }
            .background(isSplit ? AdaColors.navy : AdaColors.canvas)
        }
        .onAppear { focusedField = .email }
        .onChange(of: store.apiBaseURLString) { _, _ in
            errorMessage = nil
            password = ""
            showsPassword = false
            focusedField = .email
        }
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Sign in")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.5)
                    .accessibilityAddTraits(.isHeader)
                Text("Open your organization’s workspace.")
                    .font(.system(size: 14))
                    .foregroundStyle(AdaColors.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email address")
                        .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 10) {
                        fieldIcon("envelope", active: focusedField == .email)
                        TextField(
                            "Email address", text: $email,
                            prompt: Text(verbatim: "you@organization.org").foregroundColor(AdaColors.secondaryInk)
                        )
                        .labelsHidden()
                        .textContentType(.username)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = showsPassword ? .revealedPassword : .password }
                    }
                    .modifier(LoginInputStyle(isFocused: focusedField == .email))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 10) {
                        let isPasswordFocused = focusedField == .password || focusedField == .revealedPassword
                        fieldIcon("lock", active: isPasswordFocused)

                        Group {
                            if showsPassword {
                                TextField("Password", text: $password, prompt: passwordPrompt)
                                    .focused($focusedField, equals: .revealedPassword)
                            } else {
                                SecureField("Password", text: $password, prompt: passwordPrompt)
                                    .focused($focusedField, equals: .password)
                            }
                        }
                        .labelsHidden()
                        .textContentType(.password)
                        .textFieldStyle(.plain)
                        .onSubmit(signIn)

                        Button {
                            showsPassword.toggle()
                            focusedField = showsPassword ? .revealedPassword : .password
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash" : "eye")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AdaColors.secondaryInk)
                                .frame(width: 36, height: 42)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(showsPassword ? "Hide password" : "Show password")
                        .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                    }
                    .modifier(LoginInputStyle(isFocused: focusedField == .password || focusedField == .revealedPassword))
                }
                Toggle("Keep me signed in on this Mac", isOn: $rememberMe)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
            .disabled(isSigningIn)

            if let message = errorMessage ?? store.lastError, !isSigningIn {
                Label {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .accessibilityHidden(true)
                }
                .font(.system(size: 13))
                .foregroundStyle(AdaColors.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AdaColors.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sign in error. \(message)")
            }

            Button(action: signIn) {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityHidden(true)
                    }
                    Text(isSigningIn ? "Signing in…" : "Sign in")
                        .font(.system(size: 14, weight: .semibold))
                    if !isSigningIn {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(canSubmit || isSigningIn ? .white : AdaColors.secondaryInk)
                .background(canSubmit || isSigningIn ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(LoginSubmitStyle())
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .foregroundStyle(AdaColors.ink)
        .adaCard(padding: AdaLayout.pagePadding)
    }

    private var demoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore a demo")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Browse sample sightings and try photo review.")
                    .font(.system(size: 13))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            HStack(spacing: 8) {
                Button {
                    openDemo(.superAsiaNetwork)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe.asia.australia")
                            .accessibilityHidden(true)
                        Text("Asia Super Demo")
                        Spacer(minLength: 6)
                        Text("⌘D")
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 42)
                    .background(AdaColors.canvas, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("d", modifiers: .command)
                .accessibilityHint("Opens a workspace with sample records")

                ActionDropdown(items: DemoDashboardPersona.allCases.map { persona in
                    DropdownAction(title: persona.displayName, selected: false, action: { openDemo(persona) })
                }) {
                    HStack(spacing: 6) {
                        Text("Demo roles")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(AdaColors.canvas, in: Capsule())
                }
                .accessibilityLabel("Choose a demo role")
            }
        }
        .disabled(isSigningIn)
        .foregroundStyle(AdaColors.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaCard(padding: 24)
    }

    private func welcomePanel(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            brandLockup(color: .white)

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 16) {
                GeometryReader { bounds in
                    Image("TurtleSamples/Chewie_2019_r")
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                }
                .frame(height: min(max(height * 0.32, 160), 300))
                .clipShape(RoundedRectangle(cornerRadius: AdaLayout.cardRadius))
                .accessibilityHidden(true)

                Text("Sea turtle photo ID")
                    .font(.system(size: 37, weight: .semibold))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Compare head patterns, review sightings, and follow individual turtles over time.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 40)
        .padding(.top, 52)
        .padding(.bottom, 40)
        .frame(maxHeight: .infinity)
        .background {
            GeometryReader { bounds in
                Image("bg_satu")
                    .resizable()
                    .scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
                    .opacity(0.28)
            }
            .accessibilityHidden(true)
        }
        .clipped()
    }

    private func brandLockup(color: Color) -> some View {
        HStack(spacing: 12) {
            Image("AdaPenyuMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 38, height: 38)

            Image("AdaPenyuWordmark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 132, height: 24)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AdaPenyu")
    }

    private func fieldIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(active ? AdaColors.ink : AdaColors.secondaryInk)
            .frame(width: 17)
            .accessibilityHidden(true)
    }

    private var passwordPrompt: Text {
        Text("Enter your password").foregroundColor(AdaColors.secondaryInk)
    }

    private func openDemo(_ persona: DemoDashboardPersona) {
        guard !isSigningIn else { return }
        password = ""
        showsPassword = false
        store.enterDemoWorkspace(persona: persona)
    }

    private func signIn() {
        guard canSubmit else { return }
        let email = submittedEmail
        let password = self.password
        let rememberMe = self.rememberMe
        isSigningIn = true
        showsPassword = false
        errorMessage = nil

        Task {
            defer { isSigningIn = false }
            do {
                try await store.signIn(email: email, password: password, rememberMe: rememberMe)
                self.password = ""
            } catch is CancellationError {
                self.password = ""
            } catch {
                self.password = ""
                errorMessage = error.localizedDescription
                focusedField = (error as? APIError)?.fieldErrors["email"] == nil ? .password : .email
            }
        }
    }
}

private struct LoginSubmitStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.84 : 1)
    }
}

private struct LoginInputStyle: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return content
            .font(.system(size: 14))
            .padding(.leading, 13)
            .padding(.trailing, 8)
            .frame(minHeight: 46)
            .background(isFocused ? Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255) : AdaColors.canvas, in: shape)
            .overlay {
                shape.strokeBorder(isFocused ? AdaColors.navy : AdaColors.line, lineWidth: isFocused ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
    }
}

#if DEBUG
struct BackendSettingsSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var feedback: String?
    @State private var isChecking = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Developer API Settings").font(.title2.bold())
            Text("Active backend").font(.caption).foregroundStyle(.secondary)
            Text(store.apiBaseURLString).textSelection(.enabled)
            TextField("Backend URL", text: $urlText).textFieldStyle(.roundedBorder)
                .onChange(of: urlText) { _, _ in checkTask?.cancel(); isChecking = false; feedback = nil }
            Text("Changing the backend signs you out and clears private records and photos.")
                .font(.caption).foregroundStyle(.secondary)
            if let feedback { Text(feedback).font(.callout).textSelection(.enabled) }
            HStack {
                Button(isChecking ? "Testing…" : "Test connection", action: testConnection).disabled(isChecking)
                Button("Save backend") {
                    do { try store.changeBackend(urlText); dismiss() }
                    catch { feedback = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Reset to default") {
                do { try store.changeBackend(nil); dismiss() }
                catch { feedback = error.localizedDescription }
            }
            HStack { Spacer(); Button("Done") { dismiss() } }
        }
        .padding(24)
        .frame(width: 510)
        .onAppear { urlText = store.apiBaseURLString }
        .onDisappear { checkTask?.cancel() }
    }

    private func testConnection() {
        do {
            let url = try APIConfig.validatedURL(urlText)
            isChecking = true
            feedback = nil
            checkTask = Task {
                do {
                    try await APIClient.publicClient(baseURL: url).testConnection()
                    try Task.checkCancellation()
                    feedback = "Connection successful."
                } catch is CancellationError { return }
                catch { if !Task.isCancelled { feedback = error.localizedDescription } }
                if !Task.isCancelled { isChecking = false }
            }
        } catch { feedback = error.localizedDescription }
    }
}

#Preview("Account Login") {
    AccountLoginPreviewWrapper()
}

#Preview("Backend Settings") {
    BackendSettingsSheet(store: AppStore())
}

private struct AccountLoginPreviewWrapper: View {
    @StateObject private var store = AppStore()

    var body: some View {
        AccountLoginView(store: store)
            .frame(width: 640, height: 520)
            .sheet(isPresented: $store.isAuthSheetPresented) {
                BackendSettingsSheet(store: store)
            }
    }
}

#endif
