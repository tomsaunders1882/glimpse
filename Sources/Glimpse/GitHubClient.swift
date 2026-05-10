import Foundation

struct GitHubClient {
    let token: String
    private let session: URLSession = .shared

    enum ClientError: LocalizedError {
        case http(Int, String)
        case unauthorized
        case forbidden(String)
        case decode
        case graphQL(String)

        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return "HTTP \(code): \(msg)"
            case .unauthorized: return "Token invalid or expired. Re-authenticate in Settings."
            case .forbidden(let msg): return "Access denied: \(msg)"
            case .decode: return "Could not decode response"
            case .graphQL(let msg): return "GraphQL: \(msg)"
            }
        }

        var isAuthFailure: Bool {
            switch self {
            case .unauthorized, .forbidden: return true
            default: return false
            }
        }
    }

    func viewerLogin() async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.github.com/user")!)
        addAuthHeaders(&req)
        let (data, resp) = try await session.data(for: req)
        try checkOK(resp, data: data)
        struct User: Decodable { let login: String }
        return try JSONDecoder().decode(User.self, from: data).login
    }

    func bootstrap() async throws -> (login: String, sections: PRSections) {
        let result = try await runPRQuery(includeViewer: true)
        guard let login = result.viewer?.login else { throw ClientError.decode }
        return (login, result.sections)
    }

    func pullRequests() async throws -> PRSections {
        try await runPRQuery(includeViewer: false).sections
    }

    private struct PRQueryResult {
        let viewer: Viewer?
        let sections: PRSections
        struct Viewer { let login: String }
    }

    private func runPRQuery(includeViewer: Bool) async throws -> PRQueryResult {
        let viewerFragment = includeViewer ? "viewer { login }" : ""
        let query = """
        query {
          \(viewerFragment)
          authored: search(query: "is:open is:pr author:@me archived:false sort:updated-desc", type: ISSUE, first: 30) {
            nodes { ... on PullRequest { ...PR } }
          }
          reviewRequested: search(query: "is:open is:pr review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: 30) {
            nodes { ... on PullRequest { ...PR } }
          }
          assigned: search(query: "is:open is:pr assignee:@me archived:false sort:updated-desc", type: ISSUE, first: 30) {
            nodes { ... on PullRequest { ...PR } }
          }
          recentlyMerged: search(query: "is:pr is:merged author:@me archived:false sort:updated-desc", type: ISSUE, first: 10) {
            nodes { ... on PullRequest { ...PR } }
          }
        }
        fragment PR on PullRequest {
          id
          number
          title
          url
          isDraft
          mergeable
          reviewDecision
          updatedAt
          repository { nameWithOwner }
          commits(last: 1) {
            nodes { commit { oid statusCheckRollup { state } } }
          }
        }
        """

        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        req.httpMethod = "POST"
        addAuthHeaders(&req)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["query": query])

        let (data, resp) = try await session.data(for: req)
        try checkOK(resp, data: data)

        let decoded = try JSONDecoder().decode(GraphQLResponse<PRRoot>.self, from: data)
        if let errors = decoded.errors, !errors.isEmpty {
            throw ClientError.graphQL(errors.map(\.message).joined(separator: "; "))
        }
        guard let root = decoded.data else { throw ClientError.decode }

        let sections = PRSections(
            authored: root.authored.nodes.compactMap { $0?.toPR() },
            reviewRequested: root.reviewRequested.nodes.compactMap { $0?.toPR() },
            assigned: root.assigned.nodes.compactMap { $0?.toPR() },
            recentlyMerged: root.recentlyMerged.nodes.compactMap { $0?.toPR() }
        )
        return PRQueryResult(
            viewer: root.viewer.map { .init(login: $0.login) },
            sections: sections
        )
    }

    func notifications(ifModifiedSince: String?) async throws -> NotificationsResponse {
        var req = URLRequest(url: URL(string: "https://api.github.com/notifications?participating=true")!)
        addAuthHeaders(&req)
        if let ifModifiedSince {
            req.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClientError.decode }
        if http.statusCode == 304 {
            return NotificationsResponse(notModified: true, items: [], lastModified: nil)
        }
        try checkOK(resp, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode([GitHubNotification].self, from: data)
        return NotificationsResponse(
            notModified: false,
            items: items,
            lastModified: http.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    // MARK: - helpers

    private func addAuthHeaders(_ req: inout URLRequest) {
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Glimpse/0.1", forHTTPHeaderField: "User-Agent")
    }

    private func checkOK(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw ClientError.decode }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw ClientError.unauthorized
        case 403: throw ClientError.forbidden(String(data: data, encoding: .utf8) ?? "")
        default: throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

// MARK: - GraphQL decoding

private struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GQLError]?
    struct GQLError: Decodable { let message: String }
}

private struct PRRoot: Decodable {
    let viewer: ViewerData?
    let authored: SearchNodes
    let reviewRequested: SearchNodes
    let assigned: SearchNodes
    let recentlyMerged: SearchNodes
    struct ViewerData: Decodable { let login: String }
}

private struct SearchNodes: Decodable {
    let nodes: [PRRaw?]
}

private struct PRRaw: Decodable {
    let id: String
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let mergeable: String?
    let reviewDecision: String?
    let updatedAt: String
    let repository: Repo
    let commits: Commits

    struct Repo: Decodable { let nameWithOwner: String }
    struct Commits: Decodable {
        let nodes: [CommitNode]
        struct CommitNode: Decodable {
            let commit: Commit
            struct Commit: Decodable {
                let oid: String
                let statusCheckRollup: Rollup?
                struct Rollup: Decodable { let state: String }
            }
        }
    }

    func toPR() -> PullRequest? {
        guard let url = URL(string: url) else { return nil }
        let lastCommit = commits.nodes.first?.commit
        let date = ISO8601DateFormatter().date(from: updatedAt) ?? Date()
        return PullRequest(
            id: id,
            number: number,
            title: title,
            url: url,
            repo: repository.nameWithOwner,
            isDraft: isDraft,
            mergeable: Mergeable(mergeable),
            reviewDecision: ReviewDecision(reviewDecision),
            rollup: RollupState(lastCommit?.statusCheckRollup?.state),
            commitOid: lastCommit?.oid ?? "",
            updatedAt: date
        )
    }
}
