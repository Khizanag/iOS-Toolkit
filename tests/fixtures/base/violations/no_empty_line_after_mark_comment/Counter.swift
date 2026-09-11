struct Counter {
    let value: Int
}

// MARK: - Helpers

func double(_ counter: Counter) -> Int {
    counter.value * 2
}
