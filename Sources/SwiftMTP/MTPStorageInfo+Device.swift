import Clibmtp

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

    public var defaultStorage: MTPStorageInfo? { storageInfo().first }
}
