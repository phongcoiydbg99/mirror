import Foundation
import CoreGraphics

// CGVirtualDisplay is a private API — we dynamically load it
// Reference: https://github.com/KhaosT/CGVirtualDisplay

class VirtualDisplayManager {
    private var display: Any? = nil
    private(set) var displayID: CGDirectDisplayID = 0
    private let width: Int
    private let height: Int
    private let hiDPI: Bool

    init(width: Int, height: Int, hiDPI: Bool = true) {
        self.width = width
        self.height = height
        self.hiDPI = hiDPI
    }

    func create() throws {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type else {
            throw VirtualDisplayError.apiNotAvailable
        }

        let descriptor = descriptorClass.init()
        descriptor.setValue(width, forKey: "width")
        descriptor.setValue(height, forKey: "height")
        descriptor.setValue(60, forKey: "refreshRate")
        descriptor.setValue("Mirror Virtual Display", forKey: "name")
        descriptor.setValue(hiDPI, forKey: "hiDPI")

        // CGVirtualDisplaySettings
        guard let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
            throw VirtualDisplayError.apiNotAvailable
        }

        let settings = settingsClass.init()
        settings.setValue(hiDPI, forKey: "hiDPI")

        // CGVirtualDisplay
        guard let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            throw VirtualDisplayError.apiNotAvailable
        }

        let virtualDisplay = displayClass.init()
        let sel = NSSelectorFromString("initWithDescriptor:")
        guard virtualDisplay.responds(to: sel) else {
            throw VirtualDisplayError.apiNotAvailable
        }
        let created = virtualDisplay.perform(sel, with: descriptor)?.takeUnretainedValue() as? NSObject

        guard let createdDisplay = created else {
            throw VirtualDisplayError.creationFailed
        }

        if let id = createdDisplay.value(forKey: "displayID") as? CGDirectDisplayID {
            self.displayID = id
        }

        self.display = createdDisplay
        fputs("Virtual display created: \(width)x\(height) (ID: \(displayID))\n", stderr)
    }

    func destroy() {
        if let display = display as? NSObject {
            let sel = NSSelectorFromString("destroy")
            if display.responds(to: sel) {
                display.perform(sel)
            }
        }
        display = nil
        displayID = 0
        fputs("Virtual display destroyed\n", stderr)
    }
}

enum VirtualDisplayError: Error, CustomStringConvertible {
    case apiNotAvailable
    case creationFailed

    var description: String {
        switch self {
        case .apiNotAvailable:
            return "CGVirtualDisplay API not available. Requires macOS 14+"
        case .creationFailed:
            return "Failed to create virtual display"
        }
    }
}
