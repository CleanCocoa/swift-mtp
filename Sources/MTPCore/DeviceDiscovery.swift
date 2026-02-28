@preconcurrency import Clibmtp
import Synchronization

public enum MTP {
	private static let _initialized = Atomic<Bool>(false)

	public static var isInitialized: Bool {
		_initialized.load(ordering: .acquiring)
	}

	public static func initialize() throws(MTPError) {
		let (exchanged, _) = _initialized.compareExchange(
			expected: false, desired: true, ordering: .acquiringAndReleasing
		)
		guard exchanged else { throw .alreadyInitialized }
		LIBMTP_Init()
	}

	/// ## C contract
	/// `LIBMTP_Detect_Raw_Devices` allocates a flat `malloc` array of `LIBMTP_raw_device_t`.
	/// Caller must `free()` the array pointer (not individual elements).
	public static func detectDevices() throws(MTPError) -> [DetectedDevice] {
		guard isInitialized else { throw .notInitialized }
		var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>? = nil
		var numDevices: CInt = 0
		let result = withSuppressedStdout { LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices) }
		defer { free(rawDevices) }
		if result == LIBMTP_ERROR_NO_DEVICE_ATTACHED || numDevices == 0 {
			return []
		}
		if result != LIBMTP_ERROR_NONE {
			throw MTPError.operationFailed("device detection failed")
		}
		return (0..<numDevices).map { i in
			DetectedDevice(cDetectedDevice: &rawDevices![Int(i)])
		}
	}
}
