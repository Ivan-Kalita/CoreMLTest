//
//  ViewController.swift
//  CoreMLCatsDemo
//
//  Created by Dmitriy Rozov on 04/07/2017.
//  Copyright © 2017 Dmitriy Rozov. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

enum ModelClassNames: String {
    case MyCup = "my cup"
    case EverythingElse = "other"
}

class ViewController: UIViewController {

    @IBOutlet var resultLabel: UILabel!
    @IBOutlet var resultView: UIView!

    let session = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer!
    let captureQueue = DispatchQueue(label: "captureQueue")
    var visionRequests = [VNRequest]()

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let camera = AVCaptureDevice.default(for: .video) else {
            return
        }
        do {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            resultView.layer.addSublayer(previewLayer)

            let cameraInput = try AVCaptureDeviceInput(device: camera)
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

            session.sessionPreset = .high
            session.addInput(cameraInput)
            session.addOutput(videoOutput)

            let connection = videoOutput.connection(with: .video)
            connection?.videoOrientation = .portrait
            session.startRunning()

            guard let visionModel = try? VNCoreMLModel(for: TankClassifier().model) else {
                fatalError("Could not load model")
            }

            let classificationRequest = VNCoreMLRequest(model: visionModel, completionHandler: handleClassifications)
            classificationRequest.imageCropAndScaleOption = .centerCrop
            visionRequests = [classificationRequest]
        } catch {
            let alertController = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            present(alertController, animated: true, completion: nil)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.frame
    }

    private func handleClassifications(request: VNRequest, error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            return
        }
        guard let results = request.results as? [VNClassificationObservation] else {
            print("No results")
            return
        }

        let mostConfidentResult = results.sorted { (current, next) -> Bool in
            return current.confidence > next.confidence
        }.first

        let resulConfidence = String(format: "%.2f", mostConfidentResult?.confidence ?? 0)

        let resultString = "\(mostConfidentResult?.identifier ?? "")(\(resulConfidence))"

        DispatchQueue.main.async {
            self.resultLabel.text = resultString
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        var requestOptions: [VNImageOption: Any] = [:]
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: requestOptions)
        do {
            try imageRequestHandler.perform(visionRequests)
        } catch {
            print(error)
        }
    }
}
