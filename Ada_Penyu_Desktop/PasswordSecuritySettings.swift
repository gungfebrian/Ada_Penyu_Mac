import Combine
import Foundation

/// Mirrors AdaPenyu iPhone's password policy (`Models/AccessControl.swift`).
enum PasswordPolicy {
    static let minLength = 8
    static let maxLength = 128

    static func hasValidLength(_ password: String) -> Bool {
        password.count >= minLength && password.count <= maxLength
    }

    static func hasLetter(_ password: String) -> Bool {
        password.rangeOfCharacter(from: .letters) != nil
    }

    static func hasNumber(_ password: String) -> Bool {
        password.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func hasNonWhitespaceSymbol(_ password: String) -> Bool {
        let nonWhitespaceSymbols = CharacterSet.punctuationCharacters.union(.symbols)
        return password.unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && nonWhitespaceSymbols.contains(scalar)
        }
    }

    static func isValid(_ password: String) -> Bool {
        hasValidLength(password)
            && hasLetter(password)
            && hasNumber(password)
            && hasNonWhitespaceSymbol(password)
    }
}

@MainActor
struct PasswordSecurityService {
    let client: APIClient

    func changePassword(
        currentPassword: String,
        newPassword: String,
        confirmPassword: String,
        for user: AppUser
    ) async throws {
        try client.authorization?.requireUser(user)
        let generation = client.authorization?.generation
        let payload = [
            "current_password": currentPassword,
            "new_password": newPassword,
            "confirm_password": confirmPassword
        ]
        try await client.sendVoid(APIRequest(
            method: "POST",
            path: "/api/v1/auth/change-password",
            body: try JSONEncoder().encode(payload),
            acceptedStatuses: [204],
            timeoutInterval: 30
        ))
        if let generation {
            try client.authorization?.check(generation)
        }
    }
}

@MainActor
final class PasswordSecurityModel: ObservableObject {
    @Published var currentPassword = ""
    @Published var newPassword = ""
    @Published var confirmNewPassword = ""
    @Published var isCurrentPasswordVisible = false
    @Published var isNewPasswordVisible = false
    @Published var isConfirmPasswordVisible = false

    @Published private(set) var isSubmitting = false
    @Published private(set) var currentPasswordError: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var accessDeniedMessage: String?
    @Published private(set) var isDemo = false
    @Published private(set) var hasLiveAccount = false

    private var client: APIClient
    private var activeUser: AppUser?
    private var context: Context?
    private var revision = UUID()

    private struct Context: Equatable {
        let client: ObjectIdentifier
        let userID: UUID?
        let organizationID: UUID?
        let demo: Bool
    }

    init(client: APIClient) {
        self.client = client
        configure(client: client, user: client.account, isDemo: false)
    }

    var canChangePassword: Bool {
        !isDemo && activeUser != nil
    }

    var accessMessage: String? {
        if isDemo {
            return "Password changes are not available in demo mode. Sign in to a live account to update your password."
        }
        if activeUser == nil {
            return "Sign in to a live account to update your password."
        }
        return nil
    }

    var canSubmit: Bool {
        canChangePassword
            && !isSubmitting
            && !currentPassword.isEmpty
            && !newPassword.isEmpty
            && !confirmNewPassword.isEmpty
    }

    func configure(client: APIClient, user: AppUser?, isDemo: Bool) {
        let next = Context(
            client: ObjectIdentifier(client),
            userID: isDemo ? nil : user?.id,
            organizationID: isDemo ? nil : user?.organisationID,
            demo: isDemo
        )
        self.client = client
        self.activeUser = isDemo ? nil : user
        self.isDemo = isDemo
        self.hasLiveAccount = !isDemo && user != nil
        guard next != context else { return }
        context = next
        invalidateAndClear()
    }

    func clearForm() {
        currentPassword = ""
        newPassword = ""
        confirmNewPassword = ""
        isCurrentPasswordVisible = false
        isNewPasswordVisible = false
        isConfirmPasswordVisible = false
        clearMessages()
    }

    func invalidateAndClear() {
        revision = UUID()
        isSubmitting = false
        clearForm()
    }

    func clearMessages() {
        currentPasswordError = nil
        errorMessage = nil
        accessDeniedMessage = nil
    }

    @discardableResult
    func submit(onConfirmedSignOut: () -> Void) async -> Bool {
        guard !isSubmitting else { return false }
        clearMessages()

        guard canChangePassword, let user = activeUser else {
            errorMessage = accessMessage ?? "Sign in to a live account to update your password."
            return false
        }
        guard !currentPassword.isEmpty else {
            errorMessage = "Please enter your current password."
            return false
        }
        guard PasswordPolicy.isValid(newPassword) else {
            errorMessage = "Your password must be at least 8 characters with a mix of letters, number, and symbols."
            return false
        }
        guard newPassword == confirmNewPassword else {
            errorMessage = "New password and confirmation do not match."
            return false
        }

        let capturedRevision = revision
        let capturedUserID = user.id
        let capturedAuthGeneration = client.authorization?.generation
        let service = PasswordSecurityService(client: client)

        isSubmitting = true
        defer {
            if revision == capturedRevision {
                isSubmitting = false
            }
        }

        do {
            try await service.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmPassword: confirmNewPassword,
                for: user
            )
            guard revision == capturedRevision,
                  activeUser?.id == capturedUserID,
                  client.authorization?.generation == capturedAuthGeneration else {
                return false
            }
            clearForm()
            onConfirmedSignOut()
            return true
        } catch {
            guard revision == capturedRevision,
                  activeUser?.id == capturedUserID,
                  client.authorization?.generation == capturedAuthGeneration else {
                return false
            }
            if error is CancellationError {
                return false
            }
            handleError(error)
            return false
        }
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? APIError {
            if apiError.statusCode == 422,
               apiError.code == "CURRENT_PASSWORD_INVALID" || apiError.fieldErrors["current_password"] != nil {
                currentPasswordError = apiError.fieldErrors["current_password"] ?? apiError.localizedDescription
                return
            }
            switch apiError.statusCode {
            case 403:
                accessDeniedMessage = apiError.errorDescription ?? "Access denied by server."
                return
            case 404, 405:
                errorMessage = "Password updates are not available on this server."
                return
            default:
                break
            }
        }
        errorMessage = error.localizedDescription
    }
}
