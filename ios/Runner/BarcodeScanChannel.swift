import AVFoundation
import Flutter
import UIKit

/// Native side of barcode capture: the
/// `dev.coderofthelight.loadout/barcode_scan` MethodChannel. Presents a
/// full-screen one-shot scanner and resolves on the first detected barcode.
///
/// Privacy (threat model): frames stay inside the capture pipeline and the
/// decoded payload lives in process memory only — nothing is written to
/// disk, nothing is logged, and every FlutterError carries a stable
/// content-free code with a nil message.
final class BarcodeScanChannel: NSObject {

  /// Registers the channel. The method-call-handler closure captures the
  /// instance strongly and the engine retains the handler, so the instance
  /// lives for the engine's lifetime.
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "LoadoutBarcodeScan") else { return }
    let channel = FlutterMethodChannel(
      name: "dev.coderofthelight.loadout/barcode_scan", binaryMessenger: registrar.messenger())
    let instance = BarcodeScanChannel()
    channel.setMethodCallHandler { [instance] call, result in
      instance.handle(call, result: result)
    }
  }

  /// The reply for the flow currently on screen. Non-nil means a flow is
  /// active: any second call answers `busy` without disturbing it. Mutated
  /// on the main thread only.
  private var pendingResult: FlutterResult?

  /// Strong reference to the presented scanner for the active flow; cleared
  /// when its completion fires.
  private var presentedController: UIViewController?

  // MARK: - Channel dispatch (main thread)

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(AVCaptureDevice.default(for: .video) != nil)
    case "scanOne":
      beginScan(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginScan(_ result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: nil, details: nil))
      return
    }
    // The gate is held through the permission prompt too: a second `scanOne`
    // while the system dialog is up answers `busy`.
    pendingResult = result
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      presentScanner()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          if granted {
            self.presentScanner()
          } else {
            self.finish(FlutterError(code: "camera_denied", message: nil, details: nil))
          }
        }
      }
    default:  // .denied, .restricted
      finish(FlutterError(code: "camera_denied", message: nil, details: nil))
    }
  }

  /// Permission is settled; puts the scanner on screen. The completion is
  /// the single funnel for every outcome: detection, cancel (button or any
  /// other dismissal), and a session that could not start.
  private func presentScanner() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let device = AVCaptureDevice.default(for: .video), let host = Self.presenter() else {
      finish(FlutterError(code: "camera_unavailable", message: nil, details: nil))
      return
    }
    let scanner = BarcodeScannerViewController(device: device) { [weak self] outcome in
      guard let self else { return }
      self.presentedController = nil
      switch outcome {
      case .detected(let payload, let symbology):
        self.finish(["payload": payload, "symbology": symbology])
      case .cancelled:
        self.finish(nil)
      case .failed:
        self.finish(FlutterError(code: "camera_unavailable", message: nil, details: nil))
      }
    }
    scanner.modalPresentationStyle = .fullScreen
    presentedController = scanner
    host.present(scanner, animated: true)
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
}

// MARK: - Scanner view controller

/// Full-screen one-shot scanner: camera preview, a dimmed overlay with a
/// clear centered guide, a Cancel button, and a one-line hint. Reports
/// exactly one `Outcome` on the main thread, then dismisses itself.
final class BarcodeScannerViewController: UIViewController {

  enum Outcome {
    case detected(payload: String, symbology: String)
    case cancelled
    case failed
  }

  init(device: AVCaptureDevice, completion: @escaping (Outcome) -> Void) {
    self.device = device
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    // Safety net only; every outcome path already stops the session.
    let session = self.session
    sessionQueue.async {
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  private let device: AVCaptureDevice
  private let completion: (Outcome) -> Void

  /// All capture-session work happens here, never on the main thread.
  private let sessionQueue = DispatchQueue(
    label: "dev.coderofthelight.loadout.barcode-scan", qos: .userInitiated)

  private let session = AVCaptureSession()
  private let metadataOutput = AVCaptureMetadataOutput()
  private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)
  private let dimLayer = CAShapeLayer()
  private let hintLabel = UILabel()

  /// One-shot guard for the completion; read and written on main only.
  private var hasFired = false

  /// Set on main once the session reports it started — the rect-of-interest
  /// conversion is meaningless before then.
  private var sessionIsRunning = false

  /// The symbologies the Dart contract names; anything else is ignored.
  private static let wantedTypes: [AVMetadataObject.ObjectType] = [
    .ean13, .ean8, .upce, .code128, .code39, .itf14, .qr,
  ]

  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  /// Portrait-only keeps the preview, guide, and rect-of-interest mapping
  /// simple; the modal rotates back on dismissal.
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

  // MARK: Lifecycle (main thread)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)

    dimLayer.fillRule = .evenOdd
    dimLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
    view.layer.addSublayer(dimLayer)

    hintLabel.text = "Point at a barcode"
    hintLabel.textColor = .white
    hintLabel.font = .preferredFont(forTextStyle: .subheadline)
    hintLabel.textAlignment = .center
    hintLabel.adjustsFontSizeToFitWidth = true
    view.addSubview(hintLabel)

    let bar = UIView()
    bar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bar)

