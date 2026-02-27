# SwiftMTP Specification

## 1. Executive Summary

SwiftMTP is a Swift library wrapping libmtp to provide MTP (Media Transfer Protocol) device access on macOS. It is structured as a Swift Package Manager package with two targets: a system library wrapper (`Clibmtp`) and a pure-Swift API layer (`SwiftMTP`). The library provides device discovery, file management (list, upload, download, delete, rename, move, mkdir), and storage inspection. It uses libmtp's uncached mode and operates without any internal caching — callers manage their own cache if desired. The primary use case is file management on Supernote e-ink tablets via USB, replacing the Emacs-specific mtp.el C module with a general-purpose Swift library.

## 2. Architecture Overview

### 2.1 Architecture Style

Two-target SPM package. `Clibmtp` is a `.systemLibrary` that makes the C `libmtp.h` header importable. `SwiftMTP` is a `.target` that depends on `Clibmtp` and provides the public Swift API.

### 2.2 Package Structure

```
swift-mtp/
├── Package.swift
├── Sources/
│   ├── Clibmtp/
│   │   └── include/
│   │       ├── module.modulemap
│   │       └── shim.h
│   └── SwiftMTP/
│       ├── MTPDevice.swift          // Device lifecycle, ~Copyable wrapper
│       ├── MTPDeviceDiscovery.swift  // detect(), init from raw device
│       ├── MTPFileOperations.swift   // download, upload, delete, mkdir, move, rename
│       ├── MTPDirectoryListing.swift // listDirectory with dedup, resolvePath
│       ├── MTPStorageInfo.swift      // storage enumeration
│       ├── MTPTypes.swift           // MTPFileInfo, MTPRawDevice, MTPStorageInfo
│       ├── MTPError.swift           // MTPError enum
│       └── MTPProgressCallback.swift // Progress callback bridging
├── Tests/
│   └── SwiftMTPTests/
│       └── SwiftMTPTests.swift
└── docs/
    ├── research-findings.md
    └── swift-spec.md (this file)
```

### 2.3 Dependency Graph

```
SwiftMTPTests ──depends──> SwiftMTP ──depends──> Clibmtp ──pkg-config──> libmtp (system)
```

## 3. Technology Stack

| Layer | Technology | Version | Justification |
|---|---|---|---|
| Language | Swift | 6.2 | ~Copyable support, strict concurrency |
| Build | Swift Package Manager | 6.0 tools | Standard Swift build system |
| C library | libmtp | >= 1.1.0 | Only maintained open-source MTP library |
| C binding | pkg-config + systemLibrary | — | Standard SPM pattern for system libs |
| Package manager | Homebrew | — | `brew install libmtp` on macOS |
| Test framework | Swift Testing | — | Modern Swift testing with `@Test` |
| Platform | macOS | 14+ | Modern Swift concurrency baseline |

## 4. Swift Type Design

### 4.1 `MTPError`

```swift
public enum MTPError: Error, Equatable, Sendable {
    case noDeviceAttached
    case connectionFailed(bus: UInt32, devnum: UInt8)
    case storageFull
    case objectNotFound(id: UInt32)
    case operationFailed(String)
    case pathNotFound(String)
    case moveNotSupported
    case cancelled
}
```

Map from `LIBMTP_error_number_t` where possible. The `operationFailed` case carries the error text from `LIBMTP_Get_Errorstack`. `moveNotSupported` enables the three-tier rename strategy.

### 4.2 `MTPRawDevice`

```swift
public struct MTPRawDevice: Sendable {
    public let busLocation: UInt32
    public let devnum: UInt8
    public let vendor: String
    public let vendorId: UInt16
    public let product: String
    public let productId: UInt16
}
```

Value type from `LIBMTP_raw_device_t`. Used for discovery before opening a device.

### 4.3 `MTPFileInfo`

```swift
public struct MTPFileInfo: Sendable {
    public let id: UInt32
    public let parentId: UInt32
    public let storageId: UInt32
    public let name: String
    public let size: UInt64
    public let modificationDate: Date
    public let isDirectory: Bool
}
```

Unified representation of files and folders. Constructed from either `LIBMTP_file_t` or `LIBMTP_folder_t`. Folders from the folder tree have `size: 0` and `modificationDate: .distantPast`.

### 4.4 `MTPStorageInfo`

