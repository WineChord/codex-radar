import CodexRadarCore
import Foundation

/// A single private quota reading. Authentication and reset-credit responses are never stored.
struct QuotaCacheStore {
    struct Reading: Codable, Equatable {
        let quota: RateLimitDashboard
        let updatedAt: Date
    }

    private struct Archive: Codable {
        let version: Int
        let reading: Reading
    }

    enum StorageError: Error {
        case invalidArchive
    }

    let url: URL
    private let maximumBytes = 256 * 1024

    init(url: URL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("CodexRadarSentinel/quota-cache-v1.json")) {
        self.url = url
    }

    func load(now: Date = Date()) throws -> Reading? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumBytes else {
            throw StorageError.invalidArchive
        }
        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1, archive.reading.updatedAt.timeIntervalSince1970.isFinite,
              archive.reading.updatedAt <= now.addingTimeInterval(300) else {
            throw StorageError.invalidArchive
        }
        return archive.reading
    }

    func save(_ reading: Reading) throws {
        let data = try JSONEncoder().encode(Archive(version: 1, reading: reading))
        guard data.count <= maximumBytes else { throw StorageError.invalidArchive }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Set permissions on the temporary inode before the atomic replacement.
        let temporary = directory.appendingPathComponent(".quota-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else { throw CocoaError(.fileWriteUnknown) }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
