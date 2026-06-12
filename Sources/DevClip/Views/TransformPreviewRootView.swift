import DevClipCore
import SwiftUI

struct TransformPreviewRootView: View {
    @StateObject private var viewModel: TransformPreviewViewModel

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: TransformPreviewViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { @MainActor in
                        await viewModel.saveSamplePipeline()
                    }
                } label: {
                    Label("保存示例流水线", systemImage: "plus")
                }
                .padding(.horizontal)
                .padding(.top)

                List(selection: $viewModel.selectedPipelineID) {
                    ForEach(viewModel.pipelines) { pipeline in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pipeline.name)
                                .lineLimit(1)
                            Text("\(pipeline.steps.count) 个步骤")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(pipeline.id))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("流水线")
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("输入记录", selection: $viewModel.selectedEntryID) {
                        ForEach(viewModel.entries) { entry in
                            Text(entry.title).tag(Optional(entry.id))
                        }
                    }
                    .frame(minWidth: 260)

                    Button {
                        Task { @MainActor in
                            await viewModel.runPreview()
                        }
                    } label: {
                        Label("运行预览", systemImage: "play")
                    }
                    .disabled(viewModel.selectedPipelineID == nil || viewModel.selectedEntryID == nil)

                    Spacer()
                }

                if let pipeline = viewModel.selectedPipeline {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pipeline.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        ForEach(pipeline.steps.sorted(by: { $0.order < $1.order })) { step in
                            Label(step.actionID, systemImage: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView("暂无流水线", systemImage: "wand.and.stars")
                }

                Divider()

                Text("预览结果")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.previewText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .devClipPanel()

                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(DevClipWorkspaceBackground())
        .task {
            await viewModel.load()
        }
    }
}

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
