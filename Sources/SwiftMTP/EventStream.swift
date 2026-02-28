import Clibmtp
import Foundation
import Synchronization

final class EventCallbackContext {
	var ret: Int32 = -1
	var event: LIBMTP_event_t = LIBMTP_EVENT_NONE
	var param: UInt32 = 0
}

private final class CancellationFlag: Sendable {
	private let _value = Mutex(false)
	var isCancelled: Bool { _value.withLock { $0 } }
	func cancel() { _value.withLock { $0 = true } }
}

func eventStream(device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>, owner: AnyObject? = nil) -> AsyncStream<Event> {
	AsyncStream { continuation in
		let cancelled = CancellationFlag()
		continuation.onTermination = { _ in cancelled.cancel() }

		nonisolated(unsafe) let devicePtr = device
		nonisolated(unsafe) let retainedOwner = owner
		let thread = Thread {
			withExtendedLifetime(retainedOwner) {
				eventPollLoop(device: devicePtr, continuation: continuation, cancelled: cancelled)
			}
		}
		thread.name = "SwiftMTP.EventPoll"
		thread.qualityOfService = .utility
		thread.start()
	}
}

/// ## C contracts
/// - `LIBMTP_Read_Event_Async` registers a one-shot callback. After the callback fires,
///   it must be re-registered for the next event.
/// - `LIBMTP_Handle_Events_Timeout_Completed` drives USB event processing. The registered
///   callback fires **synchronously** on this thread during the poll call.
/// - The internal `event_cb_data_t` is freed by libmtp after the callback fires, but the
///   user_data (`void*`) is our responsibility — managed via `Unmanaged` retain/release.
/// - On cancellation, a pending `Read_Event_Async` callback may still be registered. The
///   `Unmanaged.passRetained` keeps the context alive until the callback eventually fires
///   (during device release), at which point `takeRetainedValue` releases it.
private func eventPollLoop(
	device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>,
	continuation: AsyncStream<Event>.Continuation,
	cancelled: CancellationFlag
) {
	while !cancelled.isCancelled {
		let context = EventCallbackContext()
		let contextPtr = Unmanaged.passRetained(context).toOpaque()

		let callback: LIBMTP_event_cb_fn = { ret, event, param, userData in
			let ctx = Unmanaged<EventCallbackContext>.fromOpaque(userData!).takeRetainedValue()
			ctx.ret = ret
			ctx.event = event
			ctx.param = param
		}

		guard LIBMTP_Read_Event_Async(device, callback, contextPtr) == 0 else {
			Unmanaged<EventCallbackContext>.fromOpaque(contextPtr).release()
			break
		}

		while !cancelled.isCancelled && context.ret == -1 {
			var tv = timeval(tv_sec: 0, tv_usec: 500_000)
			var completed: Int32 = 0
			LIBMTP_Handle_Events_Timeout_Completed(&tv, &completed)
		}

		if cancelled.isCancelled {
			break
		}

		if context.ret != 0 {
			break
		}

		if let event = Event(cEvent: context.event, param: context.param) {
			continuation.yield(event)
		}
	}
	continuation.finish()
}
