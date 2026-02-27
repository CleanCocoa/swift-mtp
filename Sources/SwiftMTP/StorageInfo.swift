@preconcurrency import Clibmtp

public struct StorageInfo: Sendable {
    public let id: StorageID
    public let description: String
    public let maxCapacity: UInt64
    public let freeSpace: UInt64

    public init(id: StorageID, description: String, maxCapacity: UInt64, freeSpace: UInt64) {
        self.id = id
        self.description = description
        self.maxCapacity = maxCapacity
        self.freeSpace = freeSpace
    }

    init(cStorage: UnsafePointer<LIBMTP_devicestorage_struct>) {
        let s = cStorage.pointee
        id = StorageID(rawValue: s.id)
        description = s.StorageDescription.map { String(cString: $0) } ?? ""
        maxCapacity = s.MaxCapacity
        freeSpace = s.FreeSpaceInBytes
    }
}
