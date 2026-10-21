//
// Checksums.swift
// StridKit
//
// Check-digit validators plugged into `RegexRecognizer` as `validator` closures. A regex alone
// cannot tell a 12-digit Aadhaar from a 12-digit transaction reference, or a 16-digit card number
// from a 16-digit account number; the issuing schemes' check digits can. A match that fails its
// checksum is dropped entirely, and one that passes is promoted to `validatedScore`.
//
import Foundation

/// Checksum validators used to cut false positives on numeric identifiers.
public enum Checksums {
    /// GSTIN check digit (15th character) per the GSTN specification.
    ///
    /// Characters are valued in base 36 (0-9 then A-Z). Positions alternate weights 1, 2, 1, 2...
    /// from the first character; each product is split into quotient and remainder base 36 and
    /// both are summed. The check character is `(36 - sum mod 36) mod 36` in base 36.
    public static func gstin(_ s: String) -> Bool {
        let chars = Array(s.uppercased())
        guard chars.count == 15 else { return false }
        func value(_ c: Character) -> Int? {
            if let d = c.wholeNumberValue, c.isASCII { return d }
            guard let a = c.asciiValue, a >= 65, a <= 90 else { return nil }
            return Int(a) - 65 + 10
        }
        var sum = 0
        for (i, c) in chars[0..<14].enumerated() {
            guard let v = value(c) else { return false }
            let product = v * (i % 2 == 0 ? 1 : 2)
            sum += product / 36 + product % 36
        }
        guard let check = value(chars[14]) else { return false }
        return (36 - sum % 36) % 36 == check
    }

    /// IBAN check (ISO 7064 mod 97-10): the country code and check digits are moved to the end,
    /// letters become two-digit numbers (A = 10 … Z = 35) and the whole must be 1 modulo 97.
    public static func iban(_ s: String) -> Bool {
        let clean = s.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count >= 15, clean.count <= 34 else { return false }
        let rearranged = clean.dropFirst(4) + clean.prefix(4)
        var remainder = 0
        for c in rearranged {
            let v: Int
            if let d = c.wholeNumberValue, c.isASCII { v = d }
            else if let a = c.asciiValue, a >= 65, a <= 90 { v = Int(a) - 55 }
            else { return false }
            remainder = v >= 10 ? (remainder * 100 + v) % 97 : (remainder * 10 + v) % 97
        }
        return remainder == 1
    }

    /// Two-letter state and union-territory codes that start a vehicle registration mark or a
    /// driving licence number. Old codes still seen on documents (OR, UA, CG) are included.
    public static let vehicleStateCodes: Set<String> = [
        "AN", "AP", "AR", "AS", "BR", "CG", "CH", "DD", "DL", "DN", "GA", "GJ", "HP", "HR", "JH", "JK", "KA", "KL",
        "LA", "LD", "MH", "ML", "MN", "MP", "MZ", "NL", "OD", "OR", "PB", "PY", "RJ", "SK", "TN", "TR", "TS", "TG",
        "UA", "UK", "UP", "WB",
    ]

    /// Whether `s` starts with a state code from `vehicleStateCodes`.
    public static func startsWithStateCode(_ s: String) -> Bool {
        vehicleStateCodes.contains(String(s.uppercased().prefix(2)))
    }

    /// Verhoeff checksum, used by UIDAI for Aadhaar numbers.
    ///
    /// Verhoeff is a dihedral-group (D5) check-digit scheme that catches all single-digit errors
    /// and all adjacent transpositions, which plain mod-10 schemes cannot. The algorithm walks the
    /// digits right-to-left, maintaining a running checksum `c` in the group:
    ///
    ///     c = d[c][p[i mod 8][digit_i]]
    ///
    /// where `p` permutes each digit according to its position and `d` is the group
    /// multiplication table. A valid number (check digit included) ends with `c == 0`.
    ///
    /// - Parameter digits: The candidate, possibly containing spaces or hyphens between groups
    ///   (`"2345 6789 0123"`). Any other non-digit character causes rejection.
    /// - Returns: `true` if the digits form a valid Verhoeff-checked number.
    public static func verhoeff(_ digits: String) -> Bool {
        // d: multiplication table of the dihedral group D5 (10 x 10).
        let d: [[Int]] = [
            [0,1,2,3,4,5,6,7,8,9],[1,2,3,4,0,6,7,8,9,5],[2,3,4,0,1,7,8,9,5,6],[3,4,0,1,2,8,9,5,6,7],
            [4,0,1,2,3,9,5,6,7,8],[5,9,8,7,6,0,4,3,2,1],[6,5,9,8,7,1,0,4,3,2],[7,6,5,9,8,2,1,0,4,3],
            [8,7,6,5,9,3,2,1,0,4],[9,8,7,6,5,4,3,2,1,0],
        ]
        // p: position-dependent permutation table (8 x 10); row i applies to digit position i mod 8.
        let p: [[Int]] = [
            [0,1,2,3,4,5,6,7,8,9],[1,5,7,6,2,8,3,0,9,4],[5,8,0,3,7,9,6,1,4,2],[8,9,1,6,0,4,3,5,2,7],
            [9,4,5,3,1,2,6,8,7,0],[4,2,8,6,5,7,3,9,0,1],[2,7,9,3,8,0,6,4,1,5],[7,0,4,6,9,1,3,2,5,8],
        ]
        let nums = digits.compactMap { $0.wholeNumberValue }
        // Every non-separator character must have been a digit; otherwise the input was not a
        // clean number (e.g. "12a4...") and we must not validate it.
        guard nums.count == digits.filter({ !$0.isWhitespace && $0 != "-" }).count, !nums.isEmpty else { return false }
        var c = 0
        // Position 0 is the rightmost digit (the check digit itself).
        for (i, n) in nums.reversed().enumerated() {
            c = d[c][p[i % 8][n]]
        }
        return c == 0
    }

    /// Luhn mod-10, used by payment card numbers.
    ///
    /// Walking right-to-left, every second digit (starting with the one *left* of the check
    /// digit) is doubled, and 9 is subtracted when the doubled value exceeds 9 (equivalent to
    /// summing its two digits). The number is valid when the total is divisible by 10.
    ///
    /// Example: `4111 1111 1111 1111` -> valid test Visa number.
    ///
    /// - Parameter digits: Candidate with optional separators; non-digits are ignored.
    /// - Returns: `true` if at least 12 digits are present and the Luhn sum is 0 mod 10.
    ///   The 12-digit floor stops short numeric runs from passing by chance (10% of all
    ///   random digit strings satisfy Luhn).
    public static func luhn(_ digits: String) -> Bool {
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count >= 12 else { return false }
        var sum = 0
        for (i, n) in nums.reversed().enumerated() {
            if i % 2 == 1 {
                // Odd positions from the right are doubled.
                let x = n * 2
                sum += x > 9 ? x - 9 : x
            } else {
                sum += n
            }
        }
        return sum % 10 == 0
    }

    /// Strips spaces and hyphens.
    ///
    /// In fact strips *everything* that is not a number character, which also drops any stray
    /// letters. Used to normalise matches like `"2345 6789 0123"` before checksum validation.
    public static func digitsOnly(_ s: String) -> String {
        s.filter { $0.isNumber }
    }
}
