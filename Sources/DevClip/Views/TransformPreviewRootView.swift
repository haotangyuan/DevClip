import DevClipCore
import SwiftUI

struct TransformPreviewRootView: View {
    @StateObject private var viewModel: TransformPreviewViewModel

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: TransformPreviewViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DevClipSectionHeader(title: "流水线", systemImage: "wand.and.stars")
                Spacer()
                Button {
                    Task { @MainActor in
                        await viewModel.saveSamplePipeline()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("保存示例流水线")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List(selection: $viewModel.selectedPipelineID) {
                ForEach(viewModel.pipelines) { pipeline in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                            Text(pipeline.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                        Text("\(pipeline.steps.count) 个步骤")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(pipeline.id))
                    .padding(.vertical, 2)
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.pipelines.isEmpty {
                    ContentUnavailableView("暂无流水线", systemImage: "wand.and.stars")
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    DevClipSectionHeader(title: "输入记录", systemImage: "doc.text")
                    Picker("", selection: $viewModel.selectedEntryID) {
                        ForEach(viewModel.entries) { entry in
                            Text(entry.title).tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 240)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("").font(.system(size: 13))
                    Button {
                        Task { @MainActor in
                            await viewModel.runPreview()
                        }
                    } label: {
                        Label("运行预览", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(viewModel.selectedPipelineID == nil || viewModel.selectedEntryID == nil)
                }

                Spacer()
            }
            .padding(16)

            Divider()

            // Pipeline steps
            if let pipeline = viewModel.selectedPipeline {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text(pipeline.name)
                        .font(.system(size: 13, weight: .semibold))

                    Divider().frame(height: 12)

                    HStack(spacing: 4) {
                        ForEach(pipeline.steps.sorted(by: { $0.order < $1.order })) { step in
                            Text(step.actionID)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(.quaternary)
                                )
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            } else {
                HStack {
                    Spacer()
                    ContentUnavailableView("暂无流水线", systemImage: "wand.and.stars")
                    Spacer()
                }
                .padding(20)
            }

            Divider()

            // Preview result
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    DevClipSectionHeader(title: "预览结果", systemImage: "eye")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView {
                    Text(viewModel.previewText.isEmpty ? "点击「运行预览」查看转换结果" : viewModel.previewText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(viewModel.previewText.isEmpty ? .tertiary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }

            // Status bar
            if !viewModel.statusMessage.isEmpty {
                Divider()
                HStack {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.thinMaterial.opacity(0.5))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - View Model

@MainActor
final class TransformPreviewViewModel: ObservableObject {
    @Published private(set) var pipelines: [TransformPipeline] = []
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var selectedPipelineID: UUID?
    @Published var selectedEntryID: UUID?
    @Published private(set) var previewText = ""
    @Published private(set) var statusMessage = ""

    private let repository: any ClipboardRepository
    private let pipelineStore: any TransformPipelineStore
    private let previewService: PipelinePreviewService

    init(dependencies: DependencyContainer) {
        self.repository = dependencies.repository
        self.pipelineStore = dependencies.transformPipelineStore
        self.previewService = dependencies.pipelinePreviewService
    }

    var selectedPipeline: TransformPipeline? {
        guard let selectedPipelineID else {
            return nil
        }

        return pipelines.first { $0.id == selectedPipelineID }
    }

    func load() async {
        do {
            entries = Array(try await repository.entries().reversed())
            pipelines = try await pipelineStore.pipelines()
            selectedEntryID = entries.first?.id
            selectedPipelineID = pipelines.first?.id
            statusMessage = pipelines.isEmpty ? "暂无流水线，可先保存示例" : "\(pipelines.count) 条流水线"
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    func saveSamplePipeline() async {
        let pipeline = TransformPipeline(
            name: "清理文本",
            steps: [
                TransformStep(actionID: "text.trim", order: 0),
                TransformStep(actionID: "text.removeBlankLines", order: 1)
            ]
        )

        do {
            try await pipelineStore.save(pipeline)
            pipelines = try await pipelineStore.pipelines()
            selectedPipelineID = pipeline.id
            statusMessage = "已保存示例流水线"
        } catch {
            statusMessage = "保存流水线失败：\(error.localizedDescription)"
        }
    }

    func runPreview() async {
        guard let pipeline = selectedPipeline, let selectedEntryID else {
            statusMessage = "请选择流水线和输入记录"
            return
        }

        do {
            let result = try await previewService.preview(
                pipeline: pipeline,
                entryID: selectedEntryID
            )
            previewText = result.previewText
            statusMessage = "预览完成，原记录未修改"
        } catch {
            previewText = ""
            statusMessage = "预览失败：\(error.localizedDescription)"
        }
    }
}
