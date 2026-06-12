# DevClip Roadmap

## Phase 0：项目骨架

- 创建 SwiftPM 项目。
- 创建目录和文档。
- 配置 GRDB 与 KeyboardShortcuts 依赖。
- 创建模型、协议和明确的空实现。
- 创建 SwiftUI/MenuBarExtra/窗口骨架。
- 创建 AppKit Quick Panel 边界，不实现行为。
- 创建构建运行脚本和 Codex Run action。
- 运行构建和测试。
- 更新 `docs/IMPLEMENTATION_STATUS.md`。

验收：

- `swift build` 通过。
- `swift test` 通过。
- 尝试运行 `xcodebuild`，若本机缺少完整 Xcode，明确记录环境阻塞。
- 没有 Phase 1 行为实现。

## Phase 1：剪贴板采集基础

- 实现 `PasteboardClient` 和 `SystemPasteboardClient`。
- 实现 `ClipboardMonitor` 后台轮询，默认约 350ms。
- 实现 `ClipboardSnapshot` 的多 item、多 representation 采集。
- 实现前台应用记录。
- 实现稳定 Hash。
- 实现去重和连续相同内容合并。
- 实现 `ClipboardWriteGuard`。
- 实现内存 Repository。
- 编写 Clipboard 去重、WriteGuard、多 item 分组测试。

验收：

- 复制普通文本可进入内存仓储。
- 自写入不会被重新采集。
- 多 item 复制保持同一 group。
- 全部测试通过。

## Phase 2：SQLite/GRDB/Blob/FTS

- 建立 GRDB `DatabasePool`。
- 启用 WAL、Foreign Keys、Migrations 和 Prepared Statements。
- 创建所有数据库表。
- 创建 `clipboard_fts` FTS5 表。
- 实现 Blob Store。
- 图片写入 Blob Store 并生成缩略图。
- 删除记录时清理孤立 Blob。
- 编写迁移、Repository、FTS、Blob 清理测试。

验收：

- 数据可持久化并恢复。
- Binary Blob 不直接放进主数据库。
- 1 万条基础搜索性能开始建立基线。

## Phase 3：MenuBarExtra/Quick Panel/搜索/copyOnly

- 实现 Quick Panel AppKit 浮动面板。
- 实现焦点管理和原应用恢复。
- 接入 KeyboardShortcuts。
- 实现输入即搜索。
- 实现上下键、Return、Command+Return、Shift+Return、Delete、Escape、Tab。
- 实现 `SearchQueryParser`。
- 实现 FTS 搜索和短查询回退。
- 实现 copyOnly。

验收：

- Quick Panel 热启动 P95 小于 100ms 的基线可测。
- 搜索不会被用户输入破坏 FTS 语法。
- 没有辅助功能权限时 copyOnly 可用。

## Phase 4：内容识别和敏感保护

- 实现 Detector 组合式 `ContentClassifier`。
- 实现全部首版内容类型识别。
- 实现 `SensitiveContentDetector`。
- 实现忽略应用规则。
- 实现 potential 和 secret 过期策略。
- 实现日志脱敏策略。
- 编写分类和敏感内容测试。

验收：

- secret 不持久化、不索引、不导出。
- 密码管理器来源默认忽略。
- Detector 失败不影响整体分类。

## Phase 5：转换引擎和内置转换

- 实现 TransformEngine 注册、执行、取消、超时和结构化错误。
- 实现 Base64 所有 Action。
- 实现 JSON、URL、JWT、Hash、时间和文本转换。
- 实现转换结果预览。
- 用户确认后写入剪贴板，可选保存派生记录。
- 编写 Base64 边界、JSON、URL、JWT、时间戳和转换错误测试。

验收：

- Base64 标准、URL Safe、缺失 Padding、空输入、Unicode、二进制和非法输入测试通过。
- JWT UI 提示“已解析，但未验证签名”。
- UI 显示“Base64 是编码，不是加密”。

## Phase 6：自动粘贴

- 实现辅助功能权限检测和延迟请求。
- 实现前台应用保存和恢复。
- 实现 `pasteOriginal`、`pastePlainText`、`pasteSpecificRepresentation`。
- 使用 CGEvent 模拟 Command+V。
- 失败时保留内容在剪贴板并显示非阻塞提示。

验收：

- 未授权时自动降级为 copyOnly。
- 自动粘贴只在用户主动启用后请求权限。

## Phase 7：Stack/Diff/Pipeline/Snippets

- 实现 Clipboard Stack。
- 实现 Sequential Paste。
- 实现 Diff 选择和 Diff 窗口。
- 实现 TransformPipeline 编辑和执行。
- 实现 Snippets。
- 编写 Pipeline 中断和错误测试。

验收：

- 顺序粘贴状态可恢复。
- Pipeline 失败不会修改原记录。

## Phase 8：设置、导入导出、性能和发布准备

- 完成设置窗口。
- 实现 SMAppService 开机启动。
- 实现 AES-GCM 加密导出。
- 实现导入。
- 预留并验证 Sparkle 2 接口。
- 优化 Quick Panel、搜索、空闲 CPU 和内存。
- 准备签名、Notarization 和发布流程。

验收：

- 导出不包含 secret。
- 性能目标达成或有明确剩余风险。
- 发布前构建、测试、签名和启动项验证通过。
