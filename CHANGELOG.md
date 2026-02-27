# Changelog

## [0.3.0] — 2026-02-27

### Added
- `FileInfo.SortOrder` enum with `.byName`, `.bySize`, `.byDate` (ascending/descending) and `.directoriesFirst`
- `Sequence<FileInfo>.sorted(_:)` extension for ergonomic sorting (`entries.sorted(.byName)`)
- `BusLocation`, `VendorID`, `ProductID` nominal wrapper types for USB identifiers
- `StorageInfo.usedSpace` and `StorageInfo.percentFull` computed properties
- `Path` nominal type for type-safe path resolution
- Storage facade: `download`, `info`, `delete`, `rename` on `Storage`
- `upload()`, `makeDirectory()`, and `rename()` now return `FileInfo`

### Changed
- Dropped `MTP` prefix from all types — module provides namespacing (e.g. `MTPDevice` → `Device`)
- Split `CTypes.swift` into one file per `~Copyable` wrapper
- Split `MTPTypes.swift` into one file per type declaration
- `RawDevice`, `Device`, and `MTPError` use nominal USB ID types throughout
- Internal C bridge layer uses nominal ID types consistently

## [0.2.0] — 2026-02-26

### Added
- `Event` enum and `readEvent()` for device event listening
- `deviceDisconnected` case on `MTPError`
- `Storage` handle for device-bound storage operations
- `StorageInfo` convenience overloads for storage parameter
- `defaultStorage` convenience property
- `ObjectID`, `StorageID`, `Folder` nominal types
- `RawDevice.open()` to avoid TOCTOU rescan
- `~Copyable` wrapper types (`Upload`, `FileHandle`, `FileNode`, `FolderTree`) for C resource management

### Changed
- Methods follow Swift API Design Guidelines naming
- `ObjectID`/`StorageID` used in all method signatures
- Swift 6.2 tools-version with macOS 26 platform

### Fixed
- Drain error stack between rename attempts

## [0.1.0] — 2026-02-25

### Added
- Initial release
- `Device` class with storage info, directory listing, file operations
- Download, upload, rename, delete, move, make directory
- `resolvePath` for path-based file lookup
- Progress callbacks for transfers
- Hardware-gated test suite
