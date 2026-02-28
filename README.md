# SwiftMTP

Swift wrapper around [libmtp](https://github.com/libmtp/libmtp) for MTP device access on macOS. Provides device discovery, file management (list, upload, download, delete, rename, move, mkdir), sorting, and storage inspection using libmtp's uncached mode with no internal caching.

## Installation

Requires `libmtp` via Homebrew:

```sh
brew install libmtp
```

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/swift-mtp.git", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SwiftMTP", package: "swift-mtp"),
        ]
    ),
]
```

## Usage

SwiftMTP offers an abstraction over the `libmtp` C API that makes it ergonomic to use, and avoid common pitfalls in your code base:

- `Storage` is bound to a device, so you don't need to schlep both device and storage pointers.
- Nominal ID types prevent mixiRequest a sample memo to see what you'll receive after the session.

ng up object, storage, and folder IDs at compile time.
- `~Copyable` wrappers guarantee C resource cleanup — no manual `defer`/`destroy` calls.

```swift
import SwiftMTP

mtpInitialize()

// discover and open the first device
var raw = try mtpDetectDevices().first!
let device = try raw.open()

// get the default storage — remembers its device
let storage = device.defaultStorage!

// list root and find a file by name
let root = try storage.contents()
for entry in root.sorted(.directoriesFirst) {
    print(entry.name, entry.isDirectory ? "dir" : "\(entry.size) bytes")
}

// resolve a path directly
if let note = try storage.resolvePath("/Documents/note.pdf") {
    let dest = URL(fileURLWithPath: "/tmp/note.pdf")
    try device.download(note.id, to: dest) { sent, total in
        print("\(sent)/\(total)")
        return true  // return false to cancel
    }
}

// upload into a new folder — filename defaults to lastPathComponent
let backup = try storage.makeDirectory(named: "Backup", in: .root)
let source = URL(fileURLWithPath: "/tmp/report.pdf")
let uploaded = try storage.upload(from: source, to: backup.folder!)

// rename, move, delete
try device.rename(uploaded.id, to: "final-report.pdf")
if device.supportsCapability(.moveObject) {
    try storage.move(uploaded.id, to: .root)
}
try device.delete(backup.id)

// listen for events (cancellable AsyncStream)
let eventTask = Task.detached {
    for await event in device.events() {
        print("Event: \(event)")
    }
    print("Event stream ended")
}
// later:
eventTask.cancel()
```

### Sorting

`FileInfo` collections support enum-based sorting with full type inference:

```swift
let entries = try storage.contents()
entries.sorted(.byName)              // case-insensitive, Finder-style ("file2" < "file10")
entries.sorted(.byNameDescending)
entries.sorted(.bySize)
entries.sorted(.bySizeDescending)
entries.sorted(.byDate)
entries.sorted(.byDateDescending)
entries.sorted(.directoriesFirst)    // dirs before files, then by name within each group
```

### Error Handling

All fallible operations use typed throws (`throws(MTPError)`):

```swift
do throws(MTPError) {
    try device.delete(objectId)
} catch .objectNotFound(let id) {
    // ...
} catch .operationFailed(let message) {
    // message contains the libmtp error stack
}
```

`MTPError` cases: `noDeviceAttached`, `connectionFailed`, `storageFull`, `objectNotFound`, `operationFailed`, `pathNotFound`, `notFileURL`, `moveNotSupported`, `cancelled`, `deviceDisconnected`.

## Types

| Type | Description |
|------|-------------|
| `Device` | Device handle wrapping `LIBMTP_mtpdevice_t`. Released on deinit. Not thread-safe. |
| `RawDevice` | Discovered device before opening. Call `open()` to get a `Device`. |
| `FileInfo` | Unified file/folder metadata (id, name, size, dates, isDirectory, folder). |
| `FileInfo.SortOrder` | Enum-based sorting: `.byName`, `.bySize`, `.byDate`, `.directoriesFirst`, etc. |
| `Storage` | Device-bound storage handle for scoped operations (contents, upload, mkdir, move). |
| `StorageInfo` | Storage pool value type (id, description, capacity, free space, usedSpace, percentFull). |
| `ObjectID` | Nominal wrapper for MTP object IDs. `.root` for the root object. |
| `StorageID` | Nominal wrapper for storage pool IDs. `.all` for all storages. |
| `Folder` | Compile-time safe folder reference. `.root` for the root directory. |
| `Path` | Type-safe path with component splitting. `ExpressibleByStringLiteral`. |
| `BusLocation` | Nominal wrapper for USB bus location. |
| `DeviceNumber` | Nominal wrapper for USB device number. |
| `VendorID` | Nominal wrapper for USB vendor ID (hex description). |
| `ProductID` | Nominal wrapper for USB product ID (hex description). |
| `Event` | Event enum for device notifications (store/object added/removed, property changed). |
| `MTPError` | Typed error enum covering all failure modes. |
| `DeviceCapability` | Device capability flags (moveObject, copyObject, etc.). |

## Testing

```sh
swift test
MTP_DEVICE_CONNECTED=1 swift test  # with device attached
```

Some tests require a connected MTP device and only run when `MTP_DEVICE_CONNECTED=1` is set. These are serialized since libmtp is not thread-safe.

## Architecture

Two-target SPM package (Swift 6.2, macOS 26):

- **Clibmtp** — `.systemLibrary` wrapping `libmtp.h` via pkg-config
- **SwiftMTP** — Pure Swift API layer with typed throws, `Sendable` value types, and automatic C memory management

All public value types are `Sendable`. `Device` is a `final class` with `deinit`-based cleanup — it is **not thread-safe** (libmtp uses no locking). Internal C resource management uses `~Copyable` structs (`Upload`, `FileHandle`, `FileNode`, `FolderTree`) that guarantee cleanup via `deinit`. Implicit C contracts (memory ownership, callback lifetimes, error stack semantics) are documented in docstrings on each wrapper type. The library operates statelessly — callers manage their own caching.
