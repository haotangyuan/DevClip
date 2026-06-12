import Foundation

public protocol SearchService: Sendable {
    func search(_ query: SearchQuery, currentAppBundleIdentifier: String?) async throws -> [SearchResult]
}

/// Search service that prefers repository FTS and falls back to model filtering.
public actor SQLiteSearchService: SearchService {
    private let repository: any ClipboardRepository

    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    public func search(
        _ query: SearchQuery,
        currentAppBundleIdentifier: String? = nil
    ) async throws -> [SearchResult] {
        let candidates = try await candidateEntries(for: query)
        let filtered = candidates.filter { entry in
            !isExpired(entry) && matchesText(entry, query: query) && matchesFilters(entry, filters: query.filters)
        }

        return filtered
            .map {
                SearchResult(
                    entry: $0,
                    score: score(
                        entry: $0,
                        query: query,
                        currentAppBundleIdentifier: currentAppBundleIdentifier
                    )
                )
            }
            .sorted(by: sortResults)
    }

    private func candidateEntries(for query: SearchQuery) async throws -> [ClipboardEntry] {
        let text = searchText(for: query)
        guard !text.isEmpty else {
            return try await repository.entries()
        }

        if shouldUseFTS(for: query), let ftsRepository = repository as? any FTSClipboardRepository {
            return try await ftsRepository.searchFTS(text)
        }

        return try await repository.entries()
    }

    private func shouldUseFTS(for query: SearchQuery) -> Bool {
        let textParts = query.terms + query.exactPhrases
        guard !textParts.isEmpty else {
            return false
        }

        return textParts.contains { $0.count >= 3 }
    }

    private func searchText(for query: SearchQuery) -> String {
        (query.terms + query.exactPhrases)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesText(_ entry: ClipboardEntry, query: SearchQuery) -> Bool {
        let haystack = normalizedSearchHaystack(for: entry)

        for term in query.terms {
            guard haystack.contains(term.lowercased()) else {
                return false
            }
        }

        for phrase in query.exactPhrases {
            guard haystack.contains(phrase.lowercased()) else {
                return false
            }
        }

        return true
    }

    private func isExpired(_ entry: ClipboardEntry) -> Bool {
        guard let expiresAt = entry.expiresAt else {
            return false
        }

        return expiresAt <= Date()
    }

    private func matchesFilters(_ entry: ClipboardEntry, filters: [SearchFilter]) -> Bool {
        for filter in filters {
            switch filter {
            case let .type(kind):
                guard entry.detectedKind == kind else {
                    return false
                }

            case let .app(app):
                guard matchesApp(entry, app: app) else {
                    return false
                }

            case let .pinned(isPinned):
                guard entry.isPinned == isPinned else {
                    return false
                }

            case let .sensitive(isSensitive):
                guard entry.isSensitive == isSensitive else {
                    return false
                }

            case let .before(date):
                guard entry.createdAt < date else {
                    return false
                }

            case let .after(date):
                guard entry.createdAt >= date else {
                    return false
                }

            case let .tag(tag):
                guard tags(in: entry).contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
                    return false
                }
            }
        }

        return true
    }

    private func matchesApp(_ entry: ClipboardEntry, app: String) -> Bool {
        let normalizedApp = app.lowercased()
        return (entry.sourceAppName ?? "").lowercased().contains(normalizedApp)
            || (entry.sourceBundleIdentifier ?? "").lowercased().contains(normalizedApp)
    }

    private func tags(in entry: ClipboardEntry) -> [String] {
        let rawValues = [
            entry.metadata.values["tags"],
            entry.metadata.values["tag"]
        ].compactMap { $0 }

        return rawValues.flatMap { rawValue in
            rawValue
                .split { character in
                    character == "," || character == ";" || character == " "
                }
                .map(String.init)
        }
    }

    private func score(
        entry: ClipboardEntry,
        query: SearchQuery,
        currentAppBundleIdentifier: String?
    ) -> Double {
        var score = 0.0

        for term in query.terms {
            score += textScore(for: term, entry: entry)
        }

        for phrase in query.exactPhrases {
            score += textScore(for: phrase, entry: entry) * 1.5
        }

        if entry.isPinned {
            score += 100
        }

        if
            let currentAppBundleIdentifier,
            entry.sourceBundleIdentifier == currentAppBundleIdentifier
        {
            score += 25
        }

        score += min(Double(entry.useCount) * 2, 40)
        score += min(Double(entry.copyCount), 20)
        score += recencyScore(for: entry.lastUsedAt ?? entry.createdAt)
        return score
    }

    private func textScore(for rawNeedle: String, entry: ClipboardEntry) -> Double {
        let needle = rawNeedle.lowercased()
        var score = 0.0

        if entry.title.lowercased().contains(needle) {
            score += 40
        }

        if entry.searchableText.lowercased().contains(needle) {
            score += 25
        }

        if entry.previewText.lowercased().contains(needle) {
            score += 15
        }

        if entry.detectedKind.rawValue.lowercased().contains(needle) {
            score += 10
        }

        if matchesApp(entry, app: needle) {
            score += 8
        }

        return score
    }

    private func recencyScore(for date: Date) -> Double {
        let age = max(0, Date().timeIntervalSince(date))
        let day = 24.0 * 60.0 * 60.0
        return max(0, 30 - (age / day))
    }

    private func normalizedSearchHaystack(for entry: ClipboardEntry) -> String {
        [
            entry.title,
            entry.searchableText,
            entry.previewText,
            entry.detectedKind.rawValue,
            entry.sourceAppName ?? "",
            entry.sourceBundleIdentifier ?? ""
        ]
        .joined(separator: "\n")
        .lowercased()
    }

    private func sortResults(_ lhs: SearchResult, _ rhs: SearchResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        let lhsDate = lhs.entry.lastUsedAt ?? lhs.entry.createdAt
        let rhsDate = rhs.entry.lastUsedAt ?? rhs.entry.createdAt
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.entry.id.uuidString < rhs.entry.id.uuidString
    }
}
