# SwiftMTP Public API Reference

SwiftMTP is a Swift wrapper around libmtp for communicating with MTP (Media Transfer Protocol) devices such as phones, cameras, and portable media players.

---

## Getting Started

The typical flow is: **initialize → detect → open → operate → release**.

1. Call `mtpInitialize()` once at startup.
2. Call `mtpDetectDevices()` to enumerate connected MTP devices as `[RawDevice]`.
3. Call `rawDevice.open()` to get a `Device` — the main handle for all operations.
4. Use `Device` methods directly, or obtain a `Storage` for convenience-scoped operations.
5. `Device` releases the connection automatically when it is deallocated.

```swift
import SwiftMTP

mtpInitialize()

let rawDevices = try mtpDetectDevices()
guard var raw = rawDevices.first else {
    print("No device found")
    exit(0)
}

let device = try raw.open()

print(device.friendlyName ?? "Unknown device")
print(device.modelName ?? "")

let entries = try device.contents(of: .root)
for entry in entries {
    let kind = entry.isDirectory ? "DIR " : "FILE"
    print("\(kind) \(entry.name) (\(entry.size) bytes)")
}

guard let storage = device.defaultStorage else {
    print("No storage")
    exit(0)
}

let uploaded = try device.upload(
    from: "/tmp/photo.jpg",
    to: .root,
    storage: storage.info,
    as: "photo.jpg"
) { sent, total in
    print("\(sent)/\(total)")
    return .continue
}
print("Uploaded as object \(uploaded.id)")

try device.download(uploaded.id, to: "/tmp/photo-copy.jpg")
```

---

## Types

### ID Types

These nominal wrapper types prevent accidentally passing a storage ID where an object ID is expected, or treating a generic object ID as a folder.

#### `ObjectID`

A type-safe identifier for any MTP object (file or folder) on a device.

```swift
public struct ObjectID: RawRepresentable, Hashable, Sendable, CustomStringConvertible
```

| Member | Description |
|--------|-------------|
| `init(rawValue: UInt32)` | Creates an ObjectID from a raw UInt32. |
| `rawValue: UInt32` | The underlying numeric identifier. |
| `description: String` | Human-readable form: `"ObjectID(42)"`. |

You receive `ObjectID` values from `FileInfo.id` and use them to identify objects in `download`, `delete`, `rename`, `move`, and `info(for:)` calls.

---

#### `StorageID`

A type-safe identifier for a storage pool on a device (e.g., internal memory, SD card).

```swift
public struct StorageID: RawRepresentable, Hashable, Sendable, CustomStringConvertible
```

| Member | Description |
|--------|-------------|
| `init(rawValue: UInt32)` | Creates a StorageID from a raw UInt32. |
| `rawValue: UInt32` | The underlying numeric identifier. |
| `static let all: StorageID` | Sentinel value (rawValue 0) meaning "all storages". Pass this when you do not want to filter by storage. |
| `description: String` | Human-readable form: `"StorageID(65537)"`. |

---

#### `Folder`

A type-safe wrapper around an `ObjectID` that is known to be a directory.

```swift
public struct Folder: Hashable, Sendable, CustomStringConvertible
```

| Member | Description |
|--------|-------------|
| `id: ObjectID` | The object identifier of this folder. |
| `static let root: Folder` | The root folder (object ID 0). Pass this to list or upload into the top level of a storage. |
| `description: String` | Human-readable form: `"Folder(0)"`. |

You obtain non-root `Folder` values from `FileInfo.folder`. This computed property returns `nil` for files and a `Folder` for directories, so the compiler enforces that you can only upload into something you have confirmed is a directory.

```swift
let entries = try device.contents(of: .root)
if let dir = entries.first(where: { $0.name == "Photos" }),
   let folder = dir.folder {
    try device.upload(from: "/tmp/img.jpg", to: folder, storage: storageId, as: "img.jpg")
}
```

---

### File and Storage Metadata

#### `FileInfo`

Metadata for a file or folder on an MTP device.

