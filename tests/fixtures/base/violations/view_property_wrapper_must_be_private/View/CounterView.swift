import SwiftUI

struct CounterView: View {
    @State var count = 0

    var body: some View {
        Text(String(count))
    }
}
