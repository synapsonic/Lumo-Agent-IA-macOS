import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: LumoStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var key = ""
    @State private var geminiKey = ""
    @State private var geminiStatus = ""
    @State private var testingGemini = false
    @State private var saved = false
    @State private var connectionStatus = ""
    @State private var testingConnection = false
    @State private var accessibilityGranted = AccessibilityController.isTrusted()

    private let tools: [(String,String)] = [
        ("open_application", "Ouvrir des applications"), ("open_url", "Ouvrir des liens"), ("open_item", "Ouvrir fichiers / dossiers"),
        ("list_directory", "Lister les dossiers et dates"), ("file_info", "Lire les métadonnées"), ("search_files", "Rechercher des fichiers"),
        ("read_text_file", "Lire des fichiers texte"), ("write_text_file", "Créer / remplacer des fichiers"), ("append_text_file", "Ajouter du contenu aux fichiers"),
        ("create_directory", "Créer des dossiers"), ("move_item", "Déplacer / renommer"), ("copy_item", "Copier fichiers / dossiers"), ("delete_item", "Supprimer fichiers / dossiers"),
        ("get_clipboard", "Lire le presse-papiers"), ("set_clipboard", "Modifier le presse-papiers"),
        ("system_info", "Lire les informations système"), ("list_processes", "Voir les applications ouvertes"),
        ("run_shell_command", "Exécuter des commandes Terminal"), ("run_applescript", "Automatiser macOS / applications"),
        ("accessibility_status", "Vérifier l’accès Accessibilité"), ("accessibility_request", "Demander l’accès Accessibilité"),
        ("ui_snapshot", "Observer l’interface des applications"), ("ui_focus_app", "Mettre une application au premier plan"),
        ("ui_click", "Cliquer sur les contrôles d’une application"), ("ui_set_value", "Remplir les champs d’une application"),
        ("ui_type_text", "Saisir du texte au clavier"), ("ui_key", "Utiliser les raccourcis clavier"), ("ui_click_point", "Cliquer par coordonnées (secours)")
    ]

    var body: some View {
        TabView {
            Form {
                Section("Mode IA") {
                    Picker("Mode", selection: $settings.aiMode) {
                        ForEach(AIMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    Text(settings.aiMode == .automatic ? "Recommandé : Gemini planifie à très faible coût ; Claude exécute les outils et sert de fallback." : (settings.aiMode == .economical ? "Gemini planifie les missions. Claude reste utilisé pour l'exécution outillée afin de conserver toutes les capacités macOS." : "Claude assure planification et exécution."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Google Gemini — planificateur économique") {
                    SecureField("Clé API Gemini", text: $geminiKey).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Enregistrer") { KeychainService.saveGeminiAPIKey(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button(testingGemini ? "Test en cours…" : "Tester Gemini") {
                            testingGemini = true; geminiStatus = ""
                            Task { do { geminiStatus = try await GeminiService().testConnection() } catch { geminiStatus = error.localizedDescription }; testingGemini = false }
                        }.disabled(testingGemini || (KeychainService.geminiAPIKey() ?? "").isEmpty)
                        if !geminiStatus.isEmpty { Text(geminiStatus).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text("Gemini 2.5 Flash-Lite est utilisé pour construire les plans procéduraux en modes Économique et Automatique.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Anthropic / Claude — exécution outillée") {
                    SecureField("Clé API Anthropic", text: $key).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Enregistrer") {
                            KeychainService.saveAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines)); saved = true
                            store.apiKeyAvailable = !(KeychainService.apiKey() ?? "").isEmpty
                        }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if saved { Label("Enregistrée", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    Picker("Modèle d'exécution", selection: $settings.claudeModel) {
                        ForEach(ClaudeModel.allCases) { model in Text(model.rawValue).tag(model) }
                    }
                    HStack {
                        Button(testingConnection ? "Test en cours…" : "Tester Claude") {
                            testingConnection = true; connectionStatus = ""
                            Task { do { connectionStatus = try await ClaudeService().testConnection() } catch { connectionStatus = error.localizedDescription }; testingConnection = false }
                        }.disabled(testingConnection || (KeychainService.apiKey() ?? "").isEmpty)
                        if !connectionStatus.isEmpty { Text(connectionStatus).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text("Les deux clés restent dans le Trousseau macOS. Lumo n'enregistre aucun secret dans le projet.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).tabItem { Label("IA", systemImage: "brain") }

            Form {
                Section("Taille") {
                    HStack {
                        Slider(value: $settings.characterScale, in: 0.6...1.5, step: 0.05)
                        Text("\(Int(settings.characterScale * 100)) %").monospacedDigit().frame(width: 52)
                        Button("100 %") { settings.characterScale = 1 }
                    }
                    Text("La taille est enregistrée automatiquement.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Emplacement à l'écran") {
                    HStack {
                        Button("↖︎ Haut gauche") { move("topLeft") }
                        Button("↗︎ Haut droite") { move("topRight") }
                        Button("↙︎ Bas gauche") { move("bottomLeft") }
                        Button("↘︎ Bas droite") { move("bottomRight") }
                        Button("Centre") { move("center") }
                    }
                    HStack {
                        Text("X"); TextField("X", value: $settings.positionX, format: .number).frame(width: 90)
                        Text("Y"); TextField("Y", value: $settings.positionY, format: .number).frame(width: 90)
                        Button("Appliquer") { settings.positionSaved = true; NotificationCenter.default.post(name: .lumoCoordinatesRequested, object: nil) }
                    }
                    Text("Vous pouvez aussi déplacer Lumo directement à la souris. Sa position est mémorisée automatiquement, y compris après redémarrage.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Affichage") {
                    Toggle("Toujours au-dessus des autres fenêtres", isOn: $settings.alwaysOnTop)
                        .onChange(of: settings.alwaysOnTop) { _, _ in NotificationCenter.default.post(name: .lumoAlwaysOnTopChanged, object: nil) }
                    HStack {
                        Text("Mise en veille après")
                        Slider(value: $settings.sleepDelayMinutes, in: 1...30, step: 1)
                        Text("\(Int(settings.sleepDelayMinutes)) min").monospacedDigit().frame(width: 55)
                    }
                    Button("Cacher Lumo maintenant") { NotificationCenter.default.post(name: .lumoHideRequested, object: nil) }
                }
            }.padding(20).tabItem { Label("Apparence", systemImage: "sparkles") }

            Form {
                Section("Contrôle de l’interface macOS") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accessibilityGranted ? "Accessibilité autorisée" : "Autorisation Accessibilité requise").font(.headline)
                            Text("Cette autorisation permet à Lumo d’observer les boutons, champs et fenêtres, puis de cliquer et saisir du texte dans les applications.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if accessibilityGranted {
                            Button("Vérifier") {
                                _ = AccessibilityController.isTrusted(prompt: false)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    accessibilityGranted = AccessibilityController.isTrusted()
                                }
                            }
                            .buttonStyle(BorderedButtonStyle())
                        } else {
                            Button("Autoriser…") {
                                _ = AccessibilityController.isTrusted(prompt: true)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    accessibilityGranted = AccessibilityController.isTrusted()
                                }
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                }
                Section("Mode Superpowers") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Autoriser tous les outils").font(.headline)
                            Text("Supprime les confirmations internes de Lumo. Les protections natives de macOS restent applicables.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Tout autoriser") { settings.setAllToolPermissions(.allow) }
                            .buttonStyle(BorderedProminentButtonStyle())
                        Button("Réinitialiser") { settings.resetToolPermissions() }
                    }
                }
                Section("Permissions des outils") {
                    ForEach(tools, id: \.0) { tool in
                        HStack {
                            Text(tool.1)
                            Spacer()
                            Picker("", selection: permissionBinding(tool.0)) {
                                ForEach(ToolPermission.allCases) { permission in Text(permission.rawValue).tag(permission) }
                            }.labelsHidden().frame(width: 175)
                        }
                    }
                    Text("Les outils de lecture sont autorisés par défaut. Les écritures, suppressions, Terminal et AppleScript demandent confirmation par défaut. Vous pouvez choisir Toujours autoriser pour un fonctionnement autonome. Les protections macOS (TCC, mot de passe administrateur, permissions système) restent applicables.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).tabItem { Label("Permissions", systemImage: "hand.raised.fill") }

            Form {
                Section("Démarrage") {
                    Toggle("Ouvrir Lumo à la connexion", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, enabled in Task { try? await AutoLaunchService.shared.setEnabled(enabled) } }
                    Text("Même lorsque Lumo est caché, vous pouvez le retrouver depuis la barre des menus.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).tabItem { Label("Général", systemImage: "gearshape") }
        }
        .frame(width: 680, height: 480)
        .onAppear { key = KeychainService.apiKey() ?? ""; geminiKey = KeychainService.geminiAPIKey() ?? "" }
    }

    private func move(_ preset: String) { NotificationCenter.default.post(name: .lumoPositionRequested, object: preset) }
    private func permissionBinding(_ tool: String) -> Binding<ToolPermission> {
        Binding(get: { settings.permission(forTool: tool) }, set: { settings.setPermission($0, forTool: tool) })
    }
}
