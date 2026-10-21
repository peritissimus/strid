//
// IndianPlaceRecognizer.swift
// StridKit
//
// A simple gazetteer (dictionary lookup) recognizer for Indian geography. NLTagger's place-name
// model is trained mostly on Western prose and misses a large share of Indian states and cities,
// particularly when printed in capitals in an address block ("BENGALURU, KARNATAKA 560001").
// The list is compiled into one alternation regex at first use.
//
import Foundation

/// Gazetteer of Indian states, union territories and major cities. NLTagger misses many of these,
/// especially in ALL CAPS or when followed by a PIN code.
public struct IndianPlaceRecognizer: Recognizer {
    public init() {}

    /// Place names to match. Includes both current and former names where both are in common
    /// use on documents (Bengaluru/Bangalore, Mysuru/Mysore, Prayagraj/Allahabad).
    static let places: [String] = [
        // States & UTs
        "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana",
        "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur",
        "Meghalaya", "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana",
        "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal", "Delhi", "New Delhi", "Chandigarh", "Puducherry",
        "Jammu", "Kashmir", "Ladakh", "Lakshadweep",
        // Cities
        "Mumbai", "Bengaluru", "Bangalore", "Chennai", "Kolkata", "Hyderabad", "Pune", "Ahmedabad", "Jaipur", "Surat",
        "Lucknow", "Kanpur", "Nagpur", "Indore", "Thane", "Bhopal", "Visakhapatnam", "Vadodara", "Patna", "Ghaziabad",
        "Ludhiana", "Agra", "Nashik", "Faridabad", "Meerut", "Rajkot", "Varanasi", "Srinagar", "Aurangabad", "Dhanbad",
        "Amritsar", "Navi Mumbai", "Allahabad", "Prayagraj", "Ranchi", "Howrah", "Coimbatore", "Jabalpur", "Gwalior",
        "Vijayawada", "Jodhpur", "Madurai", "Raipur", "Kota", "Guwahati", "Chandigarh", "Solapur", "Hubli", "Mysuru",
        "Mysore", "Tiruchirappalli", "Bareilly", "Thiruvananthapuram", "Kochi", "Ernakulam", "Kozhikode", "Noida",
        "Gurugram", "Gurgaon", "Dehradun", "Mangaluru", "Mangalore", "Udaipur", "Bhubaneswar", "Cuttack", "Salem",
        "Warangal", "Guntur", "Bhiwandi", "Amravati", "Nanded", "Kolhapur", "Ajmer", "Jamshedpur", "Siliguri",
    ]

    /// Single case-insensitive alternation `\b(?:New Delhi|Navi Mumbai|...|Goa)\b`.
    ///
    /// Alternatives are sorted longest-first so that "New Delhi" and "Navi Mumbai" win over the
    /// embedded "Delhi" / "Mumbai"; NSRegularExpression tries alternatives left to right and
    /// takes the first that matches. Each name is regex-escaped (defensive; none currently need it).
    private static let regex: NSRegularExpression = {
        let alts = places.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }
        return try! NSRegularExpression(pattern: #"\b(?:"# + alts.joined(separator: "|") + #")\b"#, options: [.caseInsensitive])
    }()

    /// Emits a `.location` entity for each gazetteer hit.
    ///
    /// Score `0.7` is below NLTagger's `0.85`, so when both fire on the same span (common for
    /// "Mumbai" in prose) the NLTagger entity wins the overlap and nothing is double-counted.
    public func recognize(in text: String) -> [PIIEntity] {
        let ns = text as NSString
        return Self.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let r = Range(m.range, in: text) else { return nil }
            return PIIEntity(type: .location, text: String(text[r]), range: r, score: 0.7)
        }
    }
}
