import SwiftUI
import AppKit

struct FloatingRootView: View {
    @EnvironmentObject var store: LumoStore
    @ObservedObject private var settings = AppSettings.shared

    private var horizontalAlignment: HorizontalAlignment { settings.panelGrowsRight ? .leading : .trailing }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 8) {
            if settings.panelGrowsDown {
                lumo
                if store.expanded { commandPanel }
            } else {
                if store.expanded { commandPanel }
                lumo
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: Alignment(horizontal: settings.panelGrowsRight ? .leading : .trailing,
                                    vertical: settings.panelGrowsDown ? .top : .bottom))
    }

    private var commandPanel: some View {
        CommandPanel()
    }

    private var lumo: some View {
        LumoVideoView(state: store.animationState, onOneShotFinished: store.oneShotFinished)
            .frame(width: 190 * settings.characterScale, height: 205 * settings.characterScale)
            .contentShape(Rectangle())
            .onTapGesture {
                store.interact()
                // Do not animate the SwiftUI hierarchy while AppKit resizes the host window.
                // The character stays anchored; only the surrounding NSPanel changes size.
                store.expanded.toggle()
                store.showingHistory = false
                if store.expanded { NotificationCenter.default.post(name: .lumoRequestKeyboardFocus, object: nil) }
            }
            .onHover { if $0 { store.interact() } }
            .accessibilityLabel("Lumo")
            .accessibilityHint("Cliquez pour ouvrir ou fermer le panneau de commande")
    }
}
