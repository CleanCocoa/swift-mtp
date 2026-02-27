# SwiftMTP Research Findings

Research captured from exploration of libmtp, mtp.el reference implementation, and Swift C interop patterns. This document provides everything needed to implement a Swift wrapper around libmtp.

## 1. libmtp C API Surface

Header: `libmtp.h` (installed via Homebrew at `/opt/homebrew/include/libmtp.h`).
Library: `libmtp` (1.1.23 on Homebrew as of writing). Linked via pkg-config.

### 1.1 Key Structs

#### `LIBMTP_raw_device_t`

```c
struct LIBMTP_raw_device_struct {
  LIBMTP_device_entry_t device_entry;  // vendor/product strings + IDs
  uint32_t bus_location;
  uint8_t devnum;
};

struct LIBMTP_device_entry_struct {
  char *vendor;
  uint16_t vendor_id;
  char *product;
  uint16_t product_id;
  uint32_t device_flags;
};
```

#### `LIBMTP_mtpdevice_t` (opaque device handle)

```c
struct LIBMTP_mtpdevice_struct {
  uint8_t object_bitsize;
  void *params;                          // PTPParams*
  void *usbinfo;                         // PTP_USB*
  LIBMTP_devicestorage_t *storage;       // linked list
  LIBMTP_error_t *errorstack;            // linked list
  uint8_t maximum_battery_level;
  uint32_t default_music_folder;
  uint32_t default_playlist_folder;
  uint32_t default_picture_folder;
  uint32_t default_video_folder;
  uint32_t default_organizer_folder;
  uint32_t default_zencast_folder;
  uint32_t default_album_folder;
  uint32_t default_text_folder;
  void *cd;                              // iconv converters
  LIBMTP_device_extension_t *extensions;
  int cached;
  LIBMTP_mtpdevice_t *next;
};
```

#### `LIBMTP_file_t`

```c
struct LIBMTP_file_struct {
  uint32_t item_id;
  uint32_t parent_id;
  uint32_t storage_id;
  char *filename;
  uint64_t filesize;
  time_t modificationdate;
  LIBMTP_filetype_t filetype;    // LIBMTP_FILETYPE_FOLDER for directories
  LIBMTP_file_t *next;          // singly-linked list
};
```

#### `LIBMTP_folder_t`

```c
struct LIBMTP_folder_struct {
  uint32_t folder_id;
  uint32_t parent_id;
  uint32_t storage_id;
  char *name;
  LIBMTP_folder_t *sibling;     // tree: next at same level
  LIBMTP_folder_t *child;       // tree: first child
};
```

#### `LIBMTP_devicestorage_t`

```c
struct LIBMTP_devicestorage_struct {
  uint32_t id;
  uint16_t StorageType;
  uint16_t FilesystemType;
  uint16_t AccessCapability;
  uint64_t MaxCapacity;
  uint64_t FreeSpaceInBytes;
  uint64_t FreeSpaceInObjects;
  char *StorageDescription;
  char *VolumeIdentifier;
  LIBMTP_devicestorage_t *next;
  LIBMTP_devicestorage_t *prev;  // doubly-linked
};
```

#### `LIBMTP_error_t`

```c
struct LIBMTP_error_struct {
  LIBMTP_error_number_t errornumber;
  char *error_text;
  LIBMTP_error_t *next;          // singly-linked stack
};
```

### 1.2 Key Enums

#### `LIBMTP_error_number_t`

```c
typedef enum {
  LIBMTP_ERROR_NONE,
  LIBMTP_ERROR_GENERAL,
  LIBMTP_ERROR_PTP_LAYER,
  LIBMTP_ERROR_USB_LAYER,
  LIBMTP_ERROR_MEMORY_ALLOCATION,
  LIBMTP_ERROR_NO_DEVICE_ATTACHED,
  LIBMTP_ERROR_STORAGE_FULL,
  LIBMTP_ERROR_CONNECTING,
  LIBMTP_ERROR_CANCELLED
} LIBMTP_error_number_t;
```

#### `LIBMTP_filetype_t` (subset relevant to file management)

`LIBMTP_FILETYPE_FOLDER`, `LIBMTP_FILETYPE_UNKNOWN`, plus media types (WAV, MP3, JPEG, etc.). Use `LIBMTP_FILETYPE_UNKNOWN` for generic file uploads.

