import Foundation

public struct SearchPerformanceMeasurement: Equatable, Sendable {
    public var entryCount: Int
    public var queryText: String
    public var resultCount: Int
    public var elapsedSeconds: Double

    public init(entryCount: Int, queryText: String, resultCount: Int, elapsedSeconds: Double) {
        self.entryCount = entryCount
        self.queryText = queryText
        self.resultCount = resultCount
        self.elapsedSeconds = elapsedSeconds
    }
}

public actor SearchPerformanceProbe {
    private let repository: any ClipboardRepository
    private let searchService: any SearchService

    public init(repository: any ClipboardRepository, searchService: any SearchService) {
        self.repository = repository
        self.searchService = searchService
    }

    public func seedEntries(count: Int, marker: String) async throws {
        guard count > 0 else {
            return
        }

        let group = ClipboardGroup(sourceAppName: "性能基线", itemCount: count)
        let entries = (0..<count).map { index in
            ClipboardEntry(
                groupID: group.id,
                title: "性能记录 \(index)",
                detectedKind: .plainText,
                sourceAppName: "性能基线",
                sourceBundleIdentifier: "dev.local.Performance",
                contentHash: "sha256:performance-\(marker)-\(index)",
                searchableText: "entry \(index) \(index == count - 1 ? marker : "common")",
                previewText: "entry \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                byteCount: 32
            )
        }

        try await repository.save(group: group, entries: entries, representations: [])
    }

    public func measure(query: SearchQuery, currentAppBundleIdentifier: String? = nil) async throws -> SearchPerformanceMeasurement {
        let entryCount = try await repository.entries().count
        let start = ContinuousClock.now
        let results = try await searchService.search(
            query,
            currentAppBundleIdentifier: currentAppBundleIdentifier
        )
        let elapsed = start.duration(to: .now)

        return SearchPerformanceMeasurement(
            entryCount: entryCount,
            queryText: (query.terms + query.exactPhrases).joined(separator: " "),
            resultCount: results.count,
            elapsedSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        )
    }
}
