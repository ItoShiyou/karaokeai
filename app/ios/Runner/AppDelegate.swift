import AVFoundation
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var karaoke: KaraokeAudio?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KaraokeAudio") {
      karaoke = KaraokeAudio(messenger: registrar.messenger())
    }
  }
}

/// Bridges Dart (`app.karaokeai/{audio,tts,remote}`) to AVFoundation.
/// Kept in this file so it is part of the Runner target without editing the .xcodeproj.
final class KaraokeAudio: NSObject, FlutterStreamHandler, AVSpeechSynthesizerDelegate {
  private var events: FlutterEventSink?
  private let synth = AVSpeechSynthesizer()
  private var speakResult: FlutterResult?
  private let work = DispatchQueue(label: "karaokeai.work", qos: .userInitiated)

  // Active sing session state.
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var recorded = Data()
  private let lock = NSLock()
  private var finishing = false
  private var playResult: FlutterResult?
  private var recordRate: Double = 16000

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    synth.delegate = self
    FlutterMethodChannel(name: "app.karaokeai/audio", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.onAudio(call, result) }
    FlutterMethodChannel(name: "app.karaokeai/tts", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.onTts(call, result) }
    FlutterEventChannel(name: "app.karaokeai/remote", binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  // MARK: Flutter channels

  private func onAudio(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestMicPermission":
      requestMic { result($0) }
    case "currentRoute":
      do {
        try configureSession()
        result(currentRoute())
      } catch { result(FlutterError(code: "session", message: "\(error)", details: nil)) }
    case "decodeToWav":
      guard let src = args["src"] as? String, let dst = args["dst"] as? String else {
        return result(FlutterError(code: "args", message: "src/dst", details: nil))
      }
      work.async {
        do {
          try Self.decodeToWav(src: src, dst: dst)
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "decode", message: "\(error)", details: nil))
          }
        }
      }
    case "playAndRecord":
      guard let path = args["path"] as? String else {
        return result(FlutterError(code: "args", message: "path", details: nil))
      }
      startPlayAndRecord(path: path, recordRate: (args["recordRate"] as? Double) ?? 16000, result: result)
    case "stop":
      finishSession()
      result(nil)
    case "startSession":
      do {
        try configureSession()
        try AVAudioSession.sharedInstance().setActive(true)
        setupRemoteCommands()
        result(nil)
      } catch { result(FlutterError(code: "session", message: "\(error)", details: nil)) }
    case "endSession":
      teardownRemoteCommands()
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      result(nil)
    case "excludeFromBackup":
      guard let path = args["path"] as? String else { return result(nil) }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func onTts(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "speak" else { return result(FlutterMethodNotImplemented) }
    let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
    speakResult?(nil) // never leave an earlier call hanging
    speakResult = result
    let u = AVSpeechUtterance(string: text)
    u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
    synth.speak(u)
  }

  func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
    speakResult?(nil)
    speakResult = nil
  }

  func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
    speakResult?(nil)
    speakResult = nil
  }

  // MARK: Audio session

  private func requestMic(_ done: @escaping (Bool) -> Void) {
    let cb: (Bool) -> Void = { granted in DispatchQueue.main.async { done(granted) } }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: cb)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(cb)
    }
  }

  /// Input = built-in mic only; Bluetooth is output-only (A2DP), never HFP,
  /// so a car's hands-free mic is not used and music quality is kept.
  private func configureSession() throws {
    let s = AVAudioSession.sharedInstance()
    try s.setCategory(
      .playAndRecord, mode: .default,
      options: [.allowBluetoothA2DP, .defaultToSpeaker])
    try s.setActive(true)
    if let mic = s.availableInputs?.first(where: { $0.portType == .builtInMic }) {
      try? s.setPreferredInput(mic)
    }
  }

  private func currentRoute() -> String {
    let types = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType }
    if types.contains(where: { $0 == .bluetoothA2DP || $0 == .bluetoothLE || $0 == .bluetoothHFP }) {
      return "bluetooth"
    }
    if types.contains(where: { $0 == .usbAudio || $0 == .carAudio }) { return "usb" }
    if types.contains(where: { $0 == .headphones || $0 == .headsetMic || $0 == .lineOut }) {
      return "wired"
    }
    return "speaker"
  }

  // MARK: Play + record

  private func startPlayAndRecord(path: String, recordRate: Double, result: @escaping FlutterResult) {
    lock.lock()
    let busy = engine != nil
    lock.unlock()
    if busy { return result(FlutterError(code: "busy", message: "session running", details: nil)) }
    do {
      try configureSession()
      let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
      let eng = AVAudioEngine()
      let node = AVAudioPlayerNode()
      eng.attach(node)
      eng.connect(node, to: eng.mainMixerNode, format: file.processingFormat)

      let input = eng.inputNode
      let inFormat = input.outputFormat(forBus: 0)
      guard let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: recordRate, channels: 1, interleaved: true),
        let converter = AVAudioConverter(from: inFormat, to: target)
      else {
        return result(FlutterError(code: "format", message: "mic format", details: nil))
      }
      self.recordRate = recordRate
      lock.lock()
      recorded = Data()
      finishing = false
      engine = eng
      player = node
      playResult = result
      lock.unlock()

      input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buf, _ in
        guard let self = self else { return }
        let ratio = target.sampleRate / inFormat.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
        var supplied = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
          if supplied {
            status.pointee = .noDataNow
            return nil
          }
          supplied = true
          status.pointee = .haveData
          return buf
        }
        if err == nil, let ch = out.int16ChannelData, out.frameLength > 0 {
          self.lock.lock()
          self.recorded.append(Data(bytes: ch[0], count: Int(out.frameLength) * 2))
          self.lock.unlock()
        }
      }

      try eng.start()
      node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        // Keep recording briefly so output latency doesn't cut off the tail.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.finishSession() }
      }
      node.play()
      updateNowPlaying()
    } catch {
      cleanupEngine()
      result(FlutterError(code: "audio", message: "\(error)", details: nil))
    }
  }

  /// Idempotent: called on natural end, on stop(), or from remote commands.
  private func finishSession() {
    lock.lock()
    if finishing || engine == nil {
      lock.unlock()
      return
    }
    finishing = true
    let res = playResult
    playResult = nil
    lock.unlock()

    player?.stop()
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()

    lock.lock()
    let data = recorded
    lock.unlock()
    cleanupEngine()
    res?(["pcm": FlutterStandardTypedData(bytes: data), "sampleRate": Int(recordRate)])
  }

  private func cleanupEngine() {
    lock.lock()
    engine = nil
    player = nil
    lock.unlock()
  }

  // MARK: Decode

  static func decodeToWav(src: String, dst: String) throws {
    let input = try AVAudioFile(forReading: URL(fileURLWithPath: src))
    let fmt = input.processingFormat
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: fmt.sampleRate,
      AVNumberOfChannelsKey: fmt.channelCount,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]
    let url = URL(fileURLWithPath: dst)
    try? FileManager.default.removeItem(at: url)
    // Scoped so the file is closed (header finalized) before returning.
    do {
      let output = try AVAudioFile(
        forWriting: url, settings: settings,
        commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
      guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 16384) else {
        throw NSError(domain: "karaokeai", code: 1)
      }
      while input.framePosition < input.length {
        try input.read(into: buf, frameCount: 16384)
        if buf.frameLength == 0 { break }
        try output.write(from: buf)
      }
    }
  }

  // MARK: Remote commands (Bluetooth / car buttons)

  private func setupRemoteCommands() {
    let c = MPRemoteCommandCenter.shared()
    func bind(_ cmd: MPRemoteCommand, _ name: String) {
      cmd.isEnabled = true
      cmd.removeTarget(nil)
      cmd.addTarget { [weak self] _ in
        self?.events?(name)
        return .success
      }
    }
    bind(c.nextTrackCommand, "next")
    bind(c.previousTrackCommand, "previous")
    bind(c.togglePlayPauseCommand, "playPause")
    bind(c.playCommand, "playPause")
    bind(c.pauseCommand, "playPause")
    updateNowPlaying()
  }

  private func teardownRemoteCommands() {
    let c = MPRemoteCommandCenter.shared()
    [c.nextTrackCommand, c.previousTrackCommand, c.togglePlayPauseCommand, c.playCommand, c.pauseCommand]
      .forEach { $0.removeTarget(nil) }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func updateNowPlaying() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: "KaraokeAI",
      MPNowPlayingInfoPropertyPlaybackRate: 1.0,
    ]
  }

  // MARK: FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.events = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    return nil
  }
}