```swift
public struct MTPStorageInfo: Sendable {
    public let id: UInt32
    public let description: String
    public let maxCapacity: UInt64
    public let freeSpace: UInt64
}
```

From `LIBMTP_devicestorage_t`.

### 4.5 `MTPDevice`

```swift
public final class MTPDevice: ~Copyable {
    // Internal raw pointer — not exposed
    let raw: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>
}
```

Non-copyable class wrapping the opaque device pointer. `deinit` calls `LIBMTP_Release_Device`. All device operations are instance methods on this type.

## 5. Public API Catalog

### 5.1 Library Initialization

```swift
public func mtpInitialize()
```

Calls `LIBMTP_Init()`. Must be called once before any other operation. Idempotent.

### 5.2 Device Discovery

```swift
public func mtpDetectDevices() throws(MTPError) -> [MTPRawDevice]
```

- C functions: `LIBMTP_Detect_Raw_Devices`
- Returns empty array if no devices (does not throw)
- Throws `MTPError.operationFailed` for USB-level errors

### 5.3 Device Lifecycle

```swift
// MTPDevice.swift

public init(busLocation: UInt32, devnum: UInt8) throws(MTPError)
```

- C functions: `LIBMTP_Detect_Raw_Devices`, `LIBMTP_Open_Raw_Device_Uncached`
- Finds raw device by bus+devnum, opens in uncached mode
- Calls `LIBMTP_Get_Storage(device, 0)` to populate storage list
- Throws `MTPError.noDeviceAttached` or `MTPError.connectionFailed`

```swift
deinit
```

- C functions: `LIBMTP_Release_Device`
- Always called; no explicit close needed

```swift
public var manufacturerName: String?  { get }
public var modelName: String?         { get }
public var serialNumber: String?      { get }
public var friendlyName: String?      { get }
public var deviceVersion: String?     { get }
```

- C functions: `LIBMTP_Get_Manufacturername`, `LIBMTP_Get_Modelname`, `LIBMTP_Get_Serialnumber`, `LIBMTP_Get_Friendlyname`, `LIBMTP_Get_Deviceversion`
- Each returns a freshly allocated string (caller-frees pattern)

### 5.4 Storage

```swift
public func storageInfo() -> [MTPStorageInfo]
```

- C functions: none (reads `device->storage` linked list, already populated at init)
- Returns empty array if no storage

### 5.5 Directory Listing

```swift
public func listDirectory(
    storageId: UInt32 = 0,
    parentId: UInt32 = 0
) throws(MTPError) -> [MTPFileInfo]
```

- C functions: `LIBMTP_Get_Files_And_Folders`, `LIBMTP_Get_Folder_List`, `LIBMTP_destroy_folder_t`, `LIBMTP_destroy_file_t`
- `storageId=0` → all storages, `parentId=0` → root
- Implements the dedup algorithm from mtp-module.c (see research-findings.md §2.2):
  1. Get folder tree, collect all folder IDs
  2. Find child folders of parentId from tree → emit as MTPFileInfo
  3. Get files list, skip duplicates, fix folder types
- Frees all C memory before returning

### 5.6 Path Resolution

```swift
public func resolvePath(
    _ path: String,
    storageId: UInt32 = 0
) throws(MTPError) -> MTPFileInfo?
```

- C functions: `LIBMTP_Get_Files_And_Folders`, `LIBMTP_destroy_file_t`
- Walks path component-by-component
- Returns `nil` if not found (does not throw for missing paths)
- Throws for device errors during traversal

### 5.7 File Metadata

```swift
public func fileInfo(id: UInt32) throws(MTPError) -> MTPFileInfo
```

- C functions: `LIBMTP_Get_Filemetadata`, `LIBMTP_destroy_file_t`
- Throws `MTPError.objectNotFound` if ID doesn't exist

### 5.8 File Download

```swift
public func downloadFile(
    id: UInt32,
    to localPath: String,
    progress: ((UInt64, UInt64) -> Bool)? = nil
) throws(MTPError)
```

- C functions: `LIBMTP_Get_File_To_File`
- Progress callback: `(sent, total) -> shouldContinue`
- Throws `MTPError.objectNotFound` or `MTPError.operationFailed`
- Throws `MTPError.cancelled` if progress callback returns `false`

### 5.9 File Upload

