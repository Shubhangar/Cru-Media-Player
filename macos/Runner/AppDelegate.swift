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
}
