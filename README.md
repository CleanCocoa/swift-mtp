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

SwiftMTP offers an abstraction over the `libmtp` C API that makes it ergonomic to use, and avoids common pitfalls in your code base:

- `MTPSession` actor serializes all USB I/O off the main thread — libmtp's single-threaded requirement is enforced structurally.
- `Storage` is bound to a session, so you don't need to schlep both device and storage pointers.
- Nominal ID types prevent mixing up object, storage, and folder IDs at compile time.
- `~Copyable` wrappers guarantee C resource cleanup — no manual `defer`/`destroy` calls.

```swift
import SwiftMTP

try MTP.initialize()

// discover and open the first device
var raw = try MTPSession.detect().first!
let session = try MTPSession(opening: &raw)

// device properties are nonisolated — no await needed
print(session.manufacturerName ?? "unknown")

// get the default storage — remembers its session
let storage = await session.defaultStorage!

// list root and find a file by name
let root = try await storage.contents()
for entry in root.sorted(.directoriesFirst) {
    print(entry.name, entry.isDirectory ? "dir" : "\(entry.size) bytes")
}

// resolve a path directly
if let note = try await storage.resolvePath("/Documents/note.pdf") {
    let dest = URL(fileURLWithPath: "/tmp/note.pdf")
    try await session.download(note, to: dest) { sent, total in
        print("\(sent)/\(total)")
        return .continue  // return .cancel to abort
    }
}

// upload into a new folder — filename defaults to lastPathComponent
let backup = try await storage.makeDirectory(named: "Backup", in: .root)
let source = URL(fileURLWithPath: "/tmp/report.pdf")
let uploaded = try await storage.upload(from: source, to: backup.folder!) { sent, total in
    print("\(sent)/\(total)")
    return .continue
}

// rename, move, delete — pass FileInfo/Folder directly (or .id)
try await session.rename(uploaded, to: "final-report.pdf")
if session.supportsCapability(.moveObject) {
    try await storage.move(uploaded, to: .root)
}
try await session.delete(backup)

// listen for events (cancellable AsyncStream, nonisolated)
let eventTask = Task.detached {
    for await event in session.events() {
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
let entries = try await storage.contents()
entries.sorted(.byName)              // case-insensitive, Finder-style ("file2" < "file10")
entries.sorted(.byNameDescending)
entries.sorted(.bySize)
entries.sorted(.bySizeDescending)
entries.sorted(.byDate)
entries.sorted(.byDateDescending)
entries.sorted(.directoriesFirst)    // dirs before files, then by name within each group
```

### Initialization

`MTP.initialize()` must be called exactly once before using the library. It builds libmtp's internal filetype and property mapping tables, and loads MTPZ encryption data. Calling it a second time throws `.alreadyInitialized`. The current state is inspectable via `MTP.isInitialized`:

```swift
try MTP.initialize()       // first call succeeds
MTP.isInitialized          // true

try MTP.initialize()       // throws MTPError.alreadyInitialized
```

Entry points (`MTP.detectDevices()`, `MTPSession.detect()`, `MTPSession.init(opening:)`, `MTPSession.init(busLocation:devnum:)`) throw `.notInitialized` if the library hasn't been set up. For contexts where double-init is benign (app launch, tests), use `try? MTP.initialize()`.

### Error Handling

All fallible operations use typed throws (`throws(MTPError)`):

```swift
do throws(MTPError) {
    try await session.delete(objectId)
} catch .objectNotFound(let id) {
    // ...
} catch .operationFailed(let message) {
    // message contains the libmtp error stack
}
```

`MTPError` cases: `alreadyInitialized`, `notInitialized`, `noDeviceAttached`, `connectionFailed`, `storageFull`, `objectNotFound`, `operationFailed`, `pathNotFound`, `notFileURL`, `moveNotSupported`, `cancelled`, `deviceDisconnected`.

## Types

| Type | Description |
|------|-------------|
| `MTP` | Library namespace. `initialize()`, `isInitialized`, `detectDevices()`. |
| `MTPSession` | Actor wrapping a device connection. All USB I/O is serialized here. `detect()` convenience. |
| `RawDevice` | Discovered device before opening. Pass to `MTPSession(opening:)`. |
| `FileInfo` | Unified file/folder metadata (id, name, size, dates, isDirectory, folder). |
| `FileInfo.SortOrder` | Enum-based sorting: `.byName`, `.bySize`, `.byDate`, `.directoriesFirst`, etc. |
| `Storage` | Session-bound storage handle for scoped operations (contents, upload, mkdir, move). |
| `StorageInfo` | Storage pool value type (id, description, capacity, free space, usedSpace, percentFull). |
| `ObjectID` | Nominal wrapper for MTP object IDs. `.root` for the root object. |
| `StorageID` | Nominal wrapper for storage pool IDs. `.all` for all storages. |
| `Folder` | Compile-time safe folder reference. `.root` for the root directory. |
| `Path` | Type-safe path with component splitting. `ExpressibleByStringLiteral`. |
| `BusLocation` | Nominal wrapper for USB bus location. |
| `DeviceNumber` | Nominal wrapper for USB device number. |
| `VendorID` | Nominal wrapper for USB vendor ID (hex description). |
| `ProductID` | Nominal wrapper for USB product ID (hex description). |
| `FileReference` | Protocol for types that identify an MTP object (`ObjectID`, `FileInfo`, `Folder`). |
| `Event` | Event enum for device notifications (store/object added/removed, property changed). |
| `ProgressAction` | Transfer control enum: `.continue` or `.cancel`. |
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

All public value types are `Sendable`. `MTPSession` is an actor that owns an internal `Device` handle — libmtp's single-threaded requirement is enforced by actor isolation rather than caller discipline. Device properties (`manufacturerName`, `modelName`, etc.) and `supportsCapability(_:)` are cached at init and `nonisolated` — no `await` needed. All USB I/O methods (`contents`, `download`, `upload`, `delete`, etc.) require `await` to cross the actor boundary. Internal C resource management uses `~Copyable` structs (`Upload`, `FileHandle`, `FileNode`, `FolderTree`) that guarantee cleanup via `deinit`. Implicit C contracts (memory ownership, callback lifetimes, error stack semantics) are documented in docstrings on each wrapper type. The library operates statelessly — callers manage their own caching.
