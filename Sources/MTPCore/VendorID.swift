public struct VendorID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
	public let rawValue: UInt16
	public init(rawValue: UInt16) { self.rawValue = rawValue }
	public var description: String { "VendorID(0x\(String(rawValue, radix: 16, uppercase: false)))" }
}
