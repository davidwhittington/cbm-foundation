// PreferencesView.swift
// SwiftUI tab-based preferences panel for c=foundation.

import SwiftUI

struct PreferencesView: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        TabView {
            MachinePreferencesTab(model: model)
                .tabItem { Label("Machine", systemImage: "cpu") }

            VideoPreferencesTab(model: model)
                .tabItem { Label("Video", systemImage: "display") }

            AudioPreferencesTab(model: model)
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }

            DrivePreferencesTab(model: model)
                .tabItem { Label("Drives", systemImage: "opticaldisc") }

            InputPreferencesTab(model: model)
                .tabItem { Label("Input", systemImage: "gamecontroller") }

            NetworkPreferencesTab(model: model)
                .tabItem { Label("Network", systemImage: "network") }
        }
        .frame(minWidth: 560, minHeight: 440)
        .onDisappear {
            model.save()
            model.applyToVICECore()
        }
    }
}

// MARK: - Machine Tab

struct MachinePreferencesTab: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        Form {
            Section("Machine") {
                Picker("Model", selection: $model.machineModel) {
                    ForEach(MachineModel.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Text("Machine changes take effect on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Video Tab

struct VideoPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        Form {
            Section("Display") {
                Picker("Scaling", selection: $model.scalingMode) {
                    ForEach(VideoScalingMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Toggle("Bilinear filtering", isOn: $model.linearFilterEnabled)
            }
            Section("CRT Effects") {
                Toggle("Scanlines", isOn: $model.scanlinesEnabled)
                Toggle("CRT curvature", isOn: $model.crtCurvatureEnabled)
            }
            Section("Color") {
                LabeledSlider("Brightness", value: $model.brightness, range: 0.5...1.5)
                LabeledSlider("Saturation", value: $model.saturation, range: 0...2)
                LabeledSlider("Contrast",   value: $model.contrast,   range: 0.5...1.5)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Audio Tab

struct AudioPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable audio", isOn: $model.audioEnabled)
                LabeledSlider("Volume", value: $model.audioVolume, range: 0...1)
                    .disabled(!model.audioEnabled)
            }
            Section("SID") {
                Picker("SID model", selection: $model.sidModel) {
                    ForEach(SIDModel.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                Text("6581: original hardware. 8580: revised chip with cleaner highs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Drive Tab

struct DrivePreferencesTab: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        Form {
            Section("Drive emulation") {
                Toggle("True drive emulation", isOn: $model.trueDriveEmulation)
                Text("Enables cycle-accurate 1541 behaviour. Required for some copy-protected titles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Virtual devices", isOn: $model.virtualDevices)
                Text("Fast virtual drive without TDE. Incompatible with true drive emulation when both are on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Input Tab

struct InputPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        Form {
            Section("Joystick") {
                Text("Port assignment and GameController mapping — Phase 5")
                    .foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                Text("Keymap selection (positional / symbolic) — Phase 5")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Network Tab

struct NetworkPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        Form {
            Section("FujiNet-PC / NetIEC") {
                Toggle("Enable NetIEC", isOn: $model.netIECEnabled)
                if model.netIECEnabled {
                    LabeledContent("Host") {
                        TextField("localhost", text: $model.netIECHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                    }
                    LabeledContent("Port") {
                        TextField("6400", value: $model.netIECPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                    }
                    Text("NetIEC bridges VICE's IEC bus (drives 8–11) to the FujiNet-PC daemon running on this machine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text("NetIEC server support in FujiNet-PC is in active development. This feature is scaffolded.")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Reusable Controls

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $value, in: range)
                    .frame(maxWidth: 200)
                Text(String(format: "%.2f", value))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
