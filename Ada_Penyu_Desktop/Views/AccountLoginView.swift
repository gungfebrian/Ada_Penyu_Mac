import SwiftUI

// Tokens aligned with FigCraft MCP "AdaPenyu Design System" (Frame 64) & "Overview" (Frame 2):
// - Background: #F5F6F7 | Surface: #FFFFFF | Primary: #0B253A
// - Secondary (border/divider): #D9D9D9 | Tertiary: #626F76 | Supporting: #71818B
// - Input Focused: #E8E8E8
// - 32 px gutters · 24 px card radius · 40 px main panel radius · pill buttons
private enum FigCraftLoginTokens {
    static let background = Color(red: 245 / 255, green: 246 / 255, blue: 247 / 255) // #F5F6F7
    static let surface = Color.white // #FFFFFF
    static let primary = Color(red: 11 / 255, green: 37 / 255, blue: 58 / 255) // #0B253A
    static let elevatedNavy = Color(red: 25 / 255, green: 52 / 255, blue: 74 / 255) // #19344A
    static let secondaryBorder = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255) // #D9D9D9
    static let tertiaryInk = Color(red: 98 / 255, green: 111 / 255, blue: 118 / 255) // #626F76
    static let supportingInk = Color(red: 113 / 255, green: 129 / 255, blue: 139 / 255) // #71818B
    static let inputUnfocused = Color(red: 245 / 255, green: 246 / 255, blue: 247 / 255) // #F5F6F7
    static let inputFocused = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255) // #E8E8E8
    static let cardRadius: CGFloat = 24
    static let mainPanelRadius: CGFloat = 40
    static let inputRadius: CGFloat = 14
    static let gutter: CGFloat = 32
}

struct AccountLoginView: View {
    /// Set this to `false` later to completely remove the quick demo bypass from the login screen.
    static let enableQuickDemoBypass = true

