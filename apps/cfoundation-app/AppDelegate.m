/* AppDelegate.m
 * Application lifecycle delegate for c=foundation.
 *
 * Responsibilities:
 *   - Build the NSMenu bar (app, File, Machine, View menus)
 *   - Start the VICE emulation engine (C64) after AppKit finishes launching
 *   - Load and apply persisted preferences once the VICE thread is live
 *   - Wire menu actions to VICEEngine and SwiftUIPanelCoordinator
 */

#import "AppDelegate.h"
#import "VICEEngine.h"
#import "CFoundationMacX-Swift.h"  /* Swift-generated ObjC interface */

@implementation AppDelegate

// MARK: - Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenuBar];

    NSError *error = nil;
    BOOL ok = [[VICEEngine sharedEngine] startWithMachine:VICEMachineModelC64 error:&error];
    if (!ok) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText     = @"VICE startup failed";
        alert.informativeText = error.localizedDescription ?: @"Unknown error";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    /* Apply persisted preferences to VICE core and Metal renderer.
     * Called after main_program() so all VICE resources are registered. */
    [SwiftUIPanelCoordinator.shared applyStartupPreferences];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[VICEEngine sharedEngine] stop];
}

// MARK: - NSMenu bar

- (void)buildMenuBar {
    NSMenu *menuBar = [[NSMenu alloc] init];
    [NSApp setMainMenu:menuBar];

    /* ── App menu ──────────────────────────────────────────────────────── */
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"c=foundation"];
    appItem.submenu = appMenu;

    [appMenu addItemWithTitle:@"About c=foundation"
                       action:@selector(showAboutBox:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Preferences\u2026"
                       action:@selector(showPreferences:)
                keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *servicesItem = [[NSMenuItem alloc] initWithTitle:@"Services"
                                                          action:nil
                                                   keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    servicesItem.submenu = servicesMenu;
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:servicesItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    [appMenu addItemWithTitle:@"Hide c=foundation"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Show All"
                       action:@selector(unhideAllApplications:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit c=foundation"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];

    /* ── File menu ─────────────────────────────────────────────────────── */
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [menuBar addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileItem.submenu = fileMenu;

    [fileMenu addItemWithTitle:@"Open Disk Image\u2026"
                        action:@selector(openDiskImage:)
                 keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Open Tape Image\u2026"
                        action:@selector(openTapeImage:)
                 keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Open Cartridge\u2026"
                        action:@selector(openCartridge:)
                 keyEquivalent:@""];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Media Manager\u2026"
                        action:@selector(showMediaManager:)
                 keyEquivalent:@"m"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save Snapshot\u2026"
                        action:@selector(saveSnapshot:)
                 keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Load Snapshot\u2026"
                        action:@selector(loadSnapshot:)
                 keyEquivalent:@"l"];

    /* ── Machine menu ──────────────────────────────────────────────────── */
    NSMenuItem *machineItem = [[NSMenuItem alloc] init];
    [menuBar addItem:machineItem];
    NSMenu *machineMenu = [[NSMenu alloc] initWithTitle:@"Machine"];
    machineItem.submenu = machineMenu;

    NSMenuItem *pauseItem = [[NSMenuItem alloc] initWithTitle:@"Pause"
                                                       action:@selector(togglePause:)
                                                keyEquivalent:@"p"];
    pauseItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [machineMenu addItem:pauseItem];
    [machineMenu addItem:[NSMenuItem separatorItem]];
    [machineMenu addItemWithTitle:@"Reset"
                           action:@selector(resetSoft:)
                    keyEquivalent:@"r"];
    NSMenuItem *hardReset = [[NSMenuItem alloc] initWithTitle:@"Hard Reset"
                                                       action:@selector(resetHard:)
                                                keyEquivalent:@"r"];
    hardReset.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [machineMenu addItem:hardReset];
    [machineMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *warpItem = [[NSMenuItem alloc] initWithTitle:@"Warp Mode"
                                                      action:@selector(toggleWarp:)
                                               keyEquivalent:@"w"];
    warpItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [machineMenu addItem:warpItem];

    /* ── View menu ─────────────────────────────────────────────────────── */
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    [menuBar addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    viewItem.submenu = viewMenu;

    NSMenuItem *fullscreen = [[NSMenuItem alloc] initWithTitle:@"Enter Full Screen"
                                                        action:@selector(toggleFullScreen:)
                                                 keyEquivalent:@"f"];
    fullscreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:fullscreen];

    /* ── Window menu ───────────────────────────────────────────────────── */
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [menuBar addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    windowItem.submenu = windowMenu;
    [NSApp setWindowsMenu:windowMenu];
    [windowMenu addItemWithTitle:@"Minimize"
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    windowMenu.itemArray.lastObject.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [windowMenu addItemWithTitle:@"Zoom"
                          action:@selector(performZoom:)
                   keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front"
                          action:@selector(arrangeInFront:)
                   keyEquivalent:@""];
}

// MARK: - App menu actions

- (void)showAboutBox:(id)sender {
    [SwiftUIPanelCoordinator.shared showAboutBox];
}

- (void)showPreferences:(id)sender {
    [SwiftUIPanelCoordinator.shared showPreferences];
}

// MARK: - File menu actions

- (void)openDiskImage:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Open Disk Image";
    panel.allowedContentTypes = @[];  /* any file — VICE validates the format */
    panel.allowsOtherFileTypes = YES;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSError *error = nil;
        BOOL ok = [[VICEEngine sharedEngine] attachDiskURL:panel.URL
                                                       unit:8
                                                      drive:0
                                                      error:&error];
        if (!ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSAlert alertWithError:error] runModal];
            });
        }
    }];
}

