import Clibmtp
import Foundation
import Testing

@testable import SwiftMTP

@Test func `swift build imports Clibmtp`() {
	#expect(!swiftMTPVersion.isEmpty)
}

@Test func `MTPError is Equatable`() {
	#expect(MTPError.noDeviceAttached == .noDeviceAttached)
	#expect(MTPError.storageFull == .storageFull)
	#expect(MTPError.moveNotSupported == .moveNotSupported)
	#expect(MTPError.cancelled == .cancelled)
	#expect(MTPError.noDeviceAttached != .storageFull)
	#expect(MTPError.moveNotSupported != .cancelled)
	#expect(MTPError.deviceDisconnected == .deviceDisconnected)
	#expect(MTPError.deviceDisconnected != .cancelled)
}

@Test func `MTPError is Sendable`() {
	let _: any Sendable = MTPError.noDeviceAttached
	let _: any Sendable = MTPError.storageFull
	let _: any Sendable = MTPError.moveNotSupported
	let _: any Sendable = MTPError.cancelled
	let _: any Sendable = MTPError.deviceDisconnected
}

@Test func `MTPError cases with associated values`() {
	let e1 = MTPError.noDeviceAttached
	let e2 = MTPError.connectionFailed(bus: 3, devnum: 7)
	let e3 = MTPError.storageFull
	let e4 = MTPError.objectNotFound(id: ObjectID(rawValue: 42))
	let e5 = MTPError.operationFailed("bad op")
	let e6 = MTPError.pathNotFound("/foo/bar")
	let e7 = MTPError.moveNotSupported
	let e8 = MTPError.cancelled
	let e9 = MTPError.deviceDisconnected

	#expect(e1 == .noDeviceAttached)
	#expect(e2 == .connectionFailed(bus: 3, devnum: 7))
	#expect(e2 != .connectionFailed(bus: 3, devnum: 8))
	#expect(e2 != .connectionFailed(bus: 4, devnum: 7))
	#expect(e3 == .storageFull)
	#expect(e4 == .objectNotFound(id: ObjectID(rawValue: 42)))
	#expect(e4 != .objectNotFound(id: ObjectID(rawValue: 99)))
	#expect(e5 == .operationFailed("bad op"))
	#expect(e5 != .operationFailed("other"))
	#expect(e6 == .pathNotFound("/foo/bar"))
	#expect(e6 != .pathNotFound("/baz"))
	#expect(e7 == .moveNotSupported)
	#expect(e8 == .cancelled)
	#expect(e9 == .deviceDisconnected)
}

@Test func `RawDevice stores properties`() {
	let dev = RawDevice(
		busLocation: 1,
		devnum: 2,
		vendor: "Acme",
		vendorId: 0x1234,
		product: "Widget",
		productId: 0x5678
	)
	#expect(dev.busLocation == 1)
	#expect(dev.devnum == 2)
	#expect(dev.vendor == "Acme")
	#expect(dev.vendorId == 0x1234)
	#expect(dev.product == "Widget")
	#expect(dev.productId == 0x5678)
}

@Test func `FileInfo stores file properties`() {
	let date = Date(timeIntervalSince1970: 1000)
	let info = FileInfo(
		id: ObjectID(rawValue: 1),
		parentId: ObjectID(rawValue: 0),
		storageId: StorageID(rawValue: 100),
		name: "test.txt",
		size: 1024,
		modificationDate: date,
		isDirectory: false
	)
	#expect(info.id == ObjectID(rawValue: 1))
	#expect(info.parentId == ObjectID(rawValue: 0))
	#expect(info.storageId == StorageID(rawValue: 100))
	#expect(info.name == "test.txt")
	#expect(info.size == 1024)
	#expect(info.modificationDate == date)
	#expect(info.isDirectory == false)
	#expect(info.folder == nil)
}