#### `LIBMTP_event_t`

```c
typedef enum {
  LIBMTP_EVENT_NONE,
  LIBMTP_EVENT_STORE_ADDED,
  LIBMTP_EVENT_STORE_REMOVED,
  LIBMTP_EVENT_OBJECT_ADDED,
  LIBMTP_EVENT_OBJECT_REMOVED,
  LIBMTP_EVENT_DEVICE_PROPERTY_CHANGED,
} LIBMTP_event_t;
```

#### `LIBMTP_devicecap_t`

```c
typedef enum {
  LIBMTP_DEVICECAP_GetPartialObject,
  LIBMTP_DEVICECAP_SendPartialObject,
  LIBMTP_DEVICECAP_EditObjects,
  LIBMTP_DEVICECAP_MoveObject,
  LIBMTP_DEVICECAP_CopyObject,
} LIBMTP_devicecap_t;
```

### 1.3 Progress Callback

```c
typedef int (* LIBMTP_progressfunc_t)(uint64_t const sent, uint64_t const total, void const * const data);
```

Returns non-zero to cancel the transfer.

### 1.4 Functions by Category

#### Initialization

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Init` | `void LIBMTP_Init(void)` | Call once at startup. Idempotent. |
| `LIBMTP_Set_Debug` | `void LIBMTP_Set_Debug(int)` | 0=none, 0xFF=all |

#### Device Discovery

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Detect_Raw_Devices` | `LIBMTP_error_number_t (LIBMTP_raw_device_t**, int*)` | Caller frees array with `free()` |

#### Device Open/Close

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Open_Raw_Device` | `LIBMTP_mtpdevice_t* (LIBMTP_raw_device_t*)` | Cached mode (fetches full object list at open) |
| `LIBMTP_Open_Raw_Device_Uncached` | `LIBMTP_mtpdevice_t* (LIBMTP_raw_device_t*)` | Uncached mode — **use this one** |
| `LIBMTP_Release_Device` | `void (LIBMTP_mtpdevice_t*)` | Frees device and closes USB |
| `LIBMTP_Get_Manufacturername` | `char* (LIBMTP_mtpdevice_t*)` | Caller frees with `free()` |
| `LIBMTP_Get_Modelname` | `char* (LIBMTP_mtpdevice_t*)` | Caller frees with `free()` |
| `LIBMTP_Get_Serialnumber` | `char* (LIBMTP_mtpdevice_t*)` | Caller frees with `free()` |
| `LIBMTP_Get_Friendlyname` | `char* (LIBMTP_mtpdevice_t*)` | Caller frees with `free()` |
| `LIBMTP_Get_Deviceversion` | `char* (LIBMTP_mtpdevice_t*)` | Caller frees with `free()` |
| `LIBMTP_Get_Batterylevel` | `int (LIBMTP_mtpdevice_t*, uint8_t*, uint8_t*)` | current, max |
| `LIBMTP_Check_Capability` | `int (LIBMTP_mtpdevice_t*, LIBMTP_devicecap_t)` | Non-zero = supported |
| `LIBMTP_Dump_Device_Info` | `void (LIBMTP_mtpdevice_t*)` | Prints to stdout |

#### Storage

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Get_Storage` | `int (LIBMTP_mtpdevice_t*, int)` | `sortby` param; populates `device->storage` linked list. Pass `LIBMTP_STORAGE_SORTBY_NOTSORTED` (0). Returns 0 on success. |

