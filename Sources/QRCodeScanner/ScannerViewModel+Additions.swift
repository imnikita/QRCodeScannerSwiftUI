//
//  File.swift
//  
//
//  Created by Mykyta Popov on 31/03/2024.
//

import Combine
import SwiftUI

public protocol QRScannerViewModel: ObservableObject, QRScannerResultDelegate {
	var scannerMessageText: String { get }
	var scanResult: QRScannerOutput { get set }
	var errorDismissDelay: Int { get }
	var scannerErrorMessage: (message: String, errorType: QRScannerOutput) { get }
}

public protocol QRScannerResultDelegate: AnyObject {
	func handleResult(_ result: QRScannerOutput)
}

public enum QRScannerOutput: Equatable {
	case idle, scanSuccess(String), scanFailed
}

struct ScannerErrorView: View {

	var errorInfo: (message: String, errorType: QRScannerOutput)

	var body: some View {
		HStack {
			Image("warning-icon")
				.renderingMode(.original)
				.padding(.horizontal, 10)

			Text(errorInfo.0)
				.font(.system(size: 14))
				.foregroundColor(.black)
				.multilineTextAlignment(.leading)
				.lineLimit(2)

			Spacer()
		}
		.frame(height: 58)
		.background(Color("scan-error-color"))
		.clipShape(RoundedRectangle(cornerRadius: 10))
		.padding(.horizontal, 10)
	}
}
