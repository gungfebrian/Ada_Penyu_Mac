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
                            .frame(width: min(max(geometry.size.width * 0.42, 360), 500))
                    }

                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            VStack(spacing: 18) {
                                if !isSplitLayout {
                                    compactBrandHeader
                                }

                                loginCard
                            }
                            .frame(maxWidth: 410)
                            .padding(.horizontal, FigCraftLoginTokens.gutter)
                            .padding(.vertical, 36)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        }

                        #if DEBUG
                        Button {
                            store.isAuthSheetPresented = true
                        } label: {
                            Label("API Settings", systemImage: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(FigCraftLoginTokens.supportingInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSigningIn)
                        .padding(14)
                        #endif
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
            Image("AdaPenyuMark").resizable().renderingMode(.template).scaledToFit().frame(width: 36, height: 36).foregroundStyle(FigCraftLoginTokens.primary)
            Image("AdaPenyuWordmark").resizable().renderingMode(.template).scaledToFit().frame(width: 124, height: 22)
                .foregroundStyle(FigCraftLoginTokens.primary)
            Spacer()
        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sign in")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(FigCraftLoginTokens.primary)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.system(size: 12.5, weight: .medium))
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
                            .font(.system(size: 13.5))
                            .foregroundStyle(FigCraftLoginTokens.primary)
                    }
                    .modifier(LoginInputStyle(isFocused: focusedField == .email))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.system(size: 12.5, weight: .medium))
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
                                    prompt: Text(verbatim: "Password")
                                        .foregroundColor(FigCraftLoginTokens.supportingInk)
                                )
                            } else {
                                SecureField(
                                    "",
                                    text: $password,
                                    prompt: Text(verbatim: "Password")
                                        .foregroundColor(FigCraftLoginTokens.supportingInk)
                                )
                            }
                        }
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .onSubmit(signIn)
                        .accessibilityLabel("Password")
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
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

                Toggle("Remember me", isOn: $rememberMe)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
                    .foregroundStyle(FigCraftLoginTokens.tertiaryInk)

                if let message = errorMessage ?? store.lastError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AdaColors.red)
                            .padding(.top, 1)

                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaColors.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdaColors.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button(action: signIn) {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(isSigningIn ? "Signing in…" : "Sign in")
                            .font(.system(size: 14, weight: .semibold))
                        if !isSigningIn {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
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

                if Self.enableQuickDemoBypass {
                    HStack(spacing: 10) {
                        Rectangle().fill(FigCraftLoginTokens.secondaryBorder.opacity(0.7)).frame(height: 1)
                        Text("demo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FigCraftLoginTokens.supportingInk)
                        Rectangle().fill(FigCraftLoginTokens.secondaryBorder.opacity(0.7)).frame(height: 1)
                    }
                    .padding(.top, 2)

                    HStack(spacing: 8) {
                        Button {
                            password = ""
                            store.enterDemoWorkspace(persona: .superAsiaNetwork)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "globe.asia.australia.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Asia Super Demo")
                                    .font(.system(size: 13.5, weight: .semibold))
                                Spacer()
                                Text("⌘D")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.20), in: Capsule())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Capsule().fill(FigCraftLoginTokens.elevatedNavy))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("d", modifiers: [.command])
                        .accessibilityLabel("Quick Demo Mode")

                        ActionDropdown(items: DemoDashboardPersona.allCases.map { persona in
                            DropdownAction(
                                title: persona.displayName,
                                selected: false,
                                action: {
                                    password = ""
                                    store.enterDemoWorkspace(persona: persona)
                                }
                            )
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 13))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(FigCraftLoginTokens.primary)
                            .frame(width: 52, height: 42)
                            .background(FigCraftLoginTokens.background, in: Capsule())
                            .overlay(Capsule().stroke(FigCraftLoginTokens.secondaryBorder, lineWidth: 1))
                        }
                        .help("Choose demo role")
                    }
                }
            }
            .disabled(isSigningIn)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: FigCraftLoginTokens.cardRadius, style: .continuous)
                .fill(FigCraftLoginTokens.surface)
                .shadow(color: Color.black.opacity(0.05), radius: 18, y: 8)
        )
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
                    .opacity(0.45)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image("AdaPenyuMark").resizable().scaledToFit().frame(width: 40, height: 40)
                    Image("AdaPenyuWordmark").resizable().scaledToFit().frame(width: 134, height: 24)
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 16)

                Image("turtleShade")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250)
                    .opacity(0.88)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sea Turtle\nPhoto-ID")
                        .font(.system(size: 36, weight: .semibold))
                        .tracking(-0.6)

                    Text("Southeast Asia · India · Indo-Pacific")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76))
                }

                Spacer(minLength: 8)
            }
            .foregroundStyle(.white)
            .padding(40)
        }
        .clipped()
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
