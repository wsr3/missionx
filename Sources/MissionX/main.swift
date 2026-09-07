import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("--- MissionX launched ---")
        setUpStatusItem()

        if hasWorkingAccessibilityAccess() {
            overlay.start()
        } else {
            requestAccessibilityAccess()
        }
    }

    // MARK: - Permission

    /// `AXIsProcessTrusted()` is cached per process and does not update when the
    /// user flips the switch, so test the capability we actually need instead:
    /// can we read the Dock's children?
    private func hasWorkingAccessibilityAccess() -> Bool {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw)
        return result == .success
    }

    private func requestAccessibilityAccess() {
        Log.write("accessibility access missing; prompting")
        AX.promptForPermission()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self, self.hasWorkingAccessibilityAccess() else { return }
            timer.invalidate()
            Log.write("accessibility access granted")
            self.overlay.start()
            self.refreshStatusItemMenu()
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "macwindow.badge.plus",
            accessibilityDescription: "Mission Control Plus"
        )
        item.button?.image?.isTemplate = true
        statusItem = item
        refreshStatusItemMenu()
    }

    private func refreshStatusItemMenu() {
        let menu = NSMenu()

        let granted = hasWorkingAccessibilityAccess()
        let status = NSMenuItem(
            title: granted ? "Active" : "Accessibility permission needed",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        if !granted {
            menu.addItem(
                withTitle: "Open Accessibility Settings…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            ).target = self
        }

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Log", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MissionX", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem?.menu = menu
    }

    @objc private func toggleLaunchAtLogin() {
        let message = LoginItem.setEnabled(!LoginItem.isEnabled)
        refreshStatusItemMenu()

        if let message {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/missionx.log"))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
