import Foundation

/// Uses NSDataDetector to find emails, phone numbers, URLs, and addresses.
public struct DataDetectorRecognizer: Recognizer {
    public init() {}

    /// NSDataDetector happily calls any 9-16 digit run a phone number. Keep only shapes that are phones in India:
    /// 10 digits, 11 with a leading 0 trunk prefix, or 12 with a +91 country code.
    static func plausiblePhone(_ s: String) -> Bool {
        let digits = s.filter(\.isNumber)
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        switch digits.count {
        case 10: return true
        case 11: return digits.hasPrefix("0")
        case 12: return trimmed.hasPrefix("+91") || digits.hasPrefix("91")
        case 13: return trimmed.hasPrefix("+91") && digits.hasPrefix("910")
        default: return false
        }
    }

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

            if entityType == .phone, !Self.plausiblePhone(matched) { continue }
            if let entityType {
                entities.append(PIIEntity(
                    type: entityType,
                    text: matched,
                    range: swiftRange,
                    // Phones get a lower score so Luhn-validated cards, MICR and labelled account
                    // numbers win the overlap; emails/URLs/addresses stay authoritative.
                    score: entityType == .phone ? 0.75 : 1.0
                ))
            }
        }

        return entities
    }
}
