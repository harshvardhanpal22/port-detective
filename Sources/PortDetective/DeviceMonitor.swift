import Foundation
import IOKit

/// Watches the I/O Registry for USB and Thunderbolt devices arriving and leaving.
///
/// New devices are held for a moment before being inspected, for two reasons: a
/// device's interfaces (which tell us whether it is a drive, camera and so on)
/// appear a little after the device itself, and a dock brings a burst of devices
/// that should be announced together rather than one popup each.
@MainActor
final class DeviceMonitor {
    /// Called with the full, sorted list whenever anything changes.
    var onChange: (([ConnectedDevice]) -> Void)?
    /// Called with the devices that were just plugged in, after they settle.
    var onArrival: (([ConnectedDevice]) -> Void)?

    private var devices: [UInt64: ConnectedDevice] = [:]
    private var pending: [UInt64: ConnectedDevice.Bus] = [:]
    private var settleTask: Task<Void, Never>?
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    func start() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        register(className: "IOUSBHostDevice", bus: .usb,
                 added: usbDeviceAdded, removed: usbDeviceRemoved)
        register(className: "IOThunderboltSwitch", bus: .thunderbolt,
                 added: thunderboltDeviceAdded, removed: thunderboltDeviceRemoved)
    }

    /// Re-reads every known device. Cheap; called when the menu opens so that
    /// categories filled in late by drivers show up correctly.
    func refresh() {
        for (id, device) in devices {
            let service = IOReg.service(withEntryID: id)
            if service == 0 {
                devices[id] = nil
                continue
            }
            if let updated = DeviceInspector.inspect(service, bus: device.bus) {
                devices[id] = updated
            }
            IOObjectRelease(service)
        }
        publish()
    }

    // MARK: Registration

    private func register(
        className: String,
        bus: ConnectedDevice.Bus,
        added: IOServiceMatchingCallback,
        removed: IOServiceMatchingCallback
    ) {
        guard let port = notifyPort else { return }
        let refCon = Unmanaged.passUnretained(self).toOpaque()

        var addedIterator: io_iterator_t = 0
        if IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching(className),
            added, refCon, &addedIterator
        ) == KERN_SUCCESS {
            iterators.append(addedIterator)
            // Draining the iterator lists what's already connected and arms the notification.
            handleAdded(addedIterator, bus: bus, initial: true)
        }

        var removedIterator: io_iterator_t = 0
        if IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, IOServiceMatching(className),
            removed, refCon, &removedIterator
        ) == KERN_SUCCESS {
            iterators.append(removedIterator)
            handleRemoved(removedIterator)
        }
    }

    /// Entry point from the C callbacks below. IOKit delivers these on the main
    /// run loop, because that's where the notification port's source was added.
    nonisolated static func handleCallback(
        _ refCon: UnsafeMutableRawPointer?,
        _ iterator: io_iterator_t,
        bus: ConnectedDevice.Bus,
        added: Bool
    ) {
        guard let refCon else { return }
        MainActor.assumeIsolated {
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(refCon).takeUnretainedValue()
            if added {
                monitor.handleAdded(iterator, bus: bus, initial: false)
            } else {
                monitor.handleRemoved(iterator)
            }
        }
    }

    // MARK: Events

    private func handleAdded(_ iterator: io_iterator_t, bus: ConnectedDevice.Bus, initial: Bool) {
        var changed = false
        IOReg.drain(iterator) { service in
            let id = IOReg.entryID(service)
            if initial {
                if let device = DeviceInspector.inspect(service, bus: bus) {
                    devices[id] = device
                    changed = true
                }
            } else {
                pending[id] = bus
            }
        }
        if changed { publish() }
        if !initial && !pending.isEmpty { scheduleSettle() }
    }

    private func handleRemoved(_ iterator: io_iterator_t) {
        var changed = false
        IOReg.drain(iterator) { service in
            let id = IOReg.entryID(service)
            pending[id] = nil
            if devices.removeValue(forKey: id) != nil { changed = true }
        }
        if changed { publish() }
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.settlePending()
        }
    }

    private func settlePending() {
        let waiting = pending
        pending.removeAll()

        var arrived: [ConnectedDevice] = []
        for (id, bus) in waiting {
            let service = IOReg.service(withEntryID: id)
            guard service != 0 else { continue } // unplugged again already
            if let device = DeviceInspector.inspect(service, bus: bus) {
                devices[id] = device
                arrived.append(device)
            }
            IOObjectRelease(service)
        }

        publish()
        if !arrived.isEmpty { onArrival?(arrived) }
    }

    private func publish() {
        let sorted = devices.values.sorted { a, b in
            if a.sortRank != b.sortRank { return a.sortRank < b.sortRank }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        onChange?(sorted)
    }
}

// MARK: - C callbacks
// IOKit needs plain C function pointers, which can't capture context,
// so each one forwards to the monitor through the refCon pointer.

private func usbDeviceAdded(_ refCon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    DeviceMonitor.handleCallback(refCon, iterator, bus: .usb, added: true)
}

private func usbDeviceRemoved(_ refCon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    DeviceMonitor.handleCallback(refCon, iterator, bus: .usb, added: false)
}

private func thunderboltDeviceAdded(_ refCon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    DeviceMonitor.handleCallback(refCon, iterator, bus: .thunderbolt, added: true)
}

private func thunderboltDeviceRemoved(_ refCon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    DeviceMonitor.handleCallback(refCon, iterator, bus: .thunderbolt, added: false)
}
