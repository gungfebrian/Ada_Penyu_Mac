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

            if let notice = store.sessionNotice, errorMessage == nil, store.lastError == nil, !isSigningIn {
                Label {
                    Text(notice)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .accessibilityHidden(true)
                }
                .font(.system(size: 13))
                .foregroundStyle(AdaColors.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AdaColors.navy.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(notice)
                .accessibilityIdentifier("login.sessionNotice")
            }

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

                ActionDropdown(
                    items: DemoDashboardPersona.allCases.map { persona in
                        DropdownAction(
                            title: persona.displayName,
                            subtitle: persona.roleLabel,
                            icon: "person.crop.circle",
                            selected: false,
                            action: { openDemo(persona) }
                        )
                    },
                    header: "Demo workspaces",
                    placement: .aboveLeading,
                    minWidth: 232
                ) {
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

            conservationArtwork(height: min(max(height * 0.36, 210), 300))

            VStack(alignment: .leading, spacing: 10) {
                Text("Sea turtle photo ID")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Track sightings, match scale patterns, and follow individuals over time.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            speciesFooterStrip
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 40)
        .padding(.top, 52)
        .padding(.bottom, 34)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                AdaColors.navy
                GeometryReader { bounds in
                    Image("bg_satu")
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                        .opacity(0.36)
                }
                RadialGradient(
                    colors: [AdaColors.accent.opacity(0.22), Color.clear],
                    center: .init(x: 0.78, y: 0.24),
                    startRadius: 20,
                    endRadius: 360
                )
            }
            .accessibilityHidden(true)
        }
        .clipped()
    }

    private func conservationArtwork(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Concentric bathymetric rings + migration arc connecting sighting nodes
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let center = CGPoint(x: w * 0.5, y: h * 0.44)
                let p1 = CGPoint(x: w * 0.20, y: h * 0.62)
                let p2 = CGPoint(x: w * 0.50, y: h * 0.44)
                let p3 = CGPoint(x: w * 0.80, y: h * 0.30)

                ZStack {
                    RadialGradient(
                        colors: [AdaColors.accent.opacity(0.28), Color.clear],
                        center: UnitPoint(x: 0.5, y: 0.44),
                        startRadius: 12,
                        endRadius: min(w, h) * 0.55
                    )

                    ForEach([0.42, 0.66, 0.90], id: \.self) { scale in
                        let diameter = min(w, h) * scale
                        Circle()
                            .stroke(Color.white.opacity(scale == 0.42 ? 0.16 : 0.08), lineWidth: 1)
                            .frame(width: diameter, height: diameter)
                            .position(center)
                    }

                    // Dashed migration track connecting reef sighting pins
                    Path { path in
                        path.move(to: p1)
                        path.addQuadCurve(to: p2, control: CGPoint(x: w * 0.33, y: h * 0.36))
                        path.addQuadCurve(to: p3, control: CGPoint(x: w * 0.68, y: h * 0.52))
                    }
                    .stroke(
                        Color.white.opacity(0.32),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 5])
                    )

                    // Supporting reef sighting pins (teardrop penyu silhouette)
                    loginRoutePin(size: 24)
                        .position(p1)
                    loginRoutePin(size: 26)
                        .position(p3)

                    // Central AdaPenyu fingerprint-turtle emblem
                    ZStack {
                        Circle()
                            .fill(AdaColors.navy.opacity(0.88))
                            .frame(width: 82, height: 82)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1.2)
                            )
                            .shadow(color: AdaColors.accent.opacity(0.30), radius: 20, y: 8)

                        Image("AdaPenyuMark")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 46, height: 46)
                            .foregroundStyle(.white)
                    }
                    .position(p2)
                }
            }

            // Minimal bottom capability pills
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    artworkPill(icon: "viewfinder.circle", label: "Pattern ID")
                    artworkPill(icon: "map", label: "Sighting Map")
                    artworkPill(icon: "checkmark.seal", label: "Review")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func loginRoutePin(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(AdaColors.accent.opacity(0.25))
                .frame(width: size * 1.45, height: size * 1.45)

            ZStack {
                PenyuMapPinShape()
                    .fill(.white.opacity(0.92))
                Image("AdaPenyuMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(AdaColors.navy)
                    .frame(width: size * 0.44, height: size * 0.44)
                    .offset(y: -size * 0.14)
            }
            .frame(width: size, height: size * 1.24)
            .shadow(color: Color.black.opacity(0.24), radius: 6, y: 3)
        }
    }

    private func artworkPill(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(AdaColors.navy.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private var speciesFooterStrip: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(["GreenSpecies", "HawksbillSpecies", "RidleySpecies"], id: \.self) { asset in
                    Image(asset)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 18)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Text("Indo-Pacific Sea Turtle Research")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .accessibilityHidden(true)
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
