import Foundation

public struct ClassificationInput: Equatable, Sendable {
    public var data: Data
    public var pasteboardType: String?
    public var uniformTypeIdentifier: String?

    public init(
        data: Data,
        pasteboardType: String? = nil,
        uniformTypeIdentifier: String? = nil
    ) {
        self.data = data
        self.pasteboardType = pasteboardType
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }
}

public struct ClassificationCandidate: Equatable, Sendable {
    public var kind: ClipboardContentKind
    public var confidence: Double
    public var evidence: String

    public init(kind: ClipboardContentKind, confidence: Double, evidence: String) {
        self.kind = kind
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct ClassificationResult: Equatable, Sendable {
    public var detectedKind: ClipboardContentKind
    public var candidates: [ClassificationCandidate]

    public init(detectedKind: ClipboardContentKind, candidates: [ClassificationCandidate]) {
        self.detectedKind = detectedKind
        self.candidates = candidates
    }
}

public protocol ContentDetector: Sendable {
    var id: String { get }
    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate]
}

public protocol ContentClassifier: Sendable {
    func classify(_ input: ClassificationInput) async throws -> ClassificationResult
}

/// Default type-aware classifier assembled from small independent detectors.
public struct DefaultContentClassifier: ContentClassifier {
    private let detectors: [any ContentDetector]

    public init(detectors: [any ContentDetector]? = nil) {
        self.detectors = detectors ?? [
            RepresentationTypeDetector(),
            IdentifierTextDetector(),
            EncodedDataDetector(),
            StructuredTextDetector(),
            CodeTextDetector()
        ]
    }

    public func classify(_ input: ClassificationInput) async throws -> ClassificationResult {
        var candidates: [ClassificationCandidate] = []

        for detector in detectors {
            do {
                candidates.append(contentsOf: try await detector.detect(input))
            } catch {
                candidates.append(
                    ClassificationCandidate(
                        kind: .plainText,
                        confidence: 0,
                        evidence: "detector_error:\(detector.id)"
                    )
                )
            }
        }

        let deduped = Self.deduplicate(candidates)
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.kind.rawValue < $1.kind.rawValue
                }

                return $0.confidence > $1.confidence
            }

        return ClassificationResult(
            detectedKind: deduped.first?.kind ?? fallbackKind(for: input),
            candidates: deduped
        )
    }

    private static func deduplicate(
        _ candidates: [ClassificationCandidate]
    ) -> [ClassificationCandidate] {
        var bestByKind: [ClipboardContentKind: ClassificationCandidate] = [:]

        for candidate in candidates where candidate.confidence > 0 {
            guard let existing = bestByKind[candidate.kind] else {
                bestByKind[candidate.kind] = candidate
                continue
            }

            if candidate.confidence > existing.confidence {
                bestByKind[candidate.kind] = candidate
            }
        }

        return Array(bestByKind.values)
    }

    private func fallbackKind(for input: ClassificationInput) -> ClipboardContentKind {
        if input.text != nil {
            return .plainText
        }

        return .binary
    }
}

public typealias PlaceholderContentClassifier = DefaultContentClassifier

private struct RepresentationTypeDetector: ContentDetector {
    let id = "representation-type"

    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate] {
        let type = (input.uniformTypeIdentifier ?? input.pasteboardType ?? "").lowercased()
        var candidates: [ClassificationCandidate] = []

        if type.hasPrefix("public.image") || ["public.png", "public.jpeg", "public.tiff"].contains(type) {
            candidates.append(.init(kind: .image, confidence: 0.98, evidence: "uti:image"))
        }

        if type == "nsfilenamespboardtype" {
            candidates.append(.init(kind: .fileList, confidence: 0.95, evidence: "pasteboard:file-list"))
        } else if type == "public.file-url" {
            candidates.append(.init(kind: .filePath, confidence: 0.94, evidence: "pasteboard:file-url"))
        }

        if type.hasPrefix("public.text") || type == "public.utf8-plain-text" || type == "nsstringpboardtype" {
            candidates.append(.init(kind: .plainText, confidence: 0.35, evidence: "uti:text"))
        }

        if candidates.isEmpty, input.text == nil {
            candidates.append(.init(kind: .binary, confidence: 0.55, evidence: "no:utf8-text"))
        }

        return candidates
    }
}

