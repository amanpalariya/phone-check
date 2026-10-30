import AVFoundation
import AppKit
import Foundation
import ScreenCaptureKit

// Records only the isolated capture fixture, never a desktop or unrelated window.
final class WindowRecorder: NSObject, SCStreamOutput {
  let writer: AVAssetWriter
  let input: AVAssetWriterInput
  private var firstTime: CMTime?
  private(set) var frames = 0
  init(url: URL) throws {
    writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 3200, AVVideoHeightKey: 1864,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: 40_000_000,
          AVVideoExpectedSourceFrameRateKey: 60,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
          AVVideoMaxKeyFrameIntervalKey: 120,
        ],
      ])
    input.expectsMediaDataInRealTime = true
    super.init()
    writer.add(input)
  }
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType
  ) {
    guard type == .screen, sample.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
        as? [[SCStreamFrameInfo: Any]],
      let status = attachments.first?[.status] as? Int,
      status == SCFrameStatus.complete.rawValue
    else { return }
    let time = sample.presentationTimeStamp
    if firstTime == nil {
      firstTime = time
      writer.startWriting()
      writer.startSession(atSourceTime: time)
      print("FIRST_FRAME_UNIX_MS \(Int64(Date().timeIntervalSince1970 * 1000))")
      fflush(stdout)
    }
    if input.isReadyForMoreMediaData {
      input.append(sample)
      frames += 1
    }
  }
  func finish() async {
    input.markAsFinished()
    await writer.finishWriting()
    print("RECORDED_FRAMES \(frames)")
    if let error = writer.error { print("WRITER_ERROR \(error)") }
  }
}

@main struct NativeCapture {
  @MainActor static func main() async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    guard CommandLine.arguments.count == 2 else { fatalError("Pass one output .mov path") }
    let content = try await SCShareableContent.excludingDesktopWindows(
      true, onScreenWindowsOnly: false)
    guard
      let window = content.windows.first(where: {
        $0.owningApplication?.bundleIdentifier == "dev.phonecheck.product-capture"
          && $0.title == "Phone Check — Product capture"
      })
    else { fatalError("Product capture fixture is not running") }
    let recorder = try WindowRecorder(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    let config = SCStreamConfiguration()
    config.width = 3200
    config.height = 1864
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.queueDepth = 8
    config.showsCursor = true
    config.capturesAudio = false
    config.pixelFormat = kCVPixelFormatType_32BGRA
    let stream = SCStream(
      filter: SCContentFilter(desktopIndependentWindow: window), configuration: config,
      delegate: nil)
    try stream.addStreamOutput(
      recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "phonecheck.capture"))
    try await stream.startCapture()
    print("RECORDING_READY — send a newline to stop")
    fflush(stdout)
    await Task.detached { _ = readLine() }.value
    try await stream.stopCapture()
    await recorder.finish()
  }
}
