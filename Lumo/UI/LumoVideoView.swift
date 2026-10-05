import SwiftUI
import AppKit
import AVFoundation

struct LumoVideoView: NSViewRepresentable {
    let state: LumoAnimationState
    let onOneShotFinished: () -> Void

    func makeNSView(context: Context) -> LumoVideoNSView {
        let view = LumoVideoNSView()
        view.load(state: state, onFinished: onOneShotFinished)
        return view
    }

    func updateNSView(_ nsView: LumoVideoNSView, context: Context) {
        nsView.load(state: state, onFinished: onOneShotFinished)
    }
}

final class LumoVideoNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var loadedState: LumoAnimationState?
    private var onFinished: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func load(state: LumoAnimationState, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        guard loadedState != state else { return }
        loadedState = state
        teardown()
        guard let url = Bundle.main.url(forResource: state.rawValue, withExtension: "mov") else {
            NSLog("Lumo: missing video resource %@.mov", state.rawValue); return
        }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        player = queue
        playerLayer.player = queue
        if state.loops {
            looper = AVPlayerLooper(player: queue, templateItem: item)
        } else {
            queue.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                self?.onFinished?()
            }
        }
        queue.play()
    }

    private func teardown() {
        player?.pause(); looper = nil; player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
    }
    deinit { teardown() }
}
