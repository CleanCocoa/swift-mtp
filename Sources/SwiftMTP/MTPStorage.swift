import Clibmtp

public struct MTPStorage {
    private let device: MTPDevice
    public let info: MTPStorageInfo

    init(device: MTPDevice, info: MTPStorageInfo) {
        self.device = device
        self.info = info
    }

    public var id: StorageID { info.id }
    public var description: String { info.description }
    public var maxCapacity: UInt64 { info.maxCapacity }
    public var freeSpace: UInt64 { info.freeSpace }

    public func contents(of parent: Folder = .root) throws(MTPError) -> [MTPFileInfo] {
        try device.contents(of: parent, storage: id)
    }

    public func resolvePath(_ path: String) throws(MTPError) -> MTPFileInfo? {
        try device.resolvePath(path, storage: id)
    }

    @discardableResult
    public func upload(
        from localPath: String,
        to parent: Folder,
        as filename: String,
        progress: ProgressHandler? = nil
    ) throws(MTPError) -> ObjectID {
        try device.upload(from: localPath, to: parent, storage: id, as: filename, progress: progress)
    }

    public func makeDirectory(named name: String, in parent: Folder) throws(MTPError) -> Folder {
        try device.makeDirectory(named: name, in: parent, storage: id)
    }

    public func move(_ objectId: ObjectID, to parent: Folder) throws(MTPError) {
        try device.move(objectId, to: parent, storage: id)
    }
}

extension MTPDevice {
    public func storageInfo() -> [MTPStorageInfo] {
        var result: [MTPStorageInfo] = []
        var current = raw.pointee.storage
        while let storage = current {
            result.append(MTPStorageInfo(cStorage: storage))
            current = storage.pointee.next
        }
        return result
    }

    public func storages() -> [MTPStorage] {
        storageInfo().map { MTPStorage(device: self, info: $0) }
    }

    public var defaultStorage: MTPStorage? { storages().first }
}
