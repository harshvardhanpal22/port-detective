import AppKit
import Foundation
import SwiftUI

// MARK: - USB link speed

/// The speed a USB link actually negotiated. This is the minimum of what the
/// device, the cable, any hubs in between and the Mac's port all support.
enum USBLinkSpeed: Int, Comparable {
    case low, full, high, superSpeed, superPlus, superPlusBy2

    static func < (lhs: USBLinkSpeed, rhs: USBLinkSpeed) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The registry's "Device Speed" key uses the older IOUSBFamily numbering.
    init?(legacyDeviceSpeed value: Int) {
        switch value {
        case 0: self = .low
        case 1: self = .full
        case 2: self = .high
        case 3: self = .superSpeed
        case 4: self = .superPlus
        case 5: self = .superPlusBy2
        default: return nil
        }
    }

    /// The registry's "USBSpeed" key uses IOUSBHost's connection-speed numbering.
    init?(hostConnectionSpeed value: Int) {
        switch value {
        case 1: self = .full
        case 2: self = .low
        case 3: self = .high
        case 4: self = .superSpeed
        case 5: self = .superPlus
        case 6: self = .superPlusBy2
        default: return nil
        }
    }

    var generation: String {
        switch self {
        case .low: "USB 1.1 low speed"
        case .full: "USB 1.1"
        case .high: "USB 2.0"
        case .superSpeed: "USB 3.2 Gen 1"
        case .superPlus: "USB 3.2 Gen 2"
        case .superPlusBy2: "USB 3.2 Gen 2×2"
        }
    }

    var rate: String {
        switch self {
        case .low: "1.5 Mb/s"
        case .full: "12 Mb/s"
        case .high: "480 Mb/s"
        case .superSpeed: "5 Gb/s"
        case .superPlus: "10 Gb/s"
        case .superPlusBy2: "20 Gb/s"
        }
    }
}

// MARK: - Device kind

/// What a connected device is, worked out from its name and USB interfaces.
enum DeviceKind: Equatable {
    case iPhone, iPad, phone
    case keyboard, mouse, trackpad, gameController, inputDevice
    case headphones, microphone, speaker, audioInterface, audio
    case webcam, camera
    case drive, flashDrive, cardReader, smartCardReader
    case hub, display, ethernet, printer, securityKey, bluetooth, wirelessReceiver, devBoard
    case thunderbolt, other

    var label: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .phone: "Phone"
        case .keyboard: "Keyboard"
        case .mouse: "Mouse"
        case .trackpad: "Trackpad"
        case .gameController: "Game controller"
        case .inputDevice: "Input device"
        case .headphones: "Headphones"
        case .microphone: "Microphone"
        case .speaker: "Speaker"
        case .audioInterface: "Audio interface"
        case .audio: "Audio device"
        case .webcam: "Webcam"
        case .camera: "Camera"
        case .drive: "Drive"
        case .flashDrive: "Flash drive"
        case .cardReader: "Card reader"
        case .smartCardReader: "Smart card reader"
        case .hub: "Hub"
        case .display: "Display"
        case .ethernet: "Ethernet adapter"
        case .printer: "Printer"
        case .securityKey: "Security key"
        case .bluetooth: "Bluetooth adapter"
        case .wirelessReceiver: "Wireless receiver"
        case .devBoard: "Dev board"
        case .thunderbolt: "Thunderbolt device"
        case .other: "Device"
        }
    }

    /// SF Symbols to try, most specific first.
    private var symbolCandidates: [String] {
        switch self {
        case .iPhone: ["iphone"]
        case .iPad: ["ipad"]
        case .phone: ["smartphone", "iphone"]
        case .keyboard: ["keyboard"]
        case .mouse: ["computermouse", "magicmouse"]
        case .trackpad: ["rectangle.and.hand.point.up.left", "hand.point.up.left"]
        case .gameController: ["gamecontroller"]
        case .inputDevice: ["hand.tap"]
        case .headphones: ["headphones"]
        case .microphone: ["mic"]
        case .speaker: ["hifispeaker"]
        case .audioInterface: ["slider.vertical.3"]
        case .audio: ["waveform"]
        case .webcam: ["web.camera", "video"]
        case .camera: ["camera"]
        case .drive: ["externaldrive"]
        case .flashDrive: ["mediastick", "externaldrive"]
        case .cardReader: ["sdcard", "externaldrive"]
        case .smartCardReader: ["creditcard"]
        case .hub: ["point.3.connected.trianglepath.dotted"]
        case .display: ["display"]
        case .ethernet: ["network"]
        case .printer: ["printer"]
        case .securityKey: ["key.fill", "key"]
        case .bluetooth: ["dot.radiowaves.left.and.right"]
        case .wirelessReceiver: ["dot.radiowaves.right"]
        case .devBoard: ["cpu"]
        case .thunderbolt: ["bolt.horizontal"]
        case .other: ["cable.connector"]
        }
    }

    /// The first candidate symbol that exists on this version of macOS.
    var symbol: String {
        for name in symbolCandidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return "cable.connector"
    }
}

// MARK: - Connected device

struct ConnectedDevice: Identifiable, Equatable {
    enum Bus: Equatable { case usb, thunderbolt }

    let id: UInt64
    let bus: Bus
    var name: String
    var vendor: String?
    var kind: DeviceKind
    var speed: USBLinkSpeed?
    var upstreamHub: String?
    var warning: String?

