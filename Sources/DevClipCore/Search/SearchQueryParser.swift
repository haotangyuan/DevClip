import Foundation

public protocol SearchQueryParsing: Sendable {
    func parse(_ rawQuery: String) throws -> SearchQuery
}

/// Parses user search text into safe structured filters and terms.
public struct SearchQueryParser: SearchQueryParsing {
    public init() {}

    public func parse(_ rawQuery: String) throws -> SearchQuery {
        var query = SearchQuery()

        for token in tokenize(rawQuery) {
            if appendFilter(from: token.value, to: &query) {
                continue
            }

            if token.isQuoted {
                query.exactPhrases.append(token.value)
            } else {
                query.terms.append(token.value)
            }
        }

        return query
    }

    private func tokenize(_ rawQuery: String) -> [ParsedToken] {
        var tokens: [ParsedToken] = []
        var current = ""
        var isInsideQuote = false
        var tokenStartedWithQuote = false

        func flush() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                tokens.append(ParsedToken(value: value, isQuoted: tokenStartedWithQuote))
            }

            current = ""
            tokenStartedWithQuote = false
        }

        for character in rawQuery {
            if character == "\"" {
                if isInsideQuote {
                    isInsideQuote = false
                } else {
                    if current.isEmpty {
                        tokenStartedWithQuote = true
                    }
                    isInsideQuote = true
                }
                continue
            }

            if character.isSearchWhitespace && !isInsideQuote {
                flush()
            } else {
                current.append(character)
            }
        }

        flush()
        return tokens
    }

    private func appendFilter(from token: String, to query: inout SearchQuery) -> Bool {
        if token.hasPrefix("#") {
            let tag = String(token.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else {
                return false
            }

            query.filters.append(.tag(tag))
            return true
        }

        guard let separator = token.firstIndex(of: ":") else {
            return false
        }

        let key = token[..<separator].lowercased()
        let value = token[token.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return false
        }

        switch key {
        case "type":
            guard let kind = ClipboardContentKind.caseInsensitive(rawValue: value) else {
                return false
            }
            query.filters.append(.type(kind))
            return true

        case "app":
            query.filters.append(.app(value))
            return true

        case "is":
            switch value.lowercased() {
            case "pinned":
                query.filters.append(.pinned(true))
                return true
            case "unpinned":
                query.filters.append(.pinned(false))
                return true
            default:
                return false
            }

        case "before":
            guard let date = parseDate(value) else {
                return false
            }
            query.filters.append(.before(date))
            return true

        case "after":
            guard let date = parseDate(value) else {
                return false
            }
            query.filters.append(.after(date))
            return true

        default:
            return false
        }
    }

    private func parseDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: value)
    }
}

private struct ParsedToken: Equatable, Sendable {
    var value: String
    var isQuoted: Bool
}

private extension Character {
    var isSearchWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

private extension ClipboardContentKind {
    static func caseInsensitive(rawValue: String) -> ClipboardContentKind? {
        ClipboardContentKind.allCases.first {
            $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame
        }
    }
}
