# Noncopyable Wrappers for C Resource Management

Replace raw pointer `defer`/`destroy` patterns with Swift 6.2 `~Copyable` structs that guarantee cleanup via `deinit`. The key design principle: **wrappers create the resource internally** — the `init` that takes a raw pointer is `fileprivate`, and the public/internal API uses factory functions following the Swift API Design Guidelines (`makeXYZ` naming).

## Design: `MTPCTypes.swift`

All wrapper types and their factories live in a single new file. They are `internal` — implementation details, not public API.

### 1. MTPOwnedFile — single owned `LIBMTP_file_struct`

Unifies three allocation patterns: per-node ownership from linked list iteration (`Get_Files_And_Folders`), single metadata lookup (`Get_Filemetadata`), and fresh allocation for uploads (`new_file_t`).

```swift
struct MTPOwnedFile: ~Copyable {
    let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

    fileprivate init(_ pointer: UnsafeMutablePointer<LIBMTP_file_struct>) {
        self.pointer = pointer
    }

    deinit { LIBMTP_destroy_file_t(pointer) }

    var next: UnsafeMutablePointer<LIBMTP_file_struct>? { pointer.pointee.next }
    func toFileInfo() -> MTPFileInfo { MTPFileInfo(cFile: pointer) }
    var itemId: UInt32 { pointer.pointee.item_id }
    var parentId: UInt32 { pointer.pointee.parent_id }
    var filetype: LIBMTP_filetype_t { pointer.pointee.filetype }
}
```

Factory functions:

```swift
func makeFileList(
    device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
    storageId: UInt32,
    parentId: UInt32
) -> UnsafeMutablePointer<LIBMTP_file_struct>? {
    LIBMTP_Get_Files_And_Folders(device, storageId, parentId)
}

func makeFileMetadata(
    device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
    id: UInt32
) -> MTPOwnedFile? {
    guard let p = LIBMTP_Get_Filemetadata(device, id) else { return nil }
    return MTPOwnedFile(p)
}

func makeNewFile() -> MTPOwnedFile? {
    guard let p = LIBMTP_new_file_t() else { return nil }
    return MTPOwnedFile(p)
}
```

`makeFileList` returns the raw pointer (not `MTPOwnedFile`) because the linked list is walked node-by-node — each node becomes an `MTPOwnedFile` inside the loop via its `fileprivate init`. Wrapping the head would imply ownership of the entire list, which is wrong since `destroy_file_t` only frees one node.

Linked list walk pattern:

```swift
var cursor = makeFileList(device: raw, storageId: storageId, parentId: parentId)
while let rawPtr = cursor {
    let node = MTPOwnedFile(rawPtr)
    cursor = node.next
    if node.parentId != parentId { continue }
    results.append(node.toFileInfo())
}
```

### 2. MTPOwnedFolderTree — folder tree root owner

Owns the root from `LIBMTP_Get_Folder_List`. Deinit calls `LIBMTP_destroy_folder_t`, which recursively frees the entire tree. The recursive traversal helpers (`collectAllFolderIds`, `collectChildFolders`) move here as methods.

```swift
struct MTPOwnedFolderTree: ~Copyable {
    private let root: UnsafeMutablePointer<LIBMTP_folder_struct>

    fileprivate init(_ root: UnsafeMutablePointer<LIBMTP_folder_struct>) {
        self.root = root
    }

    deinit { LIBMTP_destroy_folder_t(root) }

    func collectAllFolderIds(into ids: inout Set<UInt32>) {
        _collectAllFolderIds(root, into: &ids)
    }

    func collectChildFolders(
        parentId: UInt32,
        results: inout [MTPFileInfo],
        synthIds: inout Set<UInt32>
    ) {
        _collectChildFolders(root, parentId: parentId, results: &results, synthIds: &synthIds)
    }

    func find(id: UInt32) -> UnsafeMutablePointer<LIBMTP_folder_struct>? {
        LIBMTP_Find_Folder(root, id)
    }
}
```

Factory:

```swift
func makeFolderTree(
    device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>
) -> MTPOwnedFolderTree? {
    guard let p = LIBMTP_Get_Folder_List(device) else { return nil }
    return MTPOwnedFolderTree(p)
}
```

The two private recursive helpers move from `MTPDirectoryListing.swift` to `MTPCTypes.swift` with underscore-prefixed names (`_collectAllFolderIds`, `_collectChildFolders`).

