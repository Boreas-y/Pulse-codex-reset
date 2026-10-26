import AppKit
import SwiftUI

/// Native first-click handling for links inside Pulse's non-key accessory panel.
struct PanelLink: NSViewRepresentable {
    let title: String
    let destination: URL

    func makeNSView(context: Context) -> PanelLinkButton {
        PanelLinkButton()
    }

    func updateNSView(_ button: PanelLinkButton, context: Context) {
        button.destination = destination
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: DetailCardLayout.footnoteFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(destination.absoluteString)
    }
}

@MainActor
final class PanelLinkButton: NSButton {
    var destination: URL?
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .inline
        target = self
        action = #selector(openLink)
        setAccessibilityRole(.link)
    }

    required init?(coder: NSCoder) { return nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func openLink() {
        guard let destination, ["https", "http"].contains(destination.scheme?.lowercased() ?? "") else { return }
        open(destination)
    }
}
