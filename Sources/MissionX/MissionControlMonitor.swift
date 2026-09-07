import AppKit
import ApplicationServices

/// One window thumbnail shown inside Mission Control.
struct Thumbnail {
    let element: AXUIElement
    /// Top-left-origin frame, matching what the window server reports.
    let frame: CGRect
    let title: String?
}

/// One entry in the spaces strip along the top of Mission Control.
struct SpaceTile {
    let element: AXUIElement
    let frame: CGRect
    let title: String?
    /// Only user-added desktops can be removed; the first desktop cannot.
    let isRemovable: Bool
}

struct MissionControlLayout {
    var thumbnails: [Thumbnail] = []
    var spaces: [SpaceTile] = []
}

/// Watches the Dock's accessibility tree to tell when Mission Control is on
/// screen and what it currently shows.
///
/// On macOS 26 the Dock exposes this shape, which is what we rely on:
///     AXApplication "Dock"
///       └─ AXGroup  id=mc            (present only while Mission Control is up)
///          └─ AXGroup id=mc.display
///             ├─ AXGroup id=mc.windows      → one AXButton per window thumbnail
///             └─ AXGroup id=mc.spaces
///                └─ AXList id=mc.spaces.list → one AXButton per desktop
final class MissionControlMonitor {
    private static let rootIdentifier = "mc"
    private static let windowsIdentifier = "mc.windows"
    private static let spacesListIdentifier = "mc.spaces.list"

    /// Polling beats AX notifications here: the Dock does not reliably post
    /// notifications for Mission Control, and checking two children is cheap.
    private let pollInterval: TimeInterval = 0.2

    private var timer: Timer?
    private var dockElement: AXUIElement?
    private var dockPID: pid_t = 0
    private var isOpen = false

    var onOpen: ((MissionControlLayout) -> Void)?
    var onUpdate: ((MissionControlLayout) -> Void)?
    var onClose: (() -> Void)?

    var missionControlIsOpen: Bool { isOpen }

    func start() {
        refreshDockElement()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer?.tolerance = pollInterval / 2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Forces a re-read; used right after we act on a window so the overlay
    /// follows Mission Control's re-layout without waiting for the next tick.
    func refreshNow() {
        poll()
    }

    private func refreshDockElement() {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            dockElement = nil
            return
        }
        dockPID = dock.processIdentifier
        dockElement = AXUIElementCreateApplication(dockPID)
    }

    private func poll() {
        // The Dock restarts occasionally; pick up its new process when it does.
        if dockElement == nil || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .contains(where: { $0.processIdentifier == dockPID }) {
            refreshDockElement()
        }
        guard let dock = dockElement else { return }

        guard let root = AX.children(dock).first(where: { AX.identifier($0) == Self.rootIdentifier }) else {
            if isOpen {
                isOpen = false
                Log.write("mission control closed")
                onClose?()
            }
            return
        }

        let layout = readLayout(root: root)
        if isOpen {
            onUpdate?(layout)
        } else {
            isOpen = true
            Log.write("mission control opened: \(layout.thumbnails.count) thumbnails, \(layout.spaces.count) spaces")
            onOpen?(layout)
        }
    }

    private func readLayout(root: AXUIElement) -> MissionControlLayout {
        var layout = MissionControlLayout()

        if let container = AX.descendant(of: root, identifier: Self.windowsIdentifier) {
            layout.thumbnails = AX.children(container).compactMap { element in
                guard let frame = AX.frame(element), frame.width > 1, frame.height > 1 else { return nil }
                return Thumbnail(element: element, frame: frame, title: AX.title(element))
            }
        }

        if let list = AX.descendant(of: root, identifier: Self.spacesListIdentifier) {
            layout.spaces = AX.children(list).compactMap { element in
                guard let frame = AX.frame(element), frame.width > 1, frame.height > 1 else { return nil }
                return SpaceTile(
                    element: element,
                    frame: frame,
                    title: AX.title(element),
                    isRemovable: AX.actions(element).contains("AXRemoveDesktop")
                )
            }
        }

        return layout
    }
}
