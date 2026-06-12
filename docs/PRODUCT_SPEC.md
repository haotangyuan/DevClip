# DevClip 产品规格

## 产品定位

DevClip 是面向重度开发者的本地优先、类型感知、键盘优先的 macOS 剪贴板工作台。它保存剪贴板历史，同时针对开发者常见内容提供识别、搜索、转换、Diff、顺序粘贴和敏感内容保护。

## 设计假设

- 应用默认作为菜单栏应用运行，同时保留普通 macOS 窗口形态。
- 核心剪贴板内容、索引、转换和导出默认离线执行。
- Phase 0 只建立项目、架构、协议和空实现，不实现实际监听、转换或数据库持久化。
- 自动粘贴是显式开启能力。未启用时不请求辅助功能权限。
- 敏感内容默认保护优先于便利性，特别是 Token、私钥、密码和高熵密钥。

## 非目标

- 不做账号系统。
- 不做云同步。
- 不接入在线 AI。
- 不使用 Electron、Tauri 或 WebView 作为主界面。
- 不在 Phase 0 提前实现 Phase 1 之后的功能。

## 应用界面

- MenuBarExtra：入口、窗口打开、设置和退出。
- Quick Panel：全局快捷键呼出，输入即搜索，键盘导航，Action Panel，预览和删除。
- 完整历史管理窗口：历史、固定项、集合和详情。
- 设置窗口：启动项、快捷键、敏感内容策略、自动粘贴和导入导出。
- 转换结果预览窗口：转换前确认，不直接修改原记录。
- Diff 窗口：支持两条记录或转换前后对比。
- Clipboard Stack 窗口：管理顺序粘贴队列。

## Quick Panel 键盘契约

- 输入即搜索。
- 上下键切换。
- Return 按原格式粘贴。
- Command+Return 只写回剪贴板。
- Shift+Return 纯文本粘贴。
- Command+K 打开 Action Panel。
- Command+P 固定或取消固定。
- Command+D 进入 Diff 选择。
- Space 显示完整预览。
- Delete 删除。
- Escape 关闭并恢复原应用。
- Tab 在历史和 Action 之间切换。

## 核心内容类型

首版识别 plainText、url、email、filePath、json、jwt、base64、dataURI、uuid、unixTimestamp、isoDate、hex、hash、pem、privateKey、environmentVariables、shellCommand、xml、html、markdown、csv、color、ipAddress、gitCommit、gitDiff、stackTrace、sourceCode、image、fileList、binary。

分类器由多个小型 Detector 组成，返回类型、置信度和依据。单个 Detector 失败不得中断整体分类，同一内容允许多个候选，最高置信度写入 `detectedKind`，其他候选进入 metadata。

## 转换能力

内置转换按阶段进入：

- Base64：标准、URL Safe、Data URI 编解码，支持 padding、换行宽度、UTF-8/Hex/Image 预览和非法输入明确错误。
- JSON：validate、prettyPrint、minify、sortKeys、escape、unescape。
- URL：encode、decode、inspectQuery、sortQuery、toMarkdownLink、extractDomain。
- JWT：decodeHeader、decodePayload、inspectClaims，并显示“已解析，但未验证签名”。
- Hash：sha256、sha512、sha1、md5、hmacSHA256。
- 时间：Unix 秒/毫秒与 ISO8601 互转，当前时间戳。
- 文本：trim、去空行、去重、排序、大小写转换、Unicode/Hex/JSON/HTML 转义、换行标准化。

## 隐私和安全

- Clipboard 内容不上传。
- secret 级内容默认只进内存，60 秒后清除。
- potential 级内容默认遮罩，10 分钟后过期。
- secret 不进入全文索引、不写日志、不导出、不发送网络。
- 日志不得输出完整剪贴板正文。
- 密码管理器和钥匙串类来源应用默认忽略。

## 性能目标

- Quick Panel 热启动 P95 小于 100ms。
- 1 万条数据搜索 P95 小于 50ms。
- 普通文本采集小于 150ms。
- 空闲 CPU 平均小于 0.5%。
- 空闲内存目标小于 100MB。
- 数据库、解析、搜索、转换和图片处理不阻塞主线程。
