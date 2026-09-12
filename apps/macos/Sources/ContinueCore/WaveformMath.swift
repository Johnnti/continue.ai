public enum WaveformMath {
    public static func normalizedLevels(
        _ source: [Double],
        barCount: Int,
        floor: Double = 0.08
    ) -> [Double] {
        guard barCount > 0 else { return [] }

        let safeFloor = min(max(floor, 0), 1)
        guard !source.isEmpty else {
            return Array(repeating: safeFloor, count: barCount)
        }

        return (0..<barCount).map { index in
            let sourceIndex = min(
                source.count - 1,
                Int(Double(index) / Double(barCount) * Double(source.count))
            )
            return min(max(source[sourceIndex], safeFloor), 1)
        }
    }
}
