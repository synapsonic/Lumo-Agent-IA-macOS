import SwiftUI

struct CommandPanel: View {
    @EnvironmentObject var store: LumoStore
    @State private var input = ""
    @FocusState private var commandFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            content
            composer
            footer
        }
        .frame(width: 420, height: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onAppear { focusCommandFieldIfNeeded() }
        .onChange(of: store.showingHistory) { _, showingHistory in
            if !showingHistory { focusCommandFieldIfNeeded() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(.cyan.opacity(0.14)).frame(width: 30, height: 30)
                Image(systemName: store.showingHistory ? "clock.arrow.circlepath" : "sparkles")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.showingHistory ? "Historique" : "Lumo").font(.system(size: 15, weight: .semibold))
                if !store.showingHistory {
                    Text(store.isThinking ? (store.procedureStatus ?? "Planification…") : "Assistant local")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.showingHistory {
                Button { store.showingHistory = false } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28)
                }.buttonStyle(.plain).help("Retour")
            }
            Button { store.expanded = false } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28)
            }.buttonStyle(.plain).help("Fermer")
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
    }

    @ViewBuilder private var content: some View {
        if store.showingHistory {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        messageBubble(message)
                    }
                }.padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let action = store.pendingAction { permissionCard(action) }
                    else if store.isThinking { procedureMonitor }
                    else if let last = store.messages.last { assistantResponse(last.text) }
                    else { welcome }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }


    private var procedureMonitor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.procedureStepLabel ?? "Mission en cours")
                        .font(.system(size: 14, weight: .semibold))
                    if let start = store.procedureStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("En cours depuis \(Int(context.date.timeIntervalSince(start))) s")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button { store.stopProcedure() } label: {
                    Label("Arrêter", systemImage: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(BorderedButtonStyle())
            }

            if store.procedureEvents.isEmpty {
                Text("Préparation des prochaines actions…")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(store.procedureEvents.suffix(30)) { event in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: eventIcon(event.state))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(eventColor(event.state))
                                .frame(width: 14, height: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(event.title).font(.system(size: 12.5, weight: .semibold))
                                    Spacer()
                                    if let d = event.duration {
                                        Text(String(format: "%.1fs", d)).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                                    }
                                }
                                if !event.detail.isEmpty {
                                    Text(event.detail)
                                        .font(.system(size: 11.5, design: event.title.contains("Exécuter") ? .monospaced : .default))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(5)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func eventIcon(_ state: ProcedureEventState) -> String {
        switch state { case .running: return "circle.dotted"; case .success: return "checkmark.circle.fill"; case .failure: return "exclamationmark.triangle.fill"; case .info: return "info.circle.fill" }
    }

    private func eventColor(_ state: ProcedureEventState) -> Color {
        switch state { case .running: return .cyan; case .success: return .green; case .failure: return .orange; case .info: return .secondary }
    }

    private func assistantResponse(_ source: String) -> some View {
        MarkdownDocumentView(source: source, fontSize: 14.5)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 5) {
                Text(message.role == .user ? "Vous" : "Lumo")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                MarkdownDocumentView(source: message.text, fontSize: 13)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(message.role == .user ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 42) }
        }
    }

    private func markdownText(_ source: String) -> Text {
        if let attributed = try? AttributedString(markdown: source,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)) {
            return Text(attributed)
        }
        return Text(source)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Que puis-je faire pour toi ?").font(.system(size: 17, weight: .semibold))
            Text("Demande-moi d’ouvrir une app, retrouver un fichier ou effectuer une action sur ton Mac.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(2)
        }
    }

    private func permissionCard(_ action: PendingToolAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Autorisation requise", systemImage: "lock.shield")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            Text(action.summary).font(.system(size: 13)).foregroundStyle(.secondary)
            HStack {
                Button("Refuser") { store.rejectPending() }.buttonStyle(BorderedButtonStyle())
                Button("Autoriser") { Task { await store.approvePending() } }.buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .padding(13)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var composer: some View {
        HStack(spacing: 9) {
            TextField(store.isThinking ? "Mission en cours…" : "Demande quelque chose à Lumo…", text: $input)
                .textFieldStyle(.plain).font(.system(size: 13.5))
                .focused($commandFieldFocused).onSubmit { send() }
            if store.isThinking { ProgressView().controlSize(.small) }
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.white)
                    .frame(width: 29, height: 29)
                    .background(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.07) : Color.accentColor,
                                in: Circle())
            }
            .buttonStyle(.plain).disabled(store.isThinking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.leading, 14).padding(.trailing, 7).padding(.vertical, 7)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(commandFieldFocused ? 0.20 : 0.08)))
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            Button { store.showingHistory.toggle(); commandFieldFocused = false } label: {
                Label("Historique", systemImage: "clock.arrow.circlepath").font(.system(size: 11.5, weight: .medium))
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            Text("↩︎ envoyer").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 18).padding(.vertical, 11)
    }

    private func focusCommandFieldIfNeeded() {
        guard !store.showingHistory else { return }
        DispatchQueue.main.async { commandFieldFocused = true }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.isThinking else { return }
        input = ""
        Task { await store.submit(text) }
    }
}
