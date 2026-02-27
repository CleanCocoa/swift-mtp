import Clibmtp

/// Wraps a single `LIBMTP_file_struct` returned by `LIBMTP_Get_Filemetadata`.
///
/// ## C contract
/// `LIBMTP_destroy_file_t` frees only the single node (not `->next`). Safe for single-item
/// ownership.
struct FileHandle: ~Copyable {
	private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

	init?(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>, id: ObjectID) {
		guard let p = LIBMTP_Get_Filemetadata(device, id.rawValue) else { return nil }
		self.pointer = p
	}

	deinit { LIBMTP_destroy_file_t(pointer) }

	func toFileInfo() -> FileInfo { FileInfo(cFile: pointer) }

	func rename(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		to newName: String
	) -> CInt {
		LIBMTP_Set_File_Name(device, pointer, newName)
	}

	func download(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		to localPath: String,
		callback: LIBMTP_progressfunc_t?,
		data: UnsafeMutableRawPointer?
	) -> CInt {
		LIBMTP_Get_File_To_File(device, pointer.pointee.item_id, localPath, callback, data)
	}
}
