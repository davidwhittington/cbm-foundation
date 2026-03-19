// VICEStatusBar.swift
// Observable drive status model and status bar view for c=foundation.

import SwiftUI
import Observation

// MARK: - Model

/// Drive status state updated by VICE emulation callbacks.
@Observable
final class VICEStatusModel {
    /// LED active state, indexed 0–3 for IEC units 8–11.
    var driveLED:   [Bool]   = [false, false, false, false]
    /// Current half-track position, indexed 0–3 (divide by 2 for track number).
    var driveTrack: [Double] = [0, 0, 0, 0]
}

// MARK: - Status Bar View

/// Thin horizontal strip showing drive LED and track indicators.
/// Hosted in the emulator window's bottom titlebar accessory.
struct VICEStatusBarView: View {
    var model: VICEStatusModel

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { i in
                DriveStatusIndicator(
                    unit:      i + 8,
                    active:    model.driveLED[i],
                    halfTrack: model.driveTrack[i]
                )
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 22)
    }
}

// MARK: - Drive Indicator

private struct DriveStatusIndicator: View {
    let unit:      Int
    let active:    Bool
    let halfTrack: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Color.red : Color(.separatorColor))
                .frame(width: 7, height: 7)
            Text("\(unit)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(active ? .primary : .secondary)
            if halfTrack > 0 {
                Text(String(format: "%.1f", halfTrack / 2.0))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(active || halfTrack > 0 ? 1.0 : 0.45)
    }
}
