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
            Form {
                Toggle(
                    "开机启动",
                    isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: { newValue in
                            Task { @MainActor in
                                await viewModel.setLaunchAtLogin(newValue)
                            }
                        }
                    )
                )
                Toggle("自动粘贴", isOn: $isAutomaticPasteEnabled)
            }
            .padding(20)
            .tabItem {
                Label("通用", systemImage: "gear")
            }

            Form {
                Toggle("遮罩敏感内容", isOn: $masksSensitiveContent)
                Text("secret 记录默认不导出，导出文件使用 AES-GCM 加密。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem {
                Label("隐私", systemImage: "lock")
            }

            Form {
                SecureField("导入口令 / 导出口令", text: $viewModel.archivePassphrase)

                TextField("导出路径", text: $viewModel.exportPath)
                Button {
                    Task { @MainActor in
                        await viewModel.exportArchive()
                    }
                } label: {
                    Label("加密导出", systemImage: "square.and.arrow.up")
                }

                Divider()

                TextField("导入路径", text: $viewModel.importPath)
                Button {
                    Task { @MainActor in
                        await viewModel.importArchive()
                    }
                } label: {
                    Label("解密导入", systemImage: "square.and.arrow.down")
                }
            }
            .padding(20)
            .tabItem {
                Label("导入导出", systemImage: "lock.doc")
            }

            Form {
                LabeledContent("更新接口") {
                    Text(viewModel.updateStatus)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { @MainActor in
                        await viewModel.measureSearch()
                    }
                } label: {
                    Label("测量当前搜索", systemImage: "speedometer")
                }

                if !viewModel.performanceStatus.isEmpty {
                    Text(viewModel.performanceStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .tabItem {
                Label("维护", systemImage: "wrench.and.screwdriver")
            }
        }
        .frame(width: 620, height: 380)
        .background(DevClipWorkspaceBackground())
        .task {
            await viewModel.load()
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }
}
