import AppKit
import SwiftUI

/// Shows the frosted popup in the top-right corner of the screen.
///
/// If a second event arrives while the popup is still visible (a dock that
/// brings both devices and a charger, say), the two are merged into one popup.
@MainActor
final class HUDController {
    static let cornerRadius: CGFloat = 18

    private var panel: NSPanel?
    private var current: HUDContent?
    private var dismissTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private let screenMargin: CGFloat = 12

    func show(_ content: HUDContent) {
        var merged = content
        if var existing = current {
            existing.merge(content)
            merged = existing
        }
        current = merged

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let view = HUDView(content: merged, cornerRadius: Self.cornerRadius) { [weak self] in
            self?.hide()
        }
        let hosting = FirstMouseHostingView(rootView: view)
        let size = hosting.fittingSize
        let container = GlassContainer.make(content: hosting, cornerRadius: Self.cornerRadius)
        container.frame = NSRect(origin: .zero, size: size)

        panel.contentView = container
        panel.setFrame(frame(for: size), display: true)
        panel.invalidateShadow()

        hideTask?.cancel()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }

        dismissTask?.cancel()
        let delay: Duration = merged.hasWarning ? .seconds(12) : .seconds(7)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        current = nil
        guard let panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel?.contentView = nil // stops the animations while hidden
        }
    }

    // MARK: Window setup

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private func frame(for size: CGSize) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: visible.maxX - size.width - screenMargin,
            y: visible.maxY - size.height - screenMargin,
            width: size.width,
            height: size.height
        )
    }
}

/// Lets a click on the popup register even though the app isn't active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
