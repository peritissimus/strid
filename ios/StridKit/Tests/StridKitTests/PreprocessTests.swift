import XCTest
import CoreGraphics
@testable import StridDocuments

/// `Preprocess.upscaled` must enlarge small images by an integer factor, leave sharp ones alone,
/// and never change the aspect ratio (Vision's normalised coordinates depend on that).
final class PreprocessTests: XCTestCase {
    private func blank(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    func testSmallPhotoIsUpscaledToTarget() {
        let out = Preprocess.upscaled(blank(800, 1100))
        XCTAssertEqual(out.width, 2400)   // ceil(2400/800) = 3x
        XCTAssertEqual(out.height, 3300)
    }

    func testMidSizePhotoGetsTwoTimes() {
        let out = Preprocess.upscaled(blank(1300, 1800))
        XCTAssertEqual(out.width, 2600)
        XCTAssertEqual(out.height, 3600)
    }

    func testSharpImageIsUntouched() {
        let src = blank(1800, 2500)
        let out = Preprocess.upscaled(src)
        XCTAssertEqual(out.width, 1800)
        XCTAssertEqual(out.height, 2500)
    }

    func testScaleIsCapped() {
        let out = Preprocess.upscaled(blank(300, 400))
        XCTAssertEqual(out.width, 900)    // 3x cap, not 8x
        XCTAssertEqual(out.height, 1200)
    }
}
