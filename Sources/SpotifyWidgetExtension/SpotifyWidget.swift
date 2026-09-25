import AppKit
import SwiftUI
import WidgetKit

struct SpotifyEntry: TimelineEntry {
    let date: Date
    let snapshot: SpotifySnapshot
    let lyrics: SpotifyLyrics
}

struct SpotifyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpotifyEntry {
        SpotifyEntry(date: Date(), snapshot: .idle, lyrics: .idle)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpotifyEntry) -> Void) {
        let snapshot = SpotifyReader.currentSnapshot(loadArtwork: !context.isPreview)
        completion(SpotifyEntry(date: Date(), snapshot: snapshot, lyrics: LyricsReader.lyrics(for: snapshot)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpotifyEntry>) -> Void) {
        let now = Date()
        let snapshot = SpotifyReader.currentSnapshot(loadArtwork: !context.isPreview)
        let lyrics = LyricsReader.lyrics(for: snapshot)
        let entries = timelineEntries(from: snapshot, lyrics: lyrics, startingAt: now)
        let refresh = entries.last?.date.addingTimeInterval(snapshot.isPlaying ? 2 : 60) ?? now.addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func timelineEntries(from snapshot: SpotifySnapshot, lyrics: SpotifyLyrics, startingAt startDate: Date) -> [SpotifyEntry] {
        guard snapshot.isPlaying, snapshot.duration > 0 else {
            return [SpotifyEntry(date: startDate, snapshot: snapshot, lyrics: lyrics)]
        }

        let remaining = max(0, snapshot.duration - snapshot.position)
        let horizon = min(35, max(14, remaining + 2))
        return stride(from: 0, through: horizon, by: 1).map { offset in
            var projectedSnapshot = snapshot
            projectedSnapshot.position = min(snapshot.duration, snapshot.position + offset)
            return SpotifyEntry(date: startDate.addingTimeInterval(offset), snapshot: projectedSnapshot, lyrics: lyrics)
        }
    }
}

struct SpotifyWidget: Widget {
    static let kind = SpotifyWidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SpotifyProvider()) { entry in
            SpotifyWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Spotify")
        .description("Shows the current Spotify track with artwork and playback controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct SpotifyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SpotifyEntry

    var body: some View {
        Group {
            switch renderingMode {
            case .fullColor:
                fullColorBody
            default:
                AmbientSpotifyWidget(snapshot: entry.snapshot)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private var fullColorBody: some View {
        switch family {
        case .systemSmall:
            SmallSpotifyWidget(snapshot: entry.snapshot)
        case .systemMedium:
            MediumSpotifyWidget(snapshot: entry.snapshot)
        case .systemExtraLarge:
            ExtraLargeSpotifyWidget(snapshot: entry.snapshot, lyrics: entry.lyrics)
        default:
            LargeSpotifyWidget(snapshot: entry.snapshot, lyrics: entry.lyrics)
        }
    }
}

private struct AmbientSpotifyWidget: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: SpotifySnapshot

    var body: some View {
        let ambientSnapshot = snapshot.roundedForAmbientDisplay(interval: 5)

        switch family {
        case .systemSmall:
            SmallAmbientSpotifyWidget(snapshot: ambientSnapshot)
        case .systemMedium:
            MediumAmbientSpotifyWidget(snapshot: ambientSnapshot)
        default:
            WideAmbientSpotifyWidget(snapshot: ambientSnapshot)
        }
    }
}

private struct SmallAmbientSpotifyWidget: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 12
            let contentWidth = max(0, proxy.size.width - padding * 2)
            let contentHeight = max(0, proxy.size.height - padding * 2)
            let progressHeight: CGFloat = 18
            let artSize = min(contentWidth, max(54, contentHeight - progressHeight - 12))

            ZStack {
                FullArtworkBackground(snapshot: snapshot)

                VStack(spacing: 10) {
                    ArtworkView(snapshot: snapshot, cornerRadius: 13)
                        .frame(width: artSize, height: artSize)
                        .shadow(color: .black.opacity(0.34), radius: 10, y: 5)

                    CompactProgressRow(snapshot: snapshot, showsTime: true)
                        .frame(width: contentWidth)
                }
                .frame(width: contentWidth, height: contentHeight)
                .padding(padding)

                CornerStatusDot(snapshot: snapshot, inset: 9)
            }
        }
    }
}

private struct MediumAmbientSpotifyWidget: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 14
            let contentWidth = max(0, proxy.size.width - padding * 2)
            let contentHeight = max(0, proxy.size.height - padding * 2)
            let artSize = min(contentHeight, 112)
            let progressWidth = max(64, contentWidth - artSize - 14)

            ZStack(alignment: .leading) {
                FullArtworkBackground(snapshot: snapshot)

                HStack(spacing: 14) {
                    ArtworkView(snapshot: snapshot, cornerRadius: 14)
                        .frame(width: artSize, height: artSize)
                        .shadow(color: .black.opacity(0.34), radius: 12, y: 6)

                    CompactProgressRow(snapshot: snapshot, showsTime: true)
                        .frame(width: progressWidth)
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .center)
                .padding(padding)

                CornerStatusDot(snapshot: snapshot, inset: 11)
            }
        }
    }
}

