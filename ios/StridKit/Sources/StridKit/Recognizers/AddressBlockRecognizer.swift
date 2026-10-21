//
// AddressBlockRecognizer.swift
// StridKit
//
// Structural address detection for invoices, delivery notes, KYC letters, statements and ID cards.
//
// NLTagger finds place *names* ("Whitefield", "KARNATAKA") but not the address itself: the flat
// number, building and road stay readable, and on iOS the tagger misses even the names. This
// recognizer keys off document structure instead, in three passes:
//
//  1. Labelled blocks:
//
//         Billing Address :            <- label line (may also end a multi-column line)
//         Kavya Raghunathan            <- name-like first line  -> PERSON
//         Flat 7B, Prestige Lakeside Habitat, Varthur Road
//         Gunjur, Whitefield           <- ADDRESS (one span over these lines)
//         BENGALURU, KARNATAKA, 560087 <- PIN line ends the block
//         IN
//         State/UT Code: 29            <- terminator (never reached here)
//
//  2. Name-anchored blocks (statement headers, letters): an honorific line "MR. RAHUL SHARMA"
//     followed within a few lines by a PIN line; the lines between become the ADDRESS.
//
//  3. PIN-anchored blocks (ID cards, unlabelled footers): a line carrying a PIN code plus some
//     words ("Madhya Pradesh - 460553", "BENGALURU 560034") closes a block; the recognizer walks
//     back over at most `maxBackLines` address-like lines (commas, Devanagari, short alphanumeric
//     lines) and stops at labels, blank lines, headers and names.
//
// Rules are deliberately conservative: blocks are capped at `maxLines`, close at the first PIN
// line, blank line or field label, and the unlabelled passes require a PIN line as evidence.
// Over-redacting a header line is acceptable; leaving a street readable is not.
//
import Foundation

public struct AddressBlockRecognizer: Recognizer {
    public init() {}

    /// Most address lines a block may span (name line excluded).
    static let maxLines = 6
    /// How far a PIN-anchored block may reach back above its PIN line.
    static let maxBackLines = 4

    /// "Billing Address :", "Shipping Address:", "Address of the Applicant :", "Permanent Address -",
    /// "Addr:", and the Hindi "पता:". The label may start the line or end it: multi-column PDFs
    /// flatten to lines such as "Order Number: 171-... Order Date: 12.10.2025 Shipping Address :",
    /// with the block beneath. Group 1 is whatever follows the label on the same line (often empty).
    static let label = try! NSRegularExpression(
        pattern: #"(?im)(?:^|[ \t])(?:(?:(?:billing|shipping|delivery|permanent|present|current|correspondence|communication|residential|registered|home|office|customer|consignee|buyer|bill[ -]?to|ship[ -]?to)[ \t]+)?addr(?:ess)?(?:[ \t]+(?:of[ \t]+(?:the[ \t]+)?\w+|details))?|पता)[ \t]*[:\-–][ \t]*(.*)$"#
    )

    /// Lines beginning with these are another field, so the address has ended.
    static let terminator = try! NSRegularExpression(
        pattern: #"(?i)^[ \t]*(?:state(?:/ut)?[ \t]*code|place[ \t]+of|gst|gstin|pan(?:[ \t]*no)?|phone|mobile|tel|email|e-mail|order|invoice|date|dob|sold[ \t]+by|shipping|billing|customer|account|a/c|ifsc|branch|micr|nominee|nomination|joint[ \t]+holders?|aadhaar|statement|total|amount|description|sl\.?|item|qty|hsn|payment|mode[ \t]+of|whether|for[ \t]+\w|page|in|india|vid|cust[ \t]*id|currency|limit|from|to)\b"#
    )

