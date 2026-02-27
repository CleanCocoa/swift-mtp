public struct Folder: Hashable, Sendable, CustomStringConvertible {
    public let id: ObjectID
    init(id: ObjectID) { self.id = id }
    public static let root = Folder(id: ObjectID(rawValue: 0))
    public var description: String { "Folder(\(id.rawValue))" }
}
