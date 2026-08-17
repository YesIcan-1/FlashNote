import Foundation

public enum TranscriptionError: Error, Equatable {
    case engineUnavailable
    case permissionDenied
    case invalidState(String)
    case engineFailed(String)
}

/// 转写通道的可插拔缝。App 层提供 Apple Speech（实时）、whisper.cpp（整段）、云端 ASR 三个实现。
public protocol TranscriptionEngine: AnyObject {
    var displayName: String { get }
    var isRealtime: Bool { get }
    func start() throws
    func cancel()
    var onSegment: ((TranscriptSegment) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
}
