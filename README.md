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

```swift
import SwiftMTP

mtpInitialize()

// discover and open the first device
let raw = try mtpDetectDevices().first!
let device = try MTPDevice(busLocation: raw.busLocation, devnum: raw.devnum)

// pick a storage
let storage = device.storageInfo().first!

// list root and find a file by name
let root = try device.listDirectory(storageId: storage.id, parentId: 0)
for entry in root {
    print(entry.name, entry.isDirectory ? "dir" : "\(entry.size) bytes")
}

// resolve a path directly
if let note = try device.resolvePath("/Documents/note.pdf", storageId: storage.id) {
    try device.downloadFile(id: note.id, to: "/tmp/note.pdf") { sent, total in
        print("\(sent)/\(total)")
        return true  // return false to cancel
    }
}

// upload into a new folder
let folderId = try device.createDirectory(name: "Backup", parentId: 0, storageId: storage.id)
let newId = try device.uploadFile(
    from: "/tmp/report.pdf",
    parentId: folderId,
    storageId: storage.id,
    filename: "report.pdf"
)

// rename, move, delete
try device.renameFile(id: newId, newName: "final-report.pdf")
if device.supportsCapability(.moveObject) {
    try device.moveObject(id: newId, toParentId: 0, storageId: storage.id)
}
try device.deleteObject(id: folderId)
```

`MTPDevice` opens the device in uncached mode and populates storage on init. All device operations are instance methods. The device is released automatically on deinit.

### Error Handling

All fallible operations use typed throws (`throws(MTPError)`):

```swift
do throws(MTPError) {
    try device.deleteObject(id: 999)
} catch .objectNotFound(let id) {
    // ...
} catch .operationFailed(let message) {
    // message contains the libmtp error stack
}
```

`MTPError` cases: `noDeviceAttached`, `connectionFailed`, `storageFull`, `objectNotFound`, `operationFailed`, `pathNotFound`, `moveNotSupported`, `cancelled`.

## Types

| Type | Description |
|------|-------------|
| `MTPDevice` | Device handle wrapping `LIBMTP_mtpdevice_t`. Released on deinit. |
| `MTPRawDevice` | Discovered device before opening (bus, devnum, vendor, product). |
| `MTPFileInfo` | Unified file/folder metadata (id, name, size, dates, isDirectory). |
| `MTPStorageInfo` | Storage pool info (id, description, capacity, free space). |
| `MTPError` | Typed error enum covering all failure modes. |
| `MTPDeviceCapability` | Device capability flags (moveObject, copyObject, etc.). |

## Testing

Unit tests run without hardware:

```sh
swift test
```

Hardware integration tests require an MTP device connected via USB:

```sh
MTP_DEVICE_CONNECTED=1 swift test
```

Verify the device is visible to libmtp first:

```sh
mtp-detect
```

Hardware tests are in a serialized suite (`@Suite(.serialized)`) since libmtp is not thread-safe. When `MTP_DEVICE_CONNECTED` is unset, hardware tests are skipped and the device-detection test asserts an empty result. When set, the detection test is skipped instead and the hardware suite runs: device discovery, property reading, and root directory listing.

## Architecture

Two-target SPM package:

- **Clibmtp** — `.systemLibrary` wrapping `libmtp.h` via pkg-config
- **SwiftMTP** — Pure Swift API layer with typed throws, `Sendable` value types, and automatic C memory management

All public value types are `Sendable`. `MTPDevice` is a `final class` with `deinit`-based cleanup. The library operates statelessly — callers manage their own caching.
