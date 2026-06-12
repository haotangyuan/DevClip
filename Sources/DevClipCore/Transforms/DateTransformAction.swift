import Foundation

struct DateTransformAction: TransformAction {
    enum Mode: String, Sendable {
        case unixSecondsToISO8601 = "date.unixSecondsToISO8601"
        case unixMillisecondsToISO8601 = "date.unixMillisecondsToISO8601"
        case iso8601ToUnixSeconds = "date.iso8601ToUnixSeconds"
        case iso8601ToUnixMilliseconds = "date.iso8601ToUnixMilliseconds"
        case currentUnixTimestamp = "date.currentUnixTimestamp"
        case currentISO8601 = "date.currentISO8601"
    }

    static let builtIns: [any TransformAction] = [
        Self(mode: .unixSecondsToISO8601),
        Self(mode: .unixMillisecondsToISO8601),
        Self(mode: .iso8601ToUnixSeconds),
        Self(mode: .iso8601ToUnixMilliseconds),
        Self(mode: .currentUnixTimestamp),
        Self(mode: .currentISO8601)
    ]

    let mode: Mode
    var id: String { mode.rawValue }

    var displayName: String {
        switch mode {
        case .unixSecondsToISO8601:
            "Unix 秒转 ISO8601"
        case .unixMillisecondsToISO8601:
            "Unix 毫秒转 ISO8601"
        case .iso8601ToUnixSeconds:
            "ISO8601 转 Unix 秒"
        case .iso8601ToUnixMilliseconds:
            "ISO8601 转 Unix 毫秒"
        case .currentUnixTimestamp:
            "当前 Unix 时间戳"
        case .currentISO8601:
            "当前 ISO8601"
        }
    }

    let category: TransformCategory = .date
    let acceptedInputKinds: [ClipboardContentKind] = [.plainText, .unixTimestamp, .isoDate]
    let outputKind: ClipboardContentKind = .plainText
    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        switch mode {
        case .currentUnixTimestamp, .currentISO8601:
            true
        default:
            input.effectiveText != nil && handlesKind(input.kind)
        }
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        _ = options
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        switch mode {
        case .unixSecondsToISO8601:
            let value = try double(input.requireText())
            return textResult(formatter.string(from: Date(timeIntervalSince1970: value)), outputKind: .isoDate)
        case .unixMillisecondsToISO8601:
            let value = try double(input.requireText()) / 1000
            return textResult(formatter.string(from: Date(timeIntervalSince1970: value)), outputKind: .isoDate)
        case .iso8601ToUnixSeconds:
            let date = try parseISO8601(input.requireText())
            return textResult(String(Int(date.timeIntervalSince1970)), outputKind: .unixTimestamp)
        case .iso8601ToUnixMilliseconds:
            let date = try parseISO8601(input.requireText())
            return textResult(String(Int(date.timeIntervalSince1970 * 1000)), outputKind: .unixTimestamp)
        case .currentUnixTimestamp:
            return textResult(String(Int(Date().timeIntervalSince1970)), outputKind: .unixTimestamp)
        case .currentISO8601:
            return textResult(formatter.string(from: Date()), outputKind: .isoDate)
        }
    }

    private func double(_ text: String) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DevClipError.invalidInput(reason: "时间戳不是数字。")
        }

        return value
    }

    private func parseISO8601(_ text: String) throws -> Date {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFraction.date(from: trimmed) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmed) {
            return date
        }

        throw DevClipError.invalidInput(reason: "ISO8601 日期无效。")
    }
}
