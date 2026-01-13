import Foundation

struct DelayService {
    func randomDelay(min: Int, max: Int) -> Int {
        guard min < max else { return min }
        return Int.random(in: min...max)
    }

    func randomDelayWithVariance(base: Int, variancePercent: Double) -> Int {
        let variance = Double(base) * variancePercent
        let minVal = max(1, base - Int(variance))
        let maxVal = base + Int(variance)
        return Int.random(in: minVal...maxVal)
    }

    func humanizedDelay() -> Int {
        // Returns a delay that mimics human behavior (30-90 seconds with slight randomness)
        let baseDelays = [30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90]
        let base = baseDelays.randomElement() ?? 60
        let jitter = Int.random(in: -5...5)
        return max(20, base + jitter)
    }
}
