import AppKit
import QuotaBarCore

@MainActor
enum MenuBarIcon {
    static let size = NSSize(width: 60, height: 24)
    private static let openAI = Bundle.main.url(forResource: "openai-blossom", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }
    static var hasOpenAIArtwork: Bool { openAI != nil }

    static func image(states: [ProviderDisplayState], now: Date = Date()) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            for (index, kind) in [ProviderKind.claude, .codex].enumerated() {
                let state = states.first { $0.provider == kind }
                let value = state?.meterValue(at: now)
                let center = NSPoint(x: 12 + CGFloat(index) * 36, y: 12)
                let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 10.9, y: 1.1, width: 21.8, height: 21.8))
                ring.lineWidth = 1.25
                NSColor.black.withAlphaComponent(value == nil ? 0.55 : 0.18).setStroke()
                if value == nil { ring.setLineDash([1.5, 1.5], count: 2, phase: 0) }
                ring.stroke()
                if let value, value > 0 {
                    let progress = NSBezierPath()
                    progress.lineWidth = 1.5; progress.lineCapStyle = .round
                    progress.appendArc(withCenter: center, radius: 10.9, startAngle: 90,
                                       endAngle: 90 - CGFloat(value) * 3.6, clockwise: true)
                    NSColor.black.setStroke(); progress.stroke()
                }
                if kind == .claude {
                    drawClawd(center: center)
                } else if let logo = openAI {
                    // The official SVG includes its clear space. Draw its full
                    // canvas at 22pt so the actual knot is visually ~17pt wide.
                    logo.draw(in: NSRect(x: center.x - 11, y: 1, width: 22, height: 22))
                } else {
                    NSImage(systemSymbolName: "brain", accessibilityDescription: "Codex")?
                        .draw(in: NSRect(x: center.x - 7, y: 5, width: 14, height: 14))
                }
                if state?.errorMessage != nil {
                    NSColor.black.setFill()
                    NSBezierPath(ovalIn: NSRect(x: center.x + 8, y: 0, width: 3, height: 3)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawClawd(center: NSPoint) {
        // Bold 16x14 pixel silhouette, with transparent 2pt eyes. It remains
        // recognisable at menu-bar size, unlike a scaled-down SF Symbol.
        let points: [(CGFloat, CGFloat)] = [
            (2,14),(14,14),(14,12),(16,12),(16,6),(14,6),
            (14,2),(12,2),(12,6),(10,6),(10,0),(8,0),
            (8,6),(6,6),(6,2),(4,2),(4,6),(2,6),
            (2,8),(0,8),(0,12),(2,12)
        ]
        let origin = NSPoint(x: center.x - 8, y: center.y - 7)
        let mascot = NSBezierPath()
        for (index, point) in points.enumerated() {
            let position = NSPoint(x: origin.x + point.0, y: origin.y + point.1)
            if index == 0 { mascot.move(to: position) } else { mascot.line(to: position) }
        }
        mascot.close(); mascot.windingRule = .evenOdd
        mascot.appendRect(NSRect(x: origin.x + 4, y: origin.y + 9, width: 2, height: 2))
        mascot.appendRect(NSRect(x: origin.x + 10, y: origin.y + 9, width: 2, height: 2))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        NSColor.black.setFill(); mascot.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
