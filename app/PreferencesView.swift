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
                .help("Select the Commodore machine to emulate. Changes take effect on next launch.")
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
                .help("Controls how the C64's 384×272 frame is scaled to fill the window.")

                Toggle("Bilinear filtering", isOn: $model.linearFilterEnabled)
                    .help("Smooths pixel edges when scaling. Off gives the sharp, authentic pixel look.")
                    .onChange(of: model.linearFilterEnabled) { _, v in
                        Vice_MetalSetLinearFilter(v ? 1 : 0)
                    }
            }

            Section("CRT Effects") {
                Toggle("Scanlines", isOn: $model.scanlinesEnabled)
                    .help("Dims alternate rows to simulate the horizontal scan lines of a CRT television.")
                    .onChange(of: model.scanlinesEnabled) { _, v in
                        Vice_MetalSetScanlines(v ? 1 : 0)
                    }
                Toggle("CRT curvature", isOn: $model.crtCurvatureEnabled)
                    .help("Adds a subtle barrel distortion to simulate the curved glass of a CRT screen.")
                    .onChange(of: model.crtCurvatureEnabled) { _, v in
                        Vice_MetalSetCRTCurvature(v ? 1 : 0)
                    }
            }

            Section("Color") {
                LiveSlider(label: "Brightness", value: $model.brightness, range: 0.5...1.5) { v in
                    Vice_MetalSetBrightness(v)
                }
                .help("Overall display brightness. 1.0 is the calibrated default.")

                LiveSlider(label: "Saturation", value: $model.saturation, range: 0...2) { v in
                    Vice_MetalSetSaturation(v)
                }
                .help("Color intensity. Higher values produce richer, more vivid C64 colours.")

                LiveSlider(label: "Contrast", value: $model.contrast, range: 0.5...1.5) { v in
                    Vice_MetalSetContrast(v)
                }
                .help("Range between darkest and brightest colours. 1.0 is the calibrated default.")
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
                    .help("Master audio switch. Disabling silences the SID chip output completely.")
                    .onChange(of: model.audioEnabled) { _, v in
                        VICEEngine.shared().setResourceInt("Sound", value: v ? 1 : 0)
                    }
                LabeledSlider("Volume", value: $model.audioVolume, range: 0...1)
                    .help("SID output volume. Applies in addition to your system volume.")
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
                .help("Choose the SID chip revision. 6581 has the characteristic bass-heavy sound of early C64s. 8580 was used in later models with cleaner highs.")
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
                    .help("Enables cycle-accurate 1541 drive emulation. Required for copy-protected titles and fastloaders. Significantly slower than virtual device mode.")
                    .onChange(of: model.trueDriveEmulation) { _, v in
                        VICEEngine.shared().setResourceInt("DriveTrueEmulation", value: v ? 1 : 0)
                    }
                Text("Cycle-accurate 1541 behaviour. Required for some copy-protected titles.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Virtual devices", isOn: $model.virtualDevices)
                    .help("Fast virtual drive that bypasses true drive emulation. Incompatible with true drive emulation — only one should be active at a time.")
                    .onChange(of: model.virtualDevices) { _, v in
                        VICEEngine.shared().setResourceInt("VirtualDevices", value: v ? 1 : 0)
                    }
                Text("Fast virtual drive. Incompatible with true drive emulation when both on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Physical Drive (ZoomFloppy / XUM1541)") {
                Toggle("Enable via opencbm", isOn: $model.physDriveEnabled)
                    .help("Connect a real Commodore 1541/1571/1581 drive via a ZoomFloppy or XUM1541 USB adapter. Requires libopencbm.dylib.")
                if model.physDriveEnabled {
                    Picker("IEC unit", selection: $model.physDriveUnit) {
                        ForEach(8...11, id: \.self) { Text("Unit \($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .help("IEC bus unit number the physical drive will respond to (8–11).")
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
                    .help("Most C64 games use Port 2 for the main joystick. Enable this if your game expects Port 1.")
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
                .help("The C64 keyboard layout in use. Hardware key positions map directly to C64 matrix positions.")
                LabeledContent("Key mapping") {
                    Text("Hardware keycodes → C64 matrix").foregroundStyle(.secondary)
                }
                .help("Key events are translated from macOS hardware keycodes to the C64 keyboard matrix on every frame.")
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
                    .help("Bridge the C64's IEC bus (drives 9–11) to a Meatloaf network drive server over TCP. Lets the emulated C64 load from network endpoints.")
                if model.netIECEnabled {
                    LabeledContent("Host") {
                        TextField("meatloaf.local", text: $model.netIECHost)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    }
                    .help("Hostname or IP address of the Meatloaf server. mDNS names (e.g. meatloaf.local) work on the same network.")

                    LabeledContent("Port") {
                        TextField("1541", value: $model.netIECPort, format: .number)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 80)
                    }
                    .help("TCP port the Meatloaf server is listening on. Default is 1541.")

                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle().fill(net2iecStatusColor).frame(width: 8, height: 8)
                            Text(net2iecStatus).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button(net2iecConnecting ? "Connecting…" : "Connect") { connectNet2IEC() }
                            .disabled(net2iecConnecting)
                            .help("Attempt to connect to the Meatloaf server now.")
                        Spacer()
                        Button("Protocol Log…") { showDiagnostics = true }
                            .help("Open the network protocol log to debug IEC bus traffic.")
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
                    .help("Bridge the C64's IEC bus to a FujiNet-PC server over UDP. FujiNet-PC IEC support is in active development.")
                if model.fujiNetEnabled {
                    LabeledContent("Host") {
                        TextField("localhost", text: $model.fujiNetHost)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    }
                    .help("Hostname or IP of the FujiNet-PC IEC server. Use localhost if running on the same machine.")

                    LabeledContent("Port") {
                        TextField("6400", value: $model.fujiNetPort, format: .number)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 80)
                    }
                    .help("UDP port for the FujiNet-PC NetIEC server. Default is 6400.")

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
                }
                .pickerStyle(.segmented).frame(maxWidth: 220)
                .help("Filter log entries by category.")
                Button("Clear") { lines = [] }
                    .help("Clear all log entries.")
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

    private func pollLog() {}
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
                            .help("Enter a name for this profile.")
                        Button("Save") {
                            let name = newProfileName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            model.saveProfile(name: name)
                            profiles = model.loadProfiles()
                            newProfileName = ""
                            showSaveField = false
                        }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Save the current video, audio, and drive settings under this name.")
                        Button("Cancel") { showSaveField = false; newProfileName = "" }
                            .help("Discard and close the name field.")
                    }
                } else {
                    Button {
                        showSaveField = true
                    } label: {
                        Label("Save current settings as profile…", systemImage: "plus.circle")
                    }
                    .help("Snapshot the current video, audio, and drive settings into a named profile.")
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
                                .help("Apply \"\(profile.name)\" — restores its video, audio, and drive settings immediately.")
                            Button(role: .destructive) {
                                confirmDelete = profile
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete the \"\(profile.name)\" profile. This cannot be undone.")
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
