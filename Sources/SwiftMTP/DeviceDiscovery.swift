import Clibmtp

public func mtpInitialize() {
    LIBMTP_Init()
}

public func mtpDetectDevices() throws(MTPError) -> [RawDevice] {
    var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>? = nil
    var numDevices: CInt = 0
    let result = LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices)
    defer { free(rawDevices) }
    if result == LIBMTP_ERROR_NO_DEVICE_ATTACHED || numDevices == 0 {
        return []
    }
    if result != LIBMTP_ERROR_NONE {
        throw MTPError.operationFailed("device detection failed")
    }
    return (0..<numDevices).map { i in
        RawDevice(cRawDevice: &rawDevices![Int(i)])
    }
}
