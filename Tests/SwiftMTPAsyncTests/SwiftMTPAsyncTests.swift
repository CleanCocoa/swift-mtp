import Foundation
import SwiftMTPAsync
import Testing

private let deviceConnected = ProcessInfo.processInfo.environment["MTP_DEVICE_CONNECTED"] == "1"

@Suite(.serialized, .enabled(if: deviceConnected, "Skipping: no MTP device connected"))
struct HardwareTests {
	static let shared: MTPSession = {
		try? MTP.initialize()
		var devices = try! MTPSession.detect()
		return try! MTPSession(opening: &devices[0])
	}()

	@Test func `detect devices finds at least one`() throws {
		try? MTP.initialize()
		let devices = try MTPSession.detect()
		#expect(!devices.isEmpty)
	}

	@Test func `open device and read properties`() async throws {
		let session = HardwareTests.shared
		#expect(
			session.manufacturerName != nil || session.modelName != nil
				|| session.serialNumber != nil
				|| session.friendlyName != nil || session.deviceVersion != nil
		)
		let storages = await session.storageInfo()
		#expect(!storages.isEmpty)
		let defaultStorage = await session.defaultStorage
		#expect(defaultStorage?.id == storages.first?.id)
	}

	@Test func `list root directory`() async throws {
		let session = HardwareTests.shared
		let entries = try await session.contents()
		#expect(!entries.isEmpty)
		for entry in entries {
			#expect(!entry.name.isEmpty)
		}
	}

	@Test func `eventStream retains owner for stream lifetime`() async throws {
		let session = HardwareTests.shared

		final class Witness {}
		weak var weakWitness: Witness?
		var stream: AsyncStream<Event>?

		do {
			let witness = Witness()
			weakWitness = witness
			stream = session.testEventStream(owner: witness)
		}

		#expect(weakWitness != nil, "eventStream should retain its owner")

		let s = stream!
		stream = nil
		let task = Task.detached { for await _ in s {} }
		task.cancel()
		await task.value
	}

	@Test func `events() stream can be cancelled`() async throws {
		let session = HardwareTests.shared

		let eventTask = Task.detached {
			var count = 0
			for await _ in session.events() {
				count += 1
			}
			return count
		}

		try await Task.sleep(for: .seconds(2))
		eventTask.cancel()
		let _ = await eventTask.value
	}
}