private struct IdentifierTextDetector: ContentDetector {
    let id = "identifier-text"

    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate] {
        guard let text = input.trimmedText else {
            return []
        }

        var candidates: [ClassificationCandidate] = [
            .init(kind: .plainText, confidence: 0.25, evidence: "utf8:text")
        ]

        if URL(string: text)?.scheme != nil, text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .url, confidence: 0.95, evidence: "regex:url"))
        }

        if text.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            candidates.append(.init(kind: .email, confidence: 0.94, evidence: "regex:email"))
        }

        if UUID(uuidString: text) != nil {
            candidates.append(.init(kind: .uuid, confidence: 0.94, evidence: "parser:uuid"))
        }

        if text.range(of: #"^(\d{1,3}\.){3}\d{1,3}$"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .ipAddress, confidence: 0.86, evidence: "regex:ipv4"))
        }

        if text.range(of: #"^#?[0-9A-F]{6}([0-9A-F]{2})?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            candidates.append(.init(kind: .color, confidence: 0.82, evidence: "regex:hex-color"))
        }

        if text.range(of: #"^(/[^\0]+|~(/[^\0]+)?|\./[^\0]+|\.\./[^\0]+)$"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .filePath, confidence: 0.78, evidence: "regex:file-path"))
        }

        let pathLines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if pathLines.count > 1, pathLines.allSatisfy({ $0.hasPrefix("/") || $0.hasPrefix("~/") }) {
            candidates.append(.init(kind: .fileList, confidence: 0.8, evidence: "shape:file-list"))
        }

        if text.range(of: #"^[0-9A-F]{7,40}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            candidates.append(.init(kind: .gitCommit, confidence: text.count == 40 ? 0.88 : 0.68, evidence: "regex:git-commit"))
        }

        if let number = Double(text), number >= 0 {
            if text.range(of: #"^\d{10}$"#, options: .regularExpression) != nil {
                candidates.append(.init(kind: .unixTimestamp, confidence: 0.78, evidence: "regex:unix-seconds"))
            } else if text.range(of: #"^\d{13}$"#, options: .regularExpression) != nil {
                candidates.append(.init(kind: .unixTimestamp, confidence: 0.82, evidence: "regex:unix-milliseconds"))
            }
        }

        if ISO8601DateFormatter().date(from: text) != nil {
            candidates.append(.init(kind: .isoDate, confidence: 0.88, evidence: "parser:iso8601"))
        }

        return candidates
    }
}

private struct EncodedDataDetector: ContentDetector {
    let id = "encoded-data"

    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate] {
        guard let text = input.trimmedText else {
            return []
        }

        var candidates: [ClassificationCandidate] = []

        if text.range(of: #"^data:([^;,]+)?(;base64)?,.*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            candidates.append(.init(kind: .dataURI, confidence: 0.96, evidence: "regex:data-uri"))
        }

        if text.range(of: #"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .jwt, confidence: 0.94, evidence: "regex:jwt-shape"))
        }

        if text.range(of: #"-----BEGIN [A-Z ]+-----"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .pem, confidence: 0.94, evidence: "regex:pem"))
        }

        if text.range(of: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .privateKey, confidence: 0.99, evidence: "regex:private-key"))
        }

        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        if compact.range(of: #"^[A-Fa-f0-9]+$"#, options: .regularExpression) != nil, compact.count >= 4 {
            candidates.append(.init(kind: .hex, confidence: 0.62, evidence: "regex:hex"))
            if [32, 40, 64, 96, 128].contains(compact.count) {
                candidates.append(.init(kind: .hash, confidence: 0.84, evidence: "regex:hash-length"))
            }
        }

        if isLikelyBase64(compact) {
            candidates.append(.init(kind: .base64, confidence: 0.74, evidence: "regex:base64"))
        }

        return candidates
    }

    private func isLikelyBase64(_ value: String) -> Bool {
        guard value.count >= 8, value.count % 4 != 1 else {
            return false
        }

        guard value.range(of: #"^[A-Za-z0-9+/_-]+={0,2}$"#, options: .regularExpression) != nil else {
            return false
        }

        let letterCount = value.filter(\.isLetter).count
        let digitCount = value.filter(\.isNumber).count
        return letterCount > 0 && (digitCount > 0 || value.contains("+") || value.contains("/") || value.contains("_") || value.contains("-"))
    }
}

