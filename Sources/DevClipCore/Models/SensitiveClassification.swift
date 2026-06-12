/// Sensitivity level that drives retention, indexing, logging, and export policy.
public enum SensitiveClassification: String, Codable, CaseIterable, Sendable {
    case none
    case potential
    case secret
}
