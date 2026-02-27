import Clibmtp

public enum MTPDeviceCapability: Sendable {
    case moveObject
    case copyObject
    case getPartialObject
    case sendPartialObject
    case editObjects
}

public final class MTPDevice {
    let raw: UnsafeMutablePointer<LIBMTP_mtpdevice_struct>

    public init(busLocation: UInt32, devnum: UInt8) throws(MTPError) {
        var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>? = nil
        var numDevices: CInt = 0
        let result = LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices)
        if result == LIBMTP_ERROR_NO_DEVICE_ATTACHED {
            free(rawDevices)
            throw .noDeviceAttached
        }
        var matchIndex: Int? = nil
        for i in 0..<Int(numDevices) {
            if rawDevices![i].bus_location == busLocation && rawDevices![i].devnum == devnum {
                matchIndex = i
                break
            }
        }
        guard let idx = matchIndex else {
            free(rawDevices)
            throw .noDeviceAttached
        }
        guard let device = LIBMTP_Open_Raw_Device_Uncached(&rawDevices![idx]) else {
            free(rawDevices)
            throw .connectionFailed(bus: busLocation, devnum: devnum)
        }
        free(rawDevices)
        LIBMTP_Get_Storage(device, 0)
        raw = device
    }

    deinit {
        LIBMTP_Release_Device(raw)
    }

    public var manufacturerName: String? {
        guard let cStr = LIBMTP_Get_Manufacturername(raw) else { return nil }
        defer { free(cStr) }
        return String(cString: cStr)
    }

    public var modelName: String? {
        guard let cStr = LIBMTP_Get_Modelname(raw) else { return nil }
        defer { free(cStr) }
        return String(cString: cStr)
    }

    public var serialNumber: String? {
        guard let cStr = LIBMTP_Get_Serialnumber(raw) else { return nil }
        defer { free(cStr) }
        return String(cString: cStr)
    }

    public var friendlyName: String? {
        guard let cStr = LIBMTP_Get_Friendlyname(raw) else { return nil }
        defer { free(cStr) }
        return String(cString: cStr)
    }

    public var deviceVersion: String? {
        guard let cStr = LIBMTP_Get_Deviceversion(raw) else { return nil }
        defer { free(cStr) }
        return String(cString: cStr)
    }

    public func supportsCapability(_ cap: MTPDeviceCapability) -> Bool {
        let cCap: LIBMTP_devicecap_t = switch cap {
        case .moveObject: LIBMTP_DEVICECAP_MoveObject
        case .copyObject: LIBMTP_DEVICECAP_CopyObject
        case .getPartialObject: LIBMTP_DEVICECAP_GetPartialObject
        case .sendPartialObject: LIBMTP_DEVICECAP_SendPartialObject
        case .editObjects: LIBMTP_DEVICECAP_EditObjects
        }
        return LIBMTP_Check_Capability(raw, cCap) != 0
    }
}
