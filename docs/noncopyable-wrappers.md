# Noncopyable Wrappers for C Resource Management

Replace raw pointer `defer`/`destroy` patterns with Swift 6.2 `~Copyable` structs that guarantee cleanup via `deinit`. The key design principle: **wrappers create the resource internally** — the `init` that takes a raw pointer is `fileprivate`, and the public/internal API uses factory functions following the Swift API Design Guidelines (`makeXYZ` naming).

## Motivation: before and after

### Upload a file

Before — 12 lines, 5 raw `pointee` writes, manual `defer`, `strdup` at call site:

```swift
let attrs = try FileManager.default.attributesOfItem(atPath: localPath)
let fileSize = (attrs[.size] as? UInt64) ?? 0

guard let metadata = LIBMTP_new_file_t() else {
    throw MTPError.operationFailed("failed to allocate file metadata")
}
defer { LIBMTP_destroy_file_t(metadata) }

metadata.pointee.filename = strdup(filename)
metadata.pointee.filesize = fileSize
metadata.pointee.parent_id = parentId
metadata.pointee.storage_id = storageId
metadata.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN

let ret = withProgressCallback(progress) { callback, data in
    LIBMTP_Send_File_From_File(raw, localPath, metadata, callback, data)
}
// ... error handling ...
return metadata.pointee.item_id
```

After — factory creates + configures, method sends, property reads back the ID:

```swift
let attrs = try FileManager.default.attributesOfItem(atPath: localPath)
let fileSize = (attrs[.size] as? UInt64) ?? 0

guard let metadata = makeUploadMetadata(
    filename: filename, filesize: fileSize,
    parentId: parentId, storageId: storageId
) else {
    throw MTPError.operationFailed("failed to allocate file metadata")
}

let ret = withProgressCallback(progress) { callback, data in
    metadata.send(device: raw, from: localPath, callback: callback, data: data)
}
// ... error handling ...
return metadata.itemId
```

No `defer`, no `pointee`, no `strdup`, no `LIBMTP_FILETYPE_UNKNOWN`, no `LIBMTP_destroy_file_t`.

### Rename a folder

Before — 3 C calls, `defer`, interior pointer escapes into caller scope:

```swift
guard let folderTree = LIBMTP_Get_Folder_List(raw) else {
    _ = drainErrorStack(raw)
    throw MTPError.objectNotFound(id: id)
}
defer { LIBMTP_destroy_folder_t(folderTree) }
guard let folder = LIBMTP_Find_Folder(folderTree, id) else {
    throw MTPError.objectNotFound(id: id)
}
let ret = LIBMTP_Set_Folder_Name(raw, folder, newName)
```

After — factory creates, method encapsulates find + mutate, interior pointer never escapes:

```swift
guard let tree = makeFolderTree(device: raw) else {
    _ = drainErrorStack(raw)
    throw MTPError.objectNotFound(id: id)
}
guard let ret = tree.rename(device: raw, folderId: id, to: newName) else {
    throw MTPError.objectNotFound(id: id)
}
```

No `defer`, no `LIBMTP_Find_Folder`, no `LIBMTP_destroy_folder_t`. The interior pointer from `Find_Folder` lives and dies inside `rename()`.

### List directory (file loop)

Before — manual linked list walk with `defer` per node, C enum comparison:

```swift
var fileList = LIBMTP_Get_Files_And_Folders(raw, storageId, parentId)
while let file = fileList {
    let next = file.pointee.next
    defer { LIBMTP_destroy_file_t(file) }

    if file.pointee.parent_id != parentId { fileList = next; continue }
    if synthIds.contains(file.pointee.item_id) { fileList = next; continue }
    if allFolderIds.contains(file.pointee.item_id) && file.pointee.filetype != LIBMTP_FILETYPE_FOLDER {
        let info = MTPFileInfo(cFile: file)
        results.append(MTPFileInfo(
            id: info.id, parentId: info.parentId, storageId: info.storageId,
            name: info.name, size: info.size, modificationDate: info.modificationDate,
            isDirectory: true
        ))
    } else {
        results.append(MTPFileInfo(cFile: file))
    }
    fileList = next
}
```

After — `MTPOwnedFile` owns each node, deinit frees, `isFolder` replaces C enum:

```swift
var cursor = makeFileList(device: raw, storageId: storageId, parentId: parentId)
while let rawPtr = cursor {
    let node = MTPOwnedFile(rawPtr)
    cursor = node.next

    if node.parentId != parentId { continue }
    if synthIds.contains(node.itemId) { continue }
    if allFolderIds.contains(node.itemId) && !node.isFolder {
        let info = node.toFileInfo()
        results.append(MTPFileInfo(
            id: info.id, parentId: info.parentId, storageId: info.storageId,
            name: info.name, size: info.size, modificationDate: info.modificationDate,
            isDirectory: true
        ))
    } else {
        results.append(node.toFileInfo())
    }
}
```

No `defer`, no `pointee`, no `LIBMTP_FILETYPE_FOLDER`, no `LIBMTP_destroy_file_t`. Each `node` is freed when it goes out of scope at the end of the loop iteration.

## Design: `MTPCTypes.swift`

All wrapper types and their factories live in a single new file. They are `internal` — implementation details, not public API.

### 1. MTPOwnedFile — single owned `LIBMTP_file_struct`