```swift
@discardableResult
public func uploadFile(
    from localPath: String,
    parentId: UInt32,
    storageId: UInt32,
    filename: String,
    progress: ((UInt64, UInt64) -> Bool)? = nil
) throws(MTPError) -> UInt32
```

- C functions: `stat()`, `LIBMTP_new_file_t`, `LIBMTP_Send_File_From_File`, `LIBMTP_destroy_file_t`
- Sets `filetype = LIBMTP_FILETYPE_UNKNOWN` for all uploads
- Returns the newly assigned object ID from `metadata->item_id`
- Throws `MTPError.operationFailed` if local file can't be stat'd or upload fails
- Throws `MTPError.storageFull` when applicable

### 5.10 Delete

```swift
public func deleteObject(id: UInt32) throws(MTPError)
```

- C functions: `LIBMTP_Delete_Object`
- Works for both files and folders (recursive for folders)

### 5.11 Create Directory

```swift
public func createDirectory(
    name: String,
    parentId: UInt32,
    storageId: UInt32
) throws(MTPError) -> UInt32
```

- C functions: `LIBMTP_Create_Folder`
- **Must pass `strdup(name)`** — C function takes ownership
- Returns new folder ID

### 5.12 Move Object

```swift
public func moveObject(
    id: UInt32,
    toParentId: UInt32,
    storageId: UInt32
) throws(MTPError)
```

- C functions: `LIBMTP_Move_Object`
- Throws `MTPError.moveNotSupported` if the device doesn't support MoveObject (detected from errorstack containing "MoveObject" or via capability check)

### 5.13 Rename

```swift
public func renameFile(id: UInt32, newName: String) throws(MTPError)
public func renameFolder(id: UInt32, newName: String) throws(MTPError)
```

- C functions: `LIBMTP_Get_Filemetadata` + `LIBMTP_Set_File_Name`, or `LIBMTP_Get_Folder_List` + `LIBMTP_Find_Folder` + `LIBMTP_Set_Folder_Name`
- Separate methods because libmtp has different APIs for files vs folders

### 5.14 Capability Check

```swift
public func supportsCapability(_ cap: MTPDeviceCapability) -> Bool
```

- C functions: `LIBMTP_Check_Capability`

```swift
public enum MTPDeviceCapability {
    case moveObject
    case copyObject
    case getPartialObject
    case sendPartialObject
    case editObjects
}
```

## 6. Infrastructure & Build

