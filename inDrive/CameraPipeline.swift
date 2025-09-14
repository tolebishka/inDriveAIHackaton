import Foundation
import AVFoundation
import Vision
import UIKit

/// Паблишим эти детекции в SwiftUI-оверлей
final class CameraPipeline: NSObject, ObservableObject {
    // Параметры (можешь подправить)
    private let targetFPS: Double = 10.0           // ограничим ИИ до ~10 кадров/с
    private let sessionPreset: AVCaptureSession.Preset = .hd1280x720

    // Публичные стейты для UI
    @Published var detections: [Detection] = []
    @Published var frameSize: CGSize = .zero       // реальный размер исходного кадра (px)
    @Published var isRunningInference: Bool = false

    // Камера
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.queue")
    private var lastInferenceTime = CFAbsoluteTimeGetCurrent()
    private var isBusy = false

    // Детектор (переиспользуем твою модель и пороги)
    private let detector = MultiDamageDetector()

    override init() {
        super.init()
        configureSession()
    }

    func start() {
        if !session.isRunning { session.startRunning() }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = sessionPreset

        // Камера: задняя
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("No camera")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Видео-выход
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                        kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else {
            print("Can't add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        // Ориентация превью
        videoOutput.connection(with: .video)?.videoOrientation = .portrait

        session.commitConfiguration()
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Троттлинг по FPS
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastInferenceTime < (1.0 / targetFPS) { return }
        lastInferenceTime = now

        // Один инференс за раз
        if isBusy { return }
        isBusy = true
        DispatchQueue.main.async { self.isRunningInference = true }

        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { self.isBusy = false; return }

        // Размер кадра (px) для корректной отрисовки
        let w = CVPixelBufferGetWidth(pixel)
        let h = CVPixelBufferGetHeight(pixel)
        DispatchQueue.main.async { self.frameSize = CGSize(width: w, height: h) }

        // Ориентация для Vision
        let orient: CGImagePropertyOrientation = .right  // back camera, portrait

        // Прогон через модель (используем новый метод на CVPixelBuffer)
        let result = detector?.detect(pixelBuffer: pixel, orientation: orient) ?? []

        DispatchQueue.main.async {
            self.detections = result
            self.isRunningInference = false
            self.isBusy = false
        }
    }
}
