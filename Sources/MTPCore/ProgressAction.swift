public enum ProgressAction: Hashable, Sendable, ExpressibleByBooleanLiteral {
	case `continue`
	case cancel

	public init(booleanLiteral value: Bool) {
		self = value ? .continue : .cancel
	}
}
