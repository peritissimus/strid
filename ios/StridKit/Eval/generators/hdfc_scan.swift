import Foundation
import CoreGraphics
import CoreText

// Generates Eval/hdfc_scan.pdf: a 3-page HDFC Bank account statement laid out like the bank's
// own PDF (two-column header with the customer block beside the account block, a seven-column
// transaction table whose narrations wrap over three lines, a footer with GSTIN and registered
// office). All data is synthetic. The eval harness OCRs this file when run on the rasterised
// copy (Eval/hdfc_scan_p1.jpg, produced by the command below) so the layout-order pass and the
// address recognizers are exercised on a scanned statement, not just a text layer.
//
//   swiftc -O Eval/generators/hdfc_scan.swift -o /tmp/gen && /tmp/gen Eval/hdfc_scan.pdf
//   sips -s format jpeg -s formatOptions 70 -Z 1700 Eval/hdfc_scan.pdf --out Eval/hdfc_scan_p1.jpg
let out = URL(fileURLWithPath: CommandLine.arguments[1])
var mb = CGRect(x: 0, y: 0, width: 595, height: 842)
let ctx = CGContext(out as CFURL, mediaBox: &mb, nil)!

func draw(_ s: String, _ x: CGFloat, _ yTop: CGFloat, size: CGFloat = 7.5, bold: Bool = false, right: CGFloat? = nil, serif: Bool = true) {
    let name = serif ? (bold ? "Times-Bold" : "Times-Roman") : (bold ? "Helvetica-Bold" : "Helvetica")
    let font = CTFontCreateWithName(name as CFString, size, nil)
    let a = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
    let line = CTLineCreateWithAttributedString(a)
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: right.map { $0 - w } ?? x, y: 842 - yTop)
    CTLineDraw(line, ctx)
}
func rule(_ y: CGFloat, _ x0: CGFloat, _ x1: CGFloat) { ctx.setLineWidth(0.4); ctx.move(to: CGPoint(x: x0, y: 842 - y)); ctx.addLine(to: CGPoint(x: x1, y: 842 - y)); ctx.strokePath() }
func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) { ctx.setLineWidth(0.4); ctx.move(to: CGPoint(x: x, y: 842 - y0)); ctx.addLine(to: CGPoint(x: x, y: 842 - y1)); ctx.strokePath() }

// Synthetic customer and account.
let holder = "MR. ROHAN VENKATESH"
let customerAddress = ["A3", "NAVEEN TERRACES APARTMENTS", "4TH BLOCK, 100FT ROAD, KORAMANGALA", "BENGALURU 560034", "KARNATAKA INDIA"]
let branchAddress = ["S S PLAZA, PLOT NO 12, SECTOR 29", "HUDA MARKET, NEAR CYBER PARK", "GURUGRAM 122001"]

