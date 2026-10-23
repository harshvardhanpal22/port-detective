import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    /// The alert sounds that ship with every Mac.
    static let soundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    @Published private(set) var devices: [ConnectedDevice] = []
    @Published private(set) var charger: ChargerInfo?
    @Published private(set) var livePower: LivePower?
    @Published private(set) var launchAtLogin: Bool

    // MARK: Settings (saved automatically)

    @Published var popupsEnabled: Bool {
        didSet { UserDefaults.standard.set(popupsEnabled, forKey: Keys.popups) }
    }
    @Published var devicePopups: Bool {
        didSet { UserDefaults.standard.set(devicePopups, forKey: Keys.devicePopups) }
    }
    @Published var chargerPopups: Bool {
        didSet { UserDefaults.standard.set(chargerPopups, forKey: Keys.chargerPopups) }
    }
    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: Keys.sound)
            if soundEnabled { playSound() }
        }
    }
    @Published var soundName: String {
        didSet {
            UserDefaults.standard.set(soundName, forKey: Keys.soundName)
            playSound()
        }
    }

    let hasBattery: Bool

    /// Set by the menu bar controller, so previews can close the panel first.
    var closePanel: (() -> Void)?

    private let deviceMonitor: DeviceMonitor
    private let powerMonitor: PowerMonitor
    private let hud: HUDController
    private var currentSound: NSSound?

    private enum Keys {
        static let popups = "showPopups"
        static let devicePopups = "devicePopups"
        static let chargerPopups = "chargerPopups"
        static let sound = "soundEnabled"
        static let soundName = "soundName"
    }

    init() {
        let store = UserDefaults.standard
        store.register(defaults: [
            Keys.popups: true,
            Keys.devicePopups: true,
            Keys.chargerPopups: true,
            Keys.sound: true,
            Keys.soundName: "Glass"
        ])
        popupsEnabled = store.bool(forKey: Keys.popups)
        devicePopups = store.bool(forKey: Keys.devicePopups)
        chargerPopups = store.bool(forKey: Keys.chargerPopups)
        soundEnabled = store.bool(forKey: Keys.sound)
        soundName = store.string(forKey: Keys.soundName) ?? "Glass"
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasBattery = PowerReader.hasBattery()
        deviceMonitor = DeviceMonitor()
        powerMonitor = PowerMonitor()
        hud = HUDController()

        deviceMonitor.onChange = { [weak self] devices in
            self?.devices = devices
        }
        deviceMonitor.onArrival = { [weak self] arrived in
            guard let self, self.popupsEnabled, self.devicePopups else { return }
            self.present(HUDContent(devices: arrived))
        }
        powerMonitor.onChange = { [weak self] charger, live in
            self?.charger = charger
            self?.livePower = live
        }
        powerMonitor.onChargerConnected = { [weak self] charger in
            guard let self, self.popupsEnabled, self.chargerPopups else { return }
            self.present(HUDContent(charger: charger, batteryPercent: self.livePower?.percent))
        }

        deviceMonitor.start()
        powerMonitor.start()
    }

    // MARK: Menu panel

    func menuOpened() {
        deviceMonitor.refresh()
        powerMonitor.setLiveUpdates(true)
    }

    func menuClosed() {
        powerMonitor.setLiveUpdates(false)
    }

    // MARK: Popups and sound

    private func present(_ content: HUDContent) {
        hud.show(content)
        if soundEnabled { playSound() }
    }

    func playSound() {
        currentSound?.stop()
        currentSound = NSSound(named: NSSound.Name(soundName))
        currentSound?.play()
    }

    /// Shows the charger popup with the real charger, or a sample one if none is connected.
    func previewChargerPopup() {
        let charger = self.charger ?? .sample
        let percent = livePower?.percent ?? 64
        showPreview(HUDContent(charger: charger, batteryPercent: percent))
    }

    /// Shows the device popup with a real device, or a sample drive if nothing is plugged in.
    func previewDevicePopup() {
        let device = devices.first { !$0.isHub } ?? .sample
        showPreview(HUDContent(devices: [device]))
    }

    private func showPreview(_ content: HUDContent) {
        closePanel?()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.present(content)
        }
    }

    // MARK: Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Port Detective couldn't change the login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
