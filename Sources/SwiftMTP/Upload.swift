import Clibmtp

struct Upload: ~Copyable {
	private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

	init?(filename: String, filesize: UInt64, parentId: UInt32, storageId: UInt32) {
		guard let p = LIBMTP_new_file_t() else { return nil }
		p.pointee.filename = strdup(filename)
		p.pointee.filesize = filesize
		p.pointee.parent_id = parentId
		p.pointee.storage_id = storageId
		p.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
		self.pointer = p
	}

	deinit { LIBMTP_destroy_file_t(pointer) }

	var itemId: UInt32 { pointer.pointee.item_id }

	func send(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		from localPath: String,
		callback: LIBMTP_progressfunc_t?,
		data: UnsafeMutableRawPointer?
	) -> CInt {
		LIBMTP_Send_File_From_File(device, localPath, pointer, callback, data)
	}
}
