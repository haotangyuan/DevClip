import DevClipCore
import SwiftUI

struct HistoryRootView: View {
    @StateObject private var viewModel: HistoryViewModel

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(dependencies: dependencies))
    }

    var body: some View {
        HStack(spacing: 0) {
            HistorySidebarView(viewModel: viewModel)
            Divider()
            HistoryListPaneView(viewModel: viewModel)
            Divider()
            HistoryDetailView(viewModel: viewModel)
        }
        .background(DevClipWorkspaceBackground())
        .frame(minWidth: 980, minHeight: 560)
        .task {
            await viewModel.load()
        }
    }
}
