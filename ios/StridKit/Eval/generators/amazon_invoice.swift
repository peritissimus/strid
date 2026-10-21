import Foundation
import CoreGraphics
import CoreText

// Generates Eval/amazon_invoice.pdf: a faithful Amazon.in "Tax Invoice/Bill of Supply/Cash Memo"
// layout with entirely synthetic data (fictional seller, buyer, IDs; the GSTIN has a valid check digit).
//
//   swiftc -O Eval/generators/amazon_invoice.swift -o /tmp/gen && /tmp/gen Eval/amazon_invoice.pdf
let out = URL(fileURLWithPath: CommandLine.arguments[1])
var mb = CGRect(x: 0, y: 0, width: 595, height: 842)
let ctx = CGContext(out as CFURL, mediaBox: &mb, nil)!
ctx.beginPage(mediaBox: &mb)
func draw(_ s: String, _ x: CGFloat, _ yTop: CGFloat, size: CGFloat = 8.5, bold: Bool = false, right: CGFloat? = nil) {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    let a = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
    let line = CTLineCreateWithAttributedString(a)
    var w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let xx = right.map { $0 - w } ?? x
    ctx.textPosition = CGPoint(x: xx, y: 842 - yTop)
    CTLineDraw(line, ctx); _ = w
}
func rule(_ y: CGFloat, _ x0: CGFloat = 36, _ x1: CGFloat = 559) { ctx.setLineWidth(0.5); ctx.move(to: CGPoint(x: x0, y: 842 - y)); ctx.addLine(to: CGPoint(x: x1, y: 842 - y)); ctx.strokePath() }

draw("amazon.in", 36, 48, size: 16, bold: true)
draw("Tax Invoice/Bill of Supply/Cash Memo", 0, 44, size: 10, bold: true, right: 559)
draw("(Original for Recipient)", 0, 56, size: 8.5, right: 559)

var y: CGFloat = 86
draw("Sold By :", 36, y, bold: true); draw("Billing Address :", 330, y, bold: true)
for (i, l) in ["Brightline Retail Private Limited", "* Survey No. 45/2, Soukya Road, Samethanahalli", "Village, Anugondanahalli Hobli, Hoskote Taluk", "Bengaluru Rural, KARNATAKA, 560067", "IN"].enumerated() { draw(l, 36, y + 12 + CGFloat(i) * 11) }
for (i, l) in ["Kavya Raghunathan", "Flat 7B, Prestige Lakeside Habitat, Varthur Road", "Gunjur, Whitefield", "BENGALURU, KARNATAKA, 560087", "IN", "State/UT Code: 29"].enumerated() { draw(l, 330, y + 12 + CGFloat(i) * 11) }
y = 160
draw("PAN No: AAJCB4821P", 36, y)
draw("GST Registration No: 29AAJCB4821P1Z4", 36, y + 11)
for (i, l) in ["Kavya Raghunathan", "Kavya Raghunathan", "Flat 7B, Prestige Lakeside Habitat, Varthur Road", "Gunjur, Whitefield", "BENGALURU, KARNATAKA, 560087", "IN", "State/UT Code: 29", "Place of supply: KARNATAKA", "Place of delivery: KARNATAKA"].enumerated() { draw(l, 330, y + 95 + CGFloat(i) * 11) }
y = 232
draw("Order Number: 171-8264519-3350731", 36, y); draw("Order Date: 12.10.2025", 36, y + 11)
// Real Amazon.in invoices put this label on the same baseline as "Order Date", so the text layer
// flattens to "Order Number: ... Order Date: ... Shipping Address :" on one line.
draw("Shipping Address :", 330, y + 11, bold: true)
draw("Invoice Number : BLR7-2140187", 330, y + 100); draw("Invoice Details : KA-BLR7-1234567-2526", 330, y + 111); draw("Invoice Date : 13.10.2025", 330, y + 122)

// table
y = 360
rule(y - 10)
let cols: [(String, CGFloat)] = [("Sl.", 38), ("Description", 58), ("Unit", 300), ("Qty", 345), ("Net", 370), ("Tax", 415), ("Tax", 445), ("Tax", 480), ("Total", 520)]
for (t, x) in cols { draw(t, x, y, bold: true) }
let cols2: [(String, CGFloat)] = [("No", 38), ("Price", 300), ("Amount", 370), ("Rate", 415), ("Type", 445), ("Amount", 480), ("Amount", 520)]
for (t, x) in cols2 { draw(t, x, y + 10, bold: true) }
rule(y + 16)
y = 392
draw("1", 38, y)
draw("boAt Rockerz 450 Bluetooth On Ear Headphones with Mic, Upto 15 Hours", 58, y)
draw("Playback, 40MM Drivers (Luscious Black) | B07PR1CL3S ( B07PR1CL3S )", 58, y + 11)
draw("HSN:85183000", 58, y + 22)
draw("₹1,101.69", 300, y); draw("1", 345, y); draw("₹1,101.69", 370, y); draw("9%", 415, y); draw("CGST", 445, y); draw("₹99.15", 480, y); draw("₹1,299.00", 520, y)
draw("9%", 415, y + 11); draw("SGST", 445, y + 11); draw("₹99.16", 480, y + 11)
draw("Shipping Charges", 58, y + 36); draw("₹0.00", 300, y + 36); draw("₹0.00", 370, y + 36); draw("9%", 415, y + 36); draw("CGST", 445, y + 36); draw("₹0.00", 480, y + 36); draw("₹0.00", 520, y + 36)
rule(y + 50)
draw("TOTAL:", 36, y + 62, bold: true); draw("₹198.31", 480, y + 62, bold: true); draw("₹1,299.00", 520, y + 62, bold: true)
rule(y + 70)
draw("Amount in Words:", 36, y + 82, bold: true); draw("One Thousand Two Hundred Ninety-nine only", 36, y + 93)
rule(y + 100)
draw("For Brightline Retail Private Limited:", 0, y + 112, bold: true, right: 559)
draw("Authorized Signatory", 0, y + 150, right: 559)
rule(y + 158)
draw("Whether tax is payable under reverse charge - No", 36, y + 170)
rule(y + 178)
draw("Payment Transaction ID: 2hG8pQ7sK3nXyZ1Lm4Vw", 36, y + 192); draw("Date & Time: 12/10/2025, 14:32:11 hrs", 36, y + 203)
draw("Invoice Value: 1,299.00", 36, y + 214); draw("Mode of Payment: Credit Card", 36, y + 225)
rule(y + 236)
draw("*ASSPL-Amazon Seller Services Pvt. Ltd., ARIPL-Amazon Retail India Pvt. Ltd. (only where Amazon Retail India Pvt. Ltd. fulfillment center is co-located)", 36, y + 250, size: 6.5)
draw("Customers desirous of availing input GST credit are requested to create a Business account and purchase on Amazon.in/business from Business eligible offers", 36, y + 259, size: 6.5)
draw("Please note that this invoice is not a demand for payment", 36, y + 268, size: 6.5)
draw("Page 1 of 1", 0, 820, size: 7.5, right: 559)
ctx.endPage(); ctx.closePDF(); print("wrote", out.path)