### 6.1 Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftMTP", targets: ["SwiftMTP"]),
    ],
    targets: [
        .systemLibrary(
            name: "Clibmtp",
            pkgConfig: "libmtp",
            providers: [.brew(["libmtp"])]
        ),
        .target(
            name: "SwiftMTP",
            dependencies: ["Clibmtp"]
        ),
        .testTarget(
            name: "SwiftMTPTests",
            dependencies: ["SwiftMTP"]
        ),
    ]
)
```

### 6.2 Clibmtp module.modulemap

```
module Clibmtp [system] {
    header "shim.h"
    link "mtp"
    export *
}
```

### 6.3 Clibmtp shim.h

```c
#pragma once
#include <libmtp.h>
```

### 6.4 Build Verification

```sh
brew install libmtp         # prerequisite
swift build                 # must succeed with no errors
swift test                  # must pass all tests
```

## 7. Implementation Plan

### 7.1 Phase Overview

| Phase | Tasks | Description |
|---|---|---|
| 1 | TASK-001 | Package scaffold — verify `swift build` compiles |
| 2 | TASK-002, TASK-003 | Foundation types (errors, value types) |
| 3 | TASK-004 | Progress callback bridge |
| 4 | TASK-005, TASK-006, TASK-007 | Device lifecycle (discovery, open/close, storage) |
| 5 | TASK-008, TASK-009 | Directory operations (listing + path resolution) |
| 6 | TASK-010 | File I/O (download + upload) |
| 7 | TASK-011 | Mutation operations (delete, mkdir, move, rename) |
| 8 | TASK-012 | Tests |

### 7.2 Task Breakdown

**TASK-001: Package Scaffold**
- Phase:       1
- Depends on:  —
- Size:        S
- Description: Create `Package.swift`, `Sources/Clibmtp/include/module.modulemap`, `Sources/Clibmtp/include/shim.h`, and a minimal `Sources/SwiftMTP/SwiftMTP.swift` placeholder. Verify `swift build` succeeds with libmtp installed via Homebrew.
- Acceptance:  `swift build` completes with exit code 0. `import Clibmtp` resolves in Swift source. `LIBMTP_Init` symbol is visible.

**TASK-002: Error Types**
- Phase:       2
- Depends on:  TASK-001
- Size:        S
- Description: Create `Sources/SwiftMTP/MTPError.swift` with the `MTPError` enum. Add an internal helper to drain the libmtp error stack into a String: read `LIBMTP_Get_Errorstack`, walk the linked list collecting messages, call `LIBMTP_Clear_Errorstack`. This helper is used by all subsequent operations.
- Acceptance:  `MTPError` conforms to `Error`, `Equatable`, and `Sendable`. Error stack drain helper compiles.

**TASK-003: Value Types**
- Phase:       2
- Depends on:  TASK-001
- Size:        S
- Description: Create `Sources/SwiftMTP/MTPTypes.swift` with `MTPRawDevice`, `MTPFileInfo`, and `MTPStorageInfo`. Add internal initializers that construct from C structs: `MTPFileInfo(cFile: UnsafeMutablePointer<LIBMTP_file_struct>)`, `MTPFileInfo(cFolder: UnsafeMutablePointer<LIBMTP_folder_struct>)`, `MTPRawDevice(cRawDevice: UnsafePointer<LIBMTP_raw_device_struct>)`, `MTPStorageInfo(cStorage: UnsafePointer<LIBMTP_devicestorage_struct>)`.
- Acceptance:  All types are `Sendable`. Internal initializers compile. `MTPFileInfo` from folder has `size: 0` and `modificationDate: .distantPast`.

**TASK-004: Progress Callback Bridge**
- Phase:       3
- Depends on:  TASK-001
- Size:        S
- Description: Create `Sources/SwiftMTP/MTPProgressCallback.swift` with the `withProgressCallback` helper that bridges a Swift `((UInt64, UInt64) -> Bool)?` closure to a C `LIBMTP_progressfunc_t` + context pointer. When the closure is nil, pass NULL for both callback and data. The C callback reads the Swift closure from the context pointer and calls it.
- Acceptance:  `withProgressCallback(nil) { cb, data in ... }` passes nil/nil. `withProgressCallback(handler) { cb, data in ... }` provides a valid function pointer. Compiles with strict concurrency.

**TASK-005: Device Discovery**
- Phase:       4
- Depends on:  TASK-002, TASK-003
- Size:        S
- Description: Create `Sources/SwiftMTP/MTPDeviceDiscovery.swift` with the `mtpInitialize()` free function (calls `LIBMTP_Init`) and `mtpDetectDevices() throws(MTPError) -> [MTPRawDevice]` free function. The detect function calls `LIBMTP_Detect_Raw_Devices`, converts the C array to Swift, frees the C array, and returns.
- Acceptance:  `mtpInitialize()` can be called multiple times without error. `mtpDetectDevices()` returns an empty array when no devices are connected (does not throw). `MTPRawDevice` values have correct bus/devnum/vendor/product fields.

**TASK-006: Device Lifecycle (init/close/deinit)**
- Phase:       4
- Depends on:  TASK-002, TASK-003, TASK-005
- Size:        M
- Description: Create `Sources/SwiftMTP/MTPDevice.swift` with the `MTPDevice` class (marked `~Copyable`). Implement `init(busLocation:devnum:)` which re-detects raw devices, finds the matching one, calls `LIBMTP_Open_Raw_Device_Uncached`, and calls `LIBMTP_Get_Storage(device, 0)`. Implement `deinit` which calls `LIBMTP_Release_Device`. Add computed properties: `manufacturerName`, `modelName`, `serialNumber`, `friendlyName`, `deviceVersion` (each calls the corresponding C function, copies the string, frees the C allocation). Add `supportsCapability(_:)`.
- Acceptance:  `MTPDevice` compiles as `~Copyable`. `deinit` calls `LIBMTP_Release_Device`. Computed properties handle nil C strings gracefully. `init` throws `MTPError.noDeviceAttached` when device not found. Cannot be copied (compile error if attempted).

**TASK-007: Storage Info**
- Phase:       4
- Depends on:  TASK-006
- Size:        S
- Description: Add `storageInfo() -> [MTPStorageInfo]` method to `MTPDevice`. Walks the `device->storage` linked list (already populated during init), converts each node to `MTPStorageInfo`.
- Acceptance:  Returns empty array if no storage. Walks linked list via `.next` pointer. Does not call any additional C functions (reads from already-populated struct).

**TASK-008: Directory Listing with Dedup**
- Phase:       5
- Depends on:  TASK-006, TASK-003
- Size:        L
- Description: Create `Sources/SwiftMTP/MTPDirectoryListing.swift` with `listDirectory(storageId:parentId:)` method on `MTPDevice`. Implement the dedup algorithm from mtp-module.c:
  1. Call `LIBMTP_Get_Folder_List` → collect all folder IDs into a `Set<UInt32>`
  2. Walk the tree recursively to find folders whose `parent_id` matches `parentId` → add to results as `MTPFileInfo`, track their IDs in `synthIds: Set<UInt32>`
  3. Call `LIBMTP_destroy_folder_t` on the tree
  4. Call `LIBMTP_Get_Files_And_Folders(device, storageId, parentId)` → walk linked list
  5. For each file: skip if `parent_id != parentId`; skip if `item_id` in `synthIds`; if `item_id` in folder ID set and `filetype != FOLDER`, mark as directory; add to results
  6. Free each file node with `LIBMTP_destroy_file_t`
  All C memory must be freed before returning or throwing.
- Acceptance:  Folders appear exactly once in results. Files that are secretly folders (known to the folder tree) have `isDirectory: true`. All C allocations are freed (no leaks). `storageId=0, parentId=0` lists root.

**TASK-009: Path Resolution**
- Phase:       5
- Depends on:  TASK-008
- Size:        M
- Description: Add `resolvePath(_:storageId:)` method to `MTPDevice`. Split path on `/`, walk component-by-component. For each component, call `LIBMTP_Get_Files_And_Folders(device, storageId, currentParent)`, scan for matching filename, advance `currentParent`. Return the final match as `MTPFileInfo` or `nil` if any component is not found. Free file lists after each step.
- Acceptance:  `resolvePath("/")` returns `nil` (root has no metadata). `resolvePath("/Documents/test.txt")` walks two levels. Returns `nil` for nonexistent paths without throwing. Frees intermediate file lists.

**TASK-010: File Download & Upload**
- Phase:       6
- Depends on:  TASK-006, TASK-004, TASK-002
- Size:        M
- Description: Create `Sources/SwiftMTP/MTPFileOperations.swift`. Add `downloadFile(id:to:progress:)` — calls `LIBMTP_Get_File_To_File` with optional progress callback bridge. Add `uploadFile(from:parentId:storageId:filename:progress:)` — calls `stat()` on local file, creates `LIBMTP_file_t` via `LIBMTP_new_file_t`, sets filename/filesize/parent_id/storage_id/filetype(UNKNOWN), calls `LIBMTP_Send_File_From_File`, reads back `item_id`, frees the file struct. Add `fileInfo(id:)` — calls `LIBMTP_Get_Filemetadata`. All operations drain error stack on failure and throw `MTPError`.
- Acceptance:  Upload uses `LIBMTP_FILETYPE_UNKNOWN`. Upload returns new object ID. Download throws on failure. Progress callback is optional (nil → NULL). Upload does `strdup` for filename in the file_t struct (libmtp frees it via `destroy_file_t`). `fileInfo` throws `objectNotFound` when ID doesn't exist.

**TASK-011: Delete, Mkdir, Move, Rename**
- Phase:       7
- Depends on:  TASK-006, TASK-002
- Size:        M
- Description: Add to `MTPFileOperations.swift`:
  - `deleteObject(id:)` — calls `LIBMTP_Delete_Object`
  - `createDirectory(name:parentId:storageId:)` — calls `LIBMTP_Create_Folder` with `strdup(name)` (C function takes ownership). Returns new folder ID. Returns 0 → throw.
  - `moveObject(id:toParentId:storageId:)` — calls `LIBMTP_Move_Object`. Detects failure with "MoveObject" in error text → throws `MTPError.moveNotSupported`.
  - `renameFile(id:newName:)` — calls `LIBMTP_Get_Filemetadata` then `LIBMTP_Set_File_Name`
  - `renameFolder(id:newName:)` — calls `LIBMTP_Get_Folder_List`, `LIBMTP_Find_Folder`, `LIBMTP_Set_Folder_Name`, frees folder tree
- Acceptance:  `createDirectory` passes `strdup`'d name (never freed by Swift). `moveObject` throws `.moveNotSupported` on failure. `renameFolder` finds folder in tree before renaming. All operations drain error stack on failure.

**TASK-012: Tests**
- Phase:       8
- Depends on:  TASK-001 through TASK-011
- Size:        M
- Description: Create `Tests/SwiftMTPTests/SwiftMTPTests.swift`. Since MTP requires a physical device, tests focus on:
  1. **Build verification**: `import SwiftMTP` compiles, `import Clibmtp` compiles
  2. **Type construction**: Create `MTPFileInfo`, `MTPRawDevice`, `MTPStorageInfo` with known values, verify fields
  3. **Error types**: Verify `MTPError` cases are `Equatable` and have meaningful descriptions
  4. **Discovery without device**: `mtpInitialize()` succeeds, `mtpDetectDevices()` returns empty array (no device connected in CI)
  5. **Integration tests** (gated by environment variable `MTP_DEVICE_CONNECTED=1`): full device lifecycle, list root, resolve path, upload+download+delete round-trip
  Use `@Test` with Swift 6.2 raw identifier syntax for test names.
- Acceptance:  `swift test` passes with no device connected (integration tests skipped). All type tests verify field values. Build verification test imports both modules.

### 7.3 Dependency Graph

```
TASK-001 (scaffold)
  ├── TASK-002 (errors)
  ├── TASK-003 (value types)
  │
  ├── TASK-004 (progress callback)
  │
  ├── TASK-005 (discovery) ── depends on TASK-002, TASK-003
  │
  ├── TASK-006 (device lifecycle) ── depends on TASK-002, TASK-003, TASK-005
  │     │
  │     ├── TASK-007 (storage) ── depends on TASK-006
  │     │
  │     ├── TASK-008 (directory listing) ── depends on TASK-006, TASK-003
  │     │     │
  │     │     └── TASK-009 (path resolution) ── depends on TASK-008
  │     │
  │     ├── TASK-010 (file I/O) ── depends on TASK-006, TASK-004, TASK-002
  │     │
  │     └── TASK-011 (delete/mkdir/move/rename) ── depends on TASK-006, TASK-002
  │
  └── TASK-012 (tests) ── depends on all above
