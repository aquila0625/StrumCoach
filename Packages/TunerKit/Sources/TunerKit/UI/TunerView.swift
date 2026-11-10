import SwiftUI

/// 调音器界面（对应设计稿画面 04）：表盘、音名、乐器选择、弦按钮、标准音、参考音。
///
/// 标签栏等 App 外壳不在这里；设置按钮通过 `onSettings` 交给 App 处理。
public struct TunerView: View {
    @Bindable private var model: TunerModel
    private let palette: TunerPalette
    private let strings: TunerStrings
    private let autoStart: Bool
    private let onSettings: (() -> Void)?

    @State private var referenceOctave = 4
    @State private var showSettingsPanel = false
    @Environment(\.openURL) private var openURL
    @Environment(\.noteNaming) private var naming

    public init(model: TunerModel,
                palette: TunerPalette = .dark,
                strings: TunerStrings = .current,
                autoStart: Bool = true,
                onSettings: (() -> Void)? = nil) {
        self.model = model
        self.palette = palette
        self.strings = strings
        self.autoStart = autoStart
        self.onSettings = onSettings
    }

    /// 界面内容（不含滚动容器）；单独拿出来是为了测试里能用 ImageRenderer 截图。
    var content: some View {
        VStack(spacing: 0) {
            topBar
            instrumentPickers
            permissionBanner
            TunerGauge(cents: model.result?.cents, palette: palette, strings: strings)
                .padding(.horizontal, 20)
                .padding(.top, 6)
            readout
            if !model.tuning.isChromatic { stringRow }
            a4Card
            referenceSection
        }
        .padding(.bottom, 24)
    }

