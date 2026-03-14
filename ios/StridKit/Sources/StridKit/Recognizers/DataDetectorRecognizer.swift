import Foundation

/// Uses NSDataDetector to find emails, phone numbers, URLs, and addresses.
public struct DataDetectorRecognizer: Recognizer {
    public init() {}

    public func recognize(in text: String) -> [PIIEntity] {
        var entities: [PIIEntity] = []
        let nsText = text as NSString

        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }

        let results = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for result in results {
            guard let swiftRange = Range(result.range, in: text) else { continue }
            let matched = String(text[swiftRange])

            let entityType: PIIEntityType? = switch result.resultType {
            case .phoneNumber:
                .phone
            case .link:
                if matched.contains("@") && !matched.hasPrefix("http") {
                    .email
                } else {
                    .url
                }
            case .address:
                .location
            default:
                nil
            }

            if let entityType {
                entities.append(PIIEntity(
                    type: entityType,
                    text: matched,
                    range: swiftRange,
                    score: 1.0
                ))
            }
        }

        return entities
    }
}
