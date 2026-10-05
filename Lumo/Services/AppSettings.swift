import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku45 = "Haiku 4.5 — économique"
    case sonnet55 = "Sonnet 5.5 — avancé"
    var id: String { rawValue }
    var apiID: String {
        switch self {
        case .haiku45: return "claude-haiku-4-5-20251001"
        case .sonnet55: return "claude-sonnet-5-5"
        }
    }
}

enum AIMode: String, CaseIterable, Identifiable {
    case economical = "Économique — Gemini"
    case automatic = "Automatique — Gemini + Claude"
    case claude = "Claude uniquement"
    var id: String { rawValue }
}

enum ToolPermission: String, CaseIterable, Identifiable {
    case allow = "Toujours autoriser"
    case ask = "Demander"
    case deny = "Interdire"
    var id: String { rawValue }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var aiMode: AIMode { didSet { defaults.set(aiMode.rawValue, forKey: "aiMode") } }
    @Published var claudeModel: ClaudeModel { didSet { defaults.set(claudeModel.rawValue, forKey: "claudeModel") } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var sleepDelayMinutes: Double { didSet { defaults.set(sleepDelayMinutes, forKey: "sleepDelayMinutes") } }
    @Published var characterScale: Double { didSet { defaults.set(characterScale, forKey: "characterScale") } }
    @Published var positionX: Double { didSet { defaults.set(positionX, forKey: "positionX") } }
    @Published var positionY: Double { didSet { defaults.set(positionY, forKey: "positionY") } }
    @Published var positionSaved: Bool { didSet { defaults.set(positionSaved, forKey: "positionSaved") } }
    @Published var toolPermissions: [String:String] { didSet { defaults.set(toolPermissions, forKey: "toolPermissions") } }
    @Published var panelGrowsRight: Bool { didSet { defaults.set(panelGrowsRight, forKey: "panelGrowsRight") } }
    @Published var panelGrowsDown: Bool { didSet { defaults.set(panelGrowsDown, forKey: "panelGrowsDown") } }

    private init() {
        aiMode = AIMode(rawValue: defaults.string(forKey: "aiMode") ?? "") ?? .automatic
        claudeModel = ClaudeModel(rawValue: defaults.string(forKey: "claudeModel") ?? "") ?? .haiku45
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? true
        sleepDelayMinutes = defaults.object(forKey: "sleepDelayMinutes") as? Double ?? 5
        characterScale = defaults.object(forKey: "characterScale") as? Double ?? 1
        positionX = defaults.object(forKey: "positionX") as? Double ?? 0
        positionY = defaults.object(forKey: "positionY") as? Double ?? 0
        positionSaved = defaults.object(forKey: "positionSaved") as? Bool ?? false
        toolPermissions = defaults.dictionary(forKey: "toolPermissions") as? [String:String] ?? [:]
        panelGrowsRight = defaults.object(forKey: "panelGrowsRight") as? Bool ?? false
        panelGrowsDown = defaults.object(forKey: "panelGrowsDown") as? Bool ?? false
    }

    func permission(forTool name: String) -> ToolPermission {
        if let raw = toolPermissions[name], let value = ToolPermission(rawValue: raw) { return value }
        return SystemToolRegistry.risk(for: name) == .confirmation ? .ask : .allow
    }

    func setPermission(_ permission: ToolPermission, forTool name: String) {
        toolPermissions[name] = permission.rawValue
    }

    func setAllToolPermissions(_ permission: ToolPermission) {
        var updated = toolPermissions
        for name in SystemToolRegistry.toolNames { updated[name] = permission.rawValue }
        toolPermissions = updated
    }

    func resetToolPermissions() { toolPermissions = [:] }

    func savePosition(x: Double, y: Double) {
        positionX = x; positionY = y; positionSaved = true
    }
}
