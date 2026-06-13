import Foundation

public struct ClipboardSnapshotBuildResult: Equatable, Sendable {
    public var group: ClipboardGroup
    public var entries: [ClipboardEntry]
    public var representations: [ClipboardRepresentation]
    public var snapshotHash: String

    public init(
        group: ClipboardGroup,
        entries: [ClipboardEntry],
        representations: [ClipboardRepresentation],
        snapshotHash: String
    ) {
        self.group = group
        self.entries = entries
        self.representations = representations
        self.snapshotHash = snapshotHash
    }
}

/// Converts pasteboard snapshots into model records with type metadata.
public struct ClipboardSnapshotBuilder: Sendable {
    private let contentClassifier: any ContentClassifier
    private let blobStore: (any BlobStore)?
    private let thumbnailGenerator: any ImageThumbnailGenerating

    public init(
        contentClassifier: any ContentClassifier = DefaultContentClassifier(),
        blobStore: (any BlobStore)? = nil,
        thumbnailGenerator: any ImageThumbnailGenerating = AppKitImageThumbnailGenerator()
    ) {
        self.contentClassifier = contentClassifier
        self.blobStore = blobStore
        self.thumbnailGenerator = thumbnailGenerator
    }

    public func build(from snapshot: ClipboardSnapshot) async -> ClipboardSnapshotBuildResult {
        let groupID = UUID()
        var entries: [ClipboardEntry] = []
        var representations: [ClipboardRepresentation] = []

        for item in snapshot.items {
            guard !item.representations.isEmpty else {
                continue
            }

            let entryID = UUID()
            let extractedText = bestText(in: item)
            let contentHash = ClipboardContentHasher.hash(item: item)
            let classificationInput = bestClassificationInput(in: item)
            let classification = await classify(input: classificationInput)
            let detectedKind = classification.detectedKind
            let previewText = preview(from: extractedText, item: item)
            let title = title(from: previewText, detectedKind: detectedKind)
            let byteCount = item.representations.reduce(Int64(0)) { partial, representation in
                partial + Int64(representation.data.count)
            }
            let representationBuild = await buildRepresentations(from: item, entryID: entryID)
            var metadata = metadata(
                snapshot: snapshot,
                item: item,
                classification: classification
            )
            for (key, value) in representationBuild.metadata.values {
                metadata.values[key] = value
            }

            let entry = ClipboardEntry(
                id: entryID,
                groupID: groupID,
                title: title,
                detectedKind: detectedKind,
                sourceAppName: snapshot.sourceAppName,
                sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
                contentHash: contentHash,
                searchableText: extractedText ?? previewText,
                previewText: previewText,
                createdAt: snapshot.capturedAt,
                updatedAt: snapshot.capturedAt,
                isSensitive: false,
                expiresAt: nil,
                byteCount: byteCount,
                metadata: metadata
            )

            entries.append(entry)
            representations.append(contentsOf: representationBuild.representations)
        }

        let group = ClipboardGroup(
            id: groupID,
            createdAt: snapshot.capturedAt,
            sourceAppName: snapshot.sourceAppName,
            sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
            itemCount: entries.count,
            metadata: ClipboardMetadata(values: [
                "snapshotChangeCount": String(snapshot.changeCount),
                "snapshotHash": ClipboardContentHasher.hash(snapshot: snapshot)
            ])
        )

        return ClipboardSnapshotBuildResult(
            group: group,
            entries: entries,
            representations: representations,
            snapshotHash: ClipboardContentHasher.hash(snapshot: snapshot)
        )
    }

    private func classify(input: ClassificationInput) async -> ClassificationResult {
        do {
            return try await contentClassifier.classify(input)
        } catch {
            return ClassificationResult(
                detectedKind: fallbackDetectedKind(for: input),
                candidates: [
                    ClassificationCandidate(
                        kind: fallbackDetectedKind(for: input),
                        confidence: 0.1,
                        evidence: "classifier_error"
                    )
                ]
            )
        }
    }

    private struct RepresentationBuild: Sendable {
        var representations: [ClipboardRepresentation]
        var metadata: ClipboardMetadata
    }

