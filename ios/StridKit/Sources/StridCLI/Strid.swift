import ArgumentParser
import Foundation
import StridDocuments
import StridKit

@main
struct Strid: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "strid",
        abstract: "Detect and redact PII from text documents. Runs fully on-device.",
        subcommands: [Redact.self, Restore.self, Detect.self, Eval.self, Entities.self]
    )
}

// MARK: - Shared options

struct DetectionOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "Confidence threshold (0.0-1.0).")
    var threshold: Double = 0.5

    @Option(
        name: [.customShort("e"), .customLong("entity")],
        help: "Entity type to detect (repeatable). Default: all. See `strid entities`."
    )
    var entities: [String] = []

    func makeEngine() throws -> StridEngine {
        guard (0.0...1.0).contains(threshold) else {
            throw ValidationError("Threshold must be between 0.0 and 1.0.")
        }
        var allowed: Set<PIIEntityType>? = nil
        if !entities.isEmpty {
            var set = Set<PIIEntityType>()
            for raw in entities {
                guard let type = PIIEntityType(rawValue: raw.uppercased()) else {
                    throw ValidationError("Unknown entity type '\(raw)'. Run `strid entities` to list valid types.")
                }
                set.insert(type)
            }
            allowed = set
        }
        return StridEngine(threshold: threshold, entities: allowed)
    }
}

struct DocumentFlags: ParsableArguments {
    @Option(name: [.short, .long], help: "Password for encrypted PDFs.")
    var password: String?

    @Flag(name: .long, help: "Re-apply the input PDF's password to the output (default: output is unencrypted).")
    var keepEncryption = false

    @Flag(name: .long, help: "Trust the PDF text layer even when it looks broken (skip OCR fallback).")
    var noOcrFallback = false

    @Flag(name: .long, help: "Reversible redaction: stable tokens like [PERSON_1], labels on boxes, and an encrypted vault sidecar.")
    var reversible = false

    @Option(name: [.short, .long], help: "Vault key (passphrase) for --reversible / restore. Generated and printed if omitted.")
    var key: String?

    /// Resolves the vault key, generating one when reversible mode is on and none was given.
    mutating func resolveKey() -> String? {
        guard reversible else { return nil }
        if let key, !key.isEmpty { return key }
        let generated = Vault.generatePassphrase()
        key = generated
        Stderr.print("Vault key (keep this; it is not stored anywhere): \(generated)")
        return generated
    }

    var options: DocumentOptions {
        DocumentOptions(password: password, keepEncryption: keepEncryption, ocrFallback: !noOcrFallback,
                        vaultKey: reversible ? key : nil)
    }
}

struct InputFile: ParsableArguments {
    @Argument(help: "Path to the input text file. Use '-' to read from stdin.", completion: .file())
    var inputFile: String

    /// Format of the input file by extension; `nil` for stdin or unknown extensions (treated as text).
    var documentKind: DocumentKind? {
        inputFile == "-" ? nil : DocumentKind.detect(url: URL(fileURLWithPath: inputFile))
    }

    /// Reads the input, or `nil` if the file is empty/whitespace.
    func readText(options: DocumentOptions = DocumentOptions()) throws -> String? {
        let text: String
        if inputFile == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let s = String(data: data, encoding: .utf8) else {
                throw ValidationError("stdin is not valid UTF-8.")
            }
            text = s
        } else {
            let url = URL(fileURLWithPath: inputFile)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("File not found: \(inputFile)")
            }
            // PDF, images and DOCX are extracted (OCR where needed); everything else is read as UTF-8.
            if let kind = documentKind, kind != .text {
                text = try DocumentText.extract(from: url, options: options)
            } else {
                text = try String(contentsOf: url, encoding: .utf8)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}

// MARK: - redact

struct Redact: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Redact PII from a text file.")

    @OptionGroup var input: InputFile
    @OptionGroup var detection: DetectionOptions
    @OptionGroup var document: DocumentFlags

    @Option(name: [.short, .long], help: "Output file (default: stdout).", completion: .file())
    var output: String?

    @Option(name: .long, help: "Redaction style: placeholder, asterisks, or a single fill character.")
    var style: String = "placeholder"

    @Flag(name: .long, help: "Show detected entities without redacting.")
    var dryRun = false

