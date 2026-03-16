"""CLI interface for strid."""

import json
import sys
from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from strid.engine import DEFAULT_ENTITIES, StridEngine

app = typer.Typer(
    name="strid",
    help="Detect and redact PII from text documents.",
    no_args_is_help=True,
)
console = Console()
err_console = Console(stderr=True)


@app.command()
def redact(
    input_file: Path = typer.Argument(..., help="Path to the input text file"),
    output: Path = typer.Option(None, "-o", "--output", help="Output file (default: stdout)"),
    threshold: float = typer.Option(0.5, "-t", "--threshold", help="Confidence threshold (0.0-1.0)"),
    language: str = typer.Option("en", "-l", "--language", help="Text language code"),
    entities: list[str] = typer.Option(None, "-e", "--entity", help="Entity types to detect (can repeat)"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Show detected entities without redacting"),
) -> None:
    """Redact PII from a text file."""
    if not input_file.exists():
        err_console.print(f"[red]Error:[/red] File not found: {input_file}")
        raise typer.Exit(1)

    text = input_file.read_text(encoding="utf-8")
    if not text.strip():
        err_console.print("[yellow]Warning:[/yellow] Input file is empty")
        raise typer.Exit(0)

    engine = StridEngine(entities=entities or None, threshold=threshold)

    if dry_run:
        findings = engine.highlight(text, language)
        if not findings:
            console.print("[green]No PII detected.[/green]")
            raise typer.Exit(0)

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
            err_console.print(f"[green]Redacted output written to {output}[/green]")
        else:
            sys.stdout.write(redacted)


@app.command()
def detect(
    input_file: Path = typer.Argument(..., help="Path to the input text file"),
    threshold: float = typer.Option(0.5, "-t", "--threshold", help="Confidence threshold (0.0-1.0)"),
    language: str = typer.Option("en", "-l", "--language", help="Text language code"),
    entities: list[str] = typer.Option(None, "-e", "--entity", help="Entity types to detect (can repeat)"),
    output_json: bool = typer.Option(False, "--json", help="Output results as JSON"),
    show_context: bool = typer.Option(False, "-c", "--context", help="Show surrounding text for each match"),
) -> None:
    """Detect and report PII in a text file without modifying it."""
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
        sys.stdout.write(json.dumps(findings, indent=2) + "\n")
        return

    # Summary by entity type
    counts: dict[str, int] = {}
    for f in findings:
        counts[f["entity_type"]] = counts.get(f["entity_type"], 0) + 1

    summary = Table(title="PII Summary")
    summary.add_column("Entity Type", style="cyan")
    summary.add_column("Count", justify="right", style="bold yellow")
    for etype, count in sorted(counts.items(), key=lambda x: -x[1]):
        summary.add_row(etype, str(count))
    summary.add_section()
    summary.add_row("[bold]Total[/bold]", f"[bold]{len(findings)}[/bold]")
    console.print(summary)
    console.print()

    # Detailed findings
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
            ctx_start = max(0, f["start"] - 30)
            ctx_end = min(len(text), f["end"] + 30)
            snippet = text[ctx_start : ctx_end].replace("\n", " ").strip()
            row.append(f"...{snippet}...")
        detail.add_row(*row)

    console.print(detail)


@app.command(name="entities")
def list_entities() -> None:
    """List all supported PII entity types."""
    table = Table(title="Supported Entity Types")
    table.add_column("Entity", style="cyan")
    table.add_column("Default", style="green")
    for entity in sorted(DEFAULT_ENTITIES):
        table.add_row(entity, "yes")
    console.print(table)
