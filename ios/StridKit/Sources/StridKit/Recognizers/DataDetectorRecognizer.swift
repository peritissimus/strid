//
// DataDetectorRecognizer.swift
// StridKit
//
// Wraps Foundation's `NSDataDetector` to pick up the "universal" contact-style PII that regexes
// handle poorly: email addresses, URLs, phone numbers in arbitrary international formatting, and
// multi-line postal addresses. The detector is very eager with phone numbers, so its results are
// post-filtered to Indian shapes and scored below structured identifiers.
//
import Foundation

/// Uses NSDataDetector to find emails, phone numbers, URLs, and addresses.
public struct DataDetectorRecognizer: Recognizer {
    public init() {}

    /// NSDataDetector happily calls any 9-16 digit run a phone number. Keep only shapes that are phones in India:
    /// 10 digits, 11 with a leading 0 trunk prefix, or 12 with a +91 country code.
    ///
    /// Digit-count cases:
    ///   - 10: `98765 43210`
    ///   - 11: `098765 43210` (STD trunk prefix)
    ///   - 12: `+91 98765 43210` or `91 98765 43210`
    ///   - 13: `+91 098765 43210` (country code *and* trunk zero, occasionally printed this way)
    /// Everything else (account numbers, references, MICR codes) is rejected here and left to the
    /// banking recognizers.
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

    /// Runs one detector pass for phone numbers, links and addresses and maps each result to an
    /// entity type.
    ///
    /// - Parameter text: Text to scan.
    /// - Returns: Email, URL, phone and location entities. Returns `[]` if the detector cannot be
    ///   constructed (never expected in practice).
    public func recognize(in text: String) -> [PIIEntity] {
        var entities: [PIIEntity] = []
        let nsText = text as NSString

        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }

        let results = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for result in results {
            // NSRange is UTF-16 based; convert to a String.Index range (skips results that would
            // split a grapheme cluster, which cannot happen for these detector types anyway).
            guard let swiftRange = Range(result.range, in: text) else { continue }
            let matched = String(text[swiftRange])

            let entityType: PIIEntityType? = switch result.resultType {
            case .phoneNumber:
                .phone
            case .link:
                // NSDataDetector reports mailto links as `.link`; distinguish them from web URLs by
                // the presence of "@" without an explicit scheme.
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

            // Apply the Indian phone-shape filter; other types are taken as-is.
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
