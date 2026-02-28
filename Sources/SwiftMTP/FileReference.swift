public protocol FileReference: Sendable {
	var objectID: ObjectID { get }
}

extension ObjectID: FileReference {
	public var objectID: ObjectID { self }
}

extension FileInfo: FileReference {
	public var objectID: ObjectID { id }
}

extension Folder: FileReference {
	public var objectID: ObjectID { id }
}
