import Clibmtp

public enum MTPError: Error, Equatable, Sendable {
	case noDeviceAttached
	case connectionFailed(bus: BusLocation, devnum: UInt8)
	case storageFull
	case objectNotFound(id: ObjectID)
	case operationFailed(String)
	case pathNotFound(String)
	case moveNotSupported
	case cancelled
	case deviceDisconnected
}

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
