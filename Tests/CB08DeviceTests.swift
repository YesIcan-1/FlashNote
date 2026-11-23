import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

/// 测试替身：内存 BLE 传输，记录写入、可回放通知。
final class MockBLETransport: BLETransport {
    var wrote: [Data] = []
    var onNotify: ((Data) -> Void)?
    var onEventNotify: ((Data) -> Void)?
    func write(_ data: Data) { wrote.append(data) }
    func subscribe(
        onControlNotify: @escaping (Data) -> Void,
        onEventNotify: @escaping (Data) -> Void
    ) {
        self.onNotify = onControlNotify
        self.onEventNotify = onEventNotify
    }
}

/// 测试辅助：解析一个字节中的帧。
private func frameOf(_ data: Data?) -> CB08Frame? {
    guard let data else { return nil }
    var parser = CB08FrameParser()
    return parser.feed(data).first
}

struct CB08DeviceTests {
    private func makeDevice(seq: UInt8 = 0) -> (CB08Device, MockBLETransport) {
        let transport = MockBLETransport()
        let device = CB08Device(transport: transport, seqGenerator: { seq })
        return (device, transport)
    }

    @Test func requestBatterySendsType0Cmd3() {
        let (device, transport) = makeDevice(seq: 5)
        device.requestBattery()
        let frame = frameOf(transport.wrote.last)
        #expect(frame?.type == 0)
        #expect(frame?.cmd == 3)
    }

    @Test func handleBatteryResponse() {
        let (device, transport) = makeDevice()
        var battery: Int?
        device.onBattery = { battery = $0 }
        transport.onNotify?(frameData(type: 0, cmd: 4, params: Data([90])))
        #expect(battery == 90)
    }

    @Test func handleBatteryResponseFromEventChannel() {
        let (device, transport) = makeDevice()
        var battery: Int?
        device.onBattery = { battery = $0 }
        transport.onEventNotify?(frameData(type: 0, cmd: 4, params: Data([76])))
        #expect(battery == 76)
    }

    @Test func fileListAccumulatesAcrossFrames() {
        let (device, transport) = makeDevice()
        device.requestFileList()
        var entries: [CB08FileEntry] = []
        device.onFileList = { entries = $0 }
        transport.onNotify?(frameData(type: 2, cmd: 1, params: entryBody(1)))
        transport.onNotify?(frameData(type: 2, cmd: 1, params: entryBody(2)))
        transport.onNotify?(frameData(type: 2, cmd: 18, params: Data([0])))
        #expect(entries.count == 2)
    }

    @Test func downloadAccumulatesAndCompletes() {
        let (device, transport) = makeDevice()
        device.requestImport(filename: "note.wav")
        var received = Data()
        var completeFile: Data?
        var completedName: String?
        device.onDownloadData = { received.append($0) }
        device.onDownloadComplete = { data, name in completeFile = data; completedName = name }
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data(Array("note.wav".utf8))))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([1, 2, 3, 4])))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([5, 6])))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))
        #expect(received == Data([1,2,3,4,5,6]))
        #expect(completeFile == Data([1,2,3,4,5,6]))
        #expect(completedName == "note.wav")
    }

    @Test func realtimeAudioAndState() {
        let (device, transport) = makeDevice()
        var audio: [Data] = []
        var state: UInt8?
        device.onRealtimeAudio = { audio.append($0) }
        device.onRealtimeState = { state = $0 }
        transport.onNotify?(frameData(type: 1, cmd: 1, params: Data([0x01, 0x02, 0x03])))
        transport.onNotify?(frameData(type: 1, cmd: 4, params: Data([0])))
        #expect(audio.count == 1)
        #expect(audio[0] == Data([1,2,3]))
        #expect(state == 0)
    }

    @Test func realtimeControlUsesFirmwareWorkingCommands() {
        let (device, transport) = makeDevice()
        device.startRealtime()
        device.stopRealtime()
        #expect(transport.wrote.count == 2)
        #expect(frameOf(transport.wrote[0])?.data == Data([1, 0]))
        #expect(frameOf(transport.wrote[1])?.data == Data([1, 2]))
    }

    @Test func realtimePauseUsesStreamControlCommand() {
        let (device, transport) = makeDevice()
        device.realtimePause(paused: true)
        device.realtimePause(paused: false)
        #expect(frameOf(transport.wrote[0])?.data == Data([1, 3, 1]))
        #expect(frameOf(transport.wrote[1])?.data == Data([1, 3, 0]))
    }

    @Test func pollingDoesNotOverwriteRealtimePauseState() {
        #expect(DeviceViewModel.displayedRecordState(reported: 1, streamPaused: true, streamActive: true) == 3)
        #expect(DeviceViewModel.displayedRecordState(reported: 1, streamPaused: false, streamActive: true) == 1)
        #expect(DeviceViewModel.displayedRecordState(reported: 2, streamPaused: true, streamActive: true) == 2)
    }

    @Test func eventChannelPublishesRecordState() {
        let (device, transport) = makeDevice()
        var state: UInt8?
        device.onRecordState = { state = $0 }

        transport.onEventNotify?(frameData(type: 3, cmd: 20, params: Data([2])))

        #expect(state == 2)
    }

    @Test func versionResponseIsPublished() {
        let (device, transport) = makeDevice()
        var version: String?
        device.onFirmware = { version = $0 }

        transport.onNotify?(frameData(type: 0, cmd: 11, params: Data("V1.0.0".utf8)))

        #expect(version == "V1.0.0")
    }

    @Test func deleteUsesFullFilenameExpectedByVendorSDK() {
        let (device, transport) = makeDevice()
        let rawEntry = entryBody(1).subdata(in: 4..<32)
        let file = CB08FileEntry(time: 1, size: 100, name: "note1", rawEntry: rawEntry)

        device.deleteFile(file)

        let frame = frameOf(transport.wrote.last)
        #expect(frame?.type == 2)
        #expect(frame?.cmd == 8)
        #expect(frame?.params == Data(repeating: 0, count: 4) + Data("note1.opus".utf8))
    }

    @Test func deleteHardwareStyleNameUsesSingle36ByteFrame() {
        let (device, transport) = makeDevice()
        device.deleteFile(CB08FileEntry(time: 1, size: 233_000, name: "note20261029-141159."))
        #expect(transport.wrote.count == 1)
        #expect(transport.wrote[0].count == 36)
        #expect(frameOf(transport.wrote[0])?.params ==
            Data(repeating: 0, count: 4) + Data("note20261029-141159.opus".utf8))
    }

    @Test func deleteResultUsesSingleFileResponseCommand() {
        let (device, transport) = makeDevice()
        var result: UInt8?
        device.onFileDeleteResult = { result = $0 }
        transport.onNotify?(frameData(type: 2, cmd: 13, params: Data([0])))
        #expect(result == 0)
    }

    private func entryBody(_ n: Int) -> Data {
        var d = Data()
        d.append(contentsOf: [0,0,0,1])
        d.append(contentsOf: [0,0,0,5])
        d.append(contentsOf: [0,0,0,UInt8(n*100)])
        var name = Array("note\(n)".utf8)
        name.append(contentsOf: Array(repeating: 0, count: 20-name.count))
        d.append(contentsOf: name)
        return d
    }
}

/// 测试辅助：构造 TYPE/CMD 帧数据。
func frameData(type: UInt8, cmd: UInt8, params: Data) -> Data {
    CB08Frame.build(seq: 0, data: CB08Command.data(type: type, cmd: cmd, params: params))
}
