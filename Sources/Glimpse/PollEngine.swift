import Foundation

@MainActor
final class PollEngine {
    private let state: AppState
    private var timer: Timer?
    private var persisted: PersistedState

    init(state: AppState) {
        self.state = state
        self.persisted = Persistence.load()
    }

    func start() {
        stop()
        scheduleTimer()
        Task { await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(Preferences.interval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tick() }
        }
    }

    func tick() async {
        guard let token = Keychain.read(), !token.isEmpty else { return }
        let client = GitHubClient(token: token)
        await pollPRs(client: client)
        await pollNotifications(client: client)
        if persisted.isFirstRun { persisted.isFirstRun = false }
        Persistence.save(persisted)
    }

    // MARK: - PRs

    private func pollPRs(client: GitHubClient) async {
        do {
            let sections = try await client.pullRequests()
            var seen = Set<String>()
            let openPRs = (sections.authored + sections.reviewRequested + sections.assigned)
                .filter { seen.insert($0.id).inserted }

            if !persisted.isFirstRun {
                fireTransitionNotifications(prs: openPRs)
                fireMergeNotifications(merged: sections.recentlyMerged)
            } else {
                for m in sections.recentlyMerged { persisted.knownMergedIds.insert(m.id) }
            }

            persisted.prSnapshots = Dictionary(
                openPRs.map { ($0.id, PRSnapshot($0)) },
                uniquingKeysWith: { a, _ in a }
            )
            state.sections = sections
            state.lastFetched = Date()
            state.lastError = nil
            state.authFailed = false
        } catch {
            handle(error)
        }
    }

    private func fireTransitionNotifications(prs: [PullRequest]) {
        guard Preferences.enabled else { return }
        for pr in prs {
            guard let old = persisted.prSnapshots[pr.id] else { continue }
            let oldRollup = RollupState(rawValue: old.rollup) ?? .none
            let oldReview = ReviewDecision(rawValue: old.reviewDecision) ?? .none
            let oldMergeable = Mergeable(rawValue: old.mergeable) ?? .unknown
            let isNewCommit = old.commitOid != pr.commitOid

            let wasReady = !isNewCommit
                && oldMergeable == .mergeable
                && oldReview == .approved
                && oldRollup == .success
                && !old.isDraft
            let isReady = pr.mergeable == .mergeable
                && pr.reviewDecision == .approved
                && pr.rollup == .success
                && !pr.isDraft

            if Preferences.ready, !wasReady, isReady {
                Notifier.shared.notify(
                    id: "ready-\(pr.id)-\(pr.commitOid)",
                    title: "Ready to merge",
                    body: "\(pr.repo)#\(pr.number) — \(pr.title)",
                    url: pr.url
                )
            }

            let wasApproved = !isNewCommit && oldReview == .approved
            let isApproved = pr.reviewDecision == .approved
            if Preferences.approved, !wasApproved, isApproved {
                Notifier.shared.notify(
                    id: "approved-\(pr.id)-\(pr.commitOid)",
                    title: "Approved",
                    body: "\(pr.repo)#\(pr.number) — \(pr.title)",
                    url: pr.url
                )
            }

            let oldFailed = !isNewCommit && (oldRollup == .failure || oldRollup == .error)
            let nowFailed = pr.rollup == .failure || pr.rollup == .error
            if Preferences.checksFailed, !oldFailed, nowFailed {
                Notifier.shared.notify(
                    id: "checks-\(pr.id)-\(pr.commitOid)",
                    title: "Checks failed",
                    body: "\(pr.repo)#\(pr.number) — \(pr.title)",
                    url: pr.url
                )
            }
        }
    }

    private func fireMergeNotifications(merged: [PullRequest]) {
        guard Preferences.enabled, Preferences.merged else {
            for m in merged { persisted.knownMergedIds.insert(m.id) }
            return
        }
        for pr in merged where !persisted.knownMergedIds.contains(pr.id) {
            Notifier.shared.notify(
                id: "merged-\(pr.id)",
                title: "PR merged",
                body: "\(pr.repo)#\(pr.number) — \(pr.title)",
                url: pr.url
            )
            persisted.knownMergedIds.insert(pr.id)
        }
        // bound size
        if persisted.knownMergedIds.count > 200 {
            persisted.knownMergedIds = Set(Array(persisted.knownMergedIds).suffix(200))
        }
    }

    // MARK: - /notifications inbox

    private func pollNotifications(client: GitHubClient) async {
        do {
            let resp = try await client.notifications(ifModifiedSince: persisted.notificationsLastModified)
            if resp.notModified { return }

            if let lm = resp.lastModified {
                persisted.notificationsLastModified = lm
            }

            let unread = resp.items.filter(\.unread)
            state.unreadCount = unread.count

            if !persisted.isFirstRun, Preferences.enabled, Preferences.inbox {
                let newOnes = unread.filter { !persisted.knownNotificationIds.contains($0.id) }
                for n in newOnes {
                    Notifier.shared.notify(
                        id: "ghn-\(n.id)",
                        title: "\(n.repository.fullName) — \(prettyReason(n.reason))",
                        body: n.subject.title,
                        url: n.webURL
                    )
                }
            }

            persisted.knownNotificationIds.formUnion(resp.items.map(\.id))
            if persisted.knownNotificationIds.count > 500 {
                persisted.knownNotificationIds = Set(Array(persisted.knownNotificationIds).suffix(500))
            }
        } catch {
            handle(error)
        }
    }

    // MARK: - errors

    private func handle(_ error: Error) {
        if let ce = error as? GitHubClient.ClientError, ce.isAuthFailure {
            state.authFailed = true
            state.viewerLogin = nil
        }
        state.lastError = error.localizedDescription
    }
}

private func prettyReason(_ raw: String) -> String {
    switch raw {
    case "mention": "mentioned you"
    case "review_requested": "review requested"
    case "assign": "assigned to you"
    case "author": "your PR"
    case "comment": "new comment"
    case "team_mention": "team mention"
    case "state_change": "state changed"
    case "subscribed": "watching"
    default: raw.replacingOccurrences(of: "_", with: " ")
    }
}
