# Noncopyable Wrappers for C Resource Management

Research findings on replacing raw pointer `defer`/`destroy` patterns with Swift 6.2 `~Copyable` structs that guarantee cleanup via `deinit`.

## High-Value Changes

### 1. MTPFileNode — single file list node

Wraps `UnsafeMutablePointer<LIBMTP_file_struct>`. Deinit calls `LIBMTP_destroy_file_t`. Replaces every `defer { LIBMTP_destroy_file_t(file) }` in `listDirectory` and `resolvePath`.

```swift
struct MTPFileNode: ~Copyable {
    private let ptr: UnsafeMutablePointer<LIBMTP_file_struct>

    init?(_ ptr: UnsafeMutablePointer<LIBMTP_file_struct>?) {
        guard let ptr else { return nil }
        self.ptr = ptr
    }

    deinit { LIBMTP_destroy_file_t(ptr) }

    var next: UnsafeMutablePointer<LIBMTP_file_struct>? { ptr.pointee.next }
    borrowing func toFileInfo() -> MTPFileInfo { MTPFileInfo(cFile: ptr) }
    borrowing var itemId: UInt32 { ptr.pointee.item_id }
    borrowing var parentId: UInt32 { ptr.pointee.parent_id }
    borrowing var filetype: LIBMTP_filetype_t { ptr.pointee.filetype }
}
```

Linked list walk becomes:

```swift
var cursor = LIBMTP_Get_Files_And_Folders(raw, storageId, parentId)
while let node = MTPFileNode(cursor) {
    cursor = node.next
    if node.parentId != parentId { continue }
    results.append(node.toFileInfo())
}
```

No `defer` needed — `node` is destroyed at end of each iteration. The compiler prevents use-after-free.

`LIBMTP_destroy_file_t` frees a single node (flat singly-linked list), so per-node ownership is safe.

### 2. MTPFolderTree — folder tree root owner

Wraps the root from `LIBMTP_Get_Folder_List`. Deinit calls `LIBMTP_destroy_folder_t`, which recursively frees the entire tree.

```swift
struct MTPFolderTree: ~Copyable {
    private let root: UnsafeMutablePointer<LIBMTP_folder_struct>

    init?(_ root: UnsafeMutablePointer<LIBMTP_folder_struct>?) {
        guard let root else { return nil }
        self.root = root
    }

    deinit { LIBMTP_destroy_folder_t(root) }

    borrowing func withRoot<R>(_ body: (UnsafeMutablePointer<LIBMTP_folder_struct>) -> R) -> R {
        body(root)
    }

    borrowing func find(id: UInt32) -> UnsafeMutablePointer<LIBMTP_folder_struct>? {
        LIBMTP_Find_Folder(root, id)
    }
}
```

Interior pointers from `find()` or recursive traversal must not outlive the tree. Use closure-based APIs to keep the tree borrowed:

```swift
guard let tree = MTPFolderTree(LIBMTP_Get_Folder_List(raw)) else { ... }
guard let folder = tree.find(id: id) else { ... }
let ret = LIBMTP_Set_Folder_Name(raw, folder, newName)
// tree.deinit fires here
```

**Never wrap interior folder nodes in ~Copyable** — `destroy_folder_t` on an interior node would double-free children when the root is later destroyed.

### 3. MTPFileHandle — upload/rename metadata

Wraps `LIBMTP_new_file_t()` allocation. Deinit calls `LIBMTP_destroy_file_t`. Cleanest 1-to-1 substitution of existing `guard let` + `defer` patterns.

```swift
struct MTPFileHandle: ~Copyable {
    let pointer: UnsafeMutablePointer<LIBMTP_file_struct>

    init?() {
        guard let p = LIBMTP_new_file_t() else { return nil }
        self.pointer = p
    }

    deinit { LIBMTP_destroy_file_t(pointer) }
}
```

Usage in `uploadFile`:

```swift
guard let metadata = MTPFileHandle() else {
    throw MTPError.operationFailed("failed to allocate file metadata")
}
metadata.pointer.pointee.filename = strdup(filename)
metadata.pointer.pointee.filesize = fileSize
// ...
let ret = LIBMTP_Send_File_From_File(raw, localPath, metadata.pointer, callback, data)
let itemId = metadata.pointer.pointee.item_id
// metadata.deinit fires — no defer needed
```

### 4. MTPResult — error stack drain guarantee

Ensures `drainErrorStack` is called even if the caller forgets. If nobody calls `.get()`, deinit still clears the error stack to prevent stale errors leaking into subsequent operations.

