import Testing
import Foundation
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct OpusDecoderTests {
    @Test func rejectsPacketThatIsNotCB08PacketSize() throws {
        let decoder = try OpusDecoder()
        #expect(throws: OpusDecodingError.invalidPacketLength(39)) {
            try decoder.decode(packet: Data(repeating: 0, count: 39))
        }
    }

    @Test func encodedWAVUsesPCMHeader() {
        let wav = WAVEncoder.encode(samples: [0, 200, -200])
        #expect(Array(wav.prefix(4)) == Array("RIFF".utf8))
        #expect(wav.subdata(in: 8..<12) == Data("WAVE".utf8))
        #expect(wav.count == 50)
    }
}
