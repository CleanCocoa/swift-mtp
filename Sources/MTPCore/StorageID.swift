public struct StorageID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
	public let rawValue: UInt32
	public init(rawValue: UInt32) { self.rawValue = rawValue }
	public static let all = StorageID(rawValue: 0)
	public var description: String { "StorageID(\(rawValue))" }
}
