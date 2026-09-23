public extension ASCIIGrid {
    /// Renders this grid as a newline-separated plain-text string.
    func renderPlainText() -> String {
        if cells.isEmpty { return "" }

        var result = ""
        result.reserveCapacity(rows * (columns + 1))
        let fallbackCharacter = maskFallback?.textReplacementCharacter
        for (index, row) in cells.enumerated() {
            for cell in row {
                if cell.coverage >= 0.5 {
                    result.append(cell.character)
                } else {
                    result.append(fallbackCharacter ?? " ")
                }
            }
            if index < cells.count - 1 {
                result.append("\n")
            }
        }
        return result
    }
}
