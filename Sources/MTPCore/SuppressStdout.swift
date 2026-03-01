#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#endif

package func withSuppressedStdout<T>(_ body: () -> T) -> T {
	fflush(stdout)
	let saved = dup(STDOUT_FILENO)
	let devNull = open("/dev/null", O_WRONLY)
	dup2(devNull, STDOUT_FILENO)
	close(devNull)
	let result = body()
	fflush(stdout)
	dup2(saved, STDOUT_FILENO)
	close(saved)
	return result
}
