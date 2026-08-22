import Foundation

/// CRC-16/XMODEM：多项式 0x1021，初值 0，RefIn/RefOut=false，XorOut=0。
public enum CB08Crc16 {
    public static func compute(bytes: [UInt8], initial: UInt16 = 0x0000) -> UInt16 {
        var crc = initial
        for b in bytes {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : (crc << 1)
            }
        }
        return crc
    }
}

public struct CB08Frame: Equatable {
    public let seq: UInt8
    public let data: Data
    public var type: UInt8 { data.count >= 1 ? data[data.startIndex] : 0 }
    public var cmd: UInt8? { data.count >= 2 ? data[data.startIndex + 1] : nil }
    public var params: Data { data.count > 2 ? Data(data.dropFirst(2)) : Data() }

    /// 构造完整帧：MAGIC(0x5A) + SEQ + CRC(LE) + LEN(LE) + DATA。
    /// CRC 输入 = LEN 原始 2 字节 + DATA。
    public static func build(seq: UInt8, data: Data) -> Data {
        var frame = [UInt8(0x5A), seq & 0xFF]
        let len = UInt16(data.count)
        let lenBytes = [UInt8(len & 0xFF), UInt8((len >> 8) & 0xFF)]
        let crc = CB08Crc16.compute(bytes: lenBytes + Array(data))
        frame.append(contentsOf: [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)])
        frame.append(contentsOf: lenBytes)
        frame.append(contentsOf: data)
        return Data(frame)
    }
}

/// 流式帧解析器：支持半帧/多帧/噪声重同步、独立缓冲区（AE22/AE23 各一个）。
public struct CB08FrameParser {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ chunk: Data) -> [CB08Frame] {
        if !chunk.isEmpty {
            buffer.append(chunk)
        }
        var frames: [CB08Frame] = []
        while true {
            guard let frame = _tryParseOne() else { break }
            frames.append(frame)
        }
        return frames
    }

    private mutating func _tryParseOne() -> CB08Frame? {
        // 丢弃 MAGIC 前噪声
        while !buffer.isEmpty && buffer[buffer.startIndex] != 0x5A {
            buffer.removeFirst()
        }
        guard buffer.count >= 6 else { return nil }
        let len = Int(buffer[buffer.startIndex + 4]) | (Int(buffer[buffer.startIndex + 5]) << 8)
        if len > 8192 {
            buffer.removeFirst() // 假帧头，重同步
            return nil
        }
        guard buffer.count >= 6 + len else { return nil }
        let data = buffer.subdata(in: (buffer.startIndex + 6)..<(buffer.startIndex + 6 + len))
        let lenBytes = [UInt8(buffer[buffer.startIndex + 4]), UInt8(buffer[buffer.startIndex + 5])]
        let expectedCRC = UInt16(buffer[buffer.startIndex + 2]) | (UInt16(buffer[buffer.startIndex + 3]) << 8)
        let actualCRC = CB08Crc16.compute(bytes: lenBytes + Array(data))
        let seq = buffer[buffer.startIndex + 1]
        buffer.removeFirst(6 + len)
        guard actualCRC == expectedCRC else { return nil } // CRC 错，丢弃
        return CB08Frame(seq: seq, data: data)
    }
}

/// 文件列表条目。
public struct CB08FileEntry: Equatable {
    public let time: UInt32
    public let size: UInt32
    public let name: String

    public init(time: UInt32, size: UInt32, name: String) {
        self.time = time
        self.size = size
        self.name = name
    }

    /// 下载候选名（参考官方实现）：先去尾部 "."（列表截断扩展名所致），
    /// 去掉已含扩展名，再拼 base.wav / base.opus / 原始名。
    public var candidateNames: [String] {
        var base = name.replacingOccurrences(of: "\u{0000}", with: "")
        while base.hasSuffix(".") { base.removeLast() }
        for ext in [".wav", ".opus", ".mp3"] {
            if base.lowercased().hasSuffix(ext) {
                base.removeLast(ext.count)
                break
            }
        }
        let raw = name.replacingOccurrences(of: "\u{0000}", with: "")
        return [base + ".wav", base + ".opus", raw]
    }
}

/// 文件列表解码（count:4B BE + N×28B 条目：time:4B BE + size:4B BE + name:20B）。
public enum CB08FileList {
    public static func decode(_ body: Data) -> [CB08FileEntry] {
        guard body.count >= 4 else { return [] }
        let count = Int(readBE(body, 0, 4))
        var entries: [CB08FileEntry] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 28 <= body.count else { break }
            let time = UInt32(readBE(body, offset, 4))
            let size = UInt32(readBE(body, offset + 4, 4))
            let nameRaw = body.subdata(in: (offset + 8)..<(offset + 28))
            let name = String(data: nameRaw, encoding: .utf8)?
                .replacingOccurrences(of: "\u{0000}", with: "") ?? ""
            entries.append(CB08FileEntry(time: time, size: size, name: name))
            offset += 28
        }
        return entries
    }

    private static func readBE(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<count {
            v = (v << 8) | UInt64(data[data.startIndex + offset + i])
        }
        return v
    }
}
