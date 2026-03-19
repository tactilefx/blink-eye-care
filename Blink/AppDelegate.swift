import AppKit
import SwiftUI
import UserNotifications
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private var preferencesHostingView: NSHostingView<PreferencesView>?
    private let timerManager = TimerManager.shared
    private let settings = AppSettings.shared
    private let breakController = BreakWindowController.shared
    private var cancellables = Set<AnyCancellable>()
    private var pauseMenuItem: NSMenuItem!

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        setupMenuBar()
        observeTimer()
        timerManager.start()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = timerManager.menuBarTitle
        }

        let menu = NSMenu()

        pauseMenuItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        let takeBreakItem = NSMenuItem(title: "Take Break Now", action: #selector(takeBreakNow), keyEquivalent: "b")
        takeBreakItem.target = self
        menu.addItem(takeBreakItem)

        let skipItem = NSMenuItem(title: "Skip Next Break", action: #selector(skipBreak), keyEquivalent: "")
        skipItem.target = self
        menu.addItem(skipItem)

        menu.addItem(NSMenuItem.separator())

        // Snooze submenu
        let snoozeItem = NSMenuItem(title: "Snooze", action: nil, keyEquivalent: "")
        let snoozeMenu = NSMenu()

        let snooze15 = NSMenuItem(title: "15 minutes", action: #selector(snooze15), keyEquivalent: "")
        snooze15.target = self
        snoozeMenu.addItem(snooze15)

        let snooze30 = NSMenuItem(title: "30 minutes", action: #selector(snooze30), keyEquivalent: "")
        snooze30.target = self
        snoozeMenu.addItem(snooze30)

        let snooze60 = NSMenuItem(title: "1 hour", action: #selector(snooze60), keyEquivalent: "")
        snooze60.target = self
        snoozeMenu.addItem(snooze60)

        snoozeItem.submenu = snoozeMenu
        menu.addItem(snoozeItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Blink", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func observeTimer() {
        timerManager.$secondsRemaining
            .combineLatest(timerManager.$breakSecondsRemaining, timerManager.$isPaused, timerManager.$isOnBreak)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarTitle()
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarTitle() {
        statusItem?.button?.title = timerManager.menuBarTitle
        pauseMenuItem?.title = (timerManager.isPaused || timerManager.isSnoozed) ? "Resume" : "Pause"
    }

    @objc private func togglePause() {
        timerManager.togglePause()
    }

    @objc private func takeBreakNow() {
        timerManager.takeBreakNow()
    }

    @objc private func skipBreak() {
        timerManager.skipNextBreak()
    }

    @objc private func snooze15() {
        timerManager.snooze(minutes: 15)
    }

    @objc private func snooze30() {
        timerManager.snooze(minutes: 30)
    }

    @objc private func snooze60() {
        timerManager.snooze(minutes: 60)
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let prefsView = PreferencesView(settings: settings)
            let hostingView = NSHostingView(rootView: prefsView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Blink Preferences"
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            preferencesHostingView = hostingView
            preferencesWindow = window
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        if timerManager.isOnBreak {
            timerManager.endBreakEarly()
        }
        NSApplication.shared.terminate(nil)
    }
}
