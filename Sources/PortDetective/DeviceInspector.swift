import Foundation
import IOKit

/// Turns raw I/O Registry entries into `ConnectedDevice` values.
enum DeviceInspector {
    static func inspect(_ service: io_service_t, bus: ConnectedDevice.Bus) -> ConnectedDevice? {
        switch bus {
        case .usb: usbDevice(service)
        case .thunderbolt: thunderboltDevice(service)
        }
    }

    // MARK: USB

    private static func usbDevice(_ service: io_service_t) -> ConnectedDevice? {
        if isInternal(service) { return nil }

        let vendorID = IOReg.int(service, "idVendor")
        let productID = IOReg.int(service, "idProduct")

        let name = IOReg.string(service, "USB Product Name")
            ?? IOReg.string(service, "kUSBProductString")
            ?? fallbackName(vendorID: vendorID, productID: productID)
        let vendor = IOReg.string(service, "USB Vendor Name")
            ?? IOReg.string(service, "kUSBVendorString")

        // Two keys describe the same thing with different numbering schemes.
        let speed = IOReg.int(service, "Device Speed").flatMap(USBLinkSpeed.init(legacyDeviceSpeed:))
            ?? IOReg.int(service, "USBSpeed").flatMap(USBLinkSpeed.init(hostConnectionSpeed:))

        let interfaces = interfaceDescriptors(of: service)
        let kind = DeviceClassifier.classify(
            name: name,
            vendor: vendor,
            vendorID: vendorID,
            deviceClass: IOReg.int(service, "bDeviceClass"),
            interfaces: interfaces
        )

        let upstreamHub = IOReg.firstAncestor(of: service, conformingTo: "IOUSBHostDevice") { hub in
            IOReg.string(hub, "USB Product Name") ?? IOReg.string(hub, "kUSBProductString")
        }

        // Only warn about real storage; card readers are often USB 2 by design.
        var warning: String?
        let isStorage = interfaces.contains { $0.cls == 8 }
        if isStorage, kind != .cardReader, let speed, speed <= .high {
            warning = "Running at USB 2 speed. If this drive is rated for USB 3 or faster, "
                + "the cable or hub is holding it back. Many USB-C charging cables are USB 2 only."
        }

        return ConnectedDevice(
            id: IOReg.entryID(service),
            bus: .usb,
            name: name,
            vendor: vendor,
            kind: kind,
            speed: speed,
            upstreamHub: upstreamHub,
            warning: warning
        )
    }

    /// Skips devices that are part of the Mac itself (on Intel Macs with a T2 chip,
    /// for example, the keyboard and Touch ID sensor are USB devices).
    private static func isInternal(_ service: io_service_t) -> Bool {
        if IOReg.bool(service, "Built-In") == true { return true }
        if let raw = IOReg.value(service, "non-removable") {
            if let text = raw as? String, text.lowercased() == "yes" { return true }
            if let number = raw as? NSNumber, number.boolValue { return true }
        }
        return false
    }

    /// The class, subclass and protocol of every USB interface the device exposes.
    private static func interfaceDescriptors(of service: io_service_t) -> Set<DeviceClassifier.Interface> {
        var interfaces = Set<DeviceClassifier.Interface>()
        IOReg.forEachDescendant(of: service) { child in
            guard let interfaceClass = IOReg.int(child, "bInterfaceClass") else { return }
            interfaces.insert(DeviceClassifier.Interface(
                cls: interfaceClass,
                subclass: IOReg.int(child, "bInterfaceSubClass") ?? 0,
                proto: IOReg.int(child, "bInterfaceProtocol") ?? 0
            ))
        }
        return interfaces
    }

    private static func fallbackName(vendorID: Int?, productID: Int?) -> String {
        guard let vendorID, let productID else { return "USB device" }
        return String(format: "USB device %04X:%04X", vendorID, productID)
    }

    // MARK: Thunderbolt / USB4

    private static func thunderboltDevice(_ service: io_service_t) -> ConnectedDevice? {
        // Depth 0 is the Mac's own Thunderbolt controller; anything deeper is plugged in.
        guard let depth = IOReg.int(service, "Depth"), depth > 0 else { return nil }

        return ConnectedDevice(
            id: IOReg.entryID(service),
            bus: .thunderbolt,
            name: IOReg.string(service, "Device Model Name") ?? "Thunderbolt device",
            vendor: IOReg.string(service, "Device Vendor Name"),
            kind: .thunderbolt,
            speed: nil,
            upstreamHub: nil,
            warning: nil
        )
    }
}
