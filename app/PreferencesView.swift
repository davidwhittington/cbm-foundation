// PreferencesView.swift — c=foundation preferences, modernized.
// Real-time video toggles, separate net2iec/FujiNet-PC sections, profile management.

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

            ProfilesPreferencesTab(model: model)
                .tabItem { Label("Profiles", systemImage: "bookmark") }
        }
        .frame(minWidth: 580, minHeight: 480)
        .onDisappear {
            model.save()
            model.applyToVICECore()
        }
    }
}

// MARK: - Machine

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
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
    }
}

// MARK: - Video

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
                    .onChange(of: model.linearFilterEnabled) { _, v in
                        Vice_MetalSetLinearFilter(v ? 1 : 0)
                    }
            }

            Section("CRT Effects") {
                Toggle("Scanlines", isOn: $model.scanlinesEnabled)
                    .onChange(of: model.scanlinesEnabled) { _, v in
                        Vice_MetalSetScanlines(v ? 1 : 0)
                    }
                Toggle("CRT curvature", isOn: $model.crtCurvatureEnabled)
                    .onChange(of: model.crtCurvatureEnabled) { _, v in
                        Vice_MetalSetCRTCurvature(v ? 1 : 0)
                    }
            }

            Section("Color") {
                LiveSlider(label: "Brightness", value: $model.brightness, range: 0.5...1.5) { v in
                    Vice_MetalSetBrightness(v)
                }
                LiveSlider(label: "Saturation", value: $model.saturation, range: 0...2) { v in
                    Vice_MetalSetSaturation(v)
                }
                LiveSlider(label: "Contrast", value: $model.contrast, range: 0.5...1.5) { v in
                    Vice_MetalSetContrast(v)
                }
            }
        }
        .formStyle(.grouped).padding()
    }
}

// MARK: - Audio

