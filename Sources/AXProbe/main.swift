import AppKit
import ApplicationServices

/// A one-shot diagnostic tool: while it runs, it periodically snapshots the Dock's
/// accessibility tree and the window-server window list into /tmp/missionx-probe.
/// Open Mission Control while it runs so we can see what the tree looks like there.
final class ProbeController: NSObject {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/missionx-probe")
    private let interval: TimeInterval = 1.0
    private let deadline = Date().addingTimeInterval(180)
    private var snapshotsWritten = 0
    private var lastTreeFingerprint = ""
    private var timer: Timer?

    func start() {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        log("probe started at \(Date())")
        log("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        waitForAccessibilityPermission()
        log("accessibility permission: granted")
        // Audible cue: the user should open Mission Control now.
        NSSound.beep()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.takeSnapshot()
        }
        takeSnapshot()
    }

    /// Blocks (while pumping the run loop) until the user approves accessibility access.
    private func waitForAccessibilityPermission() {
        if AXIsProcessTrusted() { return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        log("waiting for accessibility permission...")
        while !AXIsProcessTrusted() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    private func takeSnapshot() {
        if Date() >= deadline {
            finish()
            return
        }

        // Only record when the Dock's tree actually changed, so opening Mission
        // Control produces one obvious new snapshot instead of dozens of copies.
        let tree = dockTree()
        let fingerprint = "\(tree.count)-\(tree.hashValue)"
        guard fingerprint != lastTreeFingerprint else { return }
        lastTreeFingerprint = fingerprint

        snapshotsWritten += 1
        var text = "=== snapshot \(snapshotsWritten) @ \(Date()) ===\n\n"
        text += "--- Dock accessibility tree ---\n"
        text += tree
        text += "\n--- Window list (all windows, all spaces) ---\n"
        text += windowList()

        let url = outputDirectory.appendingPathComponent(String(format: "snapshot-%02d.txt", snapshotsWritten))
        try? text.write(to: url, atomically: true, encoding: .utf8)
        log("wrote \(url.lastPathComponent) (tree \(tree.count) bytes)")
    }

    private func dockTree() -> String {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return "Dock process not found\n"
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var text = "Dock pid=\(dock.processIdentifier)\n"
        text += "top-level attributes: \(AXDump.attributeNames(of: app).joined(separator: ", "))\n\n"
        text += AXDump.tree(of: app)
        return text
    }

    private func windowList() -> String {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return "unavailable\n"
        }
        var text = ""
        for window in windows {
            let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
            let name = window[kCGWindowName as String] as? String ?? ""
            let number = window[kCGWindowNumber as String] as? Int ?? -1
            let level = window[kCGWindowLayer as String] as? Int ?? 0
            let pid = window[kCGWindowOwnerPID as String] as? Int ?? -1
            let onscreen = (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
            var bounds = CGRect.zero
            if let dict = window[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) ?? .zero
            }
            text += String(format: "id=%-8d pid=%-6d layer=%-5d onscreen=%@ owner=%-22@ bounds=(%.0f,%.0f %.0fx%.0f) name=\"%@\"\n",
                           number, pid, level, onscreen ? "Y" : "N", owner as NSString,
                           bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
                           name as NSString)
        }
        return text
    }

    private func finish() {
        timer?.invalidate()
        log("probe finished")
        NSApp.terminate(nil)
    }

    private func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        let url = outputDirectory.appendingPathComponent("probe.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = ProbeController()
DispatchQueue.main.async { controller.start() }
application.run()
