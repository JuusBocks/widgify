import Foundation
import Darwin
import WidgetKit

private struct ServedSpotifySnapshot: Encodable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: String
    var position: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
    var status: String
    var updatedAt: Date

    static let idle = ServedSpotifySnapshot(
        title: "Spotify",
        artist: "Start playback",
        album: "",
        artworkURL: "",
        position: 0,
        duration: 0,
        isPlaying: false,
        status: "Not playing",
        updatedAt: Date()
    )

    func requiresTimelineReload(comparedTo other: ServedSpotifySnapshot) -> Bool {
        title != other.title ||
            artist != other.artist ||
            album != other.album ||
            artworkURL != other.artworkURL ||
            duration != other.duration ||
            isPlaying != other.isPlaying ||
            status != other.status
    }
}

final class SpotifySnapshotServer: @unchecked Sendable {
    static let shared = SpotifySnapshotServer()
    static let port: UInt16 = 47391
    private static let widgetKind = "SpotifyWidgetPlayer"

    private let queue = DispatchQueue(label: "com.leounib.Widgify.snapshot-server")
    private let lock = NSLock()
    private var latestSnapshot = ServedSpotifySnapshot.idle
    private var socketFD: Int32 = -1
    private var socketSource: DispatchSourceRead?
    private var refreshTimer: DispatchSourceTimer?
    private var lastTimelineReload = Date.distantPast
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        NSLog("Widgify server starting on 127.0.0.1:\(Self.port)")
        queue.async { [weak self] in
            guard let self else { return }
            self.startSocket()
            _ = self.refreshSnapshot()
            self.startRefreshTimer()
        }
    }

    private func startSocket() {
        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            NSLog("Widgify server socket() failed: \(errno)")
            return
        }

        var one: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(Self.port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            NSLog("Widgify server bind() failed: \(errno)")
            close(socketFD)
            socketFD = -1
            return
        }

        guard listen(socketFD, 8) == 0 else {
            NSLog("Widgify server listen() failed: \(errno)")
            close(socketFD)
            socketFD = -1
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [socketFD] in
            close(socketFD)
        }
        source.resume()
        socketSource = source
        NSLog("Widgify server listening on 127.0.0.1:\(Self.port)")
    }

    private func startRefreshTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let didChange = self.refreshSnapshot()
            if didChange || Date().timeIntervalSince(self.lastTimelineReload) > 60 {
                self.reloadWidgetTimelines()
            }
        }
        timer.resume()
        refreshTimer = timer
    }

    private func acceptConnection() {
        let client = accept(socketFD, nil, nil)
        guard client >= 0 else { return }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 2048)
        let byteCount = recv(client, &buffer, buffer.count - 1, 0)
        let request = byteCount > 0 ? String(decoding: buffer.prefix(byteCount), as: UTF8.self) : ""

        if request.hasPrefix("GET /command?") || request.hasPrefix("POST /command?") {
            handleCommandRequest(request, client: client)
        } else {
            sendSnapshot(to: client)
        }
    }

    private func sendSnapshot(to client: Int32) {
        let snapshot = cachedSnapshot()

        let body = (try? JSONEncoder().encode(snapshot)) ?? Data("{}".utf8)
        var response = Data()
        response.append(Data("HTTP/1.1 200 OK\r\n".utf8))
        response.append(Data("Content-Type: application/json\r\n".utf8))
        response.append(Data("Cache-Control: no-store\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n\r\n".utf8))
        response.append(body)

        response.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = Darwin.write(client, baseAddress, buffer.count)
        }
        close(client)
    }

    private func sendStatus(to client: Int32, code: Int, message: String) {
        let body = Data("{\"status\":\"\(message)\"}".utf8)
        var response = Data()
        response.append(Data("HTTP/1.1 \(code) \(message)\r\n".utf8))
        response.append(Data("Content-Type: application/json\r\n".utf8))
        response.append(Data("Cache-Control: no-store\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n\r\n".utf8))
        response.append(body)

        response.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = Darwin.write(client, baseAddress, buffer.count)
        }
        close(client)
    }

    private func handleCommandRequest(_ request: String, client: Int32) {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let command = commandValue(from: firstLine) else {
            sendStatus(to: client, code: 400, message: "Bad Request")
            return
        }

        let script: String
        switch command {
        case "previous":
            script = Self.commandScript("previous track")
        case "play":
            script = Self.commandScript("play")
        case "pause":
            script = Self.commandScript("pause")
        case "playPause":
            script = Self.commandScript("playpause")
        case "next":
            script = Self.commandScript("next track")
        case "openSpotify":
            script = Self.openSpotifyScript
        default:
            sendStatus(to: client, code: 400, message: "Bad Request")
            return
        }

        _ = runAppleScript(script)
        sendStatus(to: client, code: 200, message: "OK")
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            _ = self?.refreshSnapshot()
            self?.reloadWidgetTimelines()
        }
    }

    private func commandValue(from firstLine: String) -> String? {
        guard let path = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(path)") else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "command" })?.value
    }

    private func cachedSnapshot() -> ServedSpotifySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return latestSnapshot
    }

    private func updateSnapshot(_ snapshot: ServedSpotifySnapshot) -> Bool {
        lock.lock()
        let previous = latestSnapshot
        latestSnapshot = snapshot
        lock.unlock()
        return snapshot.requiresTimelineReload(comparedTo: previous)
    }

    private func refreshSnapshot() -> Bool {
        let output = runAppleScript(Self.trackScript)
        let parts = output.components(separatedBy: "\n")

        guard parts.first != "NOT_RUNNING" else {
            var snapshot = ServedSpotifySnapshot.idle
            snapshot.artist = "Open Spotify"
            snapshot.status = "Spotify is closed"
            snapshot.updatedAt = Date()
            return updateSnapshot(snapshot)
        }

        guard parts.first != "NO_TRACK", parts.count >= 7 else {
            var snapshot = ServedSpotifySnapshot.idle
            snapshot.updatedAt = Date()
            return updateSnapshot(snapshot)
        }

        let playState = parts[4]
        let snapshot = ServedSpotifySnapshot(
            title: parts[0].isEmpty ? "Unknown track" : parts[0],
            artist: parts[1].isEmpty ? "Unknown artist" : parts[1],
            album: parts[2],
            artworkURL: parts[3],
            position: TimeInterval(parts[5]) ?? 0,
            duration: (TimeInterval(parts[6]) ?? 0) / 1000,
            isPlaying: playState == "playing",
            status: playState == "playing" ? "Playing" : "Paused",
            updatedAt: Date()
        )
        return updateSnapshot(snapshot)
    }

    private func reloadWidgetTimelines() {
        lastTimelineReload = Date()
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        }
    }

    private func runAppleScript(_ source: String) -> String {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                self.runAppleScript(source)
            }
        }

        guard let script = NSAppleScript(source: source) else {
            return "NO_TRACK"
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            NSLog("Widgify AppleScript failed: \(error)")
            return "NO_TRACK"
        }

        return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private static func commandScript(_ command: String) -> String {
        """
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client" to \(command)
        else
            tell application id "com.spotify.client" to activate
        end if
        """
    }

    private static let openSpotifyScript = """
    tell application id "com.spotify.client" to activate
    """

}
