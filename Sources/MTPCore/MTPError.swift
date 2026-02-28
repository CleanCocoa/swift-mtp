@preconcurrency import Clibmtp

public enum MTPError: Error, Equatable, Sendable {
	case alreadyInitialized
	case notInitialized
	case noDeviceAttached
	case connectionFailed(bus: BusLocation, devnum: DeviceNumber)
	case storageFull
	case objectNotFound(id: ObjectID)
	case operationFailed(String)
	case pathNotFound(String)
	case notFileURL(String)
	case moveNotSupported
	case cancelled
	case deviceDisconnected
}

/// Reads all accumulated errors from the device's per-device error stack, then clears it.
///
/// ## C contract
/// The error stack is append-only until drained. `LIBMTP_Get_Errorstack` returns a pointer into
/// the device's internal linked list — nodes must not be freed individually. Strings are copied
/// before `LIBMTP_Clear_Errorstack` frees all nodes. Must be called after each fallible
/// operation to prevent stale errors leaking into later diagnostics.
func drainErrorStack(_ device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>) -> String {
	var messages: [String] = []
	var node = LIBMTP_Get_Errorstack(device)
	while let n = node {
		if let text = n.pointee.error_text {
			messages.append(String(cString: text))
		}
		node = n.pointee.next
	}
	LIBMTP_Clear_Errorstack(device)
	return messages.isEmpty ? "unknown error" : messages.joined(separator: "; ")
}
