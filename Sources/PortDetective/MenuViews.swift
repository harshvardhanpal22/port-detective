import AppKit
import SwiftUI

// MARK: - Root

/// The content of the menu bar panel.
///
/// Each page has a pinned header and a scrolling body. The page reports how
/// tall it would like to be; the panel grows to fit, up to the space between
/// the menu bar and the Dock, and anything beyond that scrolls.
struct MenuRootView: View {
    enum Page { case main, settings }

    @ObservedObject var model: AppModel
    let cornerRadius: CGFloat
    let onHeightChange: (CGFloat) -> Void

    @State private var page: Page = .main

    init(model: AppModel, cornerRadius: CGFloat, onHeightChange: @escaping (CGFloat) -> Void) {
        self.model = model
        self.cornerRadius = cornerRadius
        self.onHeightChange = onHeightChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch page {
            case .main:
                PanelPage {
                    MainHeader {
                        withAnimation(.snappy(duration: 0.28)) { page = .settings }
                    }
                } content: {
                    MainContent(model: model)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            case .settings:
                PanelPage {
                    SettingsHeader {
                        withAnimation(.snappy(duration: 0.28)) { page = .main }
                    }
                } content: {
                    SettingsContent(model: model)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .onPreferenceChange(PanelHeightKey.self, perform: onHeightChange)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

/// A pinned header above a scrolling body, which reports the total height it wants.
struct PanelPage<Header: View, Content: View>: View {
    let header: Header
    let content: Content

    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
                    }
                )

            ScrollView(.vertical) {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .preference(key: PanelHeightKey.self, value: headerHeight + contentHeight)
    }
}

private struct HeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// During a page transition both pages exist, so the panel uses the taller one.
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Main page

struct MainHeader: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
            Text("Port Detective")
                .font(.system(size: 15, weight: .bold))
            Spacer()
            CircleIconButton(symbol: "gearshape", help: "Settings", action: openSettings)
        }
    }
}

struct MainContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PowerTile(charger: model.charger, live: model.livePower, hasBattery: model.hasBattery)
            DevicesTile(devices: model.devices)
        }
    }
}

struct PowerTile: View {
    let charger: ChargerInfo?
    let live: LivePower?
    let hasBattery: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasBattery {
                VStack(spacing: 6) {
                    ChargeIllustration(
                        mode: charger == nil ? .unplugged : .connected,
                        percent: live?.percent,
                        isCharging: live?.isCharging ?? false
                    )
                    Text(statusLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(charger == nil ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity)
            }

            if let charger {
                ChargerSummary(charger: charger)
            } else if !hasBattery {
                Text("Desktop Macs don’t report charger details.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let line = live?.flowSummary(onCharger: charger != nil) {
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tile())
    }

    private var statusLine: String {
        let percentText = live?.percent.map { "\($0)%" }
        func line(_ state: String) -> String {
            [state, percentText].compactMap { $0 }.joined(separator: ", ")
        }
        guard charger != nil else { return line("On battery") }
        if live?.fullyCharged == true { return "Fully charged" }
        if live?.isCharging == true { return line("Charging") }
        return line("Plugged in, not charging")
    }
}

struct DevicesTile: View {
    let devices: [ConnectedDevice]

    private var deviceCount: Int { devices.filter { !$0.isHub }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plugged in")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if deviceCount > 0 {
                    Text("\(deviceCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }

            if devices.isEmpty {
                Text("Plug in a drive, dock or hub to see the speed it actually connects at. To test a cable, plug a fast drive in through it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                list
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tile())
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(devices) { device in
                DeviceRow(device: device)
                    .opacity(device.isHub ? 0.6 : 1)
            }
        }
    }
}

// MARK: - Settings page

struct SettingsHeader: View {
    let back: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CircleIconButton(symbol: "chevron.left", help: "Back", action: back)
            Text("Settings")
                .font(.system(size: 15, weight: .bold))
            Spacer()
        }
    }
}

struct SettingsContent: View {
    @ObservedObject var model: AppModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup("Popups") {
                SettingsToggleRow(title: "Show popups", isOn: $model.popupsEnabled)
                SettingsDivider()
                SettingsToggleRow(title: "When a device is plugged in", isOn: $model.devicePopups)
                    .disabled(!model.popupsEnabled)
                SettingsDivider()
                SettingsToggleRow(title: "When a charger is connected", isOn: $model.chargerPopups)
                    .disabled(!model.popupsEnabled)
                SettingsDivider()
                HStack {
                    Text("Preview")
                        .font(.system(size: 13))
                    Spacer()
                    Button("Charger") { model.previewChargerPopup() }
                    Button("Device") { model.previewDevicePopup() }
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            SettingsGroup("Sound") {
                SettingsToggleRow(title: "Play a sound with popups", isOn: $model.soundEnabled)
                SettingsDivider()
                HStack(spacing: 8) {
                    Text("Sound")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("Sound", selection: $model.soundName) {
                        ForEach(AppModel.soundNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    CircleIconButton(symbol: "speaker.wave.2.fill", help: "Play sound") {
                        model.playSound()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .disabled(!model.soundEnabled)
            }

            SettingsGroup("General") {
                SettingsToggleRow(title: "Open at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            SettingsGroup("About") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Port Detective")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Version \(version)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Made by Harshvardhan Pal")
                            .font(.system(size: 12))
                    }
                    Spacer()
                }
                .padding(12)
                SettingsDivider()
                Text("Shows the real speed of everything you plug in, and what your charger can deliver.\nFree and open source under the MIT License. © 2026 Harshvardhan Pal.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            HStack {
                Spacer()
                Button("Quit Port Detective") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .controlSize(.small)
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .background(Tile())
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 12)
    }
}
