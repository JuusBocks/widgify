import AppIntents
import WidgetKit

enum SpotifyCommand: String, AppEnum {
    case previous
    case play
    case pause
    case playPause
    case next
    case shuffle
    case openSpotify

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Spotify Command")

    static let caseDisplayRepresentations: [SpotifyCommand: DisplayRepresentation] = [
        .previous: "Previous",
        .play: "Play",
        .pause: "Pause",
        .playPause: "Play or Pause",
        .next: "Next",
        .shuffle: "Shuffle",
        .openSpotify: "Open Player"
    ]
}

enum LyricsPageDirection: String, AppEnum {
    case previous
    case next

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lyrics Page Direction")

    static let caseDisplayRepresentations: [LyricsPageDirection: DisplayRepresentation] = [
        .previous: "Previous Page",
        .next: "Next Page"
    ]
}

struct SpotifyCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Control Spotify"
    static let description = IntentDescription("Controls playback in the local Spotify app.")
    static let openAppWhenRun = false

    @Parameter(title: "Command")
    var command: SpotifyCommand

    init() {
        command = .playPause
    }

    init(command: SpotifyCommand) {
        self.command = command
    }

    func perform() async throws -> some IntentResult {
        SpotifyReader.send(command)
        WidgetCenter.shared.reloadTimelines(ofKind: SpotifyWidgetConstants.kind)
        return .result()
    }
}

struct LyricsPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Lyrics Page"
    static let description = IntentDescription("Changes the visible lyrics page for plain lyrics.")
    static let openAppWhenRun = false

    @Parameter(title: "Track Key")
    var trackKey: String

    @Parameter(title: "Direction")
    var direction: LyricsPageDirection

    @Parameter(title: "Maximum Page")
    var maxPage: Int

    init() {
        trackKey = ""
        direction = .next
        maxPage = 0
    }

    init(trackKey: String, direction: LyricsPageDirection, maxPage: Int) {
        self.trackKey = trackKey
        self.direction = direction
        self.maxPage = maxPage
    }

    func perform() async throws -> some IntentResult {
        LyricsPageStore.move(trackKey: trackKey, direction: direction, maxPage: maxPage)
        WidgetCenter.shared.reloadTimelines(ofKind: SpotifyWidgetConstants.kind)
        return .result()
    }
}
