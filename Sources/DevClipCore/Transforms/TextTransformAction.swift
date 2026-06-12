import Foundation

struct TextTransformAction: TransformAction {
    enum Mode: String, CaseIterable, Sendable {
        case trim = "text.trim"
        case removeBlankLines = "text.removeBlankLines"
        case uniqueLines = "text.uniqueLines"
        case sortLines = "text.sortLines"
        case reverseLines = "text.reverseLines"
        case joinLines = "text.joinLines"
        case splitLines = "text.splitLines"
        case camelCase = "text.camelCase"
        case pascalCase = "text.pascalCase"
        case snakeCase = "text.snakeCase"
        case kebabCase = "text.kebabCase"
        case screamingSnakeCase = "text.screamingSnakeCase"
        case unicodeEscape = "text.unicodeEscape"
        case unicodeUnescape = "text.unicodeUnescape"
        case hexEncode = "text.hexEncode"
        case hexDecode = "text.hexDecode"
        case jsonEscape = "text.jsonEscape"
        case jsonUnescape = "text.jsonUnescape"
        case htmlEncode = "text.htmlEncode"
        case htmlDecode = "text.htmlDecode"
        case normalizeLF = "text.normalizeLF"
        case normalizeCRLF = "text.normalizeCRLF"
    }

    static let builtIns: [any TransformAction] = Mode.allCases.map(Self.init(mode:))

    let mode: Mode
    var id: String { mode.rawValue }

    var displayName: String {
        switch mode {
        case .trim: "去除首尾空白"
        case .removeBlankLines: "移除空行"
        case .uniqueLines: "行去重"
        case .sortLines: "行排序"
        case .reverseLines: "行反转"
        case .joinLines: "合并行"
        case .splitLines: "拆分行"
        case .camelCase: "转 camelCase"
        case .pascalCase: "转 PascalCase"
        case .snakeCase: "转 snake_case"
        case .kebabCase: "转 kebab-case"
        case .screamingSnakeCase: "转 SCREAMING_SNAKE_CASE"
        case .unicodeEscape: "Unicode 转义"
        case .unicodeUnescape: "Unicode 反转义"
        case .hexEncode: "Hex 编码"
        case .hexDecode: "Hex 解码"
        case .jsonEscape: "JSON 字符串转义"
        case .jsonUnescape: "JSON 字符串反转义"
        case .htmlEncode: "HTML 编码"
        case .htmlDecode: "HTML 解码"
        case .normalizeLF: "换行转 LF"
        case .normalizeCRLF: "换行转 CRLF"
        }
    }

    let category: TransformCategory = .text
    let acceptedInputKinds: [ClipboardContentKind] = [.plainText, .markdown, .sourceCode, .csv, .html, .xml, .json, .hex]
    let outputKind: ClipboardContentKind = .plainText
    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        input.effectiveText != nil && handlesKind(input.kind)
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        let text = try input.requireText()
        let output: String

        switch mode {
        case .trim:
            output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeBlankLines:
            output = lines(text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        case .uniqueLines:
            var seen: Set<String> = []
            output = lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .sortLines:
            output = lines(text).sorted().joined(separator: "\n")
        case .reverseLines:
            output = lines(text).reversed().joined(separator: "\n")
        case .joinLines:
            output = lines(text).joined(separator: options.string("separator", default: " "))
        case .splitLines:
            let separator = options.string("separator", default: ",").first ?? ","
            output = text.split(separator: separator).map(String.init).joined(separator: "\n")
        case .camelCase:
            output = caseWords(text).firstLowerRestUpper()
        case .pascalCase:
            output = caseWords(text).allUpperFirst()
        case .snakeCase:
            output = caseWords(text).map { $0.lowercased() }.joined(separator: "_")
        case .kebabCase:
            output = caseWords(text).map { $0.lowercased() }.joined(separator: "-")
        case .screamingSnakeCase:
            output = caseWords(text).map { $0.uppercased() }.joined(separator: "_")
        case .unicodeEscape:
            output = unicodeEscape(text)
        case .unicodeUnescape:
            output = unicodeUnescape(text)
        case .hexEncode:
            output = hexString(Data(text.utf8))
        case .hexDecode:
            output = try decodeHexText(text)
        case .jsonEscape:
            output = try jsonEscape(text)
        case .jsonUnescape:
            output = try jsonUnescape(text)
        case .htmlEncode:
            output = htmlEncode(text)
        case .htmlDecode:
            output = htmlDecode(text)
        case .normalizeLF:
            output = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        case .normalizeCRLF:
            let lf = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            output = lf.replacingOccurrences(of: "\n", with: "\r\n")
        }

        return textResult(output, outputKind: .plainText)
    }

    private func lines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private func caseWords(_ text: String) -> [String] {
        let expanded = text.replacingOccurrences(
            of: #"([a-z0-9])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return expanded
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func unicodeEscape(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            if scalar.value < 128 {
                return String(scalar)
            }

            return String(format: "\\u{%X}", scalar.value)
        }.joined()
    }

    private func unicodeUnescape(_ text: String) -> String {
        var output = text
        let pattern = #"\\u\{([0-9A-Fa-f]+)\}|\\u([0-9A-Fa-f]{4})"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() ?? []

        for match in matches {
            let hexRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard
                let range = Range(hexRange, in: text),
                let scalarValue = UInt32(text[range], radix: 16),
                let scalar = UnicodeScalar(scalarValue),
                let fullRange = Range(match.range, in: output)
            else {
                continue
            }

            output.replaceSubrange(fullRange, with: String(scalar))
        }

        return output
    }

    private func decodeHexText(_ text: String) throws -> String {
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard compact.count % 2 == 0, compact.range(of: #"^[0-9A-Fa-f]*$"#, options: .regularExpression) != nil else {
            throw DevClipError.invalidInput(reason: "Hex 文本无效。")
        }

        var data = Data()
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw DevClipError.invalidInput(reason: "Hex 文本无效。")
            }
            data.append(byte)
            index = next
        }

        guard let decoded = String(data: data, encoding: .utf8) else {
            throw DevClipError.invalidInput(reason: "Hex 解码结果不是有效 UTF-8。")
        }

        return decoded
    }

    private func jsonEscape(_ text: String) throws -> String {
        let data = try JSONEncoder().encode(text)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法 JSON 转义文本。")
        }

        return String(encoded.dropFirst().dropLast())
    }

    private func jsonUnescape(_ text: String) throws -> String {
        let quoted = "\"\(text)\""
        guard let data = quoted.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法读取 JSON 转义文本。")
        }

        return try JSONDecoder().decode(String.self, from: data)
    }

    private func htmlEncode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func htmlDecode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

private extension Array where Element == String {
    func firstLowerRestUpper() -> String {
        guard let first else {
            return ""
        }

        return first.lowercased() + dropFirst().map { $0.capitalized }.joined()
    }

    func allUpperFirst() -> String {
        map { $0.capitalized }.joined()
    }
}