private struct WideAmbientSpotifyWidget: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 18
            let contentWidth = max(0, proxy.size.width - padding * 2)
            let contentHeight = max(0, proxy.size.height - padding * 2)
            let artSize = min(contentHeight, max(104, contentWidth * 0.30))
            let progressWidth = max(120, contentWidth - artSize - 18)

            ZStack(alignment: .leading) {
                FullArtworkBackground(snapshot: snapshot)

                HStack(spacing: 18) {
                    ArtworkView(snapshot: snapshot, cornerRadius: 18)
                        .frame(width: artSize, height: artSize)
                        .shadow(color: .black.opacity(0.36), radius: 14, y: 7)

                    CompactProgressRow(snapshot: snapshot, showsTime: true)
                        .frame(width: progressWidth)
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .center)
                .padding(padding)

                CornerStatusDot(snapshot: snapshot, inset: 13)
            }
        }
    }
}

private struct SmallSpotifyWidget: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 10
            let contentWidth = max(0, proxy.size.width - padding * 2)
            let contentHeight = max(0, proxy.size.height - padding * 2)
            let artSize = min(max(44, contentWidth * 0.38), 58)

            ZStack(alignment: .topLeading) {
                FullArtworkBackground(snapshot: snapshot)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        ArtworkView(snapshot: snapshot, cornerRadius: 9)
                            .frame(width: artSize, height: artSize)
                            .shadow(color: .black.opacity(0.34), radius: 8, y: 4)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)

                            Text(snapshot.artist)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.76))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Text(snapshot.album.isEmpty ? "Spotify desktop" : snapshot.album)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(width: max(60, contentWidth - artSize - 8), alignment: .leading)
                    }
                    .frame(width: contentWidth, height: min(76, contentHeight - 34), alignment: .topLeading)

                    Spacer(minLength: 0)

                    CompactProgressRow(snapshot: snapshot, showsTime: true)

                    PlaybackControlStrip(snapshot: snapshot)
                        .font(.caption)
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                .padding(padding)

                CornerStatusDot(snapshot: snapshot, inset: 9)
            }
        }
    }
}

private struct MediumSpotifyWidget: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 12
            let contentHeight = max(80, proxy.size.height - padding * 2)
            let artSize = min(contentHeight, 108)

            ZStack(alignment: .topLeading) {
                FullArtworkBackground(snapshot: snapshot)

                HStack(alignment: .center, spacing: 12) {
                    ArtworkView(snapshot: snapshot, cornerRadius: 12)
                        .frame(width: artSize, height: artSize)
                        .shadow(color: .black.opacity(0.32), radius: 10, y: 5)

                    VStack(alignment: .leading, spacing: 6) {
                        TrackSummary(
                            snapshot: snapshot,
                            titleFont: .headline.weight(.bold),
                            artistFont: .callout.weight(.semibold),
                            albumFont: .caption
                        )
                        .layoutPriority(1)

                        Spacer(minLength: 0)

                        ProgressRow(snapshot: snapshot)

                        PlaybackControlStrip(snapshot: snapshot)
                            .font(.callout)
                    }
                    .frame(width: max(120, proxy.size.width - artSize - padding * 2 - 12), height: contentHeight, alignment: .leading)
                }
                .frame(width: max(0, proxy.size.width - padding * 2), height: contentHeight, alignment: .leading)
                .padding(padding)
                .background(.black.opacity(0.30))

                CornerStatusDot(snapshot: snapshot, inset: 10)
            }
        }
    }
}

