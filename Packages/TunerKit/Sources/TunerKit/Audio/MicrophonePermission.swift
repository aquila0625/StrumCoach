import Foundation
import AVFoundation

/// 麦克风权限状态。
public enum MicrophonePermission: Equatable, Sendable {
    case notDetermined
    case granted
    case denied

    public static func current() -> MicrophonePermission {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .notDetermined
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
        #endif
    }

    /// 弹出系统授权框（已决定过则直接返回结果）。
    public static func request() async -> MicrophonePermission {
        #if os(iOS)
        let ok = await AVAudioApplication.requestRecordPermission()
        return ok ? .granted : .denied
        #else
        let ok = await AVCaptureDevice.requestAccess(for: .audio)
        return ok ? .granted : .denied
        #endif
    }
}
