import SwiftUI
import AppKit

@main
struct GlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(AppState.shared)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    var body: some View {
        let unread = AppState.shared.unreadCount
        Image(systemName: unread > 0 ? "bell.badge.fill" : "bell")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?
    private var settingsWindow: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        Notifier.shared.setup()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await Notifier.shared.requestAuthorization() }

        if Keychain.read() == nil {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        } else {
            Task { @MainActor in AppState.shared.startPolling() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environment(AppState.shared)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Glimpse Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 480, height: 520))
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            guard let w = self?.settingsWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
