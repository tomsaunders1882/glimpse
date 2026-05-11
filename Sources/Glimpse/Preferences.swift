import Foundation

enum PreferenceKeys {
    static let pollIntervalSeconds = "pollIntervalSeconds"
    static let notificationsEnabled = "notificationsEnabled"
    static let notifyMerged = "notifyMerged"
    static let notifyApproved = "notifyApproved"
    static let notifyReady = "notifyReady"
    static let notifyChecksFailed = "notifyChecksFailed"
    static let notifyInbox = "notifyInbox"
}

enum Preferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.pollIntervalSeconds: 60,
            PreferenceKeys.notificationsEnabled: true,
            PreferenceKeys.notifyMerged: true,
            PreferenceKeys.notifyApproved: true,
            PreferenceKeys.notifyReady: true,
            PreferenceKeys.notifyChecksFailed: true,
            PreferenceKeys.notifyInbox: true,
        ])
    }

    static var interval: Int { max(30, UserDefaults.standard.integer(forKey: PreferenceKeys.pollIntervalSeconds)) }
    static var enabled: Bool { UserDefaults.standard.bool(forKey: PreferenceKeys.notificationsEnabled) }
    static var merged: Bool { UserDefaults.standard.bool(forKey: PreferenceKeys.notifyMerged) }
    static var approved: Bool { UserDefaults.standard.bool(forKey: PreferenceKeys.notifyApproved) }
    static var ready: Bool { UserDefaults.standard.bool(forKey: PreferenceKeys.notifyReady) }
    static var checksFailed: Bool { UserDefaults.standard.bool(forKey: PreferenceKeys.notifyChecksFailed) }
    static var inbox: Bool { UserDefaults.standard.bool(forKey: PreferenceKeys.notifyInbox) }
}
