import Foundation

struct JSONTransformAction: TransformAction {
    enum Mode: String, Sendable {
        case validate = "json.validate"
        case prettyPrint = "json.prettyPrint"
        case minify = "json.minify"
        case sortKeys = "json.sortKeys"
        case escape = "json.escape"
        case unescape = "json.unescape"
    }

    static let builtIns: [any TransformAction] = [
        Self(mode: .validate),
        Self(mode: .prettyPrint),
        Self(mode: .minify),
        Self(mode: .sortKeys),
        Self(mode: .escape),
        Self(mode: .unescape)
    ]

    let mode: Mode
    var id: String { mode.rawValue }

    var displayName: String {
        switch mode {
        case .validate:
            "JSON 校验"
        case .prettyPrint:
            "JSON 格式化"
        case .minify:
            "JSON 压缩"
        case .sortKeys:
            "JSON 键排序"
        case .escape:
            "JSON 转义"
        case .unescape:
            "JSON 反转义"
        }
    }

    let category: TransformCategory = .json
    let acceptedInputKinds: [ClipboardContentKind] = [.plainText, .json]
    let outputKind: ClipboardContentKind = .json
    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        input.effectiveText != nil && handlesKind(input.kind)
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        let text = try input.requireText()

        switch mode {
        case .validate:
            _ = try parseJSON(text)
            return textResult("JSON 有效", outputKind: .plainText)
        case .prettyPrint:
            return try writeJSON(parseJSON(text), options: [.prettyPrinted])
        case .minify:
            return try writeJSON(parseJSON(text), options: [])
        case .sortKeys:
            return try writeJSON(sortKeys(parseJSON(text)), options: [.prettyPrinted, .sortedKeys])
        case .escape:
            return try textResult(escapeJSON(text), outputKind: .plainText)
        case .unescape:
            return try textResult(unescapeJSON(text), outputKind: .plainText)
        }
    }

    private func parseJSON(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "JSON 文本不是有效 UTF-8。")
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DevClipError.invalidInput(reason: "JSON 无效：\(error.localizedDescription)")
        }
    }

    private func writeJSON(_ object: Any, options: JSONSerialization.WritingOptions) throws -> TransformResult {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: options)
            let text = String(data: data, encoding: .utf8) ?? ""
            return TransformResult(outputKind: .json, data: data, previewText: text)
        } catch {
            throw DevClipError.invalidInput(reason: "无法写出 JSON：\(error.localizedDescription)")
        }
    }

    private func sortKeys(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var sorted: [String: Any] = [:]
            for key in dictionary.keys.sorted() {
                sorted[key] = sortKeys(dictionary[key] as Any)
            }
            return sorted
        }

        if let array = value as? [Any] {
            return array.map(sortKeys)
        }

        return value
    }

    private func escapeJSON(_ text: String) throws -> String {
        let data = try JSONEncoder().encode(text)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法 JSON 转义文本。")
        }

        return String(encoded.dropFirst().dropLast())
    }

    private func unescapeJSON(_ text: String) throws -> String {
        let quoted = "\"\(text)\""
        guard let data = quoted.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法读取 JSON 转义文本。")
        }

        do {
            return try JSONDecoder().decode(String.self, from: data)
        } catch {
            throw DevClipError.invalidInput(reason: "JSON 反转义失败：\(error.localizedDescription)")
        }
    }
}