#### Error Stack

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Get_Errorstack` | `LIBMTP_error_t* (LIBMTP_mtpdevice_t*)` | Walk `.next` linked list |
| `LIBMTP_Clear_Errorstack` | `void (LIBMTP_mtpdevice_t*)` | **Must call after reading errors** |
| `LIBMTP_Dump_Errorstack` | `void (LIBMTP_mtpdevice_t*)` | Prints to stderr |

#### File Operations

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Get_Files_And_Folders` | `LIBMTP_file_t* (device, uint32_t storage_id, uint32_t parent_id)` | Returns linked list. `storage_id=0` means all storages. `parent_id=0` means root. **Primary listing function for uncached mode.** |
| `LIBMTP_Get_Filemetadata` | `LIBMTP_file_t* (device, uint32_t id)` | Single object metadata |
| `LIBMTP_Get_File_To_File` | `int (device, uint32_t id, const char* path, progressfunc, data)` | Download to local path. Returns 0 on success. |
| `LIBMTP_Get_File_To_File_Descriptor` | `int (device, uint32_t id, int fd, progressfunc, data)` | Download to file descriptor |
| `LIBMTP_Send_File_From_File` | `int (device, const char* path, LIBMTP_file_t* metadata, progressfunc, data)` | Upload. Populate metadata->filename, filesize, parent_id, storage_id, filetype before call. Returns 0 on success. **Populates metadata->item_id with the new ID.** |
| `LIBMTP_Send_File_From_File_Descriptor` | `int (device, int fd, LIBMTP_file_t* metadata, progressfunc, data)` | Upload from fd |
| `LIBMTP_Set_File_Name` | `int (device, LIBMTP_file_t*, const char*)` | Rename file via SetObjectPropValue |
| `LIBMTP_new_file_t` | `LIBMTP_file_t* (void)` | Allocate zeroed file struct |
| `LIBMTP_destroy_file_t` | `void (LIBMTP_file_t*)` | Free file struct (and filename) |

#### Folder Operations

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Get_Folder_List` | `LIBMTP_folder_t* (device)` | Returns **tree** (child/sibling pointers), not a flat list |
| `LIBMTP_Get_Folder_List_For_Storage` | `LIBMTP_folder_t* (device, uint32_t storage_id)` | Tree for one storage |
| `LIBMTP_Find_Folder` | `LIBMTP_folder_t* (LIBMTP_folder_t* tree, uint32_t id)` | Search tree by ID |
| `LIBMTP_Create_Folder` | `uint32_t (device, char* name, uint32_t parent_id, uint32_t storage_id)` | Returns new folder ID, or 0 on error. **WARNING: Takes ownership of `name` — do NOT free it.** |
| `LIBMTP_Set_Folder_Name` | `int (device, LIBMTP_folder_t*, const char*)` | Rename folder |
| `LIBMTP_destroy_folder_t` | `void (LIBMTP_folder_t*)` | Free entire tree |

#### Object Management

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_Delete_Object` | `int (device, uint32_t id)` | Deletes any object type. Recursive for folders. |
| `LIBMTP_Move_Object` | `int (device, uint32_t id, uint32_t storage_id, uint32_t new_parent_id)` | Many devices don't support this — check `LIBMTP_DEVICECAP_MoveObject` |
| `LIBMTP_Copy_Object` | `int (device, uint32_t id, uint32_t storage_id, uint32_t new_parent_id)` | Often unsupported |
| `LIBMTP_Set_Object_Filename` | `int (device, uint32_t id, char* filename)` | Alternative rename |

#### Partial I/O (stretch goal)

| Function | Signature | Notes |
|---|---|---|
| `LIBMTP_GetPartialObject` | `int (device, uint32_t id, uint64_t offset, uint32_t maxbytes, unsigned char**, unsigned int*)` | Check `LIBMTP_DEVICECAP_GetPartialObject` first |
| `LIBMTP_SendPartialObject` | `int (device, uint32_t id, uint64_t offset, unsigned char*, unsigned int)` | Check `LIBMTP_DEVICECAP_SendPartialObject` first |
| `LIBMTP_BeginEditObject` | `int (device, uint32_t id)` | Required before partial send |
| `LIBMTP_EndEditObject` | `int (device, uint32_t id)` | Required after partial send |
| `LIBMTP_TruncateObject` | `int (device, uint32_t id, uint64_t offset)` | Truncate at offset |

#### Track Operations (stretch goal)

```c
LIBMTP_track_t *LIBMTP_Get_Tracklisting(LIBMTP_mtpdevice_t*);
LIBMTP_track_t *LIBMTP_Get_Trackmetadata(LIBMTP_mtpdevice_t*, uint32_t);
int LIBMTP_Send_Track_From_File(LIBMTP_mtpdevice_t*, const char*, LIBMTP_track_t*, progressfunc, data);
int LIBMTP_Update_Track_Metadata(LIBMTP_mtpdevice_t*, LIBMTP_track_t*);
```

#### Album Operations (stretch goal)

