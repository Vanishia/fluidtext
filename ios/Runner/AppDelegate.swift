import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var externalEpubChannel: FlutterMethodChannel?
  private var pendingEpubFiles = [[String: String]]()
  private let epubCopyQueue = DispatchQueue(label: "fluidtext.external-epub")
  private let epubCacheDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("external_epub", isDirectory: true)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "fluidtext/external_epub", binaryMessenger: controller.binaryMessenger)
      externalEpubChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return result(nil) }
        switch call.method {
        case "takePendingFiles":
          let files = self.pendingEpubFiles
          self.pendingEpubFiles.removeAll()
          result(files)
        case "releaseFile":
          if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
            let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let directory = self.epubCacheDirectory.standardizedFileURL.resolvingSymlinksInPath()
            if file.deletingLastPathComponent() == directory {
              try? FileManager.default.removeItem(at: file)
            }
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.isFileURL, url.pathExtension.lowercased() == "epub" else {
      return super.application(app, open: url, options: options)
    }
    let hasScopedAccess = url.startAccessingSecurityScopedResource()
    epubCopyQueue.async { [self] in
      defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }
      let copy = epubCacheDirectory.appendingPathComponent(UUID().uuidString + ".epub")
      var payload = ["name": url.lastPathComponent]
      do {
        try FileManager.default.createDirectory(
          at: epubCacheDirectory, withIntermediateDirectories: true, attributes: nil)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
          readingItemAt: url, options: .withoutChanges, error: &coordinationError
        ) { readableURL in
          do { try FileManager.default.copyItem(at: readableURL, to: copy) }
          catch { copyError = error }
        }
        if let error = coordinationError { throw error }
        if let error = copyError { throw error }
        payload["path"] = copy.path
      } catch {
        try? FileManager.default.removeItem(at: copy)
        payload["error"] = error.localizedDescription
      }
      DispatchQueue.main.async { [self, payload] in
        pendingEpubFiles.append(payload)
        externalEpubChannel?.invokeMethod("filesAvailable", arguments: nil)
      }
    }
    return true
  }
}
