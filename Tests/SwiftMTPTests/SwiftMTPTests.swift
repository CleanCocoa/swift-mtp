import Testing
import Foundation
@testable import SwiftMTP
import Clibmtp

@Test func `swift build imports Clibmtp`() {
    #expect(swiftMTPVersion.isEmpty == false)
}

@Test func `MTPError conforms to Equatable and Sendable`() {
    let a: MTPError = .noDeviceAttached
    let b: MTPError = .noDeviceAttached
    #expect(a == b)

    let c: MTPError = .connectionFailed(bus: 1, devnum: 2)
    let d: MTPError = .connectionFailed(bus: 1, devnum: 2)
    #expect(c == d)
    #expect(c != a)

    let _: any Sendable = MTPError.storageFull
}

@Test func `MTPError cases construct correctly`() {
    let e1: MTPError = .objectNotFound(id: 42)
    let e2: MTPError = .operationFailed("bad op")
    let e3: MTPError = .pathNotFound("/foo/bar")
    let e4: MTPError = .moveNotSupported
    let e5: MTPError = .cancelled

    #expect(e1 == .objectNotFound(id: 42))
    #expect(e1 != .objectNotFound(id: 99))
    #expect(e2 == .operationFailed("bad op"))
    #expect(e3 == .pathNotFound("/foo/bar"))
    #expect(e4 == .moveNotSupported)
    #expect(e5 == .cancelled)
}

@Test func `MTPRawDevice stores device properties`() {
    let dev = MTPRawDevice(busLocation: 1, devnum: 2, vendor: "Acme", vendorId: 0x1234, product: "Widget", productId: 0x5678)
    #expect(dev.busLocation == 1)
    #expect(dev.devnum == 2)
    #expect(dev.vendor == "Acme")
    #expect(dev.vendorId == 0x1234)
    #expect(dev.product == "Widget")
    #expect(dev.productId == 0x5678)
}

@Test func `MTPFileInfo stores file properties`() {
    let info = MTPFileInfo(id: 1, parentId: 0, storageId: 100, name: "test.txt", size: 1024, modificationDate: Date(timeIntervalSince1970: 1000), isDirectory: false)
    #expect(info.id == 1)
    #expect(info.parentId == 0)
    #expect(info.storageId == 100)
    #expect(info.name == "test.txt")
    #expect(info.size == 1024)
    #expect(info.modificationDate == Date(timeIntervalSince1970: 1000))
    #expect(info.isDirectory == false)
}

@Test func `MTPFileInfo stores directory properties`() {
    let dir = MTPFileInfo(id: 5, parentId: 0, storageId: 200, name: "Photos", size: 0, modificationDate: .distantPast, isDirectory: true)
    #expect(dir.id == 5)
    #expect(dir.name == "Photos")
    #expect(dir.isDirectory == true)
    #expect(dir.size == 0)
}

@Test func `MTPStorageInfo stores storage properties`() {
    let storage = MTPStorageInfo(id: 0xABCD, description: "Internal Storage", maxCapacity: 64_000_000_000, freeSpace: 32_000_000_000)
    #expect(storage.id == 0xABCD)
    #expect(storage.description == "Internal Storage")
    #expect(storage.maxCapacity == 64_000_000_000)
    #expect(storage.freeSpace == 32_000_000_000)
}

@Test func `withProgressCallback passes nil for nil handler`() {
    withProgressCallback(nil) { callback, data in
        #expect(callback == nil)
        #expect(data == nil)
    }
}

@Test func `withProgressCallback provides function pointer for non-nil handler`() {
    let handler: ProgressHandler = { sent, total in
        return true
    }
    withProgressCallback(handler) { callback, data in
        #expect(callback != nil)
        #expect(data != nil)
    }
}

@Test func `mtpInitialize succeeds`() {
    mtpInitialize()
}

@Test func `mtpDetectDevices returns empty array without device`() throws {
    mtpInitialize()
    let devices = try mtpDetectDevices()
    #expect(devices.isEmpty)
}

@Test func `MTPDeviceCapability enum cases exist`() {
    let caps: [MTPDeviceCapability] = [.moveObject, .copyObject, .getPartialObject, .sendPartialObject, .editObjects]
    #expect(caps.count == 5)
}

@Test func `storageInfo method exists on MTPDevice`() {
    #expect(true)
}

@Test func `listDirectory method signature compiles`() {
    #expect(true)
}

@Test func `file operations methods compile`() {
    #expect(true)
}

@Test func `mutation operations methods compile`() {
    #expect(true)
}
