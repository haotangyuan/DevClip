/// Type labels produced by classification and used by search and actions.
public enum ClipboardContentKind: String, Codable, CaseIterable, Sendable {
    case plainText
    case url
    case email
    case filePath
    case json
    case jwt
    case base64
    case dataURI
    case uuid
    case unixTimestamp
    case isoDate
    case hex
    case hash
    case pem
    case privateKey
    case environmentVariables
    case shellCommand
    case xml
    case html
    case markdown
    case csv
    case color
    case ipAddress
    case gitCommit
    case gitDiff
    case stackTrace
    case sourceCode
    case image
    case fileList
    case binary
}
