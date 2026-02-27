import Clibmtp

public func mtpInitialize() {
    LIBMTP_Init()
}

public func mtpDetectDevices() throws(MTPError) -> [MTPRawDevice] {
    var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>? = nil
    var numDevices: CInt = 0
    let result = LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices)
    if result == LIBMTP_ERROR_NO_DEVICE_ATTACHED || numDevices == 0 {
        return []
    }
    if result != LIBMTP_ERROR_NONE {
        throw MTPError.operationFailed("device detection failed")
    }
    let devices = (0..<numDevices).map { i in
        MTPRawDevice(cRawDevice: &rawDevices![Int(i)])
    }
    free(rawDevices)
    return devices
}
