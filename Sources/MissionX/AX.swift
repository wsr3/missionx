import AppKit
import ApplicationServices

/// Undocumented but long-stable: returns the window-server window id backing an
/// accessibility window element. This is how we tie a Mission Control thumbnail
/// back to the real window we need to close.
///
/// Declared as returning Int32 rather than AXError: an unexpected value coming
/// back from C would be undefined behaviour when bridged straight to the enum.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> Int32

enum AX {
    // MARK: - Reading

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        array(element, kAXChildrenAttribute) ?? []
    }

    static func windows(_ element: AXUIElement) -> [AXUIElement] {
        array(element, kAXWindowsAttribute) ?? []
    }

    static func array(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? [AXUIElement]
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return (raw as? NSNumber)?.boolValue
    }

    static func identifier(_ element: AXUIElement) -> String? {
        string(element, kAXIdentifierAttribute)
    }

    static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    static func title(_ element: AXUIElement) -> String? {
        string(element, kAXTitleAttribute)
    }

    /// Frame in accessibility coordinates: origin at the top-left of the primary
    /// display, y growing downwards.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin: CGPoint = value(element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = value(element, kAXSizeAttribute, .cgSize) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let wrapped = raw, CFGetTypeID(wrapped) == AXValueGetTypeID() else { return nil }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        guard AXValueGetValue(wrapped as! AXValue, type, buffer) else { return nil }
        return buffer.pointee
    }

    // MARK: - Writing

    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ newValue: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, newValue as CFBoolean) == .success
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    // MARK: - Searching

    /// Depth-limited search for a descendant carrying a specific AXIdentifier.
    static func descendant(of element: AXUIElement, identifier: String, maxDepth: Int = 6) -> AXUIElement? {
        if AX.identifier(element) == identifier { return element }
        guard maxDepth > 0 else { return nil }
        for child in children(element) {
            if let match = descendant(of: child, identifier: identifier, maxDepth: maxDepth - 1) {
                return match
            }
        }
        return nil
    }

    // MARK: - Window ids

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == 0, id != 0 else { return nil }
        return id
    }

    // MARK: - Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
