// SwiftUIPanelCoordinator.swift
// NSHostingController bridge between AppKit (ObjC) and SwiftUI panels.
// Mirrors SwiftUIPanelCoordinator.swift from fuji-foundation.
//
// Usage from Objective-C:
//   [SwiftUIPanelCoordinator.shared showPreferences];
//   [SwiftUIPanelCoordinator.shared showAboutBox];

import SwiftUI

@objc
final class SwiftUIPanelCoordinator: NSObject {

    @objc static let shared = SwiftUIPanelCoordinator()

    private let prefsModel = VICEPreferenceModel()
    private var prefsWindow: NSWindow?
    private var machineSelectorWindow: NSWindow?
    private var mediaManagerWindow: NSWindow?
    private var aboutBoxWindow: NSWindow?

    private override init() { super.init() }

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
