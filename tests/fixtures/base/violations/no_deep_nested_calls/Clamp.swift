func clamp(_ delta: Int) -> Int {
    max(min(abs(
        delta
    ), 10), 0)
}
