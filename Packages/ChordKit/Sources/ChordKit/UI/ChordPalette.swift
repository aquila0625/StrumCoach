import SwiftUI
import TunerKit

/// 和弦库界面用到的颜色。App 按当前深浅主题传入对应的一份，做法与 `TunerPalette` 一致。
public struct ChordPalette: Sendable {
    public var background: Color
    public var card: Color
    public var card2: Color
    public var line: Color
    public var text: Color
    public var sub: Color
    public var dim: Color
    /// 强调色（选中的按钮、根音、试听按钮）。
    public var accent: Color
    /// 强调色上的文字。
    public var onAccent: Color
    /// 页码点里“较弱”的点、弦线之外的淡线。
    public var weak: Color
    /// 画在 `text` 色圆点上的文字（指法编号、贝斯音级）。默认等于 `background`；
    /// App 想让页面背景透明（透出自己的渐变）时单独指定。
    public var onText: Color

    public init(background: Color, card: Color, card2: Color, line: Color, text: Color, sub: Color, dim: Color,
                accent: Color, onAccent: Color = .white, weak: Color, onText: Color? = nil) {
        self.background = background; self.card = card; self.card2 = card2; self.line = line
        self.text = text; self.sub = sub; self.dim = dim
        self.accent = accent; self.onAccent = onAccent; self.weak = weak
        self.onText = onText ?? background
    }

    /// 与调音器共用一套颜色：直接把 App 手里的 `TunerPalette` 转过来。
    public init(_ tuner: TunerPalette) {
        self.init(background: tuner.background, card: tuner.card, card2: tuner.card2, line: tuner.line,
                  text: tuner.text, sub: tuner.sub, dim: tuner.dim, accent: tuner.accent,
                  onAccent: tuner.onAccent, weak: tuner.weak)
    }

    /// 与设计稿 05 一致的深色配色。
    public static let dark = ChordPalette(.dark)
    /// 与设计稿 light-05 一致的浅色配色。
    public static let light = ChordPalette(.light)
}
