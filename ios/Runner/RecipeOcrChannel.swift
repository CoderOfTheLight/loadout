import Flutter
import PhotosUI
import UIKit
import Vision
import VisionKit

/// Gate 5, OCR half (native side): the `dev.coderofthelight.loadout/recipe_ocr`
/// MethodChannel. Presents the system document camera or photo picker and runs
/// Apple Vision text recognition fully on this device.
///
/// Privacy (threat model): the photo and every recognized string stay in
/// process memory only — nothing is written to disk, nothing is logged, and
/// every FlutterError carries a stable content-free code with a nil message.
final class RecipeOcrChannel: NSObject {

  /// Registers the channel. The method-call-handler closure captures the
  /// instance strongly and the engine retains the handler, so the instance
  /// (and therefore the weak delegates of any presented controller) lives for
  /// the engine's lifetime.
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "LoadoutRecipeOcr") else { return }
    let channel = FlutterMethodChannel(
      name: "dev.coderofthelight.loadout/recipe_ocr", binaryMessenger: registrar.messenger())
    let instance = RecipeOcrChannel()
    channel.setMethodCallHandler { [instance] call, result in
      instance.handle(call, result: result)
    }
  }

  /// Recognition runs here, off the main thread; replies hop back to main.
  private let recognitionQueue = DispatchQueue(
    label: "dev.coderofthelight.loadout.recipe-ocr", qos: .utility)

  /// The reply for the flow currently on screen. Non-nil means a flow is
  /// active: any second call answers `busy` without disturbing it. Mutated on
  /// the main thread only.
  private var pendingResult: FlutterResult?

  /// Strong reference to the presented controller for the active flow;
  /// cleared in every delegate callback.
  private var presentedController: UIViewController?

  /// Marker for "the image could not be turned into something Vision can
  /// read" — mapped to `load_failed` (everything else thrown by the pipeline
  /// maps to `recognition_failed`).
  private enum PipelineError: Error {
    case loadFailed
  }

  // MARK: - Channel dispatch (main thread)

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isCameraScanAvailable":
      // Deployment target is iOS 16.0, so the iOS >= 16 half is a given.
      result(VNDocumentCameraViewController.isSupported)
    case "isPhotoPickAvailable":
      result(true)
    case "scanWithCamera":
      beginCameraScan(result)
    case "pickPhoto":
      beginPhotoPick(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginCameraScan(_ result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: nil, details: nil))
      return
    }
    guard VNDocumentCameraViewController.isSupported, let host = Self.presenter() else {
      result(FlutterError(code: "camera_unavailable", message: nil, details: nil))
      return
    }
    pendingResult = result
    let camera = VNDocumentCameraViewController()
    camera.delegate = self
    presentedController = camera
    host.present(camera, animated: true)
  }

  private func beginPhotoPick(_ result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: nil, details: nil))
      return
    }
    guard let host = Self.presenter() else {
      result(FlutterError(code: "load_failed", message: nil, details: nil))
      return
    }
    pendingResult = result
    // PHPicker runs out of process and needs no photo-library permission.
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    presentedController = picker
    host.present(picker, animated: true)
  }

  /// Answers the pending call exactly once; later calls are no-ops.
  private func finish(_ value: Any?) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let result = pendingResult else { return }
    pendingResult = nil
    result(value)
  }

  /// Topmost view controller of the key window — presenting from the root
  /// itself fails whenever Flutter already has something modal up.
  private static func presenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    let window = windows.first(where: \.isKeyWindow) ?? windows.first
    guard var top = window?.rootViewController else { return nil }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }

  // MARK: - Recognition (utility queue)

  /// Builds the images off the main thread, recognizes them, and finishes on
  /// the main thread with `[String]` or a content-free FlutterError.
  private func recognizeAndFinish(_ makeImages: @escaping () -> [UIImage]) {
    recognitionQueue.async {
      do {
        let lines = try Self.recognizeLines(in: makeImages())
        DispatchQueue.main.async {
          self.finish(lines)
        }
      } catch {
        let code = error is PipelineError ? "load_failed" : "recognition_failed"
        DispatchQueue.main.async {
          self.finish(FlutterError(code: code, message: nil, details: nil))
        }
      }
    }
  }

  /// Pages in scan order; within a page, lines in reading order. One
  /// recognized observation = one line; candidates under 0.3 confidence drop.
  private static func recognizeLines(in images: [UIImage]) throws -> [String] {
    var lines: [String] = []
    for image in images {
      let (cgImage, orientation) = try bitmap(from: image)
      let request = VNRecognizeTextRequest()
      request.revision = VNRecognizeTextRequestRevision3
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
      try handler.perform([request])
      // Vision's normalized coordinates are bottom-up: top-to-bottom reading
      // order means highest maxY first, ties left-to-right by minX.
      let ordered = (request.results ?? []).sorted { a, b in
        if a.boundingBox.maxY != b.boundingBox.maxY {
          return a.boundingBox.maxY > b.boundingBox.maxY
        }
        return a.boundingBox.minX < b.boundingBox.minX
      }
      for observation in ordered {
        guard let candidate = observation.topCandidates(1).first,
          candidate.confidence >= 0.3
        else { continue }
        lines.append(candidate.string)
      }
    }
    return lines
  }

  /// A CGImage plus the orientation Vision should apply. CIImage-backed
  /// UIImages (no cgImage) are redrawn into a plain bitmap, in memory only.
  private static func bitmap(from image: UIImage) throws -> (CGImage, CGImagePropertyOrientation) {
    if let cgImage = image.cgImage {
      return (cgImage, visionOrientation(of: image.imageOrientation))
    }
    let renderer = UIGraphicsImageRenderer(size: image.size)
    let redrawn = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    guard let cgImage = redrawn.cgImage else {
      throw PipelineError.loadFailed
    }
    return (cgImage, .up)
  }

  /// UIKit and ImageIO disagree on orientation raw values; map explicitly.
  private static func visionOrientation(
    of orientation: UIImage.Orientation
  ) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}

// MARK: - Document camera flow

extension RecipeOcrChannel: VNDocumentCameraViewControllerDelegate {

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
  ) {
    presentedController = nil
    controller.dismiss(animated: true)
    recognizeAndFinish {
      (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
    }
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    presentedController = nil
    controller.dismiss(animated: true)
    finish(nil)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFailWithError error: Error
  ) {
    // Content-free by design: the error's description never crosses the
    // channel and is never logged.
    presentedController = nil
    controller.dismiss(animated: true)
    finish(FlutterError(code: "load_failed", message: nil, details: nil))
  }
}

// MARK: - Photo picker flow

extension RecipeOcrChannel: PHPickerViewControllerDelegate {

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    presentedController = nil
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else {
      // Cancel path — including swipe-down dismissal, which also lands here
      // with an empty selection.
      finish(nil)
      return
    }
    guard provider.canLoadObject(ofClass: UIImage.self) else {
      finish(FlutterError(code: "load_failed", message: nil, details: nil))
      return
    }
    provider.loadObject(ofClass: UIImage.self) { object, error in
      // NSItemProvider completes on an arbitrary queue.
      guard error == nil, let image = object as? UIImage else {
        DispatchQueue.main.async {
          self.finish(FlutterError(code: "load_failed", message: nil, details: nil))
        }
        return
      }
      let images = [image]
      self.recognizeAndFinish { images }
    }
  }
}
