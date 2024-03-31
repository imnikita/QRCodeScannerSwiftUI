import AVFoundation
import Combine
import SwiftUI

public struct QRScannerView<ViewModel: QRScannerViewModel>: View {

	@ObservedObject var viewModel: ViewModel

	@State private var presentError = false

	private let rectSideSize: CGFloat = 261

	public var body: some View {
		ZStack(alignment: .bottom) {

			ScannerRepresentable(delegate: viewModel, outputDelay: viewModel.errorDismissDelay)

			ZStack {
				Rectangle()
					.foregroundColor(.black.opacity(0.4))

				RoundedRectangle(cornerRadius: 16)
					.frame(width: rectSideSize, height: rectSideSize)
					.blendMode(.destinationOut)
					.overlay {
						ForEach(0...4, id: \.self) { index in
							let rotation = Double(index) * 90
							RoundedRectangle(cornerRadius: 17, style: .circular)
								.trim(from: 0.59, to: 0.66)
								.stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
								.frame(width: rectSideSize, height: rectSideSize)
								.rotationEffect(.init(degrees: rotation))
								.background(Color.clear)
						}
					}
					.overlay {
						Text(viewModel.scannerMessageText)
							.foregroundColor(.white)
							.multilineTextAlignment(.center)
							.offset(x: 0, y: 165)
					}
			}
			.compositingGroup()

			if presentError {
				ScannerErrorView(errorInfo: viewModel.scannerErrorMessage)
					.transition(AnyTransition.move(edge: .bottom)
						.combined(with: .opacity.animation(.smooth)))
					.padding(.bottom, 30)
			}
		}
		.ignoresSafeArea(edges: .all)
		.onChange(of: viewModel.scanResult) { result in
			switch result {
				case .scanFailed:
					showErrorWithAnimation()
					DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(viewModel.errorDismissDelay)) {
						viewModel.scanResult = .idle
					}
				default:
					presentError = false
			}
		}
	}

	public init(viewModel: ViewModel) {
		self.viewModel = viewModel
	}

	private func showErrorWithAnimation() {
		withAnimation {
			presentError = true
		}
	}
}

extension QRScannerView {
	struct ScannerRepresentable: UIViewControllerRepresentable {
		var delegate: QRScannerResultDelegate
		var outputDelay: Int = 3

		func makeUIViewController(context: Context) -> ScannerViewController {
			let scannerViewController = ScannerViewController()
			scannerViewController.delegate = delegate
			scannerViewController.outputDelay = outputDelay
			return scannerViewController
		}

		func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) { }
	}

	class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

		weak var delegate: QRScannerResultDelegate?
		var outputDelay: Int = 3

		private var captureSession = AVCaptureSession()

		let metadataOutput = AVCaptureMetadataOutput()

		private var previewLayer: AVCaptureVideoPreviewLayer?

		private let subject = PassthroughSubject<Void, Never>()
		private var cancelable: AnyCancellable?

		private lazy var rectToScan: CGRect = {
			let screenSize = view.bounds.size
			let rectSideSize: CGFloat = 250
			let rectX = (screenSize.width - rectSideSize) / 2
			let rectY = (screenSize.height - rectSideSize) / 2

			return CGRect(x: rectX, y: rectY, width: rectSideSize, height: rectSideSize)
		}()

		override func viewDidLoad() {
			super.viewDidLoad()

			guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
				delegate?.handleResult(.scanFailed)
				return
			}

			let videoInput: AVCaptureDeviceInput

			do {
				videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
			} catch {
				delegate?.handleResult(.scanFailed)
				return
			}

			if captureSession.canAddInput(videoInput) {
				captureSession.addInput(videoInput)
			} else {
				delegate?.handleResult(.scanFailed)
				return
			}

			if captureSession.canAddOutput(metadataOutput) {
				captureSession.addOutput(metadataOutput)

				metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
				metadataOutput.metadataObjectTypes = [.qr]
			} else {
				delegate?.handleResult(.scanFailed)
				return
			}

			previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
			previewLayer?.frame = view.layer.bounds
			previewLayer?.videoGravity = .resizeAspectFill
			if let previewLayer {
				view.layer.addSublayer(previewLayer)
			}
		}

		override func viewWillAppear(_ animated: Bool) {
			super.viewWillAppear(animated)
			DispatchQueue.global(qos: .background).async {
				self.captureSession.commitConfiguration()
				self.captureSession.startRunning()
			}
		}

		override func viewWillDisappear(_ animated: Bool) {
			super.viewWillDisappear(animated)
			DispatchQueue.global(qos: .background).async {
				self.captureSession.stopRunning()
			}
		}

		private func updatePreviewLayer(layer: AVCaptureConnection, orientation: AVCaptureVideoOrientation) {
			layer.videoOrientation = orientation
			previewLayer?.frame = view.bounds
		}

		override func viewDidLayoutSubviews() {
			super.viewDidLayoutSubviews()

			guard let connection = previewLayer?.connection else {
				delegate?.handleResult(.scanFailed)
				return
			}

			switch UIDevice.current.orientation {
				case .portrait:
					updatePreviewLayer(layer: connection, orientation: .portrait)
				case .landscapeRight:
					updatePreviewLayer(layer: connection, orientation: .landscapeLeft)
				case .landscapeLeft:
					updatePreviewLayer(layer: connection, orientation: .landscapeRight)
				case .portraitUpsideDown:
					updatePreviewLayer(layer: connection, orientation: .portraitUpsideDown)
				default:
					updatePreviewLayer(layer: connection, orientation: .portrait)
			}

			if let previewLayer = previewLayer {
				metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: rectToScan)
			}
		}

		func metadataOutput(_ output: AVCaptureMetadataOutput,
							didOutput metadataObjects: [AVMetadataObject],
							from connection: AVCaptureConnection) {
			guard let metadataObject = metadataObjects.first,
				  let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
				  let stringValue = readableObject.stringValue else {
				return
			}

			cancelable?.cancel()

			cancelable = subject
				.throttle(for: .seconds(outputDelay), scheduler: DispatchQueue.main, latest: false)
				.sink { [weak self] in
					self?.delegate?.handleResult(.scanSuccess(stringValue))
				}

			subject.send()
		}
	}
}

#Preview {
	class ViewModel: QRScannerViewModel {
		var scannerMessageText = "Place the QR code inside the bounding box"
		
		var scanResult = QRScannerOutput.idle
		
		var errorDismissDelay = 3
		
		var noConnectionErrorMessage = (message: "No Internet",
										errorType: QRScannerOutput.idle)
		
		var scannerErrorMessage = (message: "QR code not supported. Please enter a valid QR code and try again.",
								   errorType: QRScannerOutput.idle)
		
		func handleResult(_ result: QRScannerOutput) { }
	}
	return QRScannerView(viewModel: ViewModel())
}