    public var body: some View {
        ScrollView { content }
        .scrollBounceBehavior(.basedOnSize)
        .background(palette.background.ignoresSafeArea())
        .foregroundStyle(palette.text)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: model.tunedEventCount)
        .task { if autoStart { await model.start() } }
        .onDisappear { if autoStart { model.stop() } }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack {
            Text(strings.title).font(.system(size: 34, weight: .bold))
            Spacer()
            // 右上角的设置：App 传了 onSettings 就交给 App（App 的设置页里可以放 `TunerChimeToggle`）；
            // 没传就弹出包自带的小面板，里面有“调准提示音”开关
            Button {
                if let onSettings { onSettings() } else { showSettingsPanel = true }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(palette.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings.settings)
            .popover(isPresented: $showSettingsPanel, arrowEdge: .top) {
                TunerChimeToggle(model: model, palette: palette, strings: strings)
                    .padding(16)
                    .frame(minWidth: 280)
                    .presentationCompactAdaptation(.popover)
                    .background(palette.background)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: 乐器与定弦

    private var instrumentPickers: some View {
        VStack(spacing: 10) {
            // 乐器：一排带图标的按钮，可左右滑动
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InstrumentLibrary.all) { inst in
                        let on = inst.id == model.instrument.id
                        Button {
                            if model.playingReference != nil { model.stopReference() }
                            model.select(instrument: inst)
                        } label: {
                            VStack(spacing: 4) {
                                InstrumentIcon(inst.family, color: on ? palette.onAccent : palette.text, size: 38)
                                Text(strings.name(inst))
                                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                    .foregroundStyle(on ? palette.onAccent : palette.sub)
                            }
                            .frame(width: 70, height: 70)
                            .background(on ? palette.accent : palette.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(strings.name(inst))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            if model.instrument.tunings.count > 1 {
                Menu {
                    ForEach(model.instrument.tunings) { t in
                        Button {
                            model.select(tuning: t)
                        } label: {
                            if t.id == model.tuning.id {
                                Label(strings.name(t), systemImage: "checkmark")
                            } else { Text(strings.name(t)) }
                        }
                    }
                } label: {
                    chip(title: strings.tuningLabel, value: strings.name(model.tuning))
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 14)
    }

    private func chip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11)).foregroundStyle(palette.sub)
                Text(value).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.sub)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(palette.text)
    }

    // MARK: 权限

    @ViewBuilder private var permissionBanner: some View {
        if model.permission == .denied {
            HStack {
                Image(systemName: "mic.slash")
                Text(strings.micDenied).font(.system(size: 14))
                Spacer()
                #if os(iOS)
                Button(strings.openSettings) {
                    if let url = URL(string: "app-settings:") { openURL(url) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                #endif
            }
            .padding(14)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20).padding(.top, 12)
        }
    }

    // MARK: 读数

    private var shown: PitchReading? { model.reading ?? model.lastReading }
    private var live: Bool { model.reading != nil }

    private var readout: some View {
        let result = model.result
        let target = result?.target ?? shown?.pitch
        let inTune = result?.isInTune ?? false
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 2) {
                Text(target.map { naming.name($0) } ?? "–")
                    .font(.system(size: 96, weight: .light))
                    .minimumScaleFactor(0.6)
                if let target {
                    Text("\(target.octave)")
                        .font(.system(size: 28, weight: .regular).monospacedDigit())
                        .foregroundStyle(palette.sub)
                        .padding(.top, 8)
                }
            }
            .frame(height: 104)
            .opacity(live ? 1 : 0.35)

            Text(statusText(result))
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(inTune ? palette.green : (live ? palette.text : palette.sub))
                .tunedPulse(trigger: model.tunedEventCount, color: palette.green)
                .padding(.top, 6)
            Text(live ? "\((model.reading?.frequency ?? 0).formatted(.number.precision(.fractionLength(1)).locale(L10n.locale))) Hz" : " ")
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(palette.sub)
                .padding(.top, 6)
        }
        .padding(.top, -6)
        .animation(.easeOut(duration: 0.15), value: inTune)
        .accessibilityElement(children: .combine)
    }

    private func statusText(_ r: TuningResult?) -> String {
        guard let r else { return model.isRunning ? strings.listening : strings.micOff }
        let c = Int(r.cents.rounded())
        let sign = c > 0 ? "+" : (c < 0 ? "−" : "")
        let tail = r.isInTune ? strings.inTune : (r.isFlat ? strings.flat : strings.sharp)
        return "\(sign)\(abs(c)) \(strings.cents) · \(tail)"
    }

    // MARK: 弦按钮

    private var stringRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.stringsHeader)
                .font(.system(size: 13)).foregroundStyle(palette.sub)
                .padding(.horizontal, 20)
            HStack(spacing: 6) {
                ForEach(model.tuning.strings) { s in stringButton(s) }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
    }

    private func stringButton(_ s: InstrumentString) -> some View {
        let isTarget = model.result?.stringIndex == s.index
        let isLocked = model.lockedString == s.index
        let tuned = model.tunedStrings.contains(s.index)
        let highlighted = isTarget || isLocked
        return Button {
            model.lockString(s.index)
        } label: {
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(naming.name(s.pitch)).font(.system(size: 19, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(s.pitch.octave)").font(.system(size: 10).monospacedDigit()).opacity(0.7)
                }
                Text("\(s.number)").font(.system(size: 10).monospacedDigit()).opacity(0.55)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(highlighted ? palette.onAccent : (tuned ? palette.green : palette.text))
            .background(highlighted ? palette.accent : palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if tuned {
                    TunedCheckmark(fill: highlighted ? palette.onAccent : palette.green,
                                   mark: highlighted ? palette.accent : .white, size: 17)
                        .padding(4)
                } else if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.onAccent)
                        .padding(5)
                }
            }
            .overlay(alignment: .topLeading) {
                if tuned && isLocked {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(palette.onAccent).padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings.stringLabel(s.number, naming.fullName(s.pitch)))
        .accessibilityValue([tuned ? strings.inTune : nil, isLocked ? strings.locked : nil]
            .compactMap { $0 }.joined(separator: "，"))
    }

    // MARK: 标准音

    private var a4Card: some View {
        HStack {
            (Text("\(strings.referenceA4) ") + Text("\(naming.fullName(Pitch(midi: 69))) = \(Int(model.a4)) Hz").bold().monospacedDigit())
                .font(.system(size: 15))
            Spacer()
            HStack(spacing: 8) {
                roundButton("minus", enabled: model.a4 > TunerDefaults.a4Range.lowerBound) { model.adjustA4(by: -1) }
                roundButton("plus", enabled: model.a4 < TunerDefaults.a4Range.upperBound) { model.adjustA4(by: 1) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(palette.card2, in: Circle())
                .foregroundStyle(enabled ? palette.text : palette.dim)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 参考音

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.referencePitch).font(.system(size: 13)).foregroundStyle(palette.sub)
                Spacer()
                if model.tuning.isChromatic {
                    HStack(spacing: 6) {
                        Text("\(strings.octave) \(referenceOctave)")
                            .font(.system(size: 13).monospacedDigit()).foregroundStyle(palette.sub)
                        smallStepper("minus", enabled: referenceOctave > 1) { referenceOctave -= 1 }
                        smallStepper("plus", enabled: referenceOctave < 7) { referenceOctave += 1 }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(referencePitches, id: \.self) { p in
                    let on = model.playingReference == p
                    Button { model.toggleReference(p) } label: {
                        VStack(spacing: 0) {
                            Text(naming.name(p))
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.55)
                            if !model.tuning.isChromatic {
                                Text("\(p.octave)").font(.system(size: 10).monospacedDigit()).opacity(0.6)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(on ? palette.onAccent : palette.text)
                        .background(on ? palette.accent : palette.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.referenceLabel(naming.fullName(p)))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var referencePitches: [Pitch] {
        if model.tuning.isChromatic {
            return [0, 2, 4, 5, 7, 9, 11].map { Pitch(midi: (referenceOctave + 1) * 12 + $0) }
        }
        return model.tuning.strings.map(\.pitch)
    }

    private func smallStepper(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(palette.card2, in: Circle())
                .foregroundStyle(enabled ? palette.text : palette.dim)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

// MARK: - 预览

@MainActor
private func previewModel(instrument: String = "guitar", frequency: Double = 110.9) -> TunerModel {
    let m = TunerModel(selection: InstrumentSelection(instrumentID: instrument,
                                                      tuningID: InstrumentLibrary.instrument(id: instrument)!.defaultTuningID))
    m.inject(PitchReading(frequency: frequency, clarity: 0.97))
    return m
}

struct TunerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TunerView(model: previewModel(), palette: .dark, autoStart: false, onSettings: {})
                .preferredColorScheme(.dark)
                .previewDisplayName("深色 · 吉他")
            TunerView(model: previewModel(), palette: .light, autoStart: false, onSettings: {})
                .preferredColorScheme(.light)
                .previewDisplayName("浅色 · 吉他")
            TunerView(model: previewModel(instrument: "auto", frequency: 440.8), palette: .dark, autoStart: false)
                .preferredColorScheme(.dark)
                .previewDisplayName("深色 · 自动（设计稿 04）")
        }
    }
}

/// “调准提示音”开关：调准一根弦时播放“叮咚”。放进任何设置页都行；状态由 `TunerModel.tuneChimeEnabled` 保存。
public struct TunerChimeToggle: View {
    @Bindable private var model: TunerModel
    private let palette: TunerPalette
    private let strings: TunerStrings

    public init(model: TunerModel, palette: TunerPalette = .dark, strings: TunerStrings = .current) {
        self.model = model
        self.palette = palette
        self.strings = strings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $model.tuneChimeEnabled) {
                Text(strings.chimeToggle).font(.system(size: 16, weight: .semibold))
            }
            .tint(palette.accent)
            Text(strings.chimeToggleHint)
                .font(.system(size: 13))
                .foregroundStyle(palette.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(palette.text)
    }
}
