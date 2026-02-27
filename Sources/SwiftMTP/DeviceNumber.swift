public struct DeviceNumber: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
	public let rawValue: UInt8
	public init(rawValue: UInt8) { self.rawValue = rawValue }
	public var description: String { "DeviceNumber(\(rawValue))" }
}
