import Foundation
import Darwin
import WidgetKit

private struct ServedSpotifySnapshot: Encodable {
    var player: String
    var title: String
    var artist: String
    var album: String
    var artworkURL: String
    var artworkData: String
    var position: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
    var isShuffling: Bool
    var status: String
    var updatedAt: Date

    static let idle = ServedSpotifySnapshot(
        player: "spotify",
        title: "Spotify",
        artist: "Start playback",
        album: "",
        artworkURL: "",
        artworkData: "",
        position: 0,
        duration: 0,
        isPlaying: false,
        isShuffling: false,
        status: "Not playing",
        updatedAt: Date()
    )

    func requiresTimelineReload(comparedTo other: ServedSpotifySnapshot) -> Bool {
        player != other.player ||
            title != other.title ||
            artist != other.artist ||
            album != other.album ||
            artworkURL != other.artworkURL ||
            artworkData != other.artworkData ||
            duration != other.duration ||
            isPlaying != other.isPlaying ||
            isShuffling != other.isShuffling ||
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
        let player = cachedSnapshot().player
        switch command {
        case "previous":
            script = Self.commandScript(spotifyCommand: "previous track", musicCommand: "previous track", player: player)
        case "play":
            script = Self.commandScript(spotifyCommand: "play", musicCommand: "play", player: player)
        case "pause":
            script = Self.commandScript(spotifyCommand: "pause", musicCommand: "pause", player: player)
        case "playPause":
            script = Self.commandScript(spotifyCommand: "playpause", musicCommand: "playpause", player: player)
        case "next":
            script = Self.commandScript(spotifyCommand: "next track", musicCommand: "next track", player: player)
        case "shuffle":
            script = Self.shuffleScript(player: player)
        case "openSpotify":
            script = Self.openPlayerScript(player: player)
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
            snapshot.artist = "Open Music"
            snapshot.status = "No player is open"
            snapshot.updatedAt = Date()
            return updateSnapshot(snapshot)
        }

        guard parts.first != "NO_TRACK", parts.count >= 10 else {
            var snapshot = ServedSpotifySnapshot.idle
            snapshot.updatedAt = Date()
            return updateSnapshot(snapshot)
        }

        let playState = parts[6]
        let snapshot = ServedSpotifySnapshot(
            player: parts[0],
            title: parts[1].isEmpty ? "Unknown track" : parts[1],
            artist: parts[2].isEmpty ? "Unknown artist" : parts[2],
            album: parts[3],
            artworkURL: parts[4],
            artworkData: parts[5],
            position: TimeInterval(parts[7]) ?? 0,
            duration: (TimeInterval(parts[8]) ?? 0) / 1000,
            isPlaying: playState == "playing",
            isShuffling: parts[9] == "true",
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
    on spotifySnapshot()
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client"
                try
                    set theTrack to current track
                    set trackName to name of theTrack
                    set artistName to artist of theTrack
                    set albumName to album of theTrack
                    set artURL to artwork url of theTrack
                    set playState to player state as string
                    set playPosition to player position as string
                    set trackDuration to duration of theTrack as string
                    set shuffleState to shuffling as string
                    return "spotify" & linefeed & trackName & linefeed & artistName & linefeed & albumName & linefeed & artURL & linefeed & "" & linefeed & playState & linefeed & playPosition & linefeed & trackDuration & linefeed & shuffleState
                on error
                    return "NO_TRACK"
                end try
            end tell
        end if
        return "NOT_RUNNING"
    end spotifySnapshot

    on musicArtwork(theTrack)
        try
            set artworkBlob to raw data of artwork 1 of theTrack
            set artPath to (POSIX path of (path to temporary items)) & "widgify-music-artwork-" & (do shell script "/usr/bin/uuidgen") & ".bin"
            set fileRef to open for access (POSIX file artPath) with write permission
            set eof fileRef to 0
            write artworkBlob to fileRef
            close access fileRef
            set encodedArtwork to do shell script "/usr/bin/base64 < " & quoted form of artPath & " | /usr/bin/tr -d '\\n'"
            do shell script "/bin/rm -f " & quoted form of artPath
            return encodedArtwork
        on error
            try
                close access fileRef
            end try
            return ""
        end try
    end musicArtwork

    on musicSnapshot()
        if application "Music" is running then
            tell application "Music"
                try
                    set theTrack to current track
                    set trackName to name of theTrack
                    set artistName to artist of theTrack
                    set albumName to album of theTrack
                    set playState to player state as string
                    set playPosition to player position as string
                    set trackDuration to ((duration of theTrack) * 1000) as string
                    set shuffleState to shuffle enabled as string
                    set encodedArtwork to my musicArtwork(theTrack)
                    return "music" & linefeed & trackName & linefeed & artistName & linefeed & albumName & linefeed & "" & linefeed & encodedArtwork & linefeed & playState & linefeed & playPosition & linefeed & trackDuration & linefeed & shuffleState
                on error
                    return "NO_TRACK"
                end try
            end tell
        end if
        return "NOT_RUNNING"
    end musicSnapshot

    set spotifyResult to spotifySnapshot()
    set musicResult to musicSnapshot()
    if spotifyResult contains (linefeed & "playing" & linefeed) then return spotifyResult
    if musicResult contains (linefeed & "playing" & linefeed) then return musicResult
    if spotifyResult is not "NOT_RUNNING" and spotifyResult is not "NO_TRACK" then return spotifyResult
    if musicResult is not "NOT_RUNNING" and musicResult is not "NO_TRACK" then return musicResult
    if spotifyResult is "NOT_RUNNING" and musicResult is "NOT_RUNNING" then return "NOT_RUNNING"
    return "NO_TRACK"
    """

    private static func commandScript(spotifyCommand: String, musicCommand: String, player: String) -> String {
        if player == "music" {
            return """
            if application "Music" is running then
                tell application "Music" to \(musicCommand)
            else
                tell application "Music" to activate
            end if
            """
        }

        return """
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client" to \(spotifyCommand)
        else
            tell application id "com.spotify.client" to activate
        end if
        """
    }

    private static func openPlayerScript(player: String) -> String {
        if player == "music" {
            return """
            tell application "Music" to activate
            """
        }

        return """
        tell application id "com.spotify.client" to activate
        """
    }

    private static func shuffleScript(player: String) -> String {
        if player == "music" {
            return """
            if application "Music" is running then
                tell application "Music" to set shuffle enabled to not shuffle enabled
            else
                tell application "Music" to activate
            end if
            """
        }

        return """
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client" to set shuffling to not shuffling
        else
            tell application id "com.spotify.client" to activate
        end if
        """
    }

}