@Test func `FileInfo stores directory properties`() {
	let dir = FileInfo(
		id: ObjectID(rawValue: 5),
		parentId: ObjectID(rawValue: 0),
		storageId: StorageID(rawValue: 200),
		name: "Photos",
		size: 0,
		modificationDate: .distantPast,
		isDirectory: true
	)
	#expect(dir.id == ObjectID(rawValue: 5))
	#expect(dir.parentId == ObjectID(rawValue: 0))
	#expect(dir.storageId == StorageID(rawValue: 200))
	#expect(dir.name == "Photos")
	#expect(dir.size == 0)
	#expect(dir.modificationDate == .distantPast)
	#expect(dir.isDirectory == true)
	#expect(dir.folder == Folder(id: ObjectID(rawValue: 5)))
}

@Test func `StorageInfo stores properties`() {
	let storage = StorageInfo(
		id: StorageID(rawValue: 0xABCD),
		description: "Internal Storage",
		maxCapacity: 64_000_000_000,
		freeSpace: 32_000_000_000
	)
	#expect(storage.id == StorageID(rawValue: 0xABCD))
	#expect(storage.description == "Internal Storage")
	#expect(storage.maxCapacity == 64_000_000_000)
	#expect(storage.freeSpace == 32_000_000_000)
}

@Test func `StorageInfo usedSpace is maxCapacity minus freeSpace`() {
	let storage = StorageInfo(
		id: StorageID(rawValue: 1),
		description: "",
		maxCapacity: 100,
		freeSpace: 40
	)
	#expect(storage.usedSpace == 60)
}

@Test func `StorageInfo percentFull is ratio of used to max`() {
	let storage = StorageInfo(
		id: StorageID(rawValue: 1),
		description: "",
		maxCapacity: 200,
		freeSpace: 50
	)
	#expect(storage.percentFull == 0.75)
}

@Test func `StorageInfo percentFull is zero when maxCapacity is zero`() {
	let storage = StorageInfo(
		id: StorageID(rawValue: 1),
		description: "",
		maxCapacity: 0,
		freeSpace: 0
	)
	#expect(storage.percentFull == 0.0)
}

@Test func `Folder equality for same ID`() {
	let a = Folder(id: ObjectID(rawValue: 7))
	let b = Folder(id: ObjectID(rawValue: 7))
	let c = Folder(id: ObjectID(rawValue: 8))
	#expect(a == b)
	#expect(a != c)
	#expect(Folder.root == Folder(id: ObjectID(rawValue: 0)))
}

@Test func `StorageID.all is zero`() {
	#expect(StorageID.all == StorageID(rawValue: 0))
}

@Test func `ObjectID and StorageID round-trip through rawValue`() {
	let obj = ObjectID(rawValue: 42)
	#expect(ObjectID(rawValue: obj.rawValue) == obj)
	let sid = StorageID(rawValue: 99)
	#expect(StorageID(rawValue: sid.rawValue) == sid)
}

@Test func `nominal type descriptions`() {
	#expect(ObjectID(rawValue: 5).description == "ObjectID(5)")
	#expect(StorageID(rawValue: 10).description == "StorageID(10)")
	#expect(Folder.root.description == "Folder(0)")
}

@Test func `DeviceCapability has all cases`() {
	let caps: [DeviceCapability] = [.moveObject, .copyObject, .getPartialObject, .sendPartialObject, .editObjects]
	#expect(caps.count == 5)
}

@Test func `mtpInitialize is idempotent`() {
	mtpInitialize()
	mtpInitialize()
}

@Test func `withProgressCallback nil handler passes nil`() {
	withProgressCallback(nil) { callback, context in
		#expect(callback == nil)
		#expect(context == nil)
	}
}

@Test func `withProgressCallback non-nil handler provides pointers`() {
	let handler: ProgressHandler = { _, _ in true }
	withProgressCallback(handler) { callback, context in
		#expect(callback != nil)
		#expect(context != nil)
	}
}

@Test func `Event is Equatable`() {
	let a = Event.objectAdded(ObjectID(rawValue: 1))
	let b = Event.objectAdded(ObjectID(rawValue: 1))
	let c = Event.objectAdded(ObjectID(rawValue: 2))
	let d = Event.objectRemoved(ObjectID(rawValue: 1))
	#expect(a == b)
	#expect(a != c)
	#expect(a != d)
	#expect(Event.devicePropertyChanged == .devicePropertyChanged)
}

