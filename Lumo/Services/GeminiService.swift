import Foundation

struct PlannedAction: Codable {
    let id: Int
    let title: String
    let tool: String
    let arguments: [String:String]
}

@MainActor
struct GeminiService {
    enum GeminiError: LocalizedError {
        case missingKey, invalidResponse, api(String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Ajoutez votre clé Gemini dans Réglages."
            case .invalidResponse: return "Gemini a renvoyé une réponse inattendue."
            case .api(let message): return message
            }
        }
    }

    func testConnection() async throws -> String {
        _ = try await generate("Réponds uniquement OK.", maxOutputTokens: 16)
        return "Connexion réussie — Gemini 2.5 Flash-Lite"
    }

    /// Legacy human-readable plan, kept for Claude-only fallback/UI compatibility.
    func plan(goal: String) async throws -> String {
        let actions = try await actionPlan(goal: goal)
        return actions.map { "\($0.id). \($0.title) — \($0.tool)" }.joined(separator: "\n")
    }

    /// One LLM call produces the complete executable plan. Swift then executes it locally.
    /// Arguments are strings because every SystemToolRegistry input is string-shaped today.
    func actionPlan(goal: String) async throws -> [PlannedAction] {
        let allowed = SystemToolRegistry.toolNames.joined(separator: ", ")
        let prompt = """
        Tu es le planificateur/exécuteur de Lumo, agent macOS. Transforme l'objectif en une liste JSON d'actions DIRECTEMENT EXÉCUTABLES localement, sans commentaire hors JSON.

        OBJECTIF UTILISATEUR:
        \(goal)

        OUTILS AUTORISÉS:
        \(allowed)

        FORMAT STRICT:
        {"actions":[{"id":1,"title":"description courte","tool":"nom_outil","arguments":{"cle":"valeur"}}]}

        RÈGLES:
        - Retourne uniquement du JSON valide, sans markdown.
        - Chaque action doit être nécessaire. Évite les micro-étapes et les doublons.
        - Pour créer un fichier, utilise write_text_file UNE SEULE FOIS avec le CONTENU COMPLET dans arguments.content.
        - Le contenu demandé par l'utilisateur doit être réellement généré dans arguments.content, jamais remplacé par un placeholder.
        - Pour modifier un fichier existant, lis-le d'abord si son contenu est nécessaire.
        - Après write_text_file, inutile d'ajouter file_exists: Lumo vérifie automatiquement l'écriture, la taille et le contenu.
        - Ajoute open_item à la fin seulement si l'objectif implique naturellement de montrer/ouvrir le résultat.
        - Terminal est réservé aux commandes, builds, tests, git et installations; jamais pour écrire un fichier si write_text_file suffit.
        - N'utilise que les outils listés ci-dessus.
        - Pour ~/Desktop, ~/Downloads, etc., conserve la notation ~.
        - Maximum 20 actions. Une tâche simple doit généralement tenir en 1 à 4 actions.
        """
        let text = try await generate(prompt, maxOutputTokens: 8192, responseMIMEType: "application/json")
        guard let data = text.data(using: .utf8) else { throw GeminiError.invalidResponse }
        struct Envelope: Codable { let actions: [PlannedAction] }
        guard let decoded = try? JSONDecoder().decode(Envelope.self, from: data), !decoded.actions.isEmpty else { throw GeminiError.invalidResponse }
        let known = Set(SystemToolRegistry.toolNames)
        guard decoded.actions.count <= 20, decoded.actions.allSatisfy({ known.contains($0.tool) }) else { throw GeminiError.invalidResponse }
        return decoded.actions
    }

    private func generate(_ prompt: String, maxOutputTokens: Int, responseMIMEType: String? = nil) async throws -> String {
        guard let key = KeychainService.geminiAPIKey(), !key.isEmpty else { throw GeminiError.missingKey }
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=\(escaped)") else { throw GeminiError.invalidResponse }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "content-type")
        var config: [String:Any] = ["maxOutputTokens": maxOutputTokens, "temperature": 0.1]
        if let responseMIMEType { config["responseMimeType"] = responseMIMEType }
        let body: [String:Any] = [
            "contents": [["role":"user", "parts":[["text":prompt]]]],
            "generationConfig": config
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any]
            let err = root?["error"] as? [String:Any]
            throw GeminiError.api((err?["message"] as? String) ?? "Erreur Gemini HTTP \(http.statusCode)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              let candidates = root["candidates"] as? [[String:Any]], let first = candidates.first,
              let content = first["content"] as? [String:Any], let parts = content["parts"] as? [[String:Any]] else { throw GeminiError.invalidResponse }
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GeminiError.invalidResponse }
        return text
    }
}
