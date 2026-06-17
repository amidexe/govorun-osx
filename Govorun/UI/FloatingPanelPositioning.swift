import AppKit

enum FloatingPanelPositioning {
    private static let bottomPadding: CGFloat = 24

    static func bottomCenterOrigin(windowSize: NSSize, xOffset: CGFloat = 0, on screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame
        let x = frame.midX - windowSize.width / 2 + xOffset
        let rawY = frame.minY + bottomPadding + autoHiddenBottomDockReserve(on: screen)
        let maxY = frame.maxY - windowSize.height - bottomPadding
        let y = max(frame.minY + bottomPadding, min(rawY, maxY))
        return NSPoint(x: x, y: y)
    }

    private static func autoHiddenBottomDockReserve(on screen: NSScreen) -> CGFloat {
        guard DockDefaults.isAutoHidden else { return 0 }
        guard DockDefaults.orientation == .bottom else { return 0 }
        guard screen.visibleFrame.minY <= screen.frame.minY + 1 else { return 0 }
        return DockDefaults.tileSize
    }
}

private enum DockOrientation {
    case bottom
    case left
    case right

    init(rawValue: String?) {
        switch rawValue {
        case "left":
            self = .left
        case "right":
            self = .right
        default:
            self = .bottom
        }
    }
}

private enum DockDefaults {
    static var isAutoHidden: Bool {
        defaults?.bool(forKey: "autohide") ?? false
    }

    static var orientation: DockOrientation {
        DockOrientation(rawValue: defaults?.string(forKey: "orientation"))
    }

    static var tileSize: CGFloat {
        guard let value = defaults?.object(forKey: "tilesize") as? NSNumber else {
            return 64
        }
        return max(32, min(CGFloat(value.doubleValue), 128))
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: "com.apple.dock")
    }
}
