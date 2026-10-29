import Foundation

enum RegressionLength {
    static let slot = UnavailableVariant(id: "c3", name: "C3 Regression length", reason: "Needs a trained model")

    static func length(features: [Double]) -> Double? {
        guard let weights = ModelWeights.load(), weights.count == features.count + 1 else { return nil }
        var sum = weights[0]
        for index in features.indices { sum += weights[index + 1] * features[index] }
        return sum
    }
}
