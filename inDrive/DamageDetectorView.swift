import SwiftUI
import PhotosUI
import AVFoundation

fileprivate let brand = Color(red: 0.756, green: 0.945, blue: 0.114) // #c1f11d

struct DamageDetectorView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLive = false

    @State private var uiImage: UIImage?
    @State private var detections: [Detection] = []
    @State private var isProcessing = false

    // Метрики (вероятности и площади)
    @State private var cleanliness: CleanProbs?
    @State private var damageAvg: Float = 0                 // среднее из максимумов по классам
    @State private var perClassCover: [String: CGFloat] = [:] // покрытие по классам 0..1
    @State private var totalDamageCover: CGFloat = 0          // общее покрытие 0..1

    // Детекторы
    private let detector = MultiDamageDetector()
    private let cleanCls = CleanlinessClassifier()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Статус над картинкой
                StatusHeader(damageScore: damageAvg)
                    .padding(.horizontal)

                // Фото
                ZStack {
                    if let image = uiImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(image.size, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    } else {
                        PlaceholderCard()
                    }

                    if isProcessing {
                        ProgressView()
                            .scaleEffect(1.1)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)

                // Две карточки-метрики → переходы
                if uiImage != nil {
                    VStack(spacing: 12) {

                        // Cleanliness → CleanDetailView
                        NavigationLink {
                            CleanDetailView(image: uiImage, probs: cleanliness)
                        } label: {
                            MetricBlock(
                                title: "Насколько чиста машина",
                                percent: cleanliness?.pClean ?? 0,
                                caption: cleanliness.map {
                                    "\(Int($0.pDirty*100))% грязный • \(Int($0.pClean*100))% чистый"
                                } ?? "—"
                            )
                        }

                        // Damage → DamageDetailView (передаём также площади)
                        NavigationLink {
                            DamageDetailView(
                                image: uiImage,
                                detections: detections,
                                perClassCoverage: perClassCover,
                                totalCoverage: totalDamageCover
                            )
                        } label: {
                            MetricBlock(
                                title: "Насколько повреждена машина",
                                percent: damageAvg,
                                caption: "Покрытие: \(Int(totalDamageCover*100))%"
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // Кнопки
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Галерея", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())

                    Button {
                        showCamera = true
                    } label: {
                        Label("Камера", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())

                    Button {
                        showLive = true
                    } label: {
                        Label("Реал-тайм", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())
                }
                .padding(.horizontal)
            }
            .padding(.top, 12)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showLive) { LiveContainerView() }
        .onChange(of: pickerItem) { newItem in Task { await handlePickedItem(newItem) } }
        .sheet(isPresented: $showCamera) { CameraPicker { img in Task { await runDetection(on: img) } } }
    }

    // MARK: - Detection

    private func runDetection(on img: UIImage) async {
        uiImage = img
        isProcessing = true
        defer { isProcessing = false }

        async let dets = detector?.detect(in: img) ?? []
        async let cls  = cleanCls?.classify(img)

        let (d, c) = await (dets, cls)
        self.detections = d
        self.cleanliness = c

        // Вероятностная метрика damage (плавная)
        self.damageAvg = computeDamageAverage(from: d)

        // Покрытие площадью: по классам и общее
        self.perClassCover = coverageByClass(from: d)
        self.totalDamageCover = totalDamageCoverage(from: d)
    }

    private func handlePickedItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            await runDetection(on: img)
        }
    }

    // MARK: - Metrics

    /// Damage = среднее из максимумов по (scratch/dent/rust)
    private func computeDamageAverage(from dets: [Detection]) -> Float {
        let groups = ["scratch","dent","rust"]
            .map { cls in dets.filter { $0.label.lowercased() == cls }
                            .map(\.confidence).max() ?? 0 }
        let avg = groups.reduce(0, +) / Float(groups.count)
        return max(0, min(1, avg))
    }

    /// --- Coverage utils (аппроксимация объединения прямоугольников) ---

    private func approxUnionArea(rects: [CGRect], samples: Int = 200) -> CGFloat {
        guard !rects.isEmpty, samples > 0 else { return 0 }
        var covered = 0
        let step = 1.0 / CGFloat(samples)
        for yi in 0..<samples {
            let y = (CGFloat(yi) + 0.5) * step
            for xi in 0..<samples {
                let x = (CGFloat(xi) + 0.5) * step
                let p = CGPoint(x: x, y: y)
                if rects.contains(where: { $0.contains(p) }) {
                    covered += 1
                }
            }
        }
        let total = samples * samples
        return CGFloat(covered) / CGFloat(total) // 0...1
    }

    private func coverageByClass(from dets: [Detection]) -> [String: CGFloat] {
        let classes = ["scratch","dent","rust"]
        var out: [String: CGFloat] = [:]
        for cls in classes {
            let rects = dets.filter { $0.label.lowercased() == cls }.map { $0.boundingBox }
            out[cls] = approxUnionArea(rects: rects, samples: 200)
        }
        return out
    }

    private func totalDamageCoverage(from dets: [Detection]) -> CGFloat {
        let allRects = dets.map { $0.boundingBox }
        return approxUnionArea(rects: allRects, samples: 200)
    }
}

// MARK: - UI Helpers

private struct StatusHeader: View {
    let damageScore: Float
    var damaged: Bool { damageScore >= 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(damaged ? "Повреждения обнаружены" : "Повреждения не обнаружены")
                .font(.headline.bold())
                .foregroundStyle(damaged ? .red : .primary)
            Text(damaged ? "Откройте детали ниже" : "Визуально дефекты не найдены")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaceholderCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "car.side.fill").font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Загрузите фото или сделайте снимок")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(brand.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct MetricBlock: View {
    let title: String
    let percent: Float // 0..1
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(percent * 100))%").font(.system(size: 28, weight: .bold))
                Text(caption).font(.callout).foregroundStyle(.greenInDrive)
            }
            ProgressView(value: Double(percent))
                .tint(brand)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(brand.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.bold())
            .foregroundStyle(Color.black)
            .padding(.vertical, 12)
            .background(.white)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(brand, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.0 : 0.05), radius: 4, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
