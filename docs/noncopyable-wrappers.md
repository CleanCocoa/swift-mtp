# Noncopyable Wrappers for C Resource Management

Replace raw pointer `defer`/`destroy` patterns with Swift 6.2 `~Copyable` structs that guarantee cleanup via `deinit`. The key design principle: **wrappers create the resource internally** — the `init` that takes a raw pointer is `fileprivate`, and the public/internal API is use-case specific types with descriptive names.

## Motivation: before and after

### Upload a file

Before — 12 lines, 5 raw `pointee` writes, manual `defer`, `strdup` at call site:

```swift
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

After — `Upload` owns the C struct from creation to destruction:

```swift
guard let upload = Upload(
    filename: filename, filesize: fileSize,
    parentId: parentId, storageId: storageId
) else {
    throw MTPError.operationFailed("failed to allocate file metadata")
}

let ret = withProgressCallback(progress) { callback, data in
    upload.send(device: raw, from: localPath, callback: callback, data: data)
}
// ... error handling ...
return upload.itemId
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

After — `FolderTree` encapsulates find + mutate, interior pointer never escapes:

```swift
guard let tree = FolderTree(device: raw) else {
    _ = drainErrorStack(raw)
    throw MTPError.objectNotFound(id: id)
}
guard let ret = tree.rename(device: raw, folderId: id, to: newName) else {
    throw MTPError.objectNotFound(id: id)
}
```

No `defer`, no `LIBMTP_Find_Folder`, no `LIBMTP_destroy_folder_t`.

### Rename a file

Before:

```swift
guard let file = LIBMTP_Get_Filemetadata(raw, id) else {
    _ = drainErrorStack(raw)
    throw MTPError.objectNotFound(id: id)
}
defer { LIBMTP_destroy_file_t(file) }
let ret = LIBMTP_Set_File_Name(raw, file, newName)
```

After:

```swift
guard let handle = FileHandle(device: raw, id: id) else {
    _ = drainErrorStack(raw)
    throw MTPError.objectNotFound(id: id)
}
let ret = handle.rename(device: raw, to: newName)
```

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

After — `FileNode` owns each node, deinit frees, `isFolder` replaces C enum:

```swift
var cursor = FileNode.list(device: raw, storageId: storageId, parentId: parentId)
while let rawPtr = cursor {
    let node = FileNode(rawPtr)
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

No `defer`, no `pointee`, no `LIBMTP_FILETYPE_FOLDER`, no `LIBMTP_destroy_file_t`.

## Design: `MTPCTypes.swift`

All wrapper types live in a single new file. They are `internal` — implementation details, not public API. Each type is use-case specific: named for what it *does*, not what C struct it wraps.

### 1. Upload — outbound file metadata for `LIBMTP_Send_File_From_File`

```swift
struct Upload: ~Copyable {
    private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

    init?(filename: String, filesize: UInt64, parentId: UInt32, storageId: UInt32) {
        guard let p = LIBMTP_new_file_t() else { return nil }
        p.pointee.filename = strdup(filename)
        p.pointee.filesize = filesize
        p.pointee.parent_id = parentId
        p.pointee.storage_id = storageId
        p.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
        self.pointer = p
    }

    deinit { LIBMTP_destroy_file_t(pointer) }

    var itemId: UInt32 { pointer.pointee.item_id }

    func send(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
        from localPath: String,
        callback: LIBMTP_progressfunc_t?,
        data: UnsafeMutableRawPointer?
    ) -> CInt {
        LIBMTP_Send_File_From_File(device, localPath, pointer, callback, data)
    }
}
```

All C struct configuration happens in `init`. `send()` and `itemId` are the only operations. No factory function needed — the `init` *is* the factory.

### 2. FileHandle — single file metadata for rename, download, inspect

```swift
struct FileHandle: ~Copyable {
    private let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

    init?(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>, id: UInt32) {
        guard let p = LIBMTP_Get_Filemetadata(device, id) else { return nil }
        self.pointer = p
    }

    deinit { LIBMTP_destroy_file_t(pointer) }

    func toFileInfo() -> MTPFileInfo { MTPFileInfo(cFile: pointer) }

    func rename(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
        to newName: String
    ) -> CInt {
        LIBMTP_Set_File_Name(device, pointer, newName)
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

Used by `fileInfo()`, `renameFile()`, and `downloadFile()`.

### 3. FileNode — single node during linked list iteration

```swift
struct FileNode: ~Copyable {
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

    static func list(
        device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
        storageId: UInt32,
        parentId: UInt32
    ) -> UnsafeMutablePointer<LIBMTP_file_struct>? {
        LIBMTP_Get_Files_And_Folders(device, storageId, parentId)
    }
}
```

`list()` is a static factory returning the raw linked list head. Each node is wrapped individually during iteration via `fileprivate init`. `next` is `fileprivate` — only the iteration pattern inside `MTPCTypes.swift` uses it.

`LIBMTP_destroy_file_t` frees a single node (flat singly-linked list), so per-node ownership is safe.

### 4. FolderTree — folder tree root with traversal and mutation

```swift
struct FolderTree: ~Copyable {
    private let root: UnsafeMutablePointer<LIBMTP_folder_struct>

    init?(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>) {
        guard let p = LIBMTP_Get_Folder_List(device) else { return nil }
        self.root = p
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

The interior pointer from `LIBMTP_Find_Folder` never leaves the wrapper — `rename()` encapsulates find + mutate.

**Never wrap interior folder nodes in ~Copyable** — `LIBMTP_destroy_folder_t` frees the entire tree recursively. Only the root gets wrapped.

The two private recursive helpers (`_collectAllFolderIds`, `_collectChildFolders`) move from `MTPDirectoryListing.swift` to `MTPCTypes.swift`.

## Call sites to refactor

### `MTPDirectoryListing.swift`

**`listDirectory`**:
- `LIBMTP_Get_Folder_List` + explicit destroy → `FolderTree(device:)`
- `LIBMTP_Get_Files_And_Folders` + per-node `defer` → `FileNode.list()` + `FileNode` per iteration
- Remove private helpers (moved to `FolderTree`)

**`resolvePath`**:
- Same file list loop → `FileNode.list()` + `FileNode` per node

### `MTPFileOperations.swift`

**`downloadFile`**: direct `LIBMTP_Get_File_To_File` → `FileHandle(device:id:)` + `handle.download()`

**`uploadFile`**: `LIBMTP_new_file_t` + 5 `pointee` writes + `defer` → `Upload(filename:filesize:parentId:storageId:)` + `upload.send()` + `upload.itemId`

**`fileInfo`**: `LIBMTP_Get_Filemetadata` + `defer` → `FileHandle(device:id:)` + `handle.toFileInfo()`

**`renameFile`**: `Get_Filemetadata` + `defer` + `Set_File_Name` → `FileHandle(device:id:)` + `handle.rename()`

**`renameFolder`**: `Get_Folder_List` + `defer` + `Find_Folder` + `Set_Folder_Name` → `FolderTree(device:)` + `tree.rename()`

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