Unifies three allocation patterns: per-node ownership from linked list iteration (`Get_Files_And_Folders`), single metadata lookup (`Get_Filemetadata`), and fresh allocation for uploads (`new_file_t`).

```swift
struct MTPOwnedFile: ~Copyable {
    private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

    fileprivate init(_ pointer: UnsafeMutablePointer<LIBMTP_file_struct>) {
        self.pointer = pointer
    }

    deinit { LIBMTP_destroy_file_t(pointer) }

    fileprivate var next: UnsafeMutablePointer<LIBMTP_file_struct>? { pointer.pointee.next }

    func toFileInfo() -> MTPFileInfo { MTPFileInfo(cFile: pointer) }
    var itemId: UInt32 { pointer.pointee.item_id }
    var parentId: UInt32 { pointer.pointee.parent_id }
    var isFolder: Bool { pointer.pointee.filetype == LIBMTP_FILETYPE_FOLDER }

    func rename(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
        to newName: String
    ) -> CInt {
        LIBMTP_Set_File_Name(device, pointer, newName)
    }

    func send(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
        from localPath: String,
        callback: LIBMTP_progressfunc_t?,
        data: UnsafeMutableRawPointer?
    ) -> CInt {
        LIBMTP_Send_File_From_File(device, localPath, pointer, callback, data)
    }

    func download(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
        to localPath: String,
        callback: LIBMTP_progressfunc_t?,
        data: UnsafeMutableRawPointer?
    ) -> CInt {
        LIBMTP_Get_File_To_File(device, pointer.pointee.item_id, localPath, callback, data)
    }
}
```

`pointer` is `private`, `next` is `fileprivate` (only used in the linked list iteration pattern within `MTPCTypes.swift`). No C types or raw pointers escape the wrapper — `filetype` is exposed as `isFolder: Bool` rather than leaking `LIBMTP_filetype_t`.

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

func makeUploadMetadata(
    filename: String,
    filesize: UInt64,
    parentId: UInt32,
    storageId: UInt32
) -> MTPOwnedFile? {
    guard let p = LIBMTP_new_file_t() else { return nil }
    p.pointee.filename = strdup(filename)
    p.pointee.filesize = filesize
    p.pointee.parent_id = parentId
    p.pointee.storage_id = storageId
    p.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
    return MTPOwnedFile(p)
}
```

`makeFileList` returns the raw pointer (not `MTPOwnedFile`) because the linked list is walked node-by-node — each node becomes an `MTPOwnedFile` inside the loop via its `fileprivate init`. Wrapping the head would imply ownership of the entire list, which is wrong since `destroy_file_t` only frees one node.

`makeUploadMetadata` encapsulates all `pointee` access — callers never touch the C struct directly. The `strdup` for filename ownership transfer is hidden inside the factory.

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

    func rename(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
        folderId: UInt32,
        to newName: String
    ) -> CInt? {
        guard let folder = LIBMTP_Find_Folder(root, folderId) else { return nil }
        return LIBMTP_Set_Folder_Name(device, folder, newName)
    }
}
```

`find()` is gone — the interior pointer from `LIBMTP_Find_Folder` never leaves the wrapper. `rename()` encapsulates the find + mutate sequence, keeping the interior pointer scoped to the method body.

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

**Never wrap interior folder nodes in ~Copyable** — `destroy_folder_t` on an interior node would double-free children when the root is later destroyed.

## Call sites to refactor

### `MTPDirectoryListing.swift`

**`listDirectory`**:
- `LIBMTP_Get_Folder_List` + explicit `LIBMTP_destroy_folder_t` → `makeFolderTree` (deinit handles free)
- `LIBMTP_Get_Files_And_Folders` + per-node `defer { destroy }` → `makeFileList` + `MTPOwnedFile` per iteration
- Remove private helpers `collectAllFolderIds` and `collectChildFolders` (moved to `MTPOwnedFolderTree`)

**`resolvePath`**:
- Same file list loop: `makeFileList` + `MTPOwnedFile` per node

### `MTPFileOperations.swift`

**`downloadFile`**: `LIBMTP_Get_File_To_File` called directly with raw device pointer → `makeFileMetadata(device:id:)`, then `file.download(device:to:callback:data:)`

**`uploadFile`**: `LIBMTP_new_file_t` + `defer` + 5 lines of `pointee` setup → `makeUploadMetadata(filename:filesize:parentId:storageId:)`, then `metadata.send(device:from:callback:data:)`, then `metadata.itemId`

**`fileInfo`**: `LIBMTP_Get_Filemetadata` + `defer` → `makeFileMetadata(device:id:)`, then `file.toFileInfo()`

**`renameFile`**: `LIBMTP_Get_Filemetadata` + `defer` + `LIBMTP_Set_File_Name` → `makeFileMetadata(device:id:)`, then `file.rename(device:to:)`

**`renameFolder`**: `LIBMTP_Get_Folder_List` + `defer` + `LIBMTP_Find_Folder` + `LIBMTP_Set_Folder_Name` → `makeFolderTree(device:)`, then `tree.rename(device:folderId:to:)`

**`listDirectory`**: `file.pointee.filetype != LIBMTP_FILETYPE_FOLDER` → `node.isFolder` (no C enum type leaks)

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
