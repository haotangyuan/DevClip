import Foundation
@testable import DevClipCore
import Testing

@Suite("Phase 5 Transform Tests")
struct Phase5TransformTests {
    @Test
    func base64StandardEncodeAndDecodeText() async throws {
        let engine = TransformEngine()

        let encoded = try await engine.execute(
            actionID: "base64.standard.encode",
            input: input("hello", kind: .plainText)
        )
        let decoded = try await engine.execute(
            actionID: "base64.standard.decode",
            input: input(encoded.previewText, kind: .base64)
        )

        #expect(encoded.previewText == "aGVsbG8=")
        #expect(decoded.previewText == "hello")
        #expect(encoded.metadata.values["warning"] == "Base64 是编码，不是加密")
    }

    @Test
    func base64URLSafeMissingPaddingAndUnicodeRoundTrip() async throws {
        let engine = TransformEngine()

        let encoded = try await engine.execute(
            actionID: "base64.urlSafe.encode",
            input: input("你好 DevClip", kind: .plainText),
            options: TransformOptions(values: ["padding": "false"])
        )
        let decoded = try await engine.execute(
            actionID: "base64.urlSafe.decode",
            input: input(encoded.previewText, kind: .base64)
        )

        #expect(!encoded.previewText.contains("="))
        #expect(decoded.previewText == "你好 DevClip")
    }

