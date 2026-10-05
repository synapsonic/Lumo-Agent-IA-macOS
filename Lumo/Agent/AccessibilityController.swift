import AppKit
import ApplicationServices
import Foundation

/// Accessibility-based UI control. Lumo observes the accessibility tree first and
/// uses absolute coordinates only as a fallback when an app exposes no usable AX element.
enum AccessibilityController {
    static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    static func requestPermission() -> ToolResult {
        let trusted = isTrusted(prompt: true)
        return .init(success: trusted, output: trusted ? "Accessibilité macOS autorisée." : "Demande d’accès Accessibilité affichée. Active Lumo dans Réglages Système > Confidentialité et sécurité > Accessibilité, puis réessaie.")
    }

    static func snapshot(app: String, maxDepth: Int, maxItems: Int) -> ToolResult {
        guard isTrusted() else { return permissionError() }
        guard let running = findApp(app) else { return .init(success: false, output: "Application introuvable ou non ouverte: \(app)") }
        let root = AXUIElementCreateApplication(running.processIdentifier)
        var lines: [String] = []
        walk(root, depth: 0, maxDepth: max(1, min(maxDepth, 8)), maxItems: max(10, min(maxItems, 500)), path: "0", lines: &lines)
        return .init(success: true, output: "app=\(running.localizedName ?? app) pid=\(running.processIdentifier)\n" + lines.joined(separator: "\n"))
    }

    static func click(app: String, role: String, title: String, value: String, index: Int) -> ToolResult {
        guard isTrusted() else { return permissionError() }
        guard let running = findApp(app) else { return .init(success:false, output:"Application introuvable: \(app)") }
        let root = AXUIElementCreateApplication(running.processIdentifier)
        let matches = find(root, role: role, title: title, value: value, maxDepth: 10, maxItems: 1200)
        guard !matches.isEmpty else { return .init(success:false, output:"Élément UI introuvable. Fais d’abord ui_snapshot pour observer l’interface.") }
        let chosen = matches[min(max(index, 0), matches.count - 1)]
        let result = AXUIElementPerformAction(chosen, kAXPressAction as CFString)
        return .init(success: result == .success, output: result == .success ? "Élément cliqué dans \(running.localizedName ?? app)." : "Impossible de cliquer (AXError \(result.rawValue)).")
    }

    static func setValue(app: String, role: String, title: String, currentValue: String, value: String, index: Int) -> ToolResult {
        guard isTrusted() else { return permissionError() }
        guard let running = findApp(app) else { return .init(success:false, output:"Application introuvable: \(app)") }
        let root = AXUIElementCreateApplication(running.processIdentifier)
        let matches = find(root, role: role, title: title, value: currentValue, maxDepth: 10, maxItems: 1200)
        guard !matches.isEmpty else { return .init(success:false, output:"Champ UI introuvable. Fais d’abord ui_snapshot.") }
        let chosen = matches[min(max(index, 0), matches.count - 1)]
        let result = AXUIElementSetAttributeValue(chosen, kAXValueAttribute as CFString, value as CFTypeRef)
        return .init(success: result == .success, output: result == .success ? "Valeur saisie." : "Impossible de saisir la valeur (AXError \(result.rawValue)).")
    }

    static func focusApp(_ app: String) -> ToolResult {
        guard let running = findApp(app) else { return .init(success:false, output:"Application introuvable: \(app)") }
        let ok = running.activate(options: [.activateIgnoringOtherApps])
        return .init(success:ok, output:ok ? "Application activée: \(running.localizedName ?? app)" : "Impossible d’activer l’application")
    }