struct AudioPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable audio", isOn: $model.audioEnabled)
                    .onChange(of: model.audioEnabled) { _, v in
                        VICEEngine.shared().setResourceInt("Sound", value: v ? 1 : 0)
                    }
                LabeledSlider("Volume", value: $model.audioVolume, range: 0...1)
                    .disabled(!model.audioEnabled)
                    .onChange(of: model.audioVolume) { _, v in
                        VICEEngine.shared().setResourceInt("SoundVolume", value: Int(v * 100))
                    }
            }
            Section("SID") {
                Picker("SID model", selection: $model.sidModel) {
                    ForEach(SIDModel.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .onChange(of: model.sidModel) { _, s in
                    VICEEngine.shared().setResourceInt("SidModel", value: s.rawValue)
                }
                Text("6581: original hardware. 8580: revised chip with cleaner highs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
    }
}

// MARK: - Drives

struct DrivePreferencesTab: View {
    @Bindable var model: VICEPreferenceModel
    @State private var physDriveStatus: String = ""

    var body: some View {
        Form {
            Section("Drive emulation") {
                Toggle("True drive emulation", isOn: $model.trueDriveEmulation)
                    .onChange(of: model.trueDriveEmulation) { _, v in
                        VICEEngine.shared().setResourceInt("DriveTrueEmulation", value: v ? 1 : 0)
                    }
                Text("Cycle-accurate 1541 behaviour. Required for some copy-protected titles.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Virtual devices", isOn: $model.virtualDevices)
                    .onChange(of: model.virtualDevices) { _, v in
                        VICEEngine.shared().setResourceInt("VirtualDevices", value: v ? 1 : 0)
                    }
                Text("Fast virtual drive. Incompatible with true drive emulation when both on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Physical Drive (ZoomFloppy / XUM1541)") {
                Toggle("Enable via opencbm", isOn: $model.physDriveEnabled)
                if model.physDriveEnabled {
                    Picker("IEC unit", selection: $model.physDriveUnit) {
                        ForEach(8...11, id: \.self) { Text("Unit \($0)").tag($0) }
                    }.pickerStyle(.menu)
                    LabeledContent("Status") {
                        Text(physDriveStatus).foregroundStyle(physDriveStatusColor)
                    }
                    Text("Requires libopencbm.dylib (brew install opencbm) and a ZoomFloppy or XUM1541 adapter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped).padding()
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
        case .enabled:  physDriveStatus = "Enabled"
        case .disabled: physDriveStatus = "Available"
        case .error:    physDriveStatus = mgr.lastError ?? "Error"
        default:        physDriveStatus = "Unavailable"
        }
    }
}

// MARK: - Input

struct InputPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel
    @State private var connectedControllers: [String] = []

    var body: some View {
        Form {
            Section("Joystick") {
                Toggle("Swap Joystick Ports (Port 1 ↔ Port 2)", isOn: $model.joySwapPorts)
                    .onChange(of: model.joySwapPorts) { _, v in
                        vice_mac_joystick_set_port_swap(v ? 1 : 0)
                    }
                LabeledContent("Port Assignment") {
                    Text(model.joySwapPorts
                         ? "Controller 1 → Port 1   ·   Controller 2 → Port 2"
                         : "Controller 1 → Port 2   ·   Controller 2 → Port 1")
                        .foregroundStyle(.secondary)
                }
                if connectedControllers.isEmpty {
                    LabeledContent("Connected Controllers") {
                        Text("None detected").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(connectedControllers.enumerated()), id: \.offset) { i, name in
                        LabeledContent("Controller \(i + 1)") {
                            Text(name).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Keyboard") {
                LabeledContent("Layout") {
                    Text("US Positional (gtk3_sym.vkm)").foregroundStyle(.secondary)
                }
                LabeledContent("Key mapping") {
                    Text("Hardware keycodes → C64 matrix").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped).padding()
        .onAppear { refreshControllers() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect))    { _ in refreshControllers() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in refreshControllers() }
    }

    private func refreshControllers() {
        connectedControllers = GCController.controllers().map { $0.vendorName ?? "Unknown" }
    }
}

// MARK: - Network

struct NetworkPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel
    @State private var net2iecStatus: String = "Disconnected"
    @State private var net2iecConnecting = false
    @State private var showDiagnostics = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable net2iec (Meatloaf)", isOn: $model.netIECEnabled)
                if model.netIECEnabled {
                    LabeledContent("Host") {
                        TextField("meatloaf.local", text: $model.netIECHost)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    }
                    LabeledContent("Port") {
                        TextField("1541", value: $model.netIECPort, format: .number)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 80)
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle().fill(net2iecStatusColor).frame(width: 8, height: 8)
                            Text(net2iecStatus).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button(net2iecConnecting ? "Connecting…" : "Connect") { connectNet2IEC() }
                            .disabled(net2iecConnecting)
                        Spacer()
                        Button("Protocol Log…") { showDiagnostics = true }
                    }
                }
            } header: {
                Label("net2iec — Meatloaf TCP Bridge", systemImage: "cable.connector")
            } footer: {
                Text("Bridges VICE IEC bus (drives 9–11) to a Meatloaf network drive server over TCP.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable FujiNet-PC (NetIEC)", isOn: $model.fujiNetEnabled)
                if model.fujiNetEnabled {
                    LabeledContent("Host") {
                        TextField("localhost", text: $model.fujiNetHost)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    }
                    LabeledContent("Port") {
                        TextField("6400", value: $model.fujiNetPort, format: .number)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 80)
                    }
                    Text("FujiNet-PC IEC server (UDP, default port 6400). Drives 8–11.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Label("NetIEC — FujiNet-PC UDP Bridge", systemImage: "server.rack")
            } footer: {
                Text("FujiNet-PC IEC server support is in active development. Stub wired, pending upstream.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
        .onAppear { refreshNet2IECStatus() }
        .sheet(isPresented: $showDiagnostics) {
            NetworkDiagnosticsView()
        }
    }

    private var net2iecStatusColor: Color {
        switch net2iecStatus {
        case "Connected":   return .green
        case "Connecting…": return .orange
        default:            return .gray
        }
    }

    private func refreshNet2IECStatus() {
        guard let mgr = Net2IECManager.shared else { return }
        switch mgr.state {
        case .connected:  net2iecStatus = "Connected"
        case .connecting: net2iecStatus = "Connecting…"
        case .error:      net2iecStatus = mgr.lastError ?? "Error"
        default:          net2iecStatus = "Disconnected"
        }
    }

    private func connectNet2IEC() {
        net2iecConnecting = true
        net2iecStatus = "Connecting…"
        VICEEngine.shared().connectNet2IEC(toHost: model.netIECHost, port: model.netIECPort) { ok, err in
            net2iecConnecting = false
            net2iecStatus = ok ? "Connected" : (err?.localizedDescription ?? "Error")
        }
    }
}

// MARK: - Network Diagnostics

struct NetworkDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [DiagLine] = []
    @State private var filter: DiagFilter = .all
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    enum DiagFilter: String, CaseIterable { case all = "All", network = "Network", errors = "Errors" }

    struct DiagLine: Identifiable {
        let id = UUID()
        let text: String
        var color: Color {
            let t = text.lowercased()
            if t.contains("error") || t.contains("fail") { return .red }
            if t.contains("net2iec") || t.contains("netiec") || t.contains("meatloaf") { return .cyan }
            if t.contains("warn") { return .orange }
            return .primary
        }
    }

    var filteredLines: [DiagLine] {
        switch filter {
        case .all:     return lines
        case .network: return lines.filter { $0.text.lowercased().contains("net") }
        case .errors:  return lines.filter { $0.text.lowercased().contains("error") || $0.text.lowercased().contains("fail") }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Network Protocol Log")
                    .font(.headline)
                Spacer()
                Picker("Filter", selection: $filter) {
                    ForEach(DiagFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 220)
                Button("Clear") { lines = [] }
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if filteredLines.isEmpty {
                            Text("No entries. Connect to a network drive to see protocol traffic.")
                                .foregroundStyle(.secondary).padding()
                        }
                        ForEach(filteredLines) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: lines.count) { _, _ in
                    if let last = filteredLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(width: 600, height: 400)
        .onReceive(timer) { _ in pollLog() }
    }

    private func pollLog() {
        // Wire to VICE log bridge when available
    }
}

// MARK: - Profiles

struct ProfilesPreferencesTab: View {
    @Bindable var model: VICEPreferenceModel
    @State private var profiles: [VICEPreferenceModel.Profile] = []
    @State private var newProfileName: String = ""
    @State private var showSaveField = false
    @State private var confirmDelete: VICEPreferenceModel.Profile? = nil

    var body: some View {
        Form {
            Section {
                if showSaveField {
                    HStack {
                        TextField("Profile name", text: $newProfileName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            let name = newProfileName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            model.saveProfile(name: name)
                            profiles = model.loadProfiles()
                            newProfileName = ""
                            showSaveField = false
                        }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { showSaveField = false; newProfileName = "" }
                    }
                } else {
                    Button {
                        showSaveField = true
                    } label: {
                        Label("Save current settings as profile…", systemImage: "plus.circle")
                    }
                }
            }

            if !profiles.isEmpty {
                Section("Saved Profiles") {
                    ForEach(profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).fontWeight(.medium)
                                Text(profile.created, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Load") { model.applyProfile(profile) }
                                .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                confirmDelete = profile
                            } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            } else if !showSaveField {
                Section {
                    Text("No profiles saved yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }

            Section {
                Text("Profiles include: video settings (scanlines, CRT, color), audio (SID model, volume), and drive configuration. Machine model and network settings are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
        .onAppear { profiles = model.loadProfiles() }
        .confirmationDialog(
            "Delete \"\(confirmDelete?.name ?? "")\"?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = confirmDelete { model.deleteProfile(p) }
                profiles = model.loadProfiles()
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
    }
}

// MARK: - Reusable Controls

struct LiveSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $value, in: range)
                    .frame(maxWidth: 200)
                    .onChange(of: value) { _, v in onChange(v) }
                Text(String(format: "%.2f", value))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.label = label; self._value = value; self.range = range
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $value, in: range).frame(maxWidth: 200)
                Text(String(format: "%.2f", value)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }
}
