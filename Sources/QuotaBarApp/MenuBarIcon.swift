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

    static func image(states: [ProviderDisplayState], mode: MenuBarMode = .concentric, showsCenterMark: Bool = true, now: Date = Date(), appearance: NSAppearance? = nil) -> NSImage {
        let combined = mode.providers.count > 1
        let allOff = mode.providers.allSatisfy { provider in states.first(where: { $0.provider == provider })?.isInactive == true }
        let renderedMode: MenuBarMode = combined && allOff ? .iconOnly : mode
        let coloured = renderedMode.providers.count > 1
        let expanded = coloured && !showsCenterMark
        let dark = (appearance ?? NSApplication.shared.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink = coloured && dark ? NSColor.white : NSColor.black
        let image = NSImage(size: size, flipped: false) { _ in
            let values = Dictionary(uniqueKeysWithValues: states.map { ($0.provider, $0.meterValue(at: now)) })
            func ring(_ provider: ProviderKind, radius: CGFloat, start: CGFloat = 90,
                      span: CGFloat = 360, clockwise: Bool = true) {
                guard states.first(where: { $0.provider == provider })?.isInactive != true else { return }
                drawRing(value: values[provider] ?? nil, radius: radius, start: start, span: span, clockwise: clockwise,
                         lineWidth: expanded ? 2.4 : 1.35, colour: coloured ? providerColour(provider, dark: dark) : ink, ink: ink)
            }
            switch renderedMode {
            case .concentric:
                ring(.claude, radius: expanded ? 10.3 : 10.7)
                ring(.codex, radius: expanded ? 6.8 : 7.8)
                ring(.gemini, radius: expanded ? 3.3 : 4.9)
                if showsCenterMark { drawQuotaMark(diameter: 5, ink: ink) }
            case .semicircles:
                ring(.claude, radius: 10.7, start: 96, span: 168, clockwise: false)
                ring(.codex, radius: 10.7, start: 84, span: 168)
                if showsCenterMark { drawQuotaMark(diameter: 12, ink: ink) }
            case .columns:
                for (index, provider) in mode.providers.enumerated() {
                    guard states.first(where: { $0.provider == provider })?.isInactive != true else { continue }
                    let bounds = NSRect(x: CGFloat(2 + index * 7), y: 3, width: 6, height: 18)
                    let track = NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5)
                    guard let used = values[provider] ?? nil else {
                        ink.withAlphaComponent(0.55).setStroke()
                        track.lineWidth = 0.8
                        track.setLineDash([1.5, 1.5], count: 2, phase: 0)
                        track.stroke()
                        continue
                    }
                    ink.withAlphaComponent(0.18).setFill()
                    track.fill()
                    let height = bounds.height * used / 100
                    NSGraphicsContext.saveGraphicsState()
                    track.addClip()
                    providerColour(provider, dark: dark).setFill()
                    NSRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            case .gemini:
                ring(.gemini, radius: 10.7)
                NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Gemini")?
                    .draw(in: NSRect(x: 5, y: 5, width: 14, height: 14))
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
                drawQuotaMark(diameter: 18, ink: ink)
            }
            if states.contains(where: { mode.providers.contains($0.provider) && !$0.isInactive && $0.errorMessage != nil }) {
                ink.setFill()
                NSBezierPath(ovalIn: NSRect(x: 21, y: 0, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = !coloured
        return image
    }

    nonisolated static func providerColour(_ provider: ProviderKind, dark: Bool = false) -> NSColor {
        if provider == .gemini { return dark ? .systemPink : .systemPurple }
        return provider == .claude
            ? NSColor(srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1)
            : (dark
                ? NSColor(srgbRed: 103.0 / 255, green: 232.0 / 255, blue: 249.0 / 255, alpha: 1)
                : NSColor(srgbRed: 8.0 / 255, green: 145.0 / 255, blue: 178.0 / 255, alpha: 1))
    }

    nonisolated private static func drawRing(value: Double?, radius: CGFloat, start: CGFloat, span: CGFloat, clockwise: Bool, lineWidth: CGFloat, colour: NSColor, ink: NSColor) {
        let direction: CGFloat = clockwise ? -1 : 1
        let center = NSPoint(x: 12, y: 12)
        let track = NSBezierPath()
        track.lineWidth = lineWidth
        track.appendArc(withCenter: center, radius: radius, startAngle: start,
                        endAngle: start + direction * span, clockwise: clockwise)
        ink.withAlphaComponent(value == nil ? 0.55 : 0.18).setStroke()
        if value == nil { track.setLineDash([1.4, 1.4], count: 2, phase: 0) }
        track.stroke()
        guard let value, value > 0 else { return }
        let progress = NSBezierPath()
        progress.lineWidth = lineWidth; progress.lineCapStyle = .round
        progress.appendArc(withCenter: center, radius: radius, startAngle: start,
                           endAngle: start + direction * span * CGFloat(value / 100), clockwise: clockwise)
        colour.setStroke(); progress.stroke()
    }

    // Optical small-size variant of the app's Q: taller bowl and a tail inside the letter.
    // An external handle makes a circular Q look like a magnifier at menu-bar sizes.
    nonisolated private static func drawQuotaMark(diameter: CGFloat, ink: NSColor) {
        let bowl = NSBezierPath(ovalIn: NSRect(x: 12 - diameter * 0.35, y: 12 - diameter * 0.42,
                                             width: diameter * 0.7, height: diameter * 0.84))
        bowl.lineWidth = max(1.2, diameter * 0.16)
        ink.setStroke()
        bowl.stroke()
        let tail = NSBezierPath()
        tail.lineWidth = bowl.lineWidth
        tail.lineCapStyle = .square
        tail.move(to: NSPoint(x: 12, y: 12 - diameter * 0.08))
        tail.line(to: NSPoint(x: 12 + diameter * 0.28, y: 12 - diameter * 0.38))
        tail.stroke()
    }
}
