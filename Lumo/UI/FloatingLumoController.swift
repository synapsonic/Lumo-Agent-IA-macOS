import AppKit
import SwiftUI
import Combine

final class LumoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class FloatingLumoController {
    private let store: LumoStore
    private let panel: LumoPanel
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var frameUpdateScheduled = false
    private var isApplyingFrame = false

    private let baseCharacterSize = NSSize(width: 190, height: 205)
    private let panelSize = NSSize(width: 390, height: 410)
    private let padding: CGFloat = 12
    private let gap: CGFloat = 8

    init(store: LumoStore) {
        self.store = store
        let initial = NSSize(width: baseCharacterSize.width + 24, height: baseCharacterSize.height + 24)
        panel = LumoPanel(contentRect: NSRect(origin: .zero, size: initial), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = AppSettings.shared.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = NSHostingView(rootView: FloatingRootView().environmentObject(store))

        restorePosition()
        observeState()

        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.persistCharacterPosition() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .lumoRequestKeyboardFocus, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.activateForInput() } })
        observers.append(NotificationCenter.default.addObserver(forName: .lumoHideRequested, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.hide() } })
        observers.append(NotificationCenter.default.addObserver(forName: .lumoPositionRequested, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in guard let self, let preset = note.object as? String else { return }; self.move(to: preset) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .lumoCoordinatesRequested, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.applySavedCoordinates() } })
        observers.append(NotificationCenter.default.addObserver(forName: .lumoAlwaysOnTopChanged, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.panel.level = AppSettings.shared.alwaysOnTop ? .floating : .normal } })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func observeState() {
        store.$expanded.removeDuplicates().dropFirst().sink { [weak self] expanded in
            Task { @MainActor in self?.scheduleResize(expanded: expanded) }
        }.store(in: &cancellables)

        AppSettings.shared.$characterScale.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.scheduleResize(expanded: self?.store.expanded ?? false) }
        }.store(in: &cancellables)
    }

    func show() { panel.level = AppSettings.shared.alwaysOnTop ? .floating : .normal; panel.orderFrontRegardless() }
    func hide() { store.expanded = false; panel.orderOut(nil) }
    func toggleVisibility() { panel.isVisible ? hide() : showAndExpand() }
    func showAndExpand(history: Bool = false) { show(); store.interact(); store.expanded = true; store.showingHistory = history; activateForInput() }
    private func activateForInput() { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }

    // MARK: - Stable character anchor
    // positionX/Y are the bottom-left coordinates of Lumo itself, not of the variable-size panel.
    // The command window grows around that fixed rectangle, so opening/closing never moves Lumo.
    private var characterSize: NSSize {
        let s = CGFloat(AppSettings.shared.characterScale)
        return NSSize(width: baseCharacterSize.width * s, height: baseCharacterSize.height * s)
    }

    private func compactSize() -> NSSize { NSSize(width: characterSize.width + 2*padding, height: characterSize.height + 2*padding) }
    private func expandedSize() -> NSSize {
        NSSize(width: max(panelSize.width, characterSize.width) + 2*padding,
               height: panelSize.height + gap + characterSize.height + 2*padding)
    }

    private func chooseGrowthDirection(characterOrigin: NSPoint) {
        let rect = NSRect(origin: characterOrigin, size: characterSize)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(rect) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        // Grow toward the side with the most room. This keeps the command panel on-screen
        // while preserving the exact character position.
        AppSettings.shared.panelGrowsRight = rect.midX < f.midX
        AppSettings.shared.panelGrowsDown = rect.midY > f.midY
    }

    private func characterLocalOrigin(in size: NSSize) -> NSPoint {
        let s = characterSize
        let x = AppSettings.shared.panelGrowsRight ? padding : size.width - padding - s.width
        let y = AppSettings.shared.panelGrowsDown ? size.height - padding - s.height : padding
        return NSPoint(x: x, y: y)
    }

    private func currentCharacterOrigin() -> NSPoint {
        let local = characterLocalOrigin(in: panel.frame.size)
        return NSPoint(x: panel.frame.minX + local.x, y: panel.frame.minY + local.y)
    }

    // Window geometry is intentionally applied on the next main-loop turn.
    // Never mutate NSWindow geometry from a SwiftUI layout/update pass: AppKit may
    // recursively request constraints and abort with "needing another Update Constraints pass".
    private func scheduleResize(expanded: Bool) {
        guard !frameUpdateScheduled else { return }
        frameUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameUpdateScheduled = false
            self.resizePanel(expanded: self.store.expanded, animated: false)
        }
    }

    private func resizePanel(expanded: Bool, animated: Bool) {
        guard !isApplyingFrame else { return }
        isApplyingFrame = true
        defer { isApplyingFrame = false }
        let characterOrigin = AppSettings.shared.positionSaved
            ? NSPoint(x: AppSettings.shared.positionX, y: AppSettings.shared.positionY)
            : currentCharacterOrigin()
        if expanded { chooseGrowthDirection(characterOrigin: characterOrigin) }
        let size = expanded ? expandedSize() : compactSize()
        let local = characterLocalOrigin(in: size)
        var frame = NSRect(x: characterOrigin.x - local.x, y: characterOrigin.y - local.y, width: size.width, height: size.height)
        frame = adjustedFrameKeepingCharacterVisible(frame, characterOrigin: characterOrigin)
        // Avoid NSWindow's animated frame machinery here: the hosting view changes
        // hierarchy at the same time as expanded changes. One atomic frame update
        // keeps the Lumo anchor fixed without entering a constraints feedback loop.
        panel.setFrame(frame, display: true, animate: false)
        persistCharacterPosition()
    }

    private func restorePosition() {
        let settings = AppSettings.shared
        if settings.positionSaved {
            resizePanel(expanded: false, animated: false)
        } else if let f = NSScreen.main?.visibleFrame {
            let cs = characterSize
            let p = NSPoint(x: f.maxX - cs.width - 20, y: f.minY + 20)
            settings.savePosition(x: p.x, y: p.y)
            resizePanel(expanded: false, animated: false)
        }
    }

    private func persistCharacterPosition() {
        // During user dragging the panel, derive the visible Lumo position from its local anchor.
        let p = currentCharacterOrigin()
        AppSettings.shared.savePosition(x: p.x, y: p.y)
    }

    private func applySavedCoordinates() {
        resizePanel(expanded: store.expanded, animated: false)
        show()
    }

    private func move(to preset: String) {
        guard let screen = screenForCharacter() ?? NSScreen.main else { return }
        let f = screen.visibleFrame, s = characterSize, m: CGFloat = 20
        let p: NSPoint
        switch preset {
        case "topLeft": p = NSPoint(x: f.minX + m, y: f.maxY - s.height - m)
        case "topRight": p = NSPoint(x: f.maxX - s.width - m, y: f.maxY - s.height - m)
        case "bottomLeft": p = NSPoint(x: f.minX + m, y: f.minY + m)
        case "center": p = NSPoint(x: f.midX - s.width/2, y: f.midY - s.height/2)
        default: p = NSPoint(x: f.maxX - s.width - m, y: f.minY + m)
        }
        AppSettings.shared.savePosition(x: p.x, y: p.y)
        resizePanel(expanded: store.expanded, animated: false)
        show()
    }

    private func screenForCharacter() -> NSScreen? {
        let r = NSRect(origin: NSPoint(x: AppSettings.shared.positionX, y: AppSettings.shared.positionY), size: characterSize)
        return NSScreen.screens.first { $0.visibleFrame.intersects(r) }
    }

    private func adjustedFrameKeepingCharacterVisible(_ frame: NSRect, characterOrigin: NSPoint) -> NSRect {
        // Do not clamp the expanded panel in a way that shifts Lumo. Growth direction already
        // chooses the best side. Only recover Lumo itself if a saved position is off-screen.
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: characterOrigin, size: characterSize)) }) ?? NSScreen.main else { return frame }
        let f = screen.visibleFrame, s = characterSize
        var cp = characterOrigin
        cp.x = min(max(cp.x, f.minX), f.maxX - s.width)
        cp.y = min(max(cp.y, f.minY), f.maxY - s.height)
        if cp != characterOrigin { AppSettings.shared.savePosition(x: cp.x, y: cp.y) }
        let local = characterLocalOrigin(in: frame.size)
        return NSRect(x: cp.x - local.x, y: cp.y - local.y, width: frame.width, height: frame.height)
    }
}

extension Notification.Name {
    static let lumoRequestKeyboardFocus = Notification.Name("LumoRequestKeyboardFocus")
    static let lumoHideRequested = Notification.Name("LumoHideRequested")
    static let lumoPositionRequested = Notification.Name("LumoPositionRequested")
    static let lumoCoordinatesRequested = Notification.Name("LumoCoordinatesRequested")
    static let lumoAlwaysOnTopChanged = Notification.Name("LumoAlwaysOnTopChanged")
    static let lumoOpenSettingsRequested = Notification.Name("LumoOpenSettingsRequested")
}
