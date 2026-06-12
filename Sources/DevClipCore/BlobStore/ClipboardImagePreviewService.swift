import Foundation

public actor ClipboardImagePreviewService {
    private let repository: any ClipboardRepository
    private let blobStore: (any BlobStore)?

    public init(repository: any ClipboardRepository, blobStore: (any BlobStore)?) {
        self.repository = repository
        self.blobStore = blobStore
    }

    public func imageData(
        for entry: ClipboardEntry,
        preferThumbnail: Bool
    ) async throws -> Data? {
        let representations = try await repository.representations(entryID: entry.id)
            .sorted { $0.priority < $1.priority }

        if preferThumbnail {
            if let representation = representations.first(where: isThumbnailRepresentation) {
                return try await data(from: representation)
            }

            if let path = entry.metadata.values["thumbnailBlobPath"], let blobStore {
                return try await blobStore.load(relativePath: path)
            }
        }

        if let representation = representations.first(where: isImageRepresentation) {
            return try await data(from: representation)
        }

        if let path = entry.metadata.values["blobPath"], let blobStore {
            return try await blobStore.load(relativePath: path)
        }

        if let representation = representations.first {
            return try await data(from: representation)
        }

        return nil
    }

    private func data(from representation: ClipboardRepresentation) async throws -> Data? {
        switch representation.storageKind {
        case .inlineData:
            return representation.inlineData

        case .blobFile:
            guard let path = representation.externalFilePath, let blobStore else {
                return nil
            }

            return try await blobStore.load(relativePath: path)

        case .fileReference:
            guard let path = representation.externalFilePath else {
                return nil
            }

            return try await Task.detached(priority: .utility) {
                try Data(contentsOf: URL(fileURLWithPath: path))
            }.value
        }
    }

    private func isThumbnailRepresentation(_ representation: ClipboardRepresentation) -> Bool {
        representation.pasteboardType == PasteboardInternalTypes.thumbnailPNG
    }

    private func isImageRepresentation(_ representation: ClipboardRepresentation) -> Bool {
        if PasteboardInternalTypes.isInternal(representation.pasteboardType) {
            return false
        }

        let type = representation.uniformTypeIdentifier ?? representation.pasteboardType
        return type.hasPrefix("public.image")
            || type == "public.png"
            || type == "public.jpeg"
            || type == "public.tiff"
            || type == "public.heic"
    }
}
