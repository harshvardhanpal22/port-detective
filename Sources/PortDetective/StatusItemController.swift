import AppKit
import Combine
import SwiftUI

/// Owns the menu bar icon and the rounded panel that opens beneath it.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    static let panelWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 16

    private let model: AppModel
    private let statusItem: NSStatusItem
    private var panel: MenuPanel?
    private var clickOutsideMonitor: Any?
    private var lastClosed = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.toolTip = "Port Detective"
        }
        model.closePanel = { [weak self] in self?.closePanel() }

        // The icon turns into a warning when something is connected slower than it should be.
        model.$devices
            .map { devices in devices.contains { $0.warning != nil } }
            .removeDuplicates()
            .sink { [weak self] hasWarning in self?.setIcon(warning: hasWarning) }
            .store(in: &cancellables)
    }

    // MARK: Icon

    private func setIcon(warning: Bool) {
        let name = warning ? "exclamationmark.triangle" : "cable.connector"
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Port Detective")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: Panel

    @objc private func togglePanel(_ sender: Any?) {
        if panel?.isVisible == true {
            closePanel()
        } else if Date().timeIntervalSince(lastClosed) > 0.25 {
            // The time check stops the click that just closed the panel from reopening it.
            openPanel()
        }
    }

    private func openPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Fresh content every time, so it always opens on the main page.
        let root = MenuRootView(model: model, cornerRadius: Self.cornerRadius) { [weak self] height in
            // Resize on the next turn of the run loop: resizing the window while
            // SwiftUI is still laying it out doesn't reliably take effect.
            Task { @MainActor in
                self?.fit(height: height)
            }
        }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = GlassContainer.make(content: hosting, cornerRadius: Self.cornerRadius)
        panel.setContentSize(NSSize(width: Self.panelWidth, height: 420))
        position(panel)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        model.menuOpened()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePanel()
            }
        }
    }

    func closePanel() {
        guard let panel, panel.isVisible else { return }
        lastClosed = Date()
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        panel.orderOut(nil)
        panel.contentView = nil // stops the animations while hidden
        model.menuClosed()
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    /// Resizes the panel to fit its content, keeping the top edge under the menu bar.
    /// It never grows past the Dock; the page scrolls instead.
    private func fit(height contentHeight: CGFloat) {
        guard let panel, contentHeight > 1 else { return }
        let height = min(ceil(contentHeight), maxPanelHeight())
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        let top = frame.maxY
        frame.size = NSSize(width: Self.panelWidth, height: height)
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// The space from just under the menu bar down to the top of the Dock, less a small margin.
    private func maxPanelHeight() -> CGFloat {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return 600 }
        return max(240, screen.visibleFrame.height - 18)
    }

    private func position(_ panel: NSPanel) {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame

        var frame = panel.frame
        let centeredX = buttonRect.midX - frame.width / 2
        frame.origin.x = min(max(centeredX, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = buttonRect.minY - 6 - frame.height
        panel.setFrame(frame, display: false)
    }

    private func makePanel() -> MenuPanel {
        let panel = MenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }
        return panel
    }
}

/// A borderless panel that can take keyboard focus (for Esc and controls)
/// without bringing the app to the front.
final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
