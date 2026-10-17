import Foundation
import CoreGraphics

public enum PanelPlacement {
    public static func shouldDismissClick(at point: CGPoint, panel: CGRect, anchor: CGRect) -> Bool {
        // The status item owns toggling. Its opening click must never be
        // mistaken for an outside click by the global monitor.
        return !panel.contains(point) && !anchor.contains(point)
    }
    public static func frame(anchor: CGRect, visible: CGRect, size: CGSize) -> CGRect {
        let gap: CGFloat = 8
        let width = min(size.width, max(1, visible.width - gap * 2))
        let height = min(size.height, max(1, visible.height - gap * 2))
        let x = max(visible.minX + gap, min(anchor.maxX - width, visible.maxX - gap - width))
        let top = min(anchor.minY - gap, visible.maxY - gap)
        let y = max(visible.minY + gap, top - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
