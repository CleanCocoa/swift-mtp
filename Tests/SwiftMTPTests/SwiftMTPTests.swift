import Testing
import SwiftMTP
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
