import AppKit
import Combine
import Foundation

/// Lives with AppStore, so a copied secret expires even after Settings closes.
@MainActor
final class ExpiringSecretClipboard {
    private let pasteboard: NSPasteboard
    private let lifetime: Duration
    private var ownedChangeCount: Int?
    private var expiry: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general, lifetime: Duration = .seconds(60)) {
        self.pasteboard = pasteboard
        self.lifetime = lifetime
    }

    func copy(_ secret: String) -> Bool {
        expiry?.cancel()
        pasteboard.clearContents()
        guard pasteboard.setString(secret, forType: .string) else { ownedChangeCount = nil; return false }
        ownedChangeCount = pasteboard.changeCount
        let lifetime = lifetime
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: lifetime) } catch { return }
            self?.clearIfOwned()
        }
        return true
    }

    func clearIfOwned() {
        expiry?.cancel()
        expiry = nil
        if let ownedChangeCount, pasteboard.changeCount == ownedChangeCount { pasteboard.clearContents() }
        ownedChangeCount = nil
    }

    deinit { expiry?.cancel() }
}

@MainActor
final class OrganizationAPIKeySettings: ObservableObject {
    enum Change { case rotate, revoke }

    @Published private(set) var metadata: OrganizationAPIKeyMetadata?
    @Published private(set) var newSecret: String?
    @Published var isSecretRevealed = false
    @Published private(set) var didCopy = false
    @Published private(set) var hasSavedSecret = false
    @Published private(set) var isLoading = false
    @Published private(set) var operation: Change?
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingDestination: AppSection?
    @Published private var permissionDenied = false
    @Published private var isDemo = false
    @Published private var isOwner = false

    let clipboard: ExpiringSecretClipboard
    private var service: OrganizationAPIKeyService
    private var context: Context?
    private var revision = UUID()
    private var isVisible = false
    private var readTask: Task<OrganizationAPIKeyMetadata, Error>?
    private var changeTask: Task<IssuedOrganizationAPIKey?, Error>?

    private struct Context: Equatable {
        let client: ObjectIdentifier
        let userID: UUID?
        let organizationID: UUID?
        let role: UserRole?
        let demo: Bool
    }

    init(client: APIClient, clipboard: ExpiringSecretClipboard? = nil) {
        service = OrganizationAPIKeyService(client: client)
        self.clipboard = clipboard ?? ExpiringSecretClipboard()
        configure(client: client, user: client.account, isDemo: false)
    }

    var canManage: Bool { isOwner && !isDemo && !permissionDenied }
    var isChanging: Bool { operation != nil }
    var canChange: Bool { canManage && isVisible && metadata != nil && !isLoading && !isChanging }
    var accessMessage: String? {
        if isDemo { return "API keys are not available in demo mode. Sign in to a live organization to manage its key." }
        if !isOwner || permissionDenied { return "Only the organization owner can manage API keys." }
        return nil
    }

    func configure(client: APIClient, user: AppUser?, isDemo: Bool) {
        let next = Context(client: ObjectIdentifier(client), userID: user?.id,
            organizationID: user?.organisationID, role: user?.role, demo: isDemo)
        guard next != context else { return }
        leave()
        context = next
        service = OrganizationAPIKeyService(client: client)
        self.isDemo = isDemo
        isOwner = user?.role == .owner && user?.organisationID != nil
        permissionDenied = false
    }

    func enter() async {
        if !isVisible { permissionDenied = false }
        isVisible = true
        if metadata == nil { await load() }
    }

    func load() async {
        guard canManage, isVisible, !isLoading, !isChanging else { return }
        let captured = revision
        let service = service
        isLoading = true
        errorMessage = nil
        let task = Task { try await service.fetchMetadata() }
        readTask = task
        defer {
            if captured == revision { isLoading = false; readTask = nil }
        }
        do {
            let result = try await task.value
            guard captured == revision, isVisible else { return }
            metadata = result
        } catch {
            guard captured == revision, isVisible else { return }
            handle(error, changing: false)
        }
    }

    func rotate() async { await change(.rotate) }
    func revoke() async { await change(.revoke) }

    private func change(_ change: Change) async {
        guard canChange else { return }
        let captured = revision
        let service = service
        operation = change
        errorMessage = nil
        clearSecret()
        let task = Task<IssuedOrganizationAPIKey?, Error> {
            switch change {
            case .rotate: return try await service.rotate()
            case .revoke: try await service.revoke(); return nil
            }
        }
        changeTask = task
        defer {
            if captured == revision { operation = nil; changeTask = nil }
        }
        do {
            let result = try await task.value
            guard captured == revision, isVisible, canManage else { return }
            metadata = result?.metadata ?? .unconfigured
            newSecret = result?.apiKey
        } catch {
            guard captured == revision, isVisible else { return }
            metadata = nil
            handle(error, changing: true)
        }
    }

    private func handle(_ error: Error, changing: Bool) {
        switch (error as? APIError)?.statusCode {
        case 403:
            permissionDenied = true
            clearSecret()
        case 404, 405:
            errorMessage = "Organization API keys are not available on this server. Contact your backend administrator."
        default:
            // Do not render arbitrary server messages that might echo a credential.
            errorMessage = changing
                ? "The key may have changed on the server, but the operation could not be confirmed. Reload key status. If a new key was issued, its secret cannot be retrieved; deliberately rotate again to obtain another."
                : "Could not load the organization's API key status. Check your connection and try again."
        }
    }

    func copySecret() {
        guard let newSecret, canManage, isVisible else { return }
        didCopy = clipboard.copy(newSecret)
        if !didCopy { errorMessage = "Could not copy the key. Reveal it and save it before leaving." }
    }

    func acknowledgeSaved() { hasSavedSecret = true }

    func requestLeave(to destination: AppSection) -> Bool {
        guard !isChanging else { return false }
        if newSecret != nil, !hasSavedSecret {
            pendingDestination = destination
            return false
        }
        return true
    }

    func cancelNavigation() { pendingDestination = nil }

    func leave() {
        revision = UUID()
        isVisible = false
        readTask?.cancel()
        changeTask?.cancel()
        readTask = nil
        changeTask = nil
        isLoading = false
        operation = nil
        metadata = nil
        errorMessage = nil
        pendingDestination = nil
        clearSecret()
    }

    private func clearSecret() {
        newSecret = nil
        isSecretRevealed = false
        didCopy = false
        hasSavedSecret = false
    }
}
