import Foundation

struct PullRequest: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repo: String
    let isDraft: Bool
    let mergeable: Mergeable
    let reviewDecision: ReviewDecision
    let rollup: RollupState
    let commitOid: String
    let updatedAt: Date
}

enum Mergeable: String {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"

    init(_ raw: String?) { self = Mergeable(rawValue: raw ?? "") ?? .unknown }
}

enum ReviewDecision: String {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
    case none

    init(_ raw: String?) { self = ReviewDecision(rawValue: raw ?? "") ?? .none }
}

enum RollupState: String {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case pending = "PENDING"
    case error = "ERROR"
    case expected = "EXPECTED"
    case none

    init(_ raw: String?) { self = RollupState(rawValue: raw ?? "") ?? .none }
}

struct PRSections: Equatable {
    var authored: [PullRequest] = []
    var reviewRequested: [PullRequest] = []
    var assigned: [PullRequest] = []
    var recentlyMerged: [PullRequest] = []
    var totalCount: Int { authored.count + reviewRequested.count + assigned.count }
}

struct GitHubNotification: Decodable, Hashable, Identifiable {
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: String
    let subject: Subject
    let repository: Repo

    struct Subject: Decodable, Hashable {
        let title: String
        let url: String?
        let type: String
    }
    struct Repo: Decodable, Hashable {
        let fullName: String
    }

    var webURL: URL? {
        if let api = subject.url {
            let web = api
                .replacingOccurrences(of: "api.github.com/repos/", with: "github.com/")
                .replacingOccurrences(of: "/pulls/", with: "/pull/")
            return URL(string: web)
        }
        return URL(string: "https://github.com/\(repository.fullName)")
    }
}

struct NotificationsResponse {
    let notModified: Bool
    let items: [GitHubNotification]
    let lastModified: String?
}
