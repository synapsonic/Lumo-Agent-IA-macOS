import Foundation

struct ClaudeTurn { let text:String; let pending:PendingToolAction? }

@MainActor
struct ClaudeService {
    enum ClaudeError: LocalizedError {
        case missingKey
        case api(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Ajoutez votre clé Anthropic dans Réglages."
            case .api(let message): return message
            case .invalidResponse: return "Claude a renvoyé une réponse inattendue. Réessayez dans quelques instants."
            }
        }
    }

    func testConnection() async throws -> String {
        guard let key = KeychainService.apiKey(), !key.isEmpty else { throw ClaudeError.missingKey }
        let model = AppSettings.shared.claudeModel
        _ = try await request(key:key, messages:[["role":"user","content":"Réponds uniquement OK."]], tools: false, maxTokens: 16)
        return "Connexion réussie — \(model.rawValue)"
    }

    func run(history:[ChatMessage], onAction:@escaping @MainActor (ActionLogEntry)->Void, onProgress:@escaping @MainActor (String)->Void = { _ in }, onEvent:@escaping @MainActor (String, String, ProcedureEventState, Double?)->Void = { _,_,_,_ in }) async throws -> ClaudeTurn {
        let anthropicKey = KeychainService.apiKey() ?? ""
        guard let goal = history.last(where: { $0.role == .user })?.text, !goal.isEmpty else {
            throw ClaudeError.invalidResponse
        }

        // v0.16: Gemini produces ONE complete executable plan. Swift executes the plan locally
        // without an LLM round-trip between deterministic actions.
        if AppSettings.shared.aiMode != .claude {
            onProgress("Planification locale…")
            onEvent("Planification", "Création d’un plan exécutable en un seul appel IA.", .running, nil)
            do {
                let actions = try await GeminiService().actionPlan(goal: goal)
                onEvent("Plan créé", "\(actions.count) action\(actions.count > 1 ? "s" : "") à exécuter localement.", .success, nil)
                return try await executeDeterministic(actions: actions, onAction: onAction, onProgress: onProgress, onEvent: onEvent)
            } catch {
                onEvent("Plan déterministe indisponible", error.localizedDescription + (AppSettings.shared.aiMode == .automatic ? " · Bascule vers Claude." : ""), .failure, nil)
                if AppSettings.shared.aiMode == .economical { throw error }
                guard !anthropicKey.isEmpty else { throw ClaudeError.missingKey }
            }
        }

        guard !anthropicKey.isEmpty else { throw ClaudeError.missingKey }
        return try await runClaudeExecutor(key: anthropicKey, history: history, goal: goal, onAction: onAction, onProgress: onProgress, onEvent: onEvent)
    }

    private func executeDeterministic(actions:[PlannedAction], onAction:@escaping @MainActor (ActionLogEntry)->Void, onProgress:@escaping @MainActor (String)->Void, onEvent:@escaping @MainActor (String, String, ProcedureEventState, Double?)->Void) async throws -> ClaudeTurn {
        var completed = Set<String>()
        var summaries:[String] = []

        for (index, action) in actions.enumerated() {
            let args = action.arguments.mapValues { AnyCodable($0) }
            let signature = action.tool + "|" + action.arguments.keys.sorted().map { "\($0)=\(action.arguments[$0] ?? "")" }.joined(separator:"|")
            if completed.contains(signature) {
                onEvent("Étape \(index + 1)/\(actions.count) · \(action.title)", "Doublon ignoré : cette action a déjà réussi.", .info, 0)
                continue
            }

            let permission = AppSettings.shared.permission(forTool: action.tool)
            if permission == .deny {
                let msg = "Action interdite par les réglages de Lumo: \(action.tool)"
                onEvent("Étape \(index + 1)/\(actions.count) · \(action.title)", msg, .failure, 0)
                return ClaudeTurn(text:msg,pending:nil)
            }
            if permission == .ask {
                return ClaudeTurn(text:"",pending:.init(name:action.tool,arguments:args,summary:SystemToolRegistry.summary(name:action.tool,args:args)))
            }

            let summary = SystemToolRegistry.summary(name:action.tool,args:args)
            onProgress("Étape \(index + 1)/\(actions.count) · \(summary)")
            onEvent("Étape \(index + 1)/\(actions.count) · \(action.title)", "\(summary)\nDémarrage…", .running, nil)
            let started = Date()
            let result: ToolResult
            if action.tool == "run_shell_command" {
                result = await Task.detached(priority:.userInitiated) { SystemToolRegistry.execute(name:action.tool,args:args) }.value
            } else {
                result = SystemToolRegistry.execute(name:action.tool,args:args)
            }
            let elapsed = Date().timeIntervalSince(started)
            onAction(.init(date:Date(),tool:action.tool,summary:result.output,success:result.success))
            onEvent("Étape \(index + 1)/\(actions.count) · \(action.title)", String(result.output.prefix(1600)), result.success ? .success : .failure, elapsed)

            guard result.success else {
                return ClaudeTurn(text:"La mission s’est arrêtée à l’étape \(index + 1)/\(actions.count) : **\(action.title)**.\n\n\(result.output)",pending:nil)
            }
            completed.insert(signature)
            summaries.append("✓ \(action.title)")
        }

        onProgress("Terminé")
        return ClaudeTurn(text:"Mission terminée.\n\n" + summaries.joined(separator:"\n"),pending:nil)
    }

    private func runClaudeExecutor(key:String, history:[ChatMessage], goal:String, onAction:@escaping @MainActor (ActionLogEntry)->Void, onProgress:@escaping @MainActor (String)->Void, onEvent:@escaping @MainActor (String, String, ProcedureEventState, Double?)->Void) async throws -> ClaudeTurn {
        var msgs:[[String:Any]] = history.suffix(8).map { ["role":$0.role.rawValue,"content":$0.text] }
        onProgress("Planification Claude…")
        let plan = try? await makePlan(key:key, goal:goal)
        if let plan {
            let count = plan.split(separator:"\n").filter { $0.range(of:#"^[0-9]+[.)]"#, options:.regularExpression) != nil }.count
            onEvent("Plan Claude créé", count > 0 ? "\(count) étapes prévues." : "Plan procédural prêt.", .success, nil)
            msgs.append(["role":"assistant", "content":"PLAN PROCÉDURAL INTERNE\n" + plan])
            msgs.append(["role":"user", "content":"Exécute ce plan. Ne répète jamais une action déjà réussie avec les mêmes arguments."])
        }

        var finalText = ""
        var successfulSignatures = Set<String>()
        var duplicateAttempts = 0
        for _ in 0..<30 {
            let root = try await request(key:key,messages:msgs)
            guard let content = root["content"] as? [[String:Any]] else { throw ClaudeError.invalidResponse }
            var toolResults:[[String:Any]] = []
            for block in content {
                if block["type"] as? String == "text", let t = block["text"] as? String { finalText += (finalText.isEmpty ? "" : "\n") + t }
                if block["type"] as? String == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                    let raw = block["input"] as? [String:Any] ?? [:]
                    let args = raw.mapValues { AnyCodable($0) }
                    let signature = name + "|" + raw.keys.sorted().map { "\($0)=\(String(describing:raw[$0]!))" }.joined(separator:"|")
                    if successfulSignatures.contains(signature) {
                        duplicateAttempts += 1
                        let message = "Action déjà exécutée avec succès avec exactement les mêmes arguments. Ne pas la répéter; poursuivre l’objectif."
                        toolResults.append(["type":"tool_result","tool_use_id":id,"content":message,"is_error":true])
                        onEvent("Doublon bloqué", SystemToolRegistry.summary(name:name,args:args), .info, 0)
                        continue
                    }
                    let permission = AppSettings.shared.permission(forTool:name)
                    if permission == .ask { return ClaudeTurn(text:finalText,pending:.init(name:name,arguments:args,summary:SystemToolRegistry.summary(name:name,args:args))) }
                    if permission == .deny {
                        let message = "Action interdite par les réglages de Lumo: \(name)"
                        onAction(.init(date:Date(),tool:name,summary:message,success:false))
                        toolResults.append(["type":"tool_result","tool_use_id":id,"content":message,"is_error":true]); continue
                    }
                    let summary = SystemToolRegistry.summary(name:name,args:args)
                    onProgress(summary); onEvent(summary,"Démarrage de l’action…",.running,nil)
                    let started = Date()
                    let r: ToolResult
                    if name == "run_shell_command" {
                        r = await Task.detached(priority:.userInitiated) { SystemToolRegistry.execute(name:name,args:args) }.value
                    } else {
                        r = SystemToolRegistry.execute(name:name,args:args)
                    }
                    let elapsed = Date().timeIntervalSince(started)
                    onEvent(summary,String(r.output.prefix(1200)),r.success ? .success : .failure,elapsed)
                    onAction(.init(date:Date(),tool:name,summary:r.output,success:r.success))
                    if r.success { successfulSignatures.insert(signature) }
                    toolResults.append(["type":"tool_result","tool_use_id":id,"content":r.output,"is_error":!r.success])
                }
            }
            guard !toolResults.isEmpty else { return ClaudeTurn(text:finalText,pending:nil) }
            if duplicateAttempts >= 3 {
                return ClaudeTurn(text:"J’ai détecté une boucle d’actions identiques et l’ai interrompue automatiquement pour éviter des appels IA inutiles.",pending:nil)
            }
            msgs.append(["role":"assistant","content":sanitizeContentBlocks(content)])
            msgs.append(["role":"user","content":sanitizeToolResults(toolResults)])
            finalText = ""
        }
        return ClaudeTurn(text:finalText.isEmpty ? "La mission a été interrompue après 30 tours Claude afin d’éviter une consommation anormale." : finalText,pending:nil)
    }

    func continueAfterConfirmation(history:[ChatMessage],action:PendingToolAction,result:ToolResult,onAction:@escaping @MainActor(ActionLogEntry)->Void) async throws -> ClaudeTurn {
        onAction(.init(date:Date(),tool:action.name,summary:result.output,success:result.success))
        var h = history; h.append(ChatMessage(role:.assistant,text:"Action système \(action.name): \(result.output)"))
        return try await run(history:h,onAction:onAction)
    }

    private func makePlan(key: String, goal: String) async throws -> String {
        let prompt = """
        Objectif utilisateur : \(goal)

        Établis un plan d'exécution concret, court et ordonné pour un agent macOS autonome.
        Chaque ligne doit être une étape vérifiable. Pour une tâche de programmation, prévois : inspection du workspace, création/modification des fichiers avec les outils fichiers, installation/commandes seulement si nécessaire, exécution des tests, correction des erreurs et vérification finale.
        N'exécute rien ici. Réponds uniquement avec une checklist numérotée, sans préambule.
        """
        let root = try await request(key:key, messages:[["role":"user","content":prompt]], tools:false, maxTokens:900)
        guard let content = root["content"] as? [[String:Any]] else { throw ClaudeError.invalidResponse }
        return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
    }

    private func request(key:String,messages:[[String:Any]], tools:Bool = true, maxTokens:Int = 850) async throws -> [String:Any] {
        let url = URL(string:"https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url:url); req.httpMethod = "POST"
        req.setValue(key,forHTTPHeaderField:"x-api-key"); req.setValue("2023-06-01",forHTTPHeaderField:"anthropic-version"); req.setValue("application/json",forHTTPHeaderField:"content-type")
        var body:[String:Any] = [
            "model": AppSettings.shared.claudeModel.apiID,
            "max_tokens": maxTokens,
            "system":"Tu es Lumo, un agent macOS local autonome en MODE PROCÉDURAL. Une demande utilisateur est un OBJECTIF, pas une action unique. Quand un PLAN PROCÉDURAL INTERNE est présent, exécute toutes ses étapes dans l’ordre et ne rends une réponse finale qu’après vérification du résultat. Après chaque tool_result, décide immédiatement de l’étape suivante. Si une étape échoue, inspecte l’erreur, corrige et reteste. Pour créer ou modifier du code, utilise en priorité write_text_file, append_text_file et replace_text_in_file; n’utilise pas Terminal pour simuler l’écriture de fichiers. Utilise read_text_file/file_info/file_exists pour vérifier réellement ce qui a été écrit. Pour les commandes, tests, compilations et gestionnaires de paquets, utilise run_shell_command. Pour l’interface graphique, applique observer → agir → vérifier avec ui_snapshot. N’abandonne jamais après une seule action si l’objectif comporte plusieurs étapes. Ne prétends jamais avoir effectué une action sans résultat d’outil. Les mots de passe, Touch ID et 2FA restent saisis par l’utilisateur. Respecte les permissions macOS et celles de Lumo. Sois concis et réponds en français.",
            "messages": sanitizeMessages(messages)
        ]
        if tools { body["tools"] = SystemToolRegistry.definitions }
        req.httpBody = try JSONSerialization.data(withJSONObject:body)
        let (data,response) = try await URLSession.shared.data(for:req)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw parseAPIError(data:data,status:http.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw ClaudeError.invalidResponse }
        return root
    }

    /// Anthropic requires the final text block of assistant content not to end in whitespace.
    /// We normalize *all* outgoing conversational strings so a tool loop can never
    /// re-submit an invalid assistant message. Tool inputs are intentionally untouched.
    private func cleanText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeContentBlocks(_ blocks: [[String:Any]]) -> [[String:Any]] {
        blocks.compactMap { original in
            var block = original
            if block["type"] as? String == "text", let text = block["text"] as? String {
                let cleaned = cleanText(text)
                if cleaned.isEmpty { return nil }
                block["text"] = cleaned
            }
            return block
        }
    }

    private func sanitizeToolResults(_ blocks: [[String:Any]]) -> [[String:Any]] {
        blocks.map { original in
            var block = original
            if let content = block["content"] as? String { block["content"] = cleanText(content) }
            return block
        }
    }

    private func sanitizeMessages(_ messages: [[String:Any]]) -> [[String:Any]] {
        messages.compactMap { original in
            var message = original
            if let text = message["content"] as? String {
                let cleaned = cleanText(text)
                if cleaned.isEmpty { return nil }
                message["content"] = cleaned
            } else if let blocks = message["content"] as? [[String:Any]] {
                let cleaned: [[String:Any]]
                if message["role"] as? String == "assistant" { cleaned = sanitizeContentBlocks(blocks) }
                else { cleaned = sanitizeToolResults(blocks) }
                if cleaned.isEmpty { return nil }
                message["content"] = cleaned
            }
            return message
        }
    }

    private func parseAPIError(data:Data,status:Int) -> ClaudeError {
        if let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
           let error = root["error"] as? [String:Any], let message = error["message"] as? String {
            if status == 401 { return .api("Clé Anthropic invalide. Vérifiez-la dans Réglages.") }
            if status == 429 { return .api("Limite Anthropic atteinte. Réessayez dans quelques instants.") }
            if message.localizedCaseInsensitiveContains("model") { return .api("Le modèle Claude sélectionné n’est pas disponible pour cette clé. Changez-le dans Réglages.") }
            return .api("Anthropic : \(message)")
        }
        return .api("Erreur Anthropic (HTTP \(status)).")
    }
}
