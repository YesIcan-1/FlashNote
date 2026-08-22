import Foundation

/// CB08 命令常量与参数编码。
public enum CB08Command {
    // TYPE
    public static let typeControl: UInt8 = 0
    public static let typeRealtime: UInt8 = 1
    public static let typeFile: UInt8 = 2
    public static let typeKey: UInt8 = 3

    public static func data(type: UInt8, cmd: UInt8, params: Data = Data()) -> Data {
        var d = Data([type, cmd])
        d.append(params)
        return d
    }

    /// 文件下载请求 2-2：offset(4B LE) + filename(24B NUL填充)。
    public static func importRequest(offset: UInt32, filename: String) -> Data {
        var params = Data()
        var off = offset.littleEndian
        params.append(Data(bytes: &off, count: 4))
        var name = Array(filename.utf8.prefix(24))
        if name.count < 24 {
            name.append(contentsOf: Array(repeating: 0, count: 24 - name.count))
        }
        params.append(contentsOf: name)
        return params
    }
}
