import AppKit
import PhoneCheckCore

/// Local, deterministic content for exercising the production notification views.
enum NotificationFixtures {
    enum Kind: String, CaseIterable, Identifiable {
        case text = "Text", bigText = "Long text", inbox = "Inbox", messaging = "Conversation"
        case picture = "Picture", progress = "Progress", indeterminate = "Indeterminate progress"
        case group = "Group", media = "Media", call = "Incoming call", actions = "Actions"
        case choices = "Choice reply", unsupported = "Unsupported action", ongoing = "Non-dismissible"
        case fallback = "Custom layout fallback", redacted = "Redacted content"
        var id: String { rawValue }
    }

    static func make(_ kind: Kind) -> [Notice] {
        var notice = Notice(key: "test-\(kind.rawValue)", app: "Messages", title: "Alex Morgan",
                            body: "Coffee at 10?", revision: "1", dismissible: true, postedAt: 1_793_145_600_000)
        notice.openable = true
        let application: String
        switch kind {
        case .bigText, .inbox, .group, .actions: application = "Mail"
        case .progress: application = "Safari"
        case .indeterminate: application = "App Store"
        case .media: application = "Music"
        case .call: application = "FaceTime"
        case .ongoing: application = "Voice Memos"
        case .fallback: application = "Calendar"
        default: application = "Messages"
        }
        notice.app = application
        notice.appIcon = appIcons[application]
        switch kind {
        case .text: break
        case .bigText:
            notice.title = "Jordan Lee — Design review notes"
            notice.body = "Thanks for walking through the latest mockups today.\n\nThe new navigation is much easier to follow. Let's keep the primary action above the fold and give the empty state a little more breathing room.\n\nFor Thursday's review, could you bring the compact layout, the expanded conversation, and the version with larger text? I'd also like to look at keyboard navigation and how the reply composer behaves with a longer message.\n\nI've added comments to the shared file. No need to address every detail before we meet — the spacing and hierarchy are the priorities.\n\nJordan"
        case .inbox:
            notice.title = "3 new messages"
            notice.lines = ["Jordan — The sketches are ready to review.", "Design team — Friday's catch-up is at 3.", "Sam — Thanks for your feedback!"]
        case .messaging:
            notice.title = "Weekend plans"; notice.kind = "messaging"
            notice.messages = decode(#"[{"sender":"Alex","text":"Coffee at 10?","time":1793145600000,"attachment":false},{"sender":"Sam","text":"See you there.","time":1793145660000,"attachment":false},{"sender":"Alex","text":"","time":1793145720000,"attachment":true}]"#)
            notice.actions = replyActions
        case .picture:
            notice.title = "A moment by the lake"; notice.body = "Here's the view from our picnic spot."
            notice.image = artwork(symbol: "mountain.2.fill", picture: true)
        case .progress, .indeterminate:
            notice.title = kind == .progress ? "Downloading presentation.pdf" : "Updating apps"
            notice.body = kind == .progress ? "18 MB of 40 MB · About 12 seconds remaining" : "Preparing your updates…"
            notice.kind = "progress"; notice.ongoing = true; notice.dismissible = false
            notice.progress = decode(kind == .progress ? #"{"value":45,"max":100,"indeterminate":false}"# : #"{"value":0,"max":100,"indeterminate":true}"#)
        case .group:
            notice.title = "3 new messages"; notice.groupKey = "test-inbox"; notice.groupSummary = true
            notice.actions = ordinaryActions
            var children: [Notice] = []
            for (index, sender) in ["Jordan Lee", "Design team", "Sam Patel"].enumerated() {
                var child = notice
                child.key += "-\(index)"; child.groupSummary = false; child.title = sender
                child.body = ["The updated sketches are ready to review.", "Friday's catch-up is at 3.", "Thanks for your feedback!"][index]
                children.append(child)
            }
            return [notice] + children
        case .media:
            notice.kind = "media"; notice.title = "Dreams"; notice.body = "Fleetwood Mac · Rumours"
            notice.image = artwork(symbol: "music.note", picture: true)
            notice.actions = decode(#"[{"id":"previous","title":"Previous","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false},{"id":"pause","title":"Pause","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false},{"id":"next","title":"Next","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false}]"#)
        case .call:
            notice.kind = "call"; notice.body = "Incoming call"; notice.dismissible = false
            notice.actions = decode(#"[{"id":"decline","title":"Decline","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":true},{"id":"answer","title":"Answer","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false}]"#)
        case .actions:
            notice.title = "Figma — Your weekly design digest"; notice.body = "3 files updated in Product Design. Catch up on the latest changes."
            notice.actions = ordinaryActions
        case .choices:
            notice.title = "Sam Patel"; notice.body = "We’re ordering lunch from the café. Want your usual?"
            notice.actions = replyActions
            notice.actions?[0].freeform = false
        case .unsupported:
            notice.title = "Priya Shah"; notice.body = "Can you send the signed PDF?"
            notice.actions = replyActions; notice.actions?[0].enabled = false
        case .ongoing:
            notice.title = "Recording in progress"; notice.body = "Design standup · 04:32"
            notice.ongoing = true; notice.dismissible = false
        case .fallback:
            notice.title = "Design review in 10 minutes"; notice.body = "2:00–2:30 PM · Conference Room 3"
        case .redacted:
            notice.title = "New message"; notice.body = ""; notice.openable = false
        }
        return [notice]
    }

    /// Use installed public app artwork; never inspect user app data.
    private static let appIcons: [String: String] = {
        let applications = [
            "Messages": "/System/Applications/Messages.app",
            "Mail": "/System/Applications/Mail.app",
            "Safari": "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
            "App Store": "/System/Applications/App Store.app",
            "Music": "/System/Applications/Music.app",
            "FaceTime": "/System/Applications/FaceTime.app",
            "Voice Memos": "/System/Applications/VoiceMemos.app",
            "Calendar": "/System/Applications/Calendar.app"
        ]
        return applications.reduce(into: [:]) { result, entry in
            guard FileManager.default.fileExists(atPath: entry.value) else { return }
            let icon = NSWorkspace.shared.icon(forFile: entry.value)
            result[entry.key] = raster(size: 64, picture: false) { rect in icon.draw(in: rect) }
        }
    }()

    private static var replyActions: [NoticeAction] {
        decode(#"[{"id":"reply","title":"Reply","input":true,"freeform":true,"choices":["Yes","Later","No thanks"],"enabled":true,"requiresUnlock":false,"destructive":false}]"#)
    }
    private static var ordinaryActions: [NoticeAction] {
        var result = replyActions
        let read: [NoticeAction] = decode(#"[{"id":"read","title":"Mark as read","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false},{"id":"archive","title":"Archive","input":false,"freeform":false,"choices":[],"enabled":true,"requiresUnlock":false,"destructive":false}]"#)
        result.append(contentsOf: read)
        return result
    }
    private static func decode<T: Decodable>(_ json: String) -> T {
        // Invalid fixture data is a development error, never external input.
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
    private static func artwork(symbol: String, picture: Bool) -> String? {
        raster(size: picture ? 320 : 64, picture: picture) { rect in
            NSGradient(starting: .systemIndigo, ending: .systemTeal)!.draw(in: rect, angle: 45)
            let mark = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: rect.width * 0.44, weight: .medium))
            mark?.draw(in: rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.24))
        }
    }
    private static func raster(size: CGFloat, picture: Bool, draw: (NSRect) -> Void) -> String? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: picture ? .jpeg : .png, properties: [.compressionFactor: 0.75])?.base64EncodedString()
    }
}
