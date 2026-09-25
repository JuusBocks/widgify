import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        SpotifySnapshotServer.shared.start()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "music.note.tv", accessibilityDescription: "Widgify")
                ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "Widgify")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Widgify"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Widgify", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Add from Desktop > Edit Widgets", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
}
