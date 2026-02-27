import Clibmtp

struct FileNode: ~Copyable {
	private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

	init(_ pointer: UnsafeMutablePointer<LIBMTP_file_struct>) {
		self.pointer = pointer
	}

	deinit { LIBMTP_destroy_file_t(pointer) }

	var next: UnsafeMutablePointer<LIBMTP_file_struct>? { pointer.pointee.next }

	func toFileInfo() -> FileInfo { FileInfo(cFile: pointer) }
	var itemId: UInt32 { pointer.pointee.item_id }
	var parentId: UInt32 { pointer.pointee.parent_id }
	var isFolder: Bool { pointer.pointee.filetype == LIBMTP_FILETYPE_FOLDER }

	static func list(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		storageId: UInt32,
		parentId: UInt32
	) -> UnsafeMutablePointer<LIBMTP_file_struct>? {
		LIBMTP_Get_Files_And_Folders(device, storageId, parentId)
	}
}
