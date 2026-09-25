# Widgify

A native macOS desktop widget for Spotify. It shows the current track, album art, progress, playback controls, and lyrics in a compact WidgetKit experience that can sit on the desktop.

The project includes:

- Small, medium, and large WidgetKit layouts.
- Album-art focused layouts that scale from small to extra large.
- Play, pause, previous, and next controls.
- A live progress display without direct scrubbing.
- Synced and plain lyrics from [LRCLIB](https://lrclib.net).
- Plain-lyrics page controls for tracks without synced lyrics.
- A tiny menu bar helper that keeps a local bridge running for faster Spotify control.

## Requirements

- macOS 14 or newer.
- Xcode with the macOS SDK.
- Spotify desktop app installed.
- An Apple ID signed into Xcode. A free Personal Team is enough for local use.

## Build With Xcode

Use the Xcode project when you want the widget to appear in macOS's desktop widget picker.

1. Open `SpotifyWidgetMac.xcodeproj` in Xcode.
2. Select the `SpotifyWidgetMac` project in the navigator.
3. Select the `SpotifyWidgetMac` target, then `Signing & Capabilities`.
4. Enable `Automatically manage signing`.
5. Choose your Apple ID or Personal Team.
6. Repeat steps 3-5 for the `SpotifyWidgetExtension` target.
7. Build and run the `SpotifyWidgetMac` scheme.
8. Open the desktop widget picker and search for `Widgify`.

Default bundle identifiers:

```text
com.leounib.Widgify
com.leounib.Widgify.SpotifyWidgetExtension
```

If Xcode says a bundle identifier is unavailable, change `leounib` to something unique in both targets.

## Install Locally

After a successful Xcode build, copy the app into `/Applications` and launch it:

```bash
cp -R "$HOME/Library/Developer/Xcode/DerivedData/SpotifyWidgetMac-"*/Build/Products/Debug/"Widgify.app" /Applications/
open "/Applications/Widgify.app"
```

For a deterministic command-line build that keeps output inside this repository, replace `YOUR_TEAM_ID` with your Apple Developer Team ID or omit that setting after configuring signing in Xcode:

```bash
xcodebuild \
  -project SpotifyWidgetMac.xcodeproj \
  -scheme SpotifyWidgetMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  -allowProvisioningUpdates \
  build

cp -R build/DerivedData/Build/Products/Debug/"Widgify.app" /Applications/
open "/Applications/Widgify.app"
```

Then add the widget:

1. Control-click the desktop.
2. Choose `Edit Widgets`.
3. Search for `Widgify`.
4. Drag the widget to the desktop.

Approve macOS Automation access if prompted. The widget reads and controls the local Spotify app with AppleScript.

## Helper App

The app runs as a menu bar utility. It does not open a normal player window.

The menu bar icon exists because WidgetKit extensions are short-lived. The helper app runs a localhost bridge on `127.0.0.1:47391`, caches Spotify metadata, and sends playback commands. This makes the widget controls much more reliable than asking the widget extension to run AppleScript directly every time.

## Lyrics

Lyrics are fetched from LRCLIB using track title, artist, album, and duration. When synced lyrics are available, the large widget highlights the current line. When only plain lyrics are available, the large widget shows page controls.

LRCLIB may not have every song. Spotify itself does not expose full lyrics through its documented public API.

## Manual Build Script

There is also a script for local compile checks:

```bash
./scripts/build-app.sh
```

The app bundle is created at:

```text
build/Widgify.app
```

This path is useful for development, but the Xcode build with your Apple Team is the recommended route for a real desktop widget install.

## Troubleshooting

- If the widget does not update after a rebuild, remove it from the desktop and add it again.
- If controls stop working, make sure `Widgify.app` is running in the menu bar.
- If macOS asks for Automation permission, allow Spotify access.
- If the widget picker does not show the widget, rebuild from Xcode with a real Apple Team selected and launch the app once.
- If lyrics are missing, the current track likely is not in LRCLIB.

## Privacy

The app talks to:

- Spotify locally through AppleScript.
- `127.0.0.1:47391` between the helper app and widget extension.
- `lrclib.net` for lyrics lookup.

No Spotify account credentials are used or stored by this app.
