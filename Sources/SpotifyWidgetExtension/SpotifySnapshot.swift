import Foundation

struct SpotifySnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var artworkData: Data?
    var position: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
    var status: String

    static let idle = SpotifySnapshot(
        title: "Spotify",
        artist: "Start playback",
        album: "",
        artworkURL: nil,
        artworkData: nil,
        position: 0,
        duration: 0,
        isPlaying: false,
        status: "Not playing"
    )
}

struct SpotifyLyrics: Equatable {
    struct Line: Equatable {
        var time: TimeInterval?
        var text: String
    }

    var status: String
    var lines: [Line]
    var isSynced: Bool

    static let idle = SpotifyLyrics(status: "Lyrics", lines: [], isSynced: false)

    var hasLyrics: Bool {
        !lines.isEmpty
    }

    func visibleLines(at position: TimeInterval, limit: Int = 3) -> [Line] {
        guard hasLyrics else { return [] }
        guard isSynced else {
            return Array(lines.prefix(limit))
        }

        let currentIndex = lines.lastIndex { line in
            guard let time = line.time else { return false }
            return time <= position + 0.35
        } ?? 0

        let start = max(0, currentIndex - 1)
        let end = min(lines.count, start + limit)
        return Array(lines[start..<end])
    }

    func isCurrent(_ line: Line, at position: TimeInterval) -> Bool {
        guard isSynced, let index = lines.firstIndex(of: line), let time = line.time else {
            return false
        }
        let nextTime = lines.dropFirst(index + 1).first { $0.time != nil }?.time ?? .infinity
        return time <= position + 0.35 && position < nextTime
    }
}

enum LyricsPageStore {
    static func key(for snapshot: SpotifySnapshot) -> String {
        [
            snapshot.title.lowercased(),
            snapshot.artist.lowercased(),
            snapshot.album.lowercased(),
            String(Int(snapshot.duration.rounded()))
        ].joined(separator: "|")
    }

    static func page(for trackKey: String, maxPage: Int) -> Int {
        min(max(UserDefaults.standard.integer(forKey: storageKey(trackKey)), 0), maxPage)
    }

    static func move(trackKey: String, direction: LyricsPageDirection, maxPage: Int) {
        let currentPage = page(for: trackKey, maxPage: maxPage)
        let nextPage: Int
        switch direction {
        case .previous:
            nextPage = max(0, currentPage - 1)
        case .next:
            nextPage = min(maxPage, currentPage + 1)
        }
        UserDefaults.standard.set(nextPage, forKey: storageKey(trackKey))
    }

    private static func storageKey(_ trackKey: String) -> String {
        "lyrics-page-\(trackKey)"
    }
}

enum SpotifyReader {
    static func currentSnapshot(loadArtwork: Bool = true) -> SpotifySnapshot {
        if let bridgedSnapshot = currentSnapshotFromHostApp(loadArtwork: loadArtwork) {
            return bridgedSnapshot
        }

        let output = runAppleScript(trackScript)
        let parts = output.components(separatedBy: "\n")

        guard parts.first != "NOT_RUNNING" else {
            var snapshot = SpotifySnapshot.idle
            snapshot.artist = "Open Spotify"
            snapshot.status = "Spotify is closed"
            return snapshot
        }

        guard parts.first != "NO_TRACK", parts.count >= 7 else {
            return SpotifySnapshot.idle
        }

        let artworkURL = URL(string: parts[3])
        var artworkData: Data?
        if loadArtwork, let artworkURL {
            artworkData = remoteData(from: artworkURL, timeout: 1.2)
        }

        return SpotifySnapshot(
            title: parts[0].isEmpty ? "Unknown track" : parts[0],
            artist: parts[1].isEmpty ? "Unknown artist" : parts[1],
            album: parts[2],
            artworkURL: artworkURL,
            artworkData: artworkData,
            position: TimeInterval(parts[5]) ?? 0,
            duration: (TimeInterval(parts[6]) ?? 0) / 1000,
            isPlaying: parts[4] == "playing",
            status: parts[4] == "playing" ? "Playing" : "Paused"
        )
    }

    private struct HostedSnapshot: Decodable {
        var title: String
        var artist: String
        var album: String
        var artworkURL: String
        var position: TimeInterval
        var duration: TimeInterval
        var isPlaying: Bool
        var status: String
    }

