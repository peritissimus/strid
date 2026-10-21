
## Swift CLI (`strid`)

A native CLI built on StridKit. Same commands as the Python tool, no Python or spaCy needed.

Input format is preserved on output: PDF in, PDF out (text-layer and scanned pages, true rasterised redaction), PNG/JPEG/HEIC in, same image out with black boxes located by on-device OCR, DOCX/RTF in, same out with formatting kept, and plain text/CSV/Markdown via string replacement. The same `StridDocuments` module powers the iOS and macOS apps.

```sh
scripts/install-cli.sh        # builds release and installs `strid` on your PATH
strid detect statement.txt    # summary + table
strid detect statement.txt --json     # machine-readable
strid redact statement.txt -o out.txt # placeholders like <IN_PAN>
strid redact statement.pdf                # writes statement_redacted.pdf
strid redact scan.png -o scan_clean.png
strid detect statement.docx --json        # extracts text, OCRs if needed
cat statement.txt | strid redact - --style asterisks
strid entities                        # list supported types
```

Options: `-t/--threshold`, `-e/--entity TYPE` (repeatable), `--dry-run`, `--style placeholder|asterisks|<char>`, `-c/--context`.

Locked PDFs: pass `-p/--password`. The output is unencrypted by default so it can be shared; add `--keep-encryption` to re-apply the same password. Copy/print restrictions are carried over. Digitally signed PDFs are flattened, so the output is unsigned and the CLI says so. Pages whose text layer is unusable (broken font encodings) fall back to OCR automatically; `--no-ocr-fallback` disables that.

### Reversible redaction

```sh
strid redact statement.pdf -o shared.pdf --reversible            # prints a generated key
strid redact statement.pdf -o shared.pdf --reversible --key "my passphrase"
strid restore shared.pdf --key "my passphrase"                    # writes statement_restored.pdf
```

In reversible mode every distinct value becomes a stable token (`[PERSON_1]`, `[IN_PAN_1]`), the token is printed inside each black box, and an encrypted vault is written next to the output as `<output>.strid`. The vault is AES-GCM sealed with a key derived from the passphrase (HKDF-SHA256, random salt); nothing in it is readable without the key. For PDFs and images the vault also carries the original bytes, so restore returns a byte-identical file. For text and DOCX it stores only the token map and restore reverses the substitutions. The key is never written anywhere by Strid: lose it and the vault is unrecoverable by design.

### Evaluation

`ios/StridKit/Eval/` holds a ground-truth corpus: each document has a sibling `<name>.expected.json` listing the PII that must be caught and strings that must not be touched.

```sh
strid eval ios/StridKit/Eval --verbose   # exit 2 if anything expected was missed
```

Recall is the metric that matters for a redaction tool, so the command fails on any miss. Add real-world (anonymised) documents here before changing recognizers.
