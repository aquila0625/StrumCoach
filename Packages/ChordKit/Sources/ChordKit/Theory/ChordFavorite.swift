import Foundation

/// 一条收藏：哪件乐器上的哪个和弦的第几个把位。持久化由 App 负责（`ChordFavorites` 可直接 `Codable`）。
public struct ChordFavorite: Hashable, Codable, Sendable, Identifiable {
    public var instrumentID: String
    public var tuningID: String
    /// 根音音级 0…11。
    public var root: Int
    public var typeID: String
    /// `ChordLibrary.voicings` 返回数组里的序号；贝斯固定为 0。
    public var voicingIndex: Int

    public init(instrumentID: String, tuningID: String, root: Int, typeID: String, voicingIndex: Int) {
        self.instrumentID = instrumentID; self.tuningID = tuningID
        self.root = root; self.typeID = typeID; self.voicingIndex = voicingIndex
    }

    public var id: String { "\(instrumentID)/\(tuningID)/\(root)/\(typeID)/\(voicingIndex)" }

    public var chord: Chord? {
        ChordType.type(id: typeID).map { Chord(root: root, type: $0) }
    }
}

/// 收藏夹：一个可以直接编码成 JSON 数组存起来的列表。
public struct ChordFavorites: Hashable, Codable, Sendable {
    public private(set) var items: [ChordFavorite]

    public init(_ items: [ChordFavorite] = []) { self.items = items }

    public init(from decoder: Decoder) throws {
        items = try decoder.singleValueContainer().decode([ChordFavorite].self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(items)
    }

    public func contains(_ f: ChordFavorite) -> Bool { items.contains(f) }

    public mutating func add(_ f: ChordFavorite) {
        if !items.contains(f) { items.insert(f, at: 0) }
    }
    public mutating func remove(_ f: ChordFavorite) { items.removeAll { $0 == f } }
    /// 已收藏则取消，否则加入；返回操作之后是否处于收藏状态。
    @discardableResult
    public mutating func toggle(_ f: ChordFavorite) -> Bool {
        if contains(f) { remove(f); return false }
        add(f); return true
    }
}
