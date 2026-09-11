import SwiftUI

struct RouteView: View {
    var body: some View {
        Text("Home")
            .navigationDestination(for: Int.self) { value in
                Text(String(value))
            }
    }
}
