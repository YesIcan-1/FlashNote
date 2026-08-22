import Foundation
import FlashNoteCore

/// 设备高层逻辑：请求应答匹配、文件列表组装、命令构造。
/// 依赖 BLETransport（CoreBluetooth 或 mock），逻辑可单测。
final class CB08Device {
    private let transport: BLETransport
    private let seqGenerator: () -> UInt8
    private var controlParser = CB08FrameParser()
    private var eventParser = CB08FrameParser()
    private var fileBuffer: [CB08FileEntry] = []

    /// 下载会话状态。
    private var importingName: String?
    private var downloadingBuffer = Data()
    var onDownloadData: ((Data) -> Void)?      // 每收到一分片（含进度）
    var onDownloadComplete: ((Data, String) -> Void)?  // 完整文件 + 实际名
    var onDownloadCode: ((UInt8) -> Void)?     // 结束码

    var onBattery: ((Int) -> Void)?
    var onFileList: (([CB08FileEntry]) -> Void)?
    var onRealtimeAudio: ((Data) -> Void)?
    var onRealtimeState: ((UInt8) -> Void)?
    var onRecordState: ((UInt8) -> Void)?
    var onAuthCode: ((String) -> Void)?
    var onFirmware: ((String) -> Void)?

    init(transport: BLETransport, seqGenerator: @escaping () -> UInt8) {
        self.transport = transport
        self.seqGenerator = seqGenerator
        transport.subscribe(
            onControlNotify: { [weak self] data in self?.handleControlNotification(data) },
            onEventNotify: { [weak self] data in self?.handleEventNotification(data) }
        )
    }

    func send(type: UInt8, cmd: UInt8, params: Data = Data()) {
        let frame = CB08Frame.build(seq: seqGenerator(), data: CB08Command.data(type: type, cmd: cmd, params: params))
        transport.write(frame)
    }

    func requestBattery() { send(type: 0, cmd: 3) }
    func requestVersion() { send(type: 0, cmd: 10) }
    func requestAuthCode() { send(type: 0, cmd: 12) }
    func requestFileList() { fileBuffer = []; send(type: 2, cmd: 0) }
    func requestImport(filename: String, offset: UInt32 = 0) {
        importingName = filename
        downloadingBuffer = Data()
        send(type: 2, cmd: 2, params: CB08Command.importRequest(offset: offset, filename: filename))
    }
    func abortImport() { send(type: 2, cmd: 7) }
    func startRealtime() { send(type: 1, cmd: 0) }
    func stopRealtime() { send(type: 1, cmd: 2) }
    func realtimePause(paused: Bool) { send(type: 1, cmd: 3, params: Data([paused ? 1 : 0])) }
    func recordStart() { send(type: 3, cmd: 1) }
    func recordSave() { send(type: 3, cmd: 3) }
    func recordPause(paused: Bool) { send(type: 3, cmd: paused ? 5 : 7) }
    func recordState() { send(type: 3, cmd: 19) }

    private func handleControlNotification(_ data: Data) {
        for frame in controlParser.feed(data) {
            switch frame.type {
            case 0:
                if frame.cmd == 4, let p = frame.params.first { onBattery?(Int(p)) }
                else if frame.cmd == 13 { onAuthCode?(String(data: frame.params, encoding: .utf8) ?? "") }
                else if frame.cmd == 11 { onFirmware?(Self.trimmedText(frame.params)) }
            case 1:
                if frame.cmd == 1 { onRealtimeAudio?(frame.params) }
                else if frame.cmd == 4 { frame.params.first.map { onRealtimeState?($0) } }
            case 2:
                handleFile(type2cmd: frame.cmd, params: frame.params)
            case 3:
                if frame.cmd == 20 { frame.params.first.map { onRecordState?($0) } }
            default: break
            }
        }
    }

    private func handleEventNotification(_ data: Data) {
        for frame in eventParser.feed(data) {
            switch frame.type {
            case 0:
                if frame.cmd == 4, let value = frame.params.first { onBattery?(Int(value)) }
                else if frame.cmd == 11 { onFirmware?(Self.trimmedText(frame.params)) }
            case 3:
                if frame.cmd == 20, let state = frame.params.first { onRecordState?(state) }
            default: break
            }
        }
    }

    private static func trimmedText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 \n\r\t")) ?? ""
    }

    private func handleFile(type2cmd cmd: UInt8?, params: Data) {
        guard let cmd else { return }
        switch cmd {
        case 1:
            fileBuffer += CB08FileList.decode(params)
        case 3:
            // 开始导入：记录实际导入文件名
            importingName = String(data: params, encoding: .utf8) ?? importingName
        case 4:
            downloadingBuffer.append(params)
            onDownloadData?(params)
        case 5:
            // 结束码：0完成 1不存在 2offset过大 3其他
            let code = params.first ?? 0
            onDownloadCode?(code)
            if code == 0, let name = importingName {
                onDownloadComplete?(downloadingBuffer, name)
            }
            downloadingBuffer = Data()
            importingName = nil
        case 18:
            onFileList?(fileBuffer); fileBuffer = []
        default: break
        }
    }
}
