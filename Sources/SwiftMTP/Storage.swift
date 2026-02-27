import Clibmtp

public struct Storage {
	private let device: Device
	public let info: StorageInfo

	init(device: Device, info: StorageInfo) {
		self.device = device
		self.info = info
	}

	public var id: StorageID { info.id }
	public var description: String { info.description }
	public var maxCapacity: UInt64 { info.maxCapacity }
	public var freeSpace: UInt64 { info.freeSpace }

	public func contents(of parent: Folder = .root) throws(MTPError) -> [FileInfo] {
		try device.contents(of: parent, storage: id)
	}

	public func resolvePath(_ path: String) throws(MTPError) -> FileInfo? {
		try device.resolvePath(path, storage: id)
	}

	public func resolvePath(_ path: Path) throws(MTPError) -> FileInfo? {
		try device.resolvePath(path.description, storage: id)
	}

	@discardableResult
	public func upload(
		from localPath: String,
		to parent: Folder,
		as filename: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) -> FileInfo {
		try device.upload(from: localPath, to: parent, storage: id, as: filename, progress: progress)
	}

	@discardableResult
	public func makeDirectory(named name: String, in parent: Folder) throws(MTPError) -> FileInfo {
		try device.makeDirectory(named: name, in: parent, storage: id)
	}

	public func download(_ id: ObjectID, to localPath: String, progress: ProgressHandler? = nil) throws(MTPError) {
		try device.download(id, to: localPath, progress: progress)
	}

	public func info(for id: ObjectID) throws(MTPError) -> FileInfo {
		try device.info(for: id)
	}

	public func delete(_ id: ObjectID) throws(MTPError) {
		try device.delete(id)
	}

	@discardableResult
	public func rename(_ id: ObjectID, to newName: String) throws(MTPError) -> FileInfo {
		try device.rename(id, to: newName)
	}

	public func move(_ objectId: ObjectID, to parent: Folder) throws(MTPError) {
		try device.move(objectId, to: parent, storage: id)
	}
}

extension Device {
	public func storageInfo() -> [StorageInfo] {
		var result: [StorageInfo] = []
		var current = raw.pointee.storage
		while let storage = current {
			result.append(StorageInfo(cStorage: storage))
			current = storage.pointee.next
		}
		return result
	}

	public func storages() -> [Storage] {
		storageInfo().map { Storage(device: self, info: $0) }
	}

	public var defaultStorage: Storage? { storages().first }
}
