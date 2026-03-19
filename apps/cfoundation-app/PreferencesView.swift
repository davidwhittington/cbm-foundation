// PreferencesView.swift
// SwiftUI tab-based preferences panel for c=foundation.

import SwiftUI
import GameController

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
    @State private var physDriveStatus: String = ""

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
            Section("Physical Drive (ZoomFloppy / XUM1541)") {
                Toggle("Enable via opencbm", isOn: $model.physDriveEnabled)
                if model.physDriveEnabled {
                    Picker("IEC unit", selection: $model.physDriveUnit) {
                        ForEach(8...11, id: \.self) { unit in
                            Text("Unit \(unit)").tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Status") {
                        Text(physDriveStatus)
                            .foregroundStyle(physDriveStatusColor)
                    }
                    Text("Requires libopencbm.dylib (brew install opencbm) and a ZoomFloppy or XUM1541 adapter connected via USB.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshPhysDriveStatus() }
        .onChange(of: model.physDriveEnabled) { _, _ in refreshPhysDriveStatus() }
    }

    private var physDriveStatusColor: Color {
        switch physDriveStatus {
        case "Enabled":     return .green
        case "Available":   return .secondary
        case "Unavailable": return .red
        default:            return .secondary
        }
    }

    private func refreshPhysDriveStatus() {
        let mgr = PhysDrvManager.shared
        switch mgr.state {
        case .enabled:      physDriveStatus = "Enabled"
        case .disabled:     physDriveStatus = "Available"
        case .error:        physDriveStatus = mgr.lastError ?? "Error"
        default:            physDriveStatus = "Unavailable"
        }
    }
}

// MARK: - Input Tab

struct InputPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel
    @State private var connectedControllers: [String] = []

    var body: some View {
        Form {
            // MARK: Joystick
            Section("Joystick") {
                Toggle("Swap Joystick Ports (Port 1 ↔ Port 2)", isOn: $model.joySwapPorts)
                    .onChange(of: model.joySwapPorts) { _, swapped in
                        vice_mac_joystick_set_port_swap(swapped ? 1 : 0)
                    }

                LabeledContent("Port Assignment") {
                    if model.joySwapPorts {
                        Text("Controller 1 → Port 1   ·   Controller 2 → Port 2")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Controller 1 → Port 2   ·   Controller 2 → Port 1")
                            .foregroundStyle(.secondary)
                    }
                }

                if connectedControllers.isEmpty {
                    LabeledContent("Connected Controllers") {
                        Text("None detected")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(connectedControllers.enumerated()), id: \.offset) { idx, name in
                        LabeledContent("Controller \(idx + 1)") {
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: Keyboard
            Section("Keyboard") {
                LabeledContent("Layout") {
                    Text("US Positional (gtk3_sym.vkm)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Key mapping") {
                    Text("Hardware keycodes → C64 matrix")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshControllers() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.GCControllerDidConnect))    { _ in refreshControllers() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.GCControllerDidDisconnect)) { _ in refreshControllers() }
    }

    private func refreshControllers() {
        connectedControllers = GCController.controllers().map {
            $0.vendorName ?? "Unknown Controller"
        }
    }
}

// MARK: - Network Tab

struct NetworkPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel
    @State private var statusText: String = "Disconnected"
    @State private var isConnecting: Bool = false

    var body: some View {
        Form {
            Section("FujiNet-PC / Meatloaf (net2iec)") {
                Toggle("Enable Network Drive (net2iec)", isOn: $model.netIECEnabled)
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
                    LabeledContent("Status") {
                        Text(statusText)
                            .foregroundStyle(statusColor)
                            .monospacedDigit()
                    }
                    Button(isConnecting ? "Connecting..." : "Connect Now") {
                        connect()
                    }
                    .disabled(isConnecting)
                    Text("Bridges VICE IEC bus (drives 8–11) to a Meatloaf or FujiNet-PC server over TCP.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshStatus() }
    }

    private var statusColor: Color {
        switch statusText {
        case "Connected":    return .green
        case "Connecting…": return .orange
        case "Error":        return .red
        default:             return .secondary
        }
    }

    private func refreshStatus() {
        let mgr = Net2IECManager.shared
        switch mgr?.state {
        case .connected:    statusText = "Connected"
        case .connecting:   statusText = "Connecting…"
        case .error:        statusText = mgr?.lastError ?? "Error"
        default:            statusText = "Disconnected"
        }
    }

    private func connect() {
        isConnecting = true
        statusText   = "Connecting…"
        VICEEngine.shared().connectNet2IEC(toHost: model.netIECHost,
                                            port: model.netIECPort) { success, error in
            isConnecting = false
            if success {
                statusText = "Connected"
            } else {
                statusText = error?.localizedDescription ?? "Error"
            }
        }
    }
}

// MARK: - Reusable Controls

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.label = label
        self._value = value
        self.range = range
    }

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
