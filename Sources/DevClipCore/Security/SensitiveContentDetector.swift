import Foundation

public struct SensitiveDetectionResult: Equatable, Sendable {
    public var classification: SensitiveClassification
    public var evidence: [String]
    public var expiresAt: Date?
    public var shouldIndex: Bool
    public var shouldPersist: Bool
    public var shouldRetainInMemory: Bool

    public init(
        classification: SensitiveClassification,
        evidence: [String] = [],
        expiresAt: Date? = nil,
        shouldIndex: Bool = true,
        shouldPersist: Bool = true,
        shouldRetainInMemory: Bool = false
    ) {
        self.classification = classification
        self.evidence = evidence
        self.expiresAt = expiresAt
        self.shouldIndex = shouldIndex
        self.shouldPersist = shouldPersist
        self.shouldRetainInMemory = shouldRetainInMemory
    }
}

public protocol SensitiveContentDetecting: Sendable {
    func detect(_ input: ClassificationInput, sourceBundleIdentifier: String?) async throws -> SensitiveDetectionResult
}

public struct IgnoredSourceApplicationPolicy: Equatable, Sendable {
    public var ignoredBundleIdentifiers: Set<String>
    public var ignoredBundleIdentifierFragments: Set<String>

    public init(
        ignoredBundleIdentifiers: Set<String> = Self.defaultBundleIdentifiers,
        ignoredBundleIdentifierFragments: Set<String> = Self.defaultBundleIdentifierFragments
    ) {
        self.ignoredBundleIdentifiers = ignoredBundleIdentifiers
        self.ignoredBundleIdentifierFragments = ignoredBundleIdentifierFragments
    }

    public func shouldIgnore(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        let normalized = bundleIdentifier.lowercased()
        if ignoredBundleIdentifiers.contains(normalized) {
            return true
        }

        return ignoredBundleIdentifierFragments.contains { normalized.contains($0) }
    }

    public static let defaultBundleIdentifiers: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.lastpass.lastpassmacdesktop"
    ]

    public static let defaultBundleIdentifierFragments: Set<String> = [
        "1password",
        "bitwarden",
        "lastpass",
        "keepass",
        "dashlane",
        "password",
        "keychain"
    ]
}

/// Offline detector for tokens, keys, passwords, and high-risk source apps.
public struct DefaultSensitiveContentDetector: SensitiveContentDetecting {
    private let ignoredSourcePolicy: IgnoredSourceApplicationPolicy
    private let clock: @Sendable () -> Date

    public init(
        ignoredSourcePolicy: IgnoredSourceApplicationPolicy = IgnoredSourceApplicationPolicy(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.ignoredSourcePolicy = ignoredSourcePolicy
        self.clock = clock
    }

    public func detect(
        _ input: ClassificationInput,
        sourceBundleIdentifier: String?
    ) async throws -> SensitiveDetectionResult {
        if ignoredSourcePolicy.shouldIgnore(bundleIdentifier: sourceBundleIdentifier) {
            return secretResult(
                evidence: ["source_app_ignored"],
                retainInMemory: false
            )
        }

        guard let text = String(data: input.data, encoding: .utf8) else {
            return SensitiveDetectionResult(classification: .none)
        }

        let evidence = Self.findEvidence(in: text)
        if evidence.contains(where: Self.isSecretEvidence) {
            return secretResult(evidence: evidence.filter(Self.isSecretEvidence))
        }

        let potentialEvidence = evidence.filter { !Self.isSecretEvidence($0) }
        if !potentialEvidence.isEmpty {
            return potentialResult(evidence: potentialEvidence)
        }

        return SensitiveDetectionResult(classification: .none)
    }

    private func potentialResult(evidence: [String]) -> SensitiveDetectionResult {
        SensitiveDetectionResult(
            classification: .potential,
            evidence: evidence,
            expiresAt: clock().addingTimeInterval(10 * 60),
            shouldIndex: true,
            shouldPersist: true,
            shouldRetainInMemory: false
        )
    }

    private func secretResult(
        evidence: [String],
        retainInMemory: Bool = true
    ) -> SensitiveDetectionResult {
        SensitiveDetectionResult(
            classification: .secret,
            evidence: evidence,
            expiresAt: clock().addingTimeInterval(60),
            shouldIndex: false,
            shouldPersist: false,
            shouldRetainInMemory: retainInMemory
        )
    }

    private static func findEvidence(in text: String) -> [String] {
        var evidence: [String] = []

        appendEvidence("pem_private_key", to: &evidence, if: text.matches(#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#))
        appendEvidence("bearer_token", to: &evidence, if: text.matches(#"(?i)\bBearer\s+[A-Za-z0-9._~+/\-]+=*"#))
        appendEvidence("jwt", to: &evidence, if: text.matches(#"\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#))
        appendEvidence("aws_access_key", to: &evidence, if: text.matches(#"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#))
        appendEvidence("github_token", to: &evidence, if: text.matches(#"\b(gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{20,})\b"#))
        appendEvidence("database_connection_secret", to: &evidence, if: text.matches(#"[A-Za-z][A-Za-z0-9+.-]*://[^:\s/@]+:[^@\s/]+@"#))
        appendEvidence("named_secret_assignment", to: &evidence, if: text.matches(#"(?i)\b(api[_-]?key|secret|token|password|passwd|pwd|client_secret)\b\s*[:=]\s*['"]?[A-Za-z0-9._~+/\-=$]{8,}"#))
        appendEvidence("env_secret", to: &evidence, if: text.matches(#"(?im)^[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY)[A-Z0-9_]*=.+"#))
        appendEvidence("verification_code", to: &evidence, if: text.matches(#"(?i)\b(code|验证码|verification)\D{0,12}\d{4,8}\b"#) || text.matches(#"^\d{6}$"#))

        if hasHighEntropyToken(in: text) {
            evidence.append("high_entropy_string")
        }

        return Array(Set(evidence)).sorted()
    }

    private static func appendEvidence(
        _ value: String,
        to evidence: inout [String],
        if condition: Bool
    ) {
        if condition {
            evidence.append(value)
        }
    }

    private static func isSecretEvidence(_ evidence: String) -> Bool {
        [
            "aws_access_key",
            "bearer_token",
            "database_connection_secret",
            "env_secret",
            "github_token",
            "jwt",
            "named_secret_assignment",
            "pem_private_key"
        ].contains(evidence)
    }

    private static func hasHighEntropyToken(in text: String) -> Bool {
        let tokens = text
            .split { character in
                character.isWhitespace || character == "\"" || character == "'" || character == "`"
            }
            .map(String.init)

        return tokens.contains { token in
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]{}<>"))
            guard trimmed.count >= 32 else {
                return false
            }

            return entropy(trimmed) >= 4.25
        }
    }

    private static func entropy(_ value: String) -> Double {
        let scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty else {
            return 0
        }

        let counts = Dictionary(grouping: scalars, by: { $0 }).mapValues(\.count)
        let length = Double(scalars.count)

        return counts.values.reduce(0) { partial, count in
            let probability = Double(count) / length
            return partial - probability * log2(probability)
        }
    }
}

public typealias PlaceholderSensitiveContentDetector = DefaultSensitiveContentDetector

private extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
