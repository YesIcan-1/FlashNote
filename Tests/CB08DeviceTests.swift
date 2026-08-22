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
    func write(_ data: Data) { wrote.append(data) }
    func subscribe(onNotify: @escaping (Data) -> Void) { self.onNotify = onNotify }
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
