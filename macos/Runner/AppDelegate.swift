import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Finder "Open With", double-clicks and Dock-icon drops arrive here, not as
  /// command-line arguments. Files received before Dart is listening wait in
  /// [pendingFiles] and are handed over when it calls "ready".
  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pendingFiles: [String] = []

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func attach(to controller: FlutterViewController) {
    attachDisplayBrightness(to: controller)
    attachTrackpad(to: controller)
    let channel = FlutterMethodChannel(
      name: "cru/open_files", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "ready" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.dartReady = true
      result(self.pendingFiles)
      self.pendingFiles = []
    }
    self.channel = channel
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    let files = urls.map { $0.isFileURL ? $0.path : $0.absoluteString }
    if dartReady, let channel = channel {
      channel.invokeMethod("open", arguments: files)
    } else {
      pendingFiles.append(contentsOf: files)
    }
  }

  // MARK: Display brightness

  /// Built-in display brightness through DisplayServices (what the brightness
  /// keys use; IOKit's IODisplayConnect doesn't exist on Apple silicon).
  /// Displays it can't drive (most external monitors) report an error, and
  /// Dart then falls back to adjusting the video instead.
  private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
  private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
  private lazy var displayServices: (GetBrightness, SetBrightness)? = {
    guard
      let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
      let get = dlsym(handle, "DisplayServicesGetBrightness"),
      let set = dlsym(handle, "DisplayServicesSetBrightness")
    else { return nil }
    return (
      unsafeBitCast(get, to: GetBrightness.self), unsafeBitCast(set, to: SetBrightness.self)
    )
  }()

  /// The display showing the player window.
  private func currentDisplay(_ controller: FlutterViewController) -> UInt32 {
    let screen = controller.view.window?.screen ?? NSScreen.main
    let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    return number?.uint32Value ?? CGMainDisplayID()
  }

  private func attachDisplayBrightness(to controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "cru/display", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      guard let self = self, let controller = controller,
        let (get, set) = self.displayServices
      else {
        result(nil)
        return
      }
      let display = self.currentDisplay(controller)
      switch call.method {
      case "get":
        var value: Float = 0
        result(get(display, &value) == 0 ? Double(value) : nil)
      case "set":
        let value = Float((call.arguments as? Double ?? 0).clamped(to: 0...1))
        result(set(display, value) == 0)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    displayChannel = channel
  }
  private var displayChannel: FlutterMethodChannel?

  // MARK: Trackpad finger position

  /// Where the fingers are on the trackpad (0 = left edge, 1 = right), so a
  /// two-finger swipe on the left half can mean brightness and on the right
  /// half volume, wherever the pointer is. Flutter only reports the deltas.
  private var fingerX: Double?
  private var fingerTime: TimeInterval = 0
  private var touchMonitor: Any?

  private func attachTrackpad(to controller: FlutterViewController) {
    controller.view.allowedTouchTypes = [.indirect]
    touchMonitor = NSEvent.addLocalMonitorForEvents(matching: [.gesture]) { [weak self] event in
      let touches = event.touches(matching: .touching, in: nil)
      if !touches.isEmpty {
        self?.fingerX =
          touches.map { Double($0.normalizedPosition.x) }.reduce(0, +) / Double(touches.count)
        self?.fingerTime = event.timestamp
      }
      return event
    }
    let channel = FlutterMethodChannel(
      name: "cru/trackpad", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "fingerX" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // Only a fresh reading belongs to the swipe in progress.
      let fresh = ProcessInfo.processInfo.systemUptime - (self?.fingerTime ?? 0) < 0.5
      result(fresh ? self?.fingerX : nil)
    }
    trackpadChannel = channel
  }
  private var trackpadChannel: FlutterMethodChannel?
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
