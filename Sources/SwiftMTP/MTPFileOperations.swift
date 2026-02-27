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
            if message.contains("cancel") || message.contains("Cancel") {
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

        guard let metadata = LIBMTP_new_file_t() else {
            throw MTPError.operationFailed("failed to allocate file metadata")
        }
        defer { LIBMTP_destroy_file_t(metadata) }

        metadata.pointee.filename = strdup(filename)
        metadata.pointee.filesize = fileSize
        metadata.pointee.parent_id = parentId
        metadata.pointee.storage_id = storageId
        metadata.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN

        let ret = withProgressCallback(progress) { callback, data in
            LIBMTP_Send_File_From_File(raw, localPath, metadata, callback, data)
        }
        if ret != 0 {
            let message = drainErrorStack(raw)
            if message.contains("storage full") || message.contains("Storage full") {
                throw MTPError.storageFull
            }
            throw MTPError.operationFailed(message)
        }

        return metadata.pointee.item_id
    }

    public func fileInfo(id: UInt32) throws(MTPError) -> MTPFileInfo {
        guard let file = LIBMTP_Get_Filemetadata(raw, id) else {
            _ = drainErrorStack(raw)
            throw MTPError.objectNotFound(id: id)
        }
        defer { LIBMTP_destroy_file_t(file) }
        return MTPFileInfo(cFile: file)
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
        guard let file = LIBMTP_Get_Filemetadata(raw, id) else {
            _ = drainErrorStack(raw)
            throw MTPError.objectNotFound(id: id)
        }
        defer { LIBMTP_destroy_file_t(file) }
        let ret = LIBMTP_Set_File_Name(raw, file, newName)
        if ret != 0 {
            let message = drainErrorStack(raw)
            throw MTPError.operationFailed(message)
        }
    }

    public func renameFolder(id: UInt32, newName: String) throws(MTPError) {
        guard let folderTree = LIBMTP_Get_Folder_List(raw) else {
            _ = drainErrorStack(raw)
            throw MTPError.objectNotFound(id: id)
        }
        defer { LIBMTP_destroy_folder_t(folderTree) }
        guard let folder = LIBMTP_Find_Folder(folderTree, id) else {
            throw MTPError.objectNotFound(id: id)
        }
        let ret = LIBMTP_Set_Folder_Name(raw, folder, newName)
        if ret != 0 {
            let message = drainErrorStack(raw)
            throw MTPError.operationFailed(message)
        }
    }
}
