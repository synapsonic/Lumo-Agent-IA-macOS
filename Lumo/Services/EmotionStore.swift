import Foundation

enum EmotionStore {
    private static let key = "lumo.emotionalState.v1"
    static func load() -> EmotionalState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(EmotionalState.self, from: data) else { return EmotionalState() }
        return state
    }
    static func save(_ state: EmotionalState) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key) }
    }
}
