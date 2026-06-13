import CryptoKit
import Foundation

public struct ClipboardArchiveExportSummary: Equatable, Sendable {
    public var exportedEntryCount: Int
    public var skippedEntryCount: Int

    public init(exportedEntryCount: Int, skippedEntryCount: Int) {
        self.exportedEntryCount = exportedEntryCount
        self.skippedEntryCount = skippedEntryCount
    }
}

public struct ClipboardArchiveImportSummary: Equatable, Sendable {
    public var importedEntryCount: Int

    public init(importedEntryCount: Int) {
        self.importedEntryCount = importedEntryCount
    }
}

public struct EncryptedClipboardArchive: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var createdAt: Date
    public var saltBase64: String
    public var nonceBase64: String
    public var ciphertextBase64: String
    public var tagBase64: String

    public init(
        formatVersion: Int,
        createdAt: Date,
        saltBase64: String,
        nonceBase64: String,
        ciphertextBase64: String,
        tagBase64: String
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.saltBase64 = saltBase64
        self.nonceBase64 = nonceBase64
        self.ciphertextBase64 = ciphertextBase64
        self.tagBase64 = tagBase64
    }
}

public protocol ClipboardArchiveService: Sendable {
    func exportEncrypted(passphrase: String) async throws -> (archive: EncryptedClipboardArchive, summary: ClipboardArchiveExportSummary)
    func importEncrypted(_ archive: EncryptedClipboardArchive, passphrase: String) async throws -> ClipboardArchiveImportSummary
}

public protocol ClipboardArchiveFileClient: Sendable {
    func write(_ archive: EncryptedClipboardArchive, to url: URL) async throws
    func read(from url: URL) async throws -> EncryptedClipboardArchive
}

public struct JSONClipboardArchiveFileClient: ClipboardArchiveFileClient {
    public init() {}

    public func write(_ archive: EncryptedClipboardArchive, to url: URL) async throws {
        let data = try JSONEncoder().encode(archive)
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    public func read(from url: URL) async throws -> EncryptedClipboardArchive {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EncryptedClipboardArchive.self, from: data)
    }
}

public actor AESGCMClipboardArchiveService: ClipboardArchiveService {
    private struct ArchivePayload: Codable, Equatable {
        var formatVersion: Int
        var groups: [ClipboardGroup]
        var entries: [ClipboardEntry]
        var representations: [ClipboardRepresentation]
    }

    private static let formatVersion = 1
    private static let keyInfo = Data("DevClip encrypted clipboard archive v1".utf8)

    private let repository: any ClipboardRepository
    private let saltGenerator: @Sendable () -> Data
    private let dateProvider: @Sendable () -> Date

    public init(
        repository: any ClipboardRepository,
        saltGenerator: @escaping @Sendable () -> Data = { Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }) },
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.saltGenerator = saltGenerator
        self.dateProvider = dateProvider
    }

    public func exportEncrypted(
        passphrase: String
    ) async throws -> (archive: EncryptedClipboardArchive, summary: ClipboardArchiveExportSummary) {
        let trimmedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassphrase.isEmpty else {
            throw DevClipError.invalidInput(reason: "导出口令不能为空。")
        }

        let allEntries = try await repository.entries()
        let exportableEntries = allEntries.filter(Self.isExportable)
        let exportableEntryIDs = Set(exportableEntries.map(\.id))
        let allGroups = try await repository.groups()
        let groupIDs = Set(exportableEntries.compactMap(\.groupID))
        let groups = allGroups.filter { groupIDs.contains($0.id) }
        var representations: [ClipboardRepresentation] = []

        for entry in exportableEntries {
            let entryRepresentations = try await repository.representations(entryID: entry.id)
            representations.append(
                contentsOf: entryRepresentations.filter { representation in
                    exportableEntryIDs.contains(representation.entryID)
                        && representation.storageKind != .blobFile
                }
            )
        }

        let payload = ArchivePayload(
            formatVersion: Self.formatVersion,
            groups: groups,
            entries: exportableEntries,
            representations: representations
        )
        let payloadData = try JSONEncoder().encode(payload)
        let salt = saltGenerator()
        let key = try Self.key(passphrase: trimmedPassphrase, salt: salt)
        let sealedBox = try AES.GCM.seal(payloadData, using: key)
        let archive = EncryptedClipboardArchive(
            formatVersion: Self.formatVersion,
            createdAt: dateProvider(),
            saltBase64: salt.base64EncodedString(),
            nonceBase64: Data(sealedBox.nonce).base64EncodedString(),
            ciphertextBase64: sealedBox.ciphertext.base64EncodedString(),
            tagBase64: sealedBox.tag.base64EncodedString()
        )
        let summary = ClipboardArchiveExportSummary(
            exportedEntryCount: exportableEntries.count,
            skippedEntryCount: allEntries.count - exportableEntries.count
        )

        return (archive, summary)
    }

    public func importEncrypted(
        _ archive: EncryptedClipboardArchive,
        passphrase: String
    ) async throws -> ClipboardArchiveImportSummary {
        guard archive.formatVersion == Self.formatVersion else {
            throw DevClipError.invalidInput(reason: "不支持的导入格式版本。")
        }

        let trimmedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassphrase.isEmpty else {
            throw DevClipError.invalidInput(reason: "导入口令不能为空。")
        }

        let salt = try Self.decodeBase64(archive.saltBase64, fieldName: "salt")
        let nonceData = try Self.decodeBase64(archive.nonceBase64, fieldName: "nonce")
        let ciphertext = try Self.decodeBase64(archive.ciphertextBase64, fieldName: "ciphertext")
        let tag = try Self.decodeBase64(archive.tagBase64, fieldName: "tag")
        let key = try Self.key(passphrase: trimmedPassphrase, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        let payloadData = try AES.GCM.open(sealedBox, using: key)
        let payload = try JSONDecoder().decode(ArchivePayload.self, from: payloadData)
        guard payload.formatVersion == Self.formatVersion else {
            throw DevClipError.invalidInput(reason: "不支持的导入内容版本。")
        }

        var importedCount = 0
        let groupsByID = Dictionary(uniqueKeysWithValues: payload.groups.map { ($0.id, $0) })
        let entriesByGroup = Dictionary(grouping: payload.entries) { entry in
            entry.groupID
        }

        for (groupID, entries) in entriesByGroup {
            let group = groupID.flatMap { groupsByID[$0] } ?? ClipboardGroup(
                sourceAppName: "DevClip 导入",
                itemCount: entries.count
            )
            let entryIDs = Set(entries.map(\.id))
            let representations = payload.representations.filter { entryIDs.contains($0.entryID) }
            try await repository.save(group: group, entries: entries, representations: representations)
            importedCount += entries.count
        }

        return ClipboardArchiveImportSummary(importedEntryCount: importedCount)
    }

    private static func isExportable(_ entry: ClipboardEntry) -> Bool {
        if entry.metadata.values["shouldExport"] == "false" {
            return false
        }

        return true
    }

    private static func key(passphrase: String, salt: Data) throws -> SymmetricKey {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "导出口令不是有效 UTF-8。")
        }

        let inputKey = SymmetricKey(data: passphraseData)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: keyInfo,
            outputByteCount: 32
        )
    }

    private static func decodeBase64(_ value: String, fieldName: String) throws -> Data {
        guard let data = Data(base64Encoded: value) else {
            throw DevClipError.invalidInput(reason: "导入文件中的 \(fieldName) 不是有效 Base64。")
        }

        return data
    }
}
