import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBackupExclusionChannel(with: engineBridge.pluginRegistry)
  }

  /// Design §7.2/§10: bootstrap asks for `NSURLIsExcludedFromBackupKey` on the
  /// app-support `db/` and `scratch/` directories so ciphertext and staging
  /// never enter iCloud/iTunes backups.
  private func registerBackupExclusionChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "LoadoutBackupExclusion") else { return }
    let channel = FlutterMethodChannel(
      name: "loadout/backup_exclusion", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(FlutterError(code: "backup_exclusion_failed", message: nil, details: nil))
      }
    }
  }
}
