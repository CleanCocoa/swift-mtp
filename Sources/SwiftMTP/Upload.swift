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

	consuming func send(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		from localPath: String,
		progress: ProgressHandler?
	) -> Uploaded {
		let p = pointer
		discard self
		let ret = withProgressCallback(progress) { callback, context in
			LIBMTP_Send_File_From_File(device, localPath, p, callback, context)
		}
		return Uploaded(pointer: p, result: ret)
	}

	struct Uploaded: ~Copyable {
		private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>
		let result: CInt
		fileprivate init(pointer: UnsafeMutablePointer<LIBMTP_file_struct>, result: CInt) {
			self.pointer = pointer
			self.result = result
		}
		deinit { LIBMTP_destroy_file_t(pointer) }
		var itemId: UInt32 { pointer.pointee.item_id }
	}
}
