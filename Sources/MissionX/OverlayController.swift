import AppKit

/// Owns the on-screen close buttons and keeps them in sync with Mission Control.
final class OverlayController {
    private let monitor = MissionControlMonitor()
    private let resolver = WindowResolver()
    private let interceptor = EventInterceptor()
    private let selection = SelectionWindow()

    private var buttons: [TargetID: CloseButtonWindow] = [:]
    private var windows: [CGWindowID: ResolvedWindow] = [:]
    private var spaces: [Int: SpaceTile] = [:]
    /// Reused across sessions so we are not allocating panels on the hot path.
    /// Separate pools because the two badge sizes are not interchangeable.
    private var recycledWindowBadges: [CloseButtonWindow] = []
    private var recycledSpaceBadges: [CloseButtonWindow] = []

    /// Set once the user starts navigating with the keyboard; moving the mouse
    /// hands control back to the pointer.
    private var focusedID: CGWindowID?

    var isActive: Bool { monitor.missionControlIsOpen }

    /// Currently visible windows, ordered left-to-right then top-to-bottom, for
    /// keyboard navigation.
    var orderedWindows: [ResolvedWindow] {
        windows.values.sorted {
            if abs($0.frame.minY - $1.frame.minY) > 20 { return $0.frame.minY < $1.frame.minY }
            return $0.frame.minX < $1.frame.minX
        }
    }

    @discardableResult
    func start() -> Bool {
        guard interceptor.start() else { return false }

        interceptor.onHoverChanged = { [weak self] buttonID, thumbnailID in
            guard let self else { return }
            for (id, button) in self.buttons {
                button.isHovered = (id == buttonID)
            }
            // The pointer moved onto a different window: let it take over from
            // the keyboard selection.
            if thumbnailID != nil, thumbnailID != self.focusedID {
                self.setFocus(nil)
            }
        }

        interceptor.onKeyDown = { [weak self] keyCode, flags in
            self?.handleKey(keyCode, flags: flags) ?? false
        }

        monitor.onOpen = { [weak self] layout in
            self?.resolver.invalidateCache()
            self?.interceptor.isEnabled = true
            self?.apply(layout)
        }
        monitor.onUpdate = { [weak self] layout in
            self?.apply(layout)
        }
        monitor.onClose = { [weak self] in
            self?.interceptor.isEnabled = false
            self?.teardown()
        }
        monitor.start()
        Log.write("overlay controller started")
        return true
    }

    /// Re-reads Mission Control; call after acting on a window so the buttons
    /// follow the re-layout immediately.
    func refresh() {
        monitor.refreshNow()
    }

    // MARK: - Layout

    private func apply(_ layout: MissionControlLayout) {
        applyWindows(layout.thumbnails)
        applySpaces(layout.spaces)
        rebuildHitTargets()

        // Keep the highlight on the selected window as Mission Control re-lays
        // things out, and drop it if that window is gone.
        if let focusedID {
            setFocus(windows[focusedID] != nil ? focusedID : nil)
        }
    }

    private func applyWindows(_ thumbnails: [Thumbnail]) {
        let resolved = resolver.resolve(thumbnails)

        var next: [CGWindowID: ResolvedWindow] = [:]
        for window in resolved { next[window.windowID] = window }

        // A transient empty or unresolvable layout happens during Mission
        // Control's open/close animation; keep what we have rather than flicker.
        if next.isEmpty && !thumbnails.isEmpty { return }
        windows = next

        // Retire badges for windows that are gone, or that we can no longer act
        // on: a button that does nothing when clicked is worse than none.
        for (id, button) in buttons {
            guard case let .window(windowID) = id else { continue }
            if next[windowID]?.axWindow == nil {
                button.hide()
                recycledWindowBadges.append(button)
                buttons.removeValue(forKey: id)
            }
        }

        for window in resolved where window.axWindow != nil {
            let id = TargetID.window(window.windowID)
            let button = buttons[id]
                ?? recycledWindowBadges.popLast()
                ?? CloseButtonWindow(size: CloseButtonWindow.windowBadgeSize)
            buttons[id] = button
            button.show(at: CGPoint(x: window.frame.minX, y: window.frame.minY))
        }
    }

    private func applySpaces(_ tiles: [SpaceTile]) {
        var next: [Int: SpaceTile] = [:]
        for (index, tile) in tiles.enumerated() where tile.isRemovable && isUsable(tile.frame) {
            next[index] = tile
        }
        spaces = next

        for (id, button) in buttons {
            guard case let .space(index) = id else { continue }
            if next[index] == nil {
                button.hide()
                recycledSpaceBadges.append(button)
                buttons.removeValue(forKey: id)
            }
        }

        for (index, tile) in next {
            let id = TargetID.space(index)
            let button = buttons[id]
                ?? recycledSpaceBadges.popLast()
                ?? CloseButtonWindow(size: CloseButtonWindow.spaceBadgeSize)
            buttons[id] = button
            button.show(at: CGPoint(x: tile.frame.minX, y: tile.frame.minY))
        }
    }

    /// The spaces strip slides out of view when collapsed, reporting frames that
    /// are partly above the top of the display. Badges there would be stranded.
    private func isUsable(_ frame: CGRect) -> Bool {
        frame.minY >= 0
    }

