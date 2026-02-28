@_exported public import MTPCore
import Foundation

public struct Storage: Sendable {
	private let session: MTPSession
	public let info: StorageInfo

	init(session: MTPSession, info: StorageInfo) {
		self.session = session
		self.info = info
	}

	public var id: StorageID { info.id }
	public var description: String { info.description }
	public var maxCapacity: UInt64 { info.maxCapacity }
	public var freeSpace: UInt64 { info.freeSpace }

	public func contents(of parent: Folder = .root) async throws(MTPError) -> [FileInfo] {
		try await session.contents(of: parent, storage: id)
	}

	public func resolvePath(_ path: String) async throws(MTPError) -> FileInfo? {
		try await session.resolvePath(path, storage: id)
	}

	public func resolvePath(_ path: Path) async throws(MTPError) -> FileInfo? {
		try await session.resolvePath(path.description, storage: id)
	}

	@discardableResult
	public func upload(
		from url: URL,
		to parent: Folder,
		as filename: String? = nil,
		progress: ProgressHandler? = nil
	) async throws(MTPError) -> FileInfo {
		try await session.upload(from: url, to: parent, storage: id, as: filename, progress: progress)
	}

	@discardableResult
	public func upload(
		from localPath: String,
		to parent: Folder,
		as filename: String,
		progress: ProgressHandler? = nil
	) async throws(MTPError) -> FileInfo {
		try await session.upload(from: localPath, to: parent, storage: id, as: filename, progress: progress)
	}

	@discardableResult
	public func makeDirectory(named name: String, in parent: Folder) async throws(MTPError) -> FileInfo {
		try await session.makeDirectory(named: name, in: parent, storage: id)
	}

	public func download(_ id: ObjectID, to url: URL, progress: ProgressHandler? = nil) async throws(MTPError) {
		try await session.download(id, to: url, progress: progress)
	}

	public func download(_ id: ObjectID, to localPath: String, progress: ProgressHandler? = nil) async throws(MTPError) {
		try await session.download(id, to: localPath, progress: progress)
	}

	public func info(for id: ObjectID) async throws(MTPError) -> FileInfo {
		try await session.info(for: id)
	}

	public func delete(_ id: ObjectID) async throws(MTPError) {
		try await session.delete(id)
	}

	@discardableResult
	public func rename(_ id: ObjectID, to newName: String) async throws(MTPError) -> FileInfo {
		try await session.rename(id, to: newName)
	}

	public func move(_ objectId: ObjectID, to parent: Folder) async throws(MTPError) {
		try await session.move(objectId, to: parent, storage: id)
	}

	public func download(_ file: some FileReference, to url: URL, progress: ProgressHandler? = nil) async throws(MTPError) {
		try await session.download(file.objectID, to: url, progress: progress)
	}

	public func download(
		_ file: some FileReference,
		to localPath: String,
		progress: ProgressHandler? = nil
	) async throws(MTPError) {
		try await session.download(file.objectID, to: localPath, progress: progress)
	}

	public func info(for file: some FileReference) async throws(MTPError) -> FileInfo {
		try await session.info(for: file.objectID)
	}

	public func delete(_ file: some FileReference) async throws(MTPError) {
		try await session.delete(file.objectID)
	}

	@discardableResult
	public func rename(_ file: some FileReference, to newName: String) async throws(MTPError) -> FileInfo {
		try await session.rename(file.objectID, to: newName)
	}

	public func move(_ file: some FileReference, to parent: Folder) async throws(MTPError) {
		try await session.move(file.objectID, to: parent, storage: id)
	}
}
