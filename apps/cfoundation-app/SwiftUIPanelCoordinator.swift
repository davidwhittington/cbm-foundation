// SwiftUIPanelCoordinator.swift
// NSHostingController bridge between AppKit (ObjC) and SwiftUI panels.
// Mirrors SwiftUIPanelCoordinator.swift from fuji-foundation.
//
// Usage from Objective-C:
//   [SwiftUIPanelCoordinator.shared showPreferences];
//   [SwiftUIPanelCoordinator.shared showAboutBox];

import AppKit
import SwiftUI

@objc
final class SwiftUIPanelCoordinator: NSObject {

    @objc static let shared = SwiftUIPanelCoordinator()

    private let prefsModel  = VICEPreferenceModel()
    private let statusModel = VICEStatusModel()

    private var prefsWindow: NSWindow?
    private var machineSelectorWindow: NSWindow?
    private var mediaManagerWindow: NSWindow?
    private var aboutBoxWindow: NSWindow?

    private override init() { super.init() }

    // MARK: - Startup

    /// Load persisted preferences, apply them to VICE core, and wire the
    /// status bar into the emulator window.
    /// Called once from AppDelegate after the VICE thread is running.
    @objc func applyStartupPreferences() {
        prefsModel.load()
        prefsModel.applyToVICECore()
        setupStatusBar()
    }

    private func setupStatusBar() {
        let bridge = VICEStatusBridge.shared()

        bridge.driveLEDHandler = { [weak self] (unit: Int, pwm: Int) in
            guard unit >= 0 && unit < 4 else { return }
            self?.statusModel.driveLED[unit] = pwm > 0
        }

        bridge.driveTrackHandler = { [weak self] (unit: Int, halfTrack: Int) in
            guard unit >= 0 && unit < 4 else { return }
            self?.statusModel.driveTrack[unit] = Double(halfTrack)
        }

        guard let window = bridge.emulatorWindow else { return }

        let hostingView = NSHostingView(rootView: VICEStatusBarView(model: statusModel))
        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.view            = hostingView
        accessoryVC.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(accessoryVC)
    }

    // MARK: - Preferences

    @objc func showPreferences() {
        if prefsWindow == nil {
            let hostVC = NSHostingController(
                rootView: PreferencesView(model: prefsModel)
            )
            let window = NSWindow(contentViewController: hostVC)
            window.title = "c=foundation Preferences"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 600, height: 480))
            window.center()
            prefsWindow = window
        }
        prefsModel.load()
        prefsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Machine Selector

    @objc func showMachineSelector() {
        if machineSelectorWindow == nil {
            let hostVC = NSHostingController(
                rootView: MachineSelectorView(model: prefsModel) { [weak self] _ in
                    self?.machineSelectorWindow?.close()
                }
            )
            let window = NSWindow(contentViewController: hostVC)
            window.title = "Select Machine"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 340, height: 400))
            window.center()
            machineSelectorWindow = window
        }
        machineSelectorWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Media Manager

    @objc func showMediaManager() {
        if mediaManagerWindow == nil {
            let hostVC = NSHostingController(rootView: MediaManagerView())
            let window = NSWindow(contentViewController: hostVC)
            window.title = "Media"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 340))
            mediaManagerWindow = window
        }
        mediaManagerWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Setup (first-run / library download)

    /// Returns an NSViewController hosting CBMSetupView.
    /// AppDelegate presents this as a modal window when libvice.dylib is missing.
    @objc static func setupViewController() -> NSViewController {
        NSHostingController(rootView: CBMSetupView())
    }

    // MARK: - About Box

    @objc func showAboutBox() {
        if aboutBoxWindow == nil {
            let hostVC = NSHostingController(rootView: AboutBoxView())
            let window = NSWindow(contentViewController: hostVC)
            window.title = "About c=foundation"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 400, height: 300))
            window.center()
            aboutBoxWindow = window
        }
        aboutBoxWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - About Box View

struct AboutBoxView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("c=foundation")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Commodore Emulator for macOS")
                .foregroundStyle(.secondary)
            Divider()
            Text("Built on VICE 3.9")
                .font(.caption)
            Text("VICE © VICE Team — GPL v2")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("macOS app © 2026 David Whittington")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 400, height: 280)
    }
}
