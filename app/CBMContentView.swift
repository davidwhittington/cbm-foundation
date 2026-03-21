// CBMContentView.swift
// Root layout: emulator canvas (left) + media/control sidebar (right).
// Mirrors fuji-dynasty's ContentView pattern.

import SwiftUI
import AppKit

struct CBMContentView: View {

    @State private var sidebarVisible: Bool = true
    @State private var viceReady: Bool = false

    private let sidebarWidth: CGFloat = 280

    var body: some View {
        HStack(spacing: 0) {
            // ── Emulator canvas ──────────────────────────────────────
            ZStack {
                Color.black
                if viceReady {
                    CBMEmulatorView()
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                }
            }
            .frame(minWidth: 384)

            // ── Sidebar ──────────────────────────────────────────────
            if sidebarVisible {
                CBMSidebarView()
                    .frame(width: sidebarWidth)
                    .background(.regularMaterial)
                    .clipShape(Rectangle())
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .toolbar {
            CBMToolbarContent(sidebarVisible: $sidebarVisible)
        }
        .onReceive(NotificationCenter.default.publisher(
                for: NSNotification.Name("CBMVICEReadyNotification"))) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                viceReady = true
            }
        }
        .onAppear {
            // VICE may already be running if content view appears after startup
            if CBMWindowBridge.sharedMetalView() != nil {
                viceReady = true
            }
        }
    }
}

// MARK: - Toolbar

struct CBMToolbarContent: ToolbarContent {
    @Binding var sidebarVisible: Bool
    @State private var isPaused: Bool = false
    @State private var warpEnabled: Bool = false

    var body: some ToolbarContent {

        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.squares.right")
            }
            .help("Show/hide sidebar")
        }

        ToolbarItemGroup(placement: .principal) {
            // Pause / Resume
            Button {
                isPaused.toggle()
                VICEEngine.shared().pauseEnabled = isPaused
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
            }
            .help(isPaused ? "Resume" : "Pause")

            // Warp mode
            Button {
                warpEnabled.toggle()
                VICEEngine.shared().warpEnabled = warpEnabled
            } label: {
                Image(systemName: "gauge.with.dots.needle.100percent")
                    .symbolVariant(warpEnabled ? .fill : .none)
                    .foregroundStyle(warpEnabled ? .yellow : .primary)
            }
            .help(warpEnabled ? "Disable warp" : "Enable warp (max speed)")

            Divider()

            // Soft reset
            Button {
                VICEEngine.shared().reset(.soft)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Soft reset (RUN/STOP + RESTORE)")

            // Hard reset
            Button {
                VICEEngine.shared().reset(.hard)
            } label: {
                Image(systemName: "power")
            }
            .help("Hard reset (power cycle)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                SwiftUIPanelCoordinator.shared.showPreferences()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Preferences")
        }
    }
}
