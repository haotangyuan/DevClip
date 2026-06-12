import Foundation
import CryptoKit

public struct BlobDescriptor: Equatable, Sendable {
    public var id: UUID
    public var relativePath: String
    public var byteCount: Int64
    public var contentHash: String

    public init(
        id: UUID = UUID(),
        relativePath: String,
        byteCount: Int64,
        contentHash: String
    ) {
        self.id = id
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.contentHash = contentHash
    }
}

public protocol BlobStore: Sendable {
    func store(data: Data, suggestedExtension: String?) async throws -> BlobDescriptor
    func load(relativePath: String) async throws -> Data
    func deleteOrphanedBlobs(referencedPaths: Set<String>) async throws
}

/// Filesystem blob store for large representations outside the main SQLite file.
public actor FileSystemBlobStore: BlobStore {
    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.rootURL = applicationSupport
                .appendingPathComponent("DevClip", isDirectory: true)
                .appendingPathComponent("Blobs", isDirectory: true)
        }
    }

    public func store(data: Data, suggestedExtension: String?) async throws -> BlobDescriptor {
        try createRootIfNeeded()

        let contentHash = sha256(data)
        let extensionComponent = sanitizedExtension(suggestedExtension)
        let directoryName = String(contentHash.dropFirst("sha256:".count).prefix(2))
        let fileName = "\(contentHash.dropFirst("sha256:".count))\(extensionComponent)"
        let relativePath = "\(directoryName)/\(fileName)"
        let directoryURL = rootURL.appendingPathComponent(directoryName, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent(relativePath, isDirectory: false)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: [.atomic])
        }

        return BlobDescriptor(
            relativePath: relativePath,
            byteCount: Int64(data.count),
            contentHash: contentHash
        )
    }

    public func load(relativePath: String) async throws -> Data {
        let fileURL = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        guard fileURL.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path) else {
            throw DevClipError.invalidInput(reason: "Blob 路径无效。")
        }

        return try Data(contentsOf: fileURL)
    }

    public func deleteOrphanedBlobs(referencedPaths: Set<String>) async throws {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }

        let subpaths = try fileManager.subpathsOfDirectory(atPath: rootURL.path)
        var directories: [URL] = []

        for relativePath in subpaths {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

            if resourceValues.isRegularFile == true {
                if !referencedPaths.contains(relativePath) {
                    try fileManager.removeItem(at: fileURL)
                }
            } else if resourceValues.isDirectory == true {
                directories.append(fileURL)
            }
        }

        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    public func url(for descriptor: BlobDescriptor) -> URL {
        rootURL.appendingPathComponent(descriptor.relativePath, isDirectory: false)
    }

    private func createRootIfNeeded() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func sanitizedExtension(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return ""
        }

        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard trimmed.range(of: #"^[A-Za-z0-9]{1,12}$"#, options: .regularExpression) != nil else {
            return ""
        }

        return ".\(trimmed)"
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return "sha256:\(digest.map { String(format: "%02x", $0) }.joined())"
    }
}