    mutating func run() throws {
        let engine = try detection.makeEngine()
        _ = document.resolveKey()
        if document.reversible && output == nil && (input.documentKind ?? .text) == .text {
            throw ValidationError("--reversible needs -o/--output so the vault can be written next to it.")
        }

        // Text files go through the document layer too when reversible (so the vault is written).
        if let kind = input.documentKind, kind != .text || document.reversible, input.inputFile != "-" {
            let inURL = URL(fileURLWithPath: input.inputFile)
            let outURL = output.map { URL(fileURLWithPath: $0) }
            if dryRun {
                // Reuse the real pipeline into a scratch file, report, and discard.
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(inURL.pathExtension)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let (_, report) = try DocumentRedactor.redact(input: inURL, output: tmp, engine: engine, options: document.options)
                Self.printReport(report, kind: kind)
                return
            }
            let (written, report) = try DocumentRedactor.redact(
                input: inURL, output: outURL, engine: engine, style: try parseStyle(style), options: document.options)
            Self.printReport(report, kind: kind)
            Stderr.print("Redacted \(kind.rawValue) written to \(written.path)")
            if let v = report.vaultURL {
                Stderr.print("Vault written to \(v.path)  (restore with: strid restore \(written.lastPathComponent) --key <key>)")
            }
            return
        }

        guard let text = try input.readText(options: document.options) else {
            Stderr.print("Warning: input is empty")
            return
        }

        if dryRun {
            let findings = Finding.from(engine.detect(in: text), in: text)
            guard !findings.isEmpty else {
                print("No PII detected.")
                return
            }
            print(Table.findings(findings, context: nil))
            print("\n\(findings.count) entities found.")
            return
        }

        let redacted = engine.redact(text, style: try parseStyle(style))
        if let output {
            try redacted.write(toFile: output, atomically: true, encoding: .utf8)
            Stderr.print("Redacted output written to \(output)")
        } else {
            FileHandle.standardOutput.write(Data(redacted.utf8))
        }
    }

    static func printReport(_ report: RedactionReport, kind: DocumentKind) {
        let rows = report.countsByType
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .map { [$0.key.rawValue, String($0.value)] }
        Stderr.print(Table.render(
            title: "\(kind.rawValue.uppercased()): \(report.pages) page(s), \(report.entities.count) entities redacted",
            header: ["Entity Type", "Count"], rows: rows))
        for w in report.warnings { Stderr.print("Note: " + w) }
    }

    private func parseStyle(_ raw: String) throws -> RedactionStyle {
        switch raw.lowercased() {
        case "placeholder": return .placeholder
        case "asterisks", "asterisk", "stars": return .asterisks
        default:
            guard raw.count == 1, let ch = raw.first else {
                throw ValidationError("Unknown style '\(raw)'. Use placeholder, asterisks, or a single character.")
            }
            return .charFill(ch)
        }
    }
}

// MARK: - restore

struct Restore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Reverse a --reversible redaction using its vault and key.")

    @Argument(help: "The redacted file. Its vault is expected at <file>.strid unless --vault is given.", completion: .file())
    var redacted: String

    @Option(name: .long, help: "Vault file path.", completion: .file())
    var vault: String?

    @Option(name: [.short, .long], help: "Vault key (passphrase).")
    var key: String

    @Option(name: [.short, .long], help: "Output path (default: <source>_restored.<ext> next to the redacted file).", completion: .file())
    var output: String?

    func run() throws {
        let out = try DocumentRedactor.restore(
            redacted: URL(fileURLWithPath: redacted),
            vault: vault.map { URL(fileURLWithPath: $0) },
            key: key,
            output: output.map { URL(fileURLWithPath: $0) })
        Stderr.print("Restored to \(out.path)")
    }
}

// MARK: - detect

