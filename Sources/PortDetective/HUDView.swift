import SwiftUI

struct HUDView: View {
    let content: HUDContent
    let cornerRadius: CGFloat
    let onClose: () -> Void

    private static let maxRows = 4

    init(content: HUDContent, cornerRadius: CGFloat, onClose: @escaping () -> Void) {
        self.content = content
        self.cornerRadius = cornerRadius
        self.onClose = onClose
    }

    private var shownDevices: [ConnectedDevice] { content.visibleDevices }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let charger = content.charger {
                ChargerPopupSection(charger: charger, percent: content.batteryPercent)
            }

            if content.charger != nil && !shownDevices.isEmpty {
                Divider()
            }

            if !shownDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label(content.deviceTitle, systemImage: "cable.connector")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(Array(shownDevices.prefix(Self.maxRows))) { device in
                        DeviceRow(device: device, animateIn: true)
                    }
                    if shownDevices.count > Self.maxRows {
                        Text("And \(shownDevices.count - Self.maxRows) more. Click the menu bar icon to see everything.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
    }
}

/// The plug-in animation, then the wattage rolling up to its real value.
struct ChargerPopupSection: View {
    let charger: ChargerInfo
    let percent: Int?

    @State private var shownWatts = 0

    init(charger: ChargerInfo, percent: Int?) {
        self.charger = charger
        self.percent = percent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChargeIllustration(mode: .plugIn, percent: percent, isCharging: true)
                .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: 12) {
                Text(charger.watts > 0 ? "\(shownWatts) W" : "? W")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(shownWatts)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charger connected")
                        .font(.system(size: 13, weight: .semibold))
                    Text(charger.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(charger.detailLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if !charger.profiles.isEmpty {
                ProfileGrid(charger: charger)
            }
            if let warning = charger.warning {
                WarningText(warning)
            }
        }
        .task {
            // Roll the number up just as the plug lands.
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.smooth(duration: 0.9)) {
                shownWatts = charger.watts
            }
        }
    }
}
