import Foundation

struct Base64TransformAction: TransformAction {
    enum Mode: String, Sendable {
        case standardEncode = "base64.standard.encode"
        case standardDecode = "base64.standard.decode"
        case urlSafeEncode = "base64.urlSafe.encode"
        case urlSafeDecode = "base64.urlSafe.decode"
        case dataURIEncode = "base64.dataURI.encode"
        case dataURIDecode = "base64.dataURI.decode"
    }

    static let builtIns: [any TransformAction] = [
        Self(mode: .standardEncode),
        Self(mode: .standardDecode),
        Self(mode: .urlSafeEncode),
        Self(mode: .urlSafeDecode),
        Self(mode: .dataURIEncode),
        Self(mode: .dataURIDecode)
    ]

    let mode: Mode

    var id: String { mode.rawValue }

    var displayName: String {
        switch mode {
        case .standardEncode:
            "Base64 标准编码"
        case .standardDecode:
            "Base64 标准解码"
        case .urlSafeEncode:
            "Base64 URL Safe 编码"
        case .urlSafeDecode:
            "Base64 URL Safe 解码"
        case .dataURIEncode:
            "Data URI 编码"
        case .dataURIDecode:
            "Data URI 解码"
        }
    }

    let category: TransformCategory = .base64

    var acceptedInputKinds: [ClipboardContentKind] {
        [.plainText, .base64, .dataURI, .binary, .image]
    }

    var outputKind: ClipboardContentKind {
        switch mode {
        case .standardEncode, .urlSafeEncode:
            .base64
        case .dataURIEncode:
            .dataURI
        case .standardDecode, .urlSafeDecode, .dataURIDecode:
            .plainText
        }
    }

    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        switch mode {
        case .standardEncode, .urlSafeEncode, .dataURIEncode:
            true
        case .standardDecode, .urlSafeDecode:
            input.effectiveText != nil
        case .dataURIDecode:
            input.effectiveText?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .hasPrefix("data:") == true
        }
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        switch mode {
        case .standardEncode:
            return encode(input.data, urlSafe: false, outputKind: .base64, options: options)
        case .urlSafeEncode:
            return encode(input.data, urlSafe: true, outputKind: .base64, options: options)
        case .dataURIEncode:
            return dataURIEncode(input.data, options: options)
        case .standardDecode:
            return try decode(input.requireText(), urlSafe: false)
        case .urlSafeDecode:
            return try decode(input.requireText(), urlSafe: true)
        case .dataURIDecode:
            return try dataURIDecode(input.requireText())
        }
    }

    private func encode(
        _ data: Data,
        urlSafe: Bool,
        outputKind: ClipboardContentKind,
        options: TransformOptions
    ) -> TransformResult {
        var encoded = data.base64EncodedString()

        if urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }

        if !options.bool("padding", default: true) {
            encoded = encoded.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }

        encoded = wrap(encoded, width: options.int("lineWidth", default: 0))
        return textResult(
            encoded,
            outputKind: outputKind,
            metadata: ClipboardMetadata(values: [
                "warning": "Base64 是编码，不是加密"
            ])
        )
    }

    private func decode(_ text: String, urlSafe: Bool) throws -> TransformResult {
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        let data = try decodedData(from: compact, urlSafe: urlSafe)
        return previewForData(
            data,
            metadata: [
                "warning": "Base64 是编码，不是加密"
            ]
        )
    }

    private func dataURIEncode(_ data: Data, options: TransformOptions) -> TransformResult {
        let mimeType = options.string("mimeType", default: imageMimeType(for: data) ?? "application/octet-stream")
        let encoded = data.base64EncodedString()
        return textResult(
            "data:\(mimeType);base64,\(encoded)",
            outputKind: .dataURI,
            metadata: ClipboardMetadata(values: [
                "mimeType": mimeType,
                "warning": "Base64 是编码，不是加密"
            ])
        )
    }

    private func dataURIDecode(_ text: String) throws -> TransformResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let commaIndex = trimmed.firstIndex(of: ",") else {
            throw DevClipError.invalidInput(reason: "Data URI 缺少逗号分隔符。")
        }

        let header = String(trimmed[..<commaIndex])
        let payload = String(trimmed[trimmed.index(after: commaIndex)...])
        let mimeType = parseMimeType(from: header)

        let data: Data
        if header.lowercased().contains(";base64") {
            data = try decodedData(from: payload.components(separatedBy: .whitespacesAndNewlines).joined(), urlSafe: false)
        } else {
            guard let decoded = payload.removingPercentEncoding?.data(using: .utf8) else {
                throw DevClipError.invalidInput(reason: "Data URI 百分号编码无效。")
            }
            data = decoded
        }

        return previewForData(
            data,
            metadata: [
                "mimeType": mimeType,
                "warning": "Base64 是编码，不是加密"
            ]
        )
    }

    private func decodedData(from input: String, urlSafe: Bool) throws -> Data {
        guard !input.isEmpty else {
            return Data()
        }

        var normalized = input
        if urlSafe || input.contains("-") || input.contains("_") {
            normalized = normalized
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
        }

        switch normalized.count % 4 {
        case 0:
            break
        case 2:
            normalized.append("==")
        case 3:
            normalized.append("=")
        default:
            throw DevClipError.invalidInput(reason: "Base64 长度模 4 等于 1，无法安全补齐。")
        }

        guard let data = Data(base64Encoded: normalized) else {
            throw DevClipError.invalidInput(reason: "Base64 输入无效。")
        }

        return data
    }

    private func wrap(_ value: String, width: Int) -> String {
        guard [64, 76].contains(width), value.count > width else {
            return value
        }

        var lines: [String] = []
        var index = value.startIndex
        while index < value.endIndex {
            let end = value.index(index, offsetBy: width, limitedBy: value.endIndex) ?? value.endIndex
            lines.append(String(value[index..<end]))
            index = end
        }

        return lines.joined(separator: "\n")
    }

    private func parseMimeType(from header: String) -> String {
        let withoutPrefix = header.dropFirst("data:".count)
        let type = withoutPrefix.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        return type.isEmpty ? "text/plain" : type
    }
}
