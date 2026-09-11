import Observation

@MainActor
@Observable
final class ItemService {
    private(set) var items: [String] = []

    func add(_ item: String) {
        guard !item.isEmpty else {
            return
        }
        items.append(item)
    }
}
