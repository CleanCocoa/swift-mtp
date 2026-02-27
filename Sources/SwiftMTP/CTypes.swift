import Clibmtp
import Foundation

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

struct FileHandle: ~Copyable {
	private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

	init?(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>, id: UInt32) {
		guard let p = LIBMTP_Get_Filemetadata(device, id) else { return nil }
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

struct FolderTree: ~Copyable {
	private let root: UnsafeMutablePointer<LIBMTP_folder_struct>

	init?(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>) {
		guard let p = LIBMTP_Get_Folder_List(device) else { return nil }
		self.root = p
	}

	deinit { LIBMTP_destroy_folder_t(root) }

	func collectAllFolderIds(into ids: inout Set<UInt32>) {
		_collectAllFolderIds(root, into: &ids)
	}

	func collectChildFolders(
		parentId: UInt32,
		results: inout [FileInfo],
		synthIds: inout Set<UInt32>
	) {
		_collectChildFolders(root, parentId: parentId, results: &results, synthIds: &synthIds)
	}

	func rename(
		device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
		folderId: UInt32,
		to newName: String
	) -> CInt? {
		guard let folder = LIBMTP_Find_Folder(root, folderId) else { return nil }
		return LIBMTP_Set_Folder_Name(device, folder, newName)
	}
}

private func _collectAllFolderIds(_ folder: UnsafeMutablePointer<LIBMTP_folder_struct>, into ids: inout Set<UInt32>) {
	ids.insert(folder.pointee.folder_id)
	if let child = folder.pointee.child {
		_collectAllFolderIds(child, into: &ids)
	}
	if let sibling = folder.pointee.sibling {
		_collectAllFolderIds(sibling, into: &ids)
	}
}

private func _collectChildFolders(
	_ folder: UnsafeMutablePointer<LIBMTP_folder_struct>,
	parentId: UInt32,
	results: inout [FileInfo],
	synthIds: inout Set<UInt32>
) {
	if folder.pointee.parent_id == parentId {
		results.append(FileInfo(cFolder: folder))
		synthIds.insert(folder.pointee.folder_id)
	}
	if let child = folder.pointee.child {
		_collectChildFolders(child, parentId: parentId, results: &results, synthIds: &synthIds)
	}
	if let sibling = folder.pointee.sibling {
		_collectChildFolders(sibling, parentId: parentId, results: &results, synthIds: &synthIds)
	}
}
