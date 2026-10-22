//
// StridEngine.swift
// StridKit
//
// The orchestrator of the detection pipeline and the main public entry point of StridKit.
//
// `detect(in:)` runs these stages in order:
//
//   1. Run every recognizer over the text and concatenate their candidates.
//   2. `EntityFilters.apply`     drop systematic false positives (labels, headers, short tokens).
//   3. Threshold + allow-list    keep only entities scoring >= `threshold` and of allowed types.
//   4. `deduplicateOverlaps`     resolve overlapping spans to a single winner per region.
//   5. `extendAcrossWraps`       grow structured identifiers that PDF extraction split across lines.
//
// `redact(_:style:)` is a convenience that chains `detect` with `Redactor.redact`.
//
import Foundation

/// Main PII detection and redaction engine.
///
/// Immutable after construction and `Sendable`, so one instance can be created at app launch
/// and shared freely. Construction compiles every regex in `IndianBankingRecognizers`, so avoid
/// creating engines in a tight loop.
public final class StridEngine: Sendable {
    /// Ordered list of detectors. Order does not affect results: all output is merged and
    /// resolved by score and specificity, never by which recognizer ran first.
    private let recognizers: [Recognizer]
    /// Minimum `PIIEntity.score` for an entity to survive stage 3.
    private let threshold: Double
    /// Optional allow-list of entity types; `nil` means every type is reported.
    private let allowedTypes: Set<PIIEntityType>?

    /// - Parameters:
    ///   - threshold: Minimum confidence score for an entity to be reported.
    ///   - entities: If provided, only these entity types are reported. `nil` means all types.
    public init(threshold: Double = 0.5, entities: Set<PIIEntityType>? = nil) {
        self.recognizers = [
            NLPRecognizer(),           // Apple NLTagger: person / place / organisation
            DataDetectorRecognizer(),  // NSDataDetector: email / phone / URL / address
        ] + IndianBankingRecognizers.all()  // regex + narration + gazetteer recognizers
        self.threshold = threshold
        self.allowedTypes = entities
    }

    /// Detect all PII entities in the given text.
    ///
    /// - Parameter text: Text to scan. Returned ranges index into this string.
    /// - Returns: Non-overlapping entities sorted by position, each at or above the threshold.
    public func detect(in text: String) -> [PIIEntity] {
        detect(in: text, policy: .default)
    }

    /// Detect PII in `text` under `policy`.
    ///
    /// The policy's always-redact terms are added after the false-positive
    /// filters (so a bank name the user wants gone is not rescued by the
    /// public-organisation list) at score 1, which makes them win every
    /// overlap. Disabled types, kept literals and unticked values are dropped
    /// before overlap resolution, so a suppressed finding never shadows a
    /// smaller one it contained.
    public func detect(in text: String, policy: RedactionPolicy) -> [PIIEntity] {
        var allEntities: [PIIEntity] = []

        // Stage 1: gather every candidate from every recognizer.
        for recognizer in recognizers {
            let found = recognizer.recognize(in: text)
            allEntities.append(contentsOf: found)
        }

        // Stages 2 + 3: filter by threshold, deduplicate overlapping ranges (keep highest score)
        var filtered = EntityFilters.apply(allEntities).filter { entity in
            entity.score >= threshold && (allowedTypes?.contains(entity.type) ?? true)
        }
        if !policy.isDefault {
            filtered.append(contentsOf: policy.termEntities(in: text))
            filtered = policy.filter(filtered, in: text)
        }
        // Stages 4 + 5, then field-label relabelling. A label never moves a finding into a type the
        // policy disabled ("Ref 5254123456" found as an account number stays one when references
        // are switched off), so the finding is still redacted under its original type.
        return relabelByFieldLabel(extendAcrossWraps(deduplicateOverlaps(splitContainers(dropAuthorityPlaces(filtered, in: text), in: text)), in: text), in: text, enabled: policy.enabledTypes)
    }

    // MARK: - Field labels

