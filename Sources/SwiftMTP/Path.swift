public struct Path: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
	public let components: [String]

	public init?(_ string: String) {
		let parts = string.split(separator: "/").map(String.init)
		if parts.isEmpty { return nil }
		self.components = parts
	}

	public init(stringLiteral value: String) {
		self.components = value.split(separator: "/").map(String.init)
	}

	public var description: String { components.joined(separator: "/") }
}
