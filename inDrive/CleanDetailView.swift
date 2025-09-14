import SwiftUI

fileprivate let brand = Color(red: 0.756, green: 0.945, blue: 0.114) // #c1f11d

struct CleanDetailView: View {
    let image: UIImage?
    let probs: CleanProbs?

    var pClean: Float { probs?.pClean ?? 0 }
    var pDirty: Float { probs?.pDirty ?? 1 - pClean }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Фото
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                        .padding(.horizontal)
                }

                // Проценты чистоты
                VStack(alignment: .leading, spacing: 16) {
                    Text("Чистота кузова")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Грязный")
                            Spacer()
                            Text("\(Int(pDirty * 100))%")
                                .font(.headline)
                        }
                        ProgressView(value: Double(pDirty))
                            .tint(.orange)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Чистый")
                            Spacer()
                            Text("\(Int(pClean * 100))%")
                                .font(.headline)
                        }
                        ProgressView(value: Double(pClean))
                            .tint(.green)
                    }
                }
                .padding()
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
                .padding(.horizontal)
            }
            .padding(.top, 12)
        }
        .navigationTitle("Чистота")
        .navigationBarTitleDisplayMode(.inline)
    }
}
