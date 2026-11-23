import Foundation
import Speech
import AVFoundation
import FlashNoteCore

/// Speech + 麦克风授权：请求权限并把系统状态映射为核心层 TranscriptionError。
enum SpeechAuthorization {
    /// 请求语音识别权限。返回 nil 表示可用，否则为对应错误。
    static func requestPermissions() async -> TranscriptionError? {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return error(for: current) }
        guard let speech: SFSpeechRecognizerAuthorizationStatus = await withCallbackTimeout(start: { finish in
            SFSpeechRecognizer.requestAuthorization(finish)
        }) else {
            return .engineFailed("语音识别授权未响应，请将 FlashNote 切到前台并检查系统设置中的权限")
        }
        return error(for: speech)
    }

    /// 请求麦克风权限。返回 nil 表示可用，否则为对应错误。
    static func requestMicrophonePermission() async -> TranscriptionError? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return nil
        case .denied, .restricted: return .permissionDenied
        case .notDetermined:
            guard let granted: Bool = await withCallbackTimeout(start: { finish in
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: finish)
            }) else {
                return .engineFailed("麦克风授权未响应，请将 FlashNote 切到前台并检查系统设置中的权限")
            }
            return granted ? nil : .permissionDenied
        @unknown default: return .permissionDenied
        }
    }

    /// macOS 的授权弹窗偶尔不会回调；限时结束等待，避免录音页一直停在加载状态。
    static func withCallbackTimeout<Value>(seconds: TimeInterval = 12,
                                           start: (@escaping (Value) -> Void) -> Void) async -> Value? {
        await withCheckedContinuation { continuation in
            let gate = AuthorizationCompletion(continuation)
            start { gate.resume($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { gate.resume(nil) }
        }
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

private final class AuthorizationCompletion<Value> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) { self.continuation = continuation }

    func resume(_ value: Value?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
