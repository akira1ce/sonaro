import SwiftUI

/// Generic view that handles loading, error, and empty states consistently
/// across the app. Content is rendered when data is available.
struct AsyncContentView<Data: RandomAccessCollection, Content: View, Empty: View>: View
where Data.Element: Identifiable {
    let data: Data
    let isLoading: Bool
    let error: String?
    let emptyMessage: String
    let emptyIcon: String
    let onRetry: (() async -> Void)?
    let hasCustomEmpty: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let empty: () -> Empty

    init(
        data: Data,
        isLoading: Bool,
        error: String?,
        emptyMessage: String = "暂无内容",
        emptyIcon: String = "music.note",
        onRetry: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder empty: @escaping () -> Empty
    ) {
        self.data = data
        self.isLoading = isLoading
        self.error = error
        self.emptyMessage = emptyMessage
        self.emptyIcon = emptyIcon
        self.onRetry = onRetry
        self.hasCustomEmpty = !(Empty.self is EmptyView.Type)
        self.content = content
        self.empty = empty
    }

    var body: some View {
        Group {
            if isLoading, data.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .padding(.top, 32)
            } else if let error, data.isEmpty {
                InfoState(
                    icon: "wifi.exclamationmark",
                    title: "加载失败",
                    message: error,
                    actionTitle: onRetry != nil ? "重试" : nil,
                    action: onRetry.map { retry in { Task { await retry() } } }
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else if data.isEmpty {
                if hasCustomEmpty {
                    empty()
                } else {
                    InfoState(
                        icon: emptyIcon,
                        title: emptyMessage
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                }
            } else {
                content()
            }
        }
    }
}

// MARK: - Convenience initializer with no custom empty view

extension AsyncContentView where Empty == EmptyView {
    init(
        data: Data,
        isLoading: Bool,
        error: String?,
        emptyMessage: String = "暂无内容",
        emptyIcon: String = "music.note",
        onRetry: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            data: data,
            isLoading: isLoading,
            error: error,
            emptyMessage: emptyMessage,
            emptyIcon: emptyIcon,
            onRetry: onRetry,
            content: content,
            empty: { EmptyView() }
        )
    }
}