```c
LIBMTP_album_t *LIBMTP_Get_Album_List(LIBMTP_mtpdevice_t*);
int LIBMTP_Create_New_Album(LIBMTP_mtpdevice_t*, LIBMTP_album_t*);
int LIBMTP_Update_Album(LIBMTP_mtpdevice_t*, LIBMTP_album_t*);
```

#### Playlist Operations (stretch goal)

```c
LIBMTP_playlist_t *LIBMTP_Get_Playlist_List(LIBMTP_mtpdevice_t*);
int LIBMTP_Create_New_Playlist(LIBMTP_mtpdevice_t*, LIBMTP_playlist_t*);
int LIBMTP_Update_Playlist(LIBMTP_mtpdevice_t*, LIBMTP_playlist_t*);
```

#### Event Operations (stretch goal)

```c
int LIBMTP_Read_Event(LIBMTP_mtpdevice_t*, LIBMTP_event_t*, uint32_t*);
int LIBMTP_Read_Event_Async(LIBMTP_mtpdevice_t*, LIBMTP_event_cb_fn, void*);
typedef void (*LIBMTP_event_cb_fn)(int, LIBMTP_event_t, uint32_t, void*);
```

---

## 2. mtp-module.c Reference Implementation

The Emacs dynamic module (`mtp.el/lisp/mtp-module.c`) wraps libmtp into 19 Elisp functions. This is the proven reference for which C functions to call and in what order.

### 2.1 Module Function Catalog

| Elisp function | Args | C functions called | Returns | Notes |
|---|---|---|---|---|
| `mtp-module-init` | 0 | `LIBMTP_Init()` | `t` | One-time init |
| `mtp-module-version` | 0 | — | `LIBMTP_VERSION_STRING` | Compile-time constant |
| `mtp-module-backend-info` | 0 | — | plist `(:libmtp-version V :module-api-version 1)` | Diagnostic |
| `mtp-module-detect` | 0 | `LIBMTP_Detect_Raw_Devices`, `LIBMTP_Open_Raw_Device_Uncached`, `LIBMTP_Get_Manufacturername/Modelname/Serialnumber`, `LIBMTP_Get_Storage`, `LIBMTP_Release_Device` | list of device plists | Opens each device temporarily to read metadata, then closes |
| `mtp-module-open` | 2 (bus, devnum) | `LIBMTP_Detect_Raw_Devices`, `LIBMTP_Open_Raw_Device_Uncached` | user-ptr handle | Finds device by bus+devnum, opens uncached |
| `mtp-module-close` | 1 (handle) | `LIBMTP_Release_Device` | `t` | Idempotent via `is_null` flag |
| `mtp-module-handle-alive-p` | 1 (handle) | — | `t`/`nil` | Checks `is_null` flag |
| `mtp-module-storage-info` | 1 (handle) | — | list of storage plists `(:id :description :capacity :free-space)` | Reads `device->storage` linked list directly |
| `mtp-module-debug-level` | 1 (level) | `LIBMTP_Set_Debug` | `t` | |
| `mtp-module-list-dir` | 3 (handle, storage_id, parent_id) | `LIBMTP_Get_Files_And_Folders`, `LIBMTP_Get_Folder_List`, `LIBMTP_destroy_folder_t`, `LIBMTP_destroy_file_t` | list of object plists | **Complex dedup logic** — see §2.2 |
| `mtp-module-get-metadata` | 2 (handle, object_id) | `LIBMTP_Get_Filemetadata`, `LIBMTP_destroy_file_t` | object plist | |
| `mtp-module-resolve-path` | 3 (handle, storage_id, path) | `LIBMTP_Get_Files_And_Folders` (called per path component) | object plist or `nil` | Walks path component-by-component |
| `mtp-module-get-file` | 3 (handle, object_id, local_path) | `LIBMTP_Get_File_To_File` | local_path string | Progress callback passed as NULL |
| `mtp-module-send-file` | 5 (handle, local_path, parent_id, storage_id, filename) | `stat()`, `LIBMTP_new_file_t`, `LIBMTP_Send_File_From_File`, `LIBMTP_destroy_file_t` | new object ID | Sets filetype to `LIBMTP_FILETYPE_UNKNOWN` |
| `mtp-module-delete` | 2 (handle, object_id) | `LIBMTP_Delete_Object` | `t` | |
| `mtp-module-mkdir` | 4 (handle, name, parent_id, storage_id) | `LIBMTP_Create_Folder` | new folder ID | **Must `strdup` name** because `Create_Folder` takes ownership |
| `mtp-module-move` | 4 (handle, object_id, storage_id, new_parent_id) | `LIBMTP_Move_Object` | `t` | Signals file-error with "MoveObject" in message on failure |
| `mtp-module-rename` | 4 (handle, object_id, new_name, is_dir) | `LIBMTP_Get_Folder_List`/`LIBMTP_Get_Filemetadata`, `LIBMTP_Set_Folder_Name`/`LIBMTP_Set_File_Name` | `t` | Branches on is_dir |
| `mtp-module-folder-ids` | 1 (handle) | `LIBMTP_Get_Folder_List`, `LIBMTP_destroy_folder_t` | list of integer IDs | Walks entire folder tree |

