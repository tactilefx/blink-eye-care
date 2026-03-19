import AppKit

final class SoundManager {
    static let shared = SoundManager()
    private init() {}

    private var currentSound: NSSound?

    func preview(_ option: SoundOption, volume: Float) {
        stopCurrent()
        guard let sound = NSSound(named: NSSound.Name(option.rawValue)) else { return }
        sound.volume = volume
        currentSound = sound
        sound.play()
    }

    func stopCurrent() {
        currentSound?.stop()
        currentSound = nil
    }

    func playBreakEndSound() {
        let settings = AppSettings.shared
        guard settings.soundEnabled else { return }
        preview(settings.selectedSoundOption, volume: Float(settings.soundVolume))
    }
}
