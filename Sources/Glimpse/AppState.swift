import Foundation
import Observation

@Observable
final class AppState {
    static let shared = AppState()

    var viewerLogin: String?
    var lastError: String?
    var authFailed: Bool = false
    var isValidating = false
    var isFetching = false
    var sections = PRSections()
    var unreadCount: Int = 0
    var lastFetched: Date?

    @ObservationIgnored
    var pollEngine: PollEngine?

    func loadToken() -> String? { Keychain.read() }
    func saveToken(_ token: String) { Keychain.write(token) }

    func clearToken() {
        Keychain.delete()
        viewerLogin = nil
        lastError = nil
        authFailed = false
        sections = PRSections()
        lastFetched = nil
    }

    @MainActor
    func validateAndFetch() async {
        guard let token = loadToken(), !token.isEmpty else {
            lastError = "No token set"
            return
        }
        isValidating = true
        isFetching = true
        defer {
            isValidating = false
            isFetching = false
        }
        do {
            let result = try await GitHubClient(token: token).bootstrap()
            viewerLogin = result.login
            sections = result.sections
            lastFetched = Date()
            lastError = nil
            authFailed = false
        } catch {
            handle(error)
        }
    }

    @MainActor
    func refresh() async {
        guard let token = loadToken(), !token.isEmpty else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            sections = try await GitHubClient(token: token).pullRequests()
            lastFetched = Date()
            lastError = nil
            authFailed = false
        } catch {
            handle(error)
        }
    }

    @MainActor
    func bootstrap() async {
        guard loadToken() != nil else { return }
        await validateAndFetch()
    }

    @MainActor
    func startPolling() {
        if pollEngine == nil { pollEngine = PollEngine(state: self) }
        pollEngine?.start()
    }

    private func handle(_ error: Error) {
        if let ce = error as? GitHubClient.ClientError, ce.isAuthFailure {
            authFailed = true
            viewerLogin = nil
        }
        lastError = error.localizedDescription
    }
}
