import AppKit
import SwiftUI

/// A plug, its cable and a battery.
///
/// - `.plugIn` plays the connection: the plug slides into the battery, a ring
///   pulses out from the contact point and the bolt pops in.
/// - `.connected` starts already plugged in.
/// - `.unplugged` shows the plug pulled back.
///
/// While connected and charging, dots of energy keep flowing along the cable.
/// If the mode changes while it's on screen (a charger is plugged in while the
/// menu is open), it animates to the new state.
struct ChargeIllustration: View {
    enum Mode: Equatable { case plugIn, connected, unplugged }

    let mode: Mode
    let percent: Int?
    let isCharging: Bool

    @State private var plugged = false
    @State private var boltVisible = false
    @State private var rippleScale: CGFloat = 0.3
    @State private var rippleOpacity: Double = 0

    init(mode: Mode, percent: Int?, isCharging: Bool) {
        self.mode = mode
        self.percent = percent
        self.isCharging = isCharging
        // Start in the final state when already connected, so the first frame is right.
        _plugged = State(initialValue: mode == .connected)
        _boltVisible = State(initialValue: mode == .connected)
    }

    // Layout, in points, inside a 260 × 64 canvas.
    private let canvas = CGSize(width: 260, height: 64)
    private let midY: CGFloat = 32
    private let cableEnd: CGFloat = 124
    private let batteryLeft: CGFloat = 170
    private let batteryWidth: CGFloat = 76
    private let batteryHeight: CGFloat = 44
    private let unpluggedOffset: CGFloat = -44

    private var level: CGFloat {
        CGFloat(min(max(percent ?? 60, 4), 100)) / 100
    }

    private var flowing: Bool { plugged && isCharging && mode != .unplugged }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !flowing)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                plugAndCable(time: time)
                    .offset(x: plugged ? 0 : unpluggedOffset)
                battery(time: time)
                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)
                    .position(x: batteryLeft, y: midY)
            }
            .frame(width: canvas.width, height: canvas.height)
        }
        .frame(width: canvas.width, height: canvas.height)
        .accessibilityHidden(true)
        .task { await start() }
        .onChange(of: mode) { _, newMode in
            Task { await animateChange(to: newMode) }
        }
    }

    // MARK: Animation steps

    @MainActor
    private func start() async {
        switch mode {
        case .unplugged:
            plugged = false
            boltVisible = false
        case .connected:
            plugged = true
            boltVisible = true
        case .plugIn:
            try? await Task.sleep(for: .milliseconds(200))
            await connect()
        }
    }

    @MainActor
    private func animateChange(to newMode: Mode) async {
        switch newMode {
        case .unplugged:
            withAnimation(.easeInOut(duration: 0.35)) {
                plugged = false
                boltVisible = false
            }
        case .connected, .plugIn:
            if !plugged { await connect() }
        }
    }

    @MainActor
    private func connect() async {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            plugged = true
        }
        try? await Task.sleep(for: .milliseconds(300))

        // Reset the ring, let one frame draw, then send it outwards.
        rippleScale = 0.3
        rippleOpacity = 0.9
        try? await Task.sleep(for: .milliseconds(16))
        withAnimation(.easeOut(duration: 0.75)) {
            rippleScale = 2.6
            rippleOpacity = 0
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
            boltVisible = true
        }
    }

    // MARK: Drawing

    private func plugAndCable(time: TimeInterval) -> some View {
        ZStack {
            // The cable fades in from the left, as if it comes from off-screen.
            Capsule()
                .fill(LinearGradient(
                    colors: [Color.primary.opacity(0), Color.primary.opacity(0.22)],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.35, y: 0.5)
                ))
                .frame(width: cableEnd, height: 6)
                .position(x: cableEnd / 2, y: midY)

            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .opacity(flowing ? dotOpacity(dotX(index, time)) : 0)
                    .position(x: dotX(index, time), y: midY)
            }

            // Plug tip, body and grip.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.45))
                .frame(width: 15, height: 10)
                .position(x: 163.5, y: midY)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.75))
                .frame(width: 32, height: 26)
                .position(x: 140, y: midY)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                        .frame(width: 2, height: 12)
                }
            }
            .position(x: 140, y: midY)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    private func battery(time: TimeInterval) -> some View {
        let fillWidth = max(8, (batteryWidth - 12) * level)
        let pulse = flowing ? 0.82 + 0.18 * sin(time * 3) : 1
        let centerX = batteryLeft + batteryWidth / 2

        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                .frame(width: batteryWidth, height: batteryHeight)
                .position(x: centerX, y: midY)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fillColor)
                .opacity(pulse)
                .frame(width: fillWidth, height: batteryHeight - 12)
                .position(x: batteryLeft + 6 + fillWidth / 2, y: midY)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.4), lineWidth: 2.5)
                .frame(width: batteryWidth, height: batteryHeight)
                .position(x: centerX, y: midY)

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.primary.opacity(0.4))
                .frame(width: 5, height: 16)
                .position(x: batteryLeft + batteryWidth + 4, y: midY)

            Image(systemName: "bolt.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(level > 0.55 ? Color.white : Color.green)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                .symbolEffect(.pulse, options: .repeating, isActive: flowing)
                .scaleEffect(boltVisible ? 1 : 0.2)
                .opacity(boltVisible ? 1 : 0)
                .position(x: centerX, y: midY)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    private var fillColor: Color {
        if mode == .unplugged || !plugged {
            return (percent ?? 100) <= 20 ? .red : Color.primary.opacity(0.35)
        }
        return .green
    }

    private func dotX(_ index: Int, _ time: TimeInterval) -> CGFloat {
        let span = Double(cableEnd) - 8
        let travelled = (time * 48 + Double(index) * span / 5).truncatingRemainder(dividingBy: span)
        return CGFloat(4 + travelled)
    }

    private func dotOpacity(_ x: CGFloat) -> Double {
        let distanceFromEnds = min(x - 4, cableEnd - 4 - x)
        return Double(min(max(distanceFromEnds / 16, 0), 1))
    }
}
