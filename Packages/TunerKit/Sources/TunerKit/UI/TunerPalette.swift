import SwiftUI

/// 调音器界面用到的颜色。App 按当前深浅主题传入对应的一份。
public struct TunerPalette: Sendable {
    public var background: Color
    public var card: Color
    public var card2: Color
    public var line: Color
    public var text: Color
    public var sub: Color
    public var dim: Color
    /// 强调色（选中的弦、未准时的指针）。
    public var accent: Color
    /// 强调色上的文字。
    public var onAccent: Color
    /// 刻度里“较弱”的小刻度。
    public var weak: Color
    /// 准音区（±5 音分）和“已准”状态。
    public var green: Color

    public init(background: Color, card: Color, card2: Color, line: Color, text: Color, sub: Color, dim: Color,
                accent: Color, onAccent: Color = .white, weak: Color, green: Color) {
        self.background = background; self.card = card; self.card2 = card2; self.line = line
        self.text = text; self.sub = sub; self.dim = dim
        self.accent = accent; self.onAccent = onAccent; self.weak = weak; self.green = green
    }

    /// 与设计稿 04 一致的深色配色。
    public static let dark = TunerPalette(
        background: Color(hex: 0x0E0F12), card: Color(hex: 0x1A1C21), card2: Color(hex: 0x22252B),
        line: Color(hex: 0x2A2D34), text: Color(hex: 0xF5F5F7), sub: Color(hex: 0x8E8E93),
        dim: Color(hex: 0x5A5D66), accent: Color(hex: 0xFF7A1A), weak: Color(hex: 0x3A3D45),
        green: Color(hex: 0x34C759))

    /// 与设计稿 light-04 一致的浅色配色。
    public static let light = TunerPalette(
        background: Color(hex: 0xF5F4F2), card: Color(hex: 0xFFFFFF), card2: Color(hex: 0xEDEBE8),
        line: Color(hex: 0xE4E1DD), text: Color(hex: 0x16171A), sub: Color(hex: 0x6E6E73),
        dim: Color(hex: 0xA6A4A0), accent: Color(hex: 0xF26B0F), weak: Color(hex: 0xD8D5D0),
        green: Color(hex: 0x28A745))
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
