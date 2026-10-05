import Foundation

enum LumoAnimationState: String, CaseIterable {
    case idle = "Lumo_Idle"
    case thinking = "Lumo_Thinking"
    case talking = "Lumo_Talking"
    case working = "Lumo_Working"
    case happy = "Lumo_Happy"
    case permission = "Lumo_Permission"
    case frustrated = "Lumo_Frustrated"
    case sleep = "Lumo_Sleep"
    case wakeUp = "Lumo_WakeUp"

    var loops: Bool {
        switch self {
        case .idle, .thinking, .talking, .working, .permission, .sleep: return true
        case .happy, .frustrated, .wakeUp: return false
        }
    }
}

struct EmotionEngine {
    func processing(from s: EmotionalState) -> EmotionalState { var x=s; x.curiosity=min(1,x.curiosity+0.06); x.energy=max(0,x.energy-0.02); return x }
    func success(from s: EmotionalState) -> EmotionalState { var x=s; x.happiness=min(1,x.happiness+0.08); x.confidence=min(1,x.confidence+0.05); x.stress=max(0,x.stress-0.04); x.affinity=min(1,x.affinity+0.01); return x }
    func failure(from s: EmotionalState) -> EmotionalState { var x=s; x.happiness=max(0,x.happiness-0.08); x.confidence=max(0,x.confidence-0.06); x.stress=min(1,x.stress+0.12); return x }
    func tick(from s: EmotionalState, idleSeconds: TimeInterval) -> EmotionalState { var x=s; if idleSeconds > 25 { x.energy=max(0.08,x.energy-0.018); x.stress=max(0,x.stress-0.01) } else { x.energy=min(1,x.energy+0.004) }; x.curiosity += (0.62-x.curiosity)*0.01; x.happiness += (0.68-x.happiness)*0.006; return x }
    func wake(from s: EmotionalState) -> EmotionalState { var x=s; x.energy=min(1,x.energy+0.12); x.curiosity=min(1,x.curiosity+0.08); return x }
}
