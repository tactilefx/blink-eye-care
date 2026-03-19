import AppKit
import SwiftUI

class BreakWindowController: NSObject, ObservableObject {
    static let shared = BreakWindowController()

    @Published var showSkipConfirm: Bool = false

    private var windows: [NSWindow] = []
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
        showSkipConfirm = false
        confirmResetWork?.cancel()

        let message = settings.randomMessage()

        for screen in NSScreen.screens {
            let window = createBreakWindow(for: screen, message: message)
            windows.append(window)

            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                window.animator().alphaValue = 1.0
            }
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        // Monitor keyboard during break
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.keyCode == 53 { // Escape
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
        showSkipConfirm = false

        let windowsToClose = windows
        windows.removeAll()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            for window in windowsToClose {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            for window in windowsToClose {
                window.close()
            }
        })
    }

    private func handleEscape() {
        if showSkipConfirm {
            // Second Escape — skip the break
            showSkipConfirm = false
            confirmResetWork?.cancel()
            timerManager.endBreakEarly()
        } else {
            // First Escape — show confirmation
            showSkipConfirm = true

            // Reset confirmation after 3 seconds
            confirmResetWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.showSkipConfirm = false
            }
            confirmResetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }

    /// Called from the Skip button tap
    func skipFromButton() {
        handleEscape()
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func createBreakWindow(for screen: NSScreen, message: String) -> NSWindow {
        let breakView = BreakOverlayView(
            message: message,
            timerManager: timerManager,
            breakController: self
        )

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
    let message: String
    @ObservedObject var timerManager: TimerManager
    @ObservedObject var breakController: BreakWindowController

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Countdown ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)

                    Text("\(timerManager.breakSecondsRemaining)")
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .foregroundColor(.white)
                }

                // Motivational message
                Text(message)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .padding(.horizontal, 60)

                Spacer()

                // Skip button / confirmation
                VStack(spacing: 0) {
                    if breakController.showSkipConfirm {
                        Text("Press Esc again to skip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .transition(.opacity)
                    } else {
                        Button(action: { breakController.skipFromButton() }) {
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
                .animation(.easeInOut(duration: 0.2), value: breakController.showSkipConfirm)
                .padding(.bottom, 40)
            }
        }
    }

    private var progress: CGFloat {
        let settings = AppSettings.shared
        guard settings.breakDuration > 0 else { return 0 }
        return CGFloat(timerManager.breakSecondsRemaining) / CGFloat(settings.breakDuration)
    }
}
