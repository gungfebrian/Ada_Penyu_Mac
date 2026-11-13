import SwiftUI

struct AccountLoginView: View {
    @ObservedObject var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            TurtleAppIconMark(size: 64)
            Text("Sign in to Ada Penyu").font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                TextField("Email", text: $email).textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                Toggle("Remember me", isOn: $rememberMe)
                Text("Remember me saves your session securely on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = errorMessage ?? store.lastError {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            Button {
                isSigningIn = true
                errorMessage = nil
                Task {
                    defer { password = ""; isSigningIn = false }
                    do { try await store.signIn(email: email, password: password, rememberMe: rememberMe) }
                    catch is CancellationError { }
                    catch { errorMessage = error.localizedDescription }
                }
            } label: {
                if isSigningIn { ProgressView().controlSize(.small) }
                else { Text("Sign In").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            .keyboardShortcut(.defaultAction)
            #if DEBUG
            Button("Developer API Settings…") { store.isAuthSheetPresented = true }
            #endif
        }
        .padding(32)
        .frame(width: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AdaColors.canvas)
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
#endif
