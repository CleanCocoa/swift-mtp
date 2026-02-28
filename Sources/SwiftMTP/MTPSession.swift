import Clibmtp
import Foundation

public actor MTPSession {
	private let device: Device
	nonisolated(unsafe) private let rawDevice: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>

	public nonisolated let manufacturerName: String?
	public nonisolated let modelName: String?
	public nonisolated let serialNumber: String?
	public nonisolated let friendlyName: String?
	public nonisolated let deviceVersion: String?
	private nonisolated let capabilities: UInt64

	private init(device: Device) {
		self.device = device
		self.rawDevice = device.raw
		self.manufacturerName = device.manufacturerName
		self.modelName = device.modelName
		self.serialNumber = device.serialNumber
		self.friendlyName = device.friendlyName
		self.deviceVersion = device.deviceVersion
		self.capabilities = device.capabilityBitmask
	}

	public init(opening raw: inout RawDevice) throws(MTPError) {
		self.init(device: try raw.open())
	}

	public init(busLocation: BusLocation, devnum: DeviceNumber) throws(MTPError) {
		self.init(device: try Device(busLocation: busLocation, devnum: devnum))
	}

	public static func detect() throws(MTPError) -> [RawDevice] {
		try MTP.detectDevices()
	}
}

extension MTPSession {
	public nonisolated func supportsCapability(_ cap: DeviceCapability) -> Bool {
		capabilities & cap.bitmask != 0
	}
}

extension MTPSession {
	public nonisolated func events() -> AsyncStream<Event> {
		SwiftMTP.eventStream(device: rawDevice, owner: self)
	}

	public func readEvent() throws(MTPError) -> Event {
		try device.readEvent()
	}

	nonisolated func testEventStream(owner: AnyObject) -> AsyncStream<Event> {
		SwiftMTP.eventStream(device: rawDevice, owner: owner)
	}
}

extension MTPSession {
	public func contents(
		of parent: Folder = .root,
		storage: StorageID = .all
	) throws(MTPError) -> [FileInfo] {
		try device.contents(of: parent, storage: storage)
	}

	public func contents(
		of parent: Folder = .root,
		storage: StorageInfo
	) throws(MTPError) -> [FileInfo] {
		try device.contents(of: parent, storage: storage)
	}

	public func resolvePath(_ path: String, storage: StorageID = .all) throws(MTPError) -> FileInfo? {
		try device.resolvePath(path, storage: storage)
	}

	public func resolvePath(_ path: String, storage: StorageInfo) throws(MTPError) -> FileInfo? {
		try device.resolvePath(path, storage: storage)
	}

	public func resolvePath(_ path: Path, storage: StorageID = .all) throws(MTPError) -> FileInfo? {
		try device.resolvePath(path, storage: storage)
	}

	public func resolvePath(_ path: Path, storage: StorageInfo) throws(MTPError) -> FileInfo? {
		try device.resolvePath(path, storage: storage)
	}
}

extension MTPSession {
	public func download(
		_ id: ObjectID,
		to url: URL,
		progress: ProgressHandler? = nil
	) throws(MTPError) {
		try device.download(id, to: url, progress: progress)
	}

	public func download(
		_ id: ObjectID,
		to localPath: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) {
		try device.download(id, to: localPath, progress: progress)
	}

	@discardableResult
	public func upload(
		from url: URL,
		to parent: Folder,
		storage: StorageID,
		as filename: String? = nil,
		progress: ProgressHandler? = nil
	) throws(MTPError) -> FileInfo {
		try device.upload(from: url, to: parent, storage: storage, as: filename, progress: progress)
	}

	@discardableResult
	public func upload(
		from localPath: String,
		to parent: Folder,
		storage: StorageID,
		as filename: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) -> FileInfo {
		try device.upload(from: localPath, to: parent, storage: storage, as: filename, progress: progress)
	}

	@discardableResult
	public func upload(
		from url: URL,
		to parent: Folder,
		storage: StorageInfo,
		as filename: String? = nil,
		progress: ProgressHandler? = nil
	) throws(MTPError) -> FileInfo {
		try device.upload(from: url, to: parent, storage: storage, as: filename, progress: progress)
	}

	@discardableResult
	public func upload(
		from localPath: String,
		to parent: Folder,
		storage: StorageInfo,
		as filename: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) -> FileInfo {
		try device.upload(from: localPath, to: parent, storage: storage, as: filename, progress: progress)
	}

	public func info(for id: ObjectID) throws(MTPError) -> FileInfo {
		try device.info(for: id)
	}

	public func delete(_ id: ObjectID) throws(MTPError) {
		try device.delete(id)
	}

	@discardableResult
	public func makeDirectory(named name: String, in parent: Folder, storage: StorageID) throws(MTPError) -> FileInfo {
		try device.makeDirectory(named: name, in: parent, storage: storage)
	}

	@discardableResult
	public func makeDirectory(named name: String, in parent: Folder, storage: StorageInfo) throws(MTPError) -> FileInfo {
		try device.makeDirectory(named: name, in: parent, storage: storage)
	}

	public func move(_ id: ObjectID, to parent: Folder, storage: StorageID) throws(MTPError) {
		try device.move(id, to: parent, storage: storage)
	}

	public func move(_ id: ObjectID, to parent: Folder, storage: StorageInfo) throws(MTPError) {
		try device.move(id, to: parent, storage: storage)
	}

	@discardableResult
	public func rename(_ id: ObjectID, to newName: String) throws(MTPError) -> FileInfo {
		try device.rename(id, to: newName)
	}

	public func download(
		_ file: some FileReference,
		to url: URL,
		progress: ProgressHandler? = nil
	) throws(MTPError) {
		try device.download(file, to: url, progress: progress)
	}

	public func download(
		_ file: some FileReference,
		to localPath: String,
		progress: ProgressHandler? = nil
	) throws(MTPError) {
		try device.download(file, to: localPath, progress: progress)
	}

	public func info(for file: some FileReference) throws(MTPError) -> FileInfo {
		try device.info(for: file)
	}

	public func delete(_ file: some FileReference) throws(MTPError) {
		try device.delete(file)
	}

	@discardableResult
	public func rename(_ file: some FileReference, to newName: String) throws(MTPError) -> FileInfo {
		try device.rename(file, to: newName)
	}

	public func move(_ file: some FileReference, to parent: Folder, storage: StorageID) throws(MTPError) {
		try device.move(file, to: parent, storage: storage)
	}

	public func move(_ file: some FileReference, to parent: Folder, storage: StorageInfo) throws(MTPError) {
		try device.move(file, to: parent, storage: storage)
	}
}

extension MTPSession {
	public func storageInfo() -> [StorageInfo] {
		device.storageInfo()
	}

	public func storages() -> [Storage] {
		device.storageInfo().map { Storage(session: self, info: $0) }
	}

	public var defaultStorage: Storage? {
		device.storageInfo().first.map { Storage(session: self, info: $0) }
	}
}