struct Detect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Detect and report PII in a text file without modifying it."
    )

    @OptionGroup var input: InputFile
    @OptionGroup var detection: DetectionOptions
    @OptionGroup var document: DocumentFlags

    @Flag(name: .long, help: "Output results as JSON.")
    var json = false

    @Flag(name: [.short, .long], help: "Show surrounding text for each match.")
    var context = false

    func run() throws {
        guard let text = try input.readText(options: document.options) else {
            Stderr.print("Warning: input is empty")
            return
        }
        let engine = try detection.makeEngine()
        let findings = Finding.from(engine.detect(in: text), in: text)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(findings)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        guard !findings.isEmpty else {
            print("No PII detected.")
            return
        }

        var counts: [String: Int] = [:]
        for f in findings { counts[f.entityType, default: 0] += 1 }
        let summaryRows = counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { [$0.key, String($0.value)] }
            + [["Total", String(findings.count)]]
        print(Table.render(title: "PII Summary", header: ["Entity Type", "Count"], rows: summaryRows))
        print()
        print(Table.findings(findings, context: context ? text : nil))
    }
}

// MARK: - eval

/// Scores the detector against a directory of documents with ground truth.
///
/// Layout: for each `<name>.<ext>` (txt, pdf, png, docx ...) a sibling `<name>.expected.json`:
///   { "entities": [ { "type": "PERSON", "text": "Rahul Sharma" }, ... ],
///     "not":      [ { "text": "IFSC" }, ... ] }           // optional: strings that must NOT be redacted
/// An expected entity is a hit when a detected entity of the same type overlaps its text (either contains
/// the other, case-insensitive). Types are matched loosely across PHONE/IN_PHONE and IN_TXN_REF/IN_BANK_ACCOUNT.
struct Eval: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Score detection against a ground-truth corpus.")

    @Argument(help: "Directory containing documents and .expected.json files.", completion: .directory)
    var corpus: String

    @OptionGroup var detection: DetectionOptions
    @OptionGroup var document: DocumentFlags

    @Flag(name: .long, help: "Print every miss and false positive.")
    var verbose = false

    static let equivalent: [Set<String>] = [
        ["PHONE", "IN_PHONE"], ["IN_TXN_REF", "IN_BANK_ACCOUNT", "IN_CUSTOMER_ID", "IN_MICR"],
        ["LOCATION", "IN_PIN_CODE"],
    ]
    static func sameType(_ a: String, _ b: String) -> Bool {
        a == b || equivalent.contains { $0.contains(a) && $0.contains(b) }
    }

    struct Expected: Decodable {
        struct E: Decodable { let type: String?; let text: String }
        let entities: [E]
        let not: [E]?
    }

    func run() throws {
        let engine = try detection.makeEngine()
        let dir = URL(fileURLWithPath: corpus)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasSuffix(".expected.json") && DocumentKind.detect(url: $0) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw ValidationError("No documents found in \(corpus)") }

        var tp = 0, fn = 0, fp = 0, forbiddenHits = 0
        var perType: [String: (tp: Int, fn: Int)] = [:]
        var docs = 0

        for file in files {
            let expURL = file.deletingPathExtension().appendingPathExtension("expected.json")
            guard let data = try? Data(contentsOf: expURL),
                  let expected = try? JSONDecoder().decode(Expected.self, from: data) else { continue }
            docs += 1
            let text = try DocumentText.extract(from: file, options: document.options)
            let found = engine.detect(in: text)

            for e in expected.entities {
                let hit = found.contains { f in
                    (e.type == nil || Self.sameType(e.type!, f.type.rawValue)) && Self.overlaps(f.text, e.text)
                }
                let key = e.type ?? "ANY"
                if hit {
                    tp += 1; perType[key, default: (0, 0)].tp += 1
                } else {
                    fn += 1; perType[key, default: (0, 0)].fn += 1
                    let wrongType = found.first { Self.overlaps($0.text, e.text) }.map { " (found as \($0.type.rawValue))" } ?? ""
                    if verbose { print("MISS  \(file.lastPathComponent): \(key) \"\(e.text)\"\(wrongType)") }
                }
            }
            // Extras: detections that touch no expected entity at all (a doc may repeat an entity; that is not an extra).
            for f in found where !expected.entities.contains(where: { Self.overlaps(f.text, $0.text) }) {
                fp += 1
                if verbose { print("EXTRA \(file.lastPathComponent): \(f.type.rawValue) \"\(f.text)\"") }
            }
            for n in expected.not ?? [] {
                if found.contains(where: { Self.overlaps($0.text, n.text) }) {
                    forbiddenHits += 1
                    print("OVER  \(file.lastPathComponent): redacted forbidden \"\(n.text)\"")
                }
            }
        }

        func f1(_ tp: Int, _ fp: Int, _ fn: Int) -> (p: Double, r: Double, f: Double) {
            let p = tp + fp == 0 ? 1 : Double(tp) / Double(tp + fp)
            let r = tp + fn == 0 ? 1 : Double(tp) / Double(tp + fn)
            return (p, r, p + r == 0 ? 0 : 2 * p * r / (p + r))
        }
        let rows = perType.sorted { $0.key < $1.key }.map { k, v -> [String] in
            let r = v.tp + v.fn == 0 ? 1 : Double(v.tp) / Double(v.tp + v.fn)
            return [k, String(v.tp), String(v.fn), String(format: "%.2f", r)]
        }
        print(Table.render(title: "Recall by type (\(docs) documents)", header: ["Type", "Hit", "Miss", "Recall"], rows: rows))
        let o = f1(tp, fp, fn)
        print(Table.render(title: "Overall", header: ["Metric", "Value"], rows: [
            ["Expected entities", String(tp + fn)], ["Found (matched)", String(tp)],
            ["Missed", String(fn)], ["Extra detections", String(fp)], ["Forbidden redactions", String(forbiddenHits)],
            ["Precision (approx)", String(format: "%.3f", o.p)], ["Recall", String(format: "%.3f", o.r)],
            ["F1", String(format: "%.3f", o.f)],
        ]))
        // Recall is what matters for redaction: fail the command when anything expected was missed.
        if fn > 0 || forbiddenHits > 0 { throw ExitCode(2) }
    }

    static func overlaps(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let y = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if x.contains(y) || y.contains(x) { return true }
        // OCR tolerance: identifiers of equal length that differ in a single character still count.
        let dx = x.filter(\.isNumber), dy = y.filter(\.isNumber)
        guard dx.count >= 8, dx.count == dy.count else { return false }
        return zip(dx, dy).filter { $0 != $1 }.count <= 1
    }
}