// Counterparties and their VPAs; names are fictional.
struct Txn { let date: String; let narration: [String]; let ref: String; let wd: String; let dep: String; let bal: String }
let txns: [Txn] = [
    Txn(date: "01/04/26", narration: ["UPI-SHANAWAZ", "KHAN-PAYTMQRBOVZGMGOC4@PAYT", "M-YESB0PTMUPI-609172329708-UPI"], ref: "0000609172329708", wd: "70.00", dep: "", bal: "1,432,041.28"),
    Txn(date: "01/04/26", narration: ["UPI-POOJA N-Q243851593@YBL-YESB0YBLUPI-6", "09179917157-UPI"], ref: "0000609179917157", wd: "23.00", dep: "", bal: "1,432,018.28"),
    Txn(date: "01/04/26", narration: ["UPI-VIDYANAND", "KUMAR-PAYTM.S1YB756@PTY-YE", "SB0MCHUPI-609105878558-UPI"], ref: "0000609105878558", wd: "50.00", dep: "", bal: "1,431,968.28"),
    Txn(date: "02/04/26", narration: ["UPI-SHIVA", "KUMAR-BAJAJPAY.6879729.MDBCXUL", "1@INDUS-INDB0MERCHA-609229002825-UPI"], ref: "0000609229002825", wd: "18.00", dep: "", bal: "1,431,950.28"),
    Txn(date: "02/04/26", narration: ["NEFT CR-IDFB0010201-RZPX PVT LTD PAYROLL", "COMPLIANCE ESC-ROHAN", "VENKATESH-IDFBH260", "92904881"], ref: "IDFBH26092904881", wd: "", dep: "351,684.00", bal: "1,783,634.28"),
    Txn(date: "02/04/26", narration: ["UPI-SIMPLE MANE", "ADIGE-PAYTM.S17EFLZ@PTY-", "YESB0MCHUPI-609272564782-UPI"], ref: "0000609272564782", wd: "85.00", dep: "", bal: "1,783,549.28"),
    Txn(date: "03/04/26", narration: ["UPI-NAGARAJ-Q626111377@YBL-YESB0YBLUPI-6", "09316847651-UPI"], ref: "0000609316847651", wd: "23.00", dep: "", bal: "1,783,526.28"),
    Txn(date: "03/04/26", narration: ["UPI-KORAMANGALA CAFE", "AND-PAYTM-73734402@", "PTYS-YESB0PTMUPI-609322754137-UPI"], ref: "0000609322754137", wd: "294.00", dep: "", bal: "1,783,232.28"),
    Txn(date: "03/04/26", narration: ["UPI-PARMANAND", "YADAV-PAYTMQR6TU0TZ@PTYS-Y", "ESB0PTMUPI-609340742237-UPI"], ref: "0000609340742237", wd: "270.00", dep: "", bal: "1,782,962.28"),
    Txn(date: "04/04/26", narration: ["UPI-DURGA PRASAD-8178872928@PTYES-KKBK", "0004608-300131582105-SENT USING PAYTM U"], ref: "0000300131582105", wd: "", dep: "16,500.00", bal: "1,799,462.28"),
    Txn(date: "04/04/26", narration: ["UPI-CHAITANYA", "CHAKRAVART-KATURI.CHAITANY", "A119@OKHDFCBANK-HDFC0000009-609469629758", "-UPI"], ref: "0000609469629758", wd: "33,000.00", dep: "", bal: "1,766,462.28"),
    Txn(date: "04/04/26", narration: ["UPI-KRISHNA KUMAR", "GOWDA-KRISHNAGOWDA@OKSBI-", "SBIN0040107-609481210315-UPI"], ref: "0000609481210315", wd: "110.00", dep: "", bal: "1,766,352.28"),
    Txn(date: "04/04/26", narration: ["UPI-MAGNOLIA", "BAKERY-MAGNOLIABAKERY.42941", "709@HDFCBANK-HDFC0MERUPI-609490975800-UP", "I"], ref: "0000609490975800", wd: "609.00", dep: "", bal: "1,765,743.28"),
    Txn(date: "05/04/26", narration: ["UPI-VENKATARAJU M S-8660778214@YBL-SBIN", "0010450-609496147295-UPI"], ref: "0000609496147295", wd: "124.00", dep: "", bal: "1,765,619.28"),
    Txn(date: "05/04/26", narration: ["UPI-SWIGGY", "LIMITED-SWIGGY.STORES@AXISBANK-UTIB0000", "100-609402059118-UPI"], ref: "0000609402059118", wd: "2,908.00", dep: "", bal: "1,762,711.28"),
    Txn(date: "06/04/26", narration: ["IMPS-P2A-609711223344-ANITA", "RAGHAVAN-KKBK-XXXXXX4421-RENT"], ref: "609711223344", wd: "28,000.00", dep: "", bal: "1,734,711.28"),
    Txn(date: "07/04/26", narration: ["ATM WDL-BENGALURU KORAMANGALA-", "4567XXXXXXXX8901"], ref: "0000609812345678", wd: "10,000.00", dep: "", bal: "1,724,711.28"),
    Txn(date: "08/04/26", narration: ["CHQ DEP 000123 SURESH IYER"], ref: "000123", wd: "", dep: "45,000.00", bal: "1,769,711.28"),
]
let perPage = 6
let pages = Int(ceil(Double(txns.count) / Double(perPage)))

