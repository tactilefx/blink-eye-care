import Foundation
import Combine

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var breakInterval: Int {
        didSet { defaults.set(breakInterval, forKey: "breakInterval") }
    }
    @Published var breakDuration: Int {
        didSet { defaults.set(breakDuration, forKey: "breakDuration") }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var selectedSound: String {
        didSet { defaults.set(selectedSound, forKey: "selectedSound") }
    }
    @Published var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: "soundVolume") }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published var showNotificationBeforeBreak: Bool {
        didSet { defaults.set(showNotificationBeforeBreak, forKey: "showNotificationBeforeBreak") }
    }
    @Published var notificationLeadTime: Int {
        didSet { defaults.set(notificationLeadTime, forKey: "notificationLeadTime") }
    }
    @Published var enabledMessageIndices: Set<Int> {
        didSet {
            let data = (try? JSONEncoder().encode(Array(enabledMessageIndices))) ?? Data()
            defaults.set(data, forKey: "enabledMessageIndices")
        }
    }

    var selectedSoundOption: SoundOption {
        get { SoundOption(rawValue: selectedSound) ?? .glass }
        set { selectedSound = newValue.rawValue }
    }

    private init() {
        let d = UserDefaults.standard

        self.breakInterval = d.object(forKey: "breakInterval") as? Int ?? 20
        self.breakDuration = d.object(forKey: "breakDuration") as? Int ?? 20
        self.soundEnabled = d.object(forKey: "soundEnabled") as? Bool ?? true
        self.selectedSound = d.string(forKey: "selectedSound") ?? SoundOption.glass.rawValue
        self.soundVolume = d.object(forKey: "soundVolume") as? Double ?? 0.8
        self.launchAtLogin = d.bool(forKey: "launchAtLogin")
        self.showNotificationBeforeBreak = d.object(forKey: "showNotificationBeforeBreak") as? Bool ?? true
        self.notificationLeadTime = d.object(forKey: "notificationLeadTime") as? Int ?? 30

        if let data = d.data(forKey: "enabledMessageIndices"),
           let indices = try? JSONDecoder().decode([Int].self, from: data) {
            self.enabledMessageIndices = Set(indices)
        } else {
            self.enabledMessageIndices = Set(0..<MotivationalTexts.defaults.count)
        }
    }

    func randomMessage() -> String {
        let messages = MotivationalTexts.defaults
        let enabled = enabledMessageIndices.filter { $0 < messages.count }
        if enabled.isEmpty { return messages[0] }
        let index = enabled.randomElement()!
        return messages[index]
    }
}
