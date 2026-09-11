import SwiftUI

struct RowView: View {
    let coordinator: AppCoordinator

    var body: some View {
        Text("Open")
            .onTapGesture {
                coordinator.push(.detail)
            }
    }
}
