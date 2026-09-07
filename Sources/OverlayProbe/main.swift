import AppKit

/// Shows several borderless windows at different window-server levels so we can see
/// which ones (if any) stay visible on top of Mission Control.
/// No special permission required.
final class OverlayProbeController {
    private var windows: [NSWindow] = []
    private let lifetime: TimeInterval = 180

    private let levelsToTest: [(name: String, level: Int)] = [
        ("maximumWindow", Int(CGWindowLevelForKey(.maximumWindow))),
        ("screenSaver", Int(CGWindowLevelForKey(.screenSaverWindow))),
        ("overlay", Int(CGWindowLevelForKey(.overlayWindow))),
        ("popUpMenu", Int(CGWindowLevelForKey(.popUpMenuWindow))),
        ("mainMenu", Int(CGWindowLevelForKey(.mainMenuWindow)))
    ]

    private let palette: [NSColor] = [
        .systemRed, .systemGreen, .systemBlue, .systemOrange, .systemPurple
    ]

    func start() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame

        for (index, entry) in levelsToTest.enumerated() {
            let size = CGSize(width: 460, height: 64)
            let origin = CGPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - CGFloat(index) * (size.height + 12) + 140
            )
            let window = makeWindow(
                frame: CGRect(origin: origin, size: size),
                text: "\(entry.name)  (level \(entry.level))",
                color: palette[index % palette.count],
                level: entry.level
            )
            windows.append(window)
        }

        log("showing \(windows.count) overlay windows for \(Int(lifetime))s")
        Timer.scheduledTimer(withTimeInterval: lifetime, repeats: false) { _ in
            NSApp.terminate(nil)
        }
    }

    private func makeWindow(frame: CGRect, text: String, color: NSColor, level: Int) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: level)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = color.withAlphaComponent(0.92)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 17, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(x: 0, y: 20, width: frame.width, height: 24)
        window.contentView?.addSubview(label)

        window.orderFrontRegardless()
        return window
    }

    private func log(_ message: String) {
        let directory = URL(fileURLWithPath: "/tmp/missionx-probe")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let line = "[\(Date())] overlay: \(message)\n"
        let url = directory.appendingPathComponent("overlay.log")
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
let controller = OverlayProbeController()
DispatchQueue.main.async { controller.start() }
application.run()