```swift
public struct FileInfo: Sendable
```

| Property | Type | Description |
|----------|------|-------------|
| `id` | `ObjectID` | The object's identifier on the device. |
| `parentId` | `ObjectID` | The identifier of the containing folder. |
| `storageId` | `StorageID` | The storage pool this object lives in. |
| `name` | `String` | The filename or directory name. |
| `size` | `UInt64` | File size in bytes. Zero for directories. |
| `modificationDate` | `Date` | Last-modified timestamp. `Date.distantPast` for directories created via `makeDirectory`. |
| `isDirectory` | `Bool` | `true` if this entry is a folder. |
| `folder` | `Folder?` | Returns a `Folder` when `isDirectory` is `true`, otherwise `nil`. Use this to chain into upload or listing calls. |

`FileInfo` has a public memberwise initializer for testing:

```swift
public init(
    id: ObjectID,
    parentId: ObjectID,
    storageId: StorageID,
    name: String,
    size: UInt64,
    modificationDate: Date,
    isDirectory: Bool
)
```

---

#### `StorageInfo`

Metadata describing a single storage pool (capacity, free space, label).

```swift
public struct StorageInfo: Sendable
```

| Property | Type | Description |
|----------|------|-------------|
| `id` | `StorageID` | Identifier for this storage. |
| `description` | `String` | Human-readable label, e.g. `"Internal storage"`. |
| `maxCapacity` | `UInt64` | Total capacity in bytes. |
| `freeSpace` | `UInt64` | Available space in bytes. |

`StorageInfo` has a public memberwise initializer for testing:

```swift
public init(id: StorageID, description: String, maxCapacity: UInt64, freeSpace: UInt64)
```

---

### Device Types

#### `RawDevice`

An unopened, enumerated MTP device — a lightweight description obtained from `mtpDetectDevices()`.

```swift
public struct RawDevice: Sendable
```

| Property | Type | Description |
|----------|------|-------------|
| `busLocation` | `UInt32` | USB bus number. Together with `devnum`, uniquely identifies the physical device. |
| `devnum` | `UInt8` | USB device number on the bus. |
| `vendor` | `String` | Vendor name string, e.g. `"Apple Inc."`. |
| `vendorId` | `UInt16` | USB vendor ID. |
| `product` | `String` | Product name string, e.g. `"iPhone"`. |
| `productId` | `UInt16` | USB product ID. |

**Methods**

```swift
public mutating func open() throws(MTPError) -> Device
```

Opens a connection to the device and returns a `Device`. Throws `MTPError.connectionFailed` if the device cannot be opened. Note this method is `mutating` because libmtp mutates the underlying raw device descriptor during connection.

`RawDevice` also has a public memberwise initializer for constructing instances in tests:

```swift
public init(
    busLocation: UInt32,
    devnum: UInt8,
    vendor: String,
    vendorId: UInt16,
    product: String,
    productId: UInt16
)
```

---

#### `Device`

An open connection to an MTP device. The connection is released when the instance is deallocated.

```swift
public final class Device
```

**Initializers**

```swift
public init(busLocation: UInt32, devnum: UInt8) throws(MTPError)
```

Opens a connection to the device at the given bus location and device number, detecting all connected devices internally. Throws `MTPError.noDeviceAttached` if no devices are found or the specified device is not present, or `MTPError.connectionFailed` if the device cannot be opened. This is a convenience alternative to the `RawDevice.open()` path when you already know the bus/devnum from a previous session.

**Device Information Properties**

| Property | Type | Description |
|----------|------|-------------|
| `manufacturerName` | `String?` | Manufacturer name reported by the device. |
| `modelName` | `String?` | Model name reported by the device. |
| `serialNumber` | `String?` | Serial number reported by the device. |
| `friendlyName` | `String?` | User-visible friendly name (e.g. "My Phone"). |
| `deviceVersion` | `String?` | Firmware or device version string. |

**Storage Methods**

```swift
public func storageInfo() -> [StorageInfo]
```

Returns metadata for all storage pools on the device. Returns an empty array if no storage is available.

