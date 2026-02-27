import Clibmtp

public typealias ProgressHandler = (UInt64, UInt64) -> Bool

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
			return handler(sent, total) ? 0 : 1
		}
		return body(callback, UnsafeMutableRawPointer(contextPtr))
	}
}
