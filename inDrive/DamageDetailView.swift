import SwiftUI
import AVFoundation

fileprivate let brand = Color(red: 0.756, green: 0.945, blue: 0.114)

struct DamageDetailView: View {
    let image: UIImage?
    let detections: [Detection]

    /// Покрытие по классам (0..1) и общее покрытие (0..1) — получаем с главного экрана
    let perClassCoverage: [String: CGFloat]
    let totalCoverage: CGFloat

    private let classes = ["scratch","dent","rust"]

    private var perClassMax: [(name: String, score: Float)] {
        classes.map { cls in
            let s = detections.filter { $0.label.lowercased() == cls }
                              .map(\.confidence).max() ?? 0
            return (name: cls.capitalized, score: s)
        }
    }

    private var damageAvg: Float {
        let avg = perClassMax.map(\.score).reduce(0, +) / Float(perClassMax.count)
        return max(0, min(1, avg))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(image.size, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        // Боксы поверх картинки
                        GeometryReader { ig in
                            let S = ig.size
                            ForEach(detections) { det in
                                let r = rectInImageSpace(det.boundingBox, imageSize: S)
                                Rectangle()
                                    .stroke(color(for: det.label), lineWidth: 2)
                                    .frame(width: r.width, height: r.height)
                                    .position(x: r.midX, y: r.midY)
                            }
                        }
                    }
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                    .padding(.horizontal)
                }

                // Итоговые проценты: вероятность + покрытие
                VStack(alignment: .leading, spacing: 12) {
                    Text("Итоговая повреждённость").font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(damageAvg*100))%").font(.title2.bold())
                        Text("Покрытие: \(Int(totalCoverage*100))%").foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(damageAvg)).tint(brand)
                }
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(brand.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                .padding(.horizontal)

                // Разбивка по классам: уверенность (max) + покрытие
                VStack(alignment: .leading, spacing: 12) {
                    Text("По типам дефектов").font(.subheadline).foregroundStyle(.secondary)

                    ForEach(perClassMax, id: \.name) { item in
                        let key = item.name.lowercased()
                        let cover = perClassCoverage[key] ?? 0
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text("Conf: \(Int(item.score*100))% • Cover: \(Int(cover*100))%")
                            }
                            ProgressView(value: Double(item.score))
                                .tint(color(for: item.name))
                        }
                    }
                }
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(brand.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                .padding(.horizontal)
            }
            .padding(.top, 12)
        }
        .navigationTitle("Повреждения")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func rectInImageSpace(_ bb: CGRect, imageSize: CGSize) -> CGRect {
        let x = bb.origin.x * imageSize.width
        let y = (1.0 - bb.origin.y - bb.height) * imageSize.height
        let w = bb.width  * imageSize.width
        let h = bb.height * imageSize.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func color(for label: String) -> Color {
        switch label.lowercased() {
        case "scratch": return .yellow
        case "dent":    return .orange
        case "rust":    return .red
        default:        return .green
        }
    }
}
