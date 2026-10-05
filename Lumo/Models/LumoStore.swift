import SwiftUI

@MainActor final class LumoStore: ObservableObject {
    @Published var expanded = false
    @Published var showingHistory = false
    @Published var emotion = EmotionStore.load() { didSet { EmotionStore.save(emotion) } }
    @Published var messages:[ChatMessage] = HistoryStore.load()
    @Published var isThinking = false
    @Published var pendingAction:PendingToolAction?
    @Published var actionLog:[ActionLogEntry] = ActionLogStore.load()
    @Published var lastInteraction = Date()
    @Published var animationState: LumoAnimationState = .idle
    @Published var procedureStatus: String?
    @Published var procedureEvents: [ProcedureEvent] = []
    @Published var procedureStartedAt: Date?
    @Published var procedureStepLabel: String?
    @Published var apiKeyAvailable = !(KeychainService.apiKey() ?? "").isEmpty

    let claude = ClaudeService(); let emotions = EmotionEngine()
    private var lifeTask: Task<Void,Never>?
    private var transitionTask: Task<Void,Never>?
    private var toolWasExecuted = false
    private var agentTask: Task<Void, Never>?

    init() { startLifeCycle() }
    deinit { lifeTask?.cancel(); transitionTask?.cancel() }

    var idleSeconds: TimeInterval { Date().timeIntervalSince(lastInteraction) }

    func interact() {
        let wasSleeping = animationState == .sleep
        lastInteraction = Date(); emotion = emotions.wake(from: emotion)
        if wasSleeping { setAnimation(.wakeUp) }
    }

    func submit(_ text:String) async {
        let clean=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,!isThinking else{return}
        apiKeyAvailable = !(KeychainService.apiKey() ?? "").isEmpty
        guard apiKeyAvailable else {
            NotificationCenter.default.post(name: .lumoOpenSettingsRequested, object: nil)
            return
        }
        interact(); messages.append(ChatMessage(role:.user,text:clean)); persist()
        setAnimation(.thinking)
        procedureEvents = []
        procedureStartedAt = Date()
        procedureStepLabel = "Préparation de la mission"
        agentTask = Task { [weak self] in await self?.perform() }
    }

    func approvePending() async {
        guard let a=pendingAction else{return}
        interact(); pendingAction=nil; isThinking=true; setAnimation(.working)
        let r=SystemToolRegistry.execute(name:a.name,args:a.arguments)
        toolWasExecuted = true
        do { let turn=try await claude.continueAfterConfirmation(history:messages,action:a,result:r,onAction:log); apply(turn) } catch { fail(error) }
    }

    func rejectPending(){
        guard let a=pendingAction else{return}
        interact(); log(.init(date:Date(),tool:a.name,summary:"Refusé par l’utilisateur: \(a.summary)",success:false))
        pendingAction=nil; messages.append(ChatMessage(role:.assistant,text:"Action annulée.")); persist(); isThinking=false
        setAnimation(.idle)
    }

    func oneShotFinished() {
        switch animationState {
        case .happy, .frustrated, .wakeUp: setAnimation(.idle)
        default: break
        }
    }

    private func perform() async {
        isThinking=true; toolWasExecuted=false; emotion=emotions.processing(from:emotion)
        appendProcedureEvent("Planification", "Construction du plan d’exécution…", .running)
        do {
            let turn = try await claude.run(
                history: messages,
                onAction: log,
                onProgress: { [weak self] status in
                    self?.procedureStatus = status
                    self?.procedureStepLabel = status
                },
                onEvent: { [weak self] title, detail, state, duration in
                    self?.appendProcedureEvent(title, detail, state, duration: duration)
                }
            )
            apply(turn)
        } catch is CancellationError {
            appendProcedureEvent("Mission arrêtée", "Arrêt demandé par l’utilisateur.", .failure)
            procedureStatus = "Arrêtée"; isThinking = false; setAnimation(.idle)
        } catch { fail(error) }
    }

    func stopProcedure() {
        agentTask?.cancel()
        agentTask = nil
        procedureStatus = "Arrêt en cours…"
    }

    private func appendProcedureEvent(_ title: String, _ detail: String, _ state: ProcedureEventState, duration: Double? = nil) {
        procedureEvents.append(.init(date: Date(), title: title, detail: detail, state: state, duration: duration))
        if procedureEvents.count > 120 { procedureEvents.removeFirst(procedureEvents.count - 120) }
    }

    private func apply(_ t:ClaudeTurn){
        if toolWasExecuted { appendProcedureEvent("Vérification finale", "Mission terminée et résultats reçus.", .success) }
        procedureStatus = nil
        procedureStepLabel = nil
        agentTask = nil
        if !t.text.isEmpty { messages.append(ChatMessage(role:.assistant,text:t.text)) }
        pendingAction=t.pending
        if t.pending != nil {
            setAnimation(.permission)
        } else {
            emotion=emotions.success(from:emotion); isThinking=false
            if toolWasExecuted { setAnimation(.happy) }
            else if !t.text.isEmpty { setAnimation(.talking); scheduleIdle(after: 3.5) }
            else { setAnimation(.idle) }
        }
        persist()
    }

    private func fail(_ e:Error){
        appendProcedureEvent("Erreur", e.localizedDescription, .failure)
        procedureStatus = nil
        procedureStepLabel = nil
        agentTask = nil
        messages.append(ChatMessage(role:.assistant,text:"Je n’ai pas pu terminer : \(e.localizedDescription)"))
        emotion=emotions.failure(from:emotion); isThinking=false; setAnimation(.frustrated); persist()
    }

    private func persist(){HistoryStore.save(messages)}

    private func log(_ e:ActionLogEntry){
        toolWasExecuted = true
        if animationState != .permission { setAnimation(.working) }
        actionLog.append(e); ActionLogStore.save(actionLog)
    }

    private func setAnimation(_ state: LumoAnimationState) {
        transitionTask?.cancel(); animationState = state
    }

    private func scheduleIdle(after seconds: Double) {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.pendingAction == nil else { return }
            self.animationState = .idle
        }
    }

    private func startLifeCycle(){
        lifeTask=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(4)); guard let self else{return}
                self.emotion=self.emotions.tick(from:self.emotion,idleSeconds:self.idleSeconds)
                if self.idleSeconds >= AppSettings.shared.sleepDelayMinutes * 60, !self.isThinking, self.pendingAction == nil, self.animationState == .idle {
                    self.animationState = .sleep
                }
            }
        }
    }
}
