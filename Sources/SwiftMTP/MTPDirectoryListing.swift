import Clibmtp

extension MTPDevice {
    public func listDirectory(
        storageId: UInt32 = 0,
        parentId: UInt32 = 0
    ) throws(MTPError) -> [MTPFileInfo] {
        var allFolderIds = Set<UInt32>()
        var synthIds = Set<UInt32>()
        var results: [MTPFileInfo] = []

        if let tree = FolderTree(device: raw) {
            tree.collectAllFolderIds(into: &allFolderIds)
            tree.collectChildFolders(parentId: parentId, results: &results, synthIds: &synthIds)
        }

        var cursor = FileNode.list(device: raw, storageId: storageId, parentId: parentId)
        if cursor == nil && allFolderIds.isEmpty {
            let message = drainErrorStack(raw)
            if message != "unknown error" {
                throw MTPError.operationFailed(message)
            }
        }

        while let rawPtr = cursor {
            let node = FileNode(rawPtr)
            cursor = node.next

            if node.parentId != parentId { continue }
            if synthIds.contains(node.itemId) { continue }
            if allFolderIds.contains(node.itemId) && !node.isFolder {
                let info = node.toFileInfo()
                results.append(MTPFileInfo(
                    id: info.id, parentId: info.parentId, storageId: info.storageId,
                    name: info.name, size: info.size, modificationDate: info.modificationDate,
                    isDirectory: true
                ))
            } else {
                results.append(node.toFileInfo())
            }
        }

        return results
    }

    public func resolvePath(_ path: String, storageId: UInt32 = 0) throws(MTPError) -> MTPFileInfo? {
        let components = path.split(separator: "/").map(String.init)
        if components.isEmpty { return nil }

        var currentParent: UInt32 = 0
        var lastMatch: MTPFileInfo? = nil

        for component in components {
            var cursor = FileNode.list(device: raw, storageId: storageId, parentId: currentParent)
            var found: MTPFileInfo? = nil

            while let rawPtr = cursor {
                let node = FileNode(rawPtr)
                cursor = node.next
                let info = node.toFileInfo()

                if found == nil && info.name == component {
                    found = info
                }
            }

            guard let match = found else {
                return nil
            }

            currentParent = match.id
            lastMatch = match
        }

        return lastMatch
    }
}
