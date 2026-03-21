// PreferenceModel.swift
// Observable preference model for c=foundation.
// Uses @Observable (macOS 14+). Mirror of fuji-foundation's PreferenceModel.swift,
// extended for Commodore-specific settings.

import Observation
import Foundation

// MARK: - Enums

enum MachineModel: Int, CaseIterable, Identifiable, CustomStringConvertible {
    case c64   = 0
    case c64sc = 1  // cycle-exact
    case c128  = 2
    case vic20 = 3
    case pet   = 4
    case plus4 = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .c64:   return "Commodore 64"
        case .c64sc: return "Commodore 64 (Cycle-Exact)"
        case .c128:  return "Commodore 128"
        case .vic20: return "VIC-20"
        case .pet:   return "PET"
        case .plus4: return "Plus/4"
        }
    }

    var shortName: String {
        switch self {
        case .c64:   return "C64"
        case .c64sc: return "C64SC"
        case .c128:  return "C128"
        case .vic20: return "VIC-20"
        case .pet:   return "PET"
        case .plus4: return "Plus/4"
        }
    }

    var description: String { displayName }
}

enum SIDModel: Int, CaseIterable, Identifiable {
    case mos6581 = 0  // original "old" SID, bass-heavy
    case mos8580 = 1  // revised SID, cleaner highs

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .mos6581: return "MOS 6581 (original)"
        case .mos8580: return "MOS 8580 (revised)"
        }
    }
}

enum VideoScalingMode: Int, CaseIterable, Identifiable {
    case integer1x = 0
    case integer2x = 1
    case integer3x = 2
    case smooth    = 3

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .integer1x: return "1× (320×200)"
        case .integer2x: return "2× (640×400)"
        case .integer3x: return "3× (960×600)"
        case .smooth:    return "Smooth (window fill)"
        }
    }
}

// MARK: - Preference Keys

private enum PrefKey {
    static let machineModel    = "MachineModel"
    static let scanlinesEnabled = "ScanlinesEnabled"
    static let crtCurvature    = "CRTCurvatureEnabled"
    static let brightness      = "Brightness"
    static let saturation      = "Saturation"
    static let contrast        = "Contrast"
    static let scalingMode     = "ScalingMode"
    static let linearFilter    = "LinearFilter"
    static let audioEnabled    = "AudioEnabled"
    static let audioVolume     = "AudioVolume"
    static let sidModel        = "SIDModel"
    static let trueDriveEmu    = "TrueDriveEmulation"
    static let virtualDevices  = "VirtualDevices"
    static let netIECEnabled   = "NetIECEnabled"
    static let netIECHost      = "NetIECHost"
    static let netIECPort      = "NetIECPort"
    static let fujiNetEnabled  = "FujiNetEnabled"
    static let fujiNetHost     = "FujiNetHost"
    static let fujiNetPort     = "FujiNetPort"
    static let physDriveEnabled = "PhysDriveEnabled"
    static let physDriveUnit    = "PhysDriveUnit"
    static let joySwapPorts     = "JoySwapPorts"
}

// MARK: - VICEPreferenceModel

@Observable
final class VICEPreferenceModel {

    // Machine
    var machineModel: MachineModel = .c64

    // Video
    var scanlinesEnabled: Bool       = false
    var crtCurvatureEnabled: Bool    = false
    var brightness: Double           = 1.0
    var saturation: Double           = 1.0
    var contrast: Double             = 1.0
    var scalingMode: VideoScalingMode = .integer2x
    var linearFilterEnabled: Bool    = false

    // Audio
    var audioEnabled: Bool  = true
    var audioVolume: Double = 1.0
    var sidModel: SIDModel  = .mos6581

    // Drive
    var trueDriveEmulation: Bool = true
    var virtualDevices: Bool     = true

    // net2iec — Meatloaf TCP bridge (IEC units 9–11)
    var netIECEnabled: Bool  = false
    var netIECHost: String   = "meatloaf.local"
    var netIECPort: Int      = 1541

    // NetIEC — FujiNet-PC UDP bridge (IEC units 8–11)
    var fujiNetEnabled: Bool = false
    var fujiNetHost: String  = "localhost"
    var fujiNetPort: Int     = 6400

    // Physical drive (opencbm / ZoomFloppy / XUM1541)
    var physDriveEnabled: Bool = false
    var physDriveUnit: Int     = 8

