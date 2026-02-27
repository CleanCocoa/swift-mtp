# Implicit C Contracts with libmtp

This file documents undocumented libmtp behaviors that SwiftMTP relies on.
The libmtp header files contain no documentation; these contracts were
verified by reading `../libmtp/src/libmtp.c`.

## Memory Ownership

### String-returning functions allocate with `malloc`

`LIBMTP_Get_Manufacturername`, `LIBMTP_Get_Modelname`, `LIBMTP_Get_Serialnumber`,
`LIBMTP_Get_Friendlyname`, and `LIBMTP_Get_Deviceversion` all return
`malloc`-allocated strings. Caller must `free()`.

**Relied on by:** `Device.getString()` which calls `free(cStr)`.

### `LIBMTP_Create_Folder` takes ownership of its `name` parameter

The function stores the pointer directly in the folder struct. Caller must
pass a `strdup`'d string. Passing a Swift string's temporary buffer would
cause a use-after-free.

**Relied on by:** `FileOperations.swift` line 80 (`strdup(name)`).

### `LIBMTP_destroy_file_t` frees a single node only

Despite the linked list structure (`->next`), this function frees only the
single node passed to it — it does NOT walk `next`. This is what makes
per-node `FileNode` ownership safe.

**Relied on by:** `FileNode.deinit`, `FileHandle.deinit`, `Upload.deinit`,
`Upload.Uploaded.deinit`.

### `LIBMTP_destroy_folder_t` frees recursively

Unlike `destroy_file_t`, this walks `child` and `sibling` pointers and frees
the entire subtree. Only the root should be wrapped in `~Copyable`. Child
pointers borrowed from the tree must not outlive the root.

**Relied on by:** `FolderTree.deinit` (wraps root only).

### `LIBMTP_Detect_Raw_Devices` allocates a flat array with `malloc`

Returns a contiguous `malloc` array of `LIBMTP_raw_device_t`. Caller must
`free()` the array pointer (not individual elements).

**Relied on by:** `DeviceDiscovery.swift` and `Device.init(busLocation:devnum:)`
which both `defer { free(rawDevices) }`.

## Callback Contracts

### Progress callbacks are invoked synchronously

`LIBMTP_Send_File_From_File` and `LIBMTP_Get_File_To_File` invoke the
progress callback on the calling thread during the transfer loop. The
callback pointer is never stored or invoked after the function returns.

**Relied on by:** `withProgressCallback` which passes a pointer to a
stack-local closure. Safe only because the callback never escapes.

### Progress callback return value: 0 = continue, non-zero = cancel

**Relied on by:** `ProgressCallback.swift` line 18
(`handler(sent, total) ? 0 : 1`).

## Mutation Contracts

### `LIBMTP_Send_File_From_File` mutates the file struct

During upload, libmtp writes back the device-assigned `item_id` into the
file struct. It may also modify `filename`, `parent_id`, and `storage_id`
if the device applies restrictions. The `Upload` → `Uploaded` consuming
projection models this state change.

**Relied on by:** `Upload.send()` which reads back `item_id` etc. via
`Uploaded.toFileInfo()`.

### `LIBMTP_Open_Raw_Device_Uncached` takes `UnsafeMutablePointer`

The C function signature requires a mutable pointer to the raw device struct,
even though it conceptually only reads it. This is why `RawDevice.open()`
must be `mutating` — Swift enforces `&cRaw` requires a mutable binding.

**Relied on by:** `RawDevice.open()`.

## Error Stack

### Error stack is per-device, append-only until drained

libmtp appends errors to a linked list on the device struct. Errors
accumulate across calls. `LIBMTP_Get_Errorstack` returns the head;
`LIBMTP_Clear_Errorstack` frees all nodes and resets.

**Relied on by:** `drainErrorStack()` which reads then clears. Must be
called after each fallible operation to prevent stale errors leaking into
later diagnostics.

### Error stack nodes are owned by the device

`LIBMTP_Get_Errorstack` returns a pointer into the device's internal list.
The nodes must NOT be freed individually — `LIBMTP_Clear_Errorstack` frees
them all. Reading `error_text` is safe only before calling Clear.

**Relied on by:** `drainErrorStack()` which copies strings before clearing.

## Thread Safety

### libmtp is not thread-safe

No function in libmtp uses locking. A single `LIBMTP_mtpdevice_struct` must
not be accessed from multiple threads concurrently. `Device` does not add
synchronization — callers must serialize access.

## Blocking Behavior

### `LIBMTP_Read_Event` blocks indefinitely

This function blocks on a USB interrupt endpoint with no timeout. It returns
only when the device sends an event or disconnects. There is no cancellation
mechanism from the C API.

**Relied on by:** `Device.readEvent()`. Callers should run this on a
dedicated thread.
