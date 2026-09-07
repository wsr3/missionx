import AppKit
import ServiceManagement

/// Launch-at-login support.
///
/// Prefers `SMAppService`, which puts a proper entry in System Settings →
/// General → Login Items. That can refuse to register a self-signed build, so
/// there is a plain LaunchAgent fallback.
enum LoginItem {
    private static let label = "com.missionx.app"

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// - Returns: a message to show the user if something needs their attention.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        enabled ? enable() : disable()
    }

    private static func enable() -> String? {
        do {
            try SMAppService.mainApp.register()
            Log.write("login item registered via SMAppService")
            if SMAppService.mainApp.status == .requiresApproval {
                return "Allow MissionX in System Settings → General → Login Items."
            }
            return nil
        } catch {
            Log.write("SMAppService register failed: \(error.localizedDescription); using LaunchAgent")
            return writeLaunchAgent()
        }
    }

    private static func disable() -> String? {
        if SMAppService.mainApp.status == .enabled {
            do {
                try SMAppService.mainApp.unregister()
                Log.write("login item unregistered via SMAppService")
            } catch {
                Log.write("SMAppService unregister failed: \(error.localizedDescription)")
            }
        }
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try? FileManager.default.removeItem(at: launchAgentURL)
            _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
            Log.write("launch agent removed")
        }
        return nil
    }

    private static func writeLaunchAgent() -> String? {
        let executable = Bundle.main.executableURL?.path ?? ""
        guard !executable.isEmpty else {
            return "Could not determine the app's path, so launch at login was not enabled."
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // Restart if it ever crashes; there is no UI to notice it died.
            "KeepAlive": false
        ]

        do {
            try FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: launchAgentURL)
            _ = runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
            Log.write("launch agent written to \(launchAgentURL.path)")
            return nil
        } catch {
            Log.write("launch agent write failed: \(error.localizedDescription)")
            return "Could not enable launch at login: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
