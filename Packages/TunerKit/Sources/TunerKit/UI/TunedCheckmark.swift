import SwiftUI

/// 打勾的描边路径：先向下再向右上。
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.86))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.16))
        return p
    }
}

/// 调准后弹出的小对勾：圆底先弹出并缩放到位，对勾再按笔画画出来。
/// “减少动态效果”打开时只淡入（没有缩放弹跳，也没有描边动画）。
struct TunedCheckmark: View {
    var fill: Color
    var mark: Color
    var size: CGFloat = 17

    @State private var shown = false
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(fill)
            CheckShape()
                .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                .stroke(mark, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round, lineJoin: .round))
                .padding(size * 0.26)
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion || shown ? 1 : 0.2)
        .opacity(shown ? 1 : 0)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { shown = true }
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { shown = true }
                withAnimation(.easeOut(duration: 0.26).delay(0.1)) { drawn = true }
            }
        }
        .accessibilityHidden(true)
    }
}

/// “已准”状态文字的一次轻微强调：略微放大再回弹，并闪一下柔和的绿色底。
/// 减少动态效果时不缩放，只闪底色。
struct TunedPulse: ViewModifier {
    var trigger: Int
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Value { var scale = 1.0; var glow = 0.0 }

    func body(content: Content) -> some View {
        let bump = reduceMotion ? 1.0 : 1.14
        content
            .keyframeAnimator(initialValue: Value(), trigger: trigger) { view, v in
                view
                    .scaleEffect(v.scale)
                    .background(Capsule().fill(color.opacity(0.22 * v.glow)).padding(.horizontal, -12).padding(.vertical, -5))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(bump, duration: 0.14, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(1, duration: 0.12)
                    LinearKeyframe(0, duration: 0.6)
                }
            }
    }
}

extension View {
    func tunedPulse(trigger: Int, color: Color) -> some View { modifier(TunedPulse(trigger: trigger, color: color)) }
}
