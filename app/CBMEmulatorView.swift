// CBMEmulatorView.swift
// NSViewRepresentable wrapper that exposes the VICE Metal view to SwiftUI.
// gMetalView is created by vice_mac_ui_init() before SwiftUI renders this.

import SwiftUI
import AppKit

struct CBMEmulatorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // gMetalView is set by Vice_MetalViewCreate() before this renders.
        // Return it directly so SwiftUI hosts it without creating a new view.
        if let mv = CBMWindowBridge.sharedMetalView() {
            return mv
        }
        // Fallback: return a black placeholder while VICE initialises
        let placeholder = NSView()
        placeholder.wantsLayer = true
        placeholder.layer?.backgroundColor = NSColor.black.cgColor
        return placeholder
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
