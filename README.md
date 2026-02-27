# SwiftMTP

Swift wrapper around [libmtp](https://github.com/libmtp/libmtp) for MTP device access on macOS. Provides device discovery, file management (list, upload, download, delete, rename, move, mkdir), and storage inspection using libmtp's uncached mode with no internal caching.

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
for entry in root {
    print(entry.name, entry.isDirectory ? "dir" : "\(entry.size) bytes")
}

// resolve a path directly
if let note = try storage.resolvePath("/Documents/note.pdf") {
    try device.download(note.id, to: "/tmp/note.pdf") { sent, total in
        print("\(sent)/\(total)")
        return true  // return false to cancel
    }
}

// upload into a new folder
let backup = try storage.makeDirectory(named: "Backup", in: .root)
let newId = try storage.upload(
    from: "/tmp/report.pdf",
    to: backup,
    as: "report.pdf"
)

// rename, move, delete
try device.rename(newId, to: "final-report.pdf")
if device.supportsCapability(.moveObject) {
    try storage.move(newId, to: .root)
}
try device.delete(backup.id)

// listen for events (blocking — run on a background thread)
Task.detached {
    while true {
        do {
            let event = try device.readEvent()
            print("Event: \(event)")
        } catch .deviceDisconnected {
            print("Device disconnected")
            break
        }
    }
}
```

`Device` opens the device in uncached mode and populates storage on init. All device operations are instance methods. The device is released automatically on deinit.

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

`MTPError` cases: `noDeviceAttached`, `connectionFailed`, `storageFull`, `objectNotFound`, `operationFailed`, `pathNotFound`, `moveNotSupported`, `cancelled`, `deviceDisconnected`.

## Types

| Type | Description |
|------|-------------|
| `Device` | Device handle wrapping `LIBMTP_mtpdevice_t`. Released on deinit. |
| `RawDevice` | Discovered device before opening. Call `open()` to get an `Device`. |
| `FileInfo` | Unified file/folder metadata (id, name, size, dates, isDirectory, folder). |
| `Storage` | Device-bound storage handle for scoped operations (contents, upload, mkdir, move). |
| `StorageInfo` | Storage pool value type (id, description, capacity, free space). |
| `ObjectID` | Nominal wrapper for MTP object IDs. |
| `StorageID` | Nominal wrapper for storage pool IDs. Use `.all` for all storages. |
| `Folder` | Compile-time safe folder reference. Use `.root` for root directory. |
| `Event` | Event enum for device notifications (store/object added/removed, property changed). |
| `MTPError` | Typed error enum covering all failure modes. |
| `DeviceCapability` | Device capability flags (moveObject, copyObject, etc.). |

## Testing

21 unit tests run without hardware, 3 require an MTP device:

```sh
swift test
MTP_DEVICE_CONNECTED=1 swift test  # with device attached
```

Hardware tests are in a serialized suite (`@Suite(.serialized)`) since libmtp is not thread-safe. When `MTP_DEVICE_CONNECTED` is unset, hardware tests are skipped and the device-detection test asserts an empty result. When set, the detection test is skipped instead and the hardware suite runs: device discovery, property reading, storage inspection, and root directory listing.

## Architecture

Two-target SPM package (Swift 6.2, macOS 26):

- **Clibmtp** — `.systemLibrary` wrapping `libmtp.h` via pkg-config
- **SwiftMTP** — Pure Swift API layer with typed throws, `Sendable` value types, and automatic C memory management

All public value types are `Sendable`. `Device` is a `final class` with `deinit`-based cleanup. Internal C resource management uses `~Copyable` structs (`Upload`, `FileHandle`, `FileNode`, `FolderTree`) that guarantee cleanup via `deinit` instead of manual `defer`/`destroy` patterns. Nominal ID types (`ObjectID`, `StorageID`, `Folder`) prevent compile-time confusion between storage, object, and parent folder IDs. The library operates statelessly — callers manage their own caching.
