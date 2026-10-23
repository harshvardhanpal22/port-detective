import AppKit
import SwiftUI

// MARK: - Device row

struct DeviceRow: View {
    let device: ConnectedDevice
    let animateIn: Bool

    @State private var bounce = 0
    @State private var rippling = false

    init(device: ConnectedDevice, animateIn: Bool = false) {
        self.device = device
        self.animateIn = animateIn
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                if animateIn {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(device.iconTint.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                        .scaleEffect(rippling ? 1.7 : 1)
                        .opacity(rippling ? 0 : 0.8)
                }
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(device.iconTint.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: device.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(device.iconTint)
                    .symbolEffect(.bounce, value: bounce)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    SpeedBadge(text: device.speedLabel, tint: device.tint)
                }
                Text(device.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let warning = device.warning {
                    WarningText(warning)
                        .padding(.top, 2)
                }
            }
        }
        .task {
            guard animateIn else { return }
            try? await Task.sleep(for: .milliseconds(300))
            bounce += 1
            withAnimation(.easeOut(duration: 0.8)) { rippling = true }
        }
    }
}

/// The negotiated speed, colour-coded by tier.
struct SpeedBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
            .fixedSize()
    }
}

struct WarningText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .foregroundStyle(.orange)
    }
}

// MARK: - Charger

struct ChargerSummary: View {
    let charger: ChargerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(charger.wattsText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(charger.name)
                        .font(.system(size: 13, weight: .semibold))
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
    }
}

struct ProfileGrid: View {
    let charger: ChargerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Power levels this charger offers")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 70), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(charger.profiles, id: \.self) { profile in
                    ProfileChip(profile: profile, isActive: charger.isActive(profile))
                }
            }
        }
    }
}

struct ProfileChip: View {
    let profile: PDProfile
    let isActive: Bool

    var body: some View {
        Text(profile.label)
            .font(.system(size: 11, weight: isActive ? .bold : .regular, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isActive ? Color.green : Color.secondary)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.green.opacity(0.16) : Color.primary.opacity(0.05))
            )
    }
}

// MARK: - Building blocks

/// The rounded, slightly raised background used for groups, like Control Center's modules.
struct Tile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

struct CircleIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    init(symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
