import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LumoStore()
    private var controller: FloatingLumoController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = FloatingLumoController(store: store)
        controller?.show()
        installMenuBarItem()
        observers.append(NotificationCenter.default.addObserver(forName: .lumoOpenSettingsRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showSettings() }
        })
        if AppSettings.shared.launchAtLogin { Task { try? await AutoLaunchService.shared.setEnabled(true) } }
        if !store.apiKeyAvailable { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.showAPIKeySetup() } }
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "✦ Lumo"
        let menu = NSMenu()
        menu.addItem(withTitle: "Afficher / cacher Lumo", action: #selector(toggleLumo), keyEquivalent: "l")
        menu.addItem(withTitle: "Historique", action: #selector(showHistory), keyEquivalent: "h")
        menu.addItem(withTitle: "Réglages…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Lumo", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func showAPIKeySetup() {
        let alert = NSAlert()
        alert.messageText = "Connecter Lumo à Claude"
        alert.informativeText = "Ajoutez votre clé API Anthropic pour que Lumo puisse comprendre vos demandes et utiliser ses outils macOS. La clé sera stockée dans le Trousseau macOS."
        alert.addButton(withTitle: "Ajouter la clé API")
        alert.addButton(withTitle: "Plus tard")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { showSettings() }
    }

    @objc private func toggleLumo() { controller?.toggleVisibility() }
    @objc private func showHistory() { controller?.showAndExpand(history: true) }
    @objc private func showSettings() {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = SettingsView().environmentObject(store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Réglages Lumo"
        window.contentView = NSHostingView(rootView: view)
        window.center(); window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
