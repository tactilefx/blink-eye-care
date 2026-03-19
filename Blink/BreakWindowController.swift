import AppKit
import SwiftUI
import Combine

// A short-lived view model that exists only for the duration of one break.
// This avoids @ObservedObject references to long-lived singletons, which
// cause EXC_BAD_ACCESS when NSHostingView is torn down on window.close().
final class BreakViewModel: ObservableObject {
    @Published var secondsRemaining: Int
    @Published var showSkipConfirm: Bool = false
    let message: String
    let totalDuration: Int
    var onSkip: () -> Void = {}

    private var timerCancellable: AnyCancellable?

    init(message: String, duration: Int) {
        self.message = message
        self.totalDuration = duration
        self.secondsRemaining = duration

        // Subscribe to the shared timer's break countdown
        timerCancellable = TimerManager.shared.$breakSecondsRemaining
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.secondsRemaining = value
            }
    }

    deinit {
        timerCancellable?.cancel()
    }

    var progress: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(secondsRemaining) / CGFloat(totalDuration)
    }
}

class BreakWindowController: NSObject {
    static let shared = BreakWindowController()

    private var windows: [NSWindow] = []
    private var viewModels: [BreakViewModel] = []
    private let timerManager = TimerManager.shared
    private let settings = AppSettings.shared
    private var keyMonitor: Any?
    private var confirmResetWork: DispatchWorkItem?

    override init() {
        super.init()
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

        for screen in NSScreen.screens {
            let vm = BreakViewModel(message: message, duration: settings.breakDuration)
            vm.onSkip = { [weak self] in self?.handleEscape() }
            viewModels.append(vm)

            let window = createBreakWindow(for: screen, viewModel: vm)
            windows.append(window)

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

        let windowsToClose = windows
        windows.removeAll()

        // Clear view models AFTER windows are closed
        let vmsToRelease = viewModels
        viewModels.removeAll()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            for window in windowsToClose {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            for window in windowsToClose {
                window.contentView = nil // Detach hosting view first
                window.close()
            }
            // vmsToRelease dealloc naturally here after closure completes
            _ = vmsToRelease
        })
    }

    private func handleEscape() {
        let isConfirming = viewModels.first?.showSkipConfirm ?? false

        if isConfirming {
            for vm in viewModels { vm.showSkipConfirm = false }
            confirmResetWork?.cancel()
            timerManager.endBreakEarly()
        } else {
            for vm in viewModels { vm.showSkipConfirm = true }

            confirmResetWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                for vm in self.viewModels { vm.showSkipConfirm = false }
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

    private func createBreakWindow(for screen: NSScreen, viewModel: BreakViewModel) -> NSWindow {
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

        return window
    }
}

struct BreakOverlayView: View {
    @ObservedObject var viewModel: BreakViewModel

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

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