```swift
public func storages() -> [Storage]
```

Returns `Storage` wrappers for all storage pools. Each `Storage` is pre-bound to this device and provides the same file operations scoped to a single storage.

```swift
public var defaultStorage: Storage?
```

Returns the first storage pool, or `nil` if the device has no storage. Suitable for single-storage devices.

**File Operation Methods**

See the [File Operations](#file-operations) section for full details with examples.

```swift
public func contents(of parent: Folder = .root, storage: StorageID = .all) throws(MTPError) -> [FileInfo]
public func contents(of parent: Folder = .root, storage: StorageInfo) throws(MTPError) -> [FileInfo]
public func resolvePath(_ path: String, storage: StorageID = .all) throws(MTPError) -> FileInfo?
public func resolvePath(_ path: String, storage: StorageInfo) throws(MTPError) -> FileInfo?
public func info(for id: ObjectID) throws(MTPError) -> FileInfo
public func download(_ id: ObjectID, to localPath: String, progress: ProgressHandler? = nil) throws(MTPError)
@discardableResult public func upload(from localPath: String, to parent: Folder, storage: StorageID, as filename: String, progress: ProgressHandler? = nil) throws(MTPError) -> FileInfo
@discardableResult public func upload(from localPath: String, to parent: Folder, storage: StorageInfo, as filename: String, progress: ProgressHandler? = nil) throws(MTPError) -> FileInfo
public func delete(_ id: ObjectID) throws(MTPError)
@discardableResult public func makeDirectory(named name: String, in parent: Folder, storage: StorageID) throws(MTPError) -> FileInfo
@discardableResult public func makeDirectory(named name: String, in parent: Folder, storage: StorageInfo) throws(MTPError) -> FileInfo
public func move(_ id: ObjectID, to parent: Folder, storage: StorageID) throws(MTPError)
public func move(_ id: ObjectID, to parent: Folder, storage: StorageInfo) throws(MTPError)
@discardableResult public func rename(_ id: ObjectID, to newName: String) throws(MTPError) -> FileInfo
```

**Capability and Event Methods**

```swift
public func supportsCapability(_ cap: DeviceCapability) -> Bool
public func readEvent() throws(MTPError) -> Event
```

---

#### `DeviceCapability`

Optional capabilities that not all MTP devices support.

```swift
public enum DeviceCapability: Sendable
```

| Case | Description |
|------|-------------|
| `.moveObject` | Device supports moving objects between folders without re-uploading. Required for `move` to succeed. |
| `.copyObject` | Device supports copying objects. |
| `.getPartialObject` | Device supports reading byte ranges of objects. |
| `.sendPartialObject` | Device supports writing byte ranges of objects. |
| `.editObjects` | Device supports in-place editing of objects. |

Check capabilities before calling operations that may not be universally supported:

```swift
if device.supportsCapability(.moveObject) {
    try device.move(objectId, to: targetFolder, storage: storageId)
} else {
    // Fall back to download + delete + re-upload
}
```

---

#### `Storage`

A convenience wrapper that binds a `Device` to a specific storage pool, scoping all operations to that storage.

```swift
public struct Storage
```

| Property | Type | Description |
|----------|------|-------------|
| `info` | `StorageInfo` | The underlying storage metadata. |
| `id` | `StorageID` | The storage identifier. Forwarded from `info.id`. |
| `description` | `String` | Human-readable storage label. Forwarded from `info.description`. |
| `maxCapacity` | `UInt64` | Total capacity in bytes. Forwarded from `info.maxCapacity`. |
| `freeSpace` | `UInt64` | Available space in bytes. Forwarded from `info.freeSpace`. |

**Methods**

All methods are equivalent to the corresponding `Device` methods with the storage already bound.

```swift
public func contents(of parent: Folder = .root) throws(MTPError) -> [FileInfo]
public func resolvePath(_ path: String) throws(MTPError) -> FileInfo?
@discardableResult public func upload(from localPath: String, to parent: Folder, as filename: String, progress: ProgressHandler? = nil) throws(MTPError) -> FileInfo
@discardableResult public func makeDirectory(named name: String, in parent: Folder) throws(MTPError) -> FileInfo
public func move(_ objectId: ObjectID, to parent: Folder) throws(MTPError)
```

---

### Event Type

#### `Event`

A device-generated notification received via `Device.readEvent()`.

```swift
public enum Event: Sendable, Equatable
```

| Case | Associated Value | Description |
|------|-----------------|-------------|
| `.storeAdded(StorageID)` | The new storage's ID | A storage pool (e.g. SD card) was inserted. |
| `.storeRemoved(StorageID)` | The removed storage's ID | A storage pool was removed. |
| `.objectAdded(ObjectID)` | The new object's ID | A file or folder was added to the device. |
| `.objectRemoved(ObjectID)` | The removed object's ID | A file or folder was deleted from the device. |
| `.devicePropertyChanged` | — | A device property (e.g. battery, friendly name) changed. |

---

### Error Type

#### `MTPError`

All errors thrown by SwiftMTP operations.

```swift
public enum MTPError: Error, Equatable, Sendable
```

| Case | Associated Values | When thrown |
|------|------------------|-------------|
| `.noDeviceAttached` | — | `Device.init(busLocation:devnum:)` when no MTP device is connected. Note: `mtpDetectDevices()` returns an empty array instead of throwing. |
| `.connectionFailed(bus: UInt32, devnum: UInt8)` | Bus and device numbers | `RawDevice.open()` or `Device.init(busLocation:devnum:)` when the device is detected but cannot be opened. |
| `.storageFull` | — | `upload` when the device has no space remaining. |
| `.objectNotFound(id: ObjectID)` | The missing object's ID | `info(for:)` or `rename` when the specified object does not exist on the device. |
| `.operationFailed(String)` | Error message from libmtp | Any operation that returns a non-zero result from libmtp for an unclassified reason. The string contains the libmtp error stack. |
| `.pathNotFound(String)` | The path that was not found | Reserved for future use. Currently `resolvePath` returns `nil` for missing paths. |
| `.moveNotSupported` | — | `move` when the device does not implement the MoveObject operation. |
| `.cancelled` | — | `download` or `upload` when a `ProgressHandler` returned `.cancel`. |
| `.deviceDisconnected` | — | `readEvent()` when the device is disconnected or returns an unrecognized event. |

---

## Global Functions and Constants

#### `mtpInitialize()`

```swift
public func mtpInitialize()
```

Initializes the libmtp library. Call this once before any other SwiftMTP calls.

---

#### `mtpDetectDevices()`

```swift
public func mtpDetectDevices() throws(MTPError) -> [RawDevice]
```

Scans for connected MTP devices and returns them as `[RawDevice]`. Returns an empty array if no devices are attached (does not throw). Throws `MTPError.operationFailed` if the detection mechanism itself fails.

---

#### `swiftMTPVersion`

```swift
public let swiftMTPVersion: String
```

The version string of the underlying libmtp library.

---

#### `ProgressHandler`

```swift
public typealias ProgressHandler = (_ sent: UInt64, _ total: UInt64) -> ProgressAction
```

A closure called periodically during `upload` and `download` transfers. Return `.continue` to keep transferring, or `.cancel` to abort. Cancellation causes the operation to throw `MTPError.cancelled`.

---

## Subsections with Code Samples

### Device Discovery and Connection

`mtpDetectDevices()` returns lightweight `RawDevice` descriptors without opening any USB connections. You select the device you want, then call `open()` — which is `mutating` — to get a `Device`.

```swift
mtpInitialize()

let devices = try mtpDetectDevices()

for raw in devices {
    print("\(raw.vendor) \(raw.product) — bus \(raw.busLocation) dev \(raw.devnum)")
}

guard var raw = devices.first else { return }
let device = try raw.open()
```

If you previously recorded the bus location and device number (for example, to reconnect after an interruption), use `Device.init(busLocation:devnum:)` directly:

```swift
let device = try Device(busLocation: 3, devnum: 7)
```

`Device` releases the USB connection in its `deinit`. There is no explicit `close()` — let ARC handle lifetime.

---

### Storage Selection

Most devices expose one storage pool (internal memory), but some have multiple (internal + SD card).

```swift
let allStorages = device.storages()
for storage in allStorages {
    print("\(storage.description): \(storage.freeSpace) bytes free of \(storage.maxCapacity)")
}
```

When calling `Device` methods directly, pass a `StorageID` or `StorageInfo`. Use `StorageID.all` to let the device pick (equivalent to not filtering by storage):

```swift
let allFiles = try device.contents(of: .root, storage: .all)
```

Pass a specific `StorageID` or `StorageInfo` to restrict results to one pool:

```swift
let sdCard = allStorages[1]
let sdFiles = try device.contents(of: .root, storage: sdCard.info)
```

The `Storage` struct is a convenience wrapper that pre-binds the device and storage, so you do not need to pass storage on every call:

```swift
let storage = device.defaultStorage!
let files = try storage.contents(of: .root)
try storage.upload(from: "/tmp/photo.jpg", to: .root, as: "photo.jpg")
```

`upload` and `makeDirectory` require an explicit storage — `StorageID.all` is not valid for write operations.

---

### Directory Listing and Path Resolution

#### Listing a directory

`contents(of:storage:)` returns the immediate children of `parent` as `[FileInfo]`. Use `.root` for the top level.

```swift
let rootEntries = try device.contents(of: .root)

let dirs = rootEntries.filter { $0.isDirectory }
if let photosDir = dirs.first(where: { $0.name == "Photos" }),
   let photosFolder = photosDir.folder {
    let photos = try device.contents(of: photosFolder)
}
```

#### Resolving a path

`resolvePath(_:storage:)` walks a slash-separated path and returns the `FileInfo` for the final component, or `nil` if any component is not found.

```swift
if let file = try device.resolvePath("Music/Albums/track01.mp3") {
    print("Found: \(file.id), \(file.size) bytes")
}
```

Path components are matched case-sensitively and must exactly match the names on the device. Leading slashes are ignored. Returns `nil` (not a throw) when the path does not exist.

---

### File Operations

#### Upload

```swift
@discardableResult
public func upload(
    from localPath: String,
    to parent: Folder,
    storage: StorageID,
    as filename: String,
    progress: ProgressHandler? = nil
) throws(MTPError) -> FileInfo
```

Sends a local file to the device and returns the device-assigned `FileInfo` — including the `ObjectID` assigned by the device. Throws `MTPError.storageFull` when the device is out of space.

```swift
let info = try device.upload(
    from: "/Users/me/photo.jpg",
    to: .root,
    storage: storageId,
    as: "photo.jpg"
)
print("Stored on device as object \(info.id) in storage \(info.storageId)")
```

The return value is `@discardableResult` — discard it when you do not need the assigned ID.

#### Download

```swift
public func download(_ id: ObjectID, to localPath: String, progress: ProgressHandler? = nil) throws(MTPError)
```

Downloads an object to a local path. Throws `MTPError.operationFailed` if the object cannot be read.

```swift
try device.download(fileInfo.id, to: "/tmp/\(fileInfo.name)")
```

#### Create directory

```swift
@discardableResult
public func makeDirectory(named name: String, in parent: Folder, storage: StorageID) throws(MTPError) -> FileInfo
```

Creates a directory and returns its `FileInfo` (including the assigned `ObjectID`). Use the returned `folder` property to immediately upload into the new directory.

```swift
let dir = try device.makeDirectory(named: "Vacation 2025", in: .root, storage: storageId)
let folder = dir.folder!
try device.upload(from: "/tmp/img.jpg", to: folder, storage: storageId, as: "img.jpg")
```

#### Rename

```swift
@discardableResult
public func rename(_ id: ObjectID, to newName: String) throws(MTPError) -> FileInfo
```

Renames a file or folder and returns the updated `FileInfo`. Throws `MTPError.objectNotFound` if the ID does not exist.

```swift
let updated = try device.rename(fileInfo.id, to: "new-name.jpg")
print(updated.name)
```

#### Move

```swift
public func move(_ id: ObjectID, to parent: Folder, storage: StorageID) throws(MTPError)
```

Moves an object to a different parent folder within the same device. Throws `MTPError.moveNotSupported` if the device does not implement the MoveObject operation. Check first with `device.supportsCapability(.moveObject)`.

```swift
guard device.supportsCapability(.moveObject) else { /* fallback */ return }
try device.move(fileInfo.id, to: targetFolder, storage: storageId)
```

#### Delete

```swift
public func delete(_ id: ObjectID) throws(MTPError)
```

Permanently deletes an object from the device.

```swift
try device.delete(fileInfo.id)
```

#### Fetch metadata for a single object

```swift
public func info(for id: ObjectID) throws(MTPError) -> FileInfo
```

Retrieves current metadata for a single object. Useful for checking the state of an object after an operation, or when you have a stored ID from a previous session.

```swift
let current = try device.info(for: knownObjectId)
print(current.name, current.size)
```

---

### Progress Tracking

`ProgressHandler` is a closure `(_ sent: UInt64, _ total: UInt64) -> ProgressAction`. Return `.continue` to keep transferring or `.cancel` to abort. Both `upload` and `download` accept an optional handler.

```swift
try device.upload(
    from: "/tmp/large-video.mp4",
    to: .root,
    storage: storageId,
    as: "video.mp4"
) { sent, total in
    let percent = total > 0 ? Int(sent * 100 / total) : 0
    print("Upload: \(percent)%")
    return .continue
}
```

To cancel mid-transfer, return `.cancel`:

```swift
var shouldCancel = false

do {
    try device.download(objectId, to: "/tmp/file.dat") { sent, total in
        return shouldCancel ? .cancel : .continue
    }
} catch MTPError.cancelled {
    print("Transfer was cancelled")
}
```

---

### Event Monitoring

`Device.readEvent()` blocks the calling thread until the device sends an event, then returns it. Call it in a loop on a dedicated thread or task.

```swift
Task.detached {
    do {
        while true {
            let event = try device.readEvent()
            switch event {
            case .storeAdded(let storageId):
                print("Storage inserted: \(storageId)")
            case .storeRemoved(let storageId):
                print("Storage removed: \(storageId)")
            case .objectAdded(let objectId):
                print("Object added: \(objectId)")
            case .objectRemoved(let objectId):
                print("Object removed: \(objectId)")
            case .devicePropertyChanged:
                print("Device property changed")
            }
        }
    } catch MTPError.deviceDisconnected {
        print("Device disconnected")
    }
}
```

`readEvent()` throws `MTPError.deviceDisconnected` both when the USB connection is lost and when the device sends an event type that libmtp does not recognize. Either condition should be treated as the end of the event loop.

---

### Error Handling

All throwing functions in SwiftMTP use typed throws (`throws(MTPError)`), so exhaustive `catch` is possible without a fallback case:

```swift
do {
    try device.download(objectId, to: "/tmp/file.dat")
} catch {
    switch error {
    case .objectNotFound(let id):
        print("Object \(id) no longer exists on device")
    case .cancelled:
        print("User cancelled")
    case .deviceDisconnected:
        print("Device was unplugged")
    case .storageFull:
        print("Device storage is full")
    case .operationFailed(let message):
        print("libmtp error: \(message)")
    case .moveNotSupported:
        print("Device does not support move")
    case .noDeviceAttached:
        print("No MTP device connected")
    case .connectionFailed(let bus, let devnum):
        print("Cannot connect to device at bus \(bus) devnum \(devnum)")
    case .pathNotFound(let path):
        print("Path not found: \(path)")
    }
}
```

`MTPError` conforms to `Equatable`, so you can compare error values in tests:

```swift
#expect(throws: MTPError.noDeviceAttached) {
    try mtpDetectDevices()
}
```