    private func buildRepresentations(
        from item: PasteboardItemSnapshot,
        entryID: UUID
    ) async -> RepresentationBuild {
        var output: [ClipboardRepresentation] = []
        var metadata = ClipboardMetadata()

        for (index, representation) in item.representations.enumerated() {
            let filePath = filePath(from: representation)
            let isFileReference = filePath != nil
            let isImage = isImageRepresentation(representation)

            if isImage, let blobBuild = await buildImageBlobRepresentation(
                from: representation,
                entryID: entryID,
                priority: index
            ) {
                output.append(contentsOf: blobBuild.representations)
                for (key, value) in blobBuild.metadata.values {
                    metadata.values[key] = value
                }
                continue
            }

            output.append(
                ClipboardRepresentation(
                    entryID: entryID,
                    pasteboardType: representation.pasteboardType,
                    uniformTypeIdentifier: representation.uniformTypeIdentifier,
                    storageKind: isFileReference ? .fileReference : .inlineData,
                    inlineData: isFileReference ? nil : representation.data,
                    externalFilePath: filePath,
                    byteCount: Int64(representation.data.count),
                    textEncoding: utf8Text(from: representation.data) == nil ? nil : "utf-8",
                    priority: index
                )
            )
        }

        return RepresentationBuild(representations: output, metadata: metadata)
    }

    private func buildImageBlobRepresentation(
        from representation: PasteboardRepresentationSnapshot,
        entryID: UUID,
        priority: Int
    ) async -> RepresentationBuild? {
        guard let blobStore else {
            return nil
        }

        do {
            let descriptor = try await blobStore.store(
                data: representation.data,
                suggestedExtension: imageExtension(for: representation)
            )
            var representations = [
                ClipboardRepresentation(
                    entryID: entryID,
                    pasteboardType: representation.pasteboardType,
                    uniformTypeIdentifier: representation.uniformTypeIdentifier,
                    storageKind: .blobFile,
                    externalFilePath: descriptor.relativePath,
                    byteCount: descriptor.byteCount,
                    textEncoding: nil,
                    priority: priority
                )
            ]
            var values: [String: String] = [
                "blobPath": descriptor.relativePath,
                "blobContentHash": descriptor.contentHash
            ]

            if
                let thumbnailData = try await thumbnailGenerator.thumbnailPNGData(
                    from: representation.data,
                    maxPixel: 256
                )
            {
                let thumbnail = try await blobStore.store(data: thumbnailData, suggestedExtension: "png")
                representations.append(
                    ClipboardRepresentation(
                        entryID: entryID,
                        pasteboardType: PasteboardInternalTypes.thumbnailPNG,
                        uniformTypeIdentifier: "public.png",
                        storageKind: .blobFile,
                        externalFilePath: thumbnail.relativePath,
                        byteCount: thumbnail.byteCount,
                        textEncoding: nil,
                        priority: priority + 10_000
                    )
                )
                values["thumbnailBlobPath"] = thumbnail.relativePath
                values["thumbnailByteCount"] = String(thumbnail.byteCount)
            }

            return RepresentationBuild(
                representations: representations,
                metadata: ClipboardMetadata(values: values)
            )
        } catch {
            return nil
        }
    }

    private func bestText(in item: PasteboardItemSnapshot) -> String? {
        let preferredTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "public.text",
            "public.url",
            "public.file-url",
            "NSStringPboardType",
            "public.html",
            "public.rtf"
        ]

        for preferredType in preferredTypes {
            if
                let representation = item.representations.first(where: { $0.pasteboardType == preferredType }),
                let text = utf8Text(from: representation.data),
                !text.isEmpty
            {
                return text
            }
        }

