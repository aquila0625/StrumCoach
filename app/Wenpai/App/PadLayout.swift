import SwiftUI
import UIKit

/// iPad 适配：界面按 iPhone 的尺寸排版，再整体放大，内容列限宽居中，背景铺满整个屏幕。
/// 这样各页面的尺寸（按设计稿写的点数）不用逐个改，在 iPad 上也不会显得太小。iPhone 上原样显示。
enum PadLayout {
    /// 按 iPhone 排版时内容列最宽多少点（放大前）。再宽卡片会被拉得太扁。
    static let maxColumnWidth: CGFloat = 560
    /// 排版至少需要的高度（设计稿 844 去掉状态栏和底部指示条后约 760，留一点余量）。
    static let designHeight: CGFloat = 800
    static let designWidth: CGFloat = 430

    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// 放大倍数：让排版高度刚好铺满屏幕，同时宽度上至少留出一个 iPhone 的宽度；限制在 1–1.7 倍。
    static func scale(for size: CGSize) -> CGFloat {
        guard isPad, size.width > 0, size.height > 0 else { return 1 }
        let k = min(size.height / designHeight, size.width / designWidth)
        return min(max(k, 1), 1.7)
    }
}

/// 把内容按 `PadLayout.scale` 放大。iPhone 上直接返回内容。
struct PadScaled<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if PadLayout.isPad {
            GeometryReader { geo in
                let k = PadLayout.scale(for: geo.size)
                let width = min(geo.size.width / k, PadLayout.maxColumnWidth)
                let height = geo.size.height / k
                content
                    .environment(\.inPadColumn, true)
                    .frame(width: width, height: height)
                    .scaleEffect(k)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(ScreenBackground())
        } else {
            content
        }
    }
}
