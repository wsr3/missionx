import AppKit

private final class SelectionView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 2, dy: 2),
            xRadius: 8,
            yRadius: 8
        )
        border.lineWidth = 4
        NSColor.controlAccentColor.setStroke()
        border.stroke()
    }
}

/// The highlight drawn around the keyboard-selected thumbnail. Mission Control
/// has no keyboard selection of its own on macOS 26, so we supply the indicator.
final class SelectionWindow {
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.contentView = SelectionView()
    }

    /// - Parameter frame: the thumbnail's frame in top-left-origin coordinates.
    func show(around frame: CGRect) {
        let outset = frame.insetBy(dx: -4, dy: -4)
        panel.setFrame(Coordinates.appKitRect(fromTopLeft: outset), display: true)
        panel.contentView?.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
