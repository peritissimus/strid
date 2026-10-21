import Foundation
import CoreGraphics
import CoreText

// Generates the identity-document fixtures in Eval/: a PAN card, a passport data page with its
// MRZ, a voter ID card, a driving licence, a vehicle registration certificate and a Form 16 page.
// Every value is synthetic. Each PDF gets a sibling .expected.json written by this program so the
// ground truth and the drawing never drift apart.
//
//   swiftc -O Eval/generators/id_cards.swift -o /tmp/genids && /tmp/genids Eval
//   for f in pan_card passport voter_card driving_licence; do
//     sips -s format jpeg -s formatOptions 70 -Z 1400 Eval/$f.pdf --out Eval/${f}_photo.jpg; cp Eval/$f.expected.json Eval/${f}_photo.expected.json; done
let dir = URL(fileURLWithPath: CommandLine.arguments[1])

struct Doc {
    let name: String
    let size: CGSize
    let draw: (CGContext, (String, CGFloat, CGFloat, CGFloat, Bool) -> Void) -> Void
    let expected: [(String, String)]
    let not: [String]
}

func text(_ ctx: CGContext, _ h: CGFloat) -> (String, CGFloat, CGFloat, CGFloat, Bool) -> Void {
    { s, x, yTop, size, bold in
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let a = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        ctx.textPosition = CGPoint(x: x, y: h - yTop)
        CTLineDraw(CTLineCreateWithAttributedString(a), ctx)
    }
}

func photoBox(_ ctx: CGContext, _ r: CGRect) {
    ctx.setFillColor(gray: 0.82, alpha: 1); ctx.fill(r)
    ctx.setFillColor(gray: 0.55, alpha: 1)
    ctx.fillEllipse(in: CGRect(x: r.midX - r.width * 0.18, y: r.midY + r.height * 0.05, width: r.width * 0.36, height: r.height * 0.36))
    ctx.fillEllipse(in: CGRect(x: r.midX - r.width * 0.32, y: r.minY - r.height * 0.1, width: r.width * 0.64, height: r.height * 0.5))
    ctx.setFillColor(gray: 0, alpha: 1)
}

func signature(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat) {
    ctx.setLineWidth(1.2)
    ctx.move(to: CGPoint(x: x, y: y))
    ctx.addCurve(to: CGPoint(x: x + 60, y: y + 4), control1: CGPoint(x: x + 10, y: y + 18), control2: CGPoint(x: x + 30, y: y - 14))
    ctx.addCurve(to: CGPoint(x: x + 95, y: y + 2), control1: CGPoint(x: x + 70, y: y + 14), control2: CGPoint(x: x + 85, y: y - 10))
    ctx.strokePath()
}

let card = CGSize(width: 243, height: 153)   // 85.6 x 54 mm at 72 dpi
let a4 = CGSize(width: 595, height: 842)

