import Testing
import Foundation
@testable import FlashNoteCore

struct CB08ProtocolTests {
    @Test func crc16MatchesVector() {
        let crc = CB08Crc16.compute(bytes: Array("123456789".utf8), initial: 0x0000)
        #expect(crc == 0x31C3)
    }

    @Test func buildFrameMatchesVendorVector() {
        // 协议 7.3 真机成功帧（SEQ=03，offset=0 + "note20260710-162938.wav" 24B）
        let params = CB08Command.importRequest(offset: 0, filename: "note20260710-162938.wav")
        let data = CB08Command.data(type: 2, cmd: 2, params: params)
        let frame = CB08Frame.build(seq: 0x03, data: data)
        let hex = frame.map { String(format: "%02x", $0) }.joined()
        let expected = "5a039e201e000202000000006e6f746532303236303731302d3136323933382e77617600"
        #expect(hex == expected, "帧与真机抓包不一致: \(hex)")
    }

    @Test func streamParserReassemblesFragments() {
        var parser = CB08FrameParser()
        let frame = CB08Frame.build(seq: 1, data: CB08Command.data(type: 0, cmd: 3, params: Data()))
        var frames: [CB08Frame] = []
        frames += parser.feed(Data(frame.prefix(2)))      // 半帧（MAGIC+SEQ）
        frames += parser.feed(Data(frame[2..<6]))          // CRC+LEN
        frames += parser.feed(Data(frame.suffix(frame.count - 6))) // 剩余
        #expect(frames.count == 1)
        #expect(frames[0].type == 0)
        #expect(frames[0].cmd == 3)
    }

    @Test func streamParserSkipsNoiseAndReassembles() {
        var parser = CB08FrameParser()
        let f1 = CB08Frame.build(seq: 8, data: CB08Command.data(type: 1, cmd: 1, params: Data([1,2,3])))
        var frames = parser.feed(Data([0x00, 0x00]) + f1) // 前导噪声 + 一整帧
        #expect(frames.count == 1)
        #expect(frames[0].seq == 8)
    }

    @Test func streamParserRejectsBadCRC() {
        var parser = CB08FrameParser()
        var frame = CB08Frame.build(seq: 2, data: CB08Command.data(type: 0, cmd: 4, params: Data([90])))
        frame[5] ^= 0xFF // 破坏
        let frames = parser.feed(frame)
        #expect(frames.isEmpty)
    }

    @Test func decodeFileList() {
        var body = Data()
        body.append(Data([0, 0, 0, 1]))          // count = 1 (BE)
        body.append(Data([0, 0, 0, 5]))          // time = 5s (BE)
        body.append(Data([0, 0, 0, 100]))        // size = 100 (BE)
        var name = Array("note20260710-162938".utf8)
        name.append(contentsOf: Array(repeating: 0, count: 20 - name.count))
        body.append(Data(name))
        let entries = CB08FileList.decode(body)
        #expect(entries.count == 1)
        #expect(entries[0].size == 100)
        #expect(entries[0].name.hasPrefix("note20260710"))
        #expect(entries[0].candidateNames == ["note20260710-162938.wav", "note20260710-162938.opus", "note20260710-162938"])
    }
}

    @Test func decodeRealDeviceFileList() {
        let frame = Data([0x5a, 0x02, 0x09, 0x97, 0x22, 0x00, 0x02, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xad, 0x00, 0x05, 0x4b, 0x78, 0x6e, 0x6f, 0x74, 0x65, 0x32, 0x30, 0x32, 0x36, 0x30, 0x38, 0x32, 0x32, 0x2d, 0x31, 0x39, 0x30, 0x32, 0x34, 0x36, 0x2e])
        var parser = CB08FrameParser()
        let frames = parser.feed(frame)
        #expect(frames.count == 1)
        let entry = CB08FileList.decode(frames[0].params)
        print("PARAMSHEX=\(frames[0].params.map { String(format: "%02x", $0) }.joined()) COUNT=\(frames[0].params.count)")
        #expect(entry.count == 1)
        #expect(entry[0].name == "note20260822-190246.")
        #expect(entry[0].size == UInt32(347000))
        #expect(entry[0].candidateNames.first == "note20260822-190246.wav")
    }
