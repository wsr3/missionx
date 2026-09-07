import AppKit

/// The little ⊗ badge drawn on a thumbnail corner.
private final class CloseButtonView: NSView {
    /// Hover is driven from the event tap, not from tracking areas: Mission
    /// Control swallows the mouse events AppKit would need.
    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    private let isPressed = false

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 2
        let circle = bounds.insetBy(dx: inset, dy: inset)

        let fill: NSColor
        if isPressed {
            fill = NSColor(white: 0.10, alpha: 0.95)
        } else if isHovered {
            fill = NSColor(white: 0.18, alpha: 0.95)
        } else {
            fill = NSColor(white: 0.12, alpha: 0.72)
        }

        let path = NSBezierPath(ovalIn: circle)
        fill.setFill()
        path.fill()
        NSColor(white: 1.0, alpha: isHovered ? 0.9 : 0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        // The X.
        let glyph = circle.insetBy(dx: circle.width * 0.30, dy: circle.height * 0.30)
        let stroke = NSBezierPath()
        stroke.move(to: CGPoint(x: glyph.minX, y: glyph.minY))
        stroke.line(to: CGPoint(x: glyph.maxX, y: glyph.maxY))
        stroke.move(to: CGPoint(x: glyph.minX, y: glyph.maxY))
        stroke.line(to: CGPoint(x: glyph.maxX, y: glyph.minY))
        stroke.lineWidth = 1.8
        stroke.lineCapStyle = .round
        NSColor(white: 1.0, alpha: isHovered ? 1.0 : 0.85).setStroke()
        stroke.stroke()
    }
}

/// A small always-on-top panel holding one close button.
///
/// Deliberately one panel per button rather than a single full-screen overlay:
/// clicks anywhere else then reach Mission Control itself, so selecting a window
/// by clicking its thumbnail keeps working.
final class CloseButtonWindow {
    static let windowBadgeSize: CGFloat = 24
    /// Desktop tiles in the spaces strip are only ~160x90, so they need a
    /// smaller badge to stay legible.
    static let spaceBadgeSize: CGFloat = 18

    private let size: CGFloat
    private let panel: NSPanel
    private let buttonView: CloseButtonView

    /// The badge's frame in top-left-origin coordinates, for hit testing in the
    /// event tap.
    private(set) var hitRect: CGRect = .zero

    var isHovered: Bool {
        get { buttonView.isHovered }
        set { buttonView.isHovered = newValue }
    }

    init(size: CGFloat = CloseButtonWindow.windowBadgeSize) {
        self.size = size
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        panel = NSPanel(
            contentRect: frame,
            // .nonactivatingPanel is essential: activating this app would make
            // macOS dismiss Mission Control out from under us.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        buttonView = CloseButtonView(frame: frame)
        panel.contentView = buttonView
    }

    /// - Parameter corner: the thumbnail's top-left corner in top-left-origin
    ///   coordinates; the badge is centred on it.
    func show(at corner: CGPoint) {
        hitRect = CGRect(
            x: corner.x - size / 2,
            y: corner.y - size / 2,
            width: size,
            height: size
        )
        let point = Coordinates.appKitPoint(fromTopLeft: corner)
        panel.setFrameOrigin(CGPoint(x: point.x - size / 2, y: point.y - size / 2))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        buttonView.isHovered = false
        hitRect = .zero
    }
}
