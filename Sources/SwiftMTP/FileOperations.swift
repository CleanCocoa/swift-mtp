import Clibmtp
import Foundation

extension Device {
	public func download(
		_ id: ObjectID,
		to localPath: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) {
		let ret = withProgressCallback(progress) { callback, context in
			LIBMTP_Get_File_To_File(raw, id.rawValue, localPath, callback, context)
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
	) throws(MTPError) -> FileInfo {
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
				parent: parent,
				storage: storage
			)
		else {
			throw MTPError.operationFailed("failed to allocate file metadata")
		}

		let uploaded = upload.send(device: raw, from: localPath, progress: progress)
		if uploaded.result != 0 {
			let message = drainErrorStack(raw)
			if message.localizedCaseInsensitiveContains("storage full") {
				throw MTPError.storageFull
			}
			throw MTPError.operationFailed(message)
		}

		return uploaded.toFileInfo()
	}

	public func info(for id: ObjectID) throws(MTPError) -> FileInfo {
		guard let handle = FileHandle(device: raw, id: id) else {
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

	@discardableResult
	public func makeDirectory(named name: String, in parent: Folder, storage: StorageID) throws(MTPError) -> FileInfo {
		let folderId = LIBMTP_Create_Folder(raw, strdup(name), parent.id.rawValue, storage.rawValue)
		if folderId == 0 {
			let message = drainErrorStack(raw)
			throw MTPError.operationFailed(message)
		}
		return FileInfo(
			id: ObjectID(rawValue: folderId),
			parentId: parent.id,
			storageId: storage,
			name: name,
			size: 0,
			modificationDate: .distantPast,
			isDirectory: true
		)
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
	) throws(MTPError) -> FileInfo {
		try upload(from: localPath, to: parent, storage: storage.id, as: filename, progress: progress)
	}

	@discardableResult
	public func makeDirectory(named name: String, in parent: Folder, storage: StorageInfo) throws(MTPError) -> FileInfo
	{
		try makeDirectory(named: name, in: parent, storage: storage.id)
	}

	public func move(_ id: ObjectID, to parent: Folder, storage: StorageInfo) throws(MTPError) {
		try move(id, to: parent, storage: storage.id)
	}

	@discardableResult
	public func rename(_ id: ObjectID, to newName: String) throws(MTPError) -> FileInfo {
		if let handle = FileHandle(device: raw, id: id) {
			let ret = handle.rename(device: raw, to: newName)
			if ret != 0 {
				let message = drainErrorStack(raw)
				throw MTPError.operationFailed(message)
			}
			return handle.toFileInfo()
		}
		_ = drainErrorStack(raw)

		guard let tree = FolderTree(device: raw) else {
			_ = drainErrorStack(raw)
			throw MTPError.objectNotFound(id: id)
		}
		guard let (ret, info) = tree.rename(device: raw, folderId: id, to: newName) else {
			throw MTPError.objectNotFound(id: id)
		}
		if ret != 0 {
			let message = drainErrorStack(raw)
			throw MTPError.operationFailed(message)
		}
		return info
	}
}
