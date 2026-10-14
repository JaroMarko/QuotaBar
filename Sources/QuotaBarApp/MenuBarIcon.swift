import AppKit
import CoreText
import QuotaBarCore

@MainActor
enum MenuBarIcon {
    static func size(for mode: MenuBarMode) -> NSSize {
        NSSize(width: mode == .semicircles ? 32 : 24, height: 24)
    }
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
        let imageSize = size(for: mode)
        let centerX = imageSize.width / 2
        let image = NSImage(size: imageSize, flipped: false) { _ in
            let values = Dictionary(uniqueKeysWithValues: states.map { ($0.provider, $0.meterValue(at: now)) })
            func ring(_ provider: ProviderKind, radius: CGFloat, start: CGFloat = 90,
                      span: CGFloat = 360, clockwise: Bool = true) {
                guard states.first(where: { $0.provider == provider })?.isInactive != true else { return }
                drawRing(value: values[provider] ?? nil, radius: radius, start: start, span: span, clockwise: clockwise, centerX: centerX)
            }
            switch renderedMode {
            case .concentric:
                ring(.claude, radius: 10.7)
                ring(.codex, radius: 7.8)
                drawQuotaMark(diameter: 8, centerX: centerX)
            case .semicircles:
                ring(.claude, radius: 7.2, start: 96, span: 168, clockwise: false)
                ring(.codex, radius: 7.2, start: 84, span: 168)
                drawQuotaMark(diameter: 8, centerX: centerX)
                drawCurvedName("Claude", side: .claude, centerX: centerX)
                drawCurvedName("Codex", side: .codex, centerX: centerX)
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
                drawQuotaMark(diameter: 18, centerX: centerX)
            }
            if states.contains(where: { mode.providers.contains($0.provider) && !$0.isInactive && $0.errorMessage != nil }) {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: imageSize.width - 3, y: 0, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    nonisolated private static func drawRing(value: Double?, radius: CGFloat, start: CGFloat, span: CGFloat, clockwise: Bool, centerX: CGFloat) {
        let direction: CGFloat = clockwise ? -1 : 1
        let center = NSPoint(x: centerX, y: 12)
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

    nonisolated private static func drawCurvedName(_ text: String, side: ProviderKind, centerX: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let font = NSFont.systemFont(ofSize: 6.5, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let lines = text.map { CTLineCreateWithAttributedString(NSAttributedString(string: String($0), attributes: attributes)) }
        let widths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        let xRadius: CGFloat = 12, yRadius: CGFloat = 8, spacing: CGFloat = 0.6
        // Arc-length placement prevents letters bunching at the flatter sides.
        let start: CGFloat = side == .claude ? .pi * 1.5 : .pi / 2
        var samples: [(angle: CGFloat, distance: CGFloat)] = [(start, 0)]
        for step in 1...120 {
            let angle = start - .pi * CGFloat(step) / 120
            let previous = samples.last!
            let dx = xRadius * (cos(angle) - cos(previous.angle))
            let dy = yRadius * (sin(angle) - sin(previous.angle))
            samples.append((angle, previous.distance + hypot(dx, dy)))
        }
        let total = widths.reduce(0, +) + CGFloat(lines.count - 1) * spacing
        var cursor = (samples.last!.distance - total) / 2
        for (line, width) in zip(lines, widths) {
            let distance = cursor + width / 2
            let index = samples.firstIndex(where: { $0.distance >= distance }) ?? samples.count - 1
            let lower = samples[max(0, index - 1)], upper = samples[index]
            let fraction = upper.distance == lower.distance ? 0 : (distance - lower.distance) / (upper.distance - lower.distance)
            let angle = lower.angle + (upper.angle - lower.angle) * fraction
            context.saveGState()
            context.translateBy(x: centerX + xRadius * cos(angle), y: 12 + yRadius * sin(angle))
            context.rotate(by: atan2(-yRadius * cos(angle), xRadius * sin(angle)))
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: -width / 2, y: -font.capHeight / 2)
            CTLineDraw(line, context)
            context.restoreGState()
            cursor += width + spacing
        }
    }

    // Monochrome version of the app's Q-shaped quota ring, without its square.
    nonisolated private static func drawQuotaMark(diameter: CGFloat, centerX: CGFloat) {
        let radius = diameter * 0.36
        let mark = NSBezierPath(ovalIn: NSRect(x: centerX - radius, y: 12 - radius, width: radius * 2, height: radius * 2))
        mark.lineWidth = max(1, diameter * 0.13)
        NSColor.black.setStroke(); mark.stroke()
        let tail = NSBezierPath()
        tail.lineWidth = mark.lineWidth; tail.lineCapStyle = .round
        tail.move(to: NSPoint(x: centerX + radius * 0.65, y: 12 - radius * 0.65))
        tail.line(to: NSPoint(x: centerX + radius * 1.1, y: 12 - radius * 1.1))
        tail.stroke()
    }
}
