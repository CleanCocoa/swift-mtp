@preconcurrency import Clibmtp

/// Wraps the root of a folder tree returned by `LIBMTP_Get_Folder_List`.
///
/// ## C contract
/// Unlike `LIBMTP_destroy_file_t`, `LIBMTP_destroy_folder_t` frees **recursively** — it walks
/// `child` and `sibling` pointers and frees the entire subtree. Only the root should be
/// wrapped. Child pointers borrowed from the tree must not outlive this wrapper.
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
	var current: UnsafeMutablePointer<LIBMTP_folder_struct>? = folder
	while let node = current {
		ids.insert(ObjectID(rawValue: node.pointee.folder_id))
		if let child = node.pointee.child {
			_collectAllFolderIds(child, into: &ids)
		}
		current = node.pointee.sibling
	}
}

private func _collectChildFolders(
	_ folder: UnsafeMutablePointer<LIBMTP_folder_struct>,
	parentId: ObjectID,
	results: inout [FileInfo],
	synthIds: inout Set<ObjectID>
) {
	var current: UnsafeMutablePointer<LIBMTP_folder_struct>? = folder
	while let node = current {
		if node.pointee.parent_id == parentId.rawValue {
			results.append(FileInfo(cFolder: node))
			synthIds.insert(ObjectID(rawValue: node.pointee.folder_id))
		}
		if let child = node.pointee.child {
			_collectChildFolders(child, parentId: parentId, results: &results, synthIds: &synthIds)
		}
		current = node.pointee.sibling
	}
}
