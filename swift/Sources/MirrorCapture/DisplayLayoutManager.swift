import Foundation
import CoreGraphics
import AppKit

class DisplayLayoutManager {
    private(set) var virtualDisplayBounds: CGRect = .zero
    private(set) var totalDesktopBounds: CGRect = .zero
    private let virtualDisplayID: CGDirectDisplayID

    init(virtualDisplayID: CGDirectDisplayID) {
        self.virtualDisplayID = virtualDisplayID
        refreshLayout()
        registerForChanges()
    }

    func refreshLayout() {
        virtualDisplayBounds = CGDisplayBounds(virtualDisplayID)
        fputs("Display layout: virtual display \(virtualDisplayID) at \(virtualDisplayBounds)\n", stderr)

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        var total = CGRect.zero
        for i in 0..<Int(displayCount) {
            let bounds = CGDisplayBounds(displayIDs[i])
            total = total == .zero ? bounds : total.union(bounds)
            fputs("  Display \(displayIDs[i]): \(bounds)\n", stderr)
        }
        totalDesktopBounds = total
        fputs("  Total desktop: \(totalDesktopBounds)\n", stderr)
    }

    func absoluteToGlobal(relX: Double, relY: Double) -> CGPoint {
        let x = virtualDisplayBounds.origin.x + relX * virtualDisplayBounds.width
        let y = virtualDisplayBounds.origin.y + relY * virtualDisplayBounds.height
        return clampToVirtualDisplay(CGPoint(x: x, y: y))
    }

    func applyDelta(dx: Double, dy: Double) -> CGPoint {
        let current = NSEvent.mouseLocation
        let screenHeight = totalDesktopBounds.height
        let currentY = screenHeight - current.y
        let newX = current.x + dx
        let newY = currentY + dy
        return clampToDesktop(CGPoint(x: newX, y: newY))
    }

    func currentCursorPosition() -> CGPoint {
        let current = NSEvent.mouseLocation
        let screenHeight = totalDesktopBounds.height
        return CGPoint(x: current.x, y: screenHeight - current.y)
    }

    func virtualDisplayCenter() -> CGPoint {
        return CGPoint(x: virtualDisplayBounds.midX, y: virtualDisplayBounds.midY)
    }

    private func clampToVirtualDisplay(_ point: CGPoint) -> CGPoint {
        let x = max(virtualDisplayBounds.minX, min(virtualDisplayBounds.maxX - 1, point.x))
        let y = max(virtualDisplayBounds.minY, min(virtualDisplayBounds.maxY - 1, point.y))
        return CGPoint(x: x, y: y)
    }

    private func clampToDesktop(_ point: CGPoint) -> CGPoint {
        let x = max(totalDesktopBounds.minX, min(totalDesktopBounds.maxX - 1, point.x))
        let y = max(totalDesktopBounds.minY, min(totalDesktopBounds.maxY - 1, point.y))
        return CGPoint(x: x, y: y)
    }

    private func registerForChanges() {
        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo = userInfo else { return }
            let manager = Unmanaged<DisplayLayoutManager>.fromOpaque(userInfo).takeUnretainedValue()
            fputs("Display reconfiguration detected, refreshing layout\n", stderr)
            manager.refreshLayout()
        }, Unmanaged.passUnretained(self).toOpaque())
    }
}
