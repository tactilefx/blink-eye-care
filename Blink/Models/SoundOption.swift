import Foundation

enum SoundOption: String, CaseIterable, Identifiable {
    case ping = "Ping"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case pop = "Pop"
    case submarine = "Submarine"

    var id: String { rawValue }
    var displayName: String { rawValue }
}