- (void)openTapeImage:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Open Tape Image";
    panel.allowsOtherFileTypes = YES;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSError *error = nil;
        BOOL ok = [[VICEEngine sharedEngine] attachTapeURL:panel.URL error:&error];
        if (!ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSAlert alertWithError:error] runModal];
            });
        }
    }];
}

- (void)openCartridge:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Open Cartridge";
    panel.allowsOtherFileTypes = YES;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSError *error = nil;
        BOOL ok = [[VICEEngine sharedEngine] attachCartridgeURL:panel.URL error:&error];
        if (!ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSAlert alertWithError:error] runModal];
            });
        }
    }];
}

- (void)showMediaManager:(id)sender {
    [SwiftUIPanelCoordinator.shared showMediaManager];
}

- (void)saveSnapshot:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save Snapshot";
    panel.allowedContentTypes = @[];
    panel.nameFieldStringValue = @"snapshot.vsf";
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSError *error = nil;
        [[VICEEngine sharedEngine] saveSnapshotToURL:panel.URL error:&error];
    }];
}

- (void)loadSnapshot:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Load Snapshot";
    panel.allowsOtherFileTypes = YES;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSError *error = nil;
        [[VICEEngine sharedEngine] loadSnapshotFromURL:panel.URL error:&error];
    }];
}

// MARK: - Machine menu actions

- (void)togglePause:(id)sender {
    VICEEngine *engine = [VICEEngine sharedEngine];
    engine.pauseEnabled = !engine.pauseEnabled;
    NSMenuItem *item = (NSMenuItem *)sender;
    item.title = engine.pauseEnabled ? @"Resume" : @"Pause";
}

- (void)resetSoft:(id)sender {
    [[VICEEngine sharedEngine] reset:VICEResetModeSoft];
}

- (void)resetHard:(id)sender {
    [[VICEEngine sharedEngine] reset:VICEResetModeHard];
}

- (void)toggleWarp:(id)sender {
    VICEEngine *engine = [VICEEngine sharedEngine];
    engine.warpEnabled = !engine.warpEnabled;
    NSMenuItem *item = (NSMenuItem *)sender;
    item.state = engine.warpEnabled ? NSControlStateValueOn : NSControlStateValueOff;
}

@end