        return item.representations.lazy.compactMap { utf8Text(from: $0.data) }.first
    }

    private func detectedKind(
        for item: PasteboardItemSnapshot,
        extractedText: String?
    ) -> ClipboardContentKind {
        if item.representations.contains(where: isImageRepresentation) {
            return .image
        }

        if item.representations.contains(where: isFileURLRepresentation) {
            return .filePath
        }

        if extractedText != nil {
            return .plainText
        }

        return .binary
    }

    private func bestClassificationInput(in item: PasteboardItemSnapshot) -> ClassificationInput {
        let representation = bestRepresentationForClassification(in: item) ?? item.representations[0]
        return ClassificationInput(
            data: representation.data,
            pasteboardType: representation.pasteboardType,
            uniformTypeIdentifier: representation.uniformTypeIdentifier
        )
    }

    private func bestRepresentationForClassification(
        in item: PasteboardItemSnapshot
    ) -> PasteboardRepresentationSnapshot? {
        if let image = item.representations.first(where: isImageRepresentation) {
            return image
        }

        if let fileURL = item.representations.first(where: isFileURLRepresentation) {
            return fileURL
        }

        let preferredTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "public.text",
            "public.url",
            "NSStringPboardType",
            "public.html"
        ]

        for preferredType in preferredTypes {
            if let representation = item.representations.first(where: { $0.pasteboardType == preferredType }) {
                return representation
            }
        }

        return item.representations.first
    }

    private func fallbackDetectedKind(for input: ClassificationInput) -> ClipboardContentKind {
        if input.uniformTypeIdentifier?.hasPrefix("public.image") == true {
            return .image
        }

        if String(data: input.data, encoding: .utf8) != nil {
            return .plainText
        }

        return .binary
    }

    private func preview(from extractedText: String?, item: PasteboardItemSnapshot) -> String {
        if let extractedText, !extractedText.isEmpty {
            return clipped(extractedText.replacingOccurrences(of: "\n", with: " "), maxLength: 500)
        }

        if item.representations.contains(where: isImageRepresentation) {
            return "图片"
        }

        return "二进制数据"
    }

    private func metadata(
        snapshot: ClipboardSnapshot,
        item: PasteboardItemSnapshot,
        classification: ClassificationResult
    ) -> ClipboardMetadata {
        let values: [String: String] = [
            "phase": "4",
            "representationTypes": representationTypes(in: item),
            "snapshotChangeCount": String(snapshot.changeCount),
            "snapshotHash": ClipboardContentHasher.hash(snapshot: snapshot),
            "classificationCandidates": classification.candidates
                .map { "\($0.kind.rawValue):\(String(format: "%.2f", $0.confidence))" }
                .joined(separator: ","),
            "classificationEvidence": classification.candidates
                .map(\.evidence)
                .joined(separator: ","),
            "candidateKinds": classification.candidates
                .filter { $0.kind != classification.detectedKind }
                .map(\.kind.rawValue)
                .joined(separator: ","),
            "shouldIndex": "true"
        ]

        return ClipboardMetadata(values: values)
    }

    private func title(from preview: String, detectedKind: ClipboardContentKind) -> String {
        let cleaned = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return detectedKind.rawValue
        }

        return clipped(cleaned, maxLength: 80)
    }

    private func representationTypes(in item: PasteboardItemSnapshot) -> String {
        item.representations.map(\.pasteboardType).joined(separator: ",")
    }

    private func utf8Text(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    private func filePath(from representation: PasteboardRepresentationSnapshot) -> String? {
        guard isFileURLRepresentation(representation) else {
            return nil
        }

        guard let text = utf8Text(from: representation.data) else {
            return nil
        }

        return URL(string: text)?.path ?? text
    }

    private func isFileURLRepresentation(_ representation: PasteboardRepresentationSnapshot) -> Bool {
        representation.pasteboardType == "public.file-url"
            || representation.uniformTypeIdentifier == "public.file-url"
            || representation.pasteboardType == "NSFilenamesPboardType"
    }

    private func isImageRepresentation(_ representation: PasteboardRepresentationSnapshot) -> Bool {
        let type = representation.uniformTypeIdentifier ?? representation.pasteboardType
        return type.hasPrefix("public.image")
            || type == "public.png"
            || type == "public.jpeg"
            || type == "public.tiff"
    }

    private func imageExtension(for representation: PasteboardRepresentationSnapshot) -> String? {
        let type = representation.uniformTypeIdentifier ?? representation.pasteboardType
        switch type {
        case "public.png":
            return "png"
        case "public.jpeg", "public.jpg":
            return "jpg"
        case "public.tiff":
            return "tiff"
        default:
            return "img"
        }
    }

    private func clipped(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }

        return String(text.prefix(maxLength))
    }
}