private struct LargeSpotifyWidget: View {
    let snapshot: SpotifySnapshot
    let lyrics: SpotifyLyrics

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 12
            let gap: CGFloat = 6
            let contentWidth = max(0, proxy.size.width - padding * 2)
            let contentHeight = max(0, proxy.size.height - padding * 2)
            let playerHeight = min(max(84, contentHeight * 0.30), 96)
            let lyricsWidth = max(0, contentWidth - 8)
            let lyricsHeight = max(118, contentHeight - playerHeight - gap)
            let artSize = min(playerHeight, 94)

            ZStack(alignment: .topLeading) {
                FullArtworkBackground(snapshot: snapshot)

                VStack(alignment: .leading, spacing: gap) {
                    HStack(alignment: .center, spacing: 12) {
                        ArtworkView(snapshot: snapshot, cornerRadius: 13)
                            .frame(width: artSize, height: artSize)
                            .shadow(color: .black.opacity(0.34), radius: 10, y: 5)

                        VStack(alignment: .leading, spacing: 5) {
                            CompactTrackSummary(snapshot: snapshot)
                            .layoutPriority(1)

                            Spacer(minLength: 0)

                            CompactProgressRow(snapshot: snapshot, showsTime: true)

                            PlaybackControlStrip(snapshot: snapshot)
                                .font(.callout)
                        }
                        .frame(width: max(130, contentWidth - artSize - 12), height: playerHeight, alignment: .leading)
                    }
                    .frame(width: contentWidth, height: playerHeight, alignment: .leading)

                    LyricsPanel(snapshot: snapshot, lyrics: lyrics, visibleLineLimit: 6, currentLineLimit: 2, prominentCurrentLine: true, showsPlainLyricsPaging: true, centersFocusedLyrics: true, focusedContentBias: .upper)
                        .frame(width: lyricsWidth, height: lyricsHeight, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(width: contentWidth, alignment: .center)
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                .padding(padding)

                CornerStatusDot(snapshot: snapshot, inset: 10)
            }
        }
    }
}

private struct ExtraLargeSpotifyWidget: View {
    let snapshot: SpotifySnapshot
    let lyrics: SpotifyLyrics

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 16
            let gap: CGFloat = 12
            let contentWidth = max(0, proxy.size.width - padding * 2)
            let contentHeight = max(0, proxy.size.height - padding * 2)
            let playerPanelWidth = min(max(248, contentWidth * 0.40), 304)
            let playerInnerWidth = max(160, playerPanelWidth - 28)
            let lyricsWidth = max(160, contentWidth - playerPanelWidth - gap)
            let artSize = min(max(108, contentHeight * 0.42), 146)

