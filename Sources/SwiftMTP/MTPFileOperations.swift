import Clibmtp
import Foundation

extension MTPDevice {
    public func downloadFile(
        id: UInt32,
        to localPath: String,
        progress: ProgressHandler? = nil
    ) throws(MTPError) {
        let ret = withProgressCallback(progress) { callback, data in
            LIBMTP_Get_File_To_File(raw, id, localPath, callback, data)
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
    public func uploadFile(
        from localPath: String,
        parentId: UInt32,
        storageId: UInt32,
        filename: String,
        progress: ProgressHandler? = nil
    ) throws(MTPError) -> UInt32 {
        let attrs = try { () throws(MTPError) -> [FileAttributeKey: Any] in
            do {
                return try FileManager.default.attributesOfItem(atPath: localPath)
            } catch {
                throw MTPError.operationFailed("cannot stat local file: \(localPath)")
            }
        }()
        let fileSize = (attrs[.size] as? UInt64) ?? 0

        guard let upload = Upload(
            filename: filename, filesize: fileSize,
            parentId: parentId, storageId: storageId
        ) else {
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

        return upload.itemId
    }

    public func fileInfo(id: UInt32) throws(MTPError) -> MTPFileInfo {
        guard let handle = FileHandle(device: raw, id: id) else {
            _ = drainErrorStack(raw)
            throw MTPError.objectNotFound(id: ObjectID(rawValue: id))
        }
        return handle.toFileInfo()
    }

    public func deleteObject(id: UInt32) throws(MTPError) {
        let ret = LIBMTP_Delete_Object(raw, id)
        if ret != 0 {
            let message = drainErrorStack(raw)
            throw MTPError.operationFailed(message)
        }
    }

    public func createDirectory(name: String, parentId: UInt32, storageId: UInt32) throws(MTPError) -> UInt32 {
        let folderId = LIBMTP_Create_Folder(raw, strdup(name), parentId, storageId)
        if folderId == 0 {
            let message = drainErrorStack(raw)
            throw MTPError.operationFailed(message)
        }
        return folderId
    }

    public func moveObject(id: UInt32, toParentId: UInt32, storageId: UInt32) throws(MTPError) {
        let ret = LIBMTP_Move_Object(raw, id, storageId, toParentId)
        if ret != 0 {
            let message = drainErrorStack(raw)
            if message.contains("MoveObject") {
                throw MTPError.moveNotSupported
            }
            throw MTPError.operationFailed(message)
        }
    }

    public func renameFile(id: UInt32, newName: String) throws(MTPError) {
        guard let handle = FileHandle(device: raw, id: id) else {
            _ = drainErrorStack(raw)
            throw MTPError.objectNotFound(id: ObjectID(rawValue: id))
        }
        let ret = handle.rename(device: raw, to: newName)
        if ret != 0 {
            let message = drainErrorStack(raw)
            throw MTPError.operationFailed(message)
        }
    }

    public func renameFolder(id: UInt32, newName: String) throws(MTPError) {
        guard let tree = FolderTree(device: raw) else {
            _ = drainErrorStack(raw)
            throw MTPError.objectNotFound(id: ObjectID(rawValue: id))
        }
        guard let ret = tree.rename(device: raw, folderId: id, to: newName) else {
            throw MTPError.objectNotFound(id: ObjectID(rawValue: id))
        }
        if ret != 0 {
            let message = drainErrorStack(raw)
            throw MTPError.operationFailed(message)
        }
    }
}
