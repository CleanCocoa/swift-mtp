@preconcurrency import Clibmtp

public enum DeviceCapability: CaseIterable, Sendable {
	case moveObject
	case copyObject
	case getPartialObject
	case sendPartialObject
	case editObjects

	package var cValue: LIBMTP_devicecap_t {
		switch self {
		case .moveObject: LIBMTP_DEVICECAP_MoveObject
		case .copyObject: LIBMTP_DEVICECAP_CopyObject
		case .getPartialObject: LIBMTP_DEVICECAP_GetPartialObject
		case .sendPartialObject: LIBMTP_DEVICECAP_SendPartialObject
		case .editObjects: LIBMTP_DEVICECAP_EditObjects
		}
	}

	package var bitmask: UInt64 { 1 << cValue.rawValue }
}

package final class Device {
	nonisolated(unsafe) package let raw: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>

	package init(raw device: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>) {
		raw = device
	}

	package init(busLocation: BusLocation, devnum: DeviceNumber) throws(MTPError) {
		guard MTP.isInitialized else { throw .notInitialized }
		var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>? = nil
		var numDevices: CInt = 0
		let result = LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices)
		defer { free(rawDevices) }
		if result == LIBMTP_ERROR_NO_DEVICE_ATTACHED {
			throw .noDeviceAttached
		}
		var matchIndex: Int? = nil
		for i in 0..<Int(numDevices) {
			if rawDevices![i].bus_location == busLocation.rawValue && rawDevices![i].devnum == devnum.rawValue {
				matchIndex = i
				break
			}
		}
		guard let idx = matchIndex else {
			throw .noDeviceAttached
		}
		guard let device = LIBMTP_Open_Raw_Device_Uncached(&rawDevices![idx]) else {
			throw .connectionFailed(bus: busLocation, devnum: devnum)
		}
		LIBMTP_Get_Storage(device, 0)
		raw = device
	}

	deinit {
		LIBMTP_Release_Device(raw)
	}

	package var manufacturerName: String? { getString(LIBMTP_Get_Manufacturername) }
	package var modelName: String? { getString(LIBMTP_Get_Modelname) }
	package var serialNumber: String? { getString(LIBMTP_Get_Serialnumber) }
	package var friendlyName: String? { getString(LIBMTP_Get_Friendlyname) }
	package var deviceVersion: String? { getString(LIBMTP_Get_Deviceversion) }

	private func getString(
		_ cfunc: (UnsafeMutablePointer<LIBMTP_mtpdevice_struct>?) -> UnsafeMutablePointer<CChar>?
	) -> String? {
		guard let cStr = cfunc(raw) else { return nil }
		defer { free(cStr) }
		return String(cString: cStr)
	}

	package nonisolated func events() -> AsyncStream<Event> {
		eventStream(device: raw, owner: self)
	}

	package func readEvent() throws(MTPError) -> Event {
		var event = LIBMTP_EVENT_NONE
		var param: UInt32 = 0
		let ret = LIBMTP_Read_Event(raw, &event, &param)
		if ret != 0 { throw .deviceDisconnected }
		guard let mtpEvent = Event(cEvent: event, param: param) else {
			throw .deviceDisconnected
		}
		return mtpEvent
	}

	package var capabilityBitmask: UInt64 {
		var mask: UInt64 = 0
		for cap in DeviceCapability.allCases {
			if LIBMTP_Check_Capability(raw, cap.cValue) != 0 {
				mask |= cap.bitmask
			}
		}
		return mask
	}

	package func storageInfo() -> [StorageInfo] {
		var result: [StorageInfo] = []
		var current = raw.pointee.storage
		while let storage = current {
			result.append(StorageInfo(cStorage: storage))
			current = storage.pointee.next
		}
		return result
	}
}
