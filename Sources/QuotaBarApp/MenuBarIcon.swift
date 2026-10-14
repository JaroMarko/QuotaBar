import AppKit
import QuotaBarCore

@MainActor
enum MenuBarIcon {
    static let size = NSSize(width: 60, height: 24)
    private static let openAI = Bundle.main.url(forResource: "openai-blossom", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }
    private static let claude = Bundle.main.url(forResource: "claude-spark", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }
    static var hasOpenAIArtwork: Bool { openAI != nil }
    static var hasClaudeArtwork: Bool { claude != nil }

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
                    if let logo = claude {
                        logo.draw(in: NSRect(x: center.x - 7.5, y: 4.5, width: 15, height: 15))
                    } else {
                        NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude")?
                            .draw(in: NSRect(x: center.x - 7, y: 5, width: 14, height: 14))
                    }
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

}
