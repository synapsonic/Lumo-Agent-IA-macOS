import Foundation

enum HistoryStore {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Lumo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
    static func load() -> [ChatMessage] {
        guard let d = try? Data(contentsOf:url) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from:d)) ?? []
    }
    static func save(_ value:[ChatMessage]) { if let d = try? JSONEncoder().encode(value) { try? d.write(to:url, options:.atomic) } }
}
