//
// Barcodes.swift
// StridDocuments
//
// QR codes and barcodes on identity documents carry the printed data in machine-readable form:
// the Aadhaar QR holds the holder's name, date of birth, gender and full address, a PAN card's
// QR the PAN and name, a cheque's barcode the MICR line. Blacking out the printed fields while
// leaving the code intact leaks everything. So every detected code is boxed, whatever it encodes.
// The payload is never decoded or read here; only the bounding box is used.
//
import CoreGraphics
import ImageIO
import PDFKit
import Foundation
import StridKit
import Vision

public enum Barcodes {
    /// Pixel rectangles (origin top-left) of every barcode or 2D code Vision finds in `image`.
    ///
    /// All symbologies Vision supports are requested. Detection failures (unsupported image,
    /// Vision error) return an empty list rather than throwing: a missing code is reported by the
    /// absence of a BARCODE entity, never by failing the whole document.
    static func detect(in image: CGImage) -> [CGRect] {
        // The decoder does not need a 216 dpi page: a code worth boxing is at least 9% of the
        // width (see `minEdgeFraction`), which is still 120+ px across at the decode width, and
        // codes too small or too worn to decode are the texture detector's job anyway. Vision's
        // time grows with pixel count, so the page is downsampled first.
        var rects = vision(in: downsampled(image, maxWidth: decodeWidth), reference: image)
        // Vision only reports codes it can decode. A large, worn or low-resolution QR (the
        // Aadhaar back carries a version-30+ code with ~3 px modules on a phone photo) is not
        // decodable but is still readable by a better scanner, so a texture-based detector adds
        // every dense square of modules Vision did not report.
        for r in denseRegions(in: image) where !rects.contains(where: { $0.intersects(r) }) {
            rects.append(r)
        }
        return rects
    }

