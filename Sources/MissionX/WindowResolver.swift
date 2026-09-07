import AppKit
import ApplicationServices

/// A Mission Control thumbnail tied to the real window it represents.
struct ResolvedWindow {
    let thumbnail: Thumbnail
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    /// The real window's accessibility element. Nil if the owning app does not
    /// answer accessibility queries; the close button is hidden in that case.
    let axWindow: AXUIElement?

    var frame: CGRect { thumbnail.frame }
    var displayTitle: String { thumbnail.title ?? ownerName }
}

/// Turns thumbnails into real windows.
///
/// The trick that makes this reliable: while Mission Control is open the window
/// server reports each real window's on-screen bounds as the *thumbnail's*
/// bounds. So an exact geometry match identifies the window, with no dependence
/// on titles (which Mission Control truncates, decorates, or omits entirely).
final class WindowResolver {
    /// Bounds come from two different APIs, so allow for rounding.
    private let tolerance: CGFloat = 2.0

    /// AXWindows enumeration is the expensive part; reuse it while a single
    /// Mission Control session is open.
    private var axWindowCache: [pid_t: [(id: CGWindowID, element: AXUIElement)]] = [:]

    func invalidateCache() {
        axWindowCache.removeAll()
    }

    func resolve(_ thumbnails: [Thumbnail]) -> [ResolvedWindow] {
        let candidates = onScreenWindows()
        var claimed = Set<CGWindowID>()

        return thumbnails.compactMap { thumbnail in
            guard let match = candidates.first(where: {
                !claimed.contains($0.id) && matches($0.bounds, thumbnail.frame)
            }) else {
                Log.write("unmatched thumbnail \(thumbnail.frame) title=\(thumbnail.title ?? "nil")")
                return nil
            }
            claimed.insert(match.id)
            return ResolvedWindow(
                thumbnail: thumbnail,
                windowID: match.id,
                pid: match.pid,
                ownerName: match.owner,
                axWindow: axWindow(pid: match.pid, windowID: match.id)
            )
        }
    }

    private func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    private struct Candidate {
        let id: CGWindowID
        let pid: pid_t
        let owner: String
        let bounds: CGRect
    }

    private func onScreenWindows() -> [Candidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            // Layer 0 is where ordinary application windows live. Mission
            // Control's own backdrop (Dock, layer 18/20) and the menu bar
            // (layer 24/25) sit above it and must not be matched.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 1, bounds.height > 1 else { return nil }
            return Candidate(
                id: id,
                pid: pid,
                owner: info[kCGWindowOwnerName as String] as? String ?? "",
                bounds: bounds
            )
        }
    }

    private func axWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        if let hit = axWindowCache[pid]?.first(where: { $0.id == windowID })?.element {
            return hit
        }
        // A miss can mean a stale cache rather than a genuinely unavailable
        // window, so re-read once before giving up. Failures are never cached.
        let windows = readAXWindows(pid: pid)
        axWindowCache[pid] = windows
        return windows.first(where: { $0.id == windowID })?.element
    }

    private func readAXWindows(pid: pid_t) -> [(id: CGWindowID, element: AXUIElement)] {
        let app = AXUIElementCreateApplication(pid)
        return AX.windows(app).compactMap { element in
            guard let id = AX.windowID(of: element) else { return nil }
            return (id: id, element: element)
        }
    }
}
