struct Item {
    let name: String
}

extension Item {
    var hasName: Bool {
        !name.isEmpty
    }
}
