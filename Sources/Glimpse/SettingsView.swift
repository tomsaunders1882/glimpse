import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var newToken: String = ""
    @State private var isReplacing: Bool = false
    @State private var hasSavedToken: Bool = Keychain.read() != nil

    @AppStorage(PreferenceKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(PreferenceKeys.notifyMerged) private var notifyMerged = true
    @AppStorage(PreferenceKeys.notifyReady) private var notifyReady = true
    @AppStorage(PreferenceKeys.notifyChecksFailed) private var notifyChecksFailed = true
    @AppStorage(PreferenceKeys.notifyInbox) private var notifyInbox = true
    @AppStorage(PreferenceKeys.pollIntervalSeconds) private var pollInterval = 60

    var body: some View {
        Form {
            Section("GitHub") {
                if hasSavedToken && !isReplacing {
                    HStack {
                        Label("Token saved", systemImage: "lock.fill")
                            .foregroundStyle(.green)
                        if let login = state.viewerLogin {
                            Text("(\(login))").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Replace") { isReplacing = true }
                        Button("Remove", role: .destructive) {
                            state.clearToken()
                            hasSavedToken = false
                            newToken = ""
                            isReplacing = false
                        }
                    }
                } else {
                    SecureField("Paste personal access token", text: $newToken)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save & validate") { Task { await save() } }
                            .disabled(newToken.isEmpty || state.isValidating)
                        if state.isValidating { ProgressView().controlSize(.small) }
                        Spacer()
                        if isReplacing {
                            Button("Cancel") {
                                isReplacing = false
                                newToken = ""
                            }
                        }
                    }
                }

                if let err = state.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                Toggle("PR merged", isOn: $notifyMerged).disabled(!notificationsEnabled)
                Toggle("Ready to merge", isOn: $notifyReady).disabled(!notificationsEnabled)
                Toggle("Checks failed", isOn: $notifyChecksFailed).disabled(!notificationsEnabled)
                Toggle("GitHub inbox (mentions, reviews, comments)", isOn: $notifyInbox).disabled(!notificationsEnabled)
            }

            Section("Polling") {
                Picker("Check every", selection: $pollInterval) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                }
                .onChange(of: pollInterval) { _, _ in
                    state.pollEngine?.scheduleTimer()
                }
            }

            Section {
                Text("Token needs `repo`, `notifications`, `read:org` scopes, SSO-authorized for your org.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
    }

    private func save() async {
        state.saveToken(newToken)
        newToken = ""
        await state.validateAndFetch()
        if state.viewerLogin != nil {
            state.startPolling()
            hasSavedToken = true
            isReplacing = false
        } else {
            // validation failed — let the user retry; surface error already shown
            hasSavedToken = false
        }
    }
}