### 2.2 Directory Listing Dedup Logic (critical)

`mtp-module-list-dir` must handle the fact that `LIBMTP_Get_Files_And_Folders` returns folders as file entries with `LIBMTP_FILETYPE_FOLDER`, while `LIBMTP_Get_Folder_List` returns the same folders in a tree structure with richer data. The dedup algorithm:

1. Call `LIBMTP_Get_Folder_List()` → get full folder tree
2. Collect all folder IDs from the tree into a set (`fids`)
3. Walk the tree to find folders with `parent_id == target_parent` → emit as folder plists (tracking their IDs in `synth_ids`)
4. Call `LIBMTP_Get_Files_And_Folders(device, storage_id, parent_id)` → get file linked list
5. For each file entry:
   - Skip if `parent_id != target_parent` (shouldn't happen but defensive)
   - Skip if `item_id` is in `synth_ids` (already emitted as folder from tree)
   - If `item_id` is in `fids` but wasn't already emitted, override its `filetype` to `FOLDER` (it's a folder the tree knows about but that wasn't a direct child match)
   - Emit as file/folder plist

This ensures each directory entry appears exactly once with correct type information.

### 2.3 Object Plist Schema

Every file/folder is represented as a plist with these keys:

```
(:id UINT32 :name STRING :size UINT64 :type {dir|file}
 :parent-id UINT32 :storage-id UINT32 :mtime UNIX-TIME)
```

Folders synthesized from the folder tree have `:size 0` and `:mtime 0`.

---

## 3. mtp-backend.el Patterns

The Elisp dispatch layer shows important architectural patterns.

### 3.1 Dual Backend Dispatch

`mtp-backend-type` is `'module` or `'cli`, auto-detected at load time. Every public function dispatches:

```elisp
(pcase mtp-backend-type
  ('module (mtp-module-FUNCTION ...))
  ('cli    (mtp-backend-FUNCTION-cli ...)))
```

SwiftMTP replaces both paths with a single Swift implementation.

### 3.2 Device Handle Lifecycle

Module mode stores a device handle (C `user-ptr`) in Tramp connection properties:

```elisp
(tramp-get-connection-property vec "mtp-device-handle" nil)
```

Pattern: `open` at first access, `close` on disconnect. The C finalizer also releases on GC.

### 3.3 Rename Strategy (three-tier)

`mtp-backend--rename-file-module` tries:
1. `LIBMTP_Move_Object` (fast, atomic, but often unsupported)
2. `LIBMTP_Set_File_Name` / `LIBMTP_Set_Folder_Name` (same-directory rename only)
3. Copy + delete fallback (download to temp, re-upload with new name, delete original)

The error message "MoveObject" in the file-error signal is used to detect MoveObject failure and cascade.

### 3.4 Storage ID Convention

All read operations pass `storage_id=0` meaning "all storages." Write operations use the `storage_id` from the parent object's metadata. This flattens the multi-storage namespace.

### 3.5 Path Resolution

`mtp-module-resolve-path` walks component-by-component:
1. Split path on `/`
2. For each component, call `LIBMTP_Get_Files_And_Folders(device, storage_id, current_parent)`
3. Linear scan the returned list for `filename == component`
4. If found and more components remain: `current_parent = match.item_id`, continue
5. If found and last component: return match as plist
6. If not found: return `nil`

---

## 4. Swift C Interop Patterns

### 4.1 System Library Module Map

Create a `Clibmtp` target that wraps the system library. The modulemap tells Swift how to import it:

**`Sources/Clibmtp/include/module.modulemap`:**
```
module Clibmtp [system] {
    header "shim.h"
    link "mtp"
    export *
}
```

**`Sources/Clibmtp/include/shim.h`:**
```c
#pragma once
#include <libmtp.h>
```

The `shim.h` exists because modulemaps need to reference headers relative to the include directory. The actual `libmtp.h` is found via pkg-config header search paths.

### 4.2 Package.swift with pkg-config

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

Key: `.systemLibrary` with `pkgConfig: "libmtp"` makes SPM run `pkg-config --cflags --libs libmtp` automatically.

### 4.3 Opaque Pointer Wrapping

`LIBMTP_mtpdevice_t*` becomes an opaque pointer in Swift: `OpaquePointer` or typed as `UnsafeMutablePointer<LIBMTP_mtpdevice_struct>`. Wrap in a class with `deinit`:

```swift
public final class MTPDevice: ~Copyable {
    let rawDevice: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>

    init(rawDevice: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>) {
        self.rawDevice = rawDevice
    }

    deinit {
        LIBMTP_Release_Device(rawDevice)
    }
}
```

Using `~Copyable` prevents accidental copies that would cause double-free.

### 4.4 Linked List Traversal

libmtp uses C linked lists everywhere. Swift pattern for consuming them:

```swift
// LIBMTP_file_t linked list (singly linked via .next)
var entries: [MTPFileInfo] = []
var current = LIBMTP_Get_Files_And_Folders(device, storageId, parentId)
while let file = current {
    entries.append(MTPFileInfo(cFile: file))
    let next = file.pointee.next
    LIBMTP_destroy_file_t(file)
    current = next
}
```

For the folder tree (child/sibling), use recursive traversal:

```swift
func collectFolders(_ folder: UnsafeMutablePointer<LIBMTP_folder_struct>?) -> [MTPFileInfo] {
    guard let folder else { return [] }
    var result = [MTPFileInfo(cFolder: folder)]
    result += collectFolders(folder.pointee.child)
    result += collectFolders(folder.pointee.sibling)
    return result
}
```

### 4.5 Callback Bridging

The progress callback `LIBMTP_progressfunc_t` is a C function pointer. Swift closures can't be passed directly. Use a context struct:

```swift
typealias ProgressHandler = (UInt64, UInt64) -> Bool  // sent, total -> continue?

func withProgressCallback<R>(
    _ handler: ProgressHandler?,
    body: (LIBMTP_progressfunc_t?, UnsafeMutableRawPointer?) -> R
) -> R {
    guard let handler else {
        return body(nil, nil)
    }
    var context = handler
    return withUnsafeMutablePointer(to: &context) { contextPtr in
        let callback: LIBMTP_progressfunc_t = { sent, total, data in
            let handler = data!.assumingMemoryBound(to: ProgressHandler.self).pointee
            return handler(sent, total) ? 0 : 1  // 0 = continue, non-zero = cancel
        }
        return body(callback, UnsafeMutableRawPointer(contextPtr))
    }
}
```

### 4.6 String Ownership

C strings from libmtp fall into two categories:

1. **Caller-frees**: `LIBMTP_Get_Manufacturername()`, `LIBMTP_Get_Modelname()`, etc. return `char*` that the caller must `free()`. In Swift: `String(cString: ptr!)` then `free(ptr)`, or use `String(bytesNoCopy:length:encoding:freeWhenDone:)`.

2. **Library-owned**: Fields in structs like `file->filename` are owned by the struct. Copy before the struct is freed: `String(cString: file.pointee.filename)`.

3. **Caller-gives-ownership**: `LIBMTP_Create_Folder(device, name, ...)` takes ownership of `name`. Must pass a `strdup`'d string. In Swift:

```swift
let cName = strdup(name)  // Swift String auto-bridges for C calls
let folderId = LIBMTP_Create_Folder(device, cName, parentId, storageId)
// Do NOT free cName — libmtp owns it now
// If Create_Folder fails (returns 0), the name may or may not have been freed
// — treat it as consumed regardless
```

### 4.7 Memory Ownership Summary

| Function | Input ownership | Output ownership |
|---|---|---|
| `LIBMTP_Detect_Raw_Devices` | — | Caller frees array with `free()` |
| `LIBMTP_Get_Manufacturername` | — | Caller frees with `free()` |
| `LIBMTP_Get_Files_And_Folders` | — | Caller frees each node with `LIBMTP_destroy_file_t` |
| `LIBMTP_Get_Folder_List` | — | Caller frees tree with `LIBMTP_destroy_folder_t` |
| `LIBMTP_Get_Filemetadata` | — | Caller frees with `LIBMTP_destroy_file_t` |
| `LIBMTP_new_file_t` | — | Caller frees with `LIBMTP_destroy_file_t` |
| `LIBMTP_Create_Folder` | Takes ownership of `name` | — |
| `LIBMTP_Send_File_From_File` | Reads metadata but doesn't free | Populates `metadata->item_id` |
| `LIBMTP_Release_Device` | Frees device and all internal state | — |

---

## 5. Key Technical Gotchas

### 5.1 `LIBMTP_Create_Folder` Takes Ownership of Name

The `name` parameter is stored directly in libmtp's internal structures. Do NOT free it after calling. Always pass a freshly allocated copy (`strdup` in C, managed carefully in Swift). The mtp-module.c explicitly does `strdup(name)` before passing to `LIBMTP_Create_Folder`.

### 5.2 Folder Tree Dedup in Directory Listing

`LIBMTP_Get_Files_And_Folders` can return folder entries as files with `LIBMTP_FILETYPE_FOLDER`. `LIBMTP_Get_Folder_List` returns the authoritative folder tree. When listing a directory, you must merge these two sources and deduplicate. The mtp-module.c implementation (§2.2) is the proven algorithm. Without dedup, folders appear twice.

### 5.3 Error Stack Must Be Drained

After any failed libmtp operation, the error stack accumulates. Call `LIBMTP_Get_Errorstack()` to read errors, then `LIBMTP_Clear_Errorstack()` to reset. If you don't clear, errors from previous operations leak into subsequent error reports.

### 5.4 Uncached Mode Is Required

`LIBMTP_Open_Raw_Device_Uncached` must be used instead of `LIBMTP_Open_Raw_Device`. Cached mode fetches the entire object tree at device open, which is extremely slow on devices with many files and also means `LIBMTP_Get_Files_And_Folders` doesn't work (it's uncached-mode-only).