    @Test
    func base64EmptyBinaryAndInvalidInput() async throws {
        let engine = TransformEngine()
        let binary = Data([0x00, 0xFF, 0x10, 0x80])

        let empty = try await engine.execute(
            actionID: "base64.standard.decode",
            input: TransformInput(kind: .base64, data: Data(), text: "")
        )
        let encodedBinary = try await engine.execute(
            actionID: "base64.standard.encode",
            input: TransformInput(kind: .binary, data: binary)
        )
        let decodedBinary = try await engine.execute(
            actionID: "base64.standard.decode",
            input: input(encodedBinary.previewText, kind: .base64)
        )

        #expect(empty.data.isEmpty)
        #expect(decodedBinary.outputKind == .binary)
        #expect(decodedBinary.metadata.values["previewKind"] == "hex")

        await #expect(throws: DevClipError.invalidInput(reason: "Base64 长度模 4 等于 1，无法安全补齐。")) {
            _ = try await engine.execute(
                actionID: "base64.standard.decode",
                input: input("abcde", kind: .base64)
            )
        }
    }

    @Test
    func base64DataURIParsesMimeType() async throws {
        let engine = TransformEngine()
        let encoded = try await engine.execute(
            actionID: "base64.dataURI.encode",
            input: input("hello", kind: .plainText),
            options: TransformOptions(values: ["mimeType": "text/plain"])
        )
        let decoded = try await engine.execute(
            actionID: "base64.dataURI.decode",
            input: input(encoded.previewText, kind: .dataURI)
        )

        #expect(encoded.previewText == "data:text/plain;base64,aGVsbG8=")
        #expect(decoded.previewText == "hello")
        #expect(decoded.metadata.values["mimeType"] == "text/plain")
    }

    @Test
    func jsonTransformsValidatePrettyMinifySortEscape() async throws {
        let engine = TransformEngine()
        let json = #"{"b":2,"a":{"d":4,"c":3}}"#

        let validate = try await engine.execute(actionID: "json.validate", input: input(json, kind: .json))
        let pretty = try await engine.execute(actionID: "json.prettyPrint", input: input(json, kind: .json))
        let minified = try await engine.execute(actionID: "json.minify", input: input(pretty.previewText, kind: .json))
        let sorted = try await engine.execute(actionID: "json.sortKeys", input: input(json, kind: .json))
        let escaped = try await engine.execute(actionID: "json.escape", input: input("a\nb", kind: .plainText))
        let unescaped = try await engine.execute(actionID: "json.unescape", input: input(escaped.previewText, kind: .plainText))

        #expect(validate.previewText == "JSON 有效")
        #expect(pretty.previewText.contains("\n"))
        #expect(minified.previewText == json)
        #expect(sorted.previewText.range(of: #""a""#)!.lowerBound < sorted.previewText.range(of: #""b""#)!.lowerBound)
        #expect(escaped.previewText == #"a\nb"#)
        #expect(unescaped.previewText == "a\nb")
    }

    @Test
    func urlTransformsInspectAndSortQuery() async throws {
        let engine = TransformEngine()
        let url = "https://example.com/path?b=2&a=1"

        let encoded = try await engine.execute(actionID: "url.encode", input: input("a b", kind: .plainText))
        let decoded = try await engine.execute(actionID: "url.decode", input: input(encoded.previewText, kind: .plainText))
        let inspected = try await engine.execute(actionID: "url.inspectQuery", input: input(url, kind: .url))
        let sorted = try await engine.execute(actionID: "url.sortQuery", input: input(url, kind: .url))
        let markdown = try await engine.execute(actionID: "url.toMarkdownLink", input: input(url, kind: .url))
        let domain = try await engine.execute(actionID: "url.extractDomain", input: input(url, kind: .url))

        #expect(encoded.previewText == "a%20b")
        #expect(decoded.previewText == "a b")
        #expect(inspected.previewText.contains("a = 1"))
        #expect(sorted.previewText == "https://example.com/path?a=1&b=2")
        #expect(markdown.previewText == "[example.com](https://example.com/path?b=2&a=1)")
        #expect(domain.previewText == "example.com")
    }

    @Test
    func jwtTransformsDecodeAndWarnAboutSignature() async throws {
        let engine = TransformEngine()
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.signature"

        let header = try await engine.execute(actionID: "jwt.decodeHeader", input: input(jwt, kind: .jwt))
        let payload = try await engine.execute(actionID: "jwt.decodePayload", input: input(jwt, kind: .jwt))
        let claims = try await engine.execute(actionID: "jwt.inspectClaims", input: input(jwt, kind: .jwt))

        #expect(header.previewText.contains(#""alg" : "HS256""#))
        #expect(payload.previewText.contains(#""name" : "John Doe""#))
        #expect(claims.previewText.contains("已解析，但未验证签名"))
        #expect(claims.metadata.values["signatureVerified"] == "false")
    }

    @Test
    func hashTransformsReturnExpectedDigests() async throws {
        let engine = TransformEngine()

        let sha256 = try await engine.execute(actionID: "hash.sha256", input: input("hello", kind: .plainText))
        let md5 = try await engine.execute(actionID: "hash.md5", input: input("hello", kind: .plainText))
        let hmac = try await engine.execute(
            actionID: "hash.hmacSHA256",
            input: input("hello", kind: .plainText),
            options: TransformOptions(values: ["key": "secret"])
        )

        #expect(sha256.previewText == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(md5.previewText == "5d41402abc4b2a76b9719d911017c592")
        #expect(hmac.previewText.count == 64)
    }

    @Test
    func dateTransformsConvertUnixAndISO8601() async throws {
        let engine = TransformEngine()

        let iso = try await engine.execute(
            actionID: "date.unixSecondsToISO8601",
            input: input("0", kind: .unixTimestamp)
        )
        let seconds = try await engine.execute(
            actionID: "date.iso8601ToUnixSeconds",
            input: input("1970-01-01T00:00:01Z", kind: .isoDate)
        )
        let milliseconds = try await engine.execute(
            actionID: "date.iso8601ToUnixMilliseconds",
            input: input("1970-01-01T00:00:01Z", kind: .isoDate)
        )

        #expect(iso.previewText == "1970-01-01T00:00:00.000Z")
        #expect(seconds.previewText == "1")
        #expect(milliseconds.previewText == "1000")
    }

    @Test
    func textTransformsCoverLinesCasesEscapesAndNewlines() async throws {
        let engine = TransformEngine()

        let trimmed = try await engine.execute(actionID: "text.trim", input: input("  hello \n", kind: .plainText))
        let unique = try await engine.execute(actionID: "text.uniqueLines", input: input("b\na\nb", kind: .plainText))
        let snake = try await engine.execute(actionID: "text.snakeCase", input: input("hello DevClip", kind: .plainText))
        let unicode = try await engine.execute(actionID: "text.unicodeEscape", input: input("你好", kind: .plainText))
        let unicodeBack = try await engine.execute(actionID: "text.unicodeUnescape", input: input(unicode.previewText, kind: .plainText))
        let hex = try await engine.execute(actionID: "text.hexEncode", input: input("Hi", kind: .plainText))
        let hexBack = try await engine.execute(actionID: "text.hexDecode", input: input(hex.previewText, kind: .hex))
        let html = try await engine.execute(actionID: "text.htmlEncode", input: input("<a&b>", kind: .plainText))
        let htmlBack = try await engine.execute(actionID: "text.htmlDecode", input: input(html.previewText, kind: .html))
        let crlf = try await engine.execute(actionID: "text.normalizeCRLF", input: input("a\nb", kind: .plainText))

        #expect(trimmed.previewText == "hello")
        #expect(unique.previewText == "b\na")
        #expect(snake.previewText == "hello_dev_clip")
        #expect(unicodeBack.previewText == "你好")
        #expect(hex.previewText == "4869")
        #expect(hexBack.previewText == "Hi")
        #expect(html.previewText == "&lt;a&amp;b&gt;")
        #expect(htmlBack.previewText == "<a&b>")
        #expect(crlf.previewText == "a\r\nb")
    }

    @Test
    func engineReturnsSmartActionsAndRunsPipeline() async throws {
        let engine = TransformEngine()
        let input = input(" hello ", kind: .plainText)

        let smartActions = try await engine.smartActions(for: input)
        let pipeline = TransformPipeline(
            name: "文本流水线",
            steps: [
                TransformStep(actionID: "text.trim", order: 0),
                TransformStep(actionID: "text.screamingSnakeCase", order: 1)
            ]
        )
        let result = try await engine.execute(pipeline: pipeline, input: input)

        #expect(smartActions.contains { $0.id == "text.trim" })
        #expect(result.previewText == "HELLO")

        await #expect(throws: DevClipError.invalidInput(reason: "未知转换动作：missing.action。")) {
            _ = try await engine.execute(
                pipeline: TransformPipeline(name: "错误", steps: [TransformStep(actionID: "missing.action", order: 0)]),
                input: input
            )
        }
    }

    @Test
    func engineTimesOutLongRunningAction() async throws {
        let engine = TransformEngine(actions: [SlowAction()])

        await #expect(throws: DevClipError.timedOut(seconds: 0.01)) {
            _ = try await engine.execute(
                actionID: "test.slow",
                input: input("slow", kind: .plainText),
                options: TransformOptions(timeoutSeconds: 0.01)
            )
        }
    }
}

private struct SlowAction: TransformAction {
    let id = "test.slow"
    let displayName = "慢动作"
    let category: TransformCategory = .text
    let acceptedInputKinds: [ClipboardContentKind] = [.plainText]
    let outputKind: ClipboardContentKind = .plainText
    let isDestructive = false

    func canHandle(_ input: TransformInput) -> Bool {
        input.effectiveText != nil
    }

    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult {
        _ = input
        _ = options
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return textResult("done")
    }
}

private func input(_ text: String, kind: ClipboardContentKind) -> TransformInput {
    TransformInput(
        kind: kind,
        data: Data(text.utf8),
        text: text
    )
}