    private static func currentSnapshotFromHostApp(loadArtwork: Bool) -> SpotifySnapshot? {
        guard let url = URL(string: "http://127.0.0.1:47391/snapshot") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 0.8

        guard let data = try? URLSession.shared.synchronousData(for: request),
              let hosted = try? JSONDecoder().decode(HostedSnapshot.self, from: data) else {
            return nil
        }

        let artworkURL = URL(string: hosted.artworkURL)
        var artworkData: Data?
        if loadArtwork, let artworkURL {
            artworkData = remoteData(from: artworkURL, timeout: 1.2)
        }

        return SpotifySnapshot(
            title: hosted.title,
            artist: hosted.artist,
            album: hosted.album,
            artworkURL: artworkURL,
            artworkData: artworkData,
            position: hosted.position,
            duration: hosted.duration,
            isPlaying: hosted.isPlaying,
            status: hosted.status
        )
    }

    static func send(_ command: SpotifyCommand) {
        if sendToHostApp(command) {
            return
        }

        let verb: String
        switch command {
        case .previous:
            verb = "previous track"
        case .play:
            verb = "play"
        case .pause:
            verb = "pause"
        case .playPause:
            verb = "playpause"
        case .next:
            verb = "next track"
        case .openSpotify:
            _ = runAppleScript("""
            tell application id "com.spotify.client" to activate
            """)
            return
        }

        _ = runAppleScript("""
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client" to \(verb)
        else
            tell application id "com.spotify.client" to activate
        end if
        """)
    }

