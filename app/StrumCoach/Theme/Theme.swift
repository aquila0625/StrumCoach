import SwiftUI

/// 设计令牌。数值来自 design/parts1.js 的 THEMES 和 design/screens.css 的 :root / .light。
struct Theme {
    let isLight: Bool
    let bg: Color
    let card: Color
    let card2: Color
    let line: Color
    let text: Color
    let sub: Color
    let dim: Color
    let accent: Color
    /// 次强拍方块
    let accent2: Color
    let accentSoft: Color
    let accentTint: Color
    let weak: Color
    let tick: Color
    let track: Color
    let green: Color
    let tabBg: Color
    let tabBorder: Color
    let sheet: Color
    /// 面板里的卡片底色（.sheet{--card:var(--sheetcard)}）
    let sheetCard: Color
    let highlight: Color
    let toggleOff: Color
    /// 弱拍正在响时的方块颜色
    let weakNow: Color
    let scrim: Color
    let knobStroke: Color
    /// 浅色主题卡片的柔和投影
    let cardShadow: Bool
    /// 播放键和当前拍的橙色光晕（深浅色都用深色主题的橙）
    let glow = Color(hex: 0xFF7A1A)

    static let dark = Theme(
        isLight: false,
        bg: Color(hex: 0x0E0F12), card: Color(hex: 0x1A1C21), card2: Color(hex: 0x22252B), line: Color(hex: 0x2A2D34),
        text: Color(hex: 0xF5F5F7), sub: Color(hex: 0x8E8E93), dim: Color(hex: 0x5A5D66),
        accent: Color(hex: 0xFF7A1A), accent2: Color(hex: 0xFF7A1A, alpha: 0.6),
        accentSoft: Color(hex: 0xFF7A1A, alpha: 0.35), accentTint: Color(hex: 0xFF7A1A, alpha: 0.10),
        weak: Color(hex: 0x3A3D45), tick: Color(hex: 0x33363D), track: Color(hex: 0x23262C), green: Color(hex: 0x34C759),
        tabBg: Color(hex: 0x141519, alpha: 0.96), tabBorder: Color(hex: 0x2A2D34),
        sheet: Color(hex: 0x17191D), sheetCard: Color(hex: 0x1A1C21), highlight: Color(white: 1, opacity: 0.06),
        toggleOff: Color(hex: 0x39393D), weakNow: Color(hex: 0x7A7F8C), scrim: Color(white: 0, opacity: 0.55),
        knobStroke: .clear, cardShadow: false
    )

    static let light = Theme(
        isLight: true,
        bg: Color(hex: 0xF5F4F2), card: Color(white: 1, opacity: 0.80), card2: Color(hex: 0xEDEBE8), line: Color(hex: 0xE4E1DD),
        text: Color(hex: 0x16171A), sub: Color(hex: 0x6E6E73), dim: Color(hex: 0xA6A4A0),
        accent: Color(hex: 0xF26B0F), accent2: Color(hex: 0xF26B0F, alpha: 0.55),
        accentSoft: Color(hex: 0xF26B0F, alpha: 0.28), accentTint: Color(hex: 0xF26B0F, alpha: 0.09),
        weak: Color(hex: 0xD8D5D0), tick: Color(hex: 0xDCD9D4), track: Color(hex: 0xECEAE6), green: Color(hex: 0x28A745),
        tabBg: Color(hex: 0xFFFCF8, alpha: 0.72), tabBorder: Color(white: 0, opacity: 0.06),
        sheet: Color(hex: 0xFFFFFF), sheetCard: Color(hex: 0xF3F1EE), highlight: Color(white: 0, opacity: 0.05),
        toggleOff: Color(hex: 0xE3E1DD), weakNow: Color(hex: 0xA8A49D), scrim: Color(hex: 0x141414, alpha: 0.28),
        knobStroke: Color(white: 0, opacity: 0.14), cardShadow: true
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.dark
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 根据系统深浅色注入主题。
struct ThemeProvider: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        // 弹出的页面（sheet）有自己的背景，不在 iPad 放大列里
        content.environment(\.theme, scheme == .light ? .light : .dark)
            .environment(\.inPadColumn, false)
    }
}

private struct InPadColumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 在 iPad 放大列（PadScaled）里：页面背景由外层铺满整屏，列里不再画，免得出现接缝。
    var inPadColumn: Bool {
        get { self[InPadColumnKey.self] }
        set { self[InPadColumnKey.self] = newValue }
    }
}

/// 页面背景。浅色主题是暖白渐变 + 右上、左下两角的橙色光晕（screens.css 末尾）。
struct ScreenBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.inPadColumn) private var inPadColumn

    var body: some View {
        if inPadColumn {
            Color.clear
        } else if theme.isLight {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0xFCF9F5), location: 0),
                        .init(color: Color(hex: 0xF4F0EB), location: 0.55),
                        .init(color: Color(hex: 0xF1ECE6), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    // radial-gradient(130% 50% at 100% 0%, rgba(255,163,102,.30) 0%, transparent 62%)
                    EllipseGlow(color: Color(hex: 0xFFA366), opacity: 0.30, rx: 1.3 * w, ry: 0.5 * h, stop: 0.62)
                        .position(x: w, y: 0)
                    // radial-gradient(110% 45% at 0% 100%, rgba(255,206,160,.38) 0%, transparent 60%)
                    EllipseGlow(color: Color(hex: 0xFFCEA0), opacity: 0.38, rx: 1.1 * w, ry: 0.45 * h, stop: 0.60)
                        .position(x: 0, y: h)
                }
            }
            .ignoresSafeArea()
        } else {
            theme.bg.ignoresSafeArea()
        }
    }
}

/// 椭圆形径向渐变：中心不透明，到 `stop` 处完全透明。
private struct EllipseGlow: View {
    let color: Color
    let opacity: Double
    let rx: CGFloat
    let ry: CGFloat
    let stop: CGFloat

    var body: some View {
        RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0, endRadius: rx * stop)
            .frame(width: rx * 2, height: rx * 2)
            .scaleEffect(x: 1, y: ry / rx)
            .frame(width: rx * 2, height: ry * 2)
            .allowsHitTesting(false)
    }
}

/// 卡片底：浅色主题加上设计稿里的两层暖色投影。
struct CardBackground: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat
    var fill: Color?
    var border: Bool = false

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(fill ?? theme.card)
                .overlay {
                    if border {
                        shape.strokeBorder(theme.isLight ? Color.white.opacity(0.9) : theme.line, lineWidth: 1)
                    }
                }
                .shadow(color: theme.cardShadow ? Color(hex: 0x5A3714, alpha: 0.05) : .clear, radius: 1, y: 1)
                .shadow(color: theme.cardShadow ? Color(hex: 0x5A3714, alpha: 0.06) : .clear, radius: 11, y: 8)
        }
    }
}

extension View {
    func card(radius: CGFloat, fill: Color? = nil, border: Bool = false) -> some View {
        modifier(CardBackground(radius: radius, fill: fill, border: border))
    }
}
