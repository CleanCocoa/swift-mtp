import Foundation
@preconcurrency import Clibmtp

public struct ObjectID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public var description: String { "ObjectID(\(rawValue))" }
}

public struct StorageID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let all = StorageID(rawValue: 0)
    public var description: String { "StorageID(\(rawValue))" }
}

public struct Folder: Hashable, Sendable, CustomStringConvertible {
    public let id: ObjectID
    init(id: ObjectID) { self.id = id }
    public static let root = Folder(id: ObjectID(rawValue: 0))
    public var description: String { "Folder(\(id.rawValue))" }
}

public struct MTPRawDevice: Sendable {
    public let busLocation: UInt32
    public let devnum: UInt8
    public let vendor: String
    public let vendorId: UInt16
    public let product: String
    public let productId: UInt16
    private nonisolated(unsafe) var cRaw: LIBMTP_raw_device_t

    public init(busLocation: UInt32, devnum: UInt8, vendor: String, vendorId: UInt16, product: String, productId: UInt16) {
        self.busLocation = busLocation
        self.devnum = devnum
        self.vendor = vendor
        self.vendorId = vendorId
        self.product = product
        self.productId = productId
        self.cRaw = LIBMTP_raw_device_t()
        self.cRaw.bus_location = busLocation
        self.cRaw.devnum = devnum
    }

    init(cRawDevice: UnsafePointer<LIBMTP_raw_device_struct>) {
        let raw = cRawDevice.pointee
        busLocation = raw.bus_location
        devnum = raw.devnum
        vendor = raw.device_entry.vendor.map { String(cString: $0) } ?? ""
        vendorId = raw.device_entry.vendor_id
        product = raw.device_entry.product.map { String(cString: $0) } ?? ""
        productId = raw.device_entry.product_id
        cRaw = raw
    }

    public mutating func open() throws(MTPError) -> MTPDevice {
        guard let device = LIBMTP_Open_Raw_Device_Uncached(&cRaw) else {
            throw .connectionFailed(bus: busLocation, devnum: devnum)
        }
        LIBMTP_Get_Storage(device, 0)
        return MTPDevice(raw: device)
    }
}

public struct MTPFileInfo: Sendable {
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

public struct MTPStorageInfo: Sendable {
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
