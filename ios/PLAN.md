# Strid iOS App — Implementation Plan

The first open source iOS app for on-device document PII redaction.

## Current State

### Done
- **StridKit** Swift package — fully functional, 18 tests passing
  - `StridEngine` — main API: `detect(in:)` and `redact(_:style:)`
  - `NLPRecognizer` — Apple NaturalLanguage NER (names, locations, orgs)
  - `DataDetectorRecognizer` — NSDataDetector (email, phone, URL, address)
  - `RegexRecognizer` — reusable regex + context scoring engine
  - `IndianBankingRecognizers` — 14 recognizers (PAN, Aadhaar, IFSC, UPI, bank account, MICR, customer ID, branch code, txn ref, DOB, credit card, IP, phone, PIN code)
  - `Redactor` — placeholder, asterisk, and char-fill redaction styles
  - Overlap deduplication (highest score wins)
- **StridApp** — basic SwiftUI shell
  - 3-tab UI: Input → Detected → Redacted
  - File import via `.fileImporter`
  - Paste from clipboard
  - Share/copy redacted output

### Not Yet Built
Everything below.

---

## Phase 1: Core App (MVP)

Ship a working app that can import a text file, detect PII, and export redacted output.

### 1.1 Xcode Project Setup
- [ ] Create Xcode project (`StridApp`, iOS 17+, SwiftUI lifecycle)
- [ ] Add StridKit as local package dependency
- [ ] Configure app icons and launch screen
- [ ] Add `NSCameraUsageDescription` for document scanner
- [ ] Add file type associations (UTIs) for .txt, .csv

### 1.2 Document Import
- [ ] **Files app** — already wired via `.fileImporter` (txt, csv)
- [ ] **Camera scan** — integrate `VNDocumentCameraViewController` via UIKit representable
- [ ] **Photo library** — import image → OCR via Vision framework
- [ ] **Paste** — already wired via `UIPasteboard`
- [ ] **Share extension** — receive files from other apps (can defer to Phase 2)

### 1.3 OCR Pipeline
- [ ] Create `OCRService` using Vision framework's `VNRecognizeTextRequest`
- [ ] Support `.accurate` recognition level for best results
- [ ] Handle multi-page scans (array of images → concatenated text)
- [ ] Language hint: English + Hindi (for mixed-language statements)
- [ ] Return text with page/region metadata for PDF annotation later

### 1.4 Detection UI
- [ ] Summary view — entity type counts in a grid/list
- [ ] Detail view — scrollable list of findings with:
  - Color-coded type badges
  - Matched text (truncated if long)
  - Confidence score as percentage
  - Tap to highlight in source text
- [ ] Source text preview with PII spans highlighted (yellow background)
- [ ] Toggle to show/hide specific entity types

### 1.5 Redaction UI
- [ ] Preview redacted text with placeholders styled differently from normal text
- [ ] Redaction style picker: placeholder (`<PERSON>`) / asterisks / block character
- [ ] Before/after toggle or split view
- [ ] Copy to clipboard button
- [ ] Share sheet (AirDrop, save to Files, email, Messages)
- [ ] Save as new file to Files app

### 1.6 Settings
- [ ] Confidence threshold slider (0.0–1.0, default 0.5)
- [ ] Entity type toggles (enable/disable specific types)
- [ ] Redaction style preference
- [ ] About / version / GitHub link

---

## Phase 2: PDF Support

The big differentiator — most bank statements are PDFs.

### 2.1 PDF Text Extraction
- [ ] Use PDFKit `PDFDocument` to extract text per page
- [ ] Fallback to Vision OCR if PDF is image-based (scanned)
- [ ] Detect whether PDF is text-based or image-based

### 2.2 PDF Redaction
- [ ] Use PDFKit annotations to draw black rectangles over PII
- [ ] Map detected entity character ranges back to PDF coordinates
- [ ] `PDFAnnotation` with `.widget` or custom drawing
- [ ] Flatten annotations so they can't be removed (burn-in)
- [ ] Export redacted PDF via `PDFDocument.write(to:)`

### 2.3 PDF Preview
- [ ] `PDFView` for displaying original and redacted side by side
- [ ] Highlight PII regions with colored overlays before redaction
- [ ] Page navigation

