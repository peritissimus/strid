"""CLI interface for strid.

Defines the ``strid`` command-line tool using Typer, with three subcommands:

* ``strid redact FILE``   -- write a redacted copy of FILE to stdout or ``-o``.
* ``strid detect FILE``   -- report what would be redacted, as tables or JSON.
* ``strid entities``      -- list the entity types scanned by default.

Output conventions:
    * Redacted text and JSON always go to **stdout** so they can be piped.
    * Human-oriented tables go to stdout via Rich.
    * Errors, warnings and status messages ("written to ...") go to
      **stderr** so they never pollute piped output.

Exit codes:
    * 0 on success, including "file is empty" and "no PII detected".
    * 1 when the input file does not exist.
"""

import json
import sys
from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from strid.engine import DEFAULT_ENTITIES, StridEngine

# Root Typer application. ``no_args_is_help`` makes a bare ``strid`` print the
# help text instead of erroring, which is friendlier for a small tool.
app = typer.Typer(
    name="strid",
    help="Detect and redact PII from text documents.",
    no_args_is_help=True,
)
# Two Rich consoles: ``console`` writes to stdout (tables, success notes) and
# ``err_console`` to stderr (errors/warnings/status) so ``strid redact f > out``
# captures only the redacted document.
console = Console()
err_console = Console(stderr=True)


@app.command()
def redact(
    # Positional, required (the ``...`` sentinel). Typer converts it to Path
    # but does not check existence; we do that ourselves for a nicer message.
    input_file: Path = typer.Argument(..., help="Path to the input text file"),
    # -o/--output: destination file. When omitted the redacted text is
    # streamed to stdout so the command composes with shell pipes.
    output: Path = typer.Option(None, "-o", "--output", help="Output file (default: stdout)"),
    # -t/--threshold: minimum Presidio confidence to keep a detection.
    # 0.5 is the engine default; lower it (e.g. 0.3) to let the weakly-scored
    # Indian numeric recognizers fire even without nearby context words.
    threshold: float = typer.Option(0.5, "-t", "--threshold", help="Confidence threshold (0.0-1.0)"),
    # -l/--language: forwarded to Presidio. Only "en" works with the default
    # spaCy model that ships with the engine.
    language: str = typer.Option("en", "-l", "--language", help="Text language code"),
    # -e/--entity: repeatable (``-e IN_PAN -e IN_AADHAAR``). Typer collects
    # the values into a list; None/empty means "use DEFAULT_ENTITIES".
    entities: list[str] = typer.Option(None, "-e", "--entity", help="Entity types to detect (can repeat)"),
    # --dry-run: show a table of what *would* be redacted and exit without
    # touching the text or writing ``--output``.
    dry_run: bool = typer.Option(False, "--dry-run", help="Show detected entities without redacting"),
) -> None:
    """Redact PII from a text file.

    Reads ``input_file`` as UTF-8, runs it through :class:`StridEngine`, and
    either prints a dry-run table of detections or emits the redacted text.

    Args:
        input_file: Path to the plain-text file to process.
        output: Optional path to write the redacted text to. If ``None`` the
            result is written to stdout.
        threshold: Confidence threshold (0.0-1.0) passed to the engine.
        language: Language code passed to Presidio.
        entities: Entity type names to detect; empty means defaults.
        dry_run: When True, only report detections, do not redact.

    Raises:
        typer.Exit: With code 1 if ``input_file`` does not exist; with code 0
            if the file is empty/whitespace-only or (in dry-run mode) nothing
            was detected. Typer turns these into process exit codes.
    """
    # Fail fast with a readable message instead of a Python traceback.
    if not input_file.exists():
        err_console.print(f"[red]Error:[/red] File not found: {input_file}")
        raise typer.Exit(1)

    text = input_file.read_text(encoding="utf-8")
    # An empty document is not an error: warn on stderr and exit cleanly so
    # batch scripts looping over many files do not abort.
    if not text.strip():
        err_console.print("[yellow]Warning:[/yellow] Input file is empty")
        raise typer.Exit(0)

    # ``entities or None`` normalises Typer's empty list to None so the engine
    # falls back to DEFAULT_ENTITIES. Engine construction loads spaCy, so it
    # is deferred until we know we actually have text to process.
    engine = StridEngine(entities=entities or None, threshold=threshold)

    if dry_run:
        # highlight() returns detections sorted by position with the matched
        # text included, which is exactly what the table needs.
        findings = engine.highlight(text, language)
        if not findings:
            console.print("[green]No PII detected.[/green]")
            raise typer.Exit(0)

        # One row per detection: type, the offending text (in red so it
        # stands out), the rounded score and the start:end character span.
        table = Table(title="Detected PII Entities")
        table.add_column("Type", style="cyan")
        table.add_column("Text", style="red")
        table.add_column("Score", justify="right", style="yellow")
        table.add_column("Position", style="dim")
        for f in findings:
            table.add_row(
                f["entity_type"],
                f["text"],
                str(f["score"]),
                f"{f['start']}:{f['end']}",
            )
        console.print(table)
        console.print(f"\n[bold]{len(findings)}[/bold] entities found.")
    else:
        redacted = engine.redact(text, language)
        if output:
            output.write_text(redacted, encoding="utf-8")
            # Status goes to stderr so stdout stays empty/clean when -o is used.
            err_console.print(f"[green]Redacted output written to {output}[/green]")
        else:
            # Raw sys.stdout.write (not Rich) so no markup interpretation,
            # wrapping or trailing newline is added to the document.
            sys.stdout.write(redacted)


