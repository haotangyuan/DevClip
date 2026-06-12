import Foundation

public enum SearchFilter: Equatable, Sendable {
    case type(ClipboardContentKind)
    case app(String)
    case pinned(Bool)
    case sensitive(Bool)
    case before(Date)
    case after(Date)
    case tag(String)
}

public struct SearchQuery: Equatable, Sendable {
    public var terms: [String]
    public var exactPhrases: [String]
    public var filters: [SearchFilter]

    public init(
        terms: [String] = [],
        exactPhrases: [String] = [],
        filters: [SearchFilter] = []
    ) {
        self.terms = terms
        self.exactPhrases = exactPhrases
        self.filters = filters
    }
}

public struct SearchResult: Equatable, Sendable {
    public var entry: ClipboardEntry
    public var score: Double

    public init(entry: ClipboardEntry, score: Double) {
        self.entry = entry
        self.score = score
    }
}
