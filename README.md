# DevClip

面向重度开发者的本地优先、类型感知、键盘优先的 macOS 剪贴板工作台。

DevClip 保存剪贴板历史，同时针对开发者常见内容提供智能识别、全文搜索、格式转换、Diff 对比、顺序粘贴和敏感内容保护。所有核心操作在本地完成，不依赖网络。

## 功能特性

**剪贴板采集与管理** — 监听 NSPasteboard 变化，一次复制中的所有 item 和所有表示完整保存，支持文本、图片、文件列表等多种格式。自动去重，连续相同内容合并。

**内容类型识别** — 由多个小型 Detector 组合的分类器，首版支持 30+ 种开发者常见类型：plainText、url、email、json、jwt、base64、filePath、uuid、unixTimestamp、pem、privateKey、sourceCode、stackTrace、gitDiff 等。单个 Detector 失败不影响整体分类。

**敏感内容保护** — 独立敏感检测层，识别 API Key、Bearer Token、私钥、数据库连接串、高熵字符串等。secret 级内容默认只保存在内存，60 秒后清除，不进入全文索引、不写日志、不导出。

**全文搜索** — 基于 SQLite FTS5 trigram 分词器，支持子串匹配和结构化过滤（kind:、app:、since: 等）。1 万条数据搜索 P95 目标 50ms 以内。

**格式转换** — 内置 Base64（标准/URL Safe/Data URI）、JSON（validate/pretty/minify/sort/escape）、URL（encode/decode/inspect）、JWT（decode + 签名未验证提示）、Hash（SHA256/512/SHA1/MD5/HMAC）、时间（Unix/ISO8601 互转）、文本（排序/去重/转义/换行标准化等）。支持转换 pipeline 和超时取消。

**自动粘贴** — 可选能力，未启用时不请求辅助功能权限。支持原格式粘贴、纯文本粘贴和指定表示粘贴。失败时自动降级为 copyOnly，不丢失剪贴板内容。

**Quick Panel** — 全局快捷键呼出的浮动面板，输入即搜索，键盘全导航。支持 Return 粘贴、Cmd+Return 写回剪贴板、Cmd+K Action Panel、Cmd+P 固定、Cmd+D Diff、Space 预览、Escape 关闭并恢复原应用。

**更多能力** — Clipboard Stack 顺序粘贴、Diff 对比、Snippet 片段库、AES-GCM 加密导出/导入、开机启动。

## 技术栈

- Swift 6 strict concurrency
- SwiftUI + AppKit (NSPanel)
- Swift Package Manager
- GRDB (SQLite + FTS5 trigram)
- CryptoKit (AES-GCM)
- KeyboardShortcuts

## 项目结构

```
DevClip/
├── Package.swift
├── Sources/
│   ├── DevClip/           # macOS 可执行 app
│   │   ├── App/           # SwiftUI App 入口和 AppDelegate
│   │   ├── Views/         # SwiftUI 视图
│   │   ├── Support/       # ViewModel、控制器、依赖注入
│   │   └── Resources/     # 应用图标
│   └── DevClipCore/       # 核心逻辑库
│       ├── BlobStore/     # 图片和大二进制存储
│       ├── Classification/# 内容类型分类器
│       ├── Database/      # GRDB 数据库迁移和配置
│       ├── Diff/          # 文本 Diff 服务
│       ├── Export/        # AES-GCM 加密导出/导入
│       ├── Models/        # 数据模型
│       ├── Paste/         # 自动粘贴引擎
│       ├── Pasteboard/    # 剪贴板监听和写入保护
│       ├── Pipeline/      # 转换 Pipeline
│       ├── Repository/    # 数据持久化层
│       ├── Search/        # 搜索服务和查询解析
│       ├── Security/      # 敏感内容检测
│       ├── Snippets/      # 片段库
│       ├── Stack/         # 剪贴板栈
│       ├── Transforms/    # 格式转换引擎
│       └── Updates/       # 更新检查接口
├── Tests/
│   └── DevClipCoreTests/  # 核心逻辑单元测试（9 个套件，61 个用例）
├── docs/                  # 架构文档、产品规格、安全设计、路线图
└── script/                # 构建运行和发布检查脚本
```

## 构建和运行

### 环境要求

- macOS 14.0+
- Xcode 16+ 或 Swift 6.0+ 工具链

### 构建

```bash
swift build
```

### 测试

```bash
swift test
```

### 运行

```bash
./script/build_and_run.sh
```

## 架构设计

DevClip 采用 SwiftPM 多 Target 结构，`DevClip` 为 UI 层，`DevClipCore` 为纯逻辑库。系统 API 通过协议隔离，所有依赖可注入 Mock 进行单元测试。

并发模型遵循 Swift 6 严格并发规则：SwiftUI View 和 ViewModel 在 MainActor，Repository 和 Monitor 使用 actor，跨并发边界的数据模型满足 Sendable。AppKit 访问统一包装在 `MainActor.run` 中。

详细架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 安全与隐私

- 所有剪贴板内容本地处理，不上传网络
- secret 级内容不进索引、不写日志、不导出
- 自动粘贴需用户显式开启，无权限时降级为 copyOnly
- 加密导出使用 AES-GCM，导出自动排除敏感条目
- 密码管理器和钥匙串类来源应用默认忽略

详见 [docs/SECURITY.md](docs/SECURITY.md)。

## 许可证

本项目尚未选择开源许可证。
