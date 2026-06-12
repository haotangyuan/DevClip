import DevClipCore
import SwiftUI

enum ClipboardKindPresentation {
    static func iconName(_ kind: ClipboardContentKind) -> String {
        switch kind {
        case .url:
            "link"
        case .email:
            "envelope"
        case .filePath, .fileList:
            "folder"
        case .json, .xml, .html, .markdown, .csv, .sourceCode, .gitDiff:
            "curlybraces"
        case .image:
            "photo"
        case .privateKey, .pem:
            "key"
        case .jwt:
            "signature"
        case .base64, .hash, .hex:
            "number"
        default:
            "doc.text"
        }
    }

    static func displayName(_ kind: ClipboardContentKind) -> String {
        switch kind {
        case .plainText:
            "文本"
        case .url:
            "链接"
        case .email:
            "邮箱"
        case .filePath:
            "文件路径"
        case .json:
            "JSON"
        case .jwt:
            "JWT"
        case .base64:
            "Base64"
        case .dataURI:
            "Data URI"
        case .uuid:
            "UUID"
        case .unixTimestamp:
            "Unix 时间戳"
        case .isoDate:
            "ISO 日期"
        case .hex:
            "Hex"
        case .hash:
            "Hash"
        case .pem:
            "PEM"
        case .privateKey:
            "私钥"
        case .environmentVariables:
            "环境变量"
        case .shellCommand:
            "Shell 命令"
        case .xml:
            "XML"
        case .html:
            "HTML"
        case .markdown:
            "Markdown"
        case .csv:
            "CSV"
        case .color:
            "颜色"
        case .ipAddress:
            "IP 地址"
        case .gitCommit:
            "Git 提交"
        case .gitDiff:
            "Git Diff"
        case .stackTrace:
            "堆栈"
        case .sourceCode:
            "源码"
        case .image:
            "图片"
        case .fileList:
            "文件列表"
        case .binary:
            "二进制"
        }
    }

    static func categoryName(_ category: TransformCategory) -> String {
        switch category {
        case .base64:
            "Base64"
        case .json:
            "JSON"
        case .url:
            "URL"
        case .jwt:
            "JWT"
        case .hash:
            "Hash"
        case .date:
            "时间"
        case .text:
            "文本"
        }
    }
}
