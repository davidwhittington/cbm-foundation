// CBMSidebarView.swift
// Media sidebar for cbm-foundation.
// Mirrors fuji-dynasty's MediaSidebarView, adapted for C64/VICE.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Drive LED state

enum CBMDriveLED {
    case idle, reading, writing
    var color: Color {
        switch self {
        case .idle:    return Color(NSColor.separatorColor)
        case .reading: return .green
        case .writing: return .red
        }
    }
}

// MARK: - Drive slot model

class CBMDriveSlot: ObservableObject, Identifiable {
    let unit: Int
    @Published var mountedFile: String? = nil
    @Published var ledState: CBMDriveLED = .idle
    @Published var writeProtected: Bool = false

    var id: Int { unit }
    var displayName: String { mountedFile.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Empty" }

    init(unit: Int) { self.unit = unit }
}

// MARK: - Sidebar view

struct CBMSidebarView: View {

    @State private var drives: [CBMDriveSlot] = (8...11).map { CBMDriveSlot(unit: $0) }
    @State private var isPaused: Bool = false
    @State private var basicDisabled: Bool = false
    @State private var net2iecConnected: Bool = false
    @State private var showDriveFilePicker: Int? = nil

    private let diskTypes: [UTType] = [
        UTType(filenameExtension: "d64") ?? .data,
        UTType(filenameExtension: "d71") ?? .data,
        UTType(filenameExtension: "d81") ?? .data,
        UTType(filenameExtension: "t64") ?? .data,
        UTType(filenameExtension: "prg") ?? .data,
        .data
    ]

    var body: some View {
        VStack(spacing: 0) {
            machineHeader
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    driveSection
                    Divider().padding(.vertical, 4)
                    networkSection
                    Divider().padding(.vertical, 4)
                    snapshotSection
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Machine header

    private var machineHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("c=foundation")
                        .font(.system(.headline, design: .monospaced))
                    Text("Commodore 64")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Machine badge
                Text("C64")
                    .font(.system(.caption, design: .monospaced).bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.15))
                            .overlay(Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                            .frame(height: 20)
                    )
            }

            HStack(spacing: 6) {
                // Pause
                Button {
                    isPaused.toggle()
                    VICEEngine.shared().pauseEnabled = isPaused
                } label: {
                    Label(isPaused ? "Resume" : "Pause",
                          systemImage: isPaused ? "play.fill" : "pause.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help(isPaused ? "Resume emulation" : "Pause emulation")

                // Soft reset
                Button {
                    VICEEngine.shared().reset(.soft)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Soft reset")

                // Hard reset
                Button {
                    VICEEngine.shared().reset(.hard)
                } label: {
                    Label("Power", systemImage: "power")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Hard reset (power cycle)")

                Spacer()

                // BASIC toggle
                Toggle(isOn: $basicDisabled) {
                    Text("BASIC")
                        .font(.system(.caption, design: .monospaced).bold())
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .onChange(of: basicDisabled) { _, v in
                    VICEEngine.shared().setResourceInt("BasicDisabled", value: v ? 1 : 0)
                }
                .help("Disable BASIC ROM (more RAM for machine language)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Drive section

    private var driveSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Disk Drives", icon: "opticaldiscdrive")
            ForEach(drives) { drive in
                driveRow(drive)
                if drive.unit < 11 {
                    Divider().padding(.leading, 36)
                }
            }
        }
    }

    private func driveRow(_ drive: CBMDriveSlot) -> some View {
        HStack(spacing: 8) {
            // LED
            ledDot(drive.ledState)

            // Unit label + filename
            VStack(alignment: .leading, spacing: 1) {
                Text("D\(drive.unit)")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.secondary)
                Text(drive.displayName)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(drive.mountedFile == nil ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Write-protect (only when mounted)
            if drive.mountedFile != nil {
                Button {
                    drive.writeProtected.toggle()
                } label: {
                    Image(systemName: drive.writeProtected ? "lock.fill" : "lock.open")
                        .foregroundStyle(drive.writeProtected ? .orange : .secondary)
                }
                .buttonStyle(.plain).controlSize(.mini)
                .help(drive.writeProtected ? "Write protected" : "Writable")
            }

            // Eject / Insert
            Button {
                if drive.mountedFile != nil {
                    ejectDrive(drive)
                } else {
                    showDriveFilePicker = drive.unit
                }
            } label: {
                Image(systemName: drive.mountedFile != nil ? "eject" : "plus.circle")
                    .foregroundStyle(drive.mountedFile != nil ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain).controlSize(.mini)
            .help(drive.mountedFile != nil ? "Eject" : "Insert disk…")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .fileImporter(
            isPresented: Binding(
                get: { showDriveFilePicker == drive.unit },
                set: { if !$0 { showDriveFilePicker = nil } }
            ),
            allowedContentTypes: diskTypes
        ) { result in
            if case .success(let url) = result {
                insertDisk(url: url, into: drive)
            }
            showDriveFilePicker = nil
        }
    }

    // MARK: - Network section

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Network", icon: "network")
            HStack(spacing: 8) {
                // net2iec status LED
                Circle()
                    .fill(net2iecConnected ? Color.green : Color(NSColor.separatorColor))
                    .shadow(color: net2iecConnected ? .green.opacity(0.8) : .clear, radius: 3)
                    .frame(width: 8, height: 8)

                Text("net2iec")
                    .font(.system(.caption, design: .monospaced).bold())

                Text(net2iecConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    SwiftUIPanelCoordinator.shared.showPreferences()
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).controlSize(.mini)
                .help("Network preferences")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { refreshNetworkStatus() }
    }

    // MARK: - Snapshot section

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Snapshots", icon: "tray.full")
            HStack(spacing: 8) {
                Button {
                    saveSnapshot()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Save snapshot")

                Button {
                    loadSnapshot()
                } label: {
                    Label("Load", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Load snapshot")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func ledDot(_ state: CBMDriveLED) -> some View {
        Circle()
            .fill(state.color)
            .overlay(Circle().stroke(state.color.opacity(0.4), lineWidth: 1))
            .shadow(color: state.color.opacity(0.8), radius: state == .idle ? 0 : 3)
            .frame(width: 8, height: 8)
    }

    private func insertDisk(url: URL, into drive: CBMDriveSlot) {
        let path = url.path
        _ = url.startAccessingSecurityScopedResource()
        try? VICEEngine.shared().attachDiskURL(url, unit: drive.unit, drive: 0)
        let ok = true
        if ok { drive.mountedFile = path }
    }

    private func ejectDrive(_ drive: CBMDriveSlot) {
        VICEEngine.shared().detachDisk(fromUnit: drive.unit, drive: 0)
        drive.mountedFile = nil
    }

    private func refreshNetworkStatus() {
        net2iecConnected = VICEEngine.shared().isNet2IECConnected
    }

    private func saveSnapshot() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "vsf") ?? .data]
        panel.nameFieldStringValue = "snapshot.vsf"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? VICEEngine.shared().saveSnapshot(to: url)
            }
        }
    }

    private func loadSnapshot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "vsf") ?? .data]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? VICEEngine.shared().loadSnapshot(from: url)
            }
        }
    }
}
