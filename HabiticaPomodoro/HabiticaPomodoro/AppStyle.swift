import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Visual styles (user-switchable, Mac first)

enum AppUIStyle: String, CaseIterable, Identifiable {
    case mint
    case garden
    case studio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mint: return "清新原生"
        case .garden: return "留白花园"
        case .studio: return "效率工作台"
        }
    }

    var tagline: String {
        switch self {
        case .mint: return "紧凑、有序，日常好用"
        case .garden: return "安静、舒展，专注优先"
        case .studio: return "专注与任务并排"
        }
    }

    var symbol: String {
        switch self {
        case .mint: return "leaf"
        case .garden: return "camera.macro"
        case .studio: return "rectangle.split.2x1"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .mint, .garden: return CGSize(width: 470, height: 820)
        case .studio: return CGSize(width: 820, height: 540)
        }
    }
}

final class UIStyleStore: ObservableObject {
    static let shared = UIStyleStore()
    private static let storageKey = "app.uiStyle.v1"

    @Published var style: AppUIStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.storageKey) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        style = AppUIStyle(rawValue: raw) ?? .mint
    }
}

// MARK: - Palette

struct AppTheme {
    let style: AppUIStyle
    let dark: Bool

    let background: Color
    let surface: Color
    let subtle: Color
    let line: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let accentSoft: Color
    let onAccent: Color

    init(style: AppUIStyle, dark: Bool) {
        self.style = style
        self.dark = dark
        let p: Palette
        switch style {
        case .mint:   p = dark ? .mintDark   : .mintLight
        case .garden: p = dark ? .gardenDark : .gardenLight
        case .studio: p = dark ? .studioDark : .studioLight
        }
        background = Color(appHex: p.background)
        surface = Color(appHex: p.surface)
        subtle = Color(appHex: p.subtle)
        line = Color(appHex: p.line)
        ink = Color(appHex: p.ink)
        muted = Color(appHex: p.muted)
        accent = Color(appHex: p.accent)
        accentSoft = Color(appHex: p.accentSoft)
        onAccent = Color(appHex: p.onAccent)
    }

    private struct Palette {
        let background: UInt32
        let surface: UInt32
        let subtle: UInt32
        let line: UInt32
        let ink: UInt32
        let muted: UInt32
        let accent: UInt32
        let accentSoft: UInt32
        let onAccent: UInt32

        static let mintLight = Palette(background: 0xFBFCF9, surface: 0xFFFFFF, subtle: 0xF0F4EC,
                                       line: 0xDCE5D8, ink: 0x263A31, muted: 0x627166,
                                       accent: 0x2D7055, accentSoft: 0xE4EEE1, onAccent: 0xFFFFFF)
        static let mintDark = Palette(background: 0x111B16, surface: 0x1B2A22, subtle: 0x22362A,
                                      line: 0x38503E, ink: 0xEDF3E9, muted: 0xB7C8B7,
                                      accent: 0xA9D6B1, accentSoft: 0x2A4330, onAccent: 0x15271B)
        static let gardenLight = Palette(background: 0xF9F9F1, surface: 0xFCFCF6, subtle: 0xF0F1E7,
                                         line: 0xDCE1CE, ink: 0x38432F, muted: 0x68725E,
                                         accent: 0x576F48, accentSoft: 0xE8EDD9, onAccent: 0xFFFFFF)
        static let gardenDark = Palette(background: 0x151A13, surface: 0x1E251B, subtle: 0x262E22,
                                        line: 0x3C4636, ink: 0xEDF1E4, muted: 0xBAC4AE,
                                        accent: 0xB7CDA5, accentSoft: 0x2E3A28, onAccent: 0x17200F)
        static let studioLight = Palette(background: 0xFCFDFA, surface: 0xFFFFFF, subtle: 0xF0F4EE,
                                         line: 0xDDE5DD, ink: 0x263B35, muted: 0x607269,
                                         accent: 0x286C61, accentSoft: 0xE4EEE7, onAccent: 0xFFFFFF)
        static let studioDark = Palette(background: 0x0F1A17, surface: 0x182622, subtle: 0x20332C,
                                        line: 0x35504A, ink: 0xEDF4EF, muted: 0xAFC6BF,
                                        accent: 0xA5D3C6, accentSoft: 0x27443C, onAccent: 0x0E211C)
    }
}

extension Color {
    /// Opaque sRGB color from 0xRRGGBB.
    init(appHex: UInt32) {
        let r = Double((appHex >> 16) & 0xFF) / 255
        let g = Double((appHex >> 8) & 0xFF) / 255
        let b = Double(appHex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Theme environment (shared views opt into the active style)

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme(style: .mint, dark: false)
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Reusable pieces

struct ThemeCard: ViewModifier {
    let theme: AppTheme
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func themeCard(_ theme: AppTheme, padding: CGFloat = 14) -> some View {
        modifier(ThemeCard(theme: theme, padding: padding))
    }
}

struct PrimaryActionStyle: ButtonStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.accent.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

struct QuietButtonStyle: ButtonStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(theme.ink)
            .frame(minHeight: 34)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(configuration.isPressed ? theme.subtle : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
            )
    }
}

struct RingTimer: View {
    let progress: Double
    let text: String
    let caption: String
    let theme: AppTheme
    var size: CGFloat = 214

    private var lineWidth: CGFloat { theme.style == .garden ? 2.5 : 3.5 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: progress)
            VStack(spacing: 6) {
                Text(text)
                    .font(.system(size: size * 0.28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(theme.ink)
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

/// Resizes the hosting window when the user switches between compact and wide styles.
#if os(macOS)
struct WindowSizeConfigurator: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let current = window.contentView?.bounds.size ?? .zero
            guard abs(current.width - size.width) > 1 || abs(current.height - size.height) > 1 else { return }
            window.setContentSize(size)
            window.center()
        }
    }
}
#endif
