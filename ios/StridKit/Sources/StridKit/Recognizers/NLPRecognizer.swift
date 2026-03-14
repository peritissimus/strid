import Foundation
import NaturalLanguage

/// Uses Apple's NaturalLanguage framework for NER (names, locations, organizations).
public struct NLPRecognizer: Recognizer {
    public init() {}

    public func recognize(in text: String) -> [PIIEntity] {
        var entities: [PIIEntity] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag else { return true }

            let entityType: PIIEntityType? = switch tag {
            case .personalName: .person
            case .placeName: .location
            case .organizationName: .organization
            default: nil
            }

            if let entityType {
                entities.append(PIIEntity(
                    type: entityType,
                    text: String(text[range]),
                    range: range,
                    score: 0.85
                ))
            }
            return true
        }

        return entities
    }
}
