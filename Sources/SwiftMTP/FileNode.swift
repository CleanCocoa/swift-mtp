import Clibmtp

/// Wraps a single node from a flat linked list returned by `LIBMTP_Get_Files_And_Folders`.
///
/// ## C contract
/// `LIBMTP_destroy_file_t` frees only the single node passed to it — it does **not** walk
/// `->next`. This is what makes per-node ownership safe: each `FileNode` owns exactly one
/// node, and iterating the list transfers ownership node-by-node via `next` before `deinit`.
struct FileNode: ~Copyable {
	private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

	init(_ pointer: UnsafeMutablePointer<LIBMTP_file_struct>) {
		self.pointer = pointer
	}

	deinit { LIBMTP_destroy_file_t(pointer) }

	var next: UnsafeMutablePointer<LIBMTP_file_struct>? { pointer.pointee.next }

	func toFileInfo() -> FileInfo { FileInfo(cFile: pointer) }
	var itemId: ObjectID { ObjectID(rawValue: pointer.pointee.item_id) }
	var parentId: ObjectID { ObjectID(rawValue: pointer.pointee.parent_id) }
	var isFolder: Bool { pointer.pointee.filetype == LIBMTP_FILETYPE_FOLDER }

	static func list(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		storageId: StorageID,
		parentId: ObjectID
	) -> UnsafeMutablePointer<LIBMTP_file_struct>? {
		LIBMTP_Get_Files_And_Folders(device, storageId.rawValue, parentId.rawValue)
	}
}