@Test func `Event is Sendable`() {
	let _: any Sendable = Event.storeAdded(StorageID(rawValue: 1))
	let _: any Sendable = Event.storeRemoved(StorageID(rawValue: 1))
	let _: any Sendable = Event.objectAdded(ObjectID(rawValue: 1))
	let _: any Sendable = Event.objectRemoved(ObjectID(rawValue: 1))
	let _: any Sendable = Event.devicePropertyChanged
}

@Test func `Event init from C constants`() {
	#expect(Event(cEvent: LIBMTP_EVENT_STORE_ADDED, param: 5) == .storeAdded(StorageID(rawValue: 5)))
	#expect(Event(cEvent: LIBMTP_EVENT_STORE_REMOVED, param: 6) == .storeRemoved(StorageID(rawValue: 6)))
	#expect(Event(cEvent: LIBMTP_EVENT_OBJECT_ADDED, param: 7) == .objectAdded(ObjectID(rawValue: 7)))
	#expect(Event(cEvent: LIBMTP_EVENT_OBJECT_REMOVED, param: 8) == .objectRemoved(ObjectID(rawValue: 8)))
	#expect(Event(cEvent: LIBMTP_EVENT_DEVICE_PROPERTY_CHANGED, param: 0) == .devicePropertyChanged)
}

@Test func `Event init returns nil for EVENT_NONE`() {
	#expect(Event(cEvent: LIBMTP_EVENT_NONE, param: 0) == nil)
}

@Test func `Path with 3 components has count 3`() {
	let path: Path = "Music/Albums/track.mp3"
	#expect(path.components.count == 3)
}

@Test func `Path empty string returns nil`() {
	let s = ""
	#expect(Path(s) == nil)
}

@Test func `Path slash-only returns nil`() {
	let s = "/"
	#expect(Path(s) == nil)
}

@Test func `Path normalizes slashes and filters empty`() {
	let s = "/Music//Albums/"
	#expect(Path(s)?.components == ["Music", "Albums"])
}

@Test func `Path conforms to ExpressibleByStringLiteral`() {
	let path: Path = "Music/Albums"
	#expect(path.components == ["Music", "Albums"])
}

@Test func `Path description returns slash-joined components`() {
	let path: Path = "Music/Albums/track.mp3"
	#expect(path.description == "Music/Albums/track.mp3")
}

@Test func `Path equality for same components`() {
	let a: Path = "Music/Albums"
	let b: Path = "Music/Albums"
	let c: Path = "Music/Other"
	#expect(a == b)
	#expect(a != c)
}

private let deviceConnected = ProcessInfo.processInfo.environment["MTP_DEVICE_CONNECTED"] == "1"

@Test(.disabled(if: deviceConnected, "Device is connected, detection will return results"))
func `mtpDetectDevices returns empty without device`() throws {
	mtpInitialize()
	let devices = try mtpDetectDevices()
	#expect(devices.isEmpty)
}

@Suite(.serialized, .enabled(if: deviceConnected, "Skipping: no MTP device connected"))
struct HardwareTests {
	@Test func `detect devices finds at least one`() throws {
		mtpInitialize()
		let devices = try mtpDetectDevices()
		#expect(!devices.isEmpty)
	}

	@Test func `open device and read properties`() throws {
		mtpInitialize()
		let devices = try mtpDetectDevices()
		var raw = try #require(devices.first)
		let device = try raw.open()
		#expect(
			device.manufacturerName != nil || device.modelName != nil || device.serialNumber != nil
				|| device.friendlyName != nil || device.deviceVersion != nil
		)
		let storages = device.storageInfo()
		#expect(!storages.isEmpty)
		#expect(device.defaultStorage?.id == storages.first?.id)
	}

	@Test func `list root directory`() throws {
		mtpInitialize()
		let devices = try mtpDetectDevices()
		var raw = try #require(devices.first)
		let device = try raw.open()
		let entries = try device.contents()
		#expect(!entries.isEmpty)
		for entry in entries {
			#expect(!entry.name.isEmpty)
		}
	}
}