    // Input
    var joySwapPorts: Bool = false

    // MARK: - Persistence

    func load() {
        let d = UserDefaults.standard
        machineModel        = MachineModel(rawValue: d.integer(forKey: PrefKey.machineModel)) ?? .c64
        scanlinesEnabled    = d.bool(forKey: PrefKey.scanlinesEnabled)
        crtCurvatureEnabled = d.bool(forKey: PrefKey.crtCurvature)
        brightness          = d.double(forKey: PrefKey.brightness).nonZeroOrDefault(1.0)
        saturation          = d.double(forKey: PrefKey.saturation).nonZeroOrDefault(1.0)
        contrast            = d.double(forKey: PrefKey.contrast).nonZeroOrDefault(1.0)
        scalingMode         = VideoScalingMode(rawValue: d.integer(forKey: PrefKey.scalingMode)) ?? .integer2x
        linearFilterEnabled = d.bool(forKey: PrefKey.linearFilter)
        audioEnabled        = d.object(forKey: PrefKey.audioEnabled) == nil ? true : d.bool(forKey: PrefKey.audioEnabled)
        audioVolume         = d.double(forKey: PrefKey.audioVolume).nonZeroOrDefault(1.0)
        sidModel            = SIDModel(rawValue: d.integer(forKey: PrefKey.sidModel)) ?? .mos6581
        trueDriveEmulation  = d.object(forKey: PrefKey.trueDriveEmu) == nil ? true : d.bool(forKey: PrefKey.trueDriveEmu)
        virtualDevices      = d.object(forKey: PrefKey.virtualDevices) == nil ? true : d.bool(forKey: PrefKey.virtualDevices)
        netIECEnabled       = d.bool(forKey: PrefKey.netIECEnabled)
        netIECHost          = d.string(forKey: PrefKey.netIECHost) ?? "meatloaf.local"
        netIECPort          = d.integer(forKey: PrefKey.netIECPort) != 0 ? d.integer(forKey: PrefKey.netIECPort) : 1541
        fujiNetEnabled      = d.bool(forKey: PrefKey.fujiNetEnabled)
        fujiNetHost         = d.string(forKey: PrefKey.fujiNetHost) ?? "localhost"
        fujiNetPort         = d.integer(forKey: PrefKey.fujiNetPort) != 0 ? d.integer(forKey: PrefKey.fujiNetPort) : 6400
        physDriveEnabled    = d.bool(forKey: PrefKey.physDriveEnabled)
        physDriveUnit       = d.integer(forKey: PrefKey.physDriveUnit) != 0 ? d.integer(forKey: PrefKey.physDriveUnit) : 8
        joySwapPorts        = d.bool(forKey: PrefKey.joySwapPorts)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(machineModel.rawValue,         forKey: PrefKey.machineModel)
        d.set(scanlinesEnabled,              forKey: PrefKey.scanlinesEnabled)
        d.set(crtCurvatureEnabled,           forKey: PrefKey.crtCurvature)
        d.set(brightness,                    forKey: PrefKey.brightness)
        d.set(saturation,                    forKey: PrefKey.saturation)
        d.set(contrast,                      forKey: PrefKey.contrast)
        d.set(scalingMode.rawValue,          forKey: PrefKey.scalingMode)
        d.set(linearFilterEnabled,           forKey: PrefKey.linearFilter)
        d.set(audioEnabled,                  forKey: PrefKey.audioEnabled)
        d.set(audioVolume,                   forKey: PrefKey.audioVolume)
        d.set(sidModel.rawValue,             forKey: PrefKey.sidModel)
        d.set(trueDriveEmulation,            forKey: PrefKey.trueDriveEmu)
        d.set(virtualDevices,                forKey: PrefKey.virtualDevices)
        d.set(netIECEnabled,                 forKey: PrefKey.netIECEnabled)
        d.set(netIECHost,                    forKey: PrefKey.netIECHost)
        d.set(netIECPort,                    forKey: PrefKey.netIECPort)
        d.set(fujiNetEnabled,                forKey: PrefKey.fujiNetEnabled)
        d.set(fujiNetHost,                   forKey: PrefKey.fujiNetHost)
        d.set(fujiNetPort,                   forKey: PrefKey.fujiNetPort)
        d.set(physDriveEnabled,              forKey: PrefKey.physDriveEnabled)
        d.set(physDriveUnit,                 forKey: PrefKey.physDriveUnit)
        d.set(joySwapPorts,                  forKey: PrefKey.joySwapPorts)
    }

