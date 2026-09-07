import AppKit
import ApplicationServices

/// Renders an accessibility element tree into readable indented text.
enum AXDump {
    static func tree(of element: AXUIElement, maxDepth: Int = 14) -> String {
        var out = ""
        walk(element, depth: 0, maxDepth: maxDepth, into: &out)
        return out
    }

    private static func walk(_ element: AXUIElement, depth: Int, maxDepth: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: depth)
        out += pad + describe(element) + "\n"

        guard depth < maxDepth else {
            out += pad + "  <max depth reached>\n"
            return
        }

        for child in children(of: element) {
            walk(child, depth: depth + 1, maxDepth: maxDepth, into: &out)
        }
    }

    static func describe(_ element: AXUIElement) -> String {
        var parts: [String] = []
        parts.append(string(element, kAXRoleAttribute) ?? "?role")

        if let subrole = string(element, kAXSubroleAttribute) { parts.append("subrole=\(subrole)") }
        if let title = string(element, kAXTitleAttribute), !title.isEmpty { parts.append("title=\(quoted(title))") }
        if let id = string(element, kAXIdentifierAttribute), !id.isEmpty { parts.append("id=\(quoted(id))") }
        if let desc = string(element, kAXDescriptionAttribute), !desc.isEmpty { parts.append("desc=\(quoted(desc))") }
        if let help = string(element, kAXHelpAttribute), !help.isEmpty { parts.append("help=\(quoted(help))") }
        if let value = valueSummary(element) { parts.append("value=\(value)") }
        if let frame = frame(of: element) {
            parts.append(String(format: "frame=(%.0f,%.0f %.0fx%.0f)",
                                frame.origin.x, frame.origin.y, frame.size.width, frame.size.height))
        }

        let attrs = attributeNames(of: element)
        // Attributes worth noticing because they usually mean "this maps to a real window".
        let interesting = ["AXWindow", "AXWindowID", "AXWindowNumber", "AXParent", "AXTopLevelUIElement", "AXURL"]
            .filter { attrs.contains($0) }
        if !interesting.isEmpty { parts.append("has=[\(interesting.joined(separator: ","))]") }

        let actions = actionNames(of: element)
        if !actions.isEmpty { parts.append("actions=[\(actions.joined(separator: ","))]") }

        let kids = children(of: element).count
        if kids > 0 { parts.append("children=\(kids)") }

        return parts.joined(separator: " ")
    }

    // MARK: - Attribute readers

    static func children(of element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let array = raw as? [AXUIElement] else { return [] }
        return array
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin: CGPoint = axValue(element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(element, kAXSizeAttribute, .cgSize) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(value as! AXValue, type, result) else { return nil }
        return result.pointee
    }

    static func attributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    static func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    private static func valueSummary(_ element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success,
              let value = raw else { return nil }
        if let s = value as? String { return s.isEmpty ? nil : quoted(s) }
        if let n = value as? NSNumber { return n.stringValue }
        return String(describing: CFCopyTypeIDDescription(CFGetTypeID(value)) as String?)
    }

    private static func quoted(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(flat)\""
    }
}