    var isHub: Bool { kind == .hub }
    var symbol: String { kind.symbol }

    var speedLabel: String {
        if bus == .thunderbolt { return "Thunderbolt" }
        return speed?.rate ?? "Unknown"
    }

    var subtitle: String {
        var parts: [String] = []
        if let vendor, !name.localizedCaseInsensitiveContains(vendor) {
            parts.append(vendor)
        }
        if bus == .thunderbolt {
            parts.append("Thunderbolt or USB4 device")
        } else {
            parts.append(speed?.generation ?? "USB")
        }
        if let upstreamHub {
            parts.append("through \(upstreamHub)")
        }
        return parts.joined(separator: ", ")
    }

    /// Colour for the speed badge.
    var tint: Color {
        if warning != nil { return .orange }
        if bus == .thunderbolt { return .purple }
        switch speed ?? .low {
        case .superPlusBy2: return .purple
        case .superPlus: return .green
        case .superSpeed: return .blue
        case .low, .full, .high: return .gray
        }
    }

    /// Colour for the device icon.
    var iconTint: Color { warning == nil ? .accentColor : .orange }

    /// Thunderbolt first, then anything with a warning, then normal devices, hubs last.
    var sortRank: Int {
        if bus == .thunderbolt { return 0 }
        if warning != nil { return 1 }
        if isHub { return 3 }
        return 2
    }

    /// Used by "Preview device popup" when nothing is plugged in.
    static let sample = ConnectedDevice(
        id: UInt64.max, bus: .usb, name: "Portable SSD T7", vendor: "Samsung",
        kind: .drive, speed: .superPlus, upstreamHub: nil, warning: nil
    )
}

// MARK: - Charger

struct PDProfile: Hashable {
    var volts: Double
    var amps: Double

    var label: String { "\(Format.number(volts))V \(Format.number(amps))A" }
}

struct ChargerInfo: Equatable {
    var name: String
    /// 0 means the charger did not report a wattage.
    var watts: Int
    var volts: Double?
    var amps: Double?
    var profiles: [PDProfile]
    var isWireless: Bool

    var wattsText: String { watts > 0 ? "\(watts) W" : "? W" }

    var detailLine: String {
        if let volts, let amps {
            return "Negotiated \(Format.number(volts)) V at \(Format.number(amps)) A"
        }
        return isWireless ? "Wireless charger" : "Power adapter"
    }

    var warning: String? {
        if watts == 0 {
            return "This charger didn’t report its wattage. It may be a basic 5 V USB charger, so expect slow charging."
        }
        if watts < 30 {
            return "Low-wattage charger. Expect slow charging, and the battery may still drain under heavy load."
        }
        return nil
    }

    func isActive(_ profile: PDProfile) -> Bool {
        guard let volts else { return false }
        return abs(profile.volts - volts) < 0.5
    }

    /// Used by "Preview charger popup" when no charger is connected.
    static let sample = ChargerInfo(
        name: "96W USB-C Power Adapter", watts: 96, volts: 20, amps: 4.7,
        profiles: [
            PDProfile(volts: 5, amps: 3), PDProfile(volts: 9, amps: 3),
            PDProfile(volts: 15, amps: 3), PDProfile(volts: 20, amps: 4.7)
        ],
        isWireless: false
    )
}

// MARK: - Live power readings

struct LivePower: Equatable {
    var systemWatts: Double?
    /// Positive while charging, negative while the battery is draining.
    var batteryWatts: Double?
    var percent: Int?
    var isCharging = false
    var fullyCharged = false

    /// One line about where the power is going, or nil if there's nothing useful to say.
    func flowSummary(onCharger: Bool) -> String? {
        if onCharger {
            var parts: [String] = []
            if let systemWatts, systemWatts > 0.5 {
                parts.append("Drawing \(Format.number(systemWatts)) W from the charger")
            }
            if isCharging, let batteryWatts, batteryWatts > 0.5 {
                parts.append("\(Format.number(batteryWatts)) W going into the battery")
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ") + "."
        }
        if let batteryWatts, batteryWatts < -0.5 {
            return "Using \(Format.number(-batteryWatts)) W from the battery."
        }
        return nil
    }
}

// MARK: - Popup content

struct HUDContent {
    var charger: ChargerInfo?
    var batteryPercent: Int?
    var devices: [ConnectedDevice] = []

    var hasWarning: Bool {
        charger?.warning != nil || devices.contains { $0.warning != nil }
    }

    /// Non-hub devices first. Hubs only appear if nothing else was plugged in.
    var visibleDevices: [ConnectedDevice] {
        let nonHubs = devices.filter { !$0.isHub }
        let list = nonHubs.isEmpty ? devices : nonHubs
        return list.sorted { $0.sortRank < $1.sortRank }
    }

    var deviceTitle: String {
        let shown = visibleDevices
        if shown.count == 1 { return "\(shown[0].kind.label) connected" }
        return "\(shown.count) devices connected"
    }

    mutating func merge(_ other: HUDContent) {
        if let charger = other.charger {
            self.charger = charger
            batteryPercent = other.batteryPercent ?? batteryPercent
        }
        for device in other.devices where !devices.contains(where: { $0.id == device.id }) {
            devices.append(device)
        }
    }
}

// MARK: - Formatting

enum Format {
    /// "20" for 20.0, "4.7" for 4.7.
    static func number(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
