import Foundation
import CoreGraphics

class VirtualDisplayManager {
    private var display: CGVirtualDisplay? = nil
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
        // 1. Create and configure descriptor
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "Mirror Virtual Display"
        descriptor.maxPixelsWide = UInt32(width)
        descriptor.maxPixelsHigh = UInt32(height)
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x5678
        descriptor.serialNum = 0x0001
        descriptor.setDispatchQueue(DispatchQueue.main)

        // 2. Create virtual display
        guard let virtualDisplay = CGVirtualDisplay(descriptor: descriptor) else {
            throw VirtualDisplayError.creationFailed
        }

        // 3. Create mode and settings
        guard let mode = CGVirtualDisplayMode(
            width: UInt(width),
            height: UInt(height),
            refreshRate: 60.0
        ) else {
            throw VirtualDisplayError.creationFailed
        }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = hiDPI ? 1 : 0
        settings.modes = [mode]

        // 4. Apply settings
        guard virtualDisplay.apply(settings) else {
            throw VirtualDisplayError.creationFailed
        }

        self.displayID = virtualDisplay.displayID
        self.display = virtualDisplay
        fputs("Virtual display created: \(width)x\(height) (ID: \(displayID))\n", stderr)
    }

    func destroy() {
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
