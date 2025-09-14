import Vision
import CoreML
import UIKit

enum Cleanliness: String { case clean = "Clean", dirty = "Dirty" }
typealias CleanProbs = (label: Cleanliness, pClean: Float, pDirty: Float)

final class CleanlinessClassifier {
    private let vnModel: VNCoreMLModel
    init?() {
        do {
            let model = try Cleanness(configuration: .init()).model
            self.vnModel = try VNCoreMLModel(for: model)
        } catch { return nil }
    }

    /// Возвращает согласованные вероятности (pClean + pDirty = 1).
    /// Если нет явных меток "clean"/"dirty", отдаём безопасный фоллбэк 0.5/0.5.
    func classify(_ image: UIImage) async -> CleanProbs? {
        guard let cg = image.cgImage else { return nil }
        let req = VNCoreMLRequest(model: vnModel)
        req.imageCropAndScaleOption = .centerCrop

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cg).perform([req])
                    guard let arr = req.results as? [VNClassificationObservation], !arr.isEmpty else {
                        cont.resume(returning: nil); return
                    }

                    let cleanObs = arr.first { $0.identifier.lowercased().contains("clean") }
                    let dirtyObs = arr.first { $0.identifier.lowercased().contains("dirty") }

                    if let c = cleanObs, let d = dirtyObs {
                        let sum = max(1e-6, c.confidence + d.confidence)
                        let pClean = Float(c.confidence / sum)
                        cont.resume(returning: (pClean >= 0.5 ? .clean : .dirty, pClean, 1 - pClean))
                    } else if let c = cleanObs {
                        let p = Float(c.confidence)
                        cont.resume(returning: (p >= 0.5 ? .clean : .dirty, p, 1 - p))
                    } else if let d = dirtyObs {
                        let p = Float(d.confidence)
                        cont.resume(returning: (p >= 0.5 ? .dirty : .clean, 1 - p, p))
                    } else {
                        cont.resume(returning: (.clean, 0.5, 0.5))
                    }
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
