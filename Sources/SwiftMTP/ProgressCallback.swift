import Clibmtp

public typealias ProgressHandler = (_ sent: UInt64, _ total: UInt64) -> Bool

/// Scoped bridge that lets callers pass an optional Swift progress closure to libmtp's C transfer functions.
///
/// Pass `nil` to disable progress reporting. Pass a closure returning `true` to continue or `false` to cancel.
/// The C callback and context pointer are only valid for the duration of `body`. Do not extent their lifetime by lettings them escape the scope.
func withProgressCallback<Value>(
	_ handler: ProgressHandler?,
	body: (_ callback: LIBMTP_progressfunc_t?, _ context: UnsafeMutableRawPointer?) -> Value
) -> Value {
	guard let handler else { return body(nil, nil) }
	var context = handler
	return withUnsafeMutablePointer(to: &context) { contextPtr in
		let callback: LIBMTP_progressfunc_t = { sent, total, data in
			let handler = data!.assumingMemoryBound(to: ProgressHandler.self).pointee
			return handler(sent, total) ? 0 : 1
		}
		return body(callback, UnsafeMutableRawPointer(contextPtr))
	}
}
