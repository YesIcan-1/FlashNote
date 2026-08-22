import Foundation

enum OpusDecodingError: Error, Equatable, LocalizedError {
    case invalidPacketLength(Int)
    case decoderCreationFailed(Int32)
    case decodeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPacketLength(let length): "OPUS 数据包长度错误：\(length)（应为 40 字节）"
        case .decoderCreationFailed(let code): "无法创建 OPUS 解码器（\(code)）"
        case .decodeFailed(let code): "OPUS 解码失败（\(code)）"
        }
    }
}

@_silgen_name("flashnote_opus_decoder_create")
private func flashnoteOpusDecoderCreate(_ sampleRate: Int32, _ channels: Int32, _ error: UnsafeMutablePointer<Int32>) -> OpaquePointer?

@_silgen_name("flashnote_opus_decode")
private func flashnoteOpusDecode(
    _ decoder: OpaquePointer,
    _ packet: UnsafePointer<UInt8>,
    _ packetLength: Int32,
    _ output: UnsafeMutablePointer<Int16>,
    _ frameSize: Int32
) -> Int32

@_silgen_name("flashnote_opus_decoder_destroy")
private func flashnoteOpusDecoderDestroy(_ decoder: OpaquePointer)

/// QS668 固定格式的单声道 16 kHz OPUS 解码器。
final class OpusDecoder {
    private let handle: OpaquePointer
    private let samplesPerPacket: Int32

    init(sampleRate: Int32 = 16_000, channels: Int32 = 1) throws {
        var error: Int32 = 0
        guard let handle = flashnoteOpusDecoderCreate(sampleRate, channels, &error), error == 0 else {
            throw OpusDecodingError.decoderCreationFailed(error)
        }
        self.handle = handle
        self.samplesPerPacket = sampleRate / 50 // 20 ms
    }

    deinit { flashnoteOpusDecoderDestroy(handle) }

    func decode(packet: Data) throws -> [Int16] {
        guard packet.count == 40 else { throw OpusDecodingError.invalidPacketLength(packet.count) }
        var output = [Int16](repeating: 0, count: Int(samplesPerPacket))
        let decoded = try packet.withUnsafeBytes { packetBytes -> Int32 in
            guard let base = packetBytes.bindMemory(to: UInt8.self).baseAddress else {
                throw OpusDecodingError.invalidPacketLength(0)
            }
            return flashnoteOpusDecode(handle, base, Int32(packet.count), &output, samplesPerPacket)
        }
        guard decoded >= 0 else { throw OpusDecodingError.decodeFailed(decoded) }
        return Array(output.prefix(Int(decoded)))
    }
}

enum WAVEncoder {
    static func encode(samples: [Int16], sampleRate: UInt32 = 16_000, channels: UInt16 = 1) -> Data {
        let bytesPerSample = UInt16(MemoryLayout<Int16>.size)
        let dataSize = UInt32(samples.count * Int(bytesPerSample))
        let byteRate = sampleRate * UInt32(channels) * UInt32(bytesPerSample)
        let blockAlign = channels * bytesPerSample

        var data = Data("RIFF".utf8)
        data.appendLE(UInt32(36) + dataSize)
        data.append(Data("WAVEfmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(channels)
        data.appendLE(sampleRate)
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(UInt16(16))
        data.append(Data("data".utf8))
        data.appendLE(dataSize)
        samples.withUnsafeBufferPointer { buffer in
            data.append(Data(buffer: buffer))
        }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<T>.size))
    }
}

/// 将设备下载的连续 40-byte OPUS 包转换为标准 WAV，供既有转写引擎使用。
enum CB08OpusFileDecoder {
    static func decodeToWAV(_ opusData: Data) throws -> Data {
        guard opusData.count.isMultiple(of: 40) else {
            throw OpusDecodingError.invalidPacketLength(opusData.count % 40)
        }
        let decoder = try OpusDecoder()
        var samples: [Int16] = []
        samples.reserveCapacity(opusData.count / 40 * 320)
        for offset in stride(from: 0, to: opusData.count, by: 40) {
            samples += try decoder.decode(packet: opusData.subdata(in: offset..<(offset + 40)))
        }
        return WAVEncoder.encode(samples: samples)
    }
}
