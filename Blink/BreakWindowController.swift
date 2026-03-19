import AppKit
import SwiftUI
import Combine

/// View model for the break overlay. One instance is shared across all
/// screen windows and lives for the entire app lifetime. Properties are
/// reset each time a new break starts.
final class BreakViewModel: ObservableObject {
    @Published var secondsRemaining: Int = 0
    @Published var showSkipConfirm: Bool = false
    @Published var message: String = ""
    @Published var isVisible: Bool = false

    var totalDuration: Int = 20
    var onSkip: () -> Void = {}

    private var timerCancellable: AnyCancellable?

    init() {
        timerCancellable = TimerManager.shared.$breakSecondsRemaining
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.secondsRemaining = value
            }
    }

    var progress: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(secondsRemaining) / CGFloat(totalDuration)
    }

    func configure(message: String, duration: Int) {
        self.message = message
        self.totalDuration = duration
        self.secondsRemaining = duration
        self.showSkipConfirm = false
        self.isVisible = true
    }

    func hide() {
        self.isVisible = false
    }
}

class BreakWindowController: NSObject {
    static let shared = BreakWindowController()

    // Long-lived: windows and view model persist for the app lifetime.
    // We never close or destroy them, just show/hide. This avoids the
    // EXC_BAD_ACCESS crash from NSHostingView teardown in autorelease pools.
    private var windows: [NSWindow] = []
    private let viewModel = BreakViewModel()
    private let timerManager = TimerManager.shared
    private let settings = AppSettings.shared
    private var keyMonitor: Any?
    private var confirmResetWork: DispatchWorkItem?

    override init() {
        super.init()
        viewModel.onSkip = { [weak self] in self?.handleEscape() }
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showBreak),
            name: .breakDidStart,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideBreak),
            name: .breakDidEnd,
            object: nil
        )
    }

    @objc private func showBreak() {
        confirmResetWork?.cancel()

        let message = settings.randomMessage()
        viewModel.configure(message: message, duration: settings.breakDuration)

        ensureWindows()

        for window in windows {
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                window.animator().alphaValue = 1.0
            }
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 {
                self.handleEscape()
                return nil
            }
            return event
        }
    }

    @objc private func hideBreak() {
        removeKeyMonitor()
        confirmResetWork?.cancel()
        confirmResetWork = nil
        viewModel.hide()

        NSAnimationContext.runAnimationGroup({ [weak self] context in
            context.duration = 0.4
            guard let self = self else { return }
            for window in self.windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            for window in self.windows {
                window.orderOut(nil) // hide, never close
            }
        })
    }

    private func handleEscape() {
        if viewModel.showSkipConfirm {
            viewModel.showSkipConfirm = false
            confirmResetWork?.cancel()
            timerManager.endBreakEarly()
        } else {
            viewModel.showSkipConfirm = true

            confirmResetWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.viewModel.showSkipConfirm = false
            }
            confirmResetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// Create windows once, reuse forever. One per screen.
    /// If the screen configuration changes, we rebuild.
    private func ensureWindows() {
        let screens = NSScreen.screens

        // Rebuild if screen count changed
        if windows.count != screens.count {
            for window in windows {
                window.orderOut(nil)
            }
            windows.removeAll()

            for screen in screens {
                let window = createWindow(for: screen)
                windows.append(window)
            }
        } else {
            // Reposition existing windows to match current screen layout
            for (window, screen) in zip(windows, screens) {
                window.setFrame(screen.frame, display: true)
            }
        }
    }

    private func createWindow(for screen: NSScreen) -> NSWindow {
        let breakView = BreakOverlayView(viewModel: viewModel)

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        let hostingView = NSHostingView(rootView: breakView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        hostingView.autoresizingMask = [.width, .height]

        window.contentView = hostingView
        window.setFrame(screen.frame, display: true)
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false

        return window
    }
}

struct BreakOverlayView: View {
    @ObservedObject var viewModel: BreakViewModel

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if viewModel.isVisible {
                VStack(spacing: 40) {
                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 4)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: viewModel.progress)
                            .stroke(
                                Color.white,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: viewModel.progress)

                        Text("\(viewModel.secondsRemaining)")
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Text(viewModel.message)
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, 60)

                    Spacer()

                    VStack(spacing: 0) {
                        if viewModel.showSkipConfirm {
                            Text("Press Esc again to skip")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .transition(.opacity)
                        } else {
                            Button(action: { viewModel.onSkip() }) {
                                Text("Skip  (Esc)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.showSkipConfirm)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
