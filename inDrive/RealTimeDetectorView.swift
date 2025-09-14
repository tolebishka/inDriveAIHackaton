import SwiftUI
import AVFoundation
import Vision

// MARK: - Реальный тайм детектор (SwiftUI экран)
struct RealTimeDetectorView: View {
    @StateObject private var camera = CameraPipeline()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Превью с камеры
            CameraPreview(session: camera.session)
                .onAppear { camera.start() }
                .onDisappear { camera.stop() }
                .overlay {
                    // Оверлей рамок поверх видимой области превью
                    GeometryReader { geo in
                        let container = geo.size
                        ZStack(alignment: .topLeading) {
                            ForEach(camera.detections) { det in
                                let r = rectOnScreen(
                                    for: det.boundingBox,
                                    imageSize: camera.frameSize,   // исходное разрешение кадра (px)
                                    container: container           // размер вью превью (pt)
                                )
                                BorderedBox(rect: r,
                                            label: "\(det.label) \(Int(det.confidence * 100))%",
                                            color: color(for: det.label))
                            }
                        }
                    }
                }

            // Небольшая плашка-статус
            StatusPill(detections: camera.detections)
                .padding(10)

            // Индикатор занятости
            if camera.isRunningInference == true {
                ProgressView().padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Live Detect")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Вспомогательные штуки, совместимые с твоими текущими компонентами

/// цвет по имени класса
private func color(for label: String) -> Color {
    switch label.lowercased() {
    case "scratch": return .yellow
    case "dent":    return .orange
    case "rust":    return .red
    default:        return .green
    }
}

/// Пересчёт нормализованного bbox (Vision, origin снизу) в координаты слоя превью,
/// учитывая, что превью вписано в контейнер без искажений (videoGravity = .resizeAspect).
private func rectOnScreen(for normBB: CGRect, imageSize: CGSize, container: CGSize) -> CGRect {
    let fitted = AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: .zero, size: container))
    let x = fitted.minX + normBB.origin.x * fitted.width
    let y = fitted.minY + (1.0 - normBB.origin.y - normBB.height) * fitted.height
    let w = normBB.width * fitted.width
    let h = normBB.height * fitted.height
    return CGRect(x: x, y: y, width: w, height: h)
}

/// Та же красивая плашка-статус, что и на фото-экране
private struct StatusPill: View {
    let detections: [Detection]
    private var isDamaged: Bool { !detections.isEmpty }
    private var severityTitle: String {
        let s = detections.map { Double($0.confidence) * Double($0.areaFraction) }.max() ?? 0
        switch s {
        case 0:                 return "Нет повреждений"
        case 0..<0.005:         return "Незначительные"
        case 0.005..<0.015:     return "Средние"
        default:                return "Существенные"
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDamaged ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundStyle(.white)
                .padding(8)
                .background(isDamaged ? Color.red : Color.green, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(isDamaged ? "Повреждения обнаружены" : "Повреждения не обнаружены")
                    .font(.subheadline.bold())
                Text(severityTitle)
                    .font(.caption)
                    .foregroundStyle(isDamaged ? .red : .secondary)
            }
            Spacer()
            if isDamaged {
                Text("\(detections.count)")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Рамка с подписью
private struct BorderedBox: View {
    let rect: CGRect
    let label: String
    let color: Color
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().stroke(color, lineWidth: 2)
            Text(label)
                .font(.caption2.bold())
                .padding(4)
                .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.black)
                .padding(4)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}