    /// Numbers are ambiguous on their own: a 10-digit value after "Phone no. :" is a phone number
    /// even when "Cust ID" sits on the next line and a 9-digit value after "MICR :" is a MICR code
    /// even though it also looks like an account number. Context windows cannot settle this
    /// because several labels fall inside one window. The label printed on the same line, directly
    /// before the value, is authoritative, so each numeric or code-like entity preceded by a known
    /// label is reported under that label's type. Redaction is unaffected; only the type changes.
    private static let fieldLabels: [(NSRegularExpression, PIIEntityType)] = [
        // Identity-document labels come first: "PF A/c No" must win over the generic "A/c No".
        (#"passport(?:\s*(?:no|number))?\.?"#, .inPassport),
        (#"(?:epic(?:\s*(?:no|number))?|voter\s*id(?:\s*(?:no|number))?|elector'?s?\s*(?:photo\s*)?identity\s*card\s*(?:no|number)?)\.?"#, .inVoterID),
        (#"(?:dl(?:\s*(?:no|number))?|driving\s*licen[cs]e(?:\s*(?:no|number))?|licen[cs]e(?:\s*(?:no|number)))\.?"#, .inDrivingLicence),
        (#"(?:regn\.?(?:\s*(?:no|number))?|(?<!gst\s)(?<!gstin\s)(?:vehicle\s*)?registration\s*(?:no|number|mark)|vehicle\s*(?:no|number|regn)|reg\.?\s*(?:no|number))\.?"#, .inVehicleReg),
        (#"(?:uan(?:\s*(?:no|number))?|universal\s*account\s*(?:no|number)|pf\s*(?:a/c|account|member)?\s*(?:no|number|id)|epf\s*(?:no|number))\.?"#, .inUAN),
        (#"tan(?:\s*(?:no|number))?\.?"#, .inTAN),
        (#"(?:cin|corporate\s*identi(?:ty|fication)\s*(?:no|number))\.?"#, .inCIN),
        (#"(?:phone|mobile|mob|tel|telephone|contact)(?:\s*(?:no|number|#))?\.?"#, .phone),
        (#"(?:cust(?:omer)?\s*(?:id|no|number)|cif(?:\s*(?:id|no))?|client\s*id)\.?"#, .inCustomerID),
        (#"micr(?:\s*(?:code|no))?\.?"#, .inMICR),
        (#"(?:rtgs/neft\s+)?ifsc(?:\s*code)?\.?"#, .inIFSC),
        (#"(?:a/c|account|acct)\s*(?:no|number|#)\.?"#, .inBankAccount),
        (#"pan(?:\s*(?:no|number))?\.?"#, .inPAN),
        (#"(?:aadhaar|aadhar|uid|uidai)(?:\s*(?:no|number))?\.?"#, .inAadhaar),
        (#"gstin|gst\s*(?:no|number|registration\s*no)\.?"#, .inGSTIN),
        (#"(?:pin|pincode|pin\s*code|postal\s*code)\.?"#, .inPINCode),
        (#"(?:dob|date\s+of\s+birth|birth\s+date)\.?"#, .inDOB),
        (#"(?:branch\s*code|br\.?\s*code)\.?"#, .inBranchCode),
        (#"(?:ref(?:erence)?(?:\s*(?:no|number|id))?|utr(?:\s*no)?|rrn|txn\s*(?:id|no|ref)|transaction\s*(?:id|no|ref(?:erence)?)|chq\.?/ref\.?\s*no\.?|cheque\s*(?:no|number))\.?"#, .inTxnRef),
    ].compactMap { pattern, type in
        // Anchored at the end: the label must be the last thing before the separator and the value.
        (try? NSRegularExpression(pattern: #"(?i)(?:^|[\s(|:])"# + pattern + #"\s*[:\-–]?\s*$"#)).map { ($0, type) }
    }

    /// Types whose values are plain numbers or codes and may be re-typed by a field label.
    private static let relabelable: Set<PIIEntityType> = [
        .phone, .inPhone, .inCustomerID, .inMICR, .inBankAccount, .inTxnRef, .inPINCode, .inBranchCode,
        .inAadhaar, .inPAN, .inIFSC, .inGSTIN, .creditCard, .orderID, .location,
        .inPassport, .inVoterID, .inDrivingLicence, .inVehicleReg, .inUAN, .inTAN, .inCIN,
    ]

    private func relabelByFieldLabel(_ entities: [PIIEntity], in text: String, enabled: Set<PIIEntityType>?) -> [PIIEntity] {
        entities.map { e in
            guard Self.relabelable.contains(e.type) else { return e }
            // Text from the start of the entity's line up to the entity, at most 40 characters.
            var lineStart = e.range.lowerBound
            var steps = 0
            while lineStart > text.startIndex, steps < 40 {
                let p = text.index(before: lineStart)
                if text[p] == "\n" { break }
                lineStart = p
                steps += 1
            }
            let prefix = String(text[lineStart..<e.range.lowerBound])
            guard !prefix.isEmpty else { return e }
            let ns = prefix as NSString
            // The first label that matches decides; when it is the entity's own type ("PF A/c No"
            // before a PF number) the later, more generic labels ("A/c No") must not override it.
            for (regex, type) in Self.fieldLabels where enabled?.contains(type) ?? true {
                if regex.firstMatch(in: prefix, range: NSRange(location: 0, length: ns.length)) != nil {
                    return type == e.type ? e : PIIEntity(type: type, text: e.text, range: e.range, score: e.score)
                }
            }
            return e
        }
    }

    // MARK: - Authorities

    private static let authorityPrefix = try! NSRegularExpression(pattern:
        #"(?i)(?:government|govt\.?|state|republic|bank|university|high court|rto|commission|commissioner|ministry|department|council|municipal corporation)\s+of\s*$"#)

    /// "GOVERNMENT OF KARNATAKA", "REPUBLIC OF INDIA", "BANK OF BARODA": the place names the
    /// issuing authority, not where the holder lives. Such locations are dropped whatever
    /// recognizer produced them.
    private func dropAuthorityPlaces(_ entities: [PIIEntity], in text: String) -> [PIIEntity] {
        entities.filter { e in
            guard e.type == .location else { return true }
            let start = text.index(e.range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            let before = String(text[start..<e.range.lowerBound])
            return Self.authorityPrefix.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) == nil
        }
    }

    // MARK: - Container splitting

    /// An ADDRESS span usually contains smaller, higher-scoring findings: the addressee, a PIN
    /// code, a place name. Overlap resolution keeps a single winner per region, so without this
    /// step the small entity would win and the rest of the address would stay readable.
    /// Instead, every address is cut around the entities it overlaps; the remaining fragments
    /// (trimmed of whitespace, newlines and separators) go forward as addresses in their own right.
    private func splitContainers(_ entities: [PIIEntity], in text: String) -> [PIIEntity] {
        let addresses = entities.filter { $0.type == .address }
        // Place and organisation names inside an address ("Varthur Road", "Prestige Lakeside
        // Habitat") are part of the address, not separate findings: they are swallowed so the
        // address stays in one piece. Everything else (the addressee, a PIN code, a phone) cuts it.
        let others = entities.filter { e in
            guard e.type != .address else { return false }
            guard let host = addresses.first(where: { $0.range.lowerBound <= e.range.lowerBound && e.range.upperBound <= $0.range.upperBound }) else { return true }
            if e.type == .location || e.type == .organization { return false }
            // A building or street line ("NAVEEN TERRACES APARTMENTS") is often tagged as a person
            // by the name tagger. It stays part of the address; a real addressee line
            // ("MR. ROHAN VENKATESH") carries no such word and still cuts the block.
            if e.type == .person, Self.isPremisesLine(Self.line(containing: e.range, in: text, within: host.range)) { return false }
            return true
        }
        var out = others
        let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–"))
        for address in addresses {
            let cuts = others.filter { $0.range.overlaps(address.range) }.sorted { $0.range.lowerBound < $1.range.lowerBound }
            var cursor = address.range.lowerBound
            var pieces: [Range<String.Index>] = []
            for c in cuts {
                if c.range.lowerBound > cursor { pieces.append(cursor..<c.range.lowerBound) }
                cursor = max(cursor, c.range.upperBound)
            }
            if cursor < address.range.upperBound { pieces.append(cursor..<address.range.upperBound) }
            for piece in pieces {
                var lo = piece.lowerBound, hi = piece.upperBound
                while lo < hi, text[lo].unicodeScalars.allSatisfy(trim.contains) { lo = text.index(after: lo) }
                while hi > lo, text[text.index(before: hi)].unicodeScalars.allSatisfy(trim.contains) { hi = text.index(before: hi) }
                // A fragment must still say something: "A3" is a flat number, but a bare "IN" or
                // "C/O" left over after the PIN and the name were cut out is not an address.
                let fragment = text[lo..<hi]
                let alnum = fragment.filter { $0.isLetter || $0.isNumber }
                guard alnum.count >= 3 || (alnum.count == 2 && alnum.contains { $0.isNumber }) else { continue }
                out.append(PIIEntity(type: .address, text: String(text[lo..<hi]), range: lo..<hi, score: address.score))
            }
        }
        return out
    }

    private static let premisesWords = try! NSRegularExpression(pattern:
        #"(?i)\b(?:apartments?|apts?|flats?|terraces?|towers?|residency|enclave|nagar|layout|colony|road|rd|street|st|lane|marg|block|phase|sector|villas?|heights|gardens?|complex|society|chs|building|bldg|floor|cross|main|extension|extn|stage|estate|plaza|house|niwas|bhavan|sadan|nilaya|county|park|avenue)\b"#)

    /// Whether a line names premises rather than a person.
    private static func isPremisesLine(_ s: Substring) -> Bool {
        let str = String(s)
        return premisesWords.firstMatch(in: str, range: NSRange(location: 0, length: (str as NSString).length)) != nil
    }

    /// The line of `text` containing `range`, clipped to `bounds`.
    private static func line(containing range: Range<String.Index>, in text: String, within bounds: Range<String.Index>) -> Substring {
        var lo = range.lowerBound, hi = range.upperBound
        while lo > bounds.lowerBound, !text[text.index(before: lo)].isNewline { lo = text.index(before: lo) }
        while hi < bounds.upperBound, !text[hi].isNewline { hi = text.index(after: hi) }
        return text[lo..<hi]
    }

    // MARK: - Line-wrap extension

    /// PDF tables wrap long identifiers mid-token across visual lines, so an entity can end exactly at a
    /// line break with its tail on the next line (or start at a line beginning with its head above).
    /// Extend such entities over the adjoining alphanumeric run, as long as that run is not a date,
    /// an amount, or the start of a new row.
    ///
    /// Example (narration column of a statement, text layer extracted by PDFKit):
    ///
    ///     UPI-PRIYA MEHTA-priya.mehta@oksbi-UTIB0001234-5254123
    ///     45678-PAYMENT
    ///
    /// The txn-ref regex matches `5254123` (ends at `\n`); the next line starts with `45678`, a
    /// pure-digit run followed by `-`, so the entity grows to cover `5254123\n45678`. Redacting the
    /// grown range then blacks out both fragments instead of leaving `45678` legible.
    ///
    /// Only "structured" identifier types are extended; names and locations are never grown.
    private func extendAcrossWraps(_ entities: [PIIEntity], in text: String) -> [PIIEntity] {
        let structured: Set<PIIEntityType> = [.inTxnRef, .inUPIID, .inIFSC, .inBankAccount, .inCustomerID, .email, .creditCard, .inAadhaar]
        return entities.map { e in
            guard structured.contains(e.type) else { return e }
            var lower = e.range.lowerBound, upper = e.range.upperBound

            // Tail on the next line.
            // Entity ends immediately before "\n": look at the run that starts the following line.
            // A complete Aadhaar number or VID (12 / 16 digits) never wraps; the digits on the next
            // line are a different field (the helpline "1947" under the VID on the card).
            // Likewise a full card number (15-16 digits): the digit on the line above is a serial
            // or a column value, not a wrapped head.
            let digits = e.text.filter(\.isNumber).count
            let complete = (e.type == .inAadhaar && digits >= 12) || (e.type == .creditCard && digits >= 15)
            if !complete, upper < text.endIndex, text[upper] == "\n" {
                let next = text.index(after: upper)
                if let run = Self.leadingRun(in: text, from: next), Self.plausibleWrapFragment(text[run]) {
                    upper = run.upperBound
                }
            }
            // Head on the previous line.
            // Entity starts immediately after "\n": look at the run that ends the preceding line.
            // The head is capped at 8 characters because a long trailing run on the previous line
            // is far more likely to be a complete separate value (an amount, another reference).
            if !complete, lower > text.startIndex, text[text.index(before: lower)] == "\n" {
                let lineEnd = text.index(before: lower)
                // An email or UPI handle never starts with a wrapped run of bare digits; on OCR'd
                // pages the line above is far more likely a helpline number ("1947").
                let digitsOnlyHeadAllowed = !(e.type == .email || e.type == .inUPIID)
                if let run = Self.trailingRun(in: text, upTo: lineEnd), Self.plausibleWrapFragment(text[run]),
                   text.distance(from: run.lowerBound, to: run.upperBound) <= 8,
                   digitsOnlyHeadAllowed || !text[run].allSatisfy(\.isNumber) {
                    lower = run.lowerBound
                }
            }
            // Nothing changed: return the original instance (keeps its id and avoids a copy).
            guard lower != e.range.lowerBound || upper != e.range.upperBound else { return e }
            let r = lower..<upper
            // The new `text` includes the embedded "\n"; that is intentional so the redacted
            // output replaces the whole span, newline included.
            return PIIEntity(type: e.type, text: String(text[r]), range: r, score: e.score)
        }
    }

    /// Characters that can be part of a wrapped identifier fragment: letters, digits, and the
    /// `@` / `.` found inside UPI IDs and email addresses.
    private static let runChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@."))

    /// Longest run of `runChars` starting exactly at `start`.
    ///
    /// Only single-scalar characters are accepted (`unicodeScalars.count == 1`), which keeps
    /// combining marks and emoji out of the run and makes the `CharacterSet` test meaningful.
    ///
    /// - Returns: The run's range, or `nil` if there is no run or it is terminated by a character
    ///   that indicates the run is really part of a different value.
    private static func leadingRun(in text: String, from start: String.Index) -> Range<String.Index>? {
        var i = start
        while i < text.endIndex, let u = text[i].unicodeScalars.first, text[i].unicodeScalars.count == 1, runChars.contains(u) {
            i = text.index(after: i)
        }
        guard i > start else { return nil }
        // Must be followed by whitespace/EOL or a narration separator, never ',' (amount) or '/' (date).
        // e.g. "45678-PAYMENT" is a continuation; "45,678.00" is an amount; "12/03/2024" is a date.
        if i < text.endIndex, !(text[i].isWhitespace || text[i] == "-") { return nil }
        return start..<i
    }

    /// Longest run of `runChars` ending exactly at `end` (exclusive), scanning backwards.
    ///
    /// Mirror image of `leadingRun`: the run must be *preceded* by whitespace, line start, or a
    /// `-` separator so that we never bite the tail off an unrelated adjacent value.
    private static func trailingRun(in text: String, upTo end: String.Index) -> Range<String.Index>? {
        var i = end
        while i > text.startIndex {
            let p = text.index(before: i)
            guard let u = text[p].unicodeScalars.first, text[p].unicodeScalars.count == 1, runChars.contains(u) else { break }
            i = p
        }
        guard i < end else { return nil }
        if i > text.startIndex, !(text[text.index(before: i)].isWhitespace || text[text.index(before: i)] == "-") { return nil }
        return i..<end
    }

    /// Short alnum fragment, not a date, not a word.
    ///
    /// Accepts, in order of the `return` expression:
    ///   - any all-digit run (`45678`, `000123456789`): the common wrapped-number case,
    ///   - a short mixed run with at least one digit (`N2452`, `7A3B`): wrapped alnum refs,
    ///   - up to four upper-case letters/digits (`UTIB`, `HDFC`): the head of a wrapped IFSC or
    ///     bank-prefixed reference.
    /// Rejects anything over 16 characters, anything containing `/` (dates), and plain words.
    private static func plausibleWrapFragment(_ s: Substring) -> Bool {
        guard !s.isEmpty, s.count <= 16, !s.contains("/") else { return false }
        // "70.00" at the end of the previous line is an amount in the next column, not a wrapped head.
        if s.contains("."), s.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        let digits = s.filter(\.isNumber).count
        // Pure digits of any length, or short mixed fragments; never a plain word, and never a
        // bare label such as "MICR" or "UPI" that happens to start the next line.
        return digits == s.count || (digits > 0 && s.count <= 8)
    }

    // MARK: - Redaction

    /// Redact PII from text using the given style.
    ///
    /// Convenience for `Redactor.redact(text, entities: detect(in: text), style: style)`.
    ///
    /// - Parameters:
    ///   - text: Text to redact.
    ///   - style: Replacement rendering; defaults to `<TYPE>` placeholders.
    /// - Returns: The redacted text.
    public func redact(_ text: String, style: RedactionStyle = .placeholder, policy: RedactionPolicy = .default) -> String {
        let entities = detect(in: text, policy: policy)
        return Redactor.redact(text, entities: entities, style: style)
    }

    // MARK: - Overlap resolution

    /// Generic model-derived types lose ties against structured identifiers.
    ///
    /// Used only when two overlapping entities have *exactly* the same score. Higher wins:
    ///   - 0: NSDataDetector / NLTagger catch-alls (phone, location, organisation, URL)
    ///   - 1: person names
    ///   - 2: everything else (PAN, IFSC, Aadhaar, UPI, card, txn ref, ...)
    /// So a `1.0`-scored IFSC beats a `1.0`-scored NLTagger "organisation" over the same text.
    private static func specificity(_ t: PIIEntityType) -> Int {
        switch t {
        case .phone, .location, .organization, .url: 0
        case .person, .address: 1
        default: 2
        }
    }

    /// Deduplicate overlapping entities — when two entities overlap, keep the one with the higher score.
    /// If scores are equal, keep the longer match.
    ///
    /// Algorithm: a single sweep over entities sorted by start position (longest first on ties).
    /// `lastEnd` tracks the right edge of the most recently accepted entity. Any entity starting
    /// before `lastEnd` overlaps the accepted one and either replaces it (higher score, or equal
    /// score and more specific type) or is dropped. Because the sort puts the longest span first
    /// among equal starts, "keep the longer match" falls out naturally: the shorter one arrives
    /// second and loses unless it scores strictly higher.
    ///
    /// Note that replacement compares against `result.last` only; a chain A-B-C where B replaces
    /// A and C overlaps only A is handled correctly because `lastEnd` is reset to B's end.
    ///
    /// - Parameter entities: Filtered entities, any order.
    /// - Returns: Non-overlapping entities in ascending position order.
    private func deduplicateOverlaps(_ entities: [PIIEntity]) -> [PIIEntity] {
        guard !entities.isEmpty else { return [] }

        // Sort by start position, then by length descending
        let sorted = entities.sorted { a, b in
            if a.range.lowerBound == b.range.lowerBound {
                return a.text.count > b.text.count
            }
            return a.range.lowerBound < b.range.lowerBound
        }

        var result: [PIIEntity] = []
        var lastEnd: String.Index?

        for entity in sorted {
            if let end = lastEnd, entity.range.lowerBound < end {
                // Overlapping — replace if this one has a higher score
                // (or the same score with a more specific type, see `specificity`).
                if let last = result.last, entity.score > last.score
                    || (entity.score == last.score && Self.specificity(entity.type) > Self.specificity(last.type)) {
                    result.removeLast()
                    result.append(entity)
                    lastEnd = entity.range.upperBound
                }
                // Otherwise skip
            } else {
                // No overlap with the last accepted entity: accept and advance the sweep edge.
                result.append(entity)
                lastEnd = entity.range.upperBound
            }
        }

        return result
    }
}