            ZStack(alignment: .topLeading) {
                FullArtworkBackground(snapshot: snapshot)

                HStack(alignment: .top, spacing: gap) {
                    VStack(alignment: .leading, spacing: 10) {
                        ArtworkView(snapshot: snapshot, cornerRadius: 14)
                            .frame(width: artSize, height: artSize)
                            .shadow(color: .black.opacity(0.34), radius: 12, y: 6)

                        TrackSummary(
                            snapshot: snapshot,
                            titleFont: .headline.weight(.bold),
                            artistFont: .callout.weight(.semibold),
                            albumFont: .caption
                        )
                        .layoutPriority(1)

                        ProgressRow(snapshot: snapshot)

                        PlaybackControlStrip(snapshot: snapshot)
                            .font(.callout)

                        Spacer(minLength: 0)
                    }
                    .frame(width: playerInnerWidth, height: contentHeight - 28, alignment: .topLeading)
                    .padding(14)
                    .frame(width: playerPanelWidth, height: contentHeight, alignment: .topLeading)
                    .background(LiquidGlassPanel(cornerRadius: 18))

                    LyricsPanel(snapshot: snapshot, lyrics: lyrics, visibleLineLimit: 8, currentLineLimit: 3, prominentCurrentLine: true, showsPlainLyricsPaging: true, centersFocusedLyrics: true)
                        .frame(width: lyricsWidth, height: contentHeight, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                .padding(padding)

                CornerStatusDot(snapshot: snapshot, inset: 12)
            }
        }
    }
}

private struct CornerStatusDot: View {
    let snapshot: SpotifySnapshot
    var inset: CGFloat

    var body: some View {
        Circle()
            .fill(snapshot.isPlaying ? .green : .secondary)
            .frame(width: 7, height: 7)
            .shadow(color: .black.opacity(0.42), radius: 3, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, inset)
            .padding(.trailing, inset)
    }
}

private struct TrackSummary: View {
    let snapshot: SpotifySnapshot
    var titleFont: Font
    var artistFont: Font = .headline.weight(.semibold)
    var albumFont: Font = .caption

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(snapshot.title)
                .font(titleFont)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.36), radius: 5, y: 2)

            Text(snapshot.artist)
                .font(artistFont)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            Text(snapshot.album.isEmpty ? "Spotify desktop" : snapshot.album)
                .font(albumFont)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
    }
}

private struct CompactTrackSummary: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.36), radius: 5, y: 2)

            Text(snapshot.artist)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)

            Text(snapshot.album.isEmpty ? "Spotify desktop" : snapshot.album)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
    }
}

private struct LyricsPanel: View {
    let snapshot: SpotifySnapshot
    let lyrics: SpotifyLyrics
    var visibleLineLimit = 3
    var currentLineLimit = 2
    var prominentCurrentLine = false
    var showsPlainLyricsPaging = false
    var centersFocusedLyrics = false
    var focusedContentBias: FocusedLyricsBias = .center

    var body: some View {
        if prominentCurrentLine {
            focusLyricsBody
        } else {
            cardLyricsBody
        }
    }

    private var focusLyricsBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
                .foregroundStyle(.white.opacity(0.86))

