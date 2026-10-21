//
// NLPRecognizer.swift
// StridKit
//
// Named-entity recognition via Apple's on-device NaturalLanguage framework. This is the only
// statistical model in the pipeline and the main source of `.person`, `.location` and
// `.organization` entities in free-running prose (letters, KYC forms, emails). It performs poorly
// on the ALL-CAPS, delimiter-separated narrations found in bank statements, which is why
// `NarrationRecognizer` and `IndianPlaceRecognizer` exist alongside it, and why `EntityFilters`
// cleans up its tendency to tag column headers as names.
//
import Foundation
import NaturalLanguage

/// Uses Apple's NaturalLanguage framework for NER (names, locations, organizations).
public struct NLPRecognizer: Recognizer {
    public init() {}

    /// Tags every word with `NLTagScheme.nameType` and emits an entity for each name-type tag.
    ///
    /// Options:
    ///   - `.joinNames` merges consecutive tokens of one name ("Priya" + "Mehta") into a single
    ///     range, so multi-word names come back as one entity.
    ///   - `.omitWhitespace` / `.omitPunctuation` skip tokens that can never be names.
    ///
    /// Every emitted entity carries a fixed score of `0.85`: above the default threshold, but
    /// below validated structured identifiers so those win overlaps.
    ///
    /// - Parameter text: Text to tag. Language is auto-detected by NLTagger.
    /// - Returns: Person, location and organisation entities.
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
            // `nil` tag means "not a name"; keep enumerating.
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
            return true  // continue enumeration
        }

        return entities
    }
}
