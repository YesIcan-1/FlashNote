import Foundation

/// 录音文件夹。V1 仅支持单层（parentID 预留为 nil）。
public struct Folder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var colorIndex: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        colorIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }
}
