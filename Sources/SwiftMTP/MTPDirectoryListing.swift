import Clibmtp

extension MTPDevice {
    public func listDirectory(
        storageId: UInt32 = 0,
        parentId: UInt32 = 0
    ) throws(MTPError) -> [MTPFileInfo] {
        var allFolderIds = Set<UInt32>()
        var synthIds = Set<UInt32>()
        var results: [MTPFileInfo] = []

        let folderTree = LIBMTP_Get_Folder_List(raw)
        if let tree = folderTree {
            collectAllFolderIds(tree, into: &allFolderIds)
            collectChildFolders(tree, parentId: parentId, results: &results, synthIds: &synthIds)
            LIBMTP_destroy_folder_t(tree)
        }

        var fileList = LIBMTP_Get_Files_And_Folders(raw, storageId, parentId)
        if fileList == nil && allFolderIds.isEmpty {
            let message = drainErrorStack(raw)
            if message != "unknown error" {
                throw MTPError.operationFailed(message)
            }
        }

        while let file = fileList {
            let next = file.pointee.next
            defer { LIBMTP_destroy_file_t(file) }

            if file.pointee.parent_id != parentId {
                fileList = next
                continue
            }
            if synthIds.contains(file.pointee.item_id) {
                fileList = next
                continue
            }
            if allFolderIds.contains(file.pointee.item_id) && file.pointee.filetype != LIBMTP_FILETYPE_FOLDER {
                let info = MTPFileInfo(cFile: file)
                results.append(MTPFileInfo(
                    id: info.id, parentId: info.parentId, storageId: info.storageId,
                    name: info.name, size: info.size, modificationDate: info.modificationDate,
                    isDirectory: true
                ))
            } else {
                results.append(MTPFileInfo(cFile: file))
            }
            fileList = next
        }

        return results
    }

    public func resolvePath(_ path: String, storageId: UInt32 = 0) throws(MTPError) -> MTPFileInfo? {
        let components = path.split(separator: "/").map(String.init)
        if components.isEmpty { return nil }

        var currentParent: UInt32 = 0
        var lastMatch: MTPFileInfo? = nil

        for component in components {
            var fileList = LIBMTP_Get_Files_And_Folders(raw, storageId, currentParent)
            var found: MTPFileInfo? = nil

            while let file = fileList {
                let next = file.pointee.next
                defer { LIBMTP_destroy_file_t(file) }
                let info = MTPFileInfo(cFile: file)

                if found == nil && info.name == component {
                    found = info
                }
                fileList = next
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

private func collectAllFolderIds(_ folder: UnsafeMutablePointer<LIBMTP_folder_struct>, into ids: inout Set<UInt32>) {
    ids.insert(folder.pointee.folder_id)
    if let child = folder.pointee.child {
        collectAllFolderIds(child, into: &ids)
    }
    if let sibling = folder.pointee.sibling {
        collectAllFolderIds(sibling, into: &ids)
    }
}

private func collectChildFolders(
    _ folder: UnsafeMutablePointer<LIBMTP_folder_struct>,
    parentId: UInt32,
    results: inout [MTPFileInfo],
    synthIds: inout Set<UInt32>
) {
    if folder.pointee.parent_id == parentId {
        results.append(MTPFileInfo(cFolder: folder))
        synthIds.insert(folder.pointee.folder_id)
    }
    if let child = folder.pointee.child {
        collectChildFolders(child, parentId: parentId, results: &results, synthIds: &synthIds)
    }
    if let sibling = folder.pointee.sibling {
        collectChildFolders(sibling, parentId: parentId, results: &results, synthIds: &synthIds)
    }
}
