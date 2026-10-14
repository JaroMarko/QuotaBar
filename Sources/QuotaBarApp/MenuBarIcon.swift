import AppKit
import QuotaBarCore

@MainActor
enum MenuBarIcon {
    static func image(states: [ProviderDisplayState], now: Date = Date()) -> NSImage {
        let image = NSImage(size: NSSize(width: 46, height: 20), flipped: false) { rect in
            for (index, kind) in [ProviderKind.claude, .codex].enumerated() {
                let state = states.first { $0.provider == kind }
                let value = state?.meterValue(at: now)
                let center = NSPoint(x: 10 + CGFloat(index) * 26, y: 10)
                let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 8, y: 2, width: 16, height: 16))
                ring.lineWidth = 1.6
                NSColor.black.withAlphaComponent(value == nil ? 0.55 : 0.2).setStroke()
                if value == nil { ring.setLineDash([1.5, 1.5], count: 2, phase: 0) }
                ring.stroke()
                if let value, value > 0 {
                    let progress = NSBezierPath()
                    progress.lineWidth = 1.8; progress.lineCapStyle = .round
                    progress.appendArc(withCenter: center, radius: 8, startAngle: 90,
                                       endAngle: 90 - CGFloat(value) * 3.6, clockwise: true)
                    NSColor.black.setStroke(); progress.stroke()
                }
                let symbol = NSImage(systemSymbolName: kind == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right",
                                     accessibilityDescription: kind.displayName)
                symbol?.draw(in: NSRect(x: center.x - 4.5, y: 5.5, width: 9, height: 9),
                             from: .zero, operation: .sourceOver, fraction: state?.isRefreshing == true ? 0.5 : 1)
                if state?.errorMessage != nil {
                    NSColor.black.setFill()
                    NSBezierPath(ovalIn: NSRect(x: center.x + 5, y: 0, width: 3, height: 3)).fill()
                }
            }
            return true
        }
        // Template rendering follows macOS menu-bar contrast in light/dark mode.
        image.isTemplate = true
        return image
    }
}
