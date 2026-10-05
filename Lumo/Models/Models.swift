import Foundation

struct EmotionalState: Codable { var happiness = 0.72; var energy = 0.75; var curiosity = 0.82; var confidence = 0.70; var stress = 0.08; var affinity = 0.50 }
enum ChatRole:String,Codable { case user,assistant }
struct ChatMessage:Identifiable,Codable { var id = UUID(); let role:ChatRole; let text:String; var date = Date() }

enum ToolRisk:String,Codable { case safe, confirmation }
struct PendingToolAction:Identifiable { let id = UUID(); let name:String; let arguments:[String:AnyCodable]; let summary:String }
struct ActionLogEntry:Identifiable,Codable { var id = UUID(); let date:Date; let tool:String; let summary:String; let success:Bool }

struct AnyCodable: Codable {
    let value: Any
    init(_ value:Any){ self.value = value }
    init(from decoder:Decoder)throws { let c = try decoder.singleValueContainer(); if let v = try? c.decode(String.self){value = v}else if let v = try? c.decode(Bool.self){value = v}else if let v = try? c.decode(Double.self){value = v}else{value = ""} }
    func encode(to encoder:Encoder)throws { var c = encoder.singleValueContainer(); if let v = value as? String{try c.encode(v)}else if let v = value as? Bool{try c.encode(v)}else if let v = value as? Double{try c.encode(v)}else{try c.encode(String(describing:value))} }
    var string:String? { value as? String }
}


enum ProcedureEventState: String, Codable { case running, success, failure, info }
struct ProcedureEvent: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let title: String
    let detail: String
    let state: ProcedureEventState
    let duration: Double?
}