---

## Phase 3: Polish & Ship

### 3.1 UX
- [ ] Onboarding flow (3 screens: import → detect → redact)
- [ ] Empty states with illustrations
- [ ] Processing indicator with entity count live-updating
- [ ] Haptic feedback on redaction complete
- [ ] Dark mode (primary) + light mode support
- [ ] iPad layout (sidebar + detail)

### 3.2 Performance
- [ ] Process large documents on background thread (already using `Task.detached`)
- [ ] Chunked processing for very large files (>1MB)
- [ ] Cache engine initialization (NLP tagger is expensive to create)
- [ ] Memory profiling for large PDFs

### 3.3 Testing
- [ ] Unit tests for each recognizer with Indian banking samples
- [ ] UI tests for import → detect → redact flow
- [ ] Snapshot tests for redacted output consistency
- [ ] Test with real bank statements from:
  - HDFC, SBI, ICICI, Axis, Kotak, PNB
  - Different formats (text, CSV, PDF)

### 3.4 Distribution
- [ ] App Store listing (screenshots, description, keywords)
- [ ] Privacy policy (easy — "we collect nothing")
- [ ] App Store review prep (demo content, no real PII in screenshots)
- [ ] TestFlight beta
- [ ] Open source repo setup (LICENSE, CONTRIBUTING.md)

---

## Phase 4: Future

Not committed, but worth tracking.

- [ ] **Hindi NER** — Apple NaturalLanguage supports Hindi; enable for mixed-language docs
- [ ] **Batch processing** — redact multiple files at once
- [ ] **Custom recognizers UI** — let users add their own regex patterns in-app
- [ ] **Redaction templates** — save entity type selections per document type (bank stmt, medical, tax)
- [ ] **macOS app** — StridKit already supports macOS; add a native Mac UI
- [ ] **Watch/Widget** — quick-scan shortcut from home screen
- [ ] **Document history** — local-only log of processed documents (no content stored)
- [ ] **Reversible redaction** — encrypt PII with a key instead of deleting (for authorized recovery)

---

## Architecture

```
StridApp/
├── App/
│   ├── StridApp.swift              # Entry point
│   └── AppState.swift              # Observable app state
├── Views/
│   ├── ContentView.swift           # Tab container
│   ├── ImportView.swift            # File picker, camera, paste
│   ├── DetectionView.swift         # Summary + detail list
│   ├── RedactionView.swift         # Redacted output + share
│   ├── SettingsView.swift          # Threshold, entity toggles
│   └── Components/
│       ├── EntityBadge.swift       # Color-coded type pill
│       ├── HighlightedTextView.swift  # Source text with PII highlighted
│       └── DocumentScannerView.swift  # VNDocumentCamera wrapper
├── Services/
│   ├── OCRService.swift            # Vision framework OCR
│   ├── PDFService.swift            # PDFKit extract + redact
│   └── DocumentStore.swift         # File I/O helpers
└── Resources/
    ├── Assets.xcassets
    └── LaunchScreen.storyboard

StridKit/  (Swift Package — already built)
├── Sources/StridKit/
│   ├── Models.swift
│   ├── StridEngine.swift
│   ├── Redactor.swift
│   └── Recognizers/
│       ├── Recognizer.swift
│       ├── NLPRecognizer.swift
│       ├── DataDetectorRecognizer.swift
│       ├── RegexRecognizer.swift
│       └── IndianBankingRecognizers.swift
└── Tests/StridKitTests/
```

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Min iOS version | 17 | VisionKit improvements, modern SwiftUI APIs |
| UI framework | SwiftUI | Faster development, less code, declarative |
| NER engine | Apple NaturalLanguage | Ships with OS, no model download, good enough |
| PDF redaction | PDFKit annotations | Native, no dependencies, supports flatten |
| OCR | Vision framework | On-device, fast, supports 18 languages |
| State management | `@Observable` | iOS 17+, simpler than Combine |
| Async | Swift concurrency | `async/await` + `Task` for background processing |
| Distribution | App Store + open source | Maximum reach + trust through transparency |
