import Foundation

/// Combines anchor quality, path length, drift and age into one plain-language confidence.
public enum ConfidenceModel {
    public static func estimate(anchorQuality: AnchorQuality?, path: StoredPath, driftEstimate: Double, ageSeconds: Double, truncated: Bool = false) -> Confidence {
        var value = 1.0
        var reasons: [String] = []
        switch anchorQuality {
        case .good: break
        case .fair: value -= 0.15; reasons.append("GPS anchor was only fair")
        case .poor: value -= 0.35; reasons.append("GPS anchor was poor")
        case nil: value -= 0.35; reasons.append("No GPS anchor")
        }
        let length = max(path.walkedLength, path.length)
        if length > 150 { value -= 0.15; reasons.append("Long path, drift adds up") }
        else if length > 60 { value -= 0.05 }
        if driftEstimate > 10 { value -= 0.2; reasons.append("Large estimated drift") }
        else if driftEstimate > 5 { value -= 0.1 }
        if path.truncated || truncated { value -= 0.2; reasons.append("Path was too long to store fully") }
        if ageSeconds > 24 * 3600 { value -= 0.3; reasons.append("More than a day old") }
        else if ageSeconds > 6 * 3600 { value -= 0.1; reasons.append("Several hours old") }
        return Confidence(value: value, reasons: reasons)
    }
}
