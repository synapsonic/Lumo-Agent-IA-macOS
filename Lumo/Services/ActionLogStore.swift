import Foundation
enum ActionLogStore {
    static var url:URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Lumo/actions.json") }
    static func load()->[ActionLogEntry] { guard let d = try? Data(contentsOf:url) else{return []}; return (try? JSONDecoder().decode([ActionLogEntry].self,from:d)) ?? [] }
    static func save(_ v:[ActionLogEntry]) { try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); if let d = try? JSONEncoder().encode(v){try? d.write(to:url,options:.atomic)} }
}
