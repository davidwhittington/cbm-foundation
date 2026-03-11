// MediaManagerView.swift
// SwiftUI panel for attaching disk, tape, and cartridge images.
// VICE drive units are numbered 8–11 (not 1–8 like Atari).

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

struct DriveSlot: Identifiable {
    let unit: Int           // 8, 9, 10, or 11
    var drive: Int = 0      // drive index within unit (0 or 1)
    var imageURL: URL?
    var id: Int { unit }

    var displayName: String { "Drive \(unit)" }
    var isAttached: Bool { imageURL != nil }
}

struct CartridgeSlot {
    var imageURL: URL?
    static let empty = CartridgeSlot()
}

// Supported disk image types
extension UTType {
    static let d64 = UTType(filenameExtension: "d64") ?? .data
    static let d71 = UTType(filenameExtension: "d71") ?? .data
    static let d81 = UTType(filenameExtension: "d81") ?? .data
    static let t64 = UTType(filenameExtension: "t64") ?? .data
    static let tap = UTType(filenameExtension: "tap") ?? .data
    static let crt = UTType(filenameExtension: "crt") ?? .data
    static let prg = UTType(filenameExtension: "prg") ?? .data
}

// MARK: - View

struct MediaManagerView: View {
    @State private var drives: [DriveSlot] = [
        DriveSlot(unit: 8),
        DriveSlot(unit: 9),
        DriveSlot(unit: 10),
        DriveSlot(unit: 11),
    ]
    @State private var cartridge = CartridgeSlot()
    @State private var showingDiskPicker: Int? = nil
    @State private var showingCartPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Text("Media")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Drives
            ForEach($drives) { $slot in
                DriveRowView(slot: $slot,
                             onEject: { ejectDrive(unit: slot.unit) },
                             onAttach: { showingDiskPicker = slot.unit })
                Divider()
            }

            // Cartridge
            CartridgeRowView(slot: $cartridge,
                             onEject: ejectCartridge,
                             onAttach: { showingCartPicker = true })

            Spacer()
        }
        .frame(minWidth: 500)
        .fileImporter(
            isPresented: Binding(get: { showingDiskPicker != nil },
                                 set: { if !$0 { showingDiskPicker = nil } }),
            allowedContentTypes: [.d64, .d71, .d81, .t64, .tap, .prg],
            allowsMultipleSelection: false
        ) { result in
            guard let unit = showingDiskPicker,
                  case .success(let urls) = result,
                  let url = urls.first else { return }
            attachDisk(url: url, unit: unit)
            showingDiskPicker = nil
        }
        .fileImporter(
            isPresented: $showingCartPicker,
            allowedContentTypes: [.crt],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                attachCartridge(url: url)
            }
        }
    }

    // MARK: - Actions

    private func attachDisk(url: URL, unit: Int) {
        guard let idx = drives.firstIndex(where: { $0.unit == unit }) else { return }
        drives[idx].imageURL = url
        var error: NSError?
        if !VICEEngine.shared().attachDisk(url, unit: unit, drive: 0, error: &error) {
            // TODO: surface error to user
        }
    }

    private func ejectDrive(unit: Int) {
        guard let idx = drives.firstIndex(where: { $0.unit == unit }) else { return }
        drives[idx].imageURL = nil
        VICEEngine.shared().detachDisk(fromUnit: unit, drive: 0)
    }

    private func attachCartridge(url: URL) {
        cartridge.imageURL = url
        var error: NSError?
        if !VICEEngine.shared().attachCartridge(url, error: &error) {
            // TODO: surface error to user
        }
    }

    private func ejectCartridge() {
        cartridge.imageURL = nil
        VICEEngine.shared().detachCartridge()
    }
}

// MARK: - Drive Row

struct DriveRowView: View {
    @Binding var slot: DriveSlot
    var onEject: () -> Void
    var onAttach: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: slot.isAttached ? "opticaldisc.fill" : "opticaldisc")
                .foregroundStyle(slot.isAttached ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.displayName)
                    .fontWeight(.medium)
                if let url = slot.imageURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if slot.isAttached {
                Button("Eject", action: onEject)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }

            Button(slot.isAttached ? "Change" : "Attach", action: onAttach)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Cartridge Row

struct CartridgeRowView: View {
    @Binding var slot: CartridgeSlot
    var onEject: () -> Void
    var onAttach: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: slot.imageURL != nil ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                .foregroundStyle(slot.imageURL != nil ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cartridge")
                    .fontWeight(.medium)
                if let url = slot.imageURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if slot.imageURL != nil {
                Button("Eject", action: onEject)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }

            Button(slot.imageURL != nil ? "Change" : "Attach", action: onAttach)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
