import Foundation

struct JWTTransformAction: TransformAction {
    enum Mode: String, Sendable {
        case decodeHeader = "jwt.decodeHeader"
        case decodePayload = "jwt.decodePayload"
        case inspectClaims = "jwt.inspectClaims"
    }

    static let builtIns: [any TransformAction] = [
        Self(mode: .decodeHeader),
        Self(mode: .decodePayload),
        Self(mode: .inspectClaims)
    ]

    let mode: Mode
    var id: String { mode.rawValue }

    var displayName: String {
        switch mode {
        case .decodeHeader:
            "JWT 解码 Header"
        case .decodePayload:
            "JWT 解码 Payload"
        case .inspectClaims:
            "JWT 查看 Claims"
        }
    }

    let category: TransformCategory = .jwt
    let acceptedInputKinds: [ClipboardContentKind] = [.plainText, .jwt]
    let outputKind: ClipboardContentKind = .json
    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        guard let text = input.effectiveText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        return handlesKind(input.kind) && text.split(separator: ".").count >= 2
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        _ = options
        let parts = try parts(from: input.requireText())

        switch mode {
        case .decodeHeader:
            return try jsonResult(from: decodeBase64URL(String(parts[0])), prefix: nil)
        case .decodePayload:
            return try jsonResult(from: decodeBase64URL(String(parts[1])), prefix: nil)
        case .inspectClaims:
            let header = try jsonObject(from: decodeBase64URL(String(parts[0])))
            let payload = try jsonObject(from: decodeBase64URL(String(parts[1])))
            let object: [String: Any] = [
                "header": header,
                "payload": payload,
                "notice": "已解析，但未验证签名"
            ]
            return try jsonResult(object: object, prefix: nil)
        }
    }

    private func parts(from text: String) throws -> [Substring] {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count >= 2 else {
            throw DevClipError.invalidInput(reason: "JWT 至少需要 Header 和 Payload 两段。")
        }

        return parts
    }

    private func decodeBase64URL(_ value: String) throws -> Data {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        switch normalized.count % 4 {
        case 0:
            break
        case 2:
            normalized.append("==")
        case 3:
            normalized.append("=")
        default:
            throw DevClipError.invalidInput(reason: "JWT Base64URL 长度无效。")
        }

        guard let data = Data(base64Encoded: normalized) else {
            throw DevClipError.invalidInput(reason: "JWT Base64URL 解码失败。")
        }

        return data
    }

    private func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DevClipError.invalidInput(reason: "JWT JSON 解析失败：\(error.localizedDescription)")
        }
    }

    private func jsonResult(from data: Data, prefix: String?) throws -> TransformResult {
        try jsonResult(object: jsonObject(from: data), prefix: prefix)
    }

    private func jsonResult(object: Any, prefix: String?) throws -> TransformResult {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? ""
        let preview = [prefix, json, "已解析，但未验证签名"].compactMap { $0 }.joined(separator: "\n")
        return TransformResult(
            outputKind: .json,
            data: data,
            previewText: preview,
            metadata: ClipboardMetadata(values: [
                "signatureVerified": "false",
                "warning": "已解析，但未验证签名"
            ])
        )
    }
}
