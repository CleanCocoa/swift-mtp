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

## Overview

### Discovery and Lifecycle

```swift
import SwiftMTP

mtpInitialize()
let rawDevices = try mtpDetectDevices()  // → [MTPRawDevice]

let device = try MTPDevice(busLocation: raw.busLocation, devnum: raw.devnum)
// device is released automatically on deinit
```

`MTPDevice` opens the device in uncached mode and populates storage on init. All device operations are instance methods.

### Storage, Listing, and Path Resolution

```swift
let storages = device.storageInfo()  // → [MTPStorageInfo]

let entries = try device.listDirectory(storageId: 0, parentId: 0)  // → [MTPFileInfo]
let file = try device.resolvePath("/Documents/note.pdf")           // → MTPFileInfo?
```

Directory listing merges the folder tree with the file list to deduplicate entries — folders appear exactly once with correct type information.

### File Operations

```swift
try device.downloadFile(id: fileId, to: "/tmp/note.pdf") { sent, total in
    return true  // return false to cancel
}

let newId = try device.uploadFile(
    from: "/tmp/upload.pdf",
    parentId: parentId,
    storageId: storageId,
    filename: "upload.pdf"
)

let metadata = try device.fileInfo(id: newId)  // → MTPFileInfo
```

### Mutations

```swift
try device.deleteObject(id: objectId)
let folderId = try device.createDirectory(name: "New Folder", parentId: 0, storageId: storageId)
try device.moveObject(id: objectId, toParentId: folderId, storageId: storageId)
try device.renameFile(id: fileId, newName: "renamed.pdf")
try device.renameFolder(id: folderId, newName: "Renamed Folder")
```

### Capabilities

```swift
if device.supportsCapability(.moveObject) {
    try device.moveObject(id: id, toParentId: dest, storageId: sid)
}
```

### Error Handling

All fallible operations use typed throws:

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
