import Foundation

struct PRSnapshot: Codable, Hashable {
    let rollup: String
    let mergeable: String
    let reviewDecision: String
    let isDraft: Bool
    let commitOid: String?

    init(_ pr: PullRequest) {
        rollup = pr.rollup.rawValue
        mergeable = pr.mergeable.rawValue
        reviewDecision = pr.reviewDecision.rawValue
        isDraft = pr.isDraft
        commitOid = pr.commitOid
    }
}

struct PersistedState: Codable {
    var prSnapshots: [String: PRSnapshot] = [:]
    var knownMergedIds: Set<String> = []
    var notificationsLastModified: String? = nil
    var knownNotificationIds: Set<String> = []
    var isFirstRun: Bool = true
}

enum Persistence {
    static let url: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Glimpse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    static func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return PersistedState() }
        return state
    }

    static func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
