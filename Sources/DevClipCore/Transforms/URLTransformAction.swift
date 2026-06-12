import Foundation

struct URLTransformAction: TransformAction {
    enum Mode: String, Sendable {
        case encode = "url.encode"
        case decode = "url.decode"
        case inspectQuery = "url.inspectQuery"
        case sortQuery = "url.sortQuery"
        case toMarkdownLink = "url.toMarkdownLink"
        case extractDomain = "url.extractDomain"
    }

    static let builtIns: [any TransformAction] = [
        Self(mode: .encode),
        Self(mode: .decode),
        Self(mode: .inspectQuery),
        Self(mode: .sortQuery),
        Self(mode: .toMarkdownLink),
        Self(mode: .extractDomain)
    ]

    let mode: Mode
    var id: String { mode.rawValue }

    var displayName: String {
        switch mode {
        case .encode:
            "URL 编码"
        case .decode:
            "URL 解码"
        case .inspectQuery:
            "查看查询参数"
        case .sortQuery:
            "查询参数排序"
        case .toMarkdownLink:
            "转 Markdown 链接"
        case .extractDomain:
            "提取域名"
        }
    }

    let category: TransformCategory = .url
    let acceptedInputKinds: [ClipboardContentKind] = [.plainText, .url]
    let outputKind: ClipboardContentKind = .plainText
    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        input.effectiveText != nil && handlesKind(input.kind)
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        let text = try input.requireText().trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .encode:
            return textResult(percentEncode(text), outputKind: .plainText)
        case .decode:
            return textResult(text.removingPercentEncoding ?? text, outputKind: .plainText)
        case .inspectQuery:
            return try inspectQuery(text)
        case .sortQuery:
            return try sortQuery(text)
        case .toMarkdownLink:
            return try markdownLink(text, title: options.values["title"])
        case .extractDomain:
            return try textResult(parseURL(text).host(percentEncoded: false) ?? "", outputKind: .plainText)
        }
    }

    private func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private func inspectQuery(_ text: String) throws -> TransformResult {
        let components = try parseComponents(text)
        let items = components.queryItems ?? []
        let output = items.map { item in
            "\(item.name) = \(item.value ?? "")"
        }.joined(separator: "\n")

        return textResult(output, outputKind: .plainText)
    }

    private func sortQuery(_ text: String) throws -> TransformResult {
        var components = try parseComponents(text)
        components.queryItems = (components.queryItems ?? []).sorted {
            if $0.name == $1.name {
                return ($0.value ?? "") < ($1.value ?? "")
            }

            return $0.name < $1.name
        }

        guard let sorted = components.url?.absoluteString else {
            throw DevClipError.invalidInput(reason: "无法重建 URL。")
        }

        return textResult(sorted, outputKind: .url)
    }

    private func markdownLink(_ text: String, title: String?) throws -> TransformResult {
        let url = try parseURL(text)
        let label = title?.isEmpty == false ? title ?? "" : (url.host(percentEncoded: false) ?? text)
        return textResult("[\(label)](\(text))", outputKind: .markdown)
    }

    private func parseComponents(_ text: String) throws -> URLComponents {
        guard let components = URLComponents(string: text) else {
            throw DevClipError.invalidInput(reason: "URL 无效。")
        }

        return components
    }

    private func parseURL(_ text: String) throws -> URL {
        guard let url = URL(string: text), url.scheme != nil else {
            throw DevClipError.invalidInput(reason: "URL 无效。")
        }

        return url
    }
}
