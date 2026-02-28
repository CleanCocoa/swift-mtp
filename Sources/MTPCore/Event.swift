@preconcurrency import Clibmtp

public enum Event: Sendable, Equatable {
	case storeAdded(StorageID)
	case storeRemoved(StorageID)
	case objectAdded(ObjectID)
	case objectRemoved(ObjectID)
	case devicePropertyChanged

	package init?(cEvent: LIBMTP_event_t, param: UInt32) {
		switch cEvent {
		case LIBMTP_EVENT_STORE_ADDED: self = .storeAdded(StorageID(rawValue: param))
		case LIBMTP_EVENT_STORE_REMOVED: self = .storeRemoved(StorageID(rawValue: param))
		case LIBMTP_EVENT_OBJECT_ADDED: self = .objectAdded(ObjectID(rawValue: param))
		case LIBMTP_EVENT_OBJECT_REMOVED: self = .objectRemoved(ObjectID(rawValue: param))
		case LIBMTP_EVENT_DEVICE_PROPERTY_CHANGED: self = .devicePropertyChanged
		default: return nil
		}
	}
}