    let cancelButton = UIButton(type: .system)
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.tintColor = .white
    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    bar.addSubview(cancelButton)

    NSLayoutConstraint.activate([
      bar.topAnchor.constraint(equalTo: view.topAnchor),
      bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
      cancelButton.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      cancelButton.centerYAnchor.constraint(equalTo: bar.bottomAnchor, constant: -22),
    ])

    NotificationCenter.default.addObserver(
      self, selector: #selector(sessionDidStartRunning),
      name: .AVCaptureSessionDidStartRunning, object: session)

    sessionQueue.async {
      self.configureAndStartSession()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = view.bounds
    let guide = Self.guideRect(in: bounds)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    dimLayer.frame = bounds
    let path = UIBezierPath(rect: bounds)
    path.append(UIBezierPath(roundedRect: guide, cornerRadius: 16))
    dimLayer.path = path.cgPath
    CATransaction.commit()

    hintLabel.frame = CGRect(x: 16, y: guide.maxY + 16, width: bounds.width - 32, height: 22)
    updateRectOfInterest()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Catch-all for any dismissal that did not go through the button or a
    // detection — same discipline as the OCR channel's delegate paths.
    fire(.cancelled, dismissing: false)
  }

  @objc private func cancelTapped() {
    fire(.cancelled, dismissing: true)
  }

  /// Reports the outcome exactly once, stops the session, and (when asked)
  /// starts the dismissal. Later calls are no-ops.
  private func fire(_ outcome: Outcome, dismissing: Bool) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard !hasFired else { return }
    hasFired = true
    stopSession()
    if dismissing {
      dismiss(animated: true)
    }
    completion(outcome)
  }

  // MARK: Guide geometry (main thread)

  /// Centered guide rectangle: ~80% of the width, ~35% of the height.
  private static func guideRect(in bounds: CGRect) -> CGRect {
    let size = CGSize(width: bounds.width * 0.8, height: bounds.height * 0.35)
    return CGRect(
      x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
      width: size.width, height: size.height)
  }

  /// Limits detection to the guide. Valid only once the preview layer has
  /// laid out AND the session runs, so it re-runs from both triggers.
  private func updateRectOfInterest() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard sessionIsRunning, view.bounds.width > 0, view.bounds.height > 0 else { return }
    let converted = previewLayer.metadataOutputRectConverted(
      fromLayerRect: Self.guideRect(in: view.bounds))
    sessionQueue.async {
      self.metadataOutput.rectOfInterest = converted
    }
  }

  @objc private func sessionDidStartRunning(_ notification: Notification) {
    // Posted on an arbitrary queue; state hops to main.
    DispatchQueue.main.async {
      self.sessionIsRunning = true
      self.updateRectOfInterest()
    }
  }

  // MARK: Capture session (session queue)

  private func configureAndStartSession() {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    session.beginConfiguration()
    guard
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input), session.canAddOutput(metadataOutput)
    else {
      session.commitConfiguration()
      DispatchQueue.main.async {
        self.fire(.failed, dismissing: true)
      }
      return
    }
    session.addInput(input)
    session.addOutput(metadataOutput)
    metadataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
    // The symbology filter is only settable AFTER the output joins the
    // session (available types are empty before that).
    let available = Set(metadataOutput.availableMetadataObjectTypes)
    let types = Self.wantedTypes.filter { available.contains($0) }
    guard !types.isEmpty else {
      session.commitConfiguration()
      DispatchQueue.main.async {
        self.fire(.failed, dismissing: true)
      }
      return
    }
    metadataOutput.metadataObjectTypes = types
    session.commitConfiguration()
    session.startRunning()
    guard session.isRunning else {
      DispatchQueue.main.async {
        self.fire(.failed, dismissing: true)
      }
      return
    }
  }

  private func stopSession() {
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }

  /// Short stable names for the Dart side; unmapped types never fire.
  private static func symbologyName(_ type: AVMetadataObject.ObjectType) -> String? {
    switch type {
    case .ean13: return "ean13"
    case .ean8: return "ean8"
    case .upce: return "upce"
    case .code128: return "code128"
    case .code39: return "code39"
    case .itf14: return "itf14"
    case .qr: return "qr"
    default: return nil
    }
  }
}

// MARK: - Metadata detection

extension BarcodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {

  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    // Session queue. The first machine-readable object with a non-empty
    // payload wins; `fire` on main makes every later callback a no-op.
    for object in metadataObjects {
      guard let readable = object as? AVMetadataMachineReadableCodeObject,
        let payload = readable.stringValue, !payload.isEmpty,
        let symbology = Self.symbologyName(readable.type)
      else { continue }
      DispatchQueue.main.async {
        self.fire(.detected(payload: payload, symbology: symbology), dismissing: true)
      }
      return
    }
  }
}
