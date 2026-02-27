import Clibmtp
import Foundation

extension Device {
	public func download(
		_ id: ObjectID,
		to localPath: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) {
		let ret = withProgressCallback(progress) { callback, data in
			LIBMTP_Get_File_To_File(raw, id.rawValue, localPath, callback, data)
		}
		if ret != 0 {
			let message = drainErrorStack(raw)
			if message.localizedCaseInsensitiveContains("cancel") {
				throw MTPError.cancelled
			}
			throw MTPError.operationFailed(message)
		}
	}

	@discardableResult
	public func upload(
		from localPath: String,
		to parent: Folder,
		storage: StorageID,
		as filename: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) -> ObjectID {
		let attrs = try { () throws(MTPError) -> [FileAttributeKey: Any] in
			do {
				return try FileManager.default.attributesOfItem(atPath: localPath)
			} catch {
				throw MTPError.operationFailed("cannot stat local file: \(localPath)")
			}
		}()
		let fileSize = (attrs[.size] as? UInt64) ?? 0

		guard
			let upload = Upload(
				filename: filename,
				filesize: fileSize,
				parentId: parent.id.rawValue,
				storageId: storage.rawValue
			)
		else {
			throw MTPError.operationFailed("failed to allocate file metadata")
		}

		let ret = withProgressCallback(progress) { callback, data in
			upload.send(device: raw, from: localPath, callback: callback, data: data)
		}
		if ret != 0 {
			let message = drainErrorStack(raw)
			if message.localizedCaseInsensitiveContains("storage full") {
				throw MTPError.storageFull
			}
			throw MTPError.operationFailed(message)
		}

		return ObjectID(rawValue: upload.itemId)
	}

	public func info(for id: ObjectID) throws(MTPError) -> FileInfo {
		guard let handle = FileHandle(device: raw, id: id.rawValue) else {
			_ = drainErrorStack(raw)
			throw MTPError.objectNotFound(id: id)
		}
		return handle.toFileInfo()
	}

	public func delete(_ id: ObjectID) throws(MTPError) {
		let ret = LIBMTP_Delete_Object(raw, id.rawValue)
		if ret != 0 {
			let message = drainErrorStack(raw)
			throw MTPError.operationFailed(message)
		}
	}

	public func makeDirectory(named name: String, in parent: Folder, storage: StorageID) throws(MTPError) -> Folder {
		let folderId = LIBMTP_Create_Folder(raw, strdup(name), parent.id.rawValue, storage.rawValue)
		if folderId == 0 {
			let message = drainErrorStack(raw)
			throw MTPError.operationFailed(message)
		}
		return Folder(id: ObjectID(rawValue: folderId))
	}

	public func move(_ id: ObjectID, to parent: Folder, storage: StorageID) throws(MTPError) {
		let ret = LIBMTP_Move_Object(raw, id.rawValue, storage.rawValue, parent.id.rawValue)
		if ret != 0 {
			let message = drainErrorStack(raw)
			if message.contains("MoveObject") {
				throw MTPError.moveNotSupported
			}
			throw MTPError.operationFailed(message)
		}
	}

	@discardableResult
	public func upload(
		from localPath: String,
		to parent: Folder,
		storage: StorageInfo,
		as filename: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) -> ObjectID {
		try upload(from: localPath, to: parent, storage: storage.id, as: filename, progress: progress)
	}

	public func makeDirectory(named name: String, in parent: Folder, storage: StorageInfo) throws(MTPError) -> Folder {
		try makeDirectory(named: name, in: parent, storage: storage.id)
	}

	public func move(_ id: ObjectID, to parent: Folder, storage: StorageInfo) throws(MTPError) {
		try move(id, to: parent, storage: storage.id)
	}

	public func rename(_ id: ObjectID, to newName: String) throws(MTPError) {
		if let handle = FileHandle(device: raw, id: id.rawValue) {
			let ret = handle.rename(device: raw, to: newName)
			if ret != 0 {
				let message = drainErrorStack(raw)
				throw MTPError.operationFailed(message)
			}
			return
		}
		_ = drainErrorStack(raw)

		guard let tree = FolderTree(device: raw) else {
			_ = drainErrorStack(raw)
			throw MTPError.objectNotFound(id: id)
		}
		guard let ret = tree.rename(device: raw, folderId: id.rawValue, to: newName) else {
			throw MTPError.objectNotFound(id: id)
		}
		if ret != 0 {
			let message = drainErrorStack(raw)
			throw MTPError.operationFailed(message)
		}
	}
}
