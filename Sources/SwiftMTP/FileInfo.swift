import Clibmtp
import Foundation

/// Metadata for a file or folder on an MTP device.
///
/// Obtain instances through the `Device` API:
///
/// ```swift
/// // Single lookup by ID
/// let info = try device.info(for: objectID)
///
/// // Directory listing
/// let entries = try device.contents(of: .root)
///
/// // Upload — returns device-assigned metadata (id, filename, storage)
/// let uploaded = try device.upload(from: "/tmp/photo.jpg",
///                                  to: .root, storage: storage,
///                                  as: "photo.jpg")
/// print(uploaded.id, uploaded.name, uploaded.storageId)
///
/// // Create directory — returns new folder metadata
/// let dir = try device.makeDirectory(named: "Photos",
///                                    in: .root, storage: storage)
///
/// // Rename — returns updated metadata
/// let renamed = try device.rename(objectID, to: "Vacation")
/// ```
public struct FileInfo: Sendable {
	public let id: ObjectID
	public let parentId: ObjectID
	public let storageId: StorageID
	public let name: String
	public let size: UInt64
	public let modificationDate: Date
	public let isDirectory: Bool

	public var folder: Folder? { isDirectory ? Folder(id: id) : nil }

	public init(
		id: ObjectID,
		parentId: ObjectID,
		storageId: StorageID,
		name: String,
		size: UInt64,
		modificationDate: Date,
		isDirectory: Bool
	) {
		self.id = id
		self.parentId = parentId
		self.storageId = storageId
		self.name = name
		self.size = size
		self.modificationDate = modificationDate
		self.isDirectory = isDirectory
	}

	init(cFile: UnsafeMutablePointer<LIBMTP_file_struct>) {
		let f = cFile.pointee
		id = ObjectID(rawValue: f.item_id)
		parentId = ObjectID(rawValue: f.parent_id)
		storageId = StorageID(rawValue: f.storage_id)
		name = f.filename.map { String(cString: $0) } ?? ""
		size = f.filesize
		modificationDate = Date(timeIntervalSince1970: TimeInterval(f.modificationdate))
		isDirectory = f.filetype == LIBMTP_FILETYPE_FOLDER
	}

	public enum SortOrder: Sendable {
		case byName
		case byNameDescending
		case bySize
		case bySizeDescending
		case byDate
		case byDateDescending
		case directoriesFirst
	}

	public static func comparator(for order: SortOrder) -> (FileInfo, FileInfo) -> Bool {
		switch order {
		case .byName:
			{ $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		case .byNameDescending:
			{ $1.name.localizedStandardCompare($0.name) == .orderedAscending }
		case .bySize:
			{ $0.size < $1.size }
		case .bySizeDescending:
			{ $0.size > $1.size }
		case .byDate:
			{ $0.modificationDate < $1.modificationDate }
		case .byDateDescending:
			{ $0.modificationDate > $1.modificationDate }
		case .directoriesFirst:
			{
				if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
				return $0.name.localizedStandardCompare($1.name) == .orderedAscending
			}
		}
	}

	init(cFolder: UnsafeMutablePointer<LIBMTP_folder_struct>) {
		let f = cFolder.pointee
		id = ObjectID(rawValue: f.folder_id)
		parentId = ObjectID(rawValue: f.parent_id)
		storageId = StorageID(rawValue: f.storage_id)
		name = f.name.map { String(cString: $0) } ?? ""
		size = 0
		modificationDate = .distantPast
		isDirectory = true
	}
}

extension Sequence where Element == FileInfo {
	public func sorted(_ order: FileInfo.SortOrder) -> [FileInfo] {
		sorted(by: FileInfo.comparator(for: order))
	}
}