for p in 0..<pages {
    ctx.beginPage(mediaBox: &mb)
    draw("Page No .: \(p + 1)", 0, 30, size: 7, right: 320)
    // Logo block.
    ctx.setFillColor(red: 0.0, green: 0.27, blue: 0.6, alpha: 1); ctx.fill(CGRect(x: 36, y: 842 - 70, width: 180, height: 22))
    ctx.setFillColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1); ctx.fill(CGRect(x: 40, y: 842 - 67, width: 16, height: 16))
    ctx.setFillColor(gray: 1, alpha: 1); draw("HDFC BANK", 62, 65, size: 14, bold: true, serif: false)
    ctx.setFillColor(gray: 0, alpha: 1); draw("We understand your world", 36, 82, size: 8, serif: false)

    // Customer box (left).
    ctx.setLineWidth(0.8); ctx.stroke(CGRect(x: 36, y: 842 - 262, width: 254, height: 150))
    var y: CGFloat = 122
    draw(holder, 44, y, size: 8); y += 15
    for l in customerAddress { draw(l, 44, y, size: 8); y += 15 }
    y += 6; draw("JOINT HOLDERS :", 44, y, size: 8)
    draw("Nomination :  Registered", 44, 270, size: 8)

    // Account block (right): labels at x 318, values at x 372.
    let rows: [(String, String)] = [
        ("Account Branch", ": S S PLAZA"), ("Address", ": " + branchAddress[0]), ("", "  " + branchAddress[1]), ("", "  " + branchAddress[2]),
        ("State", ": HARYANA"), ("Phone no.", ": 18002586161"), ("OD Limit", ": 0.00"), ("Currency", ": INR"),
        ("Email", ": ROHAN.VENKATESH@EXAMPLE.COM"), ("Cust ID", ": 78945612"), ("Account No", ": 50100234567890   VIRTUAL PREFERRED"),
        ("A/C Open Date", ": 06/05/2023"), ("Account Status", ": Regular"), ("RTGS/NEFT IFSC:", "  HDFC0003878          MICR : 110240001"),
        ("Branch Code", ": 3878"), ("Account Type", ": SAVINGS A/C - RESIDENT(100)"),
    ]
    y = 78
    for (l, v) in rows { draw(l, 318, y, size: 7.5); draw(v, l.hasSuffix(":") ? 380 : 372, y, size: 7.5); y += 10.2 }

    draw("From :  01/04/2026", 40, 292, size: 8); draw("To :  30/09/2026", 150, 292, size: 8)
    draw("Statement of account", 320, 294, size: 11)

    // Table.
    let xs: [CGFloat] = [36, 82, 238, 338, 376, 440, 506, 572]
    let heads = ["Date", "Narration", "Chq./Ref.No.", "Value Dt", "Withdrawal Amt.", "Deposit Amt.", "Closing Balance"]
    rule(302, 36, 572)
    for (i, h) in heads.enumerated() { draw(h, xs[i] + 4, 314, size: 7.5, bold: true) }
    rule(322, 36, 572)
    y = 338
    for t in txns[(p * perPage)..<min(txns.count, (p + 1) * perPage)] {
        draw(t.date, xs[0] + 3, y, size: 7.5)
        for (i, l) in t.narration.enumerated() { draw(l, xs[1] + 3, y + CGFloat(i) * 16, size: 7.5) }
        draw(t.ref, xs[3] - 4, y, size: 7.5, right: xs[3] - 4)
        draw(t.date, xs[3] + 3, y, size: 7.5)
        if !t.wd.isEmpty { draw(t.wd, 0, y, size: 7.5, right: xs[5] - 4) }
        if !t.dep.isEmpty { draw(t.dep, 0, y, size: 7.5, right: xs[6] - 4) }
        draw(t.bal, 0, y, size: 7.5, right: xs[7] - 4)
        y += CGFloat(max(1, t.narration.count)) * 16 + 10
    }
    let tableBottom: CGFloat = 740
    rule(tableBottom, 36, 572)
    for x in xs { vline(x, 302, tableBottom) }

    // Footer.
    draw("HDFC BANK LIMITED", 36, 766, size: 9, bold: true)
    draw("*Closing balance includes funds earmarked for hold and uncleared funds", 36, 777, size: 7)
    draw("Contents of this statement will be considered correct if no error is reported within 30 days of receipt of statement.The address on this statement is that on record with the Bank as at the day of requesting this statement.", 36, 786, size: 5.5)
    draw("State account branch GSTN:29AAJCB4821P1Z4", 36, 796, size: 6.5, bold: true)
    draw("HDFC Bank GSTIN number details are available at https://www.hdfcbank.com/personal/making-payments/online-tax-payment/goods-and-service-tax.", 36, 804, size: 6)
    draw("Registered Office Address: HDFC Bank House, Senapati Bapat Marg, Lower Parel, Mumbai 400013", 36, 812, size: 6.5)
    ctx.endPage()
}
ctx.closePDF()