    /// A line holding a 6-digit Indian PIN (not part of a longer number) closes the block after itself.
    static let pinLine = try! NSRegularExpression(pattern: #"(?<!\d)[1-9]\d{5}(?!\d)"#)

    /// Two to four capitalised words, optional honorific, no digits: a person, not a street.
    static let nameLike = try! NSRegularExpression(
        pattern: #"^(?:(?:Mr|Mrs|Ms|Dr|Shri|Smt|Kum|Sri)\.?[ \t]+)?[A-Z][A-Za-z.'\-]+(?:[ \t]+[A-Z][A-Za-z.'\-]+){1,3}\.?$"#
    )

    /// Honorific line that opens a name-anchored block: "MR. RAHUL SHARMA", "Smt. Sunita Devi", "M/S ACME".
    static let honorificLine = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:MR|MRS|MS|DR|SHRI|SMT|KUMARI|KUM|SRI|M/S)\.?[ \t]+\S"#, options: [.caseInsensitive]
    )

    /// "Label : value" lines in Latin script; never part of an address unless the label is an address label.
    static let latinLabel = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z ./()&-]{0,30}:"#)

    /// Amounts and dates: table cells, never address lines.
    static let amountOrDate = try! NSRegularExpression(pattern: #"^[\d,]+\.\d{2}$|\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}"#)

    /// "KARNATAKA INDIA", "Maharashtra, India", "IN": a trailing line made only of state / country
    /// names and separators, printed under the PIN line on statements and cards.
    static func isStateOrCountryLine(_ s: String) -> Bool {
        var rest = s.lowercased()
        for name in Self.regionNames { rest = rest.replacingOccurrences(of: name, with: " ") }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return rest.isEmpty && !s.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// States, union territories and country spellings, longest first so "madhya pradesh" is
    /// removed before "pradesh" could be. Sourced from the place gazetteer plus country forms.
    static let regionNames: [String] = (IndianPlaceRecognizer.places.map { $0.lowercased() } + ["india", "bharat", "in"])
        .sorted { $0.count > $1.count }

    /// Document headers that a PIN-anchored block must not climb into.
    static let headerWords = try! NSRegularExpression(
        pattern: #"(?i)\b(?:authority|government|govt|bank|limited|ltd|statement|invoice|receipt|tax|gst|understand|welcome)\b"#
    )

    /// Last words that mark a line as a place or a company rather than a person.
    static let notNameSuffixes: Set<String> = [
        "road", "rd", "street", "st", "nagar", "layout", "colony", "society", "marg", "lane", "block", "sector",
        "phase", "enclave", "vihar", "puram", "hobli", "taluk", "village", "district", "dist", "apartments",
        "apartment", "apts", "residency", "heights", "towers", "tower", "complex", "plaza", "mall", "floor",
        "house", "building", "bhavan", "chambers", "estate", "park", "garden", "gardens", "cross", "main",
        "limited", "ltd", "pvt", "private", "llp", "inc", "corporation", "corp", "technologies", "solutions",
        "services", "bank", "branch", "india", "international", "industries", "enterprises", "traders", "stores",
        "east", "west", "north", "south", "extension", "extn",
    ]

    /// One line of the scanned text with its range in the source string.
    struct Line {
        let range: NSRange
        let text: String
        /// Text without surrounding whitespace, newlines and control characters (form feeds between PDF pages).
        var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) }
        var nsLength: Int { (trimmed as NSString).length }
    }

    public func recognize(in text: String) -> [PIIEntity] {
        let lines = Self.split(text)
        var out: [PIIEntity] = []
        // Lines already consumed by a block; later passes skip them.
        var taken = [Bool](repeating: false, count: lines.count)

        // Pass 1: labelled blocks.
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard let m = Self.label.firstMatch(in: line.text, range: NSRange(location: 0, length: (line.text as NSString).length)) else { i += 1; continue }
            var block: [Line] = []
            let rest = m.range(at: 1)
            if rest.location != NSNotFound, rest.length > 0 {
                let s = (line.text as NSString).substring(with: rest)
                if !s.trimmingCharacters(in: .whitespaces).isEmpty {
                    block.append(Line(range: NSRange(location: line.range.location + rest.location, length: rest.length), text: s))
                }
            }
            taken[i] = true
            var j = i + 1
            var nameEmitted = false
            var closedByPin = false
            while j < lines.count, block.count < Self.maxLines, !closedByPin {
                let l = lines[j]
                let trimmed = l.trimmed
                if trimmed.isEmpty { break }
                if Self.isTerminator(trimmed) { break }
                // The first line(s) after the label are the addressee when they look like a person
                // (Amazon prints the name twice on shipping blocks).
                if block.isEmpty, Self.isPersonName(trimmed) {
                    if let sr = Range(l.range, in: text) {
                        out.append(PIIEntity(type: .person, text: l.text, range: sr, score: 0.9))
                    }
                    nameEmitted = true
                    taken[j] = true
                    j += 1
                    continue
                }
                _ = nameEmitted
                block.append(l)
                taken[j] = true
                if Self.hasPin(trimmed) { closedByPin = true }
                j += 1
            }
            j = Self.absorbRegionLine(after: j, lines: lines, taken: &taken, block: &block)
            Self.emit(block, in: text, into: &out)
            i = max(j, i + 1)
        }

        // Pass 2: name-anchored blocks ("MR. RAHUL SHARMA" then address lines down to a PIN line).
        i = 0
        while i < lines.count {
            defer { i += 1 }
            guard !taken[i] else { continue }
            let t = lines[i].trimmed
            guard Self.honorificLine.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil else { continue }
            var block: [Line] = []
            var j = i + 1
            var closed = false
            while j < lines.count, block.count < Self.maxLines, !taken[j] {
                let s = lines[j].trimmed
                if s.isEmpty || Self.isTerminator(s) || Self.isPersonName(s) { break }
                block.append(lines[j])
                if Self.hasPin(s) { closed = true; break }
                j += 1
            }
            // Without a PIN line this is just a name followed by prose; leave it alone.
            guard closed else { continue }
            for k in (i + 1)...j { taken[k] = true }
            j = Self.absorbRegionLine(after: j + 1, lines: lines, taken: &taken, block: &block) - 1
            Self.emit(block, in: text, into: &out)
            i = j
        }

        // Pass 3: PIN-anchored blocks walking back over address-like lines.
        for p in lines.indices where !taken[p] {
            let pinText = lines[p].trimmed
            guard Self.hasPin(pinText), Self.isAddressLike(pinText, allowPinOnly: false) else { continue }
            var start = p
            var back = 0
            while start > 0, back < Self.maxBackLines, !taken[start - 1] {
                let s = lines[start - 1].trimmed
                guard Self.isAddressLike(s, allowPinOnly: true), !Self.isPersonName(s),
                      Self.honorificLine.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) == nil
                else { break }
                start -= 1
                back += 1
            }
            // A PIN line on its own ("BENGALURU 560034") is still worth a block only when it names
            // more than the PIN; a bare state + PIN line with nothing above is left to the PIN recognizer.
            guard back > 0 || pinText.contains(",") else { continue }
            for k in start...p { taken[k] = true }
            var block = Array(lines[start...p])
            _ = Self.absorbRegionLine(after: p + 1, lines: lines, taken: &taken, block: &block)
            Self.emit(block, in: text, into: &out)
        }
        return out
    }

    /// If `lines[index]` is a free state/country line, appends it to `block`, marks it taken and
    /// returns the index after it; otherwise returns `index` unchanged.
    static func absorbRegionLine(after index: Int, lines: [Line], taken: inout [Bool], block: inout [Line]) -> Int {
        guard index < lines.count, !taken[index], !block.isEmpty, isStateOrCountryLine(lines[index].trimmed) else { return index }
        block.append(lines[index])
        taken[index] = true
        return index + 1
    }

    // MARK: - Helpers

    /// Splits `text` into lines, keeping each line's range (newline excluded).
    static func split(_ text: String) -> [Line] {
        let ns = text as NSString
        var lines: [Line] = []
        var cursor = 0
        while cursor <= ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            var content = lineRange
            let raw = ns.substring(with: lineRange)
            let trimmedNewline = raw.hasSuffix("\r\n") ? 2 : (raw.hasSuffix("\n") || raw.hasSuffix("\r") ? 1 : 0)
            content.length -= trimmedNewline
            lines.append(Line(range: content, text: ns.substring(with: content)))
            if lineRange.length == 0 { break }
            cursor = NSMaxRange(lineRange)
            if cursor == ns.length { break }
        }
        return lines
    }

    /// Emits one ADDRESS entity spanning `block` (first line start to last line end).
    static func emit(_ block: [Line], in text: String, into out: inout [PIIEntity]) {
        guard let first = block.first, let last = block.last else { return }
        let span = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        guard let sr = Range(span, in: text) else { return }
        out.append(PIIEntity(type: .address, text: String(text[sr]), range: sr, score: 0.9))
    }

    static func isTerminator(_ s: String) -> Bool {
        terminator.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func hasPin(_ s: String) -> Bool {
        pinLine.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Whether a line could be part of an unlabelled address.
    ///
    /// Accepts lines with a comma or Devanagari text, and short alphanumeric lines ("A3",
    /// "NAVEEN TERRACES APARTMENTS", "Madhya Pradesh - 460553"). Rejects blank lines, field
    /// terminators, Latin "Label: value" lines, amounts, dates, document headers and long prose.
    /// - Parameter allowPinOnly: when `false` the line must carry something besides its PIN code.
    static func isAddressLike(_ s: String, allowPinOnly: Bool) -> Bool {
        guard !s.isEmpty, s.count <= 60, !isTerminator(s) else { return false }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard s.rangeOfCharacter(from: .letters) != nil else { return false }
        if amountOrDate.firstMatch(in: s, range: full) != nil { return false }
        if headerWords.firstMatch(in: s, range: full) != nil { return false }
        let hasDevanagari = s.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
        if latinLabel.firstMatch(in: s, range: full) != nil, !hasDevanagari, !s.contains(",") { return false }
        if !allowPinOnly {
            // Strip the PIN and separators; something must remain ("BENGALURU", "Madhya Pradesh").
            let rest = s.replacingOccurrences(of: #"[1-9]\d{5}"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(CharacterSet(charactersIn: "-–")))
            guard rest.rangeOfCharacter(from: .letters) != nil else { return false }
        }
        return true
    }

    /// Person-name test for the first line of a block.
    static func isPersonName(_ s: String) -> Bool {
        guard s.rangeOfCharacter(from: .decimalDigits) == nil, s.count <= 48 else { return false }
        guard nameLike.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil else { return false }
        let last = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() } ?? ""
        return !notNameSuffixes.contains(last)
    }
}
