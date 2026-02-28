@preconcurrency import Clibmtp

public struct DetectedDevice: Sendable {
	public let busLocation: BusLocation
	public let devnum: DeviceNumber
	public let vendor: String
	public let vendorId: VendorID
	public let product: String
	public let productId: ProductID
	private nonisolated(unsafe) var cRaw: LIBMTP_raw_device_t

	public init(
		busLocation: BusLocation,
		devnum: DeviceNumber,
		vendor: String,
		vendorId: VendorID,
		product: String,
		productId: ProductID
	) {
		self.busLocation = busLocation
		self.devnum = devnum
		self.vendor = vendor
		self.vendorId = vendorId
		self.product = product
		self.productId = productId
		self.cRaw = LIBMTP_raw_device_t()
		self.cRaw.bus_location = busLocation.rawValue
		self.cRaw.devnum = devnum.rawValue
	}

	init(cDetectedDevice: UnsafePointer<LIBMTP_raw_device_struct>) {
		let raw = cDetectedDevice.pointee
		busLocation = BusLocation(rawValue: raw.bus_location)
		devnum = DeviceNumber(rawValue: raw.devnum)
		vendor = raw.device_entry.vendor.map { String(cString: $0) } ?? ""
		vendorId = VendorID(rawValue: raw.device_entry.vendor_id)
		product = raw.device_entry.product.map { String(cString: $0) } ?? ""
		productId = ProductID(rawValue: raw.device_entry.product_id)
		cRaw = raw
	}

	package mutating func open() throws(MTPError) -> Device {
		guard MTP.isInitialized else { throw .notInitialized }
		guard let device = withSuppressedStdout({ LIBMTP_Open_Raw_Device_Uncached(&cRaw) }) else {
			throw .connectionFailed(bus: busLocation, devnum: devnum)
		}
		LIBMTP_Get_Storage(device, 0)
		return Device(raw: device)
	}
}
