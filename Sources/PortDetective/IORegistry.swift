import Foundation
import IOKit

/// Small helpers for reading values out of the macOS I/O Registry.
///
/// Everything here is read-only and needs no special permissions or entitlements.
enum IOReg {
    static func value(_ entry: io_registry_entry_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    static func int(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        (value(entry, key) as? NSNumber)?.intValue
    }

    /// Use for values that can be negative (battery amperage), since some are stored
    /// as unsigned 64-bit numbers and need reinterpreting.
    static func int64(_ entry: io_registry_entry_t, _ key: String) -> Int64? {
        (value(entry, key) as? NSNumber)?.int64Value
    }

    static func string(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let raw = value(entry, key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func bool(_ entry: io_registry_entry_t, _ key: String) -> Bool? {
        (value(entry, key) as? NSNumber)?.boolValue
    }

    static func dictionary(_ entry: io_registry_entry_t, _ key: String) -> [String: Any]? {
        value(entry, key) as? [String: Any]
    }

    static func entryID(_ entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }

    /// Finds a live service by its registry entry ID. Returns 0 if it is gone.
    /// The caller must `IOObjectRelease` a non-zero result.
    static func service(withEntryID id: UInt64) -> io_service_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
    }

    /// Calls `body` for every object in the iterator, releasing each one afterwards.
    /// Draining an IOKit notification iterator is also what re-arms the notification.
    static func drain(_ iterator: io_iterator_t, _ body: (io_object_t) -> Void) {
        var object = IOIteratorNext(iterator)
        while object != 0 {
            body(object)
            IOObjectRelease(object)
            object = IOIteratorNext(iterator)
        }
    }

    /// Visits every descendant of `entry` in the IOService plane.
    static func forEachDescendant(of entry: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryEntryCreateIterator(entry, kIOServicePlane, options, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        drain(iterator, body)
    }

    /// Walks up the IOService plane and reads a value from the nearest ancestor
    /// of the given class (for example, the hub a USB device is plugged into).
    static func firstAncestor<T>(
        of entry: io_registry_entry_t,
        conformingTo className: String,
        maxDepth: Int = 10,
        read: (io_registry_entry_t) -> T?
    ) -> T? {
        var current: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &current) == KERN_SUCCESS else {
            return nil
        }
        for _ in 0..<maxDepth {
            if IOObjectConformsTo(current, className) != 0 {
                let result = read(current)
                IOObjectRelease(current)
                return result
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else { return nil }
            current = parent
        }
        IOObjectRelease(current)
        return nil
    }
}
