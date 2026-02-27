import Clibmtp

struct FolderTree: ~Copyable {
	private let root: UnsafeMutablePointer<LIBMTP_folder_struct>

	init?(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>) {
		guard let p = LIBMTP_Get_Folder_List(device) else { return nil }
		self.root = p
	}

	deinit { LIBMTP_destroy_folder_t(root) }

	func collectAllFolderIds(into ids: inout Set<ObjectID>) {
		_collectAllFolderIds(root, into: &ids)
	}

	func collectChildFolders(
		parentId: ObjectID,
		results: inout [FileInfo],
		synthIds: inout Set<ObjectID>
	) {
		_collectChildFolders(root, parentId: parentId, results: &results, synthIds: &synthIds)
	}

	func rename(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		folderId: ObjectID,
		to newName: String
	) -> (result: CInt, info: FileInfo)? {
		guard let folder = LIBMTP_Find_Folder(root, folderId.rawValue) else { return nil }
		let result = LIBMTP_Set_Folder_Name(device, folder, newName)
		return (result, FileInfo(cFolder: folder))
	}
}

private func _collectAllFolderIds(_ folder: UnsafeMutablePointer<LIBMTP_folder_struct>, into ids: inout Set<ObjectID>) {
	ids.insert(ObjectID(rawValue: folder.pointee.folder_id))
	if let child = folder.pointee.child {
		_collectAllFolderIds(child, into: &ids)
	}
	if let sibling = folder.pointee.sibling {
		_collectAllFolderIds(sibling, into: &ids)
	}
}

private func _collectChildFolders(
	_ folder: UnsafeMutablePointer<LIBMTP_folder_struct>,
	parentId: ObjectID,
	results: inout [FileInfo],
	synthIds: inout Set<ObjectID>
) {
	if folder.pointee.parent_id == parentId.rawValue {
		results.append(FileInfo(cFolder: folder))
		synthIds.insert(ObjectID(rawValue: folder.pointee.folder_id))
	}
	if let child = folder.pointee.child {
		_collectChildFolders(child, parentId: parentId, results: &results, synthIds: &synthIds)
	}
	if let sibling = folder.pointee.sibling {
		_collectChildFolders(sibling, parentId: parentId, results: &results, synthIds: &synthIds)
	}
}
