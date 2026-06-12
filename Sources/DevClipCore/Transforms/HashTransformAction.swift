import CryptoKit
import Foundation

struct HashTransformAction: TransformAction {
    enum Mode: String, Sendable {
        case sha256 = "hash.sha256"
        case sha512 = "hash.sha512"
        case sha1 = "hash.sha1"
        case md5 = "hash.md5"
        case hmacSHA256 = "hash.hmacSHA256"
    }

    static let builtIns: [any TransformAction] = [
        Self(mode: .sha256),
        Self(mode: .sha512),
        Self(mode: .sha1),
        Self(mode: .md5),
        Self(mode: .hmacSHA256)
    ]

    let mode: Mode
    var id: String { mode.rawValue }

    var displayName: String {
        switch mode {
        case .sha256:
            "SHA-256"
        case .sha512:
            "SHA-512"
        case .sha1:
            "SHA-1"
        case .md5:
            "MD5"
        case .hmacSHA256:
            "HMAC-SHA256"
        }
    }

    let category: TransformCategory = .hash
    let acceptedInputKinds: [ClipboardContentKind] = []
    let outputKind: ClipboardContentKind = .hash
    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        !input.data.isEmpty || input.effectiveText != nil
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        let data = input.data.isEmpty ? Data((input.effectiveText ?? "").utf8) : input.data
        let digest: String

        switch mode {
        case .sha256:
            digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha512:
            digest = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha1:
            digest = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .md5:
            digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .hmacSHA256:
            guard let key = options.values["key"], !key.isEmpty else {
                throw DevClipError.invalidInput(reason: "HMAC-SHA256 需要 key 选项。")
            }

            let symmetricKey = SymmetricKey(data: Data(key.utf8))
            digest = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
                .map { String(format: "%02x", $0) }
                .joined()
        }

        return textResult(digest, outputKind: .hash)
    }
}
