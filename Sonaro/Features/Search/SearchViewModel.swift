import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    typealias Search = @MainActor (_ keywords: String, _ limit: Int, _ offset: Int) async throws -> SongSearchPage

    @Published var query = ""
    @Published private(set) var songs: [Song] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var hasSearched = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var error: String?

    private let pageSize: Int
    private let debounceDuration: Duration
    private let search: Search
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    private var nextOffset = 0
    private var activeKeyword = ""

    init(
        pageSize: Int = 30,
        debounceDuration: Duration = .milliseconds(600),
        search: @escaping Search = { keywords, limit, offset in
            try await MusicService.searchSongs(keywords: keywords, limit: limit, offset: offset)
        }
    ) {
        self.pageSize = pageSize
        self.debounceDuration = debounceDuration
        self.search = search
    }

    var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func scheduleSearch() {
        // Whitespace edits do not invalidate results or restart the debounce.
        guard normalizedQuery != activeKeyword else { return }
        let keyword = beginNewSearch()
        guard !keyword.isEmpty else { return }
        let requestGeneration = generation

        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounceDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await fetch(keyword: keyword, offset: 0, replacing: true, generation: requestGeneration)
        }
    }

    func searchNow() async {
        // Return submits a pending debounce immediately, but does not repeat a
        // request already running or a successful search for the same keyword.
        if normalizedQuery == activeKeyword,
           (requestTask != nil && isLoading) || (hasSearched && error == nil) {
            return
        }
        let keyword = beginNewSearch()
        guard !keyword.isEmpty else { return }
        await fetch(keyword: keyword, offset: 0, replacing: true, generation: generation)
    }

    func loadMoreIfNeeded(current song: Song) async {
        guard song.id == songs.last?.id,
              canLoadMore,
              !isLoading,
              normalizedQuery == activeKeyword else { return }

        let requestGeneration = generation
        await fetch(
            keyword: activeKeyword,
            offset: nextOffset,
            replacing: false,
            generation: requestGeneration
        )
    }

    func retry() async {
        if songs.isEmpty {
            await searchNow()
        } else if let last = songs.last {
            error = nil
            canLoadMore = true
            await loadMoreIfNeeded(current: last)
        }
    }

    @discardableResult
    private func beginNewSearch() -> String {
        debounceTask?.cancel()
        requestTask?.cancel()
        debounceTask = nil
        requestTask = nil
        generation += 1
        let keyword = normalizedQuery
        activeKeyword = keyword
        songs = []
        total = 0
        nextOffset = 0
        error = nil
        hasSearched = false
        canLoadMore = false
        isLoading = !keyword.isEmpty
        return keyword
    }

    private func fetch(keyword: String, offset: Int, replacing: Bool, generation requestGeneration: Int) async {
        guard !Task.isCancelled, requestGeneration == generation, normalizedQuery == keyword else { return }
        // Reserve the request before yielding so repeated pagination callbacks
        // cannot start another fetch for the same offset.
        isLoading = true
        error = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFetch(keyword: keyword, offset: offset, replacing: replacing, generation: requestGeneration)
        }
        requestTask = task
        await task.value
    }

    private func performFetch(keyword: String, offset: Int, replacing: Bool, generation requestGeneration: Int) async {
        guard !Task.isCancelled, requestGeneration == generation, normalizedQuery == keyword else { return }
        do {
            let page = try await search(keyword, pageSize, offset)
            guard !Task.isCancelled, requestGeneration == generation, normalizedQuery == keyword else { return }

            if replacing {
                var seenIDs = Set<Int>()
                songs = page.songs.filter { seenIDs.insert($0.id).inserted }
            } else {
                var seenIDs = Set(songs.map(\.id))
                songs.append(contentsOf: page.songs.filter { seenIDs.insert($0.id).inserted })
            }
            total = max(page.total, songs.count)
            nextOffset = offset + page.songs.count
            canLoadMore = !page.songs.isEmpty && nextOffset < total
            hasSearched = true
            isLoading = false
        } catch {
            guard !Task.isCancelled, requestGeneration == generation, normalizedQuery == keyword else { return }
            self.error = (error as? APIError)?.errorDescription ?? "搜索失败，请稍后重试"
            canLoadMore = false
            hasSearched = true
            isLoading = false
        }
    }
}
