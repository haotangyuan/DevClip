import CryptoKit
import Foundation

/// Produces stable SHA-256 hashes for pasteboard snapshots and items.
public enum ClipboardContentHasher {
    public static func hash(item: PasteboardItemSnapshot) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("DevClipItemV1".utf8))

        for representation in item.representations.sorted(by: representationSort) {
            update(&hasher, with: representation.pasteboardType)
            update(&hasher, with: representation.uniformTypeIdentifier ?? "")
            update(&hasher, with: representation.data)
        }

        return "sha256:\(hexDigest(hasher.finalize()))"
    }

    public static func hash(snapshot: ClipboardSnapshot) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("DevClipSnapshotV1".utf8))

        for item in snapshot.items {
            update(&hasher, with: hash(item: item))
        }

        return "sha256:\(hexDigest(hasher.finalize()))"
    }

    private static func representationSort(
        lhs: PasteboardRepresentationSnapshot,
        rhs: PasteboardRepresentationSnapshot
    ) -> Bool {
        if lhs.pasteboardType == rhs.pasteboardType {
            return (lhs.uniformTypeIdentifier ?? "") < (rhs.uniformTypeIdentifier ?? "")
        }

        return lhs.pasteboardType < rhs.pasteboardType
    }

    private static func update(_ hasher: inout SHA256, with text: String) {
        let data = Data(text.utf8)
        update(&hasher, with: data)
    }

    private static func update(_ hasher: inout SHA256, with data: Data) {
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
        hasher.update(data: data)
    }

    private static func hexDigest(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
