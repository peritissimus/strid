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