    static func typeText(_ text: String) -> ToolResult {
        guard isTrusted() else { return permissionError() }
        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var u = UniChar(scalar.value)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u); up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
        return .init(success:true, output:"Texte saisi dans l’élément actuellement focalisé.")
    }

    static func key(_ key: String, modifiers: String) -> ToolResult {
        guard isTrusted() else { return permissionError() }
        let map:[String:CGKeyCode] = ["return":36,"enter":36,"tab":48,"space":49,"escape":53,"delete":51,"up":126,"down":125,"left":123,"right":124,"a":0,"c":8,"v":9,"x":7,"s":1,"o":31,"w":13,"q":12]
        guard let code = map[key.lowercased()] else { return .init(success:false,output:"Touche non prise en charge: \(key)") }
        var flags: CGEventFlags = []
        let m = modifiers.lowercased(); if m.contains("command") || m.contains("cmd") { flags.insert(.maskCommand) }; if m.contains("shift") { flags.insert(.maskShift) }; if m.contains("option") || m.contains("alt") { flags.insert(.maskAlternate) }; if m.contains("control") || m.contains("ctrl") { flags.insert(.maskControl) }
        let source = CGEventSource(stateID:.hidSystemState); let down = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:true); let up = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:false); down?.flags=flags; up?.flags=flags; down?.post(tap:.cghidEventTap); up?.post(tap:.cghidEventTap)
        return .init(success:true,output:"Touche envoyée: \(modifiers) \(key)")
    }

    static func clickPoint(x: Double, y: Double) -> ToolResult {
        guard isTrusted() else { return permissionError() }
        let p = CGPoint(x:x,y:y); let source = CGEventSource(stateID:.hidSystemState); CGEvent(mouseEventSource:source,mouseType:.mouseMoved,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap); usleep(80_000); CGEvent(mouseEventSource:source,mouseType:.leftMouseDown,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap); CGEvent(mouseEventSource:source,mouseType:.leftMouseUp,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
        return .init(success:true,output:"Clic effectué aux coordonnées écran x=\(Int(x)), y=\(Int(y)).")
    }

    private static func permissionError() -> ToolResult { .init(success:false, output:"Lumo n’a pas encore l’autorisation Accessibilité. Utilise accessibility_request puis active Lumo dans Réglages Système > Confidentialité et sécurité > Accessibilité.") }
    private static func findApp(_ query:String) -> NSRunningApplication? { let q=query.lowercased(); return NSWorkspace.shared.runningApplications.first { ($0.localizedName ?? "").lowercased().contains(q) || ($0.bundleIdentifier ?? "").lowercased() == q } }
    private static func attr(_ e:AXUIElement,_ name:CFString)->AnyObject? { var v:CFTypeRef?; return AXUIElementCopyAttributeValue(e,name,&v) == .success ? v as AnyObject? : nil }
    private static func text(_ e:AXUIElement,_ name:CFString)->String { attr(e,name) as? String ?? "" }
    private static func children(_ e:AXUIElement)->[AXUIElement] { attr(e,kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] }
    private static func walk(_ e:AXUIElement, depth:Int, maxDepth:Int, maxItems:Int, path:String, lines:inout [String]) { guard depth <= maxDepth, lines.count < maxItems else { return }; let role=text(e,kAXRoleAttribute as CFString); let title=text(e,kAXTitleAttribute as CFString); let value=text(e,kAXValueAttribute as CFString); let desc=text(e,kAXDescriptionAttribute as CFString); if !role.isEmpty { lines.append("[\(path)] role=\(role) title=\(title.prefix(100)) value=\(value.prefix(120)) description=\(desc.prefix(100))") }; for (i,c) in children(e).enumerated() { walk(c,depth:depth+1,maxDepth:maxDepth,maxItems:maxItems,path:"\(path).\(i)",lines:&lines); if lines.count >= maxItems { break } } }
    private static func find(_ root:AXUIElement, role:String, title:String, value:String, maxDepth:Int, maxItems:Int)->[AXUIElement] { var out:[AXUIElement]=[]; var visited=0; func visit(_ e:AXUIElement,_ depth:Int) { guard depth <= maxDepth, visited < maxItems else{return}; visited += 1; let r=text(e,kAXRoleAttribute as CFString); let t=text(e,kAXTitleAttribute as CFString); let v=text(e,kAXValueAttribute as CFString); let roleOK=role.isEmpty || r.localizedCaseInsensitiveContains(role); let titleOK=title.isEmpty || t.localizedCaseInsensitiveContains(title); let valueOK=value.isEmpty || v.localizedCaseInsensitiveContains(value); if roleOK && titleOK && valueOK { out.append(e) }; for c in children(e){visit(c,depth+1)} }; visit(root,0); return out }
}
