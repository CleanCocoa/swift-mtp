@preconcurrency import Clibmtp

public typealias ProgressHandler = @Sendable (_ sent: UInt64, _ total: UInt64) -> ProgressAction

/// Scoped bridge that lets callers pass an optional Swift progress closure to libmtp's C transfer functions.
///
/// Pass `nil` to disable progress reporting. Pass a closure returning `.continue` to keep transferring or `.cancel` to abort.
///
/// ## C contract
/// libmtp invokes the progress callback **synchronously** on the calling thread during transfer.
/// The callback pointer is never stored or invoked after the C function returns. This is what
/// makes passing a pointer to a stack-local closure safe. The callback and context pointer are
/// only valid for the duration of `body` — do not let them escape.
package func withProgressCallback<Value>(
	_ handler: ProgressHandler?,
	body: (_ callback: LIBMTP_progressfunc_t?, _ context: UnsafeMutableRawPointer?) -> Value
) -> Value {
	guard let handler else { return body(nil, nil) }
	var context = handler
	return withUnsafeMutablePointer(to: &context) { contextPtr in
		let callback: LIBMTP_progressfunc_t = { sent, total, data in
			let handler = data!.assumingMemoryBound(to: ProgressHandler.self).pointee
			return handler(sent, total) == .continue ? 0 : 1
		}
		return body(callback, UnsafeMutableRawPointer(contextPtr))
	}
}
