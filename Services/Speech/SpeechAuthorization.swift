import Foundation
import Speech
import AVFoundation
import FlashNoteCore

/// Speech + 麦克风授权：请求权限并把系统状态映射为核心层 TranscriptionError。
enum SpeechAuthorization {
    /// 请求语音识别权限。返回 nil 表示可用，否则为对应错误。
    static func requestPermissions() async -> TranscriptionError? {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        if let speechError = error(for: speech) { return speechError }
        return nil
    }

    /// 请求麦克风权限。返回 nil 表示可用，否则为对应错误。
    static func requestMicrophonePermission() async -> TranscriptionError? {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? nil : .permissionDenied
    }

    /// 纯函数映射（可测）：授权状态 → 核心错误。
    static func error(for status: SFSpeechRecognizerAuthorizationStatus) -> TranscriptionError? {
        switch status {
        case .authorized: nil
        case .denied, .restricted, .notDetermined: .permissionDenied
        @unknown default: .permissionDenied
        }
    }
}