            focusedLyricsContent
                .frame(
                    maxWidth: .infinity,
                    maxHeight: centersFocusedLyrics ? .infinity : nil,
                    alignment: centersFocusedLyrics ? focusedContentBias.alignment : .topLeading
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LyricsVignette())
        .clipped()
    }

    private var focusedLyricsContent: some View {
        VStack(alignment: .leading, spacing: centersFocusedLyrics ? 9 : 7) {
            if lyrics.hasLyrics {
                ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                    let isFeatured = isFeaturedLine(line)
                    Text(line.text)
                        .font(focusedFont(isFeatured: isFeatured))
                        .foregroundStyle(.white.opacity(opacity(for: line, isFeatured: isFeatured)))
                        .lineLimit(isFeatured ? currentLineLimit : 1)
                        .minimumScaleFactor(isFeatured ? 0.78 : 0.86)
                        .blur(radius: blurRadius(for: line, isFeatured: isFeatured))
                        .shadow(color: .black.opacity(isFeatured ? 0.38 : 0.18), radius: isFeatured ? 5 : 3, y: 2)
                }
            } else {
                Text("No matching lyrics found for this track yet.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardLyricsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            if lyrics.hasLyrics {
                ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                    let isCurrent = lyrics.isCurrent(line, at: snapshot.position)
                    Text(line.text)
                        .font(isCurrent ? currentLyricFont : .caption.weight(.medium))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .lineLimit(lineLimit(forCurrentLine: isCurrent))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No matching lyrics found for this track yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LiquidGlassPanel(cornerRadius: 14))
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(lyrics.status, systemImage: lyrics.isSynced ? "quote.bubble.fill" : "quote.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(lyrics.hasLyrics ? .primary : .secondary)

            Spacer(minLength: 0)

            if showsPagingControls {
                LyricsPageButton(systemName: "chevron.left", trackKey: trackKey, direction: .previous, maxPage: maxPlainLyricsPage)
                Text("\(plainLyricsPage + 1)/\(maxPlainLyricsPage + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                LyricsPageButton(systemName: "chevron.right", trackKey: trackKey, direction: .next, maxPage: maxPlainLyricsPage)
            }
        }
    }

    private var currentLyricFont: Font {
        prominentCurrentLine ? .headline.weight(.bold) : .callout.weight(.bold)
    }

    private func focusedFont(isFeatured: Bool) -> Font {
        guard centersFocusedLyrics else {
            return isFeatured ? .headline.weight(.bold) : .subheadline.weight(.semibold)
        }
        return isFeatured ? .title3.weight(.bold) : .callout.weight(.semibold)
    }

    private var trackKey: String {
        LyricsPageStore.key(for: snapshot)
    }

    private var plainLyricsPage: Int {
        LyricsPageStore.page(for: trackKey, maxPage: maxPlainLyricsPage)
    }

    private var maxPlainLyricsPage: Int {
        guard !lyrics.isSynced, visibleLineLimit > 0 else { return 0 }
        return max(0, Int(ceil(Double(lyrics.lines.count) / Double(visibleLineLimit))) - 1)
    }

    private var showsPagingControls: Bool {
        showsPlainLyricsPaging && lyrics.hasLyrics && !lyrics.isSynced && maxPlainLyricsPage > 0
    }

    private var visibleLines: [SpotifyLyrics.Line] {
        guard lyrics.hasLyrics else { return [] }
        guard !lyrics.isSynced else {
            return lyrics.visibleLines(at: snapshot.position, limit: visibleLineLimit)
        }

        let start = plainLyricsPage * visibleLineLimit
        let end = min(lyrics.lines.count, start + visibleLineLimit)
        guard start < end else { return [] }
        return Array(lyrics.lines[start..<end])
    }

    private func lineLimit(forCurrentLine isCurrent: Bool) -> Int {
        guard lyrics.isSynced else { return 2 }
        return isCurrent ? currentLineLimit : 1
    }

    private func isFeaturedLine(_ line: SpotifyLyrics.Line) -> Bool {
        guard lyrics.isSynced else {
            return visibleLines.first == line
        }
        return lyrics.isCurrent(line, at: snapshot.position)
    }

    private func opacity(for line: SpotifyLyrics.Line, isFeatured: Bool) -> Double {
        guard !isFeatured else { return 0.98 }
        guard lyrics.isSynced, let time = line.time else { return 0.58 }
        return time > snapshot.position ? 0.58 : 0.34
    }

    private func blurRadius(for line: SpotifyLyrics.Line, isFeatured: Bool) -> CGFloat {
        guard !isFeatured else { return 0 }
        guard lyrics.isSynced, let time = line.time else { return 0.25 }
        return time > snapshot.position ? 0.25 : 0.75
    }
}

private enum FocusedLyricsBias {
    case center
    case upper

    var alignment: Alignment {
        switch self {
        case .center:
            return .center
        case .upper:
            return Alignment(horizontal: .leading, vertical: .top)
        }
    }
}

private struct LyricsVignette: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    colors: [
                        .black.opacity(0.20),
                        .black.opacity(0.10),
                        .black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
            }
            .blur(radius: 0.2)
    }
}

private struct LiquidGlassPanel: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.22),
                                .white.opacity(0.07),
                                .black.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.black.opacity(0.28), .black.opacity(0.54)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.42), lineWidth: 0.8)
                    .blendMode(.screen)
            }
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.black.opacity(0.30), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(width: 92, height: 1.2)
                    .padding(.leading, 18)
                    .padding(.top, 8)
                    .blur(radius: 0.4)
            }
    }
}

