import Foundation
import AppKit
import UserNotifications

class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published var secondsRemaining: Int = 0
    @Published var breakSecondsRemaining: Int = 0
    @Published var isOnBreak: Bool = false
    @Published var isPaused: Bool = false
    @Published var isSnoozed: Bool = false

    private var timer: Timer?
    private let settings = AppSettings.shared

    var formattedTimeRemaining: String {
        if isOnBreak {
            return "\(breakSecondsRemaining)s"
        }
        if isPaused || isSnoozed {
            return "paused"
        }
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }

    var menuBarTitle: String {
        let eye = "👁"
        if isOnBreak {
            return "\(eye) Break \(breakSecondsRemaining)s"
        }
        if isPaused || isSnoozed {
            return "\(eye) ⏸"
        }
        return "\(eye) \(formattedTimeRemaining)"
    }

    private init() {
        setupWorkspaceNotifications()
    }

    func start() {
        secondsRemaining = settings.breakInterval * 60
        isPaused = false
        isSnoozed = false
        startTimer()
    }

    func pause() {
        isPaused = true
        stopTimer()
    }

    func resume() {
        isPaused = false
        isSnoozed = false
        startTimer()
    }

    func togglePause() {
        if isPaused || isSnoozed {
            resume()
        } else {
            pause()
        }
    }

    func snooze(minutes: Int) {
        // If on break, close the break windows
        if isOnBreak {
            isOnBreak = false
            breakSecondsRemaining = 0
            NotificationCenter.default.post(name: .breakDidEnd, object: nil)
        }

        // Set snooze timer
        secondsRemaining = minutes * 60
        isPaused = false
        isSnoozed = false
        startTimer()
    }

    func takeBreakNow() {
        isPaused = false
        isSnoozed = false
        startBreak()
        startTimer() // Ensure timer is running even if previously paused
    }

    func skipNextBreak() {
        secondsRemaining = settings.breakInterval * 60
        if !isPaused {
            startTimer()
        }
    }

    func endBreakEarly() {
        isOnBreak = false
        breakSecondsRemaining = 0

        NotificationCenter.default.post(name: .breakDidEnd, object: nil)

        // Reset timer for next cycle
        secondsRemaining = settings.breakInterval * 60
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if isOnBreak {
            if breakSecondsRemaining > 0 {
                breakSecondsRemaining -= 1
            }
            if breakSecondsRemaining <= 0 {
                finishBreak()
            }
        } else {
            if secondsRemaining > 0 {
                secondsRemaining -= 1
            }

            // Send notification before break
            if settings.showNotificationBeforeBreak &&
                secondsRemaining == settings.notificationLeadTime {
                sendPreBreakNotification()
            }

            if secondsRemaining <= 0 {
                startBreak()
            }
        }
    }

    private func startBreak() {
        isOnBreak = true
        breakSecondsRemaining = settings.breakDuration
        NotificationCenter.default.post(name: .breakDidStart, object: nil)
    }

    private func finishBreak() {
        isOnBreak = false
        breakSecondsRemaining = 0

        // Play sound (via SoundManager to retain the NSSound reference)
        SoundManager.shared.playBreakEndSound()

        NotificationCenter.default.post(name: .breakDidEnd, object: nil)

        // Reset timer for next cycle
        secondsRemaining = settings.breakInterval * 60
        startTimer()
    }

    private func sendPreBreakNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Blink"
        content.body = "Eye break starting in \(settings.notificationLeadTime) seconds"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "preBreak",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func setupWorkspaceNotifications() {
        let workspace = NSWorkspace.shared
        let nc = workspace.notificationCenter

        nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
        }

        nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resume()
        }

        nc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
        }

        nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resume()
        }
    }
}

extension Notification.Name {
    static let breakDidStart = Notification.Name("breakDidStart")
    static let breakDidEnd = Notification.Name("breakDidEnd")
}
