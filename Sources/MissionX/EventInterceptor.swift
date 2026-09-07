import AppKit

/// Identifies something the overlay can put a close badge on. Spaces have no
/// stable identifier of their own, so they are keyed by position in the strip.
enum TargetID: Hashable {
    case window(CGWindowID)
    case space(Int)
}

/// A clickable region, in top-left-origin global coordinates (the space both
/// accessibility frames and `CGEvent.location` use).
struct HitTarget {
    let id: TargetID
    let rect: CGRect
    let onClick: () -> Void
}

/// Intercepts input at the window-server level.
///
/// Necessary because Mission Control consumes mouse events exclusively: our
/// panels draw above it but never receive a click. So we watch the event stream,
/// swallow clicks that land on one of our buttons, and let everything else
/// through untouched.
final class EventInterceptor {
    /// Only intercept while Mission Control is up; otherwise events pass
    /// straight through with no work done.
    var isEnabled = false

    /// Regions that swallow clicks: the close buttons.
    var targets: [HitTarget] = []

    /// Whole-thumbnail regions, used only to know which window the pointer is
    /// over so keyboard shortcuts can apply to it. Clicks pass through.
    var hoverRegions: [(id: CGWindowID, rect: CGRect)] = []

    /// Reports the close button under the pointer, then the thumbnail under it.
    /// Drives hover visuals, which cannot rely on AppKit tracking areas here.
    var onHoverChanged: ((_ button: TargetID?, _ thumbnail: CGWindowID?) -> Void)?

    /// Return true to swallow the key event.
    var onKeyDown: ((CGKeyCode, CGEventFlags) -> Bool)?

    /// The window the pointer is currently over, if any.
    private(set) var hoveredThumbnail: CGWindowID?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hovered: TargetID?
    /// A click that started on a button must also swallow its mouse-up, or
    /// Mission Control sees a stray release and reacts to it.
    private var swallowingClick = false

    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<EventInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            Log.write("ERROR: could not create event tap")
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("event tap installed")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    /// Runs on the main run loop and must stay fast; the system disables taps
    /// that take too long.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        // The system disables a tap that ever timed out; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.write("event tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            return passThrough
        }

        guard isEnabled else { return passThrough }

        switch type {
        case .mouseMoved:
            updateHover(at: event.location)
            return passThrough

        case .leftMouseDown:
            guard let target = target(at: event.location) else { return passThrough }
            swallowingClick = true
            // Never run app logic inline in the callback.
            DispatchQueue.main.async(execute: target.onClick)
            return nil

        case .leftMouseUp:
            guard swallowingClick else { return passThrough }
            swallowingClick = false
            return nil

        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if onKeyDown?(keyCode, event.flags) == true { return nil }
            return passThrough

        default:
            return passThrough
        }
    }

    private func target(at location: CGPoint) -> HitTarget? {
        targets.first { $0.rect.contains(location) }
    }

    private func updateHover(at location: CGPoint) {
        let button = target(at: location)?.id
        // Smallest match wins: thumbnails can overlap in Mission Control, and
        // the one drawn on top is the one the pointer visually points at.
        let thumbnail = hoverRegions
            .filter { $0.rect.contains(location) }
            .min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })?
            .id

        guard button != hovered || thumbnail != hoveredThumbnail else { return }
        hovered = button
        hoveredThumbnail = thumbnail
        DispatchQueue.main.async { [weak self] in
            self?.onHoverChanged?(button, thumbnail)
        }
    }
}
