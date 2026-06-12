import Foundation

enum BuiltInTransformActions {
    static let all: [any TransformAction] =
        Base64TransformAction.builtIns
        + JSONTransformAction.builtIns
        + URLTransformAction.builtIns
        + JWTTransformAction.builtIns
        + HashTransformAction.builtIns
        + DateTransformAction.builtIns
        + TextTransformAction.builtIns
}

extension TransformAction {
    func handlesKind(_ kind: ClipboardContentKind) -> Bool {
        acceptedInputKinds.isEmpty || acceptedInputKinds.contains(kind)
    }
}

extension TransformInput {
    var effectiveText: String? {
        if let text {
            return text
        }

        return String(data: data, encoding: .utf8)
    }

    func requireText() throws -> String {
        guard let text = effectiveText else {
            throw DevClipError.invalidInput(reason: "当前内容不是有效文本。")
        }

        return text
    }
}

extension TransformOptions {
    func string(_ key: String, default defaultValue: String) -> String {
        values[key] ?? defaultValue
    }

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let value = values[key]?.lowercased() else {
            return defaultValue
        }

        return ["1", "true", "yes", "on"].contains(value)
    }

    func int(_ key: String, default defaultValue: Int) -> Int {
        guard let value = values[key], let int = Int(value) else {
            return defaultValue
        }

        return int
    }
}

func textResult(
    _ text: String,
    outputKind: ClipboardContentKind = .plainText,
    metadata: ClipboardMetadata = ClipboardMetadata()
) -> TransformResult {
    TransformResult(
        outputKind: outputKind,
        data: Data(text.utf8),
        previewText: text,
        metadata: metadata
    )
}

func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

func previewForData(_ data: Data, metadata: [String: String] = [:]) -> TransformResult {
    var values = metadata

    if let text = String(data: data, encoding: .utf8) {
        values["previewKind"] = "text"
        return TransformResult(
            outputKind: .plainText,
            data: data,
            previewText: text,
            metadata: ClipboardMetadata(values: values)
        )
    }

    if let imageType = imageMimeType(for: data) {
        values["previewKind"] = "image"
        values["mimeType"] = imageType
        return TransformResult(
            outputKind: .image,
            data: data,
            previewText: "图片数据（\(data.count) 字节）",
            metadata: ClipboardMetadata(values: values)
        )
    }

    values["previewKind"] = "hex"
    return TransformResult(
        outputKind: .binary,
        data: data,
        previewText: hexPreview(data),
        metadata: ClipboardMetadata(values: values)
    )
}

func hexPreview(_ data: Data, maxBytes: Int = 64) -> String {
    let clipped = data.prefix(maxBytes)
    let suffix = data.count > maxBytes ? " ..." : ""
    return clipped.map { String(format: "%02x", $0) }.joined(separator: " ") + suffix
}

func imageMimeType(for data: Data) -> String? {
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
        return "image/png"
    }

    if data.starts(with: [0xFF, 0xD8, 0xFF]) {
        return "image/jpeg"
    }

    if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
        return "image/gif"
    }

    return nil
}

extension Data {
    func starts(with bytes: [UInt8]) -> Bool {
        guard count >= bytes.count else {
            return false
        }

        return prefix(bytes.count).elementsEqual(bytes)
    }
}
