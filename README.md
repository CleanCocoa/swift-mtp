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
            // pick one:
            .product(name: "SwiftMTP", package: "swift-mtp"),      // sync (@MainActor)
            .product(name: "SwiftMTPAsync", package: "swift-mtp"), // async (actor)
        ]
    ),
]
```

## Usage

Two products are available — choose the one that fits your concurrency model:

| Product | API style | Isolation |
|---------|-----------|-----------|
| `SwiftMTP` | Synchronous | `@MainActor` on `Device` |
| `SwiftMTPAsync` | Async/await | `MTPSession` actor |

Both re-export all shared types (`MTP`, `FileInfo`, `ObjectID`, `StorageID`, `Folder`, `Path`, `Event`, etc.) so you only need a single import.

### Async (SwiftMTPAsync)

```swift
import SwiftMTPAsync

try MTP.initialize()

var raw = try MTPSession.detect().first!
let session = try MTPSession(opening: &raw)

// device properties are nonisolated — no await needed
print(session.manufacturerName ?? "unknown")

let storage = await session.defaultStorage!
let root = try await storage.contents()
for entry in root.sorted(.directoriesFirst) {
    print(entry.name, entry.isDirectory ? "dir" : "\(entry.size) bytes")
}

if let note = try await storage.resolvePath("/Documents/note.pdf") {
    let dest = URL(fileURLWithPath: "/tmp/note.pdf")
    try await session.download(note, to: dest) { sent, total in
        print("\(sent)/\(total)")
        return .continue
    }
}
```

### Sync (SwiftMTP)

```swift
import SwiftMTP

try MTP.initialize()

var raw = try Device.detect().first!
let device = try Device(opening: &raw)    // @MainActor

print(device.manufacturerName ?? "unknown")

let storage = device.defaultStorage!
let root = try storage.contents()
for entry in root.sorted(.directoriesFirst) {
    print(entry.name, entry.isDirectory ? "dir" : "\(entry.size) bytes")
}
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

Entry points (`MTP.detectDevices()`, `Device.detect()`/`MTPSession.detect()`, init methods) throw `.notInitialized` if the library hasn't been set up. For contexts where double-init is benign (app launch, tests), use `try? MTP.initialize()`.

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
| `Device` | `@MainActor` wrapper (SwiftMTP). Cached nonisolated properties, sync methods. |
| `MTPSession` | Actor wrapper (SwiftMTPAsync). Cached nonisolated properties, async methods. |
| `DetectedDevice` | Discovered device before opening. Pass to `Device(opening:)` or `MTPSession(opening:)`. |
| `FileInfo` | Unified file/folder metadata (id, name, size, dates, isDirectory, folder). |
| `FileInfo.SortOrder` | Enum-based sorting: `.byName`, `.bySize`, `.byDate`, `.directoriesFirst`, etc. |
| `Storage` | Device/session-bound storage handle for scoped operations (contents, upload, mkdir, move). |
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
swift test                           # unit tests only
swift test --filter MTPCoreTests     # core type tests
swift test --filter HardwareTests    # hardware tests (requires device)
MTP_DEVICE_CONNECTED=1 swift test    # all tests including hardware
```

Hardware tests require a connected MTP device and only run when `MTP_DEVICE_CONNECTED=1` is set. They use a single shared `MTPSession` and run serialized — libusb only allows one interface claim per process.
