import AppKit
import QuotaBarCore

@MainActor
enum MenuBarIcon {
    static let size = NSSize(width: 24, height: 24)
    private static let openAI = Bundle.main.url(forResource: "openai-blossom", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }
    private static let claude = Bundle.main.url(forResource: "claude-spark", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }
    static var hasOpenAIArtwork: Bool { openAI != nil }
    static var hasClaudeArtwork: Bool { claude != nil }

    static func image(states: [ProviderDisplayState], mode: MenuBarMode = .concentric, now: Date = Date()) -> NSImage {
        let combined = mode == .concentric || mode == .semicircles
        let allOff = mode.providers.allSatisfy { provider in states.first(where: { $0.provider == provider })?.isInactive == true }
        let renderedMode: MenuBarMode = combined && allOff ? .iconOnly : mode
        let image = NSImage(size: size, flipped: false) { _ in
            let values = Dictionary(uniqueKeysWithValues: states.map { ($0.provider, $0.meterValue(at: now)) })
            func ring(_ provider: ProviderKind, radius: CGFloat, start: CGFloat = 90,
                      span: CGFloat = 360, clockwise: Bool = true) {
                guard states.first(where: { $0.provider == provider })?.isInactive != true else { return }
                drawRing(value: values[provider] ?? nil, radius: radius, start: start, span: span, clockwise: clockwise)
            }
            switch renderedMode {
            case .concentric:
                ring(.claude, radius: 10.7)
                ring(.codex, radius: 7.8)
                drawQuotaMark(diameter: 8)
            case .semicircles:
                ring(.claude, radius: 10.7, start: 96, span: 168, clockwise: false)
                ring(.codex, radius: 10.7, start: 84, span: 168)
                drawQuotaMark(diameter: 12)
            case .claude, .codex:
                let provider: ProviderKind = mode == .claude ? .claude : .codex
                ring(provider, radius: 10.7)
                if provider == .claude {
                    (claude ?? NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude"))?
                        .draw(in: NSRect(x: 4.5, y: 4.5, width: 15, height: 15))
                } else {
                    (openAI ?? NSImage(systemSymbolName: "brain", accessibilityDescription: "Codex"))?
                        .draw(in: NSRect(x: 1, y: 1, width: 22, height: 22))
                }
            case .iconOnly:
                drawQuotaMark(diameter: 18)
            }
            if states.contains(where: { mode.providers.contains($0.provider) && !$0.isInactive && $0.errorMessage != nil }) {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 21, y: 0, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    nonisolated private static func drawRing(value: Double?, radius: CGFloat, start: CGFloat, span: CGFloat, clockwise: Bool) {
        let direction: CGFloat = clockwise ? -1 : 1
        let center = NSPoint(x: 12, y: 12)
        let track = NSBezierPath()
        track.lineWidth = 1.35
        track.appendArc(withCenter: center, radius: radius, startAngle: start,
                        endAngle: start + direction * span, clockwise: clockwise)
        NSColor.black.withAlphaComponent(value == nil ? 0.55 : 0.18).setStroke()
        if value == nil { track.setLineDash([1.4, 1.4], count: 2, phase: 0) }
        track.stroke()
        guard let value, value > 0 else { return }
        let progress = NSBezierPath()
        progress.lineWidth = 1.35; progress.lineCapStyle = .round
        progress.appendArc(withCenter: center, radius: radius, startAngle: start,
                           endAngle: start + direction * span * CGFloat(value / 100), clockwise: clockwise)
        NSColor.black.setStroke(); progress.stroke()
    }

    // Monochrome version of the app's Q-shaped quota ring, without its square.
    nonisolated private static func drawQuotaMark(diameter: CGFloat) {
        let radius = diameter * 0.36
        let mark = NSBezierPath(ovalIn: NSRect(x: 12 - radius, y: 12 - radius, width: radius * 2, height: radius * 2))
        mark.lineWidth = max(1, diameter * 0.13)
        NSColor.black.setStroke(); mark.stroke()
        let tail = NSBezierPath()
        tail.lineWidth = mark.lineWidth; tail.lineCapStyle = .round
        tail.move(to: NSPoint(x: 12 + radius * 0.65, y: 12 - radius * 0.65))
        tail.line(to: NSPoint(x: 12 + radius * 1.1, y: 12 - radius * 1.1))
        tail.stroke()
    }
}
