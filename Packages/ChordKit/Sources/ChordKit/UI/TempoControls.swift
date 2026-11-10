import SwiftUI

/// 点按 ±1、按住连续变化（越按越快）的圆形按钮。
struct RepeatStepButton: View {
    let systemName: String
    let label: String
    let palette: ChordPalette
    let action: () -> Void

    @State private var task: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .bold))
            .frame(width: 44, height: 44)
            .foregroundStyle(palette.text)
            .background(palette.card2, in: Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if task == nil { begin() } }
                    .onEnded { _ in end() }
            )
            .onDisappear { end() }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    /// 按下去先动一次（点按就是 ±1），按住超过 0.45 秒开始连续变化，间隔越来越短。
    private func begin() {
        action()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            var delay = 0.12
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = max(0.03, delay * 0.92)
            }
        }
    }

    private func end() {
        task?.cancel()
        task = nil
    }
}

/// 速度弹出层：当前 BPM、−/+（点按 ±1、长按连续变化）、滑块（30–200），以及“跟随节拍器”开关。
/// 跟随节拍器打开时，自己的速度控件变灰（实际用的是节拍器的速度）。
struct TempoPanel: View {
    let model: ChordLibraryModel
    let palette: ChordPalette
    let strings: ChordStrings

    var body: some View {
        let range = ChordLibraryModel.tempoRange
        let following = model.followsMetronome
        VStack(alignment: .leading, spacing: 14) {
            Text(strings.tempoTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.sub)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(model.effectiveBPM.rounded()))")
                    .font(.system(size: 44, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("BPM").font(.system(size: 15, weight: .medium)).foregroundStyle(palette.sub)
                Spacer()
            }
            HStack(spacing: 12) {
                RepeatStepButton(systemName: "minus", label: strings.slower, palette: palette) { model.adjustTempo(by: -1) }
                Slider(value: Binding(get: { model.tempo }, set: { model.setTempo($0) }), in: range, step: 1)
                    .tint(palette.accent)
                    .accessibilityLabel(strings.tempoTitle)
                    .accessibilityValue(strings.tempoLabel(Int(model.tempo)))
                RepeatStepButton(systemName: "plus", label: strings.faster, palette: palette) { model.adjustTempo(by: 1) }
            }
            .disabled(following)
            .opacity(following ? 0.35 : 1)
            Toggle(isOn: Binding(get: { model.followsMetronome }, set: { model.setFollowsMetronome($0) })) {
                Text(strings.followMetronome).font(.system(size: 15, weight: .medium))
            }
            .tint(palette.accent)
            if following, model.bpm != nil {
                Text(strings.followingNote(Int(model.effectiveBPM.rounded())))
                    .font(.system(size: 12)).foregroundStyle(palette.sub)
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(palette.card)
        .foregroundStyle(palette.text)
        .animation(.easeOut(duration: 0.12), value: model.effectiveBPM)
    }
}
