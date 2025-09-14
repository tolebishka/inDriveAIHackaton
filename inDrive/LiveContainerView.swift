import SwiftUI

struct LiveContainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RealTimeDetectorView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Закрыть", systemImage: "xmark.circle.fill")
                        }
                    }
                }
        }
        .ignoresSafeArea(edges: .bottom) 
    }
}
