public struct ObjectID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
	public let rawValue: UInt32
	public init(rawValue: UInt32) { self.rawValue = rawValue }
	public var description: String { "ObjectID(\(rawValue))" }
	public static let root = ObjectID(rawValue: 0)
}
