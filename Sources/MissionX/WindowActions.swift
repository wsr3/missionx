import AppKit
import ApplicationServices

enum WindowActions {
    /// Presses the window's real close button, which is what ⌘W does and
    /// therefore respects "unsaved changes" dialogs.
    @discardableResult
    static func close(_ window: ResolvedWindow) -> Bool {
        guard let axWindow = window.axWindow else {
            Log.write("close failed: no ax window for \(window.displayTitle)")
            return false
        }
        if let button = AX.element(axWindow, kAXCloseButtonAttribute), AX.press(button) {
            Log.write("closed \(window.displayTitle)")
            return true
        }
        // Some apps (notably Electron-based ones) omit the close button element
        // but still respond to the window-level close action.
        if AX.actions(axWindow).contains(kAXCancelAction), AX.perform(axWindow, kAXCancelAction) {
            Log.write("closed \(window.displayTitle) via cancel action")
            return true
        }
        Log.write("close failed for \(window.displayTitle)")
        return false
    }

    @discardableResult
    static func minimize(_ window: ResolvedWindow) -> Bool {
        guard let axWindow = window.axWindow else { return false }
        let ok = AX.setBool(axWindow, kAXMinimizedAttribute, true)
        Log.write("minimize \(window.displayTitle): \(ok)")
        return ok
    }

    @discardableResult
    static func quitApp(_ window: ResolvedWindow) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return false }
        let ok = app.terminate()
        Log.write("quit \(window.ownerName): \(ok)")
        return ok
    }

    /// Removes an entire desktop from the spaces strip.
    @discardableResult
    static func removeSpace(_ space: SpaceTile) -> Bool {
        guard space.isRemovable else { return false }
        let ok = AX.perform(space.element, "AXRemoveDesktop")
        Log.write("remove space \(space.title ?? "?"): \(ok)")
        return ok
    }
}
