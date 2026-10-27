import Foundation
import UniformTypeIdentifiers

enum HostsImportError: Error {
    case unreadable
    case tooLarge
    case invalidEncoding
    case invalidContent
    case noUserEntries
}

struct HostsImportResult {
    let suggestedProfileName: String
    let entries: [ParsedHostEntry]
}

enum HostsImport {
    static let maximumFileSize = 1_048_576
    static let allowedContentTypes: [UTType] = {
        var types: [UTType] = [.plainText]
        if let hostsType = UTType(filenameExtension: "hosts", conformingTo: .plainText) {
            types.insert(hostsType, at: 0)
        }
        return types
    }()

    static func load(from url: URL) throws -> HostsImportResult {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if values?.isRegularFile == false {
            throw HostsImportError.unreadable
        }
        if let fileSize = values?.fileSize, fileSize > maximumFileSize {
            throw HostsImportError.tooLarge
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw HostsImportError.unreadable
        }
        guard data.count <= maximumFileSize else {
            throw HostsImportError.tooLarge
        }
        guard var content = String(data: data, encoding: .utf8) else {
            throw HostsImportError.invalidEncoding
        }
        if content.first == "\u{FEFF}" {
            content.removeFirst()
        }
        guard HostsValueValidator.validate(content: content) == nil else {
            throw HostsImportError.invalidContent
        }

        let entries = HostsParser.parse(content).filter { !$0.isSystem }
        guard !entries.isEmpty else {
            throw HostsImportError.noUserEntries
        }

        let fileName = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return HostsImportResult(
            suggestedProfileName: fileName.isEmpty ? url.lastPathComponent : fileName,
            entries: entries
        )
    }
}
