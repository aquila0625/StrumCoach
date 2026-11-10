import Accelerate
import Foundation

/// 扫弦起音检测（收音结束后对整段录音做，不在音频线程里跑）。
///
/// 1. 频谱通量：1024 点 FFT、每 256 个采样一帧，取对数幅度谱里“比上一帧变大的部分”之和；
/// 2. 自适应阈值：前后各 0.25 秒内通量的中位数 × 1.5，再加上整段最大通量的 8%（压住持续的底噪和余音）；
/// 3. 峰值：超过阈值、是前后各 3 帧里最大的；两个起音至少隔 70 毫秒；声音太小（50 毫秒内 RMS 低于 −46 dBFS）的不算；
/// 4. 精确定位：在峰值附近按约 1.3 毫秒一块算高通（一阶差分）后的能量，取第一块“明显比前面响”的位置，也就是扫弦第一根弦的起音。
///
/// 根音单拨（节奏型里的 `B`）只有一根弦，比扫弦轻得多：在“该拨根音”的时间附近（`sensitive`）用更低的阈值和音量下限，
/// 能检测到起音就算；其他位置照旧，杂音不会因此被当成起音。
struct OnsetDetector {
    var sampleRate: Double
    var frameSize = 1024
    var hop = 256
    var minInterval = 0.070
    var thresholdRatio: Float = 1.5
    var thresholdFloor: Float = 0.08
    var minimumRMS: Float = 0.005
    /// 根音单拨附近：阈值倍数、整段最大通量的比例、音量下限都放低
    var sensitiveRatio: Float = 1.2
    var sensitiveFloor: Float = 0.025
    var sensitiveRMS: Float = 0.0015

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    /// 返回起音所在的采样位置（从 0 起），按时间先后。
    /// - Parameter sensitive: 这些采样范围里（根音单拨附近）用更低的阈值。
    func detect(_ samples: [Float], sensitive: [ClosedRange<Int>] = []) -> [Int] {
        let flux = spectralFlux(samples)
        guard flux.count > 8, let maxFlux = flux.max(), maxFlux > 0 else { return [] }
        let half = max(1, Int(0.25 * sampleRate) / hop)
        let minGap = Int(minInterval * sampleRate)
        var onsets: [Int] = []
        for t in 1..<flux.count {
            // 帧的中心落在根音单拨附近就放低门槛
            let center = t * hop + frameSize / 2
            let soft = sensitive.contains { $0.contains(center) }
            let lo = max(0, t - half), hi = min(flux.count, t + half + 1)
            let threshold = median(flux[lo..<hi]) * (soft ? sensitiveRatio : thresholdRatio) + (soft ? sensitiveFloor : thresholdFloor) * maxFlux
            guard flux[t] > threshold else { continue }
            let nlo = max(0, t - 3), nhi = min(flux.count, t + 4)
            guard flux[t] == flux[nlo..<nhi].max() else { continue }
            let onset = refine(samples, aroundFrame: t)
            guard rms(samples, from: onset, length: Int(0.05 * sampleRate)) >= (soft ? sensitiveRMS : minimumRMS) else { continue }
            if let last = onsets.last, onset - last < minGap { continue }
            onsets.append(onset)
        }
        return onsets
    }

    // MARK: 频谱通量

    func spectralFlux(_ samples: [Float]) -> [Float] {
        guard samples.count >= frameSize else { return [] }
        let log2n = vDSP_Length(log2(Double(frameSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameSize, isHalfWindow: false)
        let bins = frameSize / 2
        var previous = [Float](repeating: 0, count: bins)
        var flux: [Float] = []
        var real = [Float](repeating: 0, count: bins)
        var imag = [Float](repeating: 0, count: bins)
        var frame = [Float](repeating: 0, count: frameSize)
        var magnitude = [Float](repeating: 0, count: bins)
        var start = 0
        while start + frameSize <= samples.count {
            samples.withUnsafeBufferPointer { src in
                vDSP.multiply(UnsafeBufferPointer(rebasing: src[start..<start + frameSize]), window, result: &frame)
            }
            real.withUnsafeMutableBufferPointer { r in
                imag.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    frame.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(bins))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitude, 1, vDSP_Length(bins))
                }
            }
            // 对数压缩：大小声的扫弦都能看出变化
            var sum: Float = 0
            for k in 1..<bins {
                let m = log1pf(magnitude[k] * 10)
                let d = m - previous[k]
                if d > 0 { sum += d }
                previous[k] = m
            }
            flux.append(start == 0 ? 0 : sum)
            start += hop
        }
        return flux
    }

    // MARK: 定位

    /// 第 t 帧的通量最大；起音在这一帧窗口里。按小块能量找第一块“比前面明显响”的位置。
    func refine(_ samples: [Float], aroundFrame t: Int) -> Int {
        let block = max(16, Int(sampleRate * 0.0013))
        let regionStart = max(0, t * hop - frameSize / 2)
        let regionEnd = min(samples.count, t * hop + frameSize)
        var energies: [Float] = []
        var s = regionStart
        // 用一阶差分（高通）算能量：拨弦的起音是宽频的，前一下还在响的余音主要是低频，差分后压下去
        while s + block <= regionEnd {
            var e: Float = 0
            for i in max(1, s)..<s + block {
                let d = samples[i] - samples[i - 1]
                e += d * d
            }
            energies.append(e)
            s += block
        }
        guard let peak = energies.max(), peak > 0 else { return t * hop + frameSize / 2 }
        for (b, e) in energies.enumerated() where e >= 0.3 * peak {
            let before = energies[max(0, b - 8)..<b].min() ?? 0
            if b == 0 || e > 3 * before + 1e-9 { return regionStart + b * block }
        }
        return t * hop + frameSize / 2
    }

    private func rms(_ samples: [Float], from: Int, length: Int) -> Float {
        let lo = max(0, from), hi = min(samples.count, from + length)
        guard hi > lo else { return 0 }
        var sum: Float = 0
        for i in lo..<hi { sum += samples[i] * samples[i] }
        return (sum / Float(hi - lo)).squareRoot()
    }

    private func median(_ values: ArraySlice<Float>) -> Float {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
