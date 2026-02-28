public struct ProductID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
	public let rawValue: UInt16
	public init(rawValue: UInt16) { self.rawValue = rawValue }
	public var description: String {
		let hex = String(rawValue, radix: 16, uppercase: false)
		let pad = String(repeating: "0", count: max(0, 4 - hex.count))
		return "ProductID(0x\(pad)\(hex))"
	}
}
