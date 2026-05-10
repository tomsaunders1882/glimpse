import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if state.authFailed { authBanner }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    inboxRow
                    section("Authored", prs: state.sections.authored)
                    section("Review requested", prs: state.sections.reviewRequested)
                    section("Assigned", prs: state.sections.assigned)
                    if state.sections.totalCount == 0, state.viewerLogin != nil {
                        Text("No open PRs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                    if state.viewerLogin == nil {
                        Text("Add a token in Settings to get started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                }
            }
            .frame(maxHeight: 480)
            Divider()
            footer
        }
        .frame(width: 380)
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.badge")
            Text("Glimpse").font(.headline)
            Spacer()
            if state.isFetching {
                ProgressView().controlSize(.small)
            }
            if let login = state.viewerLogin {
                Text(login).foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(10)
    }

    private var authBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Token invalid or expired").font(.callout).fontWeight(.medium)
                Text("Re-paste it in Settings.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                AppDelegate.shared?.openSettings()
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    @ViewBuilder
    private var inboxRow: some View {
        if state.unreadCount > 0 {
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/notifications")!)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray.fill").foregroundStyle(.tint)
                    Text("Inbox").font(.callout)
                    Spacer()
                    Text("\(state.unreadCount) unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            Divider()
        }
    }

    // MARK: - sections

    @ViewBuilder
    private func section(_ title: String, prs: [PullRequest]) -> some View {
        if !prs.isEmpty {
            HStack {
                Text(title).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Text("\(prs.count)").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)

            ForEach(prs) { pr in
                PRRow(pr: pr)
                Divider().padding(.leading, 24)
            }
        }
    }

    // MARK: - footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.isFetching || state.viewerLogin == nil)

            if let last = state.lastFetched {
                Text("Updated \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let err = state.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }

            Spacer()

            Button("Settings…") {
                AppDelegate.shared?.openSettings()
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(8)
    }
}

// MARK: - PR row

struct PRRow: View {
    let pr: PullRequest

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(rollupColor).frame(width: 8, height: 8).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(pr.repo)#\(pr.number)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if pr.isDraft { pill("Draft", .gray) }
                        if isReady { pill("Ready", .green) }
                        if pr.mergeable == .conflicting { pill("Conflict", .red) }
                        if let r = reviewBadge { pill(r.0, r.1) }
                    }
                    Text(pr.title).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var rollupColor: Color {
        switch pr.rollup {
        case .success: .green
        case .failure, .error: .red
        case .pending, .expected: .yellow
        case .none: .gray.opacity(0.5)
        }
    }

    private var isReady: Bool {
        pr.mergeable == .mergeable
            && pr.reviewDecision == .approved
            && pr.rollup == .success
            && !pr.isDraft
    }

    private var reviewBadge: (String, Color)? {
        switch pr.reviewDecision {
        case .approved: ("Approved", .green)
        case .changesRequested: ("Changes", .red)
        case .reviewRequired: ("Review", .yellow)
        case .none: nil
        }
    }
}

@ViewBuilder
private func pill(_ text: String, _ color: Color) -> some View {
    Text(text)
        .font(.system(size: 9, weight: .semibold))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
}