```

### 7.4 Risk-Ordered Priorities

1. **TASK-001** — Highest risk: if pkg-config integration fails, nothing else works. Validate first.
2. **TASK-006** — Second highest: device open/close establishes the C interop pattern for everything else.
3. **TASK-008** — Most complex logic: dedup algorithm has several edge cases.
4. **TASK-010** — Progress callback bridging is tricky with Swift memory safety.

## 8. Design Assumptions

| ID | Assumption | Based On | Risk If Wrong |
|---|---|---|---|
| A-001 | libmtp is installed via Homebrew and pkg-config works | macOS development practice | Build fails; would need manual -I/-L flags |
| A-002 | Uncached mode provides `LIBMTP_Get_Files_And_Folders` | libmtp source + mtp-module.c usage | Would need to use cached mode or alternative API |
| A-003 | `LIBMTP_Create_Folder` always takes ownership of name | libmtp source code inspection | Memory leak or double-free |
| A-004 | Folder tree dedup is necessary for correct listing | mtp-module.c behavior, device testing | Duplicate or missing entries |
| A-005 | `storage_id=0` means "all storages" in read operations | mtp-module.c usage pattern | Would need to iterate storages |
| A-006 | MoveObject is commonly unsupported | mtp-backend.el three-tier strategy | Rename fallback path unused |
| A-007 | Object IDs are `UInt32` (32-bit) | `object_bitsize` field exists but all APIs use `uint32_t` | Truncation on 64-bit devices (rare) |
| A-008 | `LIBMTP_Init` is idempotent | libmtp docs + common practice | Multiple init calls could crash |
| A-009 | Progress callback returning non-zero cancels transfer | libmtp header documentation | Cancel wouldn't work |
| A-010 | `LIBMTP_Send_File_From_File` populates `item_id` on success | mtp-module.c reading `file_metadata->item_id` after send | Would need separate metadata lookup |

## 9. Design Decisions & Trade-offs

| ID | Decision | Alternatives Considered | Rationale |
|---|---|---|---|
| D-001 | `MTPDevice` is `~Copyable` class | Regular class, struct with manual close | Prevents double-free of device pointer. `deinit` guarantees cleanup. `~Copyable` prevents accidental copies. |
| D-002 | Uncached mode only | Cached mode, mixed | Uncached is faster to open, required for `Get_Files_And_Folders`, and matches mtp-module.c approach. Cached mode fetches entire object tree at open. |
| D-003 | No internal caching | Cache in Swift layer | Callers know their access patterns better. Keeps library simple and predictable. Matches the "stateless library" philosophy. |
| D-004 | `storage_id=0` default for reads | Require explicit storage ID | Simplifies API for single-storage devices (most common case). Matches mtp-module.c convention. Callers can pass specific ID for multi-storage. |
| D-005 | Separate `renameFile`/`renameFolder` | Single `rename` method | libmtp has different C APIs for files vs folders (different struct types required). A unified method would need to probe type first, adding an extra round-trip. |
| D-006 | Typed throws `throws(MTPError)` | Untyped `throws` | Swift 6.0 feature. Gives callers exhaustive switch over error cases. |
| D-007 | Free functions for init/detect | Static methods on MTPDevice | Discovery happens before you have a device. Separate concern. |
| D-008 | `MTPFileInfo` unifies files and folders | Separate `MTPFile`/`MTPFolder` types | Directory listings mix both. Unified type simplifies collection handling. `isDirectory` flag distinguishes. Matches mtp-module.c plist schema. |
| D-009 | Error stack drained on every failure | Only on explicit request | Prevents error leakage between operations. Matches mtp-module.c `signal_mtp_error` pattern. |
| D-010 | `strdup` for `Create_Folder` name | Swift auto-bridging | Swift's automatic C string bridging creates a temporary that would be freed after the call returns, but `Create_Folder` stores the pointer. Must manually allocate. |
| D-011 | macOS 14+ minimum | macOS 13, macOS 12 | Required for modern Swift concurrency features and `~Copyable`. |
| D-012 | `.library` product (not executable) | CLI tool, framework | Designed to be consumed by other Swift projects (e.g., a macOS app or CLI). |

## 10. Execution Notes

### 10.1 Execution Order

Implement tasks in numerical order. TASK-001 must be verified (swift build succeeds) before proceeding. TASK-012 can have stubs added incrementally as each task completes.

### 10.2 Validation Gates

After each task:
- `swift build` succeeds with no warnings
- No force-unwraps (`!`) except where C API guarantees non-nil
- All C memory freed on all paths (including error paths)
- `swift test` passes (may be trivial initially)

### 10.3 Coding Conventions

- No comments in code
- Swift 6.2 strict concurrency
- All public types are `Sendable`
- Internal helpers are `internal` (not `public`)
- C interop helpers are `private` or `internal`
- Test names use Swift 6.2 raw identifier syntax: `@Test func \`description here\`() { }`
- Prefer `guard let` for nil checks over `if let`
- Prefer `defer` for cleanup of C resources

### 10.4 File Organization

One logical concern per file. Extensions on `MTPDevice` are used to spread methods across files without subclassing.

### 10.5 Error Handling Pattern

Every method that calls libmtp follows this pattern:

```swift
let ret = LIBMTP_Some_Function(raw, ...)
if ret != 0 {
    let message = drainErrorStack(raw)
    throw MTPError.operationFailed(message)
}
```

The `drainErrorStack` helper walks the error linked list, collects messages, and calls `LIBMTP_Clear_Errorstack`.

## 11. Stretch Goals (Deferred)

These are documented for future implementation but explicitly out of scope for the initial task breakdown:

- **Track operations**: `LIBMTP_track_t` based APIs for music metadata
- **Album operations**: `LIBMTP_album_t` based APIs
- **Playlist operations**: `LIBMTP_playlist_t` based APIs
- **Event monitoring**: `LIBMTP_Read_Event_Async` for device change notifications
- **Partial I/O**: `GetPartialObject`/`SendPartialObject` for large file streaming
- **Async/await wrappers**: Swift concurrency wrappers around blocking C calls
- **Device capability queries**: Richer capability reporting beyond MoveObject check