    private func rebuildHitTargets() {
        interceptor.targets = buttons.compactMap { id, button in
            guard button.hitRect != .zero else { return nil }
            return HitTarget(id: id, rect: button.hitRect) { [weak self] in
                self?.performClose(on: id)
            }
        }
        interceptor.hoverRegions = windows.values.map { (id: $0.windowID, rect: $0.frame) }
    }

    // MARK: - Actions

    private func performClose(on id: TargetID) {
        switch id {
        case .window(let windowID):
            guard let window = windows[windowID] else { return }
            WindowActions.close(window)
        case .space(let index):
            guard let tile = spaces[index] else { return }
            WindowActions.removeSpace(tile)
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.resolver.invalidateCache()
            self?.refresh()
        }
    }

    // MARK: - Keyboard

    private enum Key {
        static let w: CGKeyCode = 13
        static let m: CGKeyCode = 46
        static let q: CGKeyCode = 12
        static let returnKey: CGKeyCode = 36
        static let escape: CGKeyCode = 53
        static let tab: CGKeyCode = 48
        static let left: CGKeyCode = 123
        static let right: CGKeyCode = 124
        static let down: CGKeyCode = 125
        static let up: CGKeyCode = 126
    }

    /// The window a shortcut applies to: the keyboard selection if the user is
    /// navigating, otherwise whatever the pointer is over.
    private var actionTarget: ResolvedWindow? {
        if let focusedID, let window = windows[focusedID] { return window }
        if let id = interceptor.hoveredThumbnail { return windows[id] }
        return nil
    }

    private func handleKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        if flags.contains(.maskCommand) {
            guard let window = actionTarget else { return false }
            switch keyCode {
            case Key.w:
                WindowActions.close(window)
                scheduleRefresh()
            case Key.m:
                WindowActions.minimize(window)
                scheduleRefresh()
            case Key.q:
                WindowActions.quitApp(window)
                scheduleRefresh()
            default:
                return false
            }
            return true
        }

        // Unmodified keys: navigation. Anything we do not handle passes through,
        // so Escape still dismisses Mission Control.
        switch keyCode {
        case Key.left: return moveFocus(.left)
        case Key.right: return moveFocus(.right)
        case Key.up: return moveFocus(.up)
        case Key.down: return moveFocus(.down)
        case Key.tab: return cycleFocus(reverse: flags.contains(.maskShift))
        case Key.returnKey: return activateFocused()
        case Key.escape:
            setFocus(nil)
            return false
        default:
            return false
        }
    }

    // MARK: - Focus

    private enum Direction {
        case left, right, up, down
    }

    private func setFocus(_ id: CGWindowID?) {
        focusedID = id
        if let id, let window = windows[id] {
            selection.show(around: window.frame)
        } else {
            selection.hide()
        }
    }

    private func moveFocus(_ direction: Direction) -> Bool {
        let ordered = orderedWindows
        guard !ordered.isEmpty else { return false }

        // First arrow press just selects something: whatever the pointer is
        // over, else the top-left window.
        guard let current = actionTarget else {
            setFocus(ordered.first?.windowID)
            return true
        }

        let origin = CGPoint(x: current.frame.midX, y: current.frame.midY)
        var best: (id: CGWindowID, score: CGFloat)?

        for candidate in ordered where candidate.windowID != current.windowID {
            let dx = candidate.frame.midX - origin.x
            let dy = candidate.frame.midY - origin.y
            let along: CGFloat
            let across: CGFloat
            switch direction {
            case .left:  along = -dx; across = abs(dy)
            case .right: along = dx;  across = abs(dy)
            case .up:    along = -dy; across = abs(dx)
            case .down:  along = dy;  across = abs(dx)
            }
            // Must actually lie in the travel direction. Penalise sideways
            // drift so movement feels like stepping through a grid.
            guard along > 1 else { continue }
            let score = along + across * 2
            if best == nil || score < best!.score {
                best = (candidate.windowID, score)
            }
        }

        if let best { setFocus(best.id) }
        return true
    }

    private func cycleFocus(reverse: Bool) -> Bool {
        let ordered = orderedWindows
        guard !ordered.isEmpty else { return false }
        guard let current = actionTarget,
              let index = ordered.firstIndex(where: { $0.windowID == current.windowID }) else {
            setFocus(ordered.first?.windowID)
            return true
        }
        let step = reverse ? -1 : 1
        let next = (index + step + ordered.count) % ordered.count
        setFocus(ordered[next].windowID)
        return true
    }

    /// Pressing the thumbnail is what Mission Control does on click: switch to
    /// that window and dismiss.
    private func activateFocused() -> Bool {
        guard let window = actionTarget else { return false }
        AX.press(window.thumbnail.element)
        setFocus(nil)
        return true
    }

    // MARK: - Teardown

    private func teardown() {
        setFocus(nil)
        for (id, button) in buttons {
            button.hide()
            switch id {
            case .window: recycledWindowBadges.append(button)
            case .space: recycledSpaceBadges.append(button)
            }
        }
        buttons.removeAll()
        windows.removeAll()
        spaces.removeAll()
        interceptor.targets = []
        interceptor.hoverRegions = []
        resolver.invalidateCache()
    }
}