@app.command()
def detect(
    # Same positional/threshold/language/entity options as ``redact``; see the
    # comments there. ``detect`` never modifies or writes the document.
    input_file: Path = typer.Argument(..., help="Path to the input text file"),
    threshold: float = typer.Option(0.5, "-t", "--threshold", help="Confidence threshold (0.0-1.0)"),
    language: str = typer.Option("en", "-l", "--language", help="Text language code"),
    entities: list[str] = typer.Option(None, "-e", "--entity", help="Entity types to detect (can repeat)"),
    # --json: machine-readable output (the highlight() dicts, pretty-printed)
    # instead of Rich tables. Useful for the eval scripts and for piping to jq.
    output_json: bool = typer.Option(False, "--json", help="Output results as JSON"),
    # -c/--context: add a column with ~30 characters either side of each match
    # so a reviewer can judge false positives without opening the file.
    show_context: bool = typer.Option(False, "-c", "--context", help="Show surrounding text for each match"),
) -> None:
    """Detect and report PII in a text file without modifying it.

    Produces either a JSON array of detections (``--json``) or two Rich
    tables: a per-entity-type summary with counts, followed by a detailed
    numbered list of every match.

    Args:
        input_file: Path to the plain-text file to scan.
        threshold: Confidence threshold (0.0-1.0) passed to the engine.
        language: Language code passed to Presidio.
        entities: Entity type names to detect; empty means defaults.
        output_json: Emit JSON to stdout instead of tables.
        show_context: Include a context snippet column in the detail table.

    Raises:
        typer.Exit: With code 1 if ``input_file`` does not exist; with code 0
            if the file is empty or nothing was detected.
    """
    if not input_file.exists():
        err_console.print(f"[red]Error:[/red] File not found: {input_file}")
        raise typer.Exit(1)

    text = input_file.read_text(encoding="utf-8")
    if not text.strip():
        err_console.print("[yellow]Warning:[/yellow] Input file is empty")
        raise typer.Exit(0)

    engine = StridEngine(entities=entities or None, threshold=threshold)
    findings = engine.highlight(text, language)

    if not findings:
        console.print("[green]No PII detected.[/green]")
        raise typer.Exit(0)

    if output_json:
        # highlight() already returns plain dicts of str/int/float, so they
        # serialise directly. Written raw to stdout to keep it pipe-friendly.
        sys.stdout.write(json.dumps(findings, indent=2) + "\n")
        return

    # Summary by entity type
    # Count detections per entity type with a plain dict (no Counter import
    # needed for something this small).
    counts: dict[str, int] = {}
    for f in findings:
        counts[f["entity_type"]] = counts.get(f["entity_type"], 0) + 1

    # Most frequent type first (sort key is negated count); ties keep dict
    # insertion order, i.e. the order the types were first seen in the text.
    summary = Table(title="PII Summary")
    summary.add_column("Entity Type", style="cyan")
    summary.add_column("Count", justify="right", style="bold yellow")
    for etype, count in sorted(counts.items(), key=lambda x: -x[1]):
        summary.add_row(etype, str(count))
    # add_section() draws a rule before the total row.
    summary.add_section()
    summary.add_row("[bold]Total[/bold]", f"[bold]{len(findings)}[/bold]")
    console.print(summary)
    console.print()

    # Detailed findings
    # Same columns as the redact --dry-run table plus a 1-based row number,
    # and an optional Context column when -c/--context was given.
    detail = Table(title="Detected PII Entities")
    detail.add_column("#", style="dim", justify="right")
    detail.add_column("Type", style="cyan")
    detail.add_column("Text", style="red")
    detail.add_column("Score", justify="right", style="yellow")
    detail.add_column("Position", style="dim")
    if show_context:
        detail.add_column("Context", style="dim")

    for i, f in enumerate(findings, 1):
        row = [
            str(i),
            f["entity_type"],
            f["text"],
            str(f["score"]),
            f"{f['start']}:{f['end']}",
        ]
        if show_context:
            # Take up to 30 characters before and after the match, clamped to
            # the document bounds. Newlines are flattened to spaces so the
            # snippet stays on one table line.
            ctx_start = max(0, f["start"] - 30)
            ctx_end = min(len(text), f["end"] + 30)
            snippet = text[ctx_start : ctx_end].replace("\n", " ").strip()
            row.append(f"...{snippet}...")
        detail.add_row(*row)

    console.print(detail)


# Exposed as ``strid entities`` (the Python name ``list_entities`` avoids
# shadowing the ``entities`` parameter name used by the other commands).
@app.command(name="entities")
def list_entities() -> None:
    """List all supported PII entity types.

    Prints the contents of :data:`DEFAULT_ENTITIES` alphabetically. Every
    listed entity is enabled by default, hence the constant "yes" column; the
    table exists so users know which names are valid for ``-e/--entity``.
    """
    table = Table(title="Supported Entity Types")
    table.add_column("Entity", style="cyan")
    table.add_column("Default", style="green")
    for entity in sorted(DEFAULT_ENTITIES):
        table.add_row(entity, "yes")
    console.print(table)