    /// Vision's decoder-backed detection.
    public static func vision(in image: CGImage, reference: CGImage? = nil) -> [CGRect] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        let ref = reference ?? image
        let size = CGSize(width: ref.width, height: ref.height)
        return (request.results ?? []).map { OCRPage.denormalise($0.boundingBox, in: size) }
    }

    /// Widest image handed to the decoder.
    static let decodeWidth = 1400

    /// `image` scaled down to at most `maxWidth` pixels wide, or itself when already narrower.
    static func downsampled(_ image: CGImage, maxWidth: Int) -> CGImage {
        guard image.width > maxWidth else { return image }
        let s = Double(maxWidth) / Double(image.width)
        let w = maxWidth, h = max(1, Int(Double(image.height) * s))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    // MARK: - Texture detector

    /// Working width for the texture analysis; the image is downsampled to at most this.
    static let analysisWidth = Int(ProcessInfo.processInfo.environment["STRID_CODES_WIDTH"] ?? "") ?? 1000
    /// Tile edge in analysis pixels. 16 px spans several modules of any code worth boxing (a
    /// crisp 5 px-module QR or a blurred 2 px-module Aadhaar code) so the per-tile statistics are
    /// stable; 8 px tiles sat inside single modules of crisp codes and missed them.
    static let tile = 16
    /// Qualifying tile: this share of pixels dark ...
    static let darkRange: ClosedRange<Double> = 0.28...0.78
    /// Share of pixels below the page-wide ink threshold: codes are ink-heavy, text is paper-heavy.
    static let inkRange: ClosedRange<Double> = 0.32...0.92
    /// ... and at least this many black/white transitions per pixel pair, in both directions.
    /// Body text crosses the horizontal threshold but is much sparser (10–25% dark) and has blank
    /// leading between lines, so it fails the dark-fraction test; photographs are dark enough but
    /// smooth, so they fail the transition tests.
    static let minTransitions = 0.12
    /// Minimum grey-level range inside a tile for it to count as printed texture at all.
    static let minContrast = 72
    /// Horizontal and vertical transition rates must be within this ratio of each other: a code is
    /// isotropic, a line of text is not (strokes run vertically, so horizontal transitions dominate).
    static let isotropy = 0.6
    /// A code must cover at least this many qualifying tiles (~20×20 px at analysis scale) ...
    static let minTiles = 16
    /// ... fill this much of its bounding box, and be roughly square.
    static let minFill = 0.55
    /// 2D codes are square; a phone photo skews them a little, a logo or a photo rarely fits.
    static let aspectRange: ClosedRange<Double> = 0.7...1.4
    /// Shortest edge as a share of the analysed width. A code that carries personal data (Aadhaar,
    /// PAN, e-documents) is printed at 10–35% of the page or card width; bank and brand logos,
    /// which share the texture signature, are 4–8%.
    static let minEdgeFraction = 0.09
    static let minRawFill = 0.45

    /// Tuning aid: `STRID_CODES_ROI=x,y,w,h` (source pixels) collects per-tile statistics inside
    /// and outside that rectangle; `denseRegions` prints percentiles for both to stderr.
    static let debugROI: CGRect? = {
        let parts = (ProcessInfo.processInfo.environment["STRID_CODES_ROI"] ?? "").split(separator: ",").compactMap { Double($0) }
        return parts.count == 4 ? CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) : nil
    }()
    nonisolated(unsafe) static var debugStats: [[(Double, Double, Double)]] = [[], []]
    nonisolated(unsafe) static var debugPass: [[Bool]] = [[], []]

    /// One dilation followed by one erosion (8-neighbourhood) on the tile mask.
    static func close(_ mask: [Bool], cols: Int, rows: Int) -> [Bool] {
        func apply(_ m: [Bool], _ value: Bool) -> [Bool] {
            var out = m
            for y in 0..<rows {
                for x in 0..<cols where m[y * cols + x] != value {
                    var hit = false
                    for dy in -1...1 where !hit {
                        for dx in -1...1 {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0, ny >= 0, nx < cols, ny < rows, m[ny * cols + nx] == value { hit = true; break }
                        }
                    }
                    if hit { out[y * cols + x] = value }
                }
            }
            return out
        }
        return apply(apply(mask, true), false)
    }

    static func dumpDebugStats() {
        guard debugROI != nil else { return }
        for (label, rows) in zip(["inside", "outside"], debugStats) where !rows.isEmpty {
            func pct(_ values: [Double], _ p: Double) -> String { String(format: "%.2f", values.sorted()[Int(Double(values.count - 1) * p)]) }
            let d = rows.map { $0.0 }, h = rows.map { $0.1 }, v = rows.map { $0.2 }
            let pass = debugPass[label == "inside" ? 0 : 1]
            FileHandle.standardError.write("\(label) pass=\(pass.filter { $0 }.count)/\(pass.count) tiles=\(rows.count) dark p10/50/90=\(pct(d, 0.1))/\(pct(d, 0.5))/\(pct(d, 0.9)) th=\(pct(h, 0.1))/\(pct(h, 0.5))/\(pct(h, 0.9)) tv=\(pct(v, 0.1))/\(pct(v, 0.5))/\(pct(v, 0.9))\n".data(using: .utf8)!)
        }
        debugStats = [[], []]
        debugPass = [[], []]
    }

    /// Squares of dense, high-frequency black-and-white texture: QR, Aztec and DataMatrix codes.
    public static func denseRegions(in image: CGImage) -> [CGRect] {
        defer { dumpDebugStats() }
        guard image.width > 0, image.height > 0 else { return [] }
        let scale = min(1.0, Double(analysisWidth) / Double(image.width))
        let w = max(tile, Int(Double(image.width) * scale)), h = max(tile, Int(Double(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }
        ctx.interpolationQuality = .medium
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return [] }
        let stride = ctx.bytesPerRow
        let px = data.bindMemory(to: UInt8.self, capacity: stride * h)

        // Global threshold halfway between paper and ink (5th / 95th percentile). Under it a
        // code is at least a third ink; a line of text is mostly paper even inside its own tile.
        var hist = [Int](repeating: 0, count: 256)
        for y in 0..<h { for x in 0..<w { hist[Int(px[y * stride + x])] += 1 } }
        func percentile(_ p: Double) -> Int {
            var acc = 0
            for v in 0..<256 { acc += hist[v]; if Double(acc) >= p * Double(w * h) { return v } }
            return 255
        }
        let globalThreshold = UInt8((percentile(0.05) + percentile(0.95)) / 2)

        // Per-tile statistics with a local threshold: the midpoint between the tile's darkest and
        // lightest pixel. A global threshold fails on a dense code, whose blurred modules read as
        // mostly dark, and a local one makes "dark fraction" mean "balance of the two tones".
        // Tiles with little contrast (paper, photographs, JPEG noise) are rejected outright.
        let cols = w / tile, rows = h / tile
        guard cols > 0, rows > 0 else { return [] }
        var ok = [Bool](repeating: false, count: cols * rows)
        for ty in 0..<rows {
            for tx in 0..<cols {
                var lo: UInt8 = 255, hi: UInt8 = 0, sum = 0
                for y in 0..<tile {
                    let row = (ty * tile + y) * stride + tx * tile
                    for x in 0..<tile { let v = px[row + x]; sum += Int(v); if v < lo { lo = v }; if v > hi { hi = v } }
                }
                let range = Int(hi) - Int(lo)
                guard range >= minContrast else { continue }
                // Threshold at the tile mean: blurred modules then split evenly instead of all
                // reading as ink, which is what a min/max midpoint does on a dense code.
                let threshold = UInt8(sum / (tile * tile))
                var dark = 0, ink = 0, th = 0, tv = 0
                for y in 0..<tile {
                    let row = (ty * tile + y) * stride + tx * tile
                    var prev = px[row] < threshold
                    if prev { dark += 1 }
                    if px[row] < globalThreshold { ink += 1 }
                    for x in 1..<tile {
                        let d = px[row + x] < threshold
                        if d { dark += 1 }
                        if px[row + x] < globalThreshold { ink += 1 }
                        if d != prev { th += 1 }
                        prev = d
                    }
                }
                for x in 0..<tile {
                    var prev = px[(ty * tile) * stride + tx * tile + x] < threshold
                    for y in 1..<tile {
                        let d = px[(ty * tile + y) * stride + tx * tile + x] < threshold
                        if d != prev { tv += 1 }
                        prev = d
                    }
                }
                let n = Double(tile * tile), pairs = Double(tile * (tile - 1))
                let df = Double(dark) / n, fh = Double(th) / pairs, fv = Double(tv) / pairs
                let inkShare = Double(ink) / n
                let isotropic = min(fh, fv) >= isotropy * max(fh, fv)
                ok[ty * cols + tx] = darkRange.contains(df) && inkRange.contains(inkShare)
                    && fh >= minTransitions && fv >= minTransitions && isotropic
                if let roi = debugROI {
                    let cx = Double(tx * tile) / scale, cy = Double(ty * tile) / scale
                    let inside = roi.contains(CGPoint(x: cx, y: cy))
                    debugStats[inside ? 0 : 1].append((df, fh, fv))
                    debugPass[inside ? 0 : 1].append(ok[ty * cols + tx])
                }
            }
        }
        // Morphological closing on the tile grid: a code with a few blurred or specular tiles
        // stays one component, while isolated noise tiles do not grow into anything.
        let raw = ok
        ok = close(ok, cols: cols, rows: rows)

        // Connected components over qualifying tiles (4-neighbourhood).
        var seen = [Bool](repeating: false, count: cols * rows)
        var out: [CGRect] = []
        for start in 0..<(cols * rows) where ok[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var count = 0, rawCount = 0
            var minX = cols, maxX = -1, minY = rows, maxY = -1
            while let i = stack.popLast() {
                count += 1
                if raw[i] { rawCount += 1 }
                let x = i % cols, y = i / cols
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nx >= 0, ny >= 0, nx < cols, ny < rows else { continue }
                    let j = ny * cols + nx
                    if ok[j], !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            let fill = Double(count) / Double(bw * bh)
            let aspect = Double(bw) / Double(bh)
            // Closing may knit a sparse scatter of busy text tiles into a block; a code is dense
            // before closing too.
            let rawFill = Double(rawCount) / Double(bw * bh)
            guard count >= minTiles, fill >= minFill, rawFill >= minRawFill, aspectRange.contains(aspect),
                  Double(min(bw, bh) * tile) >= minEdgeFraction * Double(w) else { continue }
            // Back to source pixels, padded by one tile so the quiet zone and edge modules are covered.
            let pad = Double(tile)
            let r = CGRect(x: (Double(minX * tile) - pad) / scale, y: (Double(minY * tile) - pad) / scale,
                           width: (Double(bw * tile) + 2 * pad) / scale, height: (Double(bh * tile) + 2 * pad) / scale)
            out.append(r.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)))
        }
        return out
    }

    /// A `.barcode` entity anchored at the end of `text` for each rectangle, so reports and
    /// summaries count codes alongside text findings. The empty range keeps text redactors from
    /// touching anything.
    static func entities(for rects: [CGRect], in text: String) -> [PIIEntity] {
        rects.map { _ in PIIEntity(type: .barcode, text: "QR / barcode", range: text.endIndex..<text.endIndex, score: 1.0) }
    }
}

/// Page rasters for tooling (`strid codes`): a PDF rendered page by page, or a single image.
public enum PageImages {
    public static func load(_ url: URL, password: String? = nil) throws -> [CGImage] {
        if url.pathExtension.lowercased() == "pdf" {
            let doc = try PDFDocumentHandler.open(url, password: password)
            let handler = PDFDocumentHandler(scale: 3)
            return (0..<doc.pageCount).compactMap { i in doc.page(at: i).map { handler.render($0, box: $0.bounds(for: .mediaBox)) } }
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw DocumentRedactionError.unsupportedFormat(url.pathExtension)
        }
        return [img]
    }
}
