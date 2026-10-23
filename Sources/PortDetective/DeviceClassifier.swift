import Foundation

/// Works out what a USB device is.
///
/// The name is checked first, because it's the most reliable clue: an iPhone
/// also exposes audio interfaces, so going by interfaces alone would call it
/// headphones. If the name doesn't say, the USB interface classes decide.
enum DeviceClassifier {
    struct Interface: Hashable {
        var cls: Int
        var subclass: Int
        var proto: Int
    }

    static func classify(
        name: String,
        vendor: String?,
        vendorID: Int?,
        deviceClass: Int?,
        interfaces: Set<Interface>
    ) -> DeviceKind {
        let classes = Set(interfaces.map(\.cls))
        if deviceClass == 9 || classes.contains(9) { return .hub }

        // Underscores count as letters in regex word boundaries ("SAMSUNG_Android"), so swap them out.
        let text = [name, vendor ?? ""].joined(separator: " ").replacingOccurrences(of: "_", with: " ")
        if let kind = kindFromName(text, classes: classes) { return kind }
        return kindFromInterfaces(interfaces, classes: classes, vendorID: vendorID)
    }

    // MARK: Names

    private static func kindFromName(_ text: String, classes: Set<Int>) -> DeviceKind? {
        // "Camera" alone could be a webcam or a stills camera, so let the interfaces decide.
        if matches(text, cameraWord) {
            if classes.contains(14) { return .webcam }
            if classes.contains(6) { return .camera }
        }
        for rule in rules where matches(text, rule.regex) {
            return rule.kind
        }
        if matches(text, cameraWord) { return .webcam }
        return nil
    }

    private static let cameraWord = regex(#"\bcamera\b"#)

    /// Checked in order; the first match wins.
    private static let ruleSource: [(DeviceKind, String)] = [
        (.iPad, #"\bipad"#),
        (.iPhone, #"\biphone"#),
        (.securityKey, #"\b(yubikey|yubico|security key|titan key|fido|u2f|nitrokey|solokey|onlykey)\b"#),
        (.smartCardReader, #"\bsmart ?card"#),
        (.bluetooth, #"\bbluetooth\b"#),
        (.headphones, #"\b(headphones?|headset|earbuds?|earphones?|airpods|arctis|kraken|hyperx cloud|jabra|blackwire)\b"#),
        (.microphone, #"\b(microphone|mic|yeti|snowball|shure|rode|nt-usb|podmic|at2020|quadcast|seiren|fifine)\b"#),
        (.audioInterface, #"\b(scarlett|focusrite|motu|audient|presonus|apollo|steinberg|universal audio|audio interface|dac)\b"#),
        (.speaker, #"\b(speakers?|soundbar|soundlink)\b"#),
        (.webcam, #"\b(webcam|web cam|facetime|brio|c9\d\d|streamcam|kiyo|insta360|obsbot|emeet)\b"#),
        (.gameController, #"\b(controller|gamepad|joystick|dualsense|dualshock|xbox|8bitdo|joy-?con)\b"#),
        (.trackpad, #"\b(trackpad|touchpad)\b"#),
        (.keyboard, #"\b(keyboard|keychron|nuphy|hhkb|happy hacking)\b"#),
        (.mouse, #"\b(mouse|mx master|mx anywhere|deathadder|basilisk)\b"#),
        (.wirelessReceiver, #"\b(receiver|unifying|dongle|lightspeed|logi bolt)\b"#),
        (.ethernet, #"\b(ethernet|lan|gigabit|2\.5g|rtl81\d\d|ax88\d+)\b"#),
        (.cardReader, #"\b(card ?reader|sd ?reader|microsd|sdxc|multi-?card)\b"#),
        (.flashDrive, #"\b(flash|cruzer|datatraveler|jumpdrive|thumb ?drive|pen ?drive|usb ?stick|ultra fit)\b"#),
        (.drive, #"\b(ssd|nvme|hdd|hard ?drive|hard ?disk|disk|drive|my passport|my book|backup plus|one touch|lacie|sabrent)\b"#),
        (.printer, #"\b(printer|laserjet|deskjet|officejet|pixma|ecotank|labelwriter|dymo)\b"#),
        (.display, #"\b(display|displaylink|monitor|ultrafine)\b"#),
        (.phone, #"\b(android|pixel|galaxy|oneplus|xiaomi|redmi|motorola|huawei|oppo|vivo|realme|smartphone|mtp)\b"#),
        (.devBoard, #"\b(arduino|esp32|esp8266|ch34\d|cp210\d|ftdi|uart|serial|rp2040|pico|teensy|stm32)\b"#),
        (.hub, #"\b(hub|dock|docking)\b"#)
    ]

    private static let rules: [(kind: DeviceKind, regex: NSRegularExpression)] =
        ruleSource.map { (kind: $0.0, regex: regex($0.1)) }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed and tested, so a failure here is a programming error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func matches(_ text: String, _ regex: NSRegularExpression) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    // MARK: Interfaces

    private static let appleVendorID = 0x05AC
    private static let phoneVendorIDs: Set<Int> = [
        0x18D1, // Google
        0x04E8, // Samsung
        0x2717, // Xiaomi
        0x2A70, // OnePlus
        0x22B8, // Motorola
        0x12D1, // Huawei
        0x22D9, // Oppo
        0x0FCE, // Sony Mobile
        0x1004, // LG
        0x0BB4, // HTC
        0x2D95  // Vivo
    ]

    private static func kindFromInterfaces(
        _ interfaces: Set<Interface>,
        classes: Set<Int>,
        vendorID: Int?
    ) -> DeviceKind {
        if classes.contains(14) { return .webcam }                 // video
        if classes.contains(6) {                                    // still image (PTP/MTP)
            if vendorID == appleVendorID { return .iPhone }
            if let vendorID, phoneVendorIDs.contains(vendorID) { return .phone }
            return .camera
        }
        if classes.contains(8) { return .drive }                   // mass storage
        if classes.contains(7) { return .printer }
        if classes.contains(11) { return .smartCardReader }
        if interfaces.contains(where: { $0.cls == 2 && ($0.subclass == 6 || $0.subclass == 13) }) {
            return .ethernet                                        // CDC ECM / NCM
        }
        let hid = interfaces.filter { $0.cls == 3 }
        if hid.contains(where: { $0.proto == 1 }) { return .keyboard }
        if hid.contains(where: { $0.proto == 2 }) { return .mouse }
        if classes.contains(1) { return .audio }
        if !hid.isEmpty { return .inputDevice }
        if classes.contains(0xE0) { return .bluetooth }
        if classes.contains(0x11) { return .display }              // USB-C billboard (video adapters)
        if classes.contains(2) || classes.contains(10) { return .devBoard }
        if let vendorID, phoneVendorIDs.contains(vendorID), classes.contains(0xFF) { return .phone }
        return .other
    }
}
