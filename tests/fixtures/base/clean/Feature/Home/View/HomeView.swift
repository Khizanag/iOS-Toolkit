import SwiftUI

struct HomeView: View {
    @State private var count = 0

    let title: String

    var body: some View {
        VStack {
            header
            Button("Increment") {
                count += 1
            }
        }
    }
}

// MARK: - Sub-views
private extension HomeView {
    var header: some View {
        Text(title)
            .font(.headline)
    }
}
