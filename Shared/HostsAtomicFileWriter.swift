import Darwin
import Foundation

enum HostsAtomicFileWriteError: LocalizedError {
    case invalidContent(String)
    case cannotInspectDestination
    case cannotCreateTemporaryFile(Int32)
    case cannotWrite(Int32)
    case cannotSync(Int32)
    case cannotReplace(Int32)
    case cannotVerify

    var errorDescription: String? {
        switch self {
        case let .invalidContent(message):
            return message
        case .cannotInspectDestination:
            return "Unable to read the destination file metadata."
        case let .cannotCreateTemporaryFile(code):
            return "Unable to create a temporary hosts file (errno \(code))."
        case let .cannotWrite(code):
            return "Unable to write the temporary hosts file (errno \(code))."
        case let .cannotSync(code):
            return "Unable to flush the temporary hosts file (errno \(code))."
        case let .cannotReplace(code):
            return "Unable to atomically replace the destination (errno \(code))."
        case .cannotVerify:
            return "The written hosts file did not pass verification."
        }
    }
}

enum HostsAtomicFileWriter {
    static func write(_ content: String, to targetURL: URL) throws {
        if let validationError = HostsValueValidator.validate(content: content) {
            throw HostsAtomicFileWriteError.invalidContent(validationError)
        }

        let fileManager = FileManager.default
        let directoryURL = targetURL.deletingLastPathComponent()
        let tempURL = directoryURL.appendingPathComponent(
            ".hosts-manager-\(UUID().uuidString).tmp"
        )

        var destinationStatus = stat()
        let destinationExists = targetURL.path.withCString {
            stat($0, &destinationStatus) == 0
        }
        if !destinationExists && access(targetURL.path, F_OK) == 0 {
            throw HostsAtomicFileWriteError.cannotInspectDestination
        }

        let mode = destinationExists ? destinationStatus.st_mode & 0o777 : 0o644
        let temporaryDescriptor = tempURL.path.withCString {
            open($0, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        }
        guard temporaryDescriptor >= 0 else {
            throw HostsAtomicFileWriteError.cannotCreateTemporaryFile(errno)
        }

        var installed = false
        var descriptorOpen = true
        defer {
            if descriptorOpen {
                close(temporaryDescriptor)
            }
            if !installed {
                try? fileManager.removeItem(at: tempURL)
            }
        }

        let data = Data(content.utf8)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let result = Darwin.write(
                    temporaryDescriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    throw HostsAtomicFileWriteError.cannotWrite(errno)
                }
                offset += result
            }
        }

        if fchmod(temporaryDescriptor, mode) != 0 {
            throw HostsAtomicFileWriteError.cannotWrite(errno)
        }
        if destinationExists {
            if fchown(temporaryDescriptor, destinationStatus.st_uid, destinationStatus.st_gid) != 0 {
                throw HostsAtomicFileWriteError.cannotWrite(errno)
            }
        }
        if fsync(temporaryDescriptor) != 0 {
            throw HostsAtomicFileWriteError.cannotSync(errno)
        }
        let closeResult = close(temporaryDescriptor)
        descriptorOpen = false
        guard closeResult == 0 else {
            throw HostsAtomicFileWriteError.cannotSync(errno)
        }

        let renameResult = tempURL.path.withCString { tempPath in
            targetURL.path.withCString { targetPath in
                Darwin.rename(tempPath, targetPath)
            }
        }
        guard renameResult == 0 else {
            throw HostsAtomicFileWriteError.cannotReplace(errno)
        }
        installed = true

        let directoryDescriptor = directoryURL.path.withCString {
            open($0, O_RDONLY)
        }
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            close(directoryDescriptor)
        }

        guard let written = try? String(contentsOf: targetURL, encoding: .utf8),
              written == content else {
            throw HostsAtomicFileWriteError.cannotVerify
        }
    }
}
