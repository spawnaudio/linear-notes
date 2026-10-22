import SwiftUI
import AppKit
import CoreText

/// Linear fidelity tokens: docs/Overhaul v2 - Linear Fidelity Spec.md §4.
/// Editor equivalents live in Editor/src/editor.css; update both together.
enum Palette {
    static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color { Color(nsColor: nsAdaptive(dark, light)) }
    static func nsAdaptive(_ dark: UInt32, _ light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let shell = adaptive(0x090909, 0xECECEC)
    static let canvas = adaptive(0x0F1011, 0xFCFCFD)
    static let raised = adaptive(0x141417, 0xF4F4F5)
    static let control = adaptive(0x1F2025, 0xEAEAEC)
    static let selected = adaptive(0x1E1F23, 0xDEDEDE)
    static let hover = adaptive(0x18191C, 0xE6E6E7)
    static let border = adaptive(0x232429, 0xE3E3E5)
    static let divider = adaptive(0x1E2025, 0xEDEDEF)
    static let primary = adaptive(0xF7F8F8, 0x161616)
    static let body = adaptive(0xE6E7E9, 0x1C1C1E)
    static let secondary = adaptive(0xE3E4E5, 0x3C3C3F)
    static let muted = adaptive(0x959597, 0x66666A)
    static let faint = adaptive(0x5A5A5C, 0xADADAD)
    static let accent = Color(red: 94 / 255, green: 106 / 255, blue: 210 / 255)
    static let accentTint = adaptive(0x1C1E30, 0xE8EAFB)
    static let star = Color(red: 242 / 255, green: 201 / 255, blue: 76 / 255)
    static let warning = adaptive(0xF4934D, 0xC2410C)
    @MainActor static let nsPrimary = nsAdaptive(0xF7F8F8, 0x161616)
    @MainActor static let nsMuted = nsAdaptive(0x959597, 0x66666A)
    @MainActor static let nsShell = nsAdaptive(0x090909, 0xECECEC)

    // v1.3 names kept so untouched views keep compiling against the new ladder.
    static var sidebar: Color { shell }
    static var panel: Color { raised }
    static var boundary: Color { border }
    static var line: Color { border }
    static var action: Color { accent }

    /// Identity colours for the workspace tile, as small saturated marks on neutral chrome.
    static let identities: [Color] = [0x2DBED2, 0x6574EB, 0x50BD87, 0xEBC800, 0xF4934D, 0xF05B61, 0xAD7CE9].map {
        Color(red: Double(($0 >> 16) & 255) / 255, green: Double(($0 >> 8) & 255) / 255, blue: Double($0 & 255) / 255)
    }
    static func identity(for name: String) -> Color {
        identities[Int(name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % UInt32(identities.count))]
    }
}

/// Bundled Inter Variable with SF Pro as the fallback.
@MainActor enum Typeface {
    static let family = "Inter Variable"
    private static let weightAxis = 0x77676874 // 'wght'
    private static let opticalAxis = 0x6F70737A // 'opsz'
    private(set) static var available = false

    static func register() {
        guard !available else { return }
        for name in ["InterVariable", "InterVariable-Italic"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Editor/fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        available = NSFontManager.shared.availableFontFamilies.contains(family)
    }

    static func nsFont(_ size: CGFloat, _ weight: Double = 400) -> NSFont {
        if available {
            let variation: [Int: Double] = [weightAxis: weight, opticalAxis: min(32, max(14, Double(size)))]
            let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
                .addingAttributes([NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation])
            if let font = NSFont(descriptor: descriptor, size: size), font.familyName == family { return font }
        }
        return .systemFont(ofSize: size, weight: systemWeight(weight))
    }

    static func ui(_ size: CGFloat, _ weight: Double = 400) -> Font { Font(nsFont(size, weight)) }

    private static func systemWeight(_ weight: Double) -> NSFont.Weight {
        switch weight { case ..<350: .light; case ..<450: .regular; case ..<550: .medium; case ..<650: .semibold; default: .bold }
    }
}

/// Linear's quiet icon button: no fill at rest, a soft fill on hover, a ring on keyboard focus.
struct ChromeButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: size, minHeight: size)
            .background(configuration.isPressed ? Palette.control : hovering && enabled ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.4)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(focused ? Palette.accent : .clear, lineWidth: 2) }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}

/// A 16pt SF Symbol sized and weighted to sit on Linear's icon column.
struct ChromeIcon: View {
    let name: String
    var size: CGFloat = 14
    var color: Color = Palette.muted
    init(_ name: String, size: CGFloat = 14, color: Color = Palette.muted) { self.name = name; self.size = size; self.color = color }
    var body: some View {
        Image(systemName: name).font(.system(size: size, weight: .regular)).foregroundStyle(color).frame(width: 16, height: 16)
    }
}

/// The rounded-square identity tile Linear uses for workspaces and documents.
struct IdentityTile: View {
    let name: String
    var size: CGFloat = 20
    var body: some View {
        let initials = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "N" : initials)
            .font(Typeface.ui(size * 0.45, 600)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.identity(for: name), in: RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

/// SF Symbols for the editor web view, rendered once into 16pt template masks (spec §12).
/// The editor applies them as CSS masks, so they follow the theme colour like native icons.
@MainActor enum EditorSymbols {
    static let names = [
        "arrow.clockwise", "arrow.up.right", "bold", "calendar", "checklist", "chevron.down", "chevron.left.forwardslash.chevron.right",
        "chevron.right", "chevron.up", "chevron.up.chevron.down", "curlybraces", "doc.on.doc", "doc.text", "doc.text.fill", "ellipsis",
        "exclamationmark.triangle", "globe", "info.circle", "italic", "lightbulb", "link", "list.bullet", "list.number", "magnifyingglass",
        "minus", "photo", "plus", "quote.opening", "square.and.arrow.down", "strikethrough", "tablecells", "textformat", "textformat.size",
        "underline", "xmark"
    ]
    static let masks: [String: String] = {
        let canvas = NSSize(width: 16, height: 16), scale: CGFloat = 3
        var result: [String: String] = [:]
        for name in names {
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)),
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { continue }
            bitmap.size = canvas
            let fit = min(1, canvas.width / symbol.size.width, canvas.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            symbol.draw(in: NSRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
            if let png = bitmap.representation(using: .png, properties: [:]) { result[name] = "data:image/png;base64," + png.base64EncodedString() }
        }
        return result
    }()
}
