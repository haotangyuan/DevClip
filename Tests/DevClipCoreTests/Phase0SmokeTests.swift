import Foundation
@testable import DevClipCore
import Testing

@Suite("Phase 0 Smoke Tests")
struct Phase0SmokeTests {
    @Test
    func clipboardEntryCarriesRequiredFields() {
        let groupID = UUID()
        let entry = ClipboardEntry(
            groupID: groupID,
            title: "Example",
            detectedKind: .plainText,
            sourceAppName: "Xcode",
            sourceBundleIdentifier: "com.apple.dt.Xcode",
            contentHash: "sha256:example",
            searchableText: "Example",
            previewText: "Example",
            byteCount: 7,
            metadata: ClipboardMetadata(values: ["candidateKinds": "plainText"])
        )

        #expect(entry.groupID == groupID)
        #expect(entry.detectedKind == .plainText)
        #expect(entry.sourceBundleIdentifier == "com.apple.dt.Xcode")
        #expect(entry.metadata.values["candidateKinds"] == "plainText")
    }

    @Test
    func clipboardRepresentationCarriesPasteboardAndUTTypeMetadata() {
        let entryID = UUID()
        let representation = ClipboardRepresentation(
            entryID: entryID,
            pasteboardType: "public.utf8-plain-text",
            uniformTypeIdentifier: "public.utf8-plain-text",
            storageKind: .inlineData,
            inlineData: Data("Example".utf8),
            byteCount: 7,
            textEncoding: "utf-8",
            priority: 0
        )

        #expect(representation.entryID == entryID)
        #expect(representation.storageKind == .inlineData)
        #expect(representation.byteCount == 7)
    }

    @Test
    func databasePlanDocumentsRequiredSQLiteFeatures() {
        let plan = DatabaseBootstrap.phase0Plan()

        #expect(plan.usesWAL)
        #expect(plan.usesForeignKeys)
        #expect(plan.usesMigrations)
        #expect(plan.usesFTS5)
    }
}
