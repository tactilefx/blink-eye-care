import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            SoundTab(settings: settings)
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
                .tag(1)

            MessagesTab(settings: settings)
                .tabItem { Label("Messages", systemImage: "text.quote") }
                .tag(2)

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(3)
        }
        .frame(width: 450, height: 380)
        .padding()
    }
}

// MARK: - General Tab
struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Break every")
                    Spacer()
                    Text("\(settings.breakInterval) min")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(settings.breakInterval) },
                    set: { settings.breakInterval = Int($0) }
                ), in: 5...60, step: 5)

                HStack {
                    Text("Break duration")
                    Spacer()
                    Text("\(settings.breakDuration) sec")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(settings.breakDuration) },
                    set: { settings.breakDuration = Int($0) }
                ), in: 5...60, step: 5)
            }

            Section {
                Toggle("Show notification before break", isOn: $settings.showNotificationBeforeBreak)

                if settings.showNotificationBeforeBreak {
                    HStack {
                        Text("Notify")
                        Spacer()
                        Text("\(settings.notificationLeadTime)s before")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(settings.notificationLeadTime) },
                        set: { settings.notificationLeadTime = Int($0) }
                    ), in: 10...60, step: 10)
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        toggleLaunchAtLogin(newValue)
                    }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }
}

// MARK: - Sound Tab
struct SoundTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Play sound when break ends", isOn: $settings.soundEnabled)
            }

            if settings.soundEnabled {
                Section {
                    Picker("Sound", selection: $settings.selectedSound) {
                        ForEach(SoundOption.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }

                    HStack {
                        Button("Preview") {
                            SoundManager.shared.preview(
                                settings.selectedSoundOption,
                                volume: Float(settings.soundVolume)
                            )
                        }
                        .controlSize(.small)
                    }

                    HStack {
                        Image(systemName: "speaker")
                        Slider(value: $settings.soundVolume, in: 0.1...1.0)
                        Image(systemName: "speaker.wave.3")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Messages Tab
struct MessagesTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Select messages to show during breaks") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(MotivationalTexts.defaults.enumerated()), id: \.offset) { index, message in
                            Toggle(isOn: Binding(
                                get: { settings.enabledMessageIndices.contains(index) },
                                set: { enabled in
                                    var indices = settings.enabledMessageIndices
                                    if enabled {
                                        indices.insert(index)
                                    } else {
                                        // Don't allow deselecting all
                                        if indices.count > 1 {
                                            indices.remove(index)
                                        }
                                    }
                                    settings.enabledMessageIndices = indices
                                }
                            )) {
                                Text(message.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 12))
                                    .lineLimit(2)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Tab
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "eye")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Blink")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text("v1.0.0")
                .foregroundColor(.secondary)

            Text("Protect your eyes with the 20-20-20 rule.\nEvery 20 minutes, look 20 feet away for 20 seconds.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            Divider()

            HStack(spacing: 20) {
                Link("GitHub", destination: URL(string: "https://github.com")!)
                    .font(.system(size: 12))

                Text("Free & Open Source (MIT)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