### 5.5 storage_id=0 Convention

Passing `storage_id=0` to `LIBMTP_Get_Files_And_Folders` means "all storages." This is the standard approach for read operations. For write operations, use the specific `storage_id` from the target parent object.

### 5.6 MoveObject Often Unsupported

Many Android MTP implementations (and Supernote) don't support `MoveObject`. Check `LIBMTP_Check_Capability(device, LIBMTP_DEVICECAP_MoveObject)` before attempting. The rename strategy should cascade: MoveObject → SetObjectPropValue (same-dir only) → copy+delete.

### 5.7 File Size Must Be Known Before Upload

`LIBMTP_Send_File_From_File` requires `metadata->filesize` to be set before the call. The MTP protocol declares the size in the initial handshake. This means you must `stat()` the local file first.

### 5.8 Object Handles Are Ephemeral

Object IDs (item_id, folder_id) are only valid for the current session. They change after reconnection. Never persist them.

### 5.9 `LIBMTP_Get_Storage` Must Be Called Before Reading Storage

The `device->storage` linked list is only populated after calling `LIBMTP_Get_Storage(device, 0)`. Returns 0 on success. The mtp-module.c `detect` function calls this before reading storage info.

### 5.10 Folder Tree Is Child/Sibling, Not Flat

`LIBMTP_Get_Folder_List` returns a tree where each node has `child` (first child) and `sibling` (next at same level) pointers. To find all children of a given parent, you must recursively walk the tree checking `parent_id`, not just iterate a flat list.

### 5.11 `LIBMTP_Set_Folder_Name` Requires a Folder Struct

Unlike `LIBMTP_Set_File_Name` which takes a `LIBMTP_file_t*`, `LIBMTP_Set_Folder_Name` takes a `LIBMTP_folder_t*`. You must fetch the folder tree, find the target folder node, then pass that node. The mtp-module.c rename function shows this pattern.

### 5.12 Send File Populates item_id

After `LIBMTP_Send_File_From_File` succeeds, `metadata->item_id` contains the newly assigned object ID. This is how you get the ID of an uploaded file.