**Never wrap interior folder nodes in ~Copyable** — `destroy_folder_t` on an interior node would double-free children when the root is later destroyed. Interior pointers from `find()` must not outlive the tree.

## Call sites to refactor

### `MTPDirectoryListing.swift`

**`listDirectory`**:
- `LIBMTP_Get_Folder_List` + explicit `LIBMTP_destroy_folder_t` → `makeFolderTree` (deinit handles free)
- `LIBMTP_Get_Files_And_Folders` + per-node `defer { destroy }` → `makeFileList` + `MTPOwnedFile` per iteration
- Remove private helpers `collectAllFolderIds` and `collectChildFolders` (moved to `MTPOwnedFolderTree`)

**`resolvePath`**:
- Same file list loop: `makeFileList` + `MTPOwnedFile` per node

### `MTPFileOperations.swift`

**`uploadFile`**: `LIBMTP_new_file_t` + `defer { destroy }` → `makeNewFile()`

**`fileInfo`**: `LIBMTP_Get_Filemetadata` + `defer { destroy }` → `makeFileMetadata(device:id:)`

**`renameFile`**: same `Get_Filemetadata` pattern → `makeFileMetadata`

**`renameFolder`**: `LIBMTP_Get_Folder_List` + `defer { destroy }` + `LIBMTP_Find_Folder` → `makeFolderTree` + `.find(id:)`

## What does NOT change

- No public API changes — all wrappers are `internal`
- No test changes — same behavior, structural cleanup only
- `MTPDevice.swift` — its `defer { free(rawDevices) }` is for a C array, not a libmtp-managed resource
- `MTPDeviceDiscovery.swift` — same

## Future ideas (not in scope)

### MTPResult — error stack drain guarantee

A `~Copyable` wrapper that ensures `drainErrorStack` is called even if the caller forgets. Deinit clears the error stack to prevent stale errors leaking.

```swift
struct MTPResult<T>: ~Copyable {
    private let device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>
    private let value: Result<T, String>

    consuming func get() throws(MTPError) -> T { ... }
    deinit { if case .failure = value { LIBMTP_Clear_Errorstack(device) } }
}
```

Does not help for operations that classify errors further (checking for "storage full", "MoveObject"). Lifetime coupling to `MTPDevice` not enforced statically.

### TransferSession — callback context owner

Replaces `withUnsafeMutablePointer` stack pin for progress callbacks. Tradeoff: one heap allocation vs. current zero-allocation stack pin. The nil-handler fast path should remain allocation-free.

### Consuming MTPRawDevice → MTPDevice

Store `LIBMTP_raw_device_t` by value in a ~Copyable `MTPRawDevice`. Consuming `open()` eliminates the double device scan. Public API break — worth it pre-1.0.

### MTPDevice as ~Copyable struct

`borrowing self` for reads, `consuming func disconnect()` to prevent use-after-release. **Blocked: classes cannot be ~Copyable in Swift 6.2.**

### Span for raw device arrays

Marginal benefit. `UnsafeBufferPointer` is already fine. `LIBMTP_Open_Raw_Device_Uncached` takes `inout`, requiring a copy anyway.

## Pitfalls

- **Folder tree recursive free**: `LIBMTP_destroy_folder_t` frees the entire tree. Only the root gets wrapped. Interior nodes borrow from the live tree.
- **`discard self` availability**: May still be experimental. Use borrowing extraction so deinit always fires.
- **`Sequence` conformance blocked**: `~Copyable` types can't be `Sequence.Element`. Use `while let` loops.
- **`Sendable` conformance blocked**: `~Copyable` structs can't conform to `Sendable`. Correct for MTP (inherently serial).
- **Cursor ordering**: `node.next` must be read while the node is still live — before any `continue` that drops it.
- **`LIBMTP_destroy_file_t` frees filename**: The `strdup` ownership is transferred into the C struct. The ~Copyable wrapper doesn't change this.

## Concurrency (adjacent concern)

libmtp is not thread-safe. Options:

- `@MainActor` on `MTPDevice` — simplest, forces main thread
- Custom serial `actor` — proper isolation, adds `await` everywhere
- Status quo — fine for CLI tools, latent bug for concurrent apps

Orthogonal to ~Copyable but worth deciding alongside any API redesign.