    private static func sendToHostApp(_ command: SpotifyCommand) -> Bool {
        guard var components = URLComponents(string: "http://127.0.0.1:47391/command") else {
            return false
        }
        components.queryItems = [URLQueryItem(name: "command", value: command.rawValue)]
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 0.8

        guard let (_, response) = try? URLSession.shared.synchronousResponse(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return (200..<300).contains(httpResponse.statusCode)
    }

    private static func runAppleScript(_ source: String) -> String {
        guard let script = NSAppleScript(source: source) else {
            return "NO_TRACK"
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return "NO_TRACK" }
        return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func remoteData(from url: URL, timeout: TimeInterval) -> Data? {
        if let cachedData = RemoteDataCache.shared.value(for: url) {
            return cachedData
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = timeout

        guard let data = try? URLSession.shared.synchronousData(for: request), !data.isEmpty else {
            return nil
        }

        RemoteDataCache.shared.store(data, for: url)
        return data
    }

    private static let trackScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            try
                set theTrack to current track
                set trackName to name of theTrack
                set artistName to artist of theTrack
                set albumName to album of theTrack
                set artURL to artwork url of theTrack
                set playState to player state as string
                set playPosition to player position as string
                set trackDuration to duration of theTrack as string
                return trackName & linefeed & artistName & linefeed & albumName & linefeed & artURL & linefeed & playState & linefeed & playPosition & linefeed & trackDuration
            on error
                return "NO_TRACK"
            end try
        end tell
    else
        return "NOT_RUNNING"
    end if
    """

}

enum LyricsReader {
    private struct LRCLIBRecord: Decodable {
        var instrumental: Bool
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    private static let cache = LyricsCache()

    static func lyrics(for snapshot: SpotifySnapshot) -> SpotifyLyrics {
        guard snapshot.title != SpotifySnapshot.idle.title,
              snapshot.artist != SpotifySnapshot.idle.artist,
              snapshot.duration > 0 else {
            return .idle
        }

        let key = cacheKey(for: snapshot)
        if let cached = cachedLyrics(for: key) {
            return cached
        }

        let lyrics = fetchLyrics(for: snapshot)
        store(lyrics, for: key)
        return lyrics
    }

    private static func fetchLyrics(for snapshot: SpotifySnapshot) -> SpotifyLyrics {
        guard var components = URLComponents(string: "https://lrclib.net/api/get") else {
            return SpotifyLyrics(status: "Lyrics unavailable", lines: [], isSynced: false)
        }

        components.queryItems = [
            URLQueryItem(name: "track_name", value: snapshot.title),
            URLQueryItem(name: "artist_name", value: snapshot.artist),
            URLQueryItem(name: "album_name", value: snapshot.album),
            URLQueryItem(name: "duration", value: String(Int(snapshot.duration.rounded())))
        ]

        guard let url = components.url else {
            return SpotifyLyrics(status: "Lyrics unavailable", lines: [], isSynced: false)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 1.5
        request.setValue("Widgify/1.0 (https://lrclib.net)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? URLSession.shared.synchronousResponse(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let record = try? JSONDecoder().decode(LRCLIBRecord.self, from: data) else {
            return SpotifyLyrics(status: "No lyrics found", lines: [], isSynced: false)
        }

        if record.instrumental {
            return SpotifyLyrics(status: "Instrumental", lines: [], isSynced: false)
        }

        if let syncedLyrics = record.syncedLyrics,
           let lyrics = parseSyncedLyrics(syncedLyrics),
           lyrics.hasLyrics {
            return lyrics
        }

        if let plainLyrics = record.plainLyrics {
            let lines = plainLyrics
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { SpotifyLyrics.Line(time: nil, text: $0) }

            if !lines.isEmpty {
                return SpotifyLyrics(status: "Lyrics", lines: lines, isSynced: false)
            }
        }

        return SpotifyLyrics(status: "No lyrics found", lines: [], isSynced: false)
    }

    private static func parseSyncedLyrics(_ source: String) -> SpotifyLyrics? {
        let lines = source
            .components(separatedBy: .newlines)
            .compactMap(parseSyncedLine)
            .filter { !$0.text.isEmpty }

        guard !lines.isEmpty else { return nil }
        return SpotifyLyrics(status: "Synced lyrics", lines: lines, isSynced: true)
    }

    private static func parseSyncedLine(_ source: String) -> SpotifyLyrics.Line? {
        guard let close = source.firstIndex(of: "]") else { return nil }
        let timeToken = source[source.index(after: source.startIndex)..<close]
        let text = source[source.index(after: close)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let time = parseTime(String(timeToken)) else { return nil }
        return SpotifyLyrics.Line(time: time, text: text)
    }

    private static func parseTime(_ source: String) -> TimeInterval? {
        let parts = source.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let minutes = TimeInterval(parts[0]),
              let seconds = TimeInterval(parts[1]) else {
            return nil
        }
        return minutes * 60 + seconds
    }

    private static func cacheKey(for snapshot: SpotifySnapshot) -> String {
        [
            snapshot.title.lowercased(),
            snapshot.artist.lowercased(),
            snapshot.album.lowercased(),
            String(Int(snapshot.duration.rounded()))
        ].joined(separator: "|")
    }

    private static func cachedLyrics(for key: String) -> SpotifyLyrics? {
        cache.value(for: key)
    }

    private static func store(_ lyrics: SpotifyLyrics, for key: String) {
        cache.store(lyrics, for: key)
    }
}

private final class LyricsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: SpotifyLyrics] = [:]

    func value(for key: String) -> SpotifyLyrics? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func store(_ lyrics: SpotifyLyrics, for key: String) {
        lock.lock()
        values[key] = lyrics
        lock.unlock()
    }
}

private final class RemoteDataCache: @unchecked Sendable {
    static let shared = RemoteDataCache()

    private let lock = NSLock()
    private var values: [URL: Data] = [:]
    private var keys: [URL] = []
    private let limit = 8

    func value(for url: URL) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[url]
    }

    func store(_ data: Data, for url: URL) {
        lock.lock()
        defer { lock.unlock() }

        if values[url] == nil {
            keys.append(url)
        }
        values[url] = data

        while keys.count > limit {
            let removed = keys.removeFirst()
            values.removeValue(forKey: removed)
        }
    }
}

private final class URLSessionResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<(Data, URLResponse?), Error>?

    func store(_ result: Result<(Data, URLResponse?), Error>) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func result() -> Result<(Data, URLResponse?), Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private extension URLSession {
    func synchronousData(for request: URLRequest) throws -> Data {
        let (data, _) = try synchronousResponse(for: request)
        return data
    }

    func synchronousResponse(for request: URLRequest) throws -> (Data, URLResponse?) {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = URLSessionResultBox()

        dataTask(with: request) { data, response, error in
            if let error {
                resultBox.store(.failure(error))
            } else {
                resultBox.store(.success((data ?? Data(), response)))
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + request.timeoutInterval)
        return try resultBox.result()?.get() ?? (Data(), nil)
    }
}
