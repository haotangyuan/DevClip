import DevClipCore
import SwiftUI

struct SettingsRootView: View {
    @StateObject private var viewModel: SettingsViewModel
    @AppStorage(UserDefaultsPasteAutomationPreferences.automaticPasteEnabledKey)
    private var isAutomaticPasteEnabled = false
    @AppStorage("privacy.maskSensitiveContent")
    private var masksSensitiveContent = true

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(dependencies: dependencies))
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            privacyTab
                .tabItem {
                    Label("隐私", systemImage: "lock.shield")
                }

            archiveTab
                .tabItem {
                    Label("导入导出", systemImage: "lock.doc")
                }

            maintenanceTab
                .tabItem {
                    Label("维护", systemImage: "wrench.and.screwdriver")
                }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 360)
        .background(DevClipWorkspaceBackground())
        .task {
            await viewModel.load()
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.statusMessage.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("启动与行为") {
                Toggle("开机自动启动", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { newValue in
                        Task { @MainActor in
                            await viewModel.setLaunchAtLogin(newValue)
                        }
                    }
                ))

                Toggle("选择后自动粘贴到前台应用", isOn: $isAutomaticPasteEnabled)
            }
        }
    }

    // MARK: - Privacy Tab

    private var privacyTab: some View {
        Form {
            Section("敏感内容") {
                Toggle("遮罩敏感内容", isOn: $masksSensitiveContent)

                Text("启用后，检测到可能包含密码、密钥等敏感信息的剪贴板内容将自动遮罩显示。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("导出安全") {
                Text("敏感记录默认不导出，导出文件使用 AES-GCM 加密保护。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Archive Tab

    private var archiveTab: some View {
        Form {
            Section("口令") {
                SecureField("导出 / 导入口令", text: $viewModel.archivePassphrase)
            }

            Section("加密导出") {
                TextField("导出文件路径", text: $viewModel.exportPath)

                Button {
                    Task { @MainActor in
                        await viewModel.exportArchive()
                    }
                } label: {
                    Label("加密导出", systemImage: "square.and.arrow.up")
                }
            }

            Section("解密导入") {
                TextField("导入文件路径", text: $viewModel.importPath)

                Button {
                    Task { @MainActor in
                        await viewModel.importArchive()
                    }
                } label: {
                    Label("解密导入", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    // MARK: - Maintenance Tab

    private var maintenanceTab: some View {
        Form {
            Section("更新") {
                LabeledContent("更新接口") {
                    Text(viewModel.updateStatus)
                        .foregroundStyle(.secondary)
                }
            }

            Section("搜索性能") {
                Button {
                    Task { @MainActor in
                        await viewModel.measureSearch()
                    }
                } label: {
                    Label("测量当前搜索性能", systemImage: "speedometer")
                }

                if !viewModel.performanceStatus.isEmpty {
                    Text(viewModel.performanceStatus)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}
