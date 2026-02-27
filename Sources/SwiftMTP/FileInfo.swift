import Foundation
@preconcurrency import Clibmtp

public struct FileInfo: Sendable {
    public let id: ObjectID
    public let parentId: ObjectID
    public let storageId: StorageID
    public let name: String
    public let size: UInt64
    public let modificationDate: Date
    public let isDirectory: Bool

    public var folder: Folder? { isDirectory ? Folder(id: id) : nil }

    public init(id: ObjectID, parentId: ObjectID, storageId: StorageID, name: String, size: UInt64, modificationDate: Date, isDirectory: Bool) {
        self.id = id
        self.parentId = parentId
        self.storageId = storageId
        self.name = name
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }

    init(cFile: UnsafeMutablePointer<LIBMTP_file_struct>) {
        let f = cFile.pointee
        id = ObjectID(rawValue: f.item_id)
        parentId = ObjectID(rawValue: f.parent_id)
        storageId = StorageID(rawValue: f.storage_id)
        name = f.filename.map { String(cString: $0) } ?? ""
        size = f.filesize
        modificationDate = Date(timeIntervalSince1970: TimeInterval(f.modificationdate))
        isDirectory = f.filetype == LIBMTP_FILETYPE_FOLDER
    }

    init(cFolder: UnsafeMutablePointer<LIBMTP_folder_struct>) {
        let f = cFolder.pointee
        id = ObjectID(rawValue: f.folder_id)
        parentId = ObjectID(rawValue: f.parent_id)
        storageId = StorageID(rawValue: f.storage_id)
        name = f.name.map { String(cString: $0) } ?? ""
        size = 0
        modificationDate = .distantPast
        isDirectory = true
    }
}
