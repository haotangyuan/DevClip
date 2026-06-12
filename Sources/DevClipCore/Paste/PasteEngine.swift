import Foundation

public enum PasteMode: String, Codable, CaseIterable, Sendable {
    case copyOnly
    case pasteOriginal
    case pastePlainText
    case pasteSpecificRepresentation
}

public struct PasteRequest: Equatable, Sendable {
    public var entryID: UUID
    public var mode: PasteMode
    public var representationID: UUID?
    public var targetApplication: PasteTargetApplication?

    public init(
        entryID: UUID,
        mode: PasteMode,
        representationID: UUID? = nil,
        targetApplication: PasteTargetApplication? = nil
    ) {
        self.entryID = entryID
        self.mode = mode
        self.representationID = representationID
        self.targetApplication = targetApplication
    }
}

public enum PasteFallbackReason: String, Codable, Equatable, Sendable {
    case automationDisabled
    case accessibilityPermissionDenied
    case noTargetApplication
}

public struct PasteExecutionResult: Equatable, Sendable {
    public var mode: PasteMode
    public var changeCount: Int
    public var didPaste: Bool
    public var fallbackReason: PasteFallbackReason?

    public init(
        mode: PasteMode,
        changeCount: Int,
        didPaste: Bool,
        fallbackReason: PasteFallbackReason? = nil
    ) {
        self.mode = mode
        self.changeCount = changeCount
        self.didPaste = didPaste
        self.fallbackReason = fallbackReason
    }
}