```swift
struct MTPResult<T>: ~Copyable {
    private let device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>
    private let value: Result<T, String>

    init(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>, returnCode: CInt, value: T) {
        self.device = device
        self.value = returnCode == 0 ? .success(value) : .failure("pending")
    }

    consuming func get() throws(MTPError) -> T {
        switch value {
        case .success(let v): return v
        case .failure:
            let msg = drainErrorStack(device)
            throw MTPError.operationFailed(msg)
        }
    }

    deinit {
        if case .failure = value {
            LIBMTP_Clear_Errorstack(device)
        }
    }
}
```

Does not help for operations that classify errors further (e.g. checking for "storage full" or "MoveObject" in the error text). Those still need custom drain logic.

Lifetime coupling: `MTPResult` must not outlive `MTPDevice`. Not enforced statically (would need `~Escapable` / lifetime annotations), but safe in practice since results are always stack-local.

## Medium-Value Ideas

### 5. TransferSession — callback context owner

Replaces `withUnsafeMutablePointer` stack pin for progress callbacks with a heap-allocated ~Copyable struct. Deinit deallocates the context pointer.

```swift
struct TransferSession: ~Copyable {
    private let box: UnsafeMutablePointer<ProgressHandler>

    init(handler: ProgressHandler) {
        box = .allocate(capacity: 1)
        box.initialize(to: handler)
    }

    deinit {
        box.deinitialize(count: 1)
        box.deallocate()
    }

    var cCallback: LIBMTP_progressfunc_t { /* C trampoline reading from box */ }
    var contextPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(box) }
}
```

Tradeoff: one pointer-sized heap allocation vs. current zero-allocation stack pin. The nil-handler fast path should remain allocation-free.

### 6. Consuming MTPRawDevice → MTPDevice

Store `LIBMTP_raw_device_t` by value in a ~Copyable `MTPRawDevice`. Consuming `open()` transfers ownership into `MTPDevice`, eliminating the double device scan.

```swift
extension MTPRawDevice {
    consuming func open() throws(MTPError) -> MTPDevice {
        try MTPDevice(consuming: self)
    }
}
```

Public API break. Worth it pre-1.0. The ergonomic gain (single-use token, no re-scan) is the main value, not performance.

### 7. MTPFileSequence — consuming linked list iterator

```swift
struct MTPFileSequence: ~Copyable {
    private var cursor: UnsafeMutablePointer<LIBMTP_file_struct>?

    mutating func next() -> MTPFileNode? {
        guard let current = cursor else { return nil }
        cursor = current.pointee.next
        return MTPFileNode(current)
    }
}
```

Cannot conform to `Sequence` because `~Copyable` types can't be `Sequence.Element`. Must use `while let node = seq.next()` instead of `for...in`.

## Blocked

### MTPDevice as ~Copyable struct

The most architecturally correct design: `borrowing self` for reads, `consuming func disconnect()` to prevent use-after-release. But **classes cannot be ~Copyable in Swift 6.2**. Workaround: an internal `MTPDeviceHandle: ~Copyable` struct inside the class prevents accidental pointer aliasing within the implementation, but does not change the public API.

### Span for raw device arrays

`Span` requires contiguous memory (only the `rawDevices` array qualifies). `LIBMTP_Open_Raw_Device_Uncached` takes `inout`, requiring a copy out of the span anyway. `UnsafeBufferPointer` already provides equivalent iteration safety within the `defer { free }` scope. Marginal benefit.

## Pitfalls

- **Folder tree recursive free**: `LIBMTP_destroy_folder_t` frees the entire tree from any node. Only the root should be wrapped in ~Copyable. Interior nodes must borrow from the live tree via closures.
- **`discard self` availability**: Suppressing deinit via `discard self` may still be experimental. Use `borrowing` extraction methods so deinit always fires.
- **`Sequence` conformance blocked**: `~Copyable` element types cannot satisfy `Sequence.Element`. Use `while let` loops.
- **`Sendable` conformance blocked**: `~Copyable` structs cannot conform to `Sendable`. Correct for MTP (inherently serial) but prevents actor-boundary crossing.
- **Cursor ordering in list walks**: `node.next` must be read while the node is still live — before any `continue` path that drops the node. `MTPFileSequence` enforces this structurally by advancing the cursor inside `next()`.
- **`LIBMTP_destroy_file_t` frees filename**: The `strdup` ownership for filenames is transferred into the C struct implicitly. The ~Copyable wrapper doesn't change this — it just makes the destroy call structural.

## Concurrency (adjacent concern)

libmtp is not thread-safe. Options for enforcement:

- `@MainActor` on `MTPDevice` — simplest, but forces all callers to main thread
- Custom serial `actor` — proper isolation, but adds `await` at every call site
- Status quo (no annotation) — fine for CLI tools, latent bug for concurrent apps

Orthogonal to ~Copyable but worth deciding alongside any API redesign.
