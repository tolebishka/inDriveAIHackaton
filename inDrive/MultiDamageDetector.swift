import Foundation
import Vision
import CoreML
import UIKit

/// Объединяет вывод двух детекторов
final class MultiDamageDetector {
    private let detectors: [CarDamageDetector]
    private let iouThr: CGFloat = 0.5

    init?() {
        do {
            let models: [MLModel] = [
                try Scratches(configuration: .init()).model,
                try Dent(configuration: .init()).model,
                try Rust(configuration: .init()).model,
                try Cleanness(configuration: .init()).model
            ]
            self.detectors = models.compactMap { CarDamageDetector(mlModel: $0) }
        } catch { return nil }
    }

    func detect(in image: UIImage) async -> [Detection] {
        let results = await withTaskGroup(of: [Detection].self) { group -> [[Detection]] in
            for d in detectors { group.addTask { await d.detect(in: image) } }
            var out: [[Detection]] = []
            for await r in group { out.append(r) }
            return out
        }
        return fuse(results.flatMap { $0 })
    }

    func detect(pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation = .right) -> [Detection] {
        let all = detectors.flatMap { $0.detect(pixelBuffer: pixelBuffer, orientation: orientation) }
        return fuse(all)
    }

    private func fuse(_ all: [Detection]) -> [Detection] {
        // можно оставить твой NMS из CombinedDamageDetector
        return all
    }
}