let docs: [Doc] = [
    Doc(name: "pan_card", size: card, draw: { ctx, t in
        ctx.setFillColor(red: 0.93, green: 0.95, blue: 1, alpha: 1); ctx.fill(CGRect(origin: .zero, size: card))
        ctx.setFillColor(gray: 0, alpha: 1)
        t("आयकर विभाग", 12, 16, 7, true); t("INCOME TAX DEPARTMENT", 12, 26, 7, true)
        t("भारत सरकार", 160, 16, 7, true); t("GOVT. OF INDIA", 160, 26, 7, true)
        t("Permanent Account Number Card", 60, 44, 8, true)
        t("ABCPV1234K", 60, 60, 12, true)
        t("नाम / Name", 12, 76, 6, false); t("ROHAN VENKATESH", 12, 86, 8, true)
        t("पिता का नाम / Father's Name", 12, 100, 6, false); t("SRINIVAS VENKATESH", 12, 110, 8, true)
        t("जन्म की तारीख / Date of Birth", 12, 124, 6, false); t("21/08/1990", 12, 134, 8, true)
        photoBox(ctx, CGRect(x: 180, y: 20, width: 48, height: 58))
        t("हस्ताक्षर / Signature", 176, 142, 5, false); signature(ctx, 170, 30)
    }, expected: [("IN_PAN", "ABCPV1234K"), ("PERSON", "ROHAN VENKATESH"), ("PERSON", "SRINIVAS VENKATESH"), ("IN_DOB", "21/08/1990")],
       not: ["INCOME TAX DEPARTMENT", "Permanent Account Number Card", "GOVT. OF INDIA"]),

    Doc(name: "passport", size: CGSize(width: 354, height: 250), draw: { ctx, t in
        ctx.setFillColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1); ctx.fill(CGRect(origin: .zero, size: CGSize(width: 354, height: 250)))
        ctx.setFillColor(gray: 0, alpha: 1)
        t("भारत गणराज्य  REPUBLIC OF INDIA", 90, 18, 9, true)
        t("पासपोर्ट / PASSPORT", 24, 34, 7, false)
        t("Type / प्रकार", 110, 34, 5, false); t("P", 110, 44, 8, true)
        t("Country Code", 170, 34, 5, false); t("IND", 170, 44, 8, true)
        t("Passport No.", 240, 34, 5, false); t("M8231456", 240, 44, 9, true)
        photoBox(ctx, CGRect(x: 24, y: 70, width: 70, height: 90))
        t("Surname", 110, 60, 5, false); t("VENKATESH", 110, 70, 8, true)
        t("Given Name(s)", 110, 82, 5, false); t("ROHAN", 110, 92, 8, true)
        t("Nationality", 110, 104, 5, false); t("INDIAN", 110, 114, 8, true)
        t("Sex", 200, 104, 5, false); t("M", 200, 114, 8, true)
        t("Date of Birth", 240, 104, 5, false); t("21/08/1990", 240, 114, 8, true)
        t("Place of Birth", 110, 126, 5, false); t("BENGALURU, KARNATAKA", 110, 136, 8, true)
        t("Place of Issue", 110, 148, 5, false); t("BENGALURU", 110, 158, 8, true)
        t("Date of Issue", 240, 148, 5, false); t("12/04/2021", 240, 158, 8, true)
        t("Date of Expiry", 240, 170, 5, false); t("11/04/2031", 240, 180, 8, true)
        signature(ctx, 30, 70)
        let mono = CTFontCreateWithName("Courier-Bold" as CFString, 9.2, nil)
        for (i, l) in ["P<INDVENKATESH<<ROHAN<<<<<<<<<<<<<<<<<<<<<<<<", "M8231456<4IND9008215M3104129<<<<<<<<<<<<<<<4"].enumerated() {
            let a = NSAttributedString(string: l, attributes: [kCTFontAttributeName as NSAttributedString.Key: mono])
            ctx.textPosition = CGPoint(x: 24, y: 250 - (212 + CGFloat(i) * 13)); CTLineDraw(CTLineCreateWithAttributedString(a), ctx)
        }
    }, expected: [("IN_PASSPORT", "M8231456"), ("PERSON", "VENKATESH"), ("PERSON", "ROHAN"), ("IN_DOB", "21/08/1990"),
                  ("LOCATION", "BENGALURU"), ("LOCATION", "KARNATAKA"), ("IN_PASSPORT", "P<INDVENKATESH<<ROHAN"), ("IN_PASSPORT", "M8231456<4IND9008215M3104129")],
       not: ["REPUBLIC OF INDIA", "PASSPORT", "Nationality", "Place of Birth"]),

    Doc(name: "voter_card", size: card, draw: { ctx, t in
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(origin: .zero, size: card))
        ctx.setFillColor(gray: 0, alpha: 1)
        t("भारत निर्वाचन आयोग", 70, 14, 7, true); t("ELECTION COMMISSION OF INDIA", 50, 24, 7, true)
        t("मतदाता फोटो पहचान पत्र", 60, 34, 6, false); t("Elector's Photo Identity Card", 60, 43, 6, false)
        t("RJP2846153", 150, 58, 10, true)
        photoBox(ctx, CGRect(x: 12, y: 40, width: 50, height: 60))
        t("निर्वाचक का नाम / Elector's Name", 70, 72, 5, false); t("Rohan Venkatesh", 70, 82, 8, true)
        t("पिता का नाम / Father's Name", 70, 96, 5, false); t("Srinivas Venkatesh", 70, 106, 8, true)
        t("लिंग / Sex", 70, 120, 5, false); t("M", 70, 130, 8, true)
        t("जन्म तिथि / Date of Birth", 140, 120, 5, false); t("21/08/1990", 140, 130, 8, true)
        t("Address: 4th Block, 100 Ft Road, Koramangala, Bengaluru 560034", 12, 146, 5.5, false)
    }, expected: [("IN_VOTER_ID", "RJP2846153"), ("PERSON", "Rohan Venkatesh"), ("PERSON", "Srinivas Venkatesh"), ("IN_DOB", "21/08/1990"),
                  ("ADDRESS", "4th Block, 100 Ft Road, Koramangala"), ("IN_PIN_CODE", "560034")],
       not: ["ELECTION COMMISSION OF INDIA", "Elector's Photo Identity Card"]),

    Doc(name: "driving_licence", size: card, draw: { ctx, t in
        ctx.setFillColor(red: 0.95, green: 0.98, blue: 0.95, alpha: 1); ctx.fill(CGRect(origin: .zero, size: card))
        ctx.setFillColor(gray: 0, alpha: 1)
        t("GOVERNMENT OF KARNATAKA", 60, 14, 7, true); t("DRIVING LICENCE", 80, 24, 8, true)
        t("DL No: KA05 20180012345", 12, 40, 8, true)
        t("Issue Date: 14/03/2018", 12, 52, 6, false); t("Valid Till: 20/08/2040", 120, 52, 6, false)
        photoBox(ctx, CGRect(x: 180, y: 50, width: 50, height: 60))
        t("Name: ROHAN VENKATESH", 12, 66, 7, true)
        t("S/D/W of: SRINIVAS VENKATESH", 12, 78, 6.5, false)
        t("DOB: 21/08/1990", 12, 90, 6.5, false); t("BG: B+", 100, 90, 6.5, false)
        t("Address: A3, NAVEEN TERRACES, 4TH BLOCK,", 12, 102, 6, false)
        t("KORAMANGALA, BENGALURU 560034", 12, 112, 6, false)
        t("COV: LMV, MCWG", 12, 126, 6.5, false)
        t("Signature of Holder", 170, 142, 5, false); signature(ctx, 165, 28)
    }, expected: [("IN_DRIVING_LICENCE", "KA05 20180012345"), ("PERSON", "ROHAN VENKATESH"), ("PERSON", "SRINIVAS VENKATESH"), ("IN_DOB", "21/08/1990"),
                  ("ADDRESS", "A3, NAVEEN TERRACES, 4TH BLOCK"), ("ADDRESS", "KORAMANGALA"), ("IN_PIN_CODE", "560034")],
       not: ["DRIVING LICENCE", "GOVERNMENT OF KARNATAKA", "COV"]),

    Doc(name: "vehicle_rc", size: card, draw: { ctx, t in
        ctx.setFillColor(red: 1, green: 0.97, blue: 0.9, alpha: 1); ctx.fill(CGRect(origin: .zero, size: card))
        ctx.setFillColor(gray: 0, alpha: 1)
        t("GOVERNMENT OF KARNATAKA", 60, 12, 6.5, true); t("CERTIFICATE OF REGISTRATION", 55, 21, 7, true)
        t("Regn. No: KA 05 MJ 4821", 12, 36, 8, true); t("Regn. Date: 10/01/2022", 140, 36, 6, false)
        t("Chassis No: MA3EWDE1S00482915", 12, 50, 6.5, false)
        t("Engine No: K12MN4582113", 12, 61, 6.5, false)
        t("Owner Name: ROHAN VENKATESH", 12, 74, 7, true)
        t("S/W/D of: SRINIVAS VENKATESH", 12, 85, 6, false)
        t("Address: A3, NAVEEN TERRACES, KORAMANGALA, BENGALURU 560034", 12, 96, 5.5, false)
        t("Maker: MARUTI SUZUKI INDIA LTD", 12, 108, 6, false); t("Model: SWIFT VXI", 140, 108, 6, false)
        t("Fuel: PETROL", 12, 119, 6, false); t("Colour: PEARL ARCTIC WHITE", 80, 119, 6, false)
        t("Regn Valid Upto: 09/01/2037", 12, 131, 6, false); t("Tax Upto: LTT", 140, 131, 6, false)
        t("Mobile: 9845012345", 12, 143, 6, false)
    }, expected: [("IN_VEHICLE_REG", "KA 05 MJ 4821"), ("IN_VEHICLE_REG", "MA3EWDE1S00482915"), ("IN_VEHICLE_REG", "K12MN4582113"),
                  ("PERSON", "ROHAN VENKATESH"), ("PERSON", "SRINIVAS VENKATESH"), ("ADDRESS", "A3, NAVEEN TERRACES, KORAMANGALA"),
                  ("IN_PIN_CODE", "560034"), ("PHONE", "9845012345"), ("ORGANIZATION", "MARUTI SUZUKI INDIA LTD")],
       not: ["CERTIFICATE OF REGISTRATION", "PETROL", "SWIFT VXI"]),

    Doc(name: "form16", size: a4, draw: { ctx, t in
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(origin: .zero, size: a4))
        ctx.setFillColor(gray: 0, alpha: 1)
        t("FORM NO. 16", 260, 40, 12, true)
        t("[See rule 31(1)(a)]", 250, 54, 8, false)
        t("PART A", 280, 70, 9, true)
        t("Certificate under Section 203 of the Income-tax Act, 1961 for tax deducted at source on salary", 80, 84, 8, false)
        t("Certificate No. QWERTYU", 40, 104, 8, false); t("Last updated on 30-May-2026", 400, 104, 8, false)
        t("Name and address of the Employer", 40, 124, 8, true); t("Name and address of the Employee", 320, 124, 8, true)
        t("RZPX PRIVATE LIMITED", 40, 138, 8, false); t("ROHAN VENKATESH", 320, 138, 8, false)
        t("Tower B, 3rd Floor, Prestige Tech Park,", 40, 150, 8, false); t("A3, NAVEEN TERRACES APARTMENTS,", 320, 150, 8, false)
        t("Outer Ring Road, Bengaluru 560103", 40, 162, 8, false); t("4TH BLOCK, KORAMANGALA, BENGALURU 560034", 320, 162, 8, false)
        t("CIN: U72200KA2015PTC081234", 40, 174, 8, false); t("Mobile: 9845012345", 320, 174, 8, false)
        t("PAN of the Deductor", 40, 200, 8, true); t("TAN of the Deductor", 200, 200, 8, true); t("PAN of the Employee", 360, 200, 8, true)
        t("AAJCR4821P", 40, 214, 8, false); t("BLRR12345F", 200, 214, 8, false); t("ABCPV1234K", 360, 214, 8, false)
        t("Employee Reference No.: EMP00417", 40, 236, 8, false); t("UAN: 100987654321", 320, 236, 8, false)
        t("Assessment Year: 2026-27", 40, 256, 8, false); t("Period: 01-Apr-2025 to 31-Mar-2026", 320, 256, 8, false)
        t("Summary of amount paid/credited and tax deducted at source thereon in respect of the employee", 40, 280, 8, true)
        var y: CGFloat = 300
        for (q, a, d) in [("Q1", "8,79,210.00", "1,12,400.00"), ("Q2", "8,79,210.00", "1,12,400.00"), ("Q3", "8,79,210.00", "1,12,400.00"), ("Q4", "8,79,210.00", "1,12,400.00")] {
            t(q, 40, y, 8, false); t(a, 200, y, 8, false); t(d, 360, y, 8, false); y += 14
        }
        t("Receipt Numbers of original quarterly statements: QWRTY123, QWRTY124, QWRTY125, QWRTY126", 40, y + 10, 7.5, false)
        t("Verification", 40, y + 40, 8, true)
        t("I, PRIYA NAIR, son/daughter of K. NAIR working in the capacity of FINANCE HEAD do hereby certify that", 40, y + 54, 8, false)
        t("a sum of Rs. 4,49,600.00 has been deducted and deposited to the credit of the Central Government.", 40, y + 66, 8, false)
        t("Place: Bengaluru", 40, y + 90, 8, false); t("Date: 30-May-2026", 200, y + 90, 8, false)
        t("(Signature of person responsible for deduction of tax)", 320, y + 110, 7, false)
        signature(ctx, 380, a4.height - (y + 96))
    }, expected: [("PERSON", "ROHAN VENKATESH"), ("ADDRESS", "4TH BLOCK, KORAMANGALA"),
                  ("IN_PIN_CODE", "560034"), ("PHONE", "9845012345"), ("IN_CIN", "U72200KA2015PTC081234"), ("IN_PAN", "AAJCR4821P"),
                  ("IN_TAN", "BLRR12345F"), ("IN_PAN", "ABCPV1234K"), ("IN_UAN", "100987654321"), ("PERSON", "PRIYA NAIR"),
                  ("ORGANIZATION", "RZPX PRIVATE LIMITED"), ("IN_PIN_CODE", "560103"), ("PERSON", "K. NAIR"), ("IN_CUSTOMER_ID", "EMP00417")],
       not: ["FORM NO. 16", "PART A", "Assessment Year", "Verification", "Certificate under Section 203"]),
]

for d in docs {
    var mb = CGRect(origin: .zero, size: d.size)
    let url = dir.appendingPathComponent(d.name + ".pdf")
    let ctx = CGContext(url as CFURL, mediaBox: &mb, nil)!
    ctx.beginPage(mediaBox: &mb)
    d.draw(ctx, text(ctx, d.size.height))
    ctx.endPage(); ctx.closePDF()
    let json: [String: Any] = [
        "entities": d.expected.map { ["type": $0.0, "text": $0.1] },
        "not": d.not.map { ["text": $0] },
    ]
    let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try! data.write(to: dir.appendingPathComponent(d.name + ".expected.json"))
    print("wrote", d.name)
}
