import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appearance: AppearanceManager
    @EnvironmentObject private var fontManager: FontManager

    @AppStorage("player.quality") private var quality: String = "standard"
    @State private var fontName: String = ""

    @State private var coverCacheBytes: Int?
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false

    private let qualities: [(String, String)] = [
        ("标准", "standard"), ("较高", "higher"), ("极高", "exhigh"),
        ("无损", "lossless"), ("Hi-Res", "hires"),
    ]

    var body: some View {
        Form {
            playbackSection
            appearanceSection
            fontSection
            cacheSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .confirmationDialog("确定清除所有缓存吗？", isPresented: $showClearCacheConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) { Task { await clearCache() } }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            fontName = fontManager.selectedFontName == FontManager.systemFontName
                ? ""
                : fontManager.selectedFontName
        }
    }

    // MARK: Playback

    private var playbackSection: some View {
        Section {
            Picker("音质", selection: $quality) {
                ForEach(qualities, id: \.1) { Text($0.0).tag($0.1) }
            }
        } header: {
            Text("播放设置")
        } footer: {
            Text("音质更改后，将在播放下一首歌曲时生效")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("外观") {
            Picker("主题", selection: $appearance.mode) {
                ForEach(AppearanceManager.Mode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
        }
    }

    // MARK: Font

    private var fontSection: some View {
        Section {
            TextField("留空使用系统字体", text: $fontName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(applyFontName)

            Picker("字体大小", selection: $fontManager.size) {
                ForEach(FontManager.FontSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            
            // 预览区域
            VStack(alignment: .leading, spacing: 8) {
                Text("预览效果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("歌曲名称")
                        .font(fontManager.font(.body, weight: .semibold))
                    Text("艺术家 · 专辑名称")
                        .font(fontManager.font(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.vertical, 4)
        } header: {
            Text("字体设置")
        } footer: {
            Text("输入已安装的字体族名称（如 PingFang SC）后按回车应用；留空或未安装时自动使用系统字体。部分界面可能需要重新加载才能生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func applyFontName() {
        let trimmed = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        fontManager.selectedFontName = trimmed.isEmpty ? FontManager.systemFontName : trimmed
    }

    // MARK: Cache

    private var cacheSection: some View {
        Section {
            LabeledContent("封面缓存", value: cacheSizeText(coverCacheBytes))

            Button(role: .destructive) {
                showClearCacheConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Text("清除缓存")
                    if isClearingCache {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(isClearingCache)
        } header: {
            Text("缓存")
        } footer: {
            Text("封面缓存在磁盘，歌词仅在本次运行中保留。清除后会在下次使用时重新获取。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await refreshCacheStats() }
    }

    private func refreshCacheStats() async {
        coverCacheBytes = await ImageLoader.shared.cacheUsage()
    }

    private func clearCache() async {
        isClearingCache = true
        await ImageLoader.shared.clearCache()
        await LyricsCache.shared.clear()
        await refreshCacheStats()
        isClearingCache = false
    }

    private func cacheSizeText(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: About

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("应用", value: "Sonaro")
            LabeledContent("版本", value: appVersion)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