private struct StructuredTextDetector: ContentDetector {
    let id = "structured-text"

    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate] {
        guard let text = input.trimmedText else {
            return []
        }

        var candidates: [ClassificationCandidate] = []

        if isJSON(text) {
            candidates.append(.init(kind: .json, confidence: 0.96, evidence: "parser:json"))
        }

        if text.range(of: #"(?s)^\s*<\?xml|<([A-Za-z][A-Za-z0-9:_-]*)(\s[^>]*)?>.*</\1>\s*$"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .xml, confidence: 0.86, evidence: "regex:xml"))
        }

        if text.range(of: #"(?is)<(html|body|div|span|p|script|style|a)\b[^>]*>"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .html, confidence: 0.88, evidence: "regex:html"))
        }

        if text.range(of: #"(?m)^\s*#{1,6}\s+\S|```|!\[[^\]]*\]\([^)]+\)|\[[^\]]+\]\([^)]+\)"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .markdown, confidence: 0.78, evidence: "regex:markdown"))
        }

        if isCSV(text) {
            candidates.append(.init(kind: .csv, confidence: 0.74, evidence: "shape:csv"))
        }

        if text.range(of: #"(?m)^[A-Za-z_][A-Za-z0-9_]*=.+"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .environmentVariables, confidence: 0.82, evidence: "regex:env"))
        }

        return candidates
    }

    private func isJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else {
            return false
        }

        guard let data = text.data(using: .utf8) else {
            return false
        }

        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func isCSV(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else {
            return false
        }

        let commaCounts = lines.prefix(5).map { $0.filter { $0 == "," }.count }
        guard let first = commaCounts.first, first > 0 else {
            return false
        }

        return commaCounts.allSatisfy { $0 == first }
    }
}

private struct CodeTextDetector: ContentDetector {
    let id = "code-text"

    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate] {
        guard let text = input.trimmedText else {
            return []
        }

        var candidates: [ClassificationCandidate] = []

        if text.range(of: #"(?m)^(diff --git|@@|\+\+\+ |--- )"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .gitDiff, confidence: 0.94, evidence: "regex:git-diff"))
        }

        if text.range(of: #"(?m)(^\s*at\s+[\w.$]+\(.*:\d+\)|Thread \d+|Exception|fatal error|Traceback \(most recent call last\))"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .stackTrace, confidence: 0.88, evidence: "regex:stack-trace"))
        }

        if text.range(of: #"(?m)^\s*(git|npm|pnpm|yarn|swift|xcodebuild|curl|ssh|cd|ls|mkdir|rm|docker|kubectl)\b"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .shellCommand, confidence: 0.76, evidence: "regex:shell-command"))
        }

        if text.range(of: #"\b(func|let|var|class|struct|enum|import|package|const|function|return|if|else|for|while)\b"#, options: .regularExpression) != nil,
           text.range(of: #"[{}();]"#, options: .regularExpression) != nil {
            candidates.append(.init(kind: .sourceCode, confidence: 0.74, evidence: "regex:source-code"))
        }

        return candidates
    }
}

private extension ClassificationInput {
    var text: String? {
        String(data: data, encoding: .utf8)
    }

    var trimmedText: String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
