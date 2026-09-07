import AppKit

/// Appends to /tmp/missionx.log. This app has no window to show errors in, so a
/// log file is the only way to see what it is doing.
enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/missionx.log")
    private static let queue = DispatchQueue(label: "missionx.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

/// Accessibility and window-server rects put the origin at the top-left of the
/// primary display with y growing down; AppKit puts it at the bottom-left with y
/// growing up. Everything crossing that boundary goes through here.
enum Coordinates {
    private static var primaryHeight: CGFloat {
        // The screen whose frame origin is (0,0) defines the global flip.
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
    }

    static func appKitRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitPoint(fromTopLeft point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
