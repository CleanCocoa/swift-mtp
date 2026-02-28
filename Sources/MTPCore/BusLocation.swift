public struct BusLocation: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
	public let rawValue: UInt32
	public init(rawValue: UInt32) { self.rawValue = rawValue }
	public var description: String { "BusLocation(\(rawValue))" }
}