    @ObservedObject var store: AppStore
    @AppStorage("ada.quickDemoBypassHidden") private var isQuickDemoHidden = false
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    @State private var showsPassword = false
    @FocusState private var focusedField: LoginField?
    private enum LoginField { case email, password }
    private var canSubmit: Bool {
        !isSigningIn && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let isSplitLayout = geometry.size.width >= 860
            ZStack {
                FigCraftLoginTokens.primary.ignoresSafeArea()

                HStack(spacing: 0) {
                    if isSplitLayout {
                        welcomePanel
                            .frame(width: min(max(geometry.size.width * 0.42, 380), 520))
                    }

                    ScrollView {
                        VStack(spacing: 20) {
                            if !isSplitLayout {
                                compactBrandHeader
                            }

                            if Self.enableQuickDemoBypass {
                                quickDemoBypassBanner
                            }

                            loginCard

                            #if DEBUG
                            Button {
                                store.isAuthSheetPresented = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Developer API settings…")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(FigCraftLoginTokens.tertiaryInk)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(FigCraftLoginTokens.surface.opacity(0.75))
                                        .overlay(
                                            Capsule()
                                                .stroke(FigCraftLoginTokens.secondaryBorder, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isSigningIn)
                            #endif
                        }
                        .frame(maxWidth: 440)
                        .padding(.horizontal, FigCraftLoginTokens.gutter)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                    .background(FigCraftLoginTokens.background)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: isSplitLayout ? FigCraftLoginTokens.mainPanelRadius : 0,
                            bottomLeadingRadius: isSplitLayout ? FigCraftLoginTokens.mainPanelRadius : 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                }
            }
        }
        .onAppear { focusedField = .email }
    }

    private var compactBrandHeader: some View {
        HStack(spacing: 12) {
            Image("AdaPenyuMark").resizable().renderingMode(.template).scaledToFit().frame(width: 40, height: 40).foregroundStyle(FigCraftLoginTokens.primary)
            VStack(alignment: .leading, spacing: 2) {
                Image("AdaPenyuWordmark").resizable().renderingMode(.template).scaledToFit().frame(width: 130, height: 24)
                    .foregroundStyle(FigCraftLoginTokens.primary)
                Text("Sea Turtle Group")
                    .font(.system(size: 12))
                    .foregroundStyle(FigCraftLoginTokens.supportingInk)
            }
            Spacer()
        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("SEA TURTLE GROUP")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(FigCraftLoginTokens.tertiaryInk)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(AdaColors.green)
                            .frame(width: 6, height: 6)
                        Text("Conservation Workspace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FigCraftLoginTokens.tertiaryInk)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(FigCraftLoginTokens.background, in: Capsule())
                }

                Text("Welcome back.")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FigCraftLoginTokens.primary)

                Text("Sign in to inspect encounters, review scale patterns, and sync field records.")
                    .font(.system(size: 14))
                    .foregroundStyle(FigCraftLoginTokens.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email address")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FigCraftLoginTokens.primary)

                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                focusedField == .email
                                    ? FigCraftLoginTokens.primary
                                    : FigCraftLoginTokens.tertiaryInk
                            )
                            .frame(width: 18)
                            .accessibilityHidden(true)

                        TextField(
                            "",
                            text: $email,
                            prompt: Text(verbatim: "you@organisation.org")
                                .foregroundColor(FigCraftLoginTokens.supportingInk)
                        )
                            .textContentType(.username)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .accessibilityLabel("Email address")
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(FigCraftLoginTokens.primary)
                    }
                    .modifier(LoginInputStyle(isFocused: focusedField == .email))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FigCraftLoginTokens.primary)

                    HStack(spacing: 10) {
                        Image(systemName: "lock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                focusedField == .password
                                    ? FigCraftLoginTokens.primary
                                    : FigCraftLoginTokens.tertiaryInk
                            )
                            .frame(width: 18)
                            .accessibilityHidden(true)

                        Group {
                            if showsPassword {
                                TextField(
                                    "",
                                    text: $password,
                                    prompt: Text(verbatim: "Enter your password")
                                        .foregroundColor(FigCraftLoginTokens.supportingInk)
                                )
                            } else {
                                SecureField(
                                    "",
                                    text: $password,
                                    prompt: Text(verbatim: "Enter your password")
                                        .foregroundColor(FigCraftLoginTokens.supportingInk)
                                )
                            }
                        }
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .onSubmit(signIn)
                        .accessibilityLabel("Password")
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(FigCraftLoginTokens.primary)

                        Button {
                            showsPassword.toggle()
                            focusedField = .password
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(FigCraftLoginTokens.tertiaryInk)
                        .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                    }
                    .modifier(LoginInputStyle(isFocused: focusedField == .password))
                }

                HStack(spacing: 8) {
                    Toggle("Keep me signed in on this Mac", isOn: $rememberMe)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                        .foregroundStyle(FigCraftLoginTokens.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                        Text("Keychain")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(FigCraftLoginTokens.supportingInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(FigCraftLoginTokens.background, in: Capsule())
                    .help("Your remembered session is stored securely in the macOS Keychain.")
                }

                if let message = errorMessage ?? store.lastError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AdaColors.red)
                            .padding(.top, 1)

                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaColors.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: FigCraftLoginTokens.inputRadius, style: .continuous)
                            .fill(AdaColors.red.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: FigCraftLoginTokens.inputRadius, style: .continuous)
                                    .stroke(AdaColors.red.opacity(0.22), lineWidth: 1)
                            )
                    )
                }

                // FigCraft Design System Primary Action: pill button (#0B253A, height 52)
                Button(action: signIn) {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(isSigningIn ? "Signing in…" : "Sign in")
                            .font(.system(size: 15, weight: .semibold))
                        if !isSigningIn {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    Capsule()
                        .fill(FigCraftLoginTokens.primary.opacity(canSubmit || isSigningIn ? 1 : 0.42))
                )
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)

                Label("Your remembered session is stored securely on this Mac.", systemImage: "lock")
                    .font(.system(size: 12))
                    .foregroundStyle(FigCraftLoginTokens.supportingInk)
            }
            .disabled(isSigningIn)
        }
        .padding(FigCraftLoginTokens.gutter)
        .background(
            RoundedRectangle(cornerRadius: FigCraftLoginTokens.cardRadius, style: .continuous)
                .fill(FigCraftLoginTokens.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 16, y: 6)
        )
    }

    @ViewBuilder
    private var quickDemoBypassBanner: some View {
        if isQuickDemoHidden {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isQuickDemoHidden = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Show Demo Shortcut")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(FigCraftLoginTokens.tertiaryInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(FigCraftLoginTokens.surface))
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        password = ""
                        store.enterDemoWorkspace()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Quick Demo Mode (No Login)")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("⌘D")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.18), in: Capsule())
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(AdaColors.green))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("d", modifiers: [.command])
                    .accessibilityLabel("Quick Demo Mode")

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isQuickDemoHidden = true
                        }
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FigCraftLoginTokens.tertiaryInk)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(FigCraftLoginTokens.background))
                    }
                    .buttonStyle(.plain)
                    .help("Hide demo button (can be re-shown anytime)")
                    .accessibilityLabel("Hide demo button")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Jump in as:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FigCraftLoginTokens.supportingInk)

                        ForEach(DemoDashboardPersona.allCases) { persona in
                            Button {
                                password = ""
                                store.enterDemoWorkspace(persona: persona)
                            } label: {
                                Text(persona.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(FigCraftLoginTokens.primary)
                                    .padding(.horizontal, 10)
                                    .frame(height: 25)
                                    .background(
                                        Capsule()
                                            .fill(FigCraftLoginTokens.background)
                                            .overlay(
                                                Capsule().stroke(FigCraftLoginTokens.secondaryBorder, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FigCraftLoginTokens.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
            )
        }
    }

    private var welcomePanel: some View {
        ZStack(alignment: .bottomLeading) {
            FigCraftLoginTokens.primary

            GeometryReader { proxy in
                Image("bg_satu")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .opacity(0.55)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 28) {
                // Brand row matching FigCraft Overview sidebar top-left identity
                HStack(spacing: 12) {
                    Image("AdaPenyuMark").resizable().scaledToFit().frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Image("AdaPenyuWordmark").resizable().scaledToFit().frame(width: 140, height: 26)
                            .foregroundStyle(.white)
                        Text("Sea Turtle Group")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                Spacer(minLength: 12)

                Image("turtleShade")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 270)
                    .opacity(0.85)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Every encounter\nhelps tell their story.")
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("A shared desktop workspace to recognise sea turtles, compare scale patterns, and follow their coastal journeys.")
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: 360, alignment: .leading)
                }

                // Elevated sub-card inspired by FigCraft Overview hero stat cards (#19344A, 18pt radius)
                HStack(spacing: 12) {
                    welcomePillar(icon: "square.grid.2x2", title: "Overview", subtitle: "Sightings & trends")
                    welcomePillar(icon: "map", title: "Coastal Map", subtitle: "Encounter pins")
                    welcomePillar(icon: "viewfinder", title: "Photo ID", subtitle: "I3S & scale review")
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Image(systemName: "water.waves")
                    Text("Built around conservation · Bali monitoring")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.76))
            }
            .foregroundStyle(.white)
            .padding(40)
        }
        .clipped()
    }

    private func welcomePillar(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FigCraftLoginTokens.elevatedNavy.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func signIn() {
        guard canSubmit else { return }
        isSigningIn = true; errorMessage = nil
        let submittedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { password = ""; isSigningIn = false }
            do { try await store.signIn(email: submittedEmail, password: password, rememberMe: rememberMe) }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription; focusedField = .password }
        }
    }
}

private struct LoginInputStyle: ViewModifier {
    let isFocused: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: FigCraftLoginTokens.inputRadius, style: .continuous)
                    .fill(isFocused ? FigCraftLoginTokens.inputFocused : FigCraftLoginTokens.inputUnfocused)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FigCraftLoginTokens.inputRadius, style: .continuous)
                    .stroke(
                        isFocused ? FigCraftLoginTokens.primary : FigCraftLoginTokens.secondaryBorder,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
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