/// Paste orchestration boundary. System APIs are protocol-isolated for tests.
public actor PasteEngine {
    private let repository: any ClipboardRepository
    private let pasteboardClient: any PasteboardClient
    private let writeGuard: ClipboardWriteGuard
    private let automationPreferences: any PasteAutomationPreferenceProviding
    private let accessibilityPermissionClient: any AccessibilityPermissionClient
    private let applicationFocusClient: any ApplicationFocusClient
    private let keyboardEventClient: any KeyboardEventClient
    private let blobStore: (any BlobStore)?
    private let stabilizationDelay: Duration

    public init(
        repository: any ClipboardRepository,
        pasteboardClient: any PasteboardClient,
        writeGuard: ClipboardWriteGuard,
        automationPreferences: any PasteAutomationPreferenceProviding = StaticPasteAutomationPreferences(),
        accessibilityPermissionClient: any AccessibilityPermissionClient = SystemAccessibilityPermissionClient(),
        applicationFocusClient: any ApplicationFocusClient = SystemApplicationFocusClient(),
        keyboardEventClient: any KeyboardEventClient = SystemKeyboardEventClient(),
        blobStore: (any BlobStore)? = nil,
        stabilizationDelay: Duration = .milliseconds(120)
    ) {
        self.repository = repository
        self.pasteboardClient = pasteboardClient
        self.writeGuard = writeGuard
        self.automationPreferences = automationPreferences
        self.accessibilityPermissionClient = accessibilityPermissionClient
        self.applicationFocusClient = applicationFocusClient
        self.keyboardEventClient = keyboardEventClient
        self.blobStore = blobStore
        self.stabilizationDelay = stabilizationDelay
    }

    @discardableResult
    public func perform(_ request: PasteRequest) async throws -> PasteExecutionResult {
        let receipt: PasteboardWriteReceipt

        switch request.mode {
        case .copyOnly:
            receipt = try await copyOriginal(entryID: request.entryID)
            return PasteExecutionResult(
                mode: request.mode,
                changeCount: receipt.changeCount,
                didPaste: false,
                fallbackReason: .automationDisabled
            )

        case .pastePlainText:
            receipt = try await copyPlainText(entryID: request.entryID)

        case .pasteOriginal:
            receipt = try await copyOriginal(entryID: request.entryID)

        case .pasteSpecificRepresentation:
            receipt = try await copySpecificRepresentation(
                entryID: request.entryID,
                representationID: request.representationID
            )
        }

        return try await finishAutomaticPasteIfAllowed(
            request: request,
            changeCount: receipt.changeCount
        )
    }

    private func copyOriginal(entryID: UUID) async throws -> PasteboardWriteReceipt {
        guard let entry = try await repository.entry(id: entryID) else {
            throw DevClipError.invalidInput(reason: "找不到剪贴板记录。")
        }

        let representations = try await repository.representations(entryID: entryID)
        var snapshots: [PasteboardRepresentationSnapshot] = []
        for representation in representations
            .filter({ !PasteboardInternalTypes.isInternal($0.pasteboardType) })
            .sorted(by: { $0.priority < $1.priority })
        {
            snapshots.append(try await snapshotRepresentation(from: representation))
        }

        guard !snapshots.isEmpty else {
            throw DevClipError.invalidInput(reason: "此记录没有可写回的剪贴板表示。")
        }

        return try await write(
            item: PasteboardItemSnapshot(representations: snapshots),
            contentHash: entry.contentHash
        )
    }

    private func copyPlainText(entryID: UUID) async throws -> PasteboardWriteReceipt {
        guard let entry = try await repository.entry(id: entryID) else {
            throw DevClipError.invalidInput(reason: "找不到剪贴板记录。")
        }

        let representations = try await repository.representations(entryID: entryID)
        let textTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "public.text",
            "NSStringPboardType"
        ]

        let text: String
        if
            let textRepresentation = representations.first(where: { rep in
                textTypes.contains(rep.pasteboardType)
                    && !PasteboardInternalTypes.isInternal(rep.pasteboardType)
            }),
            let inlineData = textRepresentation.inlineData,
            let decoded = String(data: inlineData, encoding: .utf8)
        {
            text = decoded
        } else {
            text = entry.searchableText.isEmpty ? entry.previewText : entry.searchableText
        }

        guard let data = text.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法编码纯文本。")
        }

        let item = PasteboardItemSnapshot(representations: [
            PasteboardRepresentationSnapshot(
                pasteboardType: "public.utf8-plain-text",
                uniformTypeIdentifier: "public.utf8-plain-text",
                data: data
            )
        ])
        return try await write(item: item, contentHash: entry.contentHash)
    }

    private func copySpecificRepresentation(
        entryID: UUID,
        representationID: UUID?
    ) async throws -> PasteboardWriteReceipt {
        guard let representationID else {
            throw DevClipError.invalidInput(reason: "缺少剪贴板表示 ID。")
        }

        guard let entry = try await repository.entry(id: entryID) else {
            throw DevClipError.invalidInput(reason: "找不到剪贴板记录。")
        }

        let representations = try await repository.representations(entryID: entryID)
        guard let representation = representations.first(where: { $0.id == representationID }) else {
            throw DevClipError.invalidInput(reason: "找不到指定剪贴板表示。")
        }

        let item = PasteboardItemSnapshot(representations: [
            try await snapshotRepresentation(from: representation)
        ])
        return try await write(item: item, contentHash: entry.contentHash)
    }

    private func finishAutomaticPasteIfAllowed(
        request: PasteRequest,
        changeCount: Int
    ) async throws -> PasteExecutionResult {
        guard await automationPreferences.isAutomaticPasteEnabled() else {
            return PasteExecutionResult(
                mode: request.mode,
                changeCount: changeCount,
                didPaste: false,
                fallbackReason: .automationDisabled
            )
        }

        guard await accessibilityPermissionClient.requestTrustIfNeeded() else {
            return PasteExecutionResult(
                mode: request.mode,
                changeCount: changeCount,
                didPaste: false,
                fallbackReason: .accessibilityPermissionDenied
            )
        }

        let targetApplication: PasteTargetApplication?
        if let requestedTargetApplication = request.targetApplication {
            targetApplication = requestedTargetApplication
        } else {
            targetApplication = await applicationFocusClient.frontmostApplication()
        }

        guard let targetApplication else {
            return PasteExecutionResult(
                mode: request.mode,
                changeCount: changeCount,
                didPaste: false,
                fallbackReason: .noTargetApplication
            )
        }

        guard await applicationFocusClient.activate(targetApplication) else {
            return PasteExecutionResult(
                mode: request.mode,
                changeCount: changeCount,
                didPaste: false,
                fallbackReason: .noTargetApplication
            )
        }

        try await Task.sleep(for: stabilizationDelay)
        try await keyboardEventClient.postCommandV()
        return PasteExecutionResult(
            mode: request.mode,
            changeCount: changeCount,
            didPaste: true
        )
    }

    private func write(
        item: PasteboardItemSnapshot,
        contentHash: String
    ) async throws -> PasteboardWriteReceipt {
        let writeRequest = PasteboardWriteRequest(
            items: [item],
            contentHash: contentHash
        )
        let receipt = try await pasteboardClient.write(writeRequest)
        try await writeGuard.recordInternalWrite(
            ClipboardWriteMarker(
                transactionID: receipt.transactionID,
                contentHash: contentHash,
                changeCount: receipt.changeCount
            )
        )
        return receipt
    }

    private func snapshotRepresentation(
        from representation: ClipboardRepresentation
    ) async throws -> PasteboardRepresentationSnapshot {
        let data: Data

        switch representation.storageKind {
        case .inlineData:
            guard let inlineData = representation.inlineData else {
                throw DevClipError.invalidInput(reason: "内联剪贴板表示缺少数据。")
            }
            data = inlineData

        case .fileReference:
            guard let path = representation.externalFilePath else {
                throw DevClipError.invalidInput(reason: "文件引用缺少路径。")
            }

            let payload: String
            if representation.pasteboardType == "public.file-url"
                || representation.uniformTypeIdentifier == "public.file-url"
            {
                payload = URL(fileURLWithPath: path).absoluteString
            } else {
                payload = path
            }

            guard let encoded = payload.data(using: .utf8) else {
                throw DevClipError.invalidInput(reason: "无法编码文件引用。")
            }
            data = encoded

        case .blobFile:
            guard let path = representation.externalFilePath else {
                throw DevClipError.invalidInput(reason: "Blob 表示缺少路径。")
            }

            guard let blobStore else {
                throw DevClipError.invalidInput(reason: "当前运行时无法读取 Blob 数据。")
            }

            data = try await blobStore.load(relativePath: path)
        }

        return PasteboardRepresentationSnapshot(
            pasteboardType: representation.pasteboardType,
            uniformTypeIdentifier: representation.uniformTypeIdentifier,
            data: data
        )
    }
}
