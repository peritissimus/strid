//
// AddressBlockRecognizer.swift
// StridKit
//
// Structural address detection for invoices, delivery notes, KYC letters and statements.
//
// NLTagger finds place *names* ("Whitefield", "KARNATAKA") but not the address itself: the flat
// number, building and road stay readable, and on iOS the tagger misses even the names. Documents
// almost always label their address blocks, so this recognizer keys off the label instead:
//
//     Billing Address :            <- label line
//     Kavya Raghunathan            <- name-like first line  -> PERSON
//     Flat 7B, Prestige Lakeside Habitat, Varthur Road
//     Gunjur, Whitefield           <- ADDRESS (one span over these lines)
//     BENGALURU, KARNATAKA, 560087 <- PIN line ends the block
//     IN
//     State/UT Code: 29            <- terminator (never reached here)
//
// Rules are deliberately conservative: only labelled blocks, at most `maxLines`, and the block
// closes at the first PIN-code line, blank line, or line that starts with another field label.
//
import Foundation

public struct AddressBlockRecognizer: Recognizer {
    public init() {}

    /// Most address lines a block may span (name line excluded).
    static let maxLines = 6

    /// "Billing Address :", "Shipping Address:", "Address of the Applicant :", "Permanent Address -", "Addr:".
    /// The label may start the line or end it: multi-column PDFs flatten to lines such as
    /// "Order Number: 171-... Order Date: 12.10.2025 Shipping Address :", with the block beneath.
    /// Group 1 is whatever follows the label on the same line (often empty).
    static let label = try! NSRegularExpression(
        pattern: #"(?im)(?:^|[ \t])(?:(?:billing|shipping|delivery|permanent|present|current|correspondence|communication|residential|registered|home|office|customer|consignee|buyer|bill[ -]?to|ship[ -]?to)[ \t]+)?addr(?:ess)?(?:[ \t]+(?:of[ \t]+(?:the[ \t]+)?\w+|details))?[ \t]*[:\-–][ \t]*(.*)$"#
    )

    /// Lines beginning with these are another field, so the address has ended.
    static let terminator = try! NSRegularExpression(
        pattern: #"(?i)^[ \t]*(?:state(?:/ut)?[ \t]*code|place[ \t]+of|gst|gstin|pan(?:[ \t]*no)?|phone|mobile|tel|email|e-mail|order|invoice|date|dob|sold[ \t]+by|shipping|billing|customer|account|a/c|ifsc|branch|micr|nominee|aadhaar|statement|total|amount|description|sl\.?|item|qty|hsn|payment|mode[ \t]+of|whether|for[ \t]+\w|page|in|india)\b"#
    )

    /// A line holding a 6-digit Indian PIN (not part of a longer number) closes the block after itself.
    static let pinLine = try! NSRegularExpression(pattern: #"(?<!\d)[1-9]\d{5}(?!\d)"#)

    /// Two to four capitalised words, optional honorific, no digits: a person, not a street.
    static let nameLike = try! NSRegularExpression(
        pattern: #"^(?:(?:Mr|Mrs|Ms|Dr|Shri|Smt|Kum|Sri)\.?[ \t]+)?[A-Z][A-Za-z.'\-]+(?:[ \t]+[A-Z][A-Za-z.'\-]+){1,3}\.?$"#
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

    public func recognize(in text: String) -> [PIIEntity] {
        var out: [PIIEntity] = []
        let ns = text as NSString
        // Split into lines keeping their ranges so entities can point back into `text`.
        var lines: [(range: NSRange, text: String)] = []
        var cursor = 0
        while cursor <= ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            var content = lineRange
            // Trim the newline from the stored range.
            let raw = ns.substring(with: lineRange)
            let trimmedNewline = raw.hasSuffix("\r\n") ? 2 : (raw.hasSuffix("\n") || raw.hasSuffix("\r") ? 1 : 0)
            content.length -= trimmedNewline
            lines.append((content, ns.substring(with: content)))
            if lineRange.length == 0 { break }
            cursor = NSMaxRange(lineRange)
            if cursor == ns.length { break }
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard let m = Self.label.firstMatch(in: line.text, range: NSRange(location: 0, length: (line.text as NSString).length)) else { i += 1; continue }
            // Address content: the remainder of the label line (if any) then following lines.
            var block: [(NSRange, String)] = []
            let rest = m.range(at: 1)
            if rest.location != NSNotFound, rest.length > 0 {
                let s = (line.text as NSString).substring(with: rest)
                if !s.trimmingCharacters(in: .whitespaces).isEmpty {
                    block.append((NSRange(location: line.range.location + rest.location, length: rest.length), s))
                }
            }
            var j = i + 1
            var nameEmitted = false
            var closedByPin = false
            while j < lines.count, block.count < Self.maxLines, !closedByPin {
                let (r, t) = lines[j]
                let trimmed = t.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { break }
                if Self.terminator.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil { break }
                // The first line after the label is the addressee when it looks like a person.
                if block.isEmpty, !nameEmitted, Self.isPersonName(trimmed) {
                    if let sr = Range(r, in: text) {
                        out.append(PIIEntity(type: .person, text: t, range: sr, score: 0.9))
                    }
                    nameEmitted = true
                    j += 1
                    continue
                }
                // Repeated addressee line (Amazon prints the name twice on shipping blocks).
                if block.isEmpty, nameEmitted, Self.isPersonName(trimmed) {
                    if let sr = Range(r, in: text) {
                        out.append(PIIEntity(type: .person, text: t, range: sr, score: 0.9))
                    }
                    j += 1
                    continue
                }
                block.append((r, t))
                if Self.pinLine.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil { closedByPin = true }
                j += 1
            }
            if let first = block.first, let last = block.last {
                let span = NSRange(location: first.0.location, length: NSMaxRange(last.0) - first.0.location)
                if let sr = Range(span, in: text) {
                    out.append(PIIEntity(type: .address, text: String(text[sr]), range: sr, score: 0.9))
                }
            }
            i = max(j, i + 1)
        }
        return out
    }

    /// Person-name test for the first line of a block.
    static func isPersonName(_ s: String) -> Bool {
        guard s.rangeOfCharacter(from: .decimalDigits) == nil, s.count <= 48 else { return false }
        guard nameLike.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil else { return false }
        let last = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() } ?? ""
        return !notNameSuffixes.contains(last)
    }
}
