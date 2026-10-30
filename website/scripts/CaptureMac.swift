import AppKit
import PhoneCheckCore
import SwiftUI

// Synthetic content only. Production views, no pairing or background services.
@main struct ProductCapture {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1600, height: 900), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.title = "Phone Check — Product capture"
    window.appearance = NSAppearance(named: .darkAqua)
    let hosting = NSHostingView(rootView: CaptureSurface())
    hosting.sizingOptions = []
    window.contentView = hosting
    window.setContentSize(NSSize(width: 1600, height: 900))
    window.setFrameOrigin(NSPoint(x: 0, y: 0))
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
  }
}
// Simulates only phone receipts. All controls, validation, and transitions are production UI.
final class CapturePhone: ObservableObject {
  weak var model: Companion?
  lazy var commands = NotificationCommandController(
    current: { [weak self] key in self?.model?.notices.first { $0.key == key } },
    connected: { true }, send: { [weak self] message in self?.execute(message) })
  private func execute(_ message: Message) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
      guard let self, let model, let id = message.command,
        let current = model.notices.first(where: { $0.key == message.key })
      else { return }
      var items = model.notices
      if message.type == "dismiss" {
        if commands.receiveResult(id: id, status: "removed") != nil {
          items.removeAll { $0.key == current.key }
          commands.notificationRemoved(current.key)
        }
      } else {
        if current.isMedia, let index = items.firstIndex(where: { $0.key == current.key }),
          var media = current.media
        {
          media.position = Int64(media.position(at: Date()))
          media.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
          if message.action == "pause" { media.playing = false }
          if message.action == "play" { media.playing = true }
          if let position = message.position { media.position = position }
          items[index].media = media
          if let i = items[index].actions?.firstIndex(where: {
            $0.mediaControl == "play" || $0.mediaControl == "pause"
          }) {
            items[index].actions?[i].id = media.playing ? "pause" : "play"
            items[index].actions?[i].title = media.playing ? "Pause" : "Play"
            items[index].actions?[i].mediaControl = media.playing ? "pause" : "play"
          }
        }
        _ = commands.receiveResult(id: id, status: "sent")
      }
      model.showPreview(items, battery: model.battery, route: model.connectionRoute ?? .local)
    }
  }
}

final class CaptureScene: ObservableObject { @Published var value = 1 }

struct CaptureSurface: View {
  @StateObject private var model = Companion(startServices: false)
  @StateObject private var scene = CaptureScene()
  @StateObject private var phone = CapturePhone()
  @StateObject private var pairingModel = Companion(startServices: false)
  var body: some View {
    ZStack {
      Image(nsImage: NSImage(data: Data(base64Encoded: asset("vscode-blurred.jpg"))!)!).resizable()
        .scaledToFill().frame(width: 1600, height: 900).clipped()
      VStack {
        CompanionView(
          model: scene.value == 6 ? pairingModel : model, captureCommands: phone.commands
        )
        .scaleEffect(2, anchor: .topTrailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        Spacer(minLength: 0)
      }.padding(.top, 24).padding(.trailing, 80)
      VStack {
        Spacer()
        HStack {
          Button("Before arrival") {
            scene.value = 0
            loadScene()
          }
          Button("Arrived") {
            scene.value = 1
            loadScene()
          }
          Button("Paused") {
            scene.value = 2
            loadScene()
          }
          Button("Dismissed") {
            scene.value = 3
            loadScene()
          }
          Button("Cloud") {
            scene.value = 4
            loadScene()
          }
          Button("Gallery") {
            scene.value = 5
            loadScene()
          }
          Button("Pairing") {
            scene.value = 6
            loadScene()
          }
        }.font(.caption).padding(20)
      }
    }
    .frame(width: 1600, height: 900).clipped()
    .onAppear {
      phone.model = model
      loadScene()
    }
  }
  private func loadScene() {
    if scene.value == 4, !model.notices.isEmpty {
      model.showPreview(model.notices, battery: model.battery, route: .cloud)
      return
    }
    if scene.value == 6 {
      pairingModel.showPairingPreview()
      return
    }
    var conversation = NotificationFixtures.make(.messaging)
    conversation[0].messages?.removeLast()
    conversation[0].app = "Messages"
    conversation[0].appIcon = asset("messages.png")
    var media = NotificationFixtures.make(.media)
    media[0].app = "YouTube Music"
    media[0].appIcon = asset("youtube-music.png")
    media[0].title = "Patient Zero"
    media[0].body = "Taylor Swift · The Life of a Showgirl: The Encore"
    media[0].image = asset("patient-zero-cover.jpg")
    media[0].media?.duration = 225868
    media[0].media?.speed = 1
    var seek = media[0].actions![0]
    seek.id = "seek"
    seek.title = "Seek"
    seek.mediaControl = "seek"
    seek.revision = String(repeating: "a", count: 64)
    media[0].actions?.append(seek)
    media[0].actions?[0].title = "Previous"
    media[0].actions?[1].title = "Pause"
    media[0].actions?[2].title = "Next"
    if scene.value >= 2 {
      media[0].media?.playing = false
      media[0].actions?[1].title = "Play"
      media[0].actions?[1].mediaControl = "play"
    }
    if scene.value == 1, let existing = model.notices.first(where: { $0.isMedia }) {
      media = [existing]
    }
    let incoming = scene.value == 0 || scene.value == 3 || scene.value == 4 ? [] : conversation
    var mail = NotificationFixtures.make(.actions)
    mail[0].app = "Gmail"
    mail[0].appIcon = asset("gmail.png")
    mail[0].title = "Design team"
    mail[0].body = "The updated sketches are ready to review."
    var group = NotificationFixtures.make(.group)
    for index in group.indices {
      group[index].app = "Gmail"
      group[index].appIcon = asset("gmail.png")
    }
    if scene.value == 5 { media = [] }
    model.showPreview(
      media + incoming + mail + (scene.value == 5 ? group : []),
      battery: BatteryStatus(percentage: 73, charging: true, powerSaving: false),
      route: scene.value == 4 ? .cloud : .local)
  }
  private func asset(_ name: String) -> String {
    guard let index = CommandLine.arguments.firstIndex(of: "--assets"),
      CommandLine.arguments.count > index + 1
    else { preconditionFailure("Pass --assets with the product asset directory") }
    let url = URL(fileURLWithPath: CommandLine.arguments[index + 1]).appendingPathComponent(name)
    return try! Data(contentsOf: url).base64EncodedString()
  }
}