    // MARK: - Profile Management

    struct Profile: Codable, Identifiable {
        var id: UUID = UUID()
        var name: String
        var created: Date = Date()
        var scanlinesEnabled: Bool
        var crtCurvatureEnabled: Bool
        var brightness: Double
        var saturation: Double
        var contrast: Double
        var linearFilterEnabled: Bool
        var sidModel: Int
        var trueDriveEmulation: Bool
        var virtualDevices: Bool
        var audioVolume: Double
    }

    private static var profilesURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cbm-foundation/profiles.json")
    }

    func saveProfile(name: String) {
        var profiles = loadProfiles()
        let p = Profile(
            name: name,
            scanlinesEnabled: scanlinesEnabled,
            crtCurvatureEnabled: crtCurvatureEnabled,
            brightness: brightness,
            saturation: saturation,
            contrast: contrast,
            linearFilterEnabled: linearFilterEnabled,
            sidModel: sidModel.rawValue,
            trueDriveEmulation: trueDriveEmulation,
            virtualDevices: virtualDevices,
            audioVolume: audioVolume
        )
        profiles.removeAll { $0.name == name }
        profiles.insert(p, at: 0)
        try? JSONEncoder().encode(profiles).write(to: Self.profilesURL)
    }

    func loadProfiles() -> [Profile] {
        guard let data = try? Data(contentsOf: Self.profilesURL),
              let profiles = try? JSONDecoder().decode([Profile].self, from: data)
        else { return [] }
        return profiles
    }

    func applyProfile(_ profile: Profile) {
        scanlinesEnabled    = profile.scanlinesEnabled
        crtCurvatureEnabled = profile.crtCurvatureEnabled
        brightness          = profile.brightness
        saturation          = profile.saturation
        contrast            = profile.contrast
        linearFilterEnabled = profile.linearFilterEnabled
        sidModel            = SIDModel(rawValue: profile.sidModel) ?? .mos6581
        trueDriveEmulation  = profile.trueDriveEmulation
        virtualDevices      = profile.virtualDevices
        audioVolume         = profile.audioVolume
        applyMetalSettings()
        save()
    }

    func deleteProfile(_ profile: Profile) {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == profile.id }
        try? JSONEncoder().encode(profiles).write(to: Self.profilesURL)
    }

    /// Apply current preference values to the running VICE core via VICEEngine.
    func applyToVICECore() {
        let engine = VICEEngine.shared()
        engine.setResourceInt("WarpMode",             value: 0)
        engine.setResourceInt("SidModel",             value: sidModel.rawValue)
        engine.setResourceInt("DriveTrueEmulation",   value: trueDriveEmulation ? 1 : 0)
        engine.setResourceInt("VirtualDevices",       value: virtualDevices ? 1 : 0)
        engine.setResourceInt("Sound",                value: audioEnabled ? 1 : 0)
        engine.setResourceInt("SoundVolume",          value: Int(audioVolume * 100))
        applyMetalSettings()
        if netIECEnabled {
            engine.connectNet2IEC(toHost: netIECHost, port: netIECPort) { _, _ in }
        } else {
            engine.disconnectNet2IEC()
        }
        if physDriveEnabled {
            try? engine.enablePhysicalDrive(forUnit: physDriveUnit)
        } else {
            engine.disablePhysicalDrive(forUnit: physDriveUnit)
        }
        vice_mac_joystick_set_port_swap(joySwapPorts ? 1 : 0)
    }

    /// Apply video settings to the Metal renderer.
    func applyMetalSettings() {
        Vice_MetalSetScanlines(scanlinesEnabled ? 1 : 0)
        Vice_MetalSetCRTCurvature(crtCurvatureEnabled ? 1 : 0)
        Vice_MetalSetBrightness(brightness)
        Vice_MetalSetSaturation(saturation)
        Vice_MetalSetContrast(contrast)
        Vice_MetalSetLinearFilter(linearFilterEnabled ? 1 : 0)
    }
}

// MARK: - Helpers

private extension Double {
    func nonZeroOrDefault(_ fallback: Double) -> Double {
        self == 0.0 ? fallback : self
    }
}
