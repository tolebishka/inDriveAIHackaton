import Foundation
import Vision
import CoreML
import UIKit

// ---------- Модель детекции ----------
struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect   
    let areaFraction: CGFloat // доля площади кадра 0..1
}

final class CarDamageDetector {
    
    convenience init?(mlModel: MLModel) {
        do {
            let vn = try VNCoreMLModel(for: mlModel)
            self.init(vnModel: vn)
        } catch { return nil }
    }
    
    private init?(vnModel: VNCoreMLModel) {
        self.vnModel = vnModel
    }
    private let vnModel: VNCoreMLModel

    var confidenceThreshold: Float = 0.35
    var minArea: CGFloat = 0.01 // 1%


    // ---------- LIVE: детекция по CVPixelBuffer (для камеры) ----------
    func detect(pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation = .right) -> [Detection] {

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit

        var out: [Detection] = []
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            try handler.perform([request])
            let results = (request.results as? [VNRecognizedObjectObservation]) ?? []
            for obs in results {
                guard let top = obs.labels.first else { continue }
                let conf = top.confidence
                // ❌ убираем фильтр по threshold
                let area = obs.boundingBox.width * obs.boundingBox.height
                guard area >= minArea else { continue }
                out.append(Detection(label: top.identifier,
                                     confidence: conf,          // ← сколько реально даёт модель
                                     boundingBox: obs.boundingBox,
                                     areaFraction: area))
            }
        } catch { }
        return out
    }

    // ---------- PHOTO: детекция по UIImage (галерея/снимок) ----------
    func detect(in image: UIImage) async -> [Detection] {
        guard let cg = image.cgImage else { return [] }

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var out: [Detection] = []
                do {
                    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                    try handler.perform([request])
                    let results = (request.results as? [VNRecognizedObjectObservation]) ?? []
                    for obs in results {
                        guard let top = obs.labels.first else { continue }
                        let conf = top.confidence
                        // ❌ убираем фильтр по threshold
                        let area = obs.boundingBox.width * obs.boundingBox.height
                        if area < self.minArea { continue }
                        out.append(Detection(label: top.identifier,
                                             confidence: conf,
                                             boundingBox: obs.boundingBox,
                                             areaFraction: area))
                    }
                } catch { }
                cont.resume(returning: out)
            }
        }
    }

}