// MARK: - entities

struct Entities: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List all supported PII entity types.")

    func run() {
        let rows = PIIEntityType.allCases
            .sorted { $0.rawValue < $1.rawValue }
            .map { [$0.rawValue, $0.displayName] }
        print(Table.render(title: "Supported Entity Types", header: ["Entity", "Description"], rows: rows))
    }
}

// MARK: - Output helpers

/// A detected entity with UTF-16 offsets, matching the Python CLI's JSON shape.
struct Finding: Encodable {
    let entityType: String
    let text: String
    let start: Int
    let end: Int
    let score: Double

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type", text, start, end, score
    }

    static func from(_ entities: [PIIEntity], in source: String) -> [Finding] {
        entities
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map { e in
                Finding(
                    entityType: e.type.rawValue,
                    text: e.text,
                    start: source.distance(from: source.startIndex, to: e.range.lowerBound),
                    end: source.distance(from: source.startIndex, to: e.range.upperBound),
                    score: (e.score * 100).rounded() / 100
                )
            }
    }
}

enum Stderr {
    static func print(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}

enum Table {
    static func findings(_ findings: [Finding], context source: String?) -> String {
        var header = ["#", "Type", "Text", "Score", "Position"]
        if source != nil { header.append("Context") }
        let rows = findings.enumerated().map { i, f -> [String] in
            var row = [String(i + 1), f.entityType, f.text, String(f.score), "\(f.start):\(f.end)"]
            if let source {
                let lo = source.index(source.startIndex, offsetBy: max(0, f.start - 30))
                let hi = source.index(source.startIndex, offsetBy: min(source.count, f.end + 30))
                let snippet = source[lo..<hi]
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                row.append("...\(snippet)...")
            }
            return row
        }
        return render(title: "Detected PII Entities", header: header, rows: rows)
    }

    static func render(title: String, header: [String], rows: [[String]]) -> String {
        let all = [header] + rows
        let widths = (0..<header.count).map { col in all.map { $0[col].count }.max() ?? 0 }
        func line(_ cells: [String]) -> String {
            "| " + zip(cells, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
                .joined(separator: " | ") + " |"
        }
        let sep = "+" + widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "+") + "+"
        var out = [title, sep, line(header), sep]
        out += rows.map(line)
        out.append(sep)
        return out.joined(separator: "\n")
    }
}
