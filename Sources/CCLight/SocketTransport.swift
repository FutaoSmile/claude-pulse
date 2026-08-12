import Darwin
import Foundation

enum SocketTransport {
    static var path: String { "/tmp/cc-light-\(getuid()).sock" }

    static func emit(_ data: Data) throws {
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxLength) { chars in
                _ = path.withCString { source in strcpy(chars, source) }
            }
        }

        let result = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(descriptor, bytes.baseAddress, data.count, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        guard result >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

final class SocketServer: @unchecked Sendable {
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private let onEvent: @Sendable (HookEvent) -> Void

    init(onEvent: @escaping @Sendable (HookEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() throws {
        unlink(SocketTransport.path)
        descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxLength) { chars in
                _ = SocketTransport.path.withCString { source in strcpy(chars, source) }
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        chmod(SocketTransport.path, 0o600)

        let queue = DispatchQueue(label: "app.cclight.socket", qos: .userInteractive)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.receive() }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
            unlink(SocketTransport.path)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func receive() {
        var buffer = [UInt8](repeating: 0, count: 128 * 1024)
        let count = recv(descriptor, &buffer, buffer.count, 0)
        guard count > 0 else { return }
        do {
            let event = try JSONDecoder().decode(HookEvent.self, from: Data(buffer.prefix(count)))
            onEvent(event)
        } catch {
            fputs("CCLight ignored malformed event: \(error)\n", stderr)
        }
    }
}
