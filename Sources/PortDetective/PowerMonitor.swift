import Foundation
import IOKit
import IOKit.ps

/// Watches for power source changes and announces when a charger is connected.
@MainActor
final class PowerMonitor {
    var onChange: ((ChargerInfo?, LivePower?) -> Void)?
    var onChargerConnected: ((ChargerInfo) -> Void)?

    private(set) var charger: ChargerInfo?
    private var runLoopSource: CFRunLoopSource?
    private var announceTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(powerSourcesChangedCallback, context)?
            .takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        // A charger that's already connected at launch doesn't get a popup.
        charger = PowerReader.charger()
        publish()
    }

    /// While the menu is open, refresh the live wattage every couple of seconds.
    func setLiveUpdates(_ enabled: Bool) {
        liveTask?.cancel()
        liveTask = nil
        guard enabled else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.reload()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    nonisolated static func handleCallback(_ context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        MainActor.assumeIsolated {
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().reload()
        }
    }

    private func reload() {
        let wasConnected = charger != nil
        charger = PowerReader.charger()
        if !wasConnected, charger != nil {
            scheduleAnnouncement()
        } else if charger == nil {
            announceTask?.cancel()
        }
        publish()
    }

    /// Chargers often report a low 5 V profile for a moment before USB Power
    /// Delivery finishes negotiating, so wait and re-read before announcing.
    private func scheduleAnnouncement() {
        announceTask?.cancel()
        announceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, let latest = PowerReader.charger() else { return }
            self.charger = latest
            self.publish()
            self.onChargerConnected?(latest)
        }
    }

    private func publish() {
        onChange?(charger, PowerReader.live())
    }
}

private func powerSourcesChangedCallback(_ context: UnsafeMutableRawPointer?) {
    PowerMonitor.handleCallback(context)
}

// MARK: - Reading power data

enum PowerReader {
    static func hasBattery() -> Bool {
        let battery = batteryService()
        guard battery != 0 else { return false }
        IOObjectRelease(battery)
        return true
    }

    /// The connected charger, or nil when running on battery.
    /// Desktop Macs have no battery and no charger to report, so they also return nil.
    static func charger() -> ChargerInfo? {
        let battery = batteryService()
        guard battery != 0 else { return nil }
        defer { IOObjectRelease(battery) }

        let externalConnected = IOReg.bool(battery, "ExternalConnected")
        if externalConnected == false { return nil }

        // The public API gives the basics; the battery's registry entry adds
        // the list of voltage/current profiles the charger offers.
        var details: [String: Any] = [:]
        if let unmanaged = IOPSCopyExternalPowerAdapterDetails(),
           let dictionary = (unmanaged.takeRetainedValue() as AnyObject) as? [String: Any] {
            details = dictionary
        }
        if let extra = IOReg.dictionary(battery, "AdapterDetails") {
            details.merge(extra) { current, _ in current }
        }
        if details.isEmpty && externalConnected != true { return nil }

        let watts = number(details["Watts"]) ?? 0
        let millivolts = number(details["AdapterVoltage"]) ?? number(details["Voltage"])
        let milliamps = number(details["Current"])

        let menu = details["UsbHvcMenu"] as? [[String: Any]] ?? []
        let profiles: [PDProfile] = menu.compactMap { entry in
            guard let mv = number(entry["MaxVoltage"]), let ma = number(entry["MaxCurrent"]),
                  mv > 0, ma > 0 else { return nil }
            return PDProfile(volts: Double(mv) / 1000, amps: Double(ma) / 1000)
        }

        let name = nonEmpty(details["Name"] as? String)
            ?? nonEmpty(details["Manufacturer"] as? String).map { "\($0) charger" }
            ?? (watts > 0 ? "\(watts) W charger" : "Charger")

        return ChargerInfo(
            name: name,
            watts: watts,
            volts: millivolts.map { Double($0) / 1000 },
            amps: milliamps.map { Double($0) / 1000 },
            profiles: profiles,
            isWireless: (details["IsWireless"] as? NSNumber)?.boolValue ?? false
        )
    }

    static func live() -> LivePower? {
        let battery = batteryService()
        guard battery != 0 else { return nil }
        defer { IOObjectRelease(battery) }

        var live = LivePower()

        // Total power coming in from the charger (Apple silicon), in milliwatts.
        if let telemetry = IOReg.dictionary(battery, "PowerTelemetryData"),
           let milliwatts = (telemetry["SystemPowerIn"] as? NSNumber)?.int64Value,
           milliwatts > 0 {
            live.systemWatts = Double(milliwatts) / 1000
        }

        // Power flowing into (+) or out of (−) the battery: mV × mA = µW.
        if let millivolts = IOReg.int64(battery, "Voltage"),
           let milliamps = IOReg.int64(battery, "Amperage") {
            live.batteryWatts = Double(millivolts) * Double(milliamps) / 1_000_000
        }

        if let current = IOReg.int(battery, "CurrentCapacity"),
           let maximum = IOReg.int(battery, "MaxCapacity"), maximum > 0 {
            live.percent = Int((Double(current) / Double(maximum) * 100).rounded())
        }
        live.isCharging = IOReg.bool(battery, "IsCharging") ?? false
        live.fullyCharged = IOReg.bool(battery, "FullyCharged") ?? false
        return live
    }

    private static func batteryService() -> io_service_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    private static func number(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