private struct LyricsPageButton: View {
    let systemName: String
    let trackKey: String
    let direction: LyricsPageDirection
    let maxPage: Int

    var body: some View {
        Button(intent: LyricsPageIntent(trackKey: trackKey, direction: direction, maxPage: maxPage)) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct FullArtworkBackground: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        ZStack {
            if let artworkImage {
                FullColorArtworkImage(image: artworkImage)
            } else {
                LinearGradient(colors: [.black, .gray.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.28),
                    .black.opacity(0.58),
                    .black.opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [.black.opacity(0.58), .black.opacity(0.18), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .clipped()
    }

    private var artworkImage: NSImage? {
        guard let data = snapshot.artworkData else { return nil }
        return NSImage(data: data)
    }
}

private struct ArtworkBackdrop: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        if let artworkImage {
            Image(nsImage: artworkImage)
                .resizable()
                .scaledToFill()
                .blur(radius: 24)
                .opacity(0.22)
                .overlay(.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var artworkImage: NSImage? {
        guard let data = snapshot.artworkData else { return nil }
        return NSImage(data: data)
    }
}

private struct ArtworkView: View {
    let snapshot: SpotifySnapshot
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.black.opacity(0.16))

            if let artworkImage {
                FullColorArtworkImage(image: artworkImage)
            } else {
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var artworkImage: NSImage? {
        guard let data = snapshot.artworkData else { return nil }
        return NSImage(data: data)
    }
}

private struct FullColorArtworkImage: View {
    let image: NSImage

    var body: some View {
        if #available(macOS 15.0, *) {
            Image(nsImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .aspectRatio(contentMode: .fill)
        } else {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        }
    }
}

private struct ProgressRow: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: progressValue)
                .tint(.green)
                .transaction { transaction in
                    transaction.animation = nil
                }

            HStack {
                Text(formatTime(snapshot.position))
                    .contentTransition(.identity)
                Spacer()
                Text(formatTime(snapshot.duration))
                    .contentTransition(.identity)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.82))
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private var progressValue: Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(max(snapshot.position / snapshot.duration, 0), 1)
    }
}

private struct CompactProgressRow: View {
    let snapshot: SpotifySnapshot
    var showsTime = false

    var body: some View {
        VStack(spacing: 4) {
            MiniProgressBar(snapshot: snapshot)

            if showsTime {
                HStack {
                    Text(formatTime(snapshot.position))
                        .contentTransition(.identity)
                    Spacer()
                    Text(formatTime(snapshot.duration))
                        .contentTransition(.identity)
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct MiniProgressBar: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.34))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.green)
                        .frame(width: proxy.size.width * progressValue)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
            .clipShape(Capsule())
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private var progressValue: Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(max(snapshot.position / snapshot.duration, 0), 1)
    }
}

private struct PlaybackControlStrip: View {
    let snapshot: SpotifySnapshot

    var body: some View {
        HStack(spacing: 18) {
            ControlButton(systemName: "backward.fill", command: .previous)
            ControlButton(systemName: snapshot.isPlaying ? "pause.circle.fill" : "play.circle.fill", command: snapshot.isPlaying ? .pause : .play)
                .font(.title2)
            ControlButton(systemName: "forward.fill", command: .next)
            Spacer(minLength: 8)

            ControlButton(systemName: "music.note.list", command: .openSpotify)
        }
        .foregroundStyle(.white.opacity(0.94))
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }
}

private struct ControlButton: View {
    let systemName: String
    let command: SpotifyCommand

    var body: some View {
        Button(intent: SpotifyCommandIntent(command: command)) {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    return "\(total / 60):\(String(format: "%02d", total % 60))"
}

private extension SpotifySnapshot {
    func roundedForAmbientDisplay(interval: TimeInterval) -> SpotifySnapshot {
        guard interval > 0, duration > 0 else { return self }

        var snapshot = self
        let roundedPosition = floor(position / interval) * interval
        snapshot.position = min(duration, max(0, roundedPosition))
        return snapshot
    }
}
