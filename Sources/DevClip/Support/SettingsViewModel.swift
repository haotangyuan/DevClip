import DevClipCore
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var launchAtLoginEnabled = false
    @Published var exportPath: String
    @Published var importPath: String
    @Published var archivePassphrase = ""
    @Published private(set) var statusMessage = ""
    @Published private(set) var updateStatus = ""
    @Published private(set) var performanceStatus = ""

    private let launchAtLoginClient: any LaunchAtLoginClient
    private let archiveService: any ClipboardArchiveService
    private let archiveFileClient: any ClipboardArchiveFileClient
    private let updateClient: any UpdateCheckingClient
    private let searchPerformanceProbe: SearchPerformanceProbe

    init(dependencies: DependencyContainer) {
        self.launchAtLoginClient = dependencies.launchAtLoginClient
        self.archiveService = dependencies.archiveService
        self.archiveFileClient = dependencies.archiveFileClient
        self.updateClient = dependencies.updateClient
        self.searchPerformanceProbe = dependencies.searchPerformanceProbe

        let defaultURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("DevClip-Export.json")
        self.exportPath = defaultURL.path
        self.importPath = defaultURL.path
    }

    func load() async {
        launchAtLoginEnabled = await launchAtLoginClient.isEnabled()
        let status = await updateClient.integrationStatus()
        updateStatus = status.note
    }

    func setLaunchAtLogin(_ isEnabled: Bool) async {
        do {
            try await launchAtLoginClient.setEnabled(isEnabled)
            launchAtLoginEnabled = await launchAtLoginClient.isEnabled()
            statusMessage = launchAtLoginEnabled ? "已开启开机启动" : "已关闭开机启动"
        } catch {
            launchAtLoginEnabled = await launchAtLoginClient.isEnabled()
            statusMessage = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    func exportArchive() async {
        do {
            let result = try await archiveService.exportEncrypted(passphrase: archivePassphrase)
            try await archiveFileClient.write(result.archive, to: url(from: exportPath))
            statusMessage = "已导出 \(result.summary.exportedEntryCount) 条，跳过敏感记录 \(result.summary.skippedSensitiveCount) 条"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func importArchive() async {
        do {
            let archive = try await archiveFileClient.read(from: url(from: importPath))
            let summary = try await archiveService.importEncrypted(
                archive,
                passphrase: archivePassphrase
            )
            statusMessage = "已导入 \(summary.importedEntryCount) 条记录"
        } catch {
            statusMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func measureSearch() async {
        do {
            let measurement = try await searchPerformanceProbe.measure(
                query: SearchQuery(terms: ["common"])
            )
            let milliseconds = measurement.elapsedSeconds * 1000
            performanceStatus = String(
                format: "当前库 %d 条，搜索 %.2f ms，结果 %d 条",
                measurement.entryCount,
                milliseconds,
                measurement.resultCount
            )
        } catch {
            performanceStatus = "性能测量失败：\(error.localizedDescription)"
        }
    }

    private func url(from path: String) -> URL {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
        }

        return URL(fileURLWithPath: path)
    }
}
